// test/re_endorsement_test.dart
//
// ════════════════════════════════════════════════════════════════════════════
//  "I endorse once, then I try again and the button doesn't do anything."
//
//  ── The defect ──────────────────────────────────────────────────────────
//  Re-endorsing is SUPPORTED and repeatable: endorse_report_to_agency uses
//  `on conflict (report_id) do update`, minting a fresh token and PIN each
//  time (that is what reissues a lost letter, and it voids the old QR). So
//  nothing on the server refused the second attempt. The refusal was a form
//  error nobody could see.
//
//  The cause is an asymmetry between the first and later endorsements:
//
//    FIRST   Send is DISABLED until an agency card is tapped. That tap is
//            partway down the form, so by the time Send is live the admin is
//            already looking at the reason box underneath it.
//
//    LATER   The agency arrives PRESELECTED from the current endorsement, so
//            `canSend` is true the instant the dialog opens. But the reason
//            field is deliberately blank — the old reason justified the old
//            letter — and at 1280x800 it sits at y=772 of 800, with its error
//            text 60px BELOW the fold.
//
//  So: the admin opens a dialog that looks pre-filled, presses the one enabled
//  button, and `_submit` bails at `if (_reasonMissing)`. The red border and the
//  sentence explaining what is missing both render off-screen, inside a scroll
//  view the admin has no reason to scroll. Measured before the fix, the refusal
//  landed off-screen at 1280x800, 1024x768, 412x915 and 360x640 — every size
//  but a full-height 1440x900 desktop. A refusal you cannot see is a dead
//  button.
//
//  A second, quieter bug sat behind it: `_endorse()` read `widget.report` — the
//  row as it stood when the admin TAPPED it — while every render path in the
//  pane reads the live `report` getter. The dialog stays open across an
//  endorsement, so on the second pass the snapshot still said "not endorsed":
//  the picker opened with NOTHING selected and no "Clear endorsement" button,
//  contradicting the "Change endorsement" label the admin had just pressed.
//
//  ── What these tests pin ────────────────────────────────────────────────
//   1. a re-endorsement resolves — as many times as it is asked for;
//   2. the reason is always required, including on a re-endorsement;
//   3. the refusal is ON SCREEN at every width, which is the actual fix;
//   4. the re-endorse notice says a new reason is needed and the printed
//      letter is about to be voided;
//   5. a first endorsement is untouched by any of it.
// ════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/admin/widgets/endorse_entity_dialog.dart';

const _kMissingReason =
    'A reason is required before this report can be endorsed.';

Finder _send() => find.widgetWithText(FilledButton, 'Send Endorsement');
Finder _reasonField() => find.byType(TextField).last;

bool _sendEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(_send()).onPressed != null;

/// The footer reminder, scoped to the footer.
///
/// The top-of-body re-endorse notice also contains the words "reason below", so
/// a bare `textContaining` matches BOTH and the finder throws. The reminder is
/// the tappable one, so it is found through its InkWell.
Finder _reminder() => find.descendant(
      of: find.byType(InkWell),
      matching: find.textContaining(RegExp(r'reason below|written reason')),
    );

