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
      final nameRect = tester.getRect(find.text('Mark Reduca'));
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

  // ── Touch target ────────────────────────────────────────────────────────
  //
  // The seal is now the ONLY route to the verification sentence — the strip
  // that used to state it outright is gone. So the thing you tap has to be
  // reachable by a thumb, not merely present.
  //
  // It wasn't: the padding around the glyph was proportional (`w * 0.012`),
  // which produced a 23-31dp target across the phone range, against the 44dp
  // floor Apple's HIG and Material's accessibility guidance both publish. The
  // comment beside it claimed the padding grew the area "to one"; the
  // arithmetic never got there.
  group('the seal is reachable by a thumb', () {
    for (final device in const <Device>[kSmallPhone, kModernPhone]) {
      testWidgets('${device.name}: the tap target clears 44dp', (tester) async {
        await pumpAt(
          tester,
          device,
          () => _card(status: VerifStatus.verified),
        );

        // The gesture area is the Tooltip's child box, not the glyph — the
        // icon stays visually small on purpose and the box around it is what
        // the finger actually hits.
        final target = tester.getSize(
          find
              .ancestor(
                of: find.byIcon(Icons.verified_rounded),
                matching: find.byType(SizedBox),
              )
              .first,
        );

        expect(
          target.width,
          greaterThanOrEqualTo(44.0),
          reason: 'a target the thumb misses is a sentence nobody can read',
        );
        expect(target.height, greaterThanOrEqualTo(44.0));
      });
    }
  });
}
