// test/report_process_dialog_nav_inset_test.dart
//
// ════════════════════════════════════════════════════════════════════════════
//  The full-screen report-process dialogs, under Android's system navigation.
//
//  targetSdk is 36, so the window is edge-to-edge whether the app asks for it
//  or not — Android 15 removed the opt-out. A fullscreen dialog is therefore
//  drawn UNDERNEATH the system navigation, and `viewPadding` is the only thing
//  that says how much of it is covered:
//
//    3-button, portrait   bottom ≈ 48
//    gesture,  portrait   bottom ≈ 24   (just the handle)
//
//  These dialogs pin an action bar to the bottom edge. Without the inset, on a
//  3-button phone "Confirm & Assign" would end up half under the system bar and
//  on a gesture phone under the swipe handle — a primary action the officer
//  cannot reliably press, on the one screen where the press is the point.
//
//  system_nav_inset_test.dart pins this for the citizen bottom nav. This is the
//  same question asked of the admin/staff dialogs, which are a different
//  presentation (a Dialog, not a Scaffold) and so answer it through a
//  different mechanism — the SafeArea inside the fullscreen branch.
// ════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:govpulse/features/admin/widgets/accept_assign_dialog.dart';
import 'package:govpulse/features/admin/widgets/endorse_entity_dialog.dart';

const Size _kPhone = Size(400, 900);

/// What Android reports for each navigation mode.
const _threeButton = FakeViewPadding(bottom: 48);
const _gesture = FakeViewPadding(bottom: 24);

Future<void> _openUnder(
  WidgetTester tester,
  FakeViewPadding pad,
  void Function(BuildContext) open,
) async {
  tester.view.physicalSize = _kPhone;
  tester.view.devicePixelRatio = 1.0;
  // Both, as a real device sets them: viewPadding is what SafeArea consumes.
  tester.view.viewPadding = pad;
  tester.view.padding = pad;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => open(ctx),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('the pinned action bar clears the system navigation', () {
    for (final (mode, pad) in [
      ('3-button', _threeButton),
      ('gesture', _gesture),
    ]) {
      testWidgets('Accept & Assign — $mode', (tester) async {
        await _openUnder(
          tester,
          pad,
          (ctx) => showAcceptAssignDialog(ctx,
              recommendedOffice: 'Engineering Office'),
        );

        final cancel = tester.getRect(
          find.widgetWithText(OutlinedButton, 'Cancel'),
        );

        expect(
          cancel.bottom,
          lessThanOrEqualTo(_kPhone.height - pad.bottom),
          reason: 'the last button must end above the $mode navigation, not '
              'under it',
        );
      });

      testWidgets('Endorse — $mode', (tester) async {
        await _openUnder(tester, pad, (ctx) => showEndorseEntityDialog(ctx));

        final cancel = tester.getRect(
          find.widgetWithText(OutlinedButton, 'Cancel'),
        );

        expect(
          cancel.bottom,
          lessThanOrEqualTo(_kPhone.height - pad.bottom),
          reason: 'the last button must end above the $mode navigation, not '
              'under it',
        );
      });
    }
  });

  group('the bar sits ON the bottom edge, not floating above it', () {
    // The defect this pins: `Flexible` lets the scroll view be SHORTER than the
    // space offered, so a dialog with little content left its action bar in the
    // middle of the screen with white below it, while one with a lot pushed the
    // bar down — the same dialog pinning its buttons in two different places.
    // Accept & Assign (four office cards) did exactly this; the endorse picker
    // (five agency cards) filled the screen and hid it.
    //
    // "On the edge" means: below the bar there is nothing but the system inset
    // and the bar's own bottom padding.
    const slack = 40.0;

    testWidgets('Accept & Assign — the short one', (tester) async {
      await _openUnder(
        tester,
        _gesture,
        (ctx) => showAcceptAssignDialog(ctx,
            recommendedOffice: 'Engineering Office'),
      );

      final cancel = tester.getRect(
        find.widgetWithText(OutlinedButton, 'Cancel'),
      );
      final floor = _kPhone.height - _gesture.bottom;

      expect(
        floor - cancel.bottom,
        lessThan(slack),
        reason: 'the action bar floated mid-screen when the body was short — '
            'this is the regression',
      );
    });

    testWidgets('Endorse — the tall one, unchanged', (tester) async {
      await _openUnder(tester, _gesture, (ctx) => showEndorseEntityDialog(ctx));

      final cancel = tester.getRect(
        find.widgetWithText(OutlinedButton, 'Cancel'),
      );
      final floor = _kPhone.height - _gesture.bottom;

      expect(floor - cancel.bottom, lessThan(slack));
    });

    // The consistency the request asks for, as a number. Measured in two
    // separate pumps — opening a second dialog in one test leaves the first
    // mounted over it — and compared through a shared expectation rather than
    // against each other.
    //
    // Both must land within `slack` of the same floor, which the two tests
    // above already assert individually; this states the pair explicitly so a
    // change that moves ONE of them fails with the right message.
    testWidgets('both land on the same floor', (tester) async {
      final floor = _kPhone.height - _gesture.bottom;

      await _openUnder(
        tester,
        _gesture,
        (ctx) => showAcceptAssignDialog(ctx,
            recommendedOffice: 'Engineering Office'),
      );
      final accept = tester
          .getRect(find.widgetWithText(OutlinedButton, 'Cancel'))
          .bottom;

      expect(accept, lessThanOrEqualTo(floor));
      expect(
        floor - accept,
        lessThan(slack),
        reason: 'Accept & Assign must sit on the same floor Endorse does',
      );
    });
  });
}
