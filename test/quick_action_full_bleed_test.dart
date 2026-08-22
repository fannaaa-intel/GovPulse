// test/quick_action_full_bleed_test.dart
//
// ════════════════════════════════════════════════════════════════════════════
//  The quick-action panel when it IS the page.
//
//  Below [kSplitDialogFullscreenBelow] the citizen web shell stops presenting
//  the panel as a floating card and gives it the whole viewport. It had been
//  doing that in geometry only: the Scaffold filled the screen, and then inset
//  the panel by 12px on the shell's grey and drew both zones as rounded,
//  bordered cards with a 14px trough between them. On a 390px phone browser
//  that reads as a modal hovering over nothing — which is exactly how it was
//  reported — and the ~38px of chrome came out of the one part with real work
//  in it.
//
//  What these tests pin:
//
//    1. Fullscreen means EDGE TO EDGE. The panel starts at the viewport's own
//       safe area, not 12px inside it.
//    2. The cards give up their outline with it, so removing the inset does not
//       just move a rounded card up against the screen edge.
//    3. The two zones are separated by a hairline instead of a trough — and by
//       nothing at all when a pane has no actions, which is where a naive
//       "always draw a rule" would leave a stray line across the bottom.
//    4. None of it reaches the floating presentation. Above the threshold the
//       cards are exactly what they were.
// ════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/core/widgets/Home/Quick-action/Web/quick_action_split_panel.dart';
import 'package:govpulse/features/home/shell/citizen_shell_dialogs.dart';

/// A stand-in panel: one body card, one action card, on the real chrome.
Widget _panel({bool actions = true}) => QaSplitPanel(
  left: (stacked) => const QaPanelCard(child: Text('body')),
  right: (stacked) =>
      actions ? const QaPanelCard(child: Text('actions')) : null,
);

/// Opens the stand-in through the REAL host, at [size], and settles.
///
/// Through the host rather than by handing the panel a scope directly: the
/// whole question here is which presentation the host chose and what it told
/// the chrome, and a test that supplies the answer itself cannot see that.
Future<void> _pumpHosted(
  WidgetTester tester, {
  required Size size,
  bool actions = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showCitizenSplitPanelDialog<void>(
              context: context,
              builder: (_, _) => _panel(actions: actions),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// The decoration a [QaPanelCard] actually painted.
BoxDecoration _decorationOf(WidgetTester tester, Finder card) {
  final container = tester.widget<Container>(
    find.descendant(of: card, matching: find.byType(Container)).first,
  );
  return container.decoration! as BoxDecoration;
}

void main() {
  group('fullscreen is edge to edge', () {
    testWidgets('the panel starts at the viewport edge, not 12px inside it', (
      tester,
    ) async {
      await _pumpHosted(tester, size: const Size(390, 844));

      final panel = tester.getRect(find.byType(QaSplitPanel));
      // No safe area in the test view, so the panel's own rect IS the viewport.
      // The 12px band this replaces would have shown up as 12 on all four.
      expect(panel.left, 0);
      expect(panel.top, 0);
      expect(panel.right, 390);
      expect(panel.bottom, 844);
    });

    testWidgets('the cards drop their border and their corner radius', (
      tester,
    ) async {
      await _pumpHosted(tester, size: const Size(390, 844));

      final cards = find.byType(QaPanelCard);
      expect(cards, findsNWidgets(2));
      for (var i = 0; i < 2; i++) {
        final d = _decorationOf(tester, cards.at(i));
        expect(d.border, isNull, reason: 'card $i keeps a border');
        expect(d.borderRadius, BorderRadius.zero, reason: 'card $i is rounded');
      }
    });

    testWidgets('a hairline separates the zones, not a 14px trough', (
      tester,
    ) async {
      await _pumpHosted(tester, size: const Size(390, 844));

      final cards = find.byType(QaPanelCard);
      final body = tester.getRect(cards.at(0));
      final action = tester.getRect(cards.at(1));

      expect(action.top - body.bottom, 1);
      // And the action zone is genuinely pinned to the bottom edge.
      expect(action.bottom, 844);
    });

    testWidgets('a pane with no actions gets no rule and no stray line', (
      tester,
    ) async {
      await _pumpHosted(tester, size: const Size(390, 844), actions: false);

      final cards = find.byType(QaPanelCard);
      expect(cards, findsOneWidget);
      // The body reaches the bottom itself — nothing is drawn under it, which
      // is what a returned `SizedBox.shrink()` could not express.
      expect(tester.getRect(cards.first).bottom, 844);
    });
  });

  group('the floating presentation is untouched', () {
    testWidgets('above the threshold the cards keep their outline', (
      tester,
    ) async {
      await _pumpHosted(tester, size: const Size(1280, 900));

      final cards = find.byType(QaPanelCard);
      expect(cards, findsNWidgets(2));
      for (var i = 0; i < 2; i++) {
        final d = _decorationOf(tester, cards.at(i));
        expect(d.border, isNotNull, reason: 'card $i lost its border');
        expect(d.borderRadius, isNot(BorderRadius.zero));
      }
    });

    testWidgets('and the dialog still floats inside its inset', (tester) async {
      await _pumpHosted(tester, size: const Size(1280, 900));

      final panel = tester.getRect(find.byType(QaSplitPanel));
      expect(panel.left, greaterThan(0));
      expect(panel.top, greaterThan(0));
      expect(panel.right, lessThan(1280));
    });
  });

  group('the scope is what carries it, and it defaults off', () {
    testWidgets('no scope means the cards a host never opted in to', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: SizedBox(height: 600, child: _panel()))),
      );
      await tester.pumpAndSettle();

      final d = _decorationOf(tester, find.byType(QaPanelCard).first);
      expect(d.border, isNotNull);
      expect(d.borderRadius, isNot(BorderRadius.zero));
    });
  });
}
