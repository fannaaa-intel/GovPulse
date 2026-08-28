// Layout + behaviour tests for the MOBILE home profile card's verified seal.
//
// The seal used to sit in a full-width strip BELOW the name, carrying the
// sentence "You're a verified Aparri citizen" as permanent text. It now sits
// inline after the name, and that sentence is revealed on tap (mobile) or
// hover (web/desktop) instead — bought so the quick actions below the card
// rise into view without a scroll.
//
// That move put the seal into a Row it shares with the name, which is the
// widest thing in the card. So the two things worth pinning are:
//
//   1. the row does not overflow at any phone size, in either orientation,
//      even at Android's Largest font scale — the strip's own history is a
//      warning here, its label having been one translation away from a
//      striped overflow (see the Flexible comments in the widget);
//   2. the sentence is genuinely reachable by touch, since a tooltip that
//      never opens on mobile would silently delete the information rather
//      than relocate it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/core/widgets/Home/home_enums.dart';
import 'package:govpulse/core/widgets/Home/sections/home_profile_card.dart';

import '_responsive_matrix.dart';

const _kSentence = "You're a verified Aparri citizen";

Widget _card({
  required VerifStatus status,
  String? fullName = 'Mark Reduca',
  String username = 'Mark',
}) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: HomeProfileCard(
        username: username,
        verifStatus: status,
        fullName: fullName,
        facePhotoUrl: null,
        profileLoading: false,
        notificationCount: 3,
        onNotificationTap: () {},
        onVerifyTap: () {},
      ),
    ),
  ),
);

