// Do the citizen web home sections survive every desktop window and text size?
//
// ── Why this file exists ──────────────────────────────────────────────────
// The mobile audit (_responsive_matrix.dart + responsive_audit_test.dart) is
// deliberately mobile-only: it tops out at a 768px tablet and runs under a VM
// where `kIsWeb` is a compile-time false, so it takes the Android/iOS branch by
// construction. The desktop sweeps that exist — 1400/1440/1600 — belong almost
// entirely to the ADMIN console.
//
// The citizen web home page is assembled from the sections in
// core/widgets/Home/sections/Web/, and six of them had no test of any kind.
// That is the same blind spot that produced the live 900–979px feed overflow
// already pinned in newsfeed_web_responsive_test: a layout nothing could pump
// at the relevant width, so nothing noticed it was broken there.
//
// ── Why these particular widgets ──────────────────────────────────────────
// They are the ones reachable from a widget test. A section that branches on
// `kIsWeb` cannot be driven here at all — the VM always takes the false arm —
// which is why HomeQuickActionsSectionWeb is absent below and why the fix for
// that class of gap is to split the layout into a widget (as FeedRailLayout
// was) rather than to write a test that silently measures the mobile form.
//
// ── What counts as a failure ──────────────────────────────────────────────
// A RenderFlex overflow at any width or scale. Text scale matters as much as
// width and is the half that is easy to forget: 1.3 is Android's "Largest" and
// roughly a browser zoom, and it is what breaks a Row that only just fitted.
// Tests also run on Flutter's fallback font, whose every glyph is one em wide,
// so a string measures roughly twice what Roboto gives it — the probe is
// pessimistic on purpose, standing in for the Tagalog half of this bilingual
// app where the same label runs half again as long.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:govpulse/core/widgets/Home/sections/Web/home_contact_strip.dart';
import 'package:govpulse/core/widgets/Home/sections/Web/home_footer.dart';
import 'package:govpulse/core/widgets/Home/sections/Web/home_stats_bar.dart';

/// Browser windows people actually use, from a narrow split-screen pane up to
/// a 4K monitor. 1280 and 1440 are the common laptop widths; 820 is an iPad in
/// portrait and the narrowest window the two-panel layouts are asked to hold.
const _widths = <double>[820, 900, 1024, 1100, 1280, 1440, 1600, 1920, 2560];

/// 1.0 is the design size; 1.3 is Android's "Largest" and roughly a 130%
/// browser zoom.
const _scales = <double>[1.0, 1.15, 1.3];

/// Pumps [build] at [width] and [scale], returning every overflow Flutter
/// logged while laying it out.
///
/// The empty-tree pump first is load-bearing, and its absence is a classic
/// false pass: `pumpWidget` UPDATES a tree whose widget types match rather than
/// rebuilding it, so a sweep reusing one RenderFlex across nine widths gets an
/// overflow report only from the FIRST width that overflowed — a section broken
/// at every size looks broken at one and clean at eight.
Future<List<String>> _sweep(
  WidgetTester tester,
  double width,
  double scale,
  Widget Function() build,
) async {
  await tester.pumpWidget(const SizedBox.shrink());

  final errors = <String>[];
  final prev = FlutterError.onError;
  FlutterError.onError = (details) {
    final s = details.exceptionAsString();
    if (s.contains('overflowed') ||
        s.contains('RenderFlex') ||
        s.contains('Infinity')) {
      errors.add(s.split('\n').first);
    } else {
      prev?.call(details);
    }
  };

  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  try {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // Scrollable because these sections are tall and stack vertically on
          // the real page; without it every one of them reports a vertical
          // overflow that says nothing about the horizontal fit under test.
          body: SingleChildScrollView(child: build()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
  } finally {
    FlutterError.onError = prev;
  }
  return errors.toSet().toList();
}

/// Runs one section across the whole matrix and reports EVERY failing cell at
/// once, rather than dying on the first — a section broken at 1.3 scale only is
/// a different bug from one broken at every scale, and that is visible only if
/// the sweep finishes.
Future<void> _expectNoOverflow(
  WidgetTester tester,
  String name,
  Widget Function() build,
) async {
  final failures = <String>[];
  for (final width in _widths) {
    for (final scale in _scales) {
      final errors = await _sweep(tester, width, scale, build);
      for (final e in errors) {
        failures.add('${width.toInt()}px @ ${scale}x — $e');
      }
    }
  }
  expect(
    failures,
    isEmpty,
    reason: '$name overflowed in ${failures.length} of '
        '${_widths.length * _scales.length} cells:\n${failures.join('\n')}',
  );
}

void main() {
  testWidgets('HomeStatsBar holds every desktop width and text size',
      (tester) async {
    // Four stat tiles in a Row under a 1280px cap. The cap is what makes the
    // ultra-wide cases interesting: above it the tiles stop growing, so the
    // risk moves to the NARROW end, where four tiles and their labels have to
    // share a 820px window.
    await _expectNoOverflow(tester, 'HomeStatsBar', () => const HomeStatsBar());
  });

  testWidgets('HomeContactStrip holds every desktop width and text size',
      (tester) async {
    await _expectNoOverflow(
        tester, 'HomeContactStrip', () => const HomeContactStrip());
  });

  testWidgets('HomeFooter holds every desktop width and text size',
      (tester) async {
    // Multi-column footer: a brand column plus link columns. The columns are
    // where a long label at 1.3x scale runs out of room.
    await _expectNoOverflow(tester, 'HomeFooter', () => const HomeFooter());
  });
}
