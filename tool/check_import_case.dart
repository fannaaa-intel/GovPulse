#!/usr/bin/env dart
// ════════════════════════════════════════════════════════════════════════════
//  Import casing guard
//
//    dart run tool/check_import_case.dart
//
//  Fails the build when a Dart import spells a filename with different CASE
//  than the file actually has on disk.
//
//  ── WHY THIS EXISTS ───────────────────────────────────────────────────────
//  Windows and macOS resolve paths case-INsensitively; Linux does not. So an
//  import written `Chat_bubbles_model.dart` against a file named
//  `chat_bubbles_model.dart` compiles perfectly on a developer's machine, is
//  reported clean by `flutter analyze`, and then fails only on the Linux CI
//  box with an unresolved-import error at the compile step.
//
//  That is exactly what broke the Vercel web deploy on 2026-08-01: two files
//  in lib/core/widgets/Home/Chat-bubbles/ imported `Chat_bubbles_model.dart`.
//  Both were reachable from main.dart, so the whole web build aborted, while
//  `flutter build web --release` kept succeeding locally. The defect is
//  invisible to every local check by construction — hence a dedicated guard.
//
//  This repo is unusually exposed to it because several directories are
//  capitalised (Home/, Newsfeed/, Resets/, Chat-bubbles/, Chat-agent/,
//  Quick-action/, profileVerification/), so the eye has no reliable "everything
//  is lowercase" rule to fall back on.
//
//  ── WHAT IT DOES AND DOES NOT REPORT ──────────────────────────────────────
//  It reports ONLY case mismatches — an import whose target exists on disk
//  under a different spelling of the same name. It deliberately stays silent
//  about imports that resolve to nothing at all, because those are already a
//  hard error from `flutter analyze` on every platform, and duplicating that
//  check here would only add noise.
//
//  ── HOW IMPORTS ARE RESOLVED ──────────────────────────────────────────────
//  Relative imports are resolved the way the Dart front-end does it: against
//  the importing file's `package:` URI, NOT its file:// path. The difference
//  is load-bearing. `Uri.parse('package:govpulse/a/b/c.dart')` has the path
//  `govpulse/a/b/c.dart`, so `..` segments clamp at the package root instead of
//  climbing into the filesystem above lib/. Verified against the live SDK:
//
//    package:govpulse/features/home/emergency/emergency_screen.dart
//      + '../../../../core/theme/app_colors.dart'
//      -> package:govpulse/core/theme/app_colors.dart
//
//  Resolving that same pair as file paths yields <repo>/core/theme/... which
//  does not exist — an earlier version of this script did exactly that and
//  produced 16 phantom failures. If you change the resolution logic, re-check
//  that over-deep `../` imports still pass.
// ════════════════════════════════════════════════════════════════════════════

import 'dart:io';

/// Package name from pubspec.yaml, so the guard survives a rename.
String _packageName(Directory root) {
  final pubspec = File('${root.path}/pubspec.yaml');
  if (!pubspec.existsSync()) return 'govpulse';
  for (final line in pubspec.readAsLinesSync()) {
    final m = RegExp(r'^name:\s*(\S+)').firstMatch(line);
    if (m != null) return m.group(1)!;
  }
  return 'govpulse';
}

/// Matches `import '...'` / `export '...'`, single or double quoted.
final _importRe = RegExp(
  r"""^\s*(?:import|export)\s+(?:'([^']+)'|"([^"]+)")""",
  multiLine: true,
);

class _Problem {
  final String file;
  final int line;
  final String spelled;
  final String actual;
  const _Problem(this.file, this.line, this.spelled, this.actual);
}

void main(List<String> args) {
  final root = Directory(args.isEmpty ? '.' : args[0]);
  final pkg = _packageName(root);
  final libDir = Directory('${root.path}/lib');

  if (!libDir.existsSync()) {
    stderr.writeln('check_import_case: no lib/ under ${root.path}');
    exit(2);
  }

  // Exact-case inventory, keyed by path under lib/ (i.e. the package: path).
  final exact = <String>{};
  // Lowercased -> the one true spelling, for detecting case-only mismatches.
  final byLower = <String, String>{};

  for (final e in libDir.listSync(recursive: true)) {
    if (e is! File) continue;
    final rel = _rel(e.path, libDir.path);
    exact.add(rel);
    byLower[rel.toLowerCase()] = rel;
  }

  final problems = <_Problem>[];
  var imports = 0;
  var files = 0;

  // lib/ is scanned with full relative-import resolution. test/ is scanned too,
  // but only its `package:` imports are meaningful there, which the same code
  // path handles.
  for (final dir in ['lib', 'test']) {
    final d = Directory('${root.path}/$dir');
    if (!d.existsSync()) continue;

    for (final e in d.listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      files++;

      final source = e.readAsStringSync();
      // `package:<pkg>/<path under lib>` is the base only for files in lib/.
      final selfRel = _rel(e.path, '${root.path}/$dir');
      final base = dir == 'lib'
          ? Uri.parse('package:$pkg/$selfRel')
          : null;

      for (final m in _importRe.allMatches(source)) {
        final spelled = m.group(1) ?? m.group(2)!;
        if (spelled.startsWith('dart:')) continue;

        String? target;
        if (spelled.startsWith('package:$pkg/')) {
          target = spelled.substring('package:$pkg/'.length);
        } else if (spelled.startsWith('package:')) {
          continue; // third-party; pub owns its casing
        } else if (base != null) {
          final r = base.resolve(spelled);
          if (r.scheme != 'package' || !r.path.startsWith('$pkg/')) continue;
          target = r.path.substring('$pkg/'.length);
        } else {
          continue; // relative import inside test/ — not part of the package
        }

        imports++;
        if (exact.contains(target)) continue;

        // Not an exact hit. Only a CASE difference is this guard's business;
        // anything else is an unresolved import and analyze's problem.
        final actual = byLower[target.toLowerCase()];
        if (actual != null) {
          problems.add(
            _Problem(_rel(e.path, root.path), _lineOf(source, m.start),
                spelled, actual),
          );
        }
      }
    }
  }

  stdout.writeln(
      'check_import_case: $imports intra-package imports across $files files');

  if (problems.isEmpty) {
    stdout.writeln('PASS - every import matches the on-disk casing.');
    exit(0);
  }

  stdout.writeln('');
  stdout.writeln('FAIL - ${problems.length} import(s) differ from disk casing.');
  stdout.writeln('These compile on Windows/macOS and break on Linux CI.');
  stdout.writeln('');
  for (final p in problems) {
    stdout.writeln('  ${p.file}:${p.line}');
    stdout.writeln('    imports : ${p.spelled}');
    stdout.writeln('    on disk : lib/${p.actual}');
    stdout.writeln('');
  }
  exit(1);
}

String _rel(String path, String from) => path
    .replaceAll(r'\', '/')
    .replaceFirst('${from.replaceAll(r'\', '/')}/', '');

int _lineOf(String source, int offset) =>
    '\n'.allMatches(source.substring(0, offset)).length + 1;