void main() {
  group('verified seal placement', () {
    testWidgets('sits inline with the name, not in a strip below it', (
      tester,
    ) async {
      await pumpAt(tester, kModernPhone, () => _card(status: VerifStatus.verified));

      final seal = find.byIcon(Icons.verified_rounded);
      expect(seal, findsOneWidget);

      // Inline means "on the name's line". Vertical overlap with the name is
      // the assertion that actually distinguishes this from the old strip,
      // which cleared the name by the better part of a card.
      // 'Mark Reduca' does not fit beside the seal at this width, so the card
      // shows the first name — see the shortening group below. This test is
      // about PLACEMENT, so it finds whichever form rendered.
      final nameRect = tester.getRect(find.text('Mark'));
      final sealRect = tester.getRect(seal);
      expect(
        sealRect.left,
        greaterThan(nameRect.left),
        reason: 'seal should follow the name, not precede it',
      );
      expect(
        sealRect.center.dy,
        inInclusiveRange(nameRect.top, nameRect.bottom),
        reason: 'seal should share the name\'s line',
      );
    });

    testWidgets('the sentence is not permanently on screen', (tester) async {
      await pumpAt(tester, kModernPhone, () => _card(status: VerifStatus.verified));
      expect(
        find.text(_kSentence),
        findsNothing,
        reason: 'the strip is gone; the sentence should be revealed, not resident',
      );
    });

    testWidgets('no seal for pending or unverified citizens', (tester) async {
      for (final status in [VerifStatus.none, VerifStatus.pending]) {
        await pumpAt(tester, kModernPhone, () => _card(status: status));
        expect(
          find.byIcon(Icons.verified_rounded),
          findsNothing,
          reason: 'unverified citizens must not wear the seal ($status)',
        );
      }
    });
  });

  group('tap reveals the sentence', () {
    testWidgets('tapping the seal shows it, and it fades back out', (
      tester,
    ) async {
      await pumpAt(tester, kModernPhone, () => _card(status: VerifStatus.verified));

      await tester.tap(find.byIcon(Icons.verified_rounded));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.text(_kSentence),
        findsOneWidget,
        reason: 'a touch user has no hover; tap must open the tooltip',
      );

      // showDuration (3s) is handed to the framework as `touchDelay`, whose
      // timer starts at the tap and ends by reversing the fade. Pumps here are
      // INCREMENTS on the test clock, not absolute times: +1s leaves the
      // tooltip mid-life, and the +2s that follows carries it past the 3s mark
      // and through the fade-out.
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.text(_kSentence),
        findsOneWidget,
        reason: 'should still be readable a second in',
      );
      // The dismissal pump is deliberately generous. `pumpAt` has already
      // advanced the clock 600ms and leaves the card's shimmer running on a
      // repeating controller, so frames keep being scheduled and the fade-out
      // lands about a second later than a bare `pumpWidget` would put it.
      // Asserting "gone by 4s" tests the behaviour that matters — it dismisses
      // itself, no second tap needed — without pinning the frame it happens on.
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.text(_kSentence),
        findsNothing,
        reason: 'should dismiss itself without a second tap',
      );
    });
  });

  group('the name row survives the device matrix', () {
    for (final device in kAllPhones) {
      testWidgets('$device at 1.0x', (tester) async {
        final errors = await pumpAt(
          tester,
          device,
          () => _card(status: VerifStatus.verified),
        );
        expect(errors, isEmpty, reason: errors.join('\n'));
      });

      // Android's Largest. The matrix's fallback font already measures about
      // double Roboto, so this stacks a real-world worst case on top of an
      // already pessimistic probe.
      testWidgets('$device at 1.3x', (tester) async {
        final errors = await pumpAt(
          tester,
          device,
          () => _card(status: VerifStatus.verified),
          textScale: 1.3,
        );
        expect(errors, isEmpty, reason: errors.join('\n'));
      });
    }

    testWidgets('a very long name ellipsizes instead of evicting the seal', (
      tester,
    ) async {
      final errors = await pumpAt(
        tester,
        kSmallPhone,
        () => _card(
          status: VerifStatus.verified,
          fullName: 'Bonifacio Maximiliano Villanueva-Dimaculangan',
        ),
      );
      expect(errors, isEmpty, reason: errors.join('\n'));

      // The point of Flexible-not-Expanded: the name yields, the seal stays.
      final seal = find.byIcon(Icons.verified_rounded);
      expect(seal, findsOneWidget);
      final sealRect = tester.getRect(seal);
      expect(
        sealRect.right,
        lessThanOrEqualTo(kSmallPhone.size.width),
        reason: 'seal pushed off-screen by a long name',
      );
    });
  });

  // ── Name shortening, and the gap it exists to close ─────────────────────
  //
  // `Flexible` alone does not keep the seal beside the name: a Text that
  // ellipsizes still OCCUPIES its full allotted width — the glyphs stop at the
  // ellipsis but the box does not — so the seal was pushed out to the
  // truncation point and floated at the far right, visibly detached from the
  // word it certifies. "Chanzelyn Sa… ✓" put the seal a third of a card away.
  //
  // The row now measures the name and picks the longest form that fits: the
  // full name, else the FIRST name, else an ellipsis. Step two is the point —
  // an ellipsis is a failure state, and a person's first name is a legitimate
  // way to address them.
  group('a long name falls back to the first name', () {
    testWidgets('a name that does not fit shows the first name only', (
      tester,
    ) async {
      await pumpAt(
        tester,
        kModernPhone,
        () =>
            _card(status: VerifStatus.verified, fullName: 'Chanzelyn Salvador'),
      );

      expect(find.text('Chanzelyn'), findsOneWidget);
      expect(
        find.text('Chanzelyn Salvador'),
        findsNothing,
        reason: 'the full name did not fit; it should not be ellipsized',
      );
    });

    testWidgets('a short name keeps its full form', (tester) async {
      await pumpAt(
        tester,
        kModernPhone,
        () => _card(status: VerifStatus.verified, fullName: 'Ana Cruz'),
      );

      // Shortening is a fallback, not the default.
      expect(find.text('Ana Cruz'), findsOneWidget);
    });

    testWidgets('a single-word name is left alone', (tester) async {
      await pumpAt(
        tester,
        kModernPhone,
        () => _card(
          status: VerifStatus.verified,
          fullName: 'Bartholomewlongname',
        ),
      );

      // No first name to fall back TO, so the ellipsis is correct here — the
      // last rung of the ladder.
      expect(find.textContaining('Bartholomew'), findsOneWidget);
    });

    // The complaint that started this: dead space between the name and the
    // seal. Measured, not eyeballed — 2.6-3.4dp across the phone range, which
    // is the hairline Facebook and X set their verified marks at. A verified
    // mark reads as part of the NAME; any daylight makes it look like a
    // separate item sitting next to one.
    for (final probe in const <({String name, String shown})>[
      (name: 'Mark Reduca', shown: 'Mark'),
      (name: 'Chanzelyn Salvador', shown: 'Chanzelyn'),
      (name: 'Ana Cruz', shown: 'Ana Cruz'),
    ]) {
      testWidgets('no dead space after "${probe.shown}"', (tester) async {
        await pumpAt(
          tester,
          kModernPhone,
          () => _card(status: VerifStatus.verified, fullName: probe.name),
        );

        final nameRect = tester.getRect(find.text(probe.shown));
        final sealRect = tester.getRect(find.byIcon(Icons.verified_rounded));
        final gap = sealRect.left - nameRect.right;

        // The seal's 44dp touch box is LEFT-aligned around its glyph, so the
        // box's trailing space overhangs into the card's own padding instead
        // of wedging itself between the text and the mark. Only the row's
        // deliberate `width * 0.014` should separate them.
        expect(
          gap,
          lessThan(5.0),
          reason: 'dead space crept back in: ${gap.toStringAsFixed(1)}dp',
        );
        expect(gap, greaterThan(0.0), reason: 'the seal should not overlap');
      });
    }
  });

  // ── The handle line below the name ──────────────────────────────────────
  //
  // The seal's 44dp touch target used to SIZE the name row: a 44dp box against
  // ~26dp of text made the row 44dp tall, and the surplus pushed the "@handle"
  // line down. Measured 9.1dp of gap under a verified name against 1.6dp under
  // an unverified one — the same dead-space complaint as the seal itself, one
  // axis over.
  //
  // The target now overflows the row instead of sizing it, so both land in the
  // same place. Verified against unverified is the assertion that matters: it
  // cannot pass by accident.
  group('the handle sits the same distance under either name', () {
    for (final device in const <Device>[
      kSmallPhone,
      kPhone,
      kModernPhone,
      kBigPhone,
    ]) {
      testWidgets('${device.name}: verified matches unverified', (
        tester,
      ) async {
        Future<double> gapFor(VerifStatus status) async {
          await pumpAt(
            tester,
            device,
            () => _card(status: status, fullName: 'Ana Cruz'),
          );
          final name = tester.getRect(find.text('Ana Cruz'));
          final handle = tester.getRect(find.text('@Mark'));
          return handle.top - name.bottom;
        }

        final verified = await gapFor(VerifStatus.verified);
        final plain = await gapFor(VerifStatus.none);

        expect(
          verified,
          closeTo(plain, 0.5),
          reason:
              'the seal is inflating the name row again: '
              '${verified.toStringAsFixed(1)}dp vs ${plain.toStringAsFixed(1)}dp',
        );
        // And it is a hairline in absolute terms, not merely equal.
        expect(verified, lessThan(4.0));
      });
    }
  });

  // ── Touch target ────────────────────────────────────────────────────────
  //
  // The seal is the ONLY route to the verification sentence — the strip that
  // used to state it outright is gone. So the thing you tap has to be
  // reachable by a thumb, not merely present. The glyph is ~19dp against the
  // 44dp floor Apple's HIG and Material both publish.
  //
  // Asserted by TAPPING rather than by measuring a widget, and that is
  // deliberate: the target overflows its own box so the row is not stretched
  // (see the handle group above), which means no single widget's reported size
  // is the answer. What matters is whether a tap that lands short of the glyph
  // still opens the tooltip — which is exactly what a thumb aiming at a small
  // mark does.
  group('the seal is reachable by a thumb', () {
    for (final device in const <Device>[kSmallPhone, kModernPhone]) {
      testWidgets('${device.name}: a tap beside the glyph still opens it', (
        tester,
      ) async {
        await pumpAt(
          tester,
          device,
          () => _card(status: VerifStatus.verified),
        );

        final seal = tester.getRect(find.byIcon(Icons.verified_rounded));

        // 14dp right of the glyph's own edge: inside the target's 44dp WIDTH,
        // outside the glyph. Before the target existed this was a miss.
        await tester.tapAt(Offset(seal.right + 14, seal.center.dy));
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          find.text(_kSentence),
          findsOneWidget,
          reason: 'a target the thumb misses is a sentence nobody can read',
        );

        // Let the tooltip retire so the next case starts clean. Fixed pumps,
        // NOT pumpAndSettle: the card runs a repeating shimmer controller, so
        // there is never a frame with nothing scheduled and pumpAndSettle
        // times out rather than returning.
        await tester.pump(const Duration(seconds: 4));
        await tester.pump(const Duration(milliseconds: 500));
      });
    }
  });

}
