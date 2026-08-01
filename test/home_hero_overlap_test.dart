// The web hero puts a profile card over the bottom of the hero image. On a
// phone-width browser that card falls back to its tall STACKED layout, and the
// bug this pins is that a taller card rides UPWARD into the hero copy — hiding
// the "Report issues, get updates…" subtitle entirely.
//
// Reported from a real phone (Messenger in-app browser) on 2026-08-01: the
// subtitle was clipped to a sliver behind the card.
//
// The assertion is geometric rather than visual: the subtitle's rect must not
// intersect the card's rect. That is the actual invariant — "the copy is
// readable" — and it holds regardless of how either box is styled later.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/core/widgets/Home/home_enums.dart';
import 'package:govpulse/core/widgets/Home/sections/Web/home_hero_section.dart';

const _kSubtitle =
    'Report issues, get updates, and access\ngovernment services in Aparri.';
const _kTitleTail = 'together';

Future<void> _pump(WidgetTester tester, double width,
    {double textScale = 1.0}) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: HomeHeroSection(
            username: 'Mark',
            fullName: 'Mark Reduca',
            facePhotoUrl: null,
            facePhotoPath: null,
            verifStatus: VerifStatus.verified,
            profileLoading: false,
            onVerifyTap: () {},
            sidePadding: width >= 1100 ? 32 : 16,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  // Widths a phone browser actually reports, including the narrow viewport an
  // in-app browser (Messenger/Facebook) gives you.
  for (final w in <double>[320, 360, 390, 412, 430, 600, 900]) {
    testWidgets('hero copy is not covered by the profile card at ${w.toInt()}px',
        (tester) async {
      await _pump(tester, w);

      expect(tester.takeException(), isNull);

      final subtitle = find.text(_kSubtitle);
      expect(subtitle, findsOneWidget,
          reason: 'the hero subtitle should be rendered at ${w}px');

      // Measure the CARD ITSELF, not a text inside it. A text sits below the
      // card's top edge, so asserting against one passes even while the card's
      // avatar and name are sitting on top of the hero copy.
      final card = find.byKey(kHomeHeroProfileCardKey);
      expect(card, findsOneWidget,
          reason: 'the profile card should be rendered at ${w}px');

      final subRect = tester.getRect(subtitle);
      final cardRect = tester.getRect(card);

      expect(
        subRect.overlaps(cardRect),
        isFalse,
        reason: 'at ${w}px the profile card covers the hero subtitle '
            '(subtitle=$subRect, card=$cardRect)',
      );

      // The card must also sit BELOW the headline, not on top of it.
      final title = find.text(_kTitleTail, findRichText: true);
      if (title.evaluate().isNotEmpty) {
        expect(tester.getRect(title).bottom, lessThanOrEqualTo(cardRect.top),
            reason: 'at ${w}px the card rides up over the headline');
      }
    });
  }

  // Large system text is an accessibility setting, not an edge case, and it is
  // the case a FIXED hero height cannot survive: the copy needs more lines than
  // the band was drawn for. The hero grows instead, so the guarantee holds.
  for (final scale in <double>[1.3, 1.8, 2.4]) {
    testWidgets('hero copy survives ${scale}x system text at 390px',
        (tester) async {
      await _pump(tester, 390, textScale: scale);

      expect(tester.takeException(), isNull,
          reason: 'no overflow at ${scale}x text scale');

      final subtitle = find.text(_kSubtitle);
      final card = find.byKey(kHomeHeroProfileCardKey);
      expect(subtitle, findsOneWidget);
      expect(card, findsOneWidget);

      expect(
        tester.getRect(subtitle).overlaps(tester.getRect(card)),
        isFalse,
        reason: 'at ${scale}x the card covers the hero subtitle',
      );
    });
  }
}
