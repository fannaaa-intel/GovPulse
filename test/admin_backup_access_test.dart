// REGRESSION GUARD — "Backup & Recovery" is an ADMIN-ONLY section.
//
// Restore writes to 38 tables with user triggers paused. A staff member or a
// citizen reaching it would be the most damaging authorization bug in the
// project, so the separation is asserted here rather than left to a code read.
//
// ── WHAT ACTUALLY PROTECTS THIS, AND WHY THE OBVIOUS TEST IS VACUOUS ──────
// The tempting test is "pump the staff console, expect no Backup item". That
// passes trivially and proves nothing: the staff console is a DIFFERENT widget
// with its own `_navFor()` list, so it could never show an admin rail item
// however broken the gate was. A green from that test would be noise.
//
// The real guarantees are structural, and that is what these cases assert:
//
//  1. The staff nav list does not contain a backup entry — asserted against
//     the staff console's own nav labels, not the admin's.
//  2. Nothing outside `lib/features/admin/` imports the backup page, provider
//     or dialogs. This is the property that keeps the page off every citizen,
//     guest and staff surface, and it is the one a careless later import would
//     break. A source-level assertion is the only way to catch that, because a
//     widget test cannot pump a page that has not been added yet.
//  3. The server gate is declared: `admin-backup` has `verify_jwt = true` in
//     config.toml. `authorizeCaller` reads the role claim WITHOUT verifying the
//     signature, so flipping that flag to false would let anyone forge an admin
//     claim. That is a one-line change with no visible symptom, which is
//     exactly what a guard test is for.
//
// ── NON-VACUOUS ───────────────────────────────────────────────────────────
// Verified by breaking each in turn:
//   · adding a 'Backup' _NavItem to staff `_navFor()` fails case 1;
//   · adding `import '.../admin_backup_page.dart';` to the staff console fails
//     case 2 (confirmed: the scan reports the offending file and line);
//   · setting `verify_jwt = false` under [functions.admin-backup] fails case 3.
//
// ── NO NETWORK, NO PUMP ───────────────────────────────────────────────────
// Nothing signs in and no widget is built. These are structural facts about
// the repo, so they are read from source — which also means the test cannot
// pass for the wrong reason (a silent exception during a pump, say).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Repo root, found by walking up from the test file rather than assuming the
/// working directory — `flutter test` and an IDE run it from different places.
Directory _repoRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    if (File('${dir.path}/pubspec.yaml').existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail('Could not locate the repo root (no pubspec.yaml found walking up).');
}

void main() {
  final root = _repoRoot();

  test('the staff console nav offers no backup section', () {
    final src = File('${root.path}/lib/features/staff/screens/staff_console_screen.dart')
        .readAsStringSync();

    // Scope the check to the nav builder, so an unrelated mention of the word
    // elsewhere in the file cannot make this pass or fail by accident.
    final navStart = src.indexOf('_navFor(');
    expect(navStart, greaterThan(-1),
        reason: 'staff console no longer has _navFor(); update this guard');
    final navEnd = src.indexOf('];', navStart);
    expect(navEnd, greaterThan(navStart));
    final navBody = src.substring(navStart, navEnd).toLowerCase();

    expect(navBody.contains('backup'), isFalse,
        reason: 'The staff console nav must never offer Backup & Recovery.');
    expect(navBody.contains('restore'), isFalse,
        reason: 'The staff console nav must never offer a restore entry.');
  });

  test('nothing outside lib/features/admin imports the backup feature', () {
    final offenders = <String>[];
    final needles = [
      'admin_backup_page',
      'admin_backup_provider',
      'backup_dialogs',
      'AdminBackupPage',
    ];

    for (final entity in Directory('${root.path}/lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      // Normalise separators so this behaves the same on Windows and POSIX.
      final rel = entity.path
          .substring(root.path.length + 1)
          .replaceAll(r'\', '/');
      if (rel.startsWith('lib/features/admin/')) continue;

      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final needle in needles) {
          if (lines[i].contains(needle)) {
            offenders.add('$rel:${i + 1} → ${lines[i].trim()}');
          }
        }
      }
    }

    expect(offenders, isEmpty,
        reason: 'The backup feature must stay inside lib/features/admin/. '
            'Reached from:\n${offenders.join('\n')}');
  });

  test('the admin-backup edge function keeps verify_jwt = true', () {
    final cfg = File('${root.path}/supabase/config.toml').readAsStringSync();

    final header = cfg.indexOf('[functions.admin-backup]');
    expect(header, greaterThan(-1),
        reason: 'config.toml has no [functions.admin-backup] section, so the '
            'function would deploy with default JWT handling.');

    // Read only this function's block, ending at the next TOML section header.
    //
    // Naive `indexOf('\n[')` is wrong here: this block's comments mention
    // `authorizeCaller()` and `[functions.*]`, and a '[' inside a comment
    // truncated the block to a single newline — which made the contains()
    // assertion pass vacuously. Scan line by line and skip comments instead.
    final after = cfg.substring(header + '[functions.admin-backup]'.length);
    final blockLines = <String>[];
    for (final line in after.split('\n')) {
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('#')) continue; // a comment, not a new section
      if (trimmed.startsWith('[')) break; // the next real section
      blockLines.add(line);
    }
    final block = blockLines.join('\n');

    // Guard the guard: if the block ever parses empty, the assertions below
    // would pass on nothing at all.
    expect(block.trim(), isNotEmpty,
        reason: 'Parsed an empty [functions.admin-backup] block — the block '
            'parser is broken, so the verify_jwt assertion would be vacuous.');

    expect(block.replaceAll(' ', ''), contains('verify_jwt=true'),
        reason: 'admin-backup MUST keep verify_jwt = true. authorizeCaller '
            'trusts the role claim without checking the signature, so this '
            'flag is the only thing stopping a forged admin token.');
    expect(block.replaceAll(' ', ''), isNot(contains('verify_jwt=false')));
  });
}
