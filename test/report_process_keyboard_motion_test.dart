// test/report_process_keyboard_motion_test.dart
//
// ════════════════════════════════════════════════════════════════════════════
//  The keyboard transition, frame by frame.
//
//  ── The defect ──────────────────────────────────────────────────────────
//  Reported from the phone: opening and closing the keyboard on the endorse
//  and reject forms was "not too smooth" — the layout moved in steps, lagging
//  the keyboard and then catching up in a jump.
//
//  ── The cause ───────────────────────────────────────────────────────────
//  The fullscreen form was a [Dialog] with a zero inset. Dialog pads itself by
//  `viewInsets` using an [AnimatedPadding] — 100ms, Curves.decelerate, on its
//  OWN clock — while the OS reports the keyboard's rise in steps on a
//  different one. Two animations on the same dimension, racing.
//
//  Measured before the fix, at a 900px viewport with a 320px keyboard:
//
//      inset  60 -> box 900   (hadn't moved yet)
//      inset 140 -> box 882
//      inset 220 -> box 846
//      inset 320 -> box 745   (still 165px behind)
//      settled   -> box 580   (snap)
//
//  ── The fix ─────────────────────────────────────────────────────────────
//  A [Scaffold] with `resizeToAvoidBottomInset`, which shrinks the body on the
//  keyboard's own clock — no second animation to race. This is the same
//  mechanism keyboard_visibility_test.dart pins as correct, and the one the
//  citizen quick-action panel switched to after the identical bug (its note
//  calls the symptom "brick by brick"). See AdminFullBleedDialog.
//
//  These tests are the measurement, kept: they assert the box tracks the inset
//  EXACTLY on every frame, in both directions, which the Dialog form could not
//  do and no screenshot would ever have caught.
// ════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:govpulse/features/admin/widgets/accept_assign_dialog.dart';
import 'package:govpulse/features/admin/widgets/endorse_entity_dialog.dart';

const double _kH = 900;
const double _kW = 400;

Future<void> _open(
  WidgetTester tester,
  void Function(BuildContext) show,
) async {
  tester.view.physicalSize = const Size(_kW, _kH);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => show(ctx),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// The form's own content box — what the keyboard has to shrink.
double _box(WidgetTester tester) =>
    tester.getRect(find.byType(SafeArea).last).height;

Future<void> _setKeyboard(WidgetTester tester, double inset) async {
  tester.view.viewInsets = FakeViewPadding(bottom: inset);
  // ONE frame. The point is that no catch-up animation is needed.
  await tester.pump(const Duration(milliseconds: 16));
}

void main() {
  group('the form tracks the keyboard with no lag', () {
    // A keyboard does not appear at full height — it rises in steps, and each
    // step is a frame the layout has to answer on.
    const rise = [60.0, 140.0, 220.0, 280.0, 320.0];

    testWidgets('Endorse — going up', (tester) async {
      await _open(tester, (ctx) => showEndorseEntityDialog(ctx));
      expect(_box(tester), _kH);

      for (final inset in rise) {
        await _setKeyboard(tester, inset);
        expect(
          _box(tester),
          _kH - inset,
          reason: 'at inset $inset the box must already be ${_kH - inset} — a '
              'smaller number means it is lagging and will snap',
        );
      }
    });

    testWidgets('Endorse — going down', (tester) async {
      await _open(tester, (ctx) => showEndorseEntityDialog(ctx));

      await _setKeyboard(tester, 320);
      expect(_box(tester), _kH - 320);

      for (final inset in [220.0, 120.0, 40.0, 0.0]) {
        await _setKeyboard(tester, inset);
        expect(
          _box(tester),
          _kH - inset,
          reason: 'the way back must be as monotonic as the way up',
        );
      }
    });

    testWidgets('Accept & Assign — the same shell, the same behaviour', (
      tester,
    ) async {
      await _open(
        tester,
        (ctx) => showAcceptAssignDialog(ctx,
            recommendedOffice: 'Engineering Office'),
      );

      for (final inset in rise) {
        await _setKeyboard(tester, inset);
        expect(_box(tester), _kH - inset);
      }
    });
  });

  group('the field stays above the keyboard', () {
    // The half that matters to the person typing: the box shrinking is only
    // useful if the focused field ends up somewhere they can see it. Scaffold
    // strips the inset from the MediaQuery its body sees, which is what lets
    // the framework scroll a focused field back into view.
    testWidgets('the endorse reason field is visible with the keyboard up', (
      tester,
    ) async {
      await _open(tester, (ctx) => showEndorseEntityDialog(ctx));

      await _setKeyboard(tester, 320);
      await tester.pumpAndSettle();

      final field = find.byType(TextField).last;
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();

      final rect = tester.getRect(field);
      const keyboardLine = _kH - 320;

      expect(
        rect.bottom,
        lessThanOrEqualTo(keyboardLine),
        reason: 'the reason field must sit above the keyboard, not under it — '
            'this is the box the admin is actually typing into',
      );
    });
  });
}
