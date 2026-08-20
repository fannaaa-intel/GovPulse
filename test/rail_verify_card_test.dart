// Drives the citizen web rail's verification card through its three states.
//
// The card is a landscape mockup folded into a 288px rail, so its whole risk is
// width: the headline block and the illustration share a row, and the pill,
// rule, footnote and button span the full width around them. Two width-
// dependent decisions carry that (the padding tightens, and the illustration
// drops out entirely rather than crushing the copy), and both were computed by
// hand against the real rail width — so they are checked here at the widths the
// shell actually hands the card.
//
// 288 is `_kRailLabelledWidth`: the inline rail at >= 1024 AND the drawer below
// it. The narrower widths are the one case where the card gets less than it
// asks for — Flutter clamps a Drawer to the screen width, so a browser window
// narrower than 288 squeezes it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/core/widgets/Home/home_enums.dart';
import 'package:govpulse/core/widgets/Home/sections/Web/rail_verify_card.dart';

/// Pumps the card at a rail width of [width] and fails on any overflow.
///
/// The card is constrained by a [SizedBox], not by the screen: that is exactly
/// how the shell mounts it (a fixed-width rail inside a Row), and it is the
/// constraint its LayoutBuilder actually reads.
Future<void> _pumpAt(
  WidgetTester tester,
  double width,
  VerifStatus status, {
  VoidCallback? onVerify,
}) async {
  tester.view.physicalSize = const Size(1440, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: width,
            child: RailVerifyCard(status: status, onVerify: onVerify ?? () {}),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('lays out without overflow', () {
    for (final status in VerifStatus.values) {
      // 288: the rail and the drawer. 264/240: a clamped drawer. 220: below the
      // step where the illustration gets out of the copy's way.
      for (final w in [288.0, 264.0, 240.0, 220.0]) {
        testWidgets('${status.name} at ${w.toInt()}px', (tester) async {
          await _pumpAt(tester, w, status);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('each state gets its own artwork', () {
    const expected = {
      VerifStatus.verified: 'assets/images/verification/verifies-status.webp',
      VerifStatus.pending: 'assets/images/verification/Pending.webp',
      VerifStatus.none: 'assets/images/verification/Unverified.webp',
    };

    for (final entry in expected.entries) {
      testWidgets(entry.key.name, (tester) async {
        await _pumpAt(tester, 288, entry.key);
        final image = tester.widget<Image>(find.byType(Image));
        expect((image.image as AssetImage).assetName, entry.value);
      });
    }
  });

  testWidgets('the artwork box is identical in all three states', (
    tester,
  ) async {
    // The point of the one-build-method/skin split: the card must not change
    // size as a citizen's status advances. The illustration is the only fixed
    // box in the layout, so it is the thing that would drift first.
    final sizes = <VerifStatus, Size>{};
    for (final status in VerifStatus.values) {
      await _pumpAt(tester, 288, status);
      sizes[status] = tester.getSize(find.byType(Image));
    }

    expect(sizes[VerifStatus.verified], const Size(92, 92));
    expect(sizes[VerifStatus.pending], sizes[VerifStatus.verified]);
    expect(sizes[VerifStatus.none], sizes[VerifStatus.verified]);
  });

  testWidgets('a squeezed drawer drops the artwork rather than crushing the '
      'headline', (tester) async {
    await _pumpAt(tester, 220, VerifStatus.none);
    expect(find.byType(Image), findsNothing);
    expect(find.textContaining('Your account is'), findsOneWidget);
    expect(find.text('Verify Your Account'), findsOneWidget);
  });

  group('only the unverified state offers a control', () {
    testWidgets('none shows the button and fires the callback', (tester) async {
      var fired = 0;
      await _pumpAt(tester, 288, VerifStatus.none, onVerify: () => fired++);

      expect(find.text('Verify Your Account'), findsOneWidget);
      await tester.tap(find.text('Verify Your Account'));
      expect(fired, 1);
    });

    // Deliberate, and long-standing: `_startVerification` refuses a pending
    // account and the wizard rejects a second pending submission, so a button
    // in either of these states would be dead.
    for (final status in [VerifStatus.pending, VerifStatus.verified]) {
      testWidgets('${status.name} shows no button', (tester) async {
        await _pumpAt(tester, 288, status);
        expect(find.byType(FilledButton), findsNothing);
        expect(find.text('Verify Your Account'), findsNothing);
      });
    }
  });

  group('maybe() holds the slot empty until the profile lands', () {
    // VerifStatus falls back to `none`, so rendering on status alone would
    // flash the red "unverified" card at a verified citizen on every cold load.
    testWidgets('renders nothing while loading', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RailVerifyCard.maybe(
              profileLoaded: false,
              status: VerifStatus.none,
              onVerify: () {},
            ),
          ),
        ),
      );
      expect(find.byType(RailVerifyCard), findsNothing);
    });

    testWidgets('renders the card once loaded', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 288,
              child: RailVerifyCard.maybe(
                profileLoaded: true,
                status: VerifStatus.verified,
                onVerify: () {},
              ),
            ),
          ),
        ),
      );
      expect(find.byType(RailVerifyCard), findsOneWidget);
      expect(find.text('VERIFIED'), findsOneWidget);
    });
  });
}
