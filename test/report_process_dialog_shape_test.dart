// test/report_process_dialog_shape_test.dart
//
// ════════════════════════════════════════════════════════════════════════════
//  The three report-process dialogs draw ONE header shape, and pin their
//  actions the same way.
//
//  Accept & Assign, Endorse to External Entity and Reject had drifted into
//  three variations of the same header. They now share
//  [AdminDialogScreenHeader], whose phone shape is:
//
//      [<]  Accept & Assign
//      (seal)  This report is valid and will be assigned…
//
//  — the chevron and the title on one row, the seal leading the description it
//  illustrates on the next. These pin that so the next edit to one dialog
//  cannot quietly re-fork the other two.
//
//  The ✕ is gone at EVERY width, not just on the phone screen: the action bar
//  carries an explicit Cancel, the barrier is dismissible and Esc pops the
//  route, so the ✕ was a fourth way out whose only effect was to make the title
//  share its row with a control.
// ════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:govpulse/features/admin/widgets/accept_assign_dialog.dart';
import 'package:govpulse/features/admin/widgets/admin_dialog_back.dart';
import 'package:govpulse/features/admin/widgets/admin_dialog_keyboard.dart';
import 'package:govpulse/features/admin/widgets/endorse_entity_dialog.dart';
import 'package:govpulse/features/admin/widgets/report_detail_kit.dart';

const Size _kPhone = Size(400, 900);
const Size _kTablet = Size(800, 1000);
const Size _kDesktop = Size(1400, 1000);

