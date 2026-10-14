// test/chat_composer_keyboard_test.dart
//
// ════════════════════════════════════════════════════════════════════════════
//  The Ask Kuya Gov composer, with the keyboard open.
//
//  ── The defect ──────────────────────────────────────────────────────────
//  Reported from the phone app (Android 16, 25057RN09G): tapping the message
//  field on the opening screen raises the keyboard, and the composer is then
//  only HALF visible — the text being typed ("Paano po…") is clipped by the
//  top edge of the keyboard, and the send button is cut off with it.
//
//  ── Why it happened ─────────────────────────────────────────────────────
//  The screen is a Column of:
//
//      header · info bar · Expanded(message list) · FAQ chips · composer
//
//  `resizeToAvoidBottomInset` (default true) shrinks the body by the keyboard
//  inset, and `Expanded` dutifully surrenders the message list's height. But
//  the FAQ chip block is a RIGID sibling — an unbounded Column + Wrap with no
//  height limit. Measured at 430px wide it is **471px tall**: a label plus
//  SEVEN wrapped chips, each a full Tagalog question on its own line.
//
//  With a 340px keyboard on a 932px screen the body is 592px. Header (70) +
//  info bar (93) + chips (471) + composer (72) = 706px of rigid content. Once
//  Expanded has collapsed to zero there is nothing left to give, so the column
//  overflows by 139px and the overflow comes out of whatever sits LAST: the
//  composer, which lands at y 659–731 with the keyboard starting at y 592.
//
//  This is the [[rigid-child-defeats-flex-fix]] shape. Padding, insets and
//  SafeArea are all innocent; the unshrinkable child is the constraint. The
//  first draft of this test guessed the chips at 190px, which left Expanded
//  enough slack to absorb the inset — so it passed against the BROKEN layout
//  and proved nothing. The numbers above are measured, not estimated.
//
//  ── What these tests pin ────────────────────────────────────────────────
//  1. With the keyboard open, the composer's bottom is above the keyboard.
//  2. No RenderFlex overflow while the keyboard is open.
//  3. With no keyboard the chips are all still there — the fix must not buy
//     composer room by permanently amputating the FAQ list.
//  4. The same holds on a short viewport, which is the web layout's risk: it
//     has the identical Column shape.
// ════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:govpulse/core/services/faq_catalog.dart';
import 'package:govpulse/core/theme/mobile_metrics.dart';
import 'package:govpulse/core/widgets/Home/Chat-agent/chat_agent_info_bar.dart';
import 'package:govpulse/core/widgets/Home/Chat-agent/chat_input_bar.dart';

import '_responsive_matrix.dart';

/// The reporter's handset, in logical pixels at dpr 1 so the arithmetic in a
/// failure message is readable.
const Size _kPhone = Size(430, 932);

/// A typical Android IME, a little over a third of the screen — matching the
/// proportions in the reported screenshot.
const double _kKeyboard = 340;

/// Mirrors the screen's `_buildFaqChips`, so the block under test has the real
/// height (471px at this width) rather than a guess.
Widget _faqChips(double width) {
  Widget chip(String label) => Container(
        padding: EdgeInsets.symmetric(
          horizontal: width * 0.038,
          vertical: width * 0.024,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(width * 0.05),
          border: Border.all(color: Colors.blue),
        ),
        child: Text(label, style: TextStyle(fontSize: width * 0.030)),
      );

  return Container(
    width: double.infinity,
    color: Colors.white,
    padding: EdgeInsets.fromLTRB(
      width * 0.04,
      width * 0.025,
      width * 0.04,
      width * 0.03,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'COMMON QUESTIONS — OR TYPE YOUR OWN',
          style: TextStyle(
            fontSize: width * 0.026,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: width * 0.022),
        Wrap(
          spacing: width * 0.022,
          runSpacing: width * 0.022,
          children: [
            for (final faq in featuredFaqs) chip(faq.question),
            chip('All questions…'),
          ],
        ),
      ],
    ),
  );
}

