// test/quick_action_keyboard_test.dart
//
// ════════════════════════════════════════════════════════════════════════════
//  The stacked quick-action panel, with a keyboard open.
//
//  keyboard_visibility_test.dart pins the mechanism for [AccountPageBody], and
//  its own header names what it does NOT cover: "the chat composer, the
//  quick-action forms and pinned bottom bars". This is that gap, for the part
//  of it that is a plain widget and so reachable from the VM.
//
//  The defect these guard against, seen on a phone browser on the live site:
//  the host Dialog shrinks by `viewInsets` when the keyboard opens, but the
//  pinned action zone kept its full intrinsic height — Continue over Back over
//  Cancel, comfortably 200px — and took it out of the one part that needed the
//  room. The working area collapsed to a sliver of the step notice and the
//  field being typed into was pushed off the bottom of the panel, so the
//  citizen was typing into something they could not see.
//
//  [QaSplitPanel] is reached only through the citizen web shell, but nothing
//  about it is web-gated at the widget level, so it renders fine here.
// ════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/core/widgets/Home/Quick-action/Web/quick_action_split_panel.dart';

/// Panel height with no keyboard. Comfortably inside the 800x600 test surface —
/// a taller box is silently clamped to the surface and every number below then
/// measures the clamp instead of the layout.
const double kPanel = 520;

/// Height of the stand-in action zone: Continue over Back over Cancel.
const double kActions = 210;

/// Mounts the panel STACKED — narrower than [kQaSplitCollapseBelow] — with
/// [keyboard] logical pixels of bottom inset, and settles the transition.
Future<void> pumpStacked(WidgetTester tester, {required double keyboard}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(viewInsets: EdgeInsets.only(bottom: keyboard)),
        child: Center(
          child: SizedBox(
            width: 400,
            // What a phone browser has left once the keyboard is up. The host
            // Dialog applies the inset itself, which is why it is subtracted
            // here and only read as a flag inside the panel.
            height: kPanel - keyboard,
            child: QaSplitPanel(
              left: (stacked) => Container(
                key: const Key('body'),
                color: const Color(0xFFEEEEEE),
              ),
              right: (stacked) => Container(
                key: const Key('actions'),
                height: kActions,
                color: const Color(0xFFDDDDDD),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

double heightOf(WidgetTester tester, String key) =>
    tester.getSize(find.byKey(Key(key))).height;

void main() {
  group('stacked quick-action panel', () {
    testWidgets('pins the action zone when no keyboard is up', (tester) async {
      await pumpStacked(tester, keyboard: 0);

      expect(find.byKey(const Key('actions')), findsOneWidget);
      expect(heightOf(tester, 'actions'), kActions);
      expect(heightOf(tester, 'body'), kPanel - kQaGap - kActions);
    });

    testWidgets('stands the action zone down while the keyboard is up', (
      tester,
    ) async {
      await pumpStacked(tester, keyboard: 240);

      // The pin exists so Continue is always reachable. While the keyboard
      // covers it, it is not reachable anyway, so the pin costs height and
      // buys nothing.
      expect(find.byKey(const Key('actions')), findsNothing);
    });

    testWidgets('the working area keeps every pixel the keyboard left', (
      tester,
    ) async {
      await pumpStacked(tester, keyboard: 240);

      // The whole of the shortened panel, with no zone and no gap taken out.
      expect(heightOf(tester, 'body'), kPanel - 240);
    });

    testWidgets('the body gives up less height than the keyboard takes', (
      tester,
    ) async {
      await pumpStacked(tester, keyboard: 0);
      final closed = heightOf(tester, 'body');

      await pumpStacked(tester, keyboard: 240);
      final open = heightOf(tester, 'body');

      // This is the whole point. The panel is 240 shorter, but the body loses
      // less than that, because the zone and its gap come back to it. Before
      // the fix the body lost the full 240 and was left with 56 — which is what
      // the reported "the input is covered" actually was.
      expect(open, greaterThan(closed - 240));
      expect(open, kPanel - 240);
      expect(closed, kPanel - kQaGap - kActions);
    });

    testWidgets('the action zone comes back when the keyboard closes', (
      tester,
    ) async {
      await pumpStacked(tester, keyboard: 240);
      expect(find.byKey(const Key('actions')), findsNothing);

      await pumpStacked(tester, keyboard: 0);
      expect(find.byKey(const Key('actions')), findsOneWidget);
      expect(heightOf(tester, 'actions'), kActions);
    });

    testWidgets('the zone collapses over time rather than between frames', (
      tester,
    ) async {
      await pumpStacked(tester, keyboard: 0);
      final pinned = heightOf(tester, 'body');

      // Re-mount with the keyboard up but do NOT settle: partway through the
      // transition the body must be somewhere between the two resting sizes.
      // A hard swap would already be at its final height on the first frame,
      // which is the jump that reads as a glitch next to the rising keyboard.
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              viewInsets: EdgeInsets.only(bottom: 240),
            ),
            child: Center(
              child: SizedBox(
                width: 400,
                height: kPanel - 240,
                child: QaSplitPanel(
                  left: (stacked) => Container(
                    key: const Key('body'),
                    color: const Color(0xFFEEEEEE),
                  ),
                  right: (stacked) => Container(
                    key: const Key('actions'),
                    height: kActions,
                    color: const Color(0xFFDDDDDD),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 80));

      final midway = heightOf(tester, 'body');
      expect(midway, lessThan(kPanel - 240));
      expect(midway, isNot(pinned));

      await tester.pumpAndSettle();
      expect(heightOf(tester, 'body'), kPanel - 240);
    });
  });
}
