// Drives the citizen web shell's two washed promo cards — the app-download card
// in the right sidebar and the verification card in the left rail — against the
// geometry they now share through WebPromoCardStyle.
//
// The per-state behaviour of the verification card lives in
// rail_verify_card_test.dart. What is checked HERE is the thing that has no
// single owner: that the two cards, in two different rails at two different
// widths, still agree. They used to agree only by transcription — the verify
// card carried a doc comment promising it was a copy of the download card's
// anatomy — and a promise in a comment is not a test.
//
// The real widths: 288 for the rail (`_kRailLabelledWidth`, inline and in the
// drawer) and 312 for the sidebar (`_kRightSidebarWidth` 340, less the 8/20
// padding the shell wraps it in).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/core/widgets/Home/home_enums.dart';
import 'package:govpulse/core/widgets/Home/sections/Web/home_app_download_card.dart';
import 'package:govpulse/core/widgets/Home/sections/Web/rail_verify_card.dart';
import 'package:govpulse/core/widgets/Home/sections/Web/web_promo_card_style.dart';

const double _kRailWidth = 288;
const double _kSidebarCardWidth = 312;

Future<void> _pump(WidgetTester tester, double width, Widget card) async {
  tester.view.physicalSize = const Size(1440, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(width: width, child: card),
        ),
      ),
    ),
  );
}

void main() {
  group('the download card lays out without overflow', () {
    // 312 is the real sidebar width; the rest guard the card if it is ever
    // reused somewhere narrower, including below the step where the artwork
    // has to get out of the copy's way.
    for (final w in [_kSidebarCardWidth, _kRailWidth, 264.0, 240.0, 220.0]) {
      testWidgets('at ${w.toInt()}px', (tester) async {
        await _pump(tester, w, const HomeAppDownloadCard());

        expect(tester.takeException(), isNull);
        expect(find.text('Stay connected\non the go!'), findsOneWidget);
        expect(find.text('Download App'), findsOneWidget);
      });
    }
  });

  testWidgets('the download card shows the stay-connected artwork', (
    tester,
  ) async {
    await _pump(tester, _kSidebarCardWidth, const HomeAppDownloadCard());
    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as AssetImage).assetName,
      'assets/images/stay-connected.webp',
    );
  });

  testWidgets('a narrow reuse drops the artwork rather than crushing the '
      'headline', (tester) async {
    await _pump(tester, 220, const HomeAppDownloadCard());
    expect(find.byType(Image), findsNothing);
    expect(find.text('Stay connected\non the go!'), findsOneWidget);
    expect(find.text('Download App'), findsOneWidget);
  });

  // The card is honest about having no listing yet: the button is live, and
  // tapping it says so rather than doing nothing. Guards `_download`'s null-URL
  // branch, which is the ONLY branch reachable until kGovPulseAppDownloadUrl is
  // filled in.
  testWidgets('with no listing configured the button explains itself', (
    tester,
  ) async {
    expect(kGovPulseAppDownloadUrl, isNull);

    await _pump(tester, _kSidebarCardWidth, const HomeAppDownloadCard());
    await tester.tap(find.text('Download App'));
    await tester.pump();

    expect(
      find.text('The GovPulse mobile app is coming soon.'),
      findsOneWidget,
    );
  });

  group('the two cards agree', () {
    testWidgets('same artwork box at their real widths', (tester) async {
      await _pump(tester, _kSidebarCardWidth, const HomeAppDownloadCard());
      final download = tester.getSize(find.byType(Image));

      await _pump(
        tester,
        _kRailWidth,
        RailVerifyCard(status: VerifStatus.verified, onVerify: () {}),
      );
      final verify = tester.getSize(find.byType(Image));

      // 288 and 312 deliberately land in the same band of
      // WebPromoCardStyle.artFor, so the rail and the sidebar show the same
      // size picture.
      expect(download, const Size(92, 92));
      expect(verify, download);
    });

    testWidgets('same button, filling each card', (tester) async {
      await _pump(tester, _kSidebarCardWidth, const HomeAppDownloadCard());
      final downloadBtn = find.byType(FilledButton);
      final downloadStyle = tester.widget<FilledButton>(downloadBtn).style;
      final downloadWidth = tester.getSize(downloadBtn).width;

      await _pump(
        tester,
        _kRailWidth,
        // `none` is the only state that renders a button.
        RailVerifyCard(status: VerifStatus.none, onVerify: () {}),
      );
      final verifyBtn = find.byType(FilledButton);
      final verifyStyle = tester.widget<FilledButton>(verifyBtn).style;
      final verifyWidth = tester.getSize(verifyBtn).width;

      // Compared as a STYLE, not as a measured height. The two labels are
      // different lengths, and under the test font — Ahem, which is about twice
      // the width of a real one — "Verify Your Account" wraps at the rail's
      // width while "Download App" does not, so the rendered heights differ by
      // a line for reasons that have nothing to do with this code. The shared
      // style is the actual claim: same green, same 14px vertical padding, same
      // radius, same label weight.
      expect(verifyStyle, downloadStyle);
      expect(downloadStyle, WebPromoCardStyle.button());

      // Both fill their card, so the widths differ only by the cards' widths.
      // Measured as an INSET from the content box rather than against an
      // absolute number: a FilledButton lands a couple of px inside the
      // double.infinity box it is given (its own visual-density adjustment),
      // and the claim here is that the two cards inset identically, not what
      // Material's constant happens to be this version.
      final downloadInset = (_kSidebarCardWidth - 36) - downloadWidth;
      final verifyInset = (_kRailWidth - 36) - verifyWidth;
      expect(downloadInset, verifyInset);
      expect(downloadInset, lessThan(4));
    });
  });

  group('WebPromoCardStyle.artFor', () {
    test('holds both real rail widths in one band', () {
      expect(WebPromoCardStyle.artFor(_kRailWidth), 92);
      expect(WebPromoCardStyle.artFor(_kSidebarCardWidth), 92);
    });

    test('drops the artwork only once the copy would be crushed', () {
      expect(WebPromoCardStyle.artFor(236), 72);
      expect(WebPromoCardStyle.artFor(235), 0);
    });

    test('never leaves the copy column under 126px', () {
      // The invariant the ladder exists to hold. Walked across every width the
      // card can plausibly be handed.
      for (double w = 160; w <= 400; w++) {
        final art = WebPromoCardStyle.artFor(w);
        if (art == 0) continue;
        final copy =
            w -
            (2 * WebPromoCardStyle.padFor(w)) -
            art -
            WebPromoCardStyle.artGap;
        expect(copy, greaterThanOrEqualTo(126), reason: 'at ${w}px');
      }
    });
  });
}