Future<void> _sized(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Opens [open] from a button, so the dialog is mounted the way the console
/// mounts it rather than pumped bare.
Future<void> _open(
  WidgetTester tester,
  void Function(BuildContext) open,
) async {
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
  group('the phone screen header', () {
    testWidgets('Accept & Assign leads with a back chevron', (tester) async {
      await _sized(tester, _kPhone);
      await _open(
        tester,
        (ctx) => showAcceptAssignDialog(ctx,
            recommendedOffice: 'Engineering Office'),
      );

      expect(find.text('Accept & Assign'), findsOneWidget);
      expect(find.byType(AdminDialogBack), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsNothing);
    });

    testWidgets('Endorse leads with a back chevron', (tester) async {
      await _sized(tester, _kPhone);
      await _open(tester, (ctx) => showEndorseEntityDialog(ctx));

      expect(find.text('Endorse to External Entity'), findsOneWidget);
      expect(find.byType(AdminDialogBack), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsNothing);
    });

    testWidgets(
      'the chevron and the title SHARE the top row',
      (tester) async {
        await _sized(tester, _kPhone);
        await _open(tester, (ctx) => showEndorseEntityDialog(ctx));

        // The shape the request asks for, stated as geometry:
        //     [<]  Endorse to External Entity
        //     (seal)  description…
        final chevron = tester.getRect(find.byType(AdminDialogBack));
        final title = tester.getRect(find.text('Endorse to External Entity'));

        // Beside, not stacked: the two overlap vertically.
        expect(
          chevron.top,
          lessThan(title.bottom),
          reason: 'the chevron and title must share a row, not stack',
        );
        expect(
          title.top,
          lessThan(chevron.bottom),
          reason: 'the chevron and title must share a row, not stack',
        );
        // And the chevron leads.
        expect(chevron.right, lessThanOrEqualTo(title.left));
      },
    );

    testWidgets('the phone form drops the seal entirely', (tester) async {
      await _sized(tester, _kPhone);
      await _open(tester, (ctx) => showEndorseEntityDialog(ctx));

      // The seal cost the description ~70px of a ~390px screen, wrapping two
      // readable lines into three or four narrow ones. It is decoration — it
      // repeats what the title already says — and the description carries the
      // irreversibility warning, which is the most important sentence here.
      //
      // The endorse seal is a send glyph; the only send_rounded left on the
      // phone form is the one on the "Send Endorsement" button.
      expect(
        find.byIcon(Icons.send_rounded),
        findsOneWidget,
        reason: 'the header seal is gone; only the action button keeps its icon',
      );
    });

    testWidgets('the description runs the full width', (tester) async {
      await _sized(tester, _kPhone);
      await _open(tester, (ctx) => showEndorseEntityDialog(ctx));

      final title = tester.getRect(find.text('Endorse to External Entity'));
      final desc = tester.getRect(
        find.textContaining('Send this report to the appropriate'),
      );

      // Under the title row, and starting at the header's own left edge rather
      // than indented past a seal.
      expect(desc.top, greaterThanOrEqualTo(title.top));
      expect(
        desc.left,
        lessThan(title.left),
        reason: 'the description is no longer indented past the seal — it '
            'starts left of where the title sits beside the chevron',
      );
      // And it is genuinely wide: most of the screen, not a narrow column.
      expect(desc.width, greaterThan(_kPhone.width * 0.8));
    });
  });

  group('the modal keeps no close X', () {
    for (final (label, size) in [
      ('tablet', _kTablet),
      ('desktop', _kDesktop),
    ]) {
      testWidgets('Endorse at $label', (tester) async {
        await _sized(tester, size);
        await _open(tester, (ctx) => showEndorseEntityDialog(ctx));

        expect(find.text('Endorse to External Entity'), findsOneWidget);
        expect(find.byIcon(Icons.close_rounded), findsNothing);
        // The way out that remains, and is enough.
        expect(find.widgetWithText(OutlinedButton, 'Cancel'), findsOneWidget);
      });

      testWidgets('Accept & Assign at $label', (tester) async {
        await _sized(tester, size);
        await _open(
          tester,
          (ctx) => showAcceptAssignDialog(ctx,
              recommendedOffice: 'Engineering Office'),
        );

        expect(find.byIcon(Icons.close_rounded), findsNothing);
        expect(find.widgetWithText(OutlinedButton, 'Cancel'), findsOneWidget);
      });
    }
  });

  group('the endorse picker has no search field', () {
    for (final (label, size) in [
      ('phone', _kPhone),
      ('tablet', _kTablet),
      ('desktop', _kDesktop),
    ]) {
      testWidgets('at $label', (tester) async {
        await _sized(tester, size);
        await _open(tester, (ctx) => showEndorseEntityDialog(ctx));

        // Five agencies, all on screen at every width. A search box over a list
        // you can already see in full can only ever hide things — and on a
        // phone it cost a row of height plus a keyboard the picker never needs.
        expect(find.text('Search agency…'), findsNothing);
        expect(find.byIcon(Icons.search_rounded), findsNothing);

        // The list it was searching is all still there.
        for (final agency in ['PNP Aparri', 'BFP Aparri', 'DPWH', 'DENR']) {
          expect(find.text(agency), findsOneWidget, reason: agency);
        }
      });
    }
  });

  group('the action bar stands down for the keyboard', () {
    testWidgets('Endorse drops its bar when the keyboard is up', (
      tester,
    ) async {
      await _sized(tester, _kPhone);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () => showEndorseEntityDialog(ctx),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Down: the bar is pinned and reachable.
      expect(find.text('Send Endorsement'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Cancel'), findsOneWidget);

      // Up: it is under the keyboard and unreachable, so it gives the body its
      // height back rather than sitting on top of the keyboard.
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await tester.pumpAndSettle();

      expect(find.text('Send Endorsement'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Cancel'), findsNothing);

      // And it comes straight back.
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();
      expect(find.text('Send Endorsement'), findsOneWidget);
    });

    testWidgets('the bar stays put on a modal, where nothing is covered', (
      tester,
    ) async {
      await _sized(tester, _kDesktop);
      await _open(tester, (ctx) => showEndorseEntityDialog(ctx));

      // `keyboardUp` is gated on the fullscreen form: a desktop modal has room
      // for both, and an on-screen keyboard is not what is being typed on.
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await tester.pumpAndSettle();

      expect(find.text('Send Endorsement'), findsOneWidget);
    });
  });

  group('the phone action buttons are a real tap target', () {
    // Stacked full-width on a phone these are the two biggest controls on the
    // screen, and at 14px of vertical padding they read as thin slabs. They
    // must clear the 48dp Material minimum.
    const minTarget = 48.0;

    testWidgets('Endorse', (tester) async {
      await _sized(tester, _kPhone);
      await _open(tester, (ctx) => showEndorseEntityDialog(ctx));

      final send = tester.getSize(
        find.widgetWithText(FilledButton, 'Send Endorsement'),
      );
      final cancel = tester.getSize(
        find.widgetWithText(OutlinedButton, 'Cancel'),
      );

      expect(send.height, greaterThanOrEqualTo(minTarget));
      expect(cancel.height, greaterThanOrEqualTo(minTarget));
      // Stacked, so both run the full width of the bar.
      expect(send.width, closeTo(cancel.width, 0.5));
    });

    testWidgets('Accept & Assign', (tester) async {
      await _sized(tester, _kPhone);
      await _open(
        tester,
        (ctx) => showAcceptAssignDialog(ctx,
            recommendedOffice: 'Engineering Office'),
      );

      final confirm = tester.getSize(
        find.widgetWithText(FilledButton, 'Confirm & Assign'),
      );
      final cancel = tester.getSize(
        find.widgetWithText(OutlinedButton, 'Cancel'),
      );

      expect(confirm.height, greaterThanOrEqualTo(minTarget));
      expect(cancel.height, greaterThanOrEqualTo(minTarget));
      expect(confirm.width, closeTo(cancel.width, 0.5));
    });

    testWidgets('the modal sits on the Material floor, not above it', (
      tester,
    ) async {
      await _sized(tester, _kDesktop);
      await _open(tester, (ctx) => showEndorseEntityDialog(ctx));

      // The extra height is for the phone's stacked full-width bar. In a modal
      // row the buttons sit at their natural width, where Material's own 48dp
      // floor already applies — so the modal sits exactly ON the minimum while
      // the phone form sits above it.
      final send = tester.getSize(
        find.widgetWithText(FilledButton, 'Send Endorsement'),
      );
      expect(send.height, minTarget);
    });
  });

  group('the two pickers place their actions the same way', () {
    // The request: Accept & Assign should match Endorse. On a phone both stack
    // primary-over-Cancel full width; in a modal both push the pair right.
    //
    // One dialog per test: `_open` pumps a fresh tree, so opening a second in
    // the same test leaves the first mounted over it.
    Future<(Rect primary, Rect cancel)> measure(
      WidgetTester tester,
      Size size,
      void Function(BuildContext) open,
      String primaryLabel,
    ) async {
      await _sized(tester, size);
      await _open(tester, open);
      return (
        tester.getRect(find.widgetWithText(FilledButton, primaryLabel)),
        tester.getRect(find.widgetWithText(OutlinedButton, 'Cancel')),
      );
    }

    testWidgets('phone — Endorse stacks primary above Cancel', (tester) async {
      final (send, cancel) = await measure(
        tester,
        _kPhone,
        (ctx) => showEndorseEntityDialog(ctx),
        'Send Endorsement',
      );
      expect(send.bottom, lessThanOrEqualTo(cancel.top));
      expect(send.width, closeTo(cancel.width, 0.5));
    });

    testWidgets('phone — Accept & Assign stacks the same way', (tester) async {
      final (confirm, cancel) = await measure(
        tester,
        _kPhone,
        (ctx) => showAcceptAssignDialog(ctx,
            recommendedOffice: 'Engineering Office'),
        'Confirm & Assign',
      );
      expect(confirm.bottom, lessThanOrEqualTo(cancel.top));
      expect(confirm.width, closeTo(cancel.width, 0.5));
    });

    testWidgets('modal — Endorse puts Cancel then the primary, right', (
      tester,
    ) async {
      final (send, cancel) = await measure(
        tester,
        _kDesktop,
        (ctx) => showEndorseEntityDialog(ctx),
        'Send Endorsement',
      );
      expect(cancel.right, lessThanOrEqualTo(send.left));
    });

    testWidgets('modal — Accept & Assign does the same', (tester) async {
      final (confirm, cancel) = await measure(
        tester,
        _kDesktop,
        (ctx) => showAcceptAssignDialog(ctx,
            recommendedOffice: 'Engineering Office'),
        'Confirm & Assign',
      );
      expect(
        cancel.right,
        lessThanOrEqualTo(confirm.left),
        reason: 'Cancel leads the primary in both dialogs, pushed right',
      );
    });
  });

  group('the report-process actions are not thin strips', () {
    // DetailActionButton is the shared control behind Accept & Assign, Reject,
    // Endorse and Return to triage in BOTH consoles — the most consequential
    // buttons in the product, several of them irreversible. At 13px of padding
    // alone they came out around 44px and read as strips of colour.
    for (final width in [380.0, 700.0, 1280.0]) {
      testWidgets('DetailActionButton at ${width.toInt()}px', (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: DetailActionButton(
                  label: 'Accept & Assign',
                  icon: Icons.check_rounded,
                  color: const Color(0xFF16A34A),
                  onTap: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester.getSize(find.byType(DetailActionButton)).height,
          greaterThanOrEqualTo(50),
          reason: 'the process actions carry a 50px floor at every width',
        );
      });
    }

    testWidgets('a long label wraps taller rather than clipping', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: 320,
                child: DetailActionButton(
                  // The real staff label, which wraps on a phone.
                  label: 'Not my department — return to triage',
                  icon: Icons.reply_rounded,
                  color: const Color(0xFF2563EB),
                  outlined: true,
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The floor is a MINIMUM, not a fixed height — a wrapped label must be
      // free to grow past it rather than be clipped.
      expect(
        tester.getSize(find.byType(DetailActionButton)).height,
        greaterThanOrEqualTo(50),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('the withdraw confirmation got the same treatment', () {
    // It was the LAST report-process dialog still drawn as a bare AlertDialog:
    // a form with a required text field, so on a phone it had every problem
    // the others were fixed for — a small card floating on a barrier, an
    // action bar sitting on the keyboard, buttons at Material's bare minimum.
    Future<void> openWithdraw(WidgetTester tester, Size size) async {
      await _sized(tester, size);
      await _open(
        tester,
        (ctx) => showEndorseEntityDialog(ctx, currentEndorsement: 'DPWH'),
      );
      await tester.tap(find.text('Clear endorsement'));
      await tester.pumpAndSettle();
    }

    testWidgets('phone — a screen with a chevron, not a floating card', (
      tester,
    ) async {
      await openWithdraw(tester, const Size(400, 1400));

      expect(find.text('Withdraw this endorsement'), findsOneWidget);
      // Two chevrons: the endorse screen underneath and this one on top.
      expect(find.byType(AdminDialogBack), findsNWidgets(2));

      // Full bleed — the content box IS the screen. Measured on the header
      // rather than on `Dialog`, whose own rect always fills the viewport and
      // so would report 400 either way.
      final header = tester.getRect(
        find.text('Withdraw this endorsement'),
      );
      // 60 = the header's own 16px padding + the 32px chevron + the 12px gap
      // it sits beside. Anything much past that means a centred card's inset.
      expect(
        header.left,
        lessThanOrEqualTo(64),
        reason: 'a full-bleed screen starts at the edge, not inset by a '
            'centred card',
      );
    });

    testWidgets('phone — the buttons are stacked and full size', (
      tester,
    ) async {
      await openWithdraw(tester, const Size(400, 1400));

      final withdraw = tester.getRect(
        find.widgetWithText(FilledButton, 'Withdraw'),
      );
      final cancel = tester
          .getRect(find.widgetWithText(OutlinedButton, 'Cancel').last);

      expect(withdraw.bottom, lessThanOrEqualTo(cancel.top));
      expect(withdraw.height, greaterThanOrEqualTo(48));
      expect(cancel.height, greaterThanOrEqualTo(48));
    });

    testWidgets('the reason is still required', (tester) async {
      await openWithdraw(tester, const Size(400, 1400));

      // Disabled until something is typed — withdrawing voids a signed letter
      // and revokes an agency's credential, so the justification is not
      // optional. endorse_dialog_test drives the full resolve path.
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Withdraw'),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('desktop — still a modal', (tester) async {
      await openWithdraw(tester, _kDesktop);

      expect(find.text('Withdraw this endorsement'), findsOneWidget);
      // The endorse dialog's chevron is absent at this width, and the withdraw
      // form adds none of its own.
      expect(find.byType(AdminDialogBack), findsNothing);

      // A centred card, so its title is inset well away from the viewport
      // edge — the opposite of the phone assertion above.
      final header = tester.getRect(
        find.text('Withdraw this endorsement'),
      );
      expect(
        header.left,
        greaterThan(200),
        reason: 'the modal is a centred card, not the whole window',
      );
    });
  });

  group('AdminDialogScreenHeader', () {
    testWidgets('the modal form draws no chevron', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminDialogScreenHeader(
              full: false,
              seal: const SizedBox(width: 40, height: 40),
              title: const Text('Title'),
              description: const Text('Description'),
              padding: EdgeInsets.zero,
            ),
          ),
        ),
      );
      expect(find.byType(AdminDialogBack), findsNothing);
      expect(find.text('Title'), findsOneWidget);
      expect(find.text('Description'), findsOneWidget);
    });

    testWidgets('the screen form draws exactly one', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminDialogScreenHeader(
              full: true,
              seal: const SizedBox(width: 40, height: 40),
              title: const Text('Title'),
              description: const Text('Description'),
              padding: EdgeInsets.zero,
            ),
          ),
        ),
      );
      expect(find.byType(AdminDialogBack), findsOneWidget);
    });
  });
}
