import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/auth/facebook_username_screen.dart';

import '_responsive_matrix.dart';

// The username picker, swept for overflow at every width it has to survive.
//
// ── Why it needs its own sweep now ──────────────────────────────────────────
// The screen is not new — it already carried three layouts (mobile, web
// two-panel above 1000px, web compact below). What IS new is that web can
// finally reach it: the OAuth redirect is a cold start, so the mobile flow's
// `await`-then-push never ran, and the citizen silently landed in the shell
// with a blank handle. Now the router holds them here.
//
// A layout nobody could open is a layout nobody had measured, and this one has
// a text field, a live availability check, an error line and two buttons —
// every ingredient of a column that overflows once the text gets longer.
//
// `pumpAt` runs on Flutter's fallback font, where every glyph is one em wide,
// so strings measure roughly DOUBLE what Roboto gives them. A layout that
// survives here has real headroom for the Tagalog half of this bilingual app
// and for a user on Android's largest font setting.
//
// kIsWeb is a compile-time false under `flutter test`, so this exercises the
// MOBILE arm — the one the shipped Android and iOS app takes, and the one that
// must not regress, since this commit shares the screen with web rather than
// forking it.
void main() {
  Widget buildPicker({String name = 'Juan Dela Cruz'}) {
    return MaterialApp(
      home: FacebookUsernameScreen(
        facebookName: name,
        onComplete: (_) async {},
        onCancel: () {},
      ),
    );
  }

  group('the picker holds at every phone size', () {
    for (final device in kAllPhones) {
      testWidgets('no overflow at $device', (tester) async {
        final errors = await pumpAt(tester, device, buildPicker);
        expect(errors, isEmpty, reason: errors.join('\n'));
      });
    }

    testWidgets('no overflow on a tablet', (tester) async {
      final errors = await pumpAt(tester, kTablet, buildPicker);
      expect(errors, isEmpty, reason: errors.join('\n'));
    });
  });

  group('large text does not break it', () {
    // Somebody who needs bigger text is exactly the person least able to
    // recover from a layout that clips its only button.
    for (final scale in [1.3, 1.6, 2.0]) {
      testWidgets('no overflow at 320px with ${scale}x text', (tester) async {
        final errors = await pumpAt(
          tester,
          kSmallPhone,
          buildPicker,
          textScale: scale,
        );
        expect(errors, isEmpty, reason: errors.join('\n'));
      });
    }
  });

  group('a long name does not break the pre-filled suggestion', () {
    // The suggestion is derived from the Facebook display name, which the app
    // does not control — it can be long, accented, or a single word.
    testWidgets('a very long name still lays out', (tester) async {
      final errors = await pumpAt(
        tester,
        kSmallPhone,
        () => buildPicker(
          name: 'Maria Cristina Dela Cruz Villanueva Bautista Santos',
        ),
      );
      expect(errors, isEmpty, reason: errors.join('\n'));
    });

    testWidgets('an empty name still lays out', (tester) async {
      final errors = await pumpAt(
        tester,
        kSmallPhone,
        () => buildPicker(name: ''),
      );
      expect(errors, isEmpty, reason: errors.join('\n'));
    });
  });

  group('what the citizen is asked', () {
    testWidgets('the prompt and the field are both present', (tester) async {
      await pumpAt(tester, kModernPhone, buildPicker);

      expect(find.textContaining('Almost there'), findsOneWidget);
      expect(find.byType(TextField), findsWidgets);
    });

    testWidgets('the Facebook name is pre-filled, sanitised', (tester) async {
      await pumpAt(tester, kModernPhone, buildPicker);

      // "Juan Dela Cruz" -> "juan_dela_cruz". Pinned because the suggestion is
      // the reason most citizens never have to type anything here.
      expect(find.text('juan_dela_cruz'), findsOneWidget);
    });
  });
}
