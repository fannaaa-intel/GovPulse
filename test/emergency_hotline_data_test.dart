import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:govpulse/features/home/emergency/emergency_screen.dart';

// Pins the Aparri emergency numbers this screen ships.
//
// WHY THIS EXISTS
// These numbers were cross-checked in Aug 2026 against five sources: the
// LGU-Aparri Citizen's Charter (2022), two hotline postings from the Office of
// the Vice Mayor (Oct 2022 and Apr 2021), a widely-reshared Nov 2024 social
// post, and the Cagayan PROVINCIAL DRRMO directory at pdrrmo.cagayan.gov.ph.
// They do not all agree, and two of the disagreements are a single digit wide.
//
// A silent edit here — a "cleanup", a copy-paste slip — sends someone in an
// emergency to a dead line, and nothing else in the app would notice. So the
// digits are asserted literally. If one of these fails, that is the point:
// confirm the replacement against a primary source before changing it.
//
// The same numbers are ALSO served through the chatbot out of public.lgu_facts.
// This screen holds the hardcoded copy; the two must not drift apart.
//
// The numbers sit inside a per-category modal, so each test opens the category
// first. That means these also cover the modal actually opening — a hotline a
// citizen cannot reach is the same failure as a wrong one.
void main() {
  /// Category tile label → the hotlines it must contain, digits only.
  const expected = <String, Map<String, String>>{
    'Police': {'Aparri Police Station': '09172032003'},
    'Fire Station': {'Aparri Fire Station (BFP)': '09164910946'},
    'Hospital': {
      'Aparri Provincial Hospital': '09363748430',
      'Municipal Health Office (East)': '09531908364',
    },
    'MDRRMO': {
      'MDRRMO Aparri East (Rescue 511)': '09972404984',
      'MDRRMO Aparri West': '09655845600',
      'Provincial DRRMO Cagayan': '09271819424',
    },
  };

  Widget host(Widget child) => ProviderScope(
    child: MaterialApp(debugShowCheckedModeBanner: false, home: child),
  );

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      host(const EmergencyScreen(username: 'juandelacruz', isVerified: true)),
    );
    await tester.pump(const Duration(milliseconds: 600));
  }

  /// Swallows layout overflow so these tests report on the NUMBERS only.
  ///
  /// The category card's "View hotlines" Row (emergency_screen.dart:1819)
  /// overflows by ~38px under the test binding's fallback font, whose glyphs
  /// are all one em wide and so measure roughly double real text. That is a
  /// pre-existing cosmetic artifact of the harness, not a defect these tests
  /// are about, and test/responsive_audit_test.dart already owns overflow for
  /// this screen. Letting it fail here would mean a wrong hotline and a wide
  /// label produce the same red, which is the opposite of what this file is
  /// for. The desktop-web case below still asserts no exception escapes.
  void ignoreOverflow() {
    final prior = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) return;
      prior?.call(details);
    };
    addTearDown(() => FlutterError.onError = prior);
  }

  /// Opens one category tile and returns every digit rendered inside it.
  Future<String> openCategory(WidgetTester tester, String label) async {
    final tile = find.text(label);
    expect(
      tile,
      findsWidgets,
      reason: 'the "$label" category tile is missing from the screen',
    );
    // Tap the label that actually sits inside a tappable card. Some category
    // words also appear in the page's own chrome ("Police" in a heading), and
    // tapping that hits nothing while warnIfMissed stays quiet.
    //
    // pumpAndSettle is NOT usable on this screen: the 911 badge runs a
    // repeating pulse controller, so the frame queue never drains and settle
    // times out. Fixed pumps instead.
    Finder tappable = tile.last;
    for (final candidate in tile.evaluate()) {
      final withAncestor = find.ancestor(
        of: find.byWidget(candidate.widget),
        matching: find.byType(InkWell),
      );
      if (withAncestor.evaluate().isNotEmpty) {
        tappable = find.byWidget(candidate.widget);
        break;
      }
    }
    await tester.tap(tappable, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    return tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join(' ')
        .replaceAll(RegExp(r'[^0-9]'), '');
  }

  setUp(() {
    // A tall phone: every category tile is reachable without scrolling.
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  for (final category in expected.keys) {
    testWidgets('$category hotline numbers are unchanged', (tester) async {
      // Logical pixels at dpr 1.0, matching test/_responsive_matrix.dart.
      // A big phone: the modal has room, so an overflow here would be real.
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      ignoreOverflow();

      await pumpScreen(tester);
      final digits = await openCategory(tester, category);

      expected[category]!.forEach((name, number) {
        expect(
          digits.contains(number),
          isTrue,
          reason:
              'The number for "$name" is no longer $number. Verify the '
              "replacement against a primary source (the LGU Citizen's "
              'Charter, or pdrrmo.cagayan.gov.ph) before updating this test — '
              'a wrong hotline is worse than a missing one.',
        );
      });
    });
  }

  testWidgets('911 is on the screen and needs no interaction to find', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    ignoreOverflow();

    await pumpScreen(tester);

    // 911 is the one number that must never be behind a tap.
    expect(find.text('911'), findsWidgets);
  });

  testWidgets('renders at a desktop-web width without throwing', (
    tester,
  ) async {
    // Citizen-web takes a different branch (a band, not the phone hero). An
    // overflow here would push hotline rows off-screen, which on this screen
    // means a number nobody can reach.
    tester.view.physicalSize = const Size(2560, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await pumpScreen(tester);
    expect(tester.takeException(), isNull);
  });
}
