// test/admin_dialog_keyboard_test.dart
//
// ════════════════════════════════════════════════════════════════════════════
//  The report-process dialogs, with a keyboard open.
//
//  ── The defect ──────────────────────────────────────────────────────────
//  Reported on the phone app: typing into "Or provide another reason" on the
//  reject dialog, the FIELD behaves (the framework scrolls it above the
//  keyboard) but the pinned action bar rides up with it and sits directly on
//  the keyboard. Under the keyboard those buttons are unreachable anyway, so
//  the pin is costing the body ~100px and buying nothing.
//
//  ── The mistake these tests exist to prevent ────────────────────────────
//  [Dialog] pads itself by `MediaQuery.viewInsets` and then wraps its child in
//  `MediaQuery.removeViewInsets(removeBottom: true, ...)`. So a
//  `MediaQuery.viewInsetsOf(context).bottom > 0` written from INSIDE the dialog
//  is always zero — dead code that always takes the same branch.
//
//  That is not hypothetical: the citizen quick-action panel shipped exactly
//  that check and it never fired once (see quick_action_keyboard_test.dart).
//  The first test below is the one that catches it — it mounts a REAL Dialog
//  over a REAL view inset rather than hand-supplying a MediaQuery.
// ════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:govpulse/features/admin/widgets/admin_dialog_keyboard.dart';

const Size _kPhone = Size(400, 800);
const double _kKeyboard = 320;

void main() {
  group('AdminDialogKeyboard', () {
    testWidgets(
      'reads the REAL inset at a dialog build site, above the strip',
      (tester) async {
        tester.view.physicalSize = _kPhone;
        tester.view.devicePixelRatio = 1.0;
        tester.view.viewInsets = const FakeViewPadding(bottom: _kKeyboard);
        addTearDown(tester.view.reset);

        // Where a dialog's own build() runs: outside the Dialog it returns.
        bool? atBuildSite;
        // Where the dialog's CONTENT runs: inside, below the strip.
        bool? insideDialog;

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (outer) {
                atBuildSite = AdminDialogKeyboard.of(outer);
                return Dialog(
                  child: Builder(
                    builder: (inner) {
                      insideDialog = AdminDialogKeyboard.of(inner);
                      return const SizedBox(height: 100);
                    },
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The whole point: the answer is available where the dialogs read it…
        expect(
          atBuildSite,
          isTrue,
          reason: 'a dialog\'s own build context is above the strip and must '
              'see the keyboard',
        );
        // …and provably NOT available where it would be tempting to read it.
        expect(
          insideDialog,
          isFalse,
          reason: 'Dialog strips viewInsets from its subtree — a check written '
              'here is dead code. This is the regression being pinned.',
        );
      },
    );

    testWidgets('an explicit scope overrides the ambient read', (tester) async {
      bool? seen;
      await tester.pumpWidget(
        MaterialApp(
          home: AdminDialogKeyboard(
            keyboardUp: true,
            child: Builder(
              builder: (ctx) {
                seen = AdminDialogKeyboard.of(ctx);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      expect(seen, isTrue);
    });

    testWidgets('defaults to false with no keyboard and no scope', (
      tester,
    ) async {
      bool? seen;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) {
              seen = AdminDialogKeyboard.of(ctx);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(seen, isFalse);
    });
  });

  group('AdminKeyboardCollapse', () {
    /// The action bar stands in for a real one — two stacked full-width
    /// buttons, which is what these dialogs pin on a phone.
    Widget host({required bool keyboardUp}) => MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            const Expanded(child: SizedBox.expand()),
            AdminKeyboardCollapse(
              keyboardUp: keyboardUp,
              child: Container(key: const Key('bar'), height: 120),
            ),
          ],
        ),
      ),
    );

    testWidgets('the bar keeps its height while the keyboard is down', (
      tester,
    ) async {
      await tester.pumpWidget(host(keyboardUp: false));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(const Key('bar'))).height, 120);
    });

    testWidgets('the bar is gone from the layout while the keyboard is up', (
      tester,
    ) async {
      await tester.pumpWidget(host(keyboardUp: true));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('bar')), findsNothing);
    });

    testWidgets(
      'going OUT is instant — one moving part while the keyboard rises',
      (tester) async {
        await tester.pumpWidget(host(keyboardUp: false));
        await tester.pumpAndSettle();

        final before = tester.getSize(find.byType(AdminKeyboardCollapse)).height;
        expect(before, 120);

        // Keyboard opens. Animating the collapse here would put two animations
        // on the same dimension on different clocks — measured elsewhere in
        // this app as the body going down 58px, back up 55, then down 53, and
        // felt as a shake. So the collapse must be over almost immediately,
        // leaving the host's resize as the only thing moving.
        await tester.pumpWidget(host(keyboardUp: true));
        await tester.pump(const Duration(milliseconds: 16));

        expect(
          tester.getSize(find.byType(AdminKeyboardCollapse)).height,
          0,
          reason: 'the bar must be out of the layout within a frame, not eased',
        );
      },
    );

    testWidgets('coming BACK is eased, not snapped', (tester) async {
      await tester.pumpWidget(host(keyboardUp: true));
      await tester.pumpAndSettle();

      // Keyboard closes. There is nothing to race here — keyboardUp only
      // clears once the inset has reached zero — and an instant return would
      // snap the whole bar in one frame.
      await tester.pumpWidget(host(keyboardUp: false));
      await tester.pump(const Duration(milliseconds: 100));

      final mid = tester.getSize(find.byType(AdminKeyboardCollapse)).height;
      expect(
        mid,
        greaterThan(0),
        reason: 'it should have started growing',
      );
      expect(
        mid,
        lessThan(120),
        reason: 'and should NOT be there already — that would be a snap',
      );

      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(AdminKeyboardCollapse)).height, 120);
    });
  });
}
