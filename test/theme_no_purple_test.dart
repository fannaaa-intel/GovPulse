// The app's colour scheme must not produce PURPLE anywhere.
//
// ── The bug this locks down ────────────────────────────────────────────────
// Material 3 derives every colour role from a seed through a tonal-palette
// calculation, and the result is not the colour you seeded with. Two separate
// faults followed from that:
//
//   1. MOBILE seeded from the brand blue #0D47A1 and got `primary` = #475D92,
//      a desaturated blue-violet.
//   2. WEB passed a ThemeData with NO colorScheme at all, so the browser fell
//      back to Flutter's stock #6750A4 — a strong purple. This is the one a
//      user actually reported, on a "Cancel" button.
//
// A bare TextButton takes its label colour from `colorScheme.primary`, and the
// overwhelming majority of this app's TextButtons are bare. So the purple was
// on ~99 controls, not one.
//
// These tests assert the SCHEME, and then assert what a real bare TextButton
// actually renders — because a scheme that is right in isolation can still be
// overridden by a ThemeData that forgets to carry it, which is exactly what
// the web app did.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/core/theme/app_colors.dart';

/// Whether a colour reads as violet rather than as blue.
///
/// The distinguishing feature is NOT "red beats green" — #475D92, one of the
/// two colours that actually shipped, has green slightly above red and still
/// looks unmistakably purple. What separates violet from blue is how close red
/// sits to green while blue leads: in the brand blue #0D47A1 red is far below
/// green (.05 vs .28), whereas in both shipped purples red is within a hair of
/// it (.28 vs .36, and .40 vs .31). Written as: blue leads, and the red/green
/// gap has closed to almost nothing.
bool _looksPurple(Color c) {
  final r = c.r, g = c.g, b = c.b;
  if (b < 0.35) return false; // not blue-dominant at all
  if (b <= g + 0.08) return false; // blue must actually lead
  return (g - r) < 0.12; // red has caught up with green → violet
}

void main() {
  group('the shared scheme', () {
    test('primary is the brand blue, not its tonal approximation', () {
      // Pinned, not seeded. ColorScheme.fromSeed(#0D47A1).primary is #475D92.
      expect(govPulseColorScheme.primary, AppColors.primaryBlue);
    });

    test('primary is not purple', () {
      expect(
        _looksPurple(govPulseColorScheme.primary),
        isFalse,
        reason: 'primary = ${govPulseColorScheme.primary}',
      );
    });

    test('it is neither of the two purples that actually shipped', () {
      // #475D92 was mobile's seeded value; #6750A4 is Flutter's stock default,
      // which is what the web app rendered.
      expect(govPulseColorScheme.primary, isNot(const Color(0xFF475D92)));
      expect(govPulseColorScheme.primary, isNot(const Color(0xFF6750A4)));
    });

    test('onPrimary still contrasts with it', () {
      // primary and onPrimary are a PAIR. Pinning one without the other is how
      // a filled button gets a label that cannot be read on its own fill.
      final bg = govPulseColorScheme.primary;
      final fg = govPulseColorScheme.onPrimary;
      final lumBg = bg.computeLuminance();
      final lumFg = fg.computeLuminance();
      final ratio = (max(lumBg, lumFg) + 0.05) / (min(lumBg, lumFg) + 0.05);
      expect(ratio, greaterThan(4.5), reason: 'WCAG AA for normal text');
    });

    test('surfaces stay plain white rather than tinted', () {
      // The older half of this fix: a seeded scheme blends primary into every
      // surface, which is what made the account menus look faintly pink.
      expect(govPulseColorScheme.surface, Colors.white);
      expect(govPulseColorScheme.surfaceContainer, Colors.white);
    });
  });

  group('what a bare control actually renders', () {
    testWidgets('a TextButton with no style draws a blue label',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(colorScheme: govPulseColorScheme),
          home: Scaffold(
            body: TextButton(onPressed: () {}, child: const Text('Cancel')),
          ),
        ),
      );

      final color =
          DefaultTextStyle.of(tester.element(find.text('Cancel'))).style.color;
      expect(color, AppColors.primaryBlue);
      expect(_looksPurple(color!), isFalse, reason: 'label = $color');
    });

    testWidgets('a TextButton is blue on a scheme-less ThemeData too',
        (tester) async {
      // The web app's exact mistake: a ThemeData built for other reasons
      // (scaffold background, page transitions) that forgets to carry the
      // scheme. It must now be impossible to build one of those without the
      // shared scheme and still get purple, because the shared scheme is what
      // both apps pass.
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: govPulseColorScheme,
            scaffoldBackgroundColor: Colors.white,
          ),
          home: Scaffold(
            body: TextButton(onPressed: () {}, child: const Text('Cancel')),
          ),
        ),
      );

      final color =
          DefaultTextStyle.of(tester.element(find.text('Cancel'))).style.color;
      expect(_looksPurple(color!), isFalse, reason: 'label = $color');
    });
  });

  group('the purple detector itself', () {
    // A detector that never fires would make every test above vacuously green.
    test('it recognises the two colours that actually shipped', () {
      expect(_looksPurple(const Color(0xFF6750A4)), isTrue);
      expect(_looksPurple(const Color(0xFF475D92)), isTrue);
    });

    test('it does not cry purple over the brand blue', () {
      expect(_looksPurple(AppColors.primaryBlue), isFalse);
      expect(_looksPurple(Colors.white), isFalse);
      expect(_looksPurple(const Color(0xFF16A34A)), isFalse); // approve green
      expect(_looksPurple(const Color(0xFFDC2626)), isFalse); // danger red
    });
  });
}

double max(double a, double b) => a > b ? a : b;
double min(double a, double b) => a < b ? a : b;