/// Opens the dialog the way the report detail pane does. [current] is the
/// agency the report is ALREADY endorsed to — null for a first endorsement.
Future<void> _open(
  WidgetTester tester, {
  String? current,
  Size size = const Size(1280, 800),
  double textScale = 1.0,
  void Function(EndorseChoice?)? onResult,
}) async {
  tester.view.physicalSize = size;
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
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final r = await showEndorseEntityDialog(
                context,
                currentEndorsement: current,
              );
              onResult?.call(r);
            },
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
  // ── 1. The reported symptom ─────────────────────────────────────────────
  //
  // The press must produce a VISIBLE refusal. Asserting the error merely
  // `findsOneWidget` is what let this ship: the widget was in the tree the
  // whole time, just below the fold. Only its rect proves the admin can see
  // it, so that is what is asserted — at the sizes where it was off-screen.
  for (final size in <Size>[
    Size(1440, 900), // full-height desktop — was marginal (y=865 of 900)
    Size(1280, 800), // the common admin laptop — was off-screen
    Size(1024, 768), // small laptop / tablet landscape — was off-screen
    Size(412, 915), // Android phone — was off-screen
    Size(360, 640), // smallest supported phone — was off-screen by 926px
  ]) {
    testWidgets(
      'a refused re-endorsement shows its reason on screen at '
      '${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        EndorseChoice? result = EndorseChoice.clear; // sentinel
        await _open(
          tester,
          current: 'DPWH',
          size: size,
          onResult: (r) => result = r,
        );

        // The preselected agency is what makes Send live with a blank reason —
        // the whole precondition for this bug.
        expect(_sendEnabled(tester), isTrue,
            reason: 'a re-endorsement opens with the agency already selected');

        await tester.tap(_send());
        await tester.pumpAndSettle();

        // It must not have resolved — an endorsement without a reason would be
        // refused by the server anyway.
        expect(result, same(EndorseChoice.clear),
            reason: 'a blank reason must not endorse');

        final err = find.text(_kMissingReason);
        expect(err, findsOneWidget);

        final rect = tester.getRect(err);
        expect(
          rect.top >= 0 && rect.bottom <= size.height,
          isTrue,
          reason: 'the refusal rendered at y=${rect.top.toStringAsFixed(0)}..'
              '${rect.bottom.toStringAsFixed(0)} on a ${size.height.toInt()}px '
              'screen — off-screen, which is why this read as a dead button',
        );
      },
    );
  }

  // ── 2. Re-endorsing works, repeatedly ──────────────────────────────────
  //
  // The point of the feature. The server mints a new token/PIN on conflict, so
  // the client must never be the thing that caps it at one.
  testWidgets('a re-endorsement resolves once a reason is given',
      (tester) async {
    EndorseChoice? result;
    await _open(tester, current: 'DPWH', onResult: (r) => result = r);

    await tester.enterText(
        _reasonField(), 'Reissued — the first letter was lost in transit.');
    await tester.pumpAndSettle();
    await tester.tap(_send());
    await tester.pumpAndSettle();

    expect(result, isNotNull, reason: 'the second endorsement must go through');
    expect(result!.agency, 'DPWH', reason: 'the preselected agency carries');
    expect(result!.reason, 'Reissued — the first letter was lost in transit.');
    expect(result!.isClear, isFalse);
  });

  testWidgets('re-endorsing to a DIFFERENT agency resolves to the new one',
      (tester) async {
    EndorseChoice? result;
    await _open(
      tester,
      current: 'DPWH',
      size: const Size(1100, 1800), // tall: every card reachable by tap()
      onResult: (r) => result = r,
    );

    await tester.tap(find.text('DENR').first);
    await tester.pumpAndSettle();
    await tester.enterText(
        _reasonField(), 'Reassessed as an environmental matter, not a road.');
    await tester.pumpAndSettle();
    await tester.tap(_send());
    await tester.pumpAndSettle();

    expect(result?.agency, 'DENR',
        reason: 'the admin overrode the preselected agency');
  });

  // ── 3. The notice ───────────────────────────────────────────────────────
  //
  // Scrolling the error into view fixes the dead-button symptom, but the admin
  // still needs to know BEFORE pressing that the blank reason is deliberate and
  // that re-sending voids the letter already printed.
  testWidgets('a re-endorsement warns that the printed letter will be voided',
      (tester) async {
    await _open(tester, current: 'DPWH');

    expect(find.textContaining('Already endorsed to DPWH'), findsOneWidget);
    expect(find.textContaining('stops working'), findsOneWidget,
        reason: 'the old letter is voided — the admin must be told');
    expect(find.textContaining('new reason'), findsOneWidget,
        reason: 'the blank reason field is deliberate, and must be explained');
  });

  // ── 4. The first endorsement is unchanged ──────────────────────────────
  testWidgets('a first endorsement shows no re-endorse notice', (tester) async {
    await _open(tester);

    expect(find.textContaining('Already endorsed to'), findsNothing);
    // Send stays disabled until an agency is picked, so the blind press that
    // caused the report is impossible on this path.
    expect(_sendEnabled(tester), isFalse);
  });

  // The pane passes the LIVE row, so a report endorsed moments ago opens its
  // picker already on that agency — matching the "Change endorsement" label the
  // admin pressed. A stale snapshot showed an empty picker and no Clear button.
  testWidgets('the current endorsement is preselected and can be withdrawn',
      (tester) async {
    await _open(tester, current: 'DENR');

    expect(_sendEnabled(tester), isTrue,
        reason: 'preselected from the live row');
    expect(find.text('Clear endorsement'), findsOneWidget,
        reason: 'an endorsed report must offer withdrawal');
  });

  // ── 5. Many endorsements across MANY reports ───────────────────────────
  //
  // The dialog is one widget reused for every report, so anything it keeps
  // between openings — a selection, typed text, a raised error — would bleed
  // from one report onto the next. The reason especially: it is printed
  // verbatim on the letter, so report A's justification appearing on report
  // B's letter would be a real disclosure, not just a cosmetic bug.
  testWidgets('several different reports can each be endorsed repeatedly',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    for (final (label, agency, why) in const [
      ('RPT-A', 'DPWH', 'A: national highway, not municipal.'),
      ('RPT-B', 'DENR', 'B: illegal dumping in a protected zone.'),
      ('RPT-C', 'PNP Aparri', 'C: peace and order concern.'),
    ]) {
      EndorseChoice? first;
      await _open(tester, onResult: (r) => first = r);
      await tester.tap(find.text(agency).first);
      await tester.pumpAndSettle();
      await tester.enterText(_reasonField(), why);
      await tester.pumpAndSettle();
      await tester.tap(_send());
      await tester.pumpAndSettle();

      expect(first, isNotNull, reason: '$label first endorsement must resolve');
      expect(first!.reason, why);

      // Round two on the SAME report, opened on the live agency — no tap, which
      // is the scenario that was reported as a dead button.
      EndorseChoice? second;
      await _open(tester, current: first!.agency, onResult: (r) => second = r);
      await tester.enterText(_reasonField(), '$label reissued: letter lost.');
      await tester.pumpAndSettle();
      await tester.tap(_send());
      await tester.pumpAndSettle();

      expect(second, isNotNull,
          reason: '$label must be endorsable a second time');
      expect(second!.agency, first!.agency);
      expect(second!.reason, '$label reissued: letter lost.',
          reason: '$label must carry its NEW reason, not the previous one');
    }
  });

  testWidgets('a refused endorsement does not poison the next report',
      (tester) async {
    EndorseChoice? refused = EndorseChoice.clear; // sentinel
    await _open(tester, current: 'DPWH', onResult: (r) => refused = r);
    await tester.tap(_send());
    await tester.pumpAndSettle();
    expect(refused, same(EndorseChoice.clear));
    expect(find.text(_kMissingReason), findsOneWidget);

    // Leave via Cancel, as the admin would. NOT pumpWidget: that swaps the
    // tree while the dialog ROUTE is still on the navigator, leaving its
    // frosted barrier (RenderBackdropFilter + RenderAbsorbPointer, from
    // app_dialog) absorbing pointers over the new tree, so the next tap
    // silently never lands.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.pumpAndSettle();

    EndorseChoice? next;
    await _open(tester, current: 'DENR', onResult: (r) => next = r);

    // The previous report's error and its typed reason must both be gone.
    expect(find.text(_kMissingReason), findsNothing,
        reason: "the previous report's error must not open raised");
    expect(
      tester.widget<TextField>(_reasonField()).controller?.text ?? '',
      isEmpty,
      reason: "the previous report's justification is printed on a letter — "
          'it must never appear on another report',
    );

    await tester.enterText(_reasonField(), 'B: a clean, separate endorsement.');
    await tester.pumpAndSettle();
    await tester.tap(_send());
    await tester.pumpAndSettle();

    expect(next?.agency, 'DENR',
        reason: 'a refusal on one report must not block the next');
  });

  // ── 6. The footer reminder ─────────────────────────────────────────────
  //
  // The reminder is the part that keeps the admin from pressing blind in the
  // first place. It lives in the PINNED footer rather than the scroll body,
  // because the body's own copy scrolls away exactly when Send comes into
  // reach. Its job is to be present at every size and scroll position, so its
  // rect is what gets asserted — not merely that the widget exists.
  testWidgets('the reminder appears only while pressing Send would be refused',
      (tester) async {
    // Nothing picked yet: nothing is missing, so no reminder.
    await _open(tester, size: const Size(1100, 1800));
    expect(_reminder(), findsNothing,
        reason: 'the form has not been started — there is nothing to nag about');

    await tester.tap(find.text('DPWH').first);
    await tester.pumpAndSettle();
    expect(_reminder(), findsOneWidget,
        reason: 'agency chosen, reason blank — Send would be refused');

    // It must clear on the FIRST keystroke, not on the next submit. The
    // onChanged handler used to rebuild only `if (_reasonTouched)`, which is
    // false on this path, so the reminder sat there while the admin typed.
    await tester.enterText(_reasonField(), 'A');
    await tester.pumpAndSettle();
    expect(_reminder(), findsNothing,
        reason: 'one keystroke satisfies it — a prompt, not a scold');
  });

  testWidgets('tapping the reminder takes the admin to the reason field',
      (tester) async {
    await _open(tester, current: 'DPWH', size: const Size(1280, 800));

    await tester.tap(_reminder());
    await tester.pumpAndSettle();

    final r = tester.getRect(_reasonField());
    expect(r.top >= 0 && r.bottom <= 800, isTrue,
        reason: 'the reminder names a field that may be off-screen, so it must '
            'also take the admin there — it landed at '
            'y=${r.top.toStringAsFixed(0)}..${r.bottom.toStringAsFixed(0)}');
  });

  // ── 7. Responsiveness: phone, tablet, desktop, at two text scales ──────
  //
  // Swept rather than spot-checked because the failure mode is a function of
  // height × text scale, not width: a 320px phone lays out fine at 1.0 and
  // overflowed by 62px at 1.3. Two real overflows were found this way —
  // one PRE-EXISTING (the footer's three buttons colliding between 768 and
  // 834px on the "Change endorsement" flow) and one introduced by the
  // reminder itself on short phones.
  for (final scale in <double>[1.0, 1.3]) {
    for (final size in <Size>[
      Size(1440, 900), // desktop
      Size(1280, 800), // common admin laptop
      Size(1024, 768), // small laptop
      Size(834, 1112), // iPad portrait — the pre-existing footer overflow
      Size(768, 1024), // smaller tablet — same band
      Size(412, 915), // Android phone
      Size(390, 844), // iPhone
      Size(360, 640), // small Android
      Size(320, 568), // smallest supported
    ]) {
      testWidgets(
          'endorse dialog lays out clean at '
          '${size.width.toInt()}x${size.height.toInt()} @${scale}x',
          (tester) async {
        // The re-endorse flow: the widest footer (Clear + Cancel + Send) AND
        // the reminder, i.e. the worst case for both overflows.
        await _open(tester, current: 'DPWH', size: size, textScale: scale);

        expect(tester.takeException(), isNull,
            reason: 'overflow at ${size.width.toInt()}x'
                '${size.height.toInt()} @${scale}x');

        // Send and Cancel must be reachable at every size — they are the way
        // out of the dialog.
        expect(_send(), findsOneWidget);
        expect(find.widgetWithText(OutlinedButton, 'Cancel'), findsOneWidget);

        // Where the reminder shows, it must be genuinely on screen. On the
        // smallest phone at large text it deliberately stands down rather than
        // overflow — the body notice and the scroll-on-refusal still cover
        // that case, so its absence there is correct, not a miss.
        if (_reminder().evaluate().isNotEmpty) {
          final r = tester.getRect(_reminder());
          expect(r.top >= 0 && r.bottom <= size.height, isTrue,
              reason: 'the reminder is pinned — it must never render '
                  'off-screen (was y=${r.top.toStringAsFixed(0)}..'
                  '${r.bottom.toStringAsFixed(0)})');
        }
      });
    }
  }

  // The refusal path has to stay visible at every size too, not just at the
  // five widths the original bug was measured at.
  for (final size in <Size>[
    Size(834, 1112),
    Size(768, 1024),
    Size(390, 844),
    Size(320, 568),
  ]) {
    testWidgets(
        'a refused re-endorsement still reveals its reason at '
        '${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      await _open(tester, current: 'DPWH', size: size);
      await tester.tap(_send());
      await tester.pumpAndSettle();

      final rect = tester.getRect(find.text(_kMissingReason));
      expect(rect.top >= 0 && rect.bottom <= size.height, isTrue,
          reason: 'refusal at y=${rect.top.toStringAsFixed(0)}..'
              '${rect.bottom.toStringAsFixed(0)} on a '
              '${size.height.toInt()}px screen');
    });
  }
}