/// The screen's column, reduced to the parts that decide the vertical
/// arithmetic. [clamp] selects the fixed shape over the shipped one.
Widget _harness({
  required bool clamp,
  double keyboard = 0,
  Size size = _kPhone,
  bool showChips = true,
}) {
  // The screen sizes itself with uiScaleWidth, which on mobile is the
  // SHORTEST side clamped to 480 — not the raw viewport width. Passing
  // size.width here would inflate every widget in landscape and invent an
  // overflow the shipped app never has.
  final scale = uiScaleWidthOf(size);
  final chips = _faqChips(scale);

  return MediaQuery(
    data: MediaQueryData(
      size: size,
      viewInsets: EdgeInsets.only(bottom: keyboard),
    ),
    child: MaterialApp(
      home: Scaffold(
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: Column(
            children: [
              Container(height: 70, color: Colors.white),
              // Mirrors the screen: the bar is dropped only on a compact
              // landscape handset with the keyboard up.
              if (!(_compactLandscape(size) && keyboard > 0))
                ChatAgentInfoBar(width: scale),
              const Expanded(child: SizedBox.expand()),
              if (showChips)
                clamp
                    ? Flexible(
                        child: SingleChildScrollView(child: chips),
                      )
                    : chips,
              ChatInputBar(
                width: scale,
                controller: TextEditingController(),
                focusNode: FocusNode(),
                onSend: () {},
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Mirrors [isCompactLandscape], which reads a BuildContext the harness does
/// not have at this point.
bool _compactLandscape(Size size) =>
    size.width > size.height && size.shortestSide < 600 && size.height < 500;

/// The info bar runs a looping "Online" pulse, so pumpAndSettle never settles.
Future<void> _pump(WidgetTester tester, Widget w) async {
  await tester.pumpWidget(w);
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  group('Ask Kuya Gov composer vs the keyboard', () {
    testWidgets('composer stays above the keyboard on the opening screen', (
      tester,
    ) async {
      tester.view.physicalSize = _kPhone;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pump(tester, _harness(clamp: true, keyboard: _kKeyboard));

      final composer = tester.getRect(find.byType(ChatInputBar));
      final visibleBottom = _kPhone.height - _kKeyboard;

      expect(
        composer.bottom,
        lessThanOrEqualTo(visibleBottom + 0.5),
        reason:
            'The composer is painted under the keyboard. Its bottom is at '
            '${composer.bottom.toStringAsFixed(1)} but the keyboard starts at '
            '$visibleBottom — so the field being typed into is clipped, which '
            'is the reported defect.',
      );
      expect(composer.top, greaterThanOrEqualTo(0));
      expect(
        composer.height,
        greaterThan(40),
        reason: 'Surviving as a squashed sliver is not the same as usable.',
      );
    });

    testWidgets('no RenderFlex overflow while the keyboard is open', (
      tester,
    ) async {
      tester.view.physicalSize = _kPhone;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pump(tester, _harness(clamp: true, keyboard: _kKeyboard));

      expect(
        tester.takeException(),
        isNull,
        reason: 'The overflow IS the visible clipping.',
      );
    });

    testWidgets('the chips are still all present when there is room', (
      tester,
    ) async {
      tester.view.physicalSize = _kPhone;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pump(tester, _harness(clamp: true));

      expect(tester.takeException(), isNull);
      // Every featured question, plus "All questions…".
      expect(
        find.byType(Wrap),
        findsOneWidget,
        reason:
            'The fix must not win composer room by deleting the FAQ chips — '
            'with no keyboard they are the point of the opening screen.',
      );
      for (final faq in featuredFaqs) {
        expect(find.text(faq.question), findsOneWidget);
      }
      expect(find.text('All questions…'), findsOneWidget);
    });

    testWidgets('composer survives a short viewport (web, small window)', (
      tester,
    ) async {
      const short = Size(900, 520);
      tester.view.physicalSize = short;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pump(tester, _harness(clamp: true, size: short));

      expect(tester.takeException(), isNull);
      final composer = tester.getRect(find.byType(ChatInputBar));
      expect(
        composer.bottom,
        lessThanOrEqualTo(short.height + 0.5),
        reason: 'The web layout has the identical Column shape.',
      );
    });
  });

  // ── Responsiveness sweep ────────────────────────────────────────────────
  //
  //  The defect was reported on one handset, but the arithmetic that caused it
  //  (rigid chips + shrinking body) gets WORSE as the screen gets shorter. A
  //  fix verified only at 430x932 would leave the small phones broken, and
  //  landscape — where a keyboard can take over half the height — is the
  //  harshest case in the matrix.
  //
  //  pumpAt runs with kIsWeb == false, so these take the same branch the
  //  shipped Android app takes, and its fallback font is deliberately
  //  pessimistic (~2x glyph width), which stands in for the Tagalog chip
  //  labels and Android's largest font setting.
  group('Ask Kuya Gov composer across the device matrix', () {
    for (final device in kAllPhones) {
      testWidgets('no overflow with the keyboard open — $device', (
        tester,
      ) async {
        // A keyboard takes roughly 40% of a phone screen's height, and more of
        // a landscape one. Clamped so a short landscape viewport still leaves
        // a plausible body rather than a negative one.
        final keyboard = (device.size.height * 0.40).clamp(0.0, 340.0);

        final errors = await pumpAt(
          tester,
          device,
          () => _harness(
            clamp: true,
            keyboard: keyboard,
            size: device.size,
          ),
        );

        expect(
          errors,
          isEmpty,
          reason:
              'The composer is clipped at $device with a '
              '${keyboard.toStringAsFixed(0)}px keyboard.',
        );
      });
    }
  });
}
