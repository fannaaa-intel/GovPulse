// test/quick_action_keyboard_test.dart
//
// ════════════════════════════════════════════════════════════════════════════
//  The stacked quick-action panel, with a keyboard open.
//
//  keyboard_visibility_test.dart pins the mechanism for [AccountPageBody], and
//  its own header names what it does NOT cover: "the quick-action forms and
//  pinned bottom bars". This is that gap.
//
//  ── The defect ──────────────────────────────────────────────────────────
//  Seen on a phone browser on the live site. The host Dialog shrinks by
//  `viewInsets` when the keyboard opens, but the pinned action zone kept its
//  full intrinsic height — Continue over Back over Cancel, comfortably 200px —
//  and took the whole cost out of the one zone that needed the room. The body
//  collapsed to a sliver of the step notice and the field being typed into was
//  pushed off the bottom, so the citizen was typing into something they could
//  not see.
//
//  ── The mistake the FIRST fix made, which these tests exist to prevent ───
//  It asked `MediaQuery.viewInsetsOf(context).bottom > 0` from inside the
//  panel. [Dialog] strips viewInsets from its subtree, so that is always zero:
//  the check never fired and the fix shipped inert. The first test below is
//  the one that would have caught it — it mounts a REAL Dialog rather than a
//  hand-supplied MediaQuery, which is precisely what the original tests did
//  not do.
// ════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/core/widgets/Home/Quick-action/Web/quick_action_split_panel.dart';

/// Panel height with no keyboard. Comfortably inside the 800x600 test surface —
/// a taller box is silently clamped to the surface, and every number below then
/// measures the clamp instead of the layout.
const double kPanel = 520;

/// Height of the stand-in action zone: Continue over Back over Cancel.
const double kActions = 210;

Widget panel() => QaSplitPanel(
  left: (stacked) =>
      Container(key: const Key('body'), color: const Color(0xFFEEEEEE)),
  right: (stacked) => Container(
    key: const Key('actions'),
    height: kActions,
    color: const Color(0xFFDDDDDD),
  ),
);

/// Mounts the panel STACKED — narrower than [kQaSplitCollapseBelow] — inside a
/// [QaKeyboardScope], the way the host provides it.
Future<void> pumpStacked(
  WidgetTester tester, {
  required double keyboard,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: SizedBox(
          width: 400,
          // What a phone browser has left once the keyboard is up. The host
          // Dialog applies the inset itself, which is why it is subtracted
          // here and only carried as a flag into the panel.
          height: kPanel - keyboard,
          child: QaKeyboardScope(keyboardUp: keyboard > 0, child: panel()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

double heightOf(WidgetTester tester, String key) =>
    tester.getSize(find.byKey(Key(key))).height;

void main() {
  group('the dialog boundary', () {
    testWidgets('Dialog strips viewInsets, so MediaQuery cannot see the '
        'keyboard from inside the panel', (tester) async {
      late double insetInside;

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              viewInsets: EdgeInsets.only(bottom: 240),
            ),
            child: Dialog(
              child: Builder(
                builder: (context) {
                  insetInside = MediaQuery.of(context).viewInsets.bottom;
                  return const SizedBox(width: 100, height: 100);
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 240 outside, 0 inside. This is the whole reason QaKeyboardScope exists,
      // and the reason a check written against MediaQuery inside the panel is
      // dead code rather than merely fragile.
      expect(insetInside, 0);
    });

    testWidgets('the scope carries the flag across that boundary', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              viewInsets: EdgeInsets.only(bottom: 240),
            ),
            child: Builder(
              // Read ABOVE the Dialog, exactly as the host does.
              builder: (outer) => Dialog(
                insetPadding: EdgeInsets.zero,
                child: SizedBox(
                  width: 400,
                  height: kPanel - 240,
                  child: QaKeyboardScope(
                    keyboardUp: MediaQuery.viewInsetsOf(outer).bottom > 0,
                    child: panel(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('actions')), findsNothing);
    });
  });

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
      // the fix the body lost the full 240 and was left with 56 — which is
      // what "the input is covered" actually was.
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

    testWidgets('the body height never reverses while the keyboard rises', (
      tester,
    ) async {
      // ── The "small quake" ────────────────────────────────────────────────
      // Animating the collapse while the keyboard rose put two animations on
      // the same dimension on different clocks. Measured, the body went
      // 296 -> 238 -> 293 -> 240: down 58, back UP 55, then down 53 again.
      // Monotonic or not is the whole property; the exact numbers are not.
      Future<void> frame(double k) => tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 400,
              height: kPanel - k,
              child: QaKeyboardScope(keyboardUp: k > 0, child: panel()),
            ),
          ),
        ),
      );

      await frame(0);
      await tester.pumpAndSettle();

      final heights = <double>[heightOf(tester, 'body')];
      for (var t = 16; t <= 300; t += 16) {
        await frame((280 * (t / 250)).clamp(0.0, 280.0));
        await tester.pump(const Duration(milliseconds: 16));
        heights.add(heightOf(tester, 'body'));
      }

      // Every step after the first must be <= the one before it. The first
      // step is the zone leaving, which is meant to be immediate.
      for (var i = 2; i < heights.length; i++) {
        expect(
          heights[i],
          lessThanOrEqualTo(heights[i - 1] + 0.5),
          reason:
              'body grew from ${heights[i - 1]} to ${heights[i]} at sample $i '
              '- the collapse is racing the keyboard again',
        );
      }
    });

    testWidgets('the return is eased rather than snapping back', (
      tester,
    ) async {
      await pumpStacked(tester, keyboard: 240);
      final open = heightOf(tester, 'body');

      // Keyboard gone. The panel is already back to full height, so nothing is
      // racing this one — it is the direction worth easing.
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 400,
              height: kPanel,
              child: QaKeyboardScope(keyboardUp: false, child: panel()),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 80));

      final midway = heightOf(tester, 'body');
      expect(midway, lessThan(kPanel));
      expect(midway, greaterThan(kPanel - kQaGap - kActions));
      expect(midway, isNot(open));

      await tester.pumpAndSettle();
      expect(heightOf(tester, 'body'), kPanel - kQaGap - kActions);
    });
  });
}
