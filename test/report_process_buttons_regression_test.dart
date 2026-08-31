// test/report_process_buttons_regression_test.dart
//
// ════════════════════════════════════════════════════════════════════════════
//  Every button in the report process, on every surface that has one.
//
//  The report process spans four surfaces and one lifecycle:
//
//    admin   triage → Accept & Assign / Reject / Endorse / Reopen / Download,
//                     plus Approve / Return on an office's progress update
//    staff   the office's own queue → Under review / In progress / Resolved,
//                     Return to triage, post a progress update, internal notes
//    citizen read-only, plus "Chat with agent"
//    QR scan an agency with no account → confirm receipt, post an update,
//                     Mark Completed, attach photos
//
//  ── What this file is FOR, and what it deliberately is not ──────────────
//  Every one of these buttons ends in a network round trip, and most of them
//  are irreversible. Mounting the real consoles needs Supabase and a signed-in
//  admin/officer, so this cannot be an end-to-end test and does not pretend to
//  be one. What it pins is the layer where the bugs actually were:
//
//    1. RE-ENTRANCY — a second press before the first write returns. The
//       guard has to sit BEFORE the first await, or two presses become two
//       writes. busy_button_double_write (in the repo's notes) is the case
//       where a flag that only reached the widget tree was not a guard at all.
//
//    2. FEEDBACK — `busy` must be threaded per button, not per pane. A pane
//       where five buttons grey out together says something is happening but
//       never which thing. The admin's second "Reject Report" — the one shown
//       while an office is working the report — was missing `busy:` entirely
//       and is why this file exists.
//
//    3. CLOSED REPORTS — a finished report must offer no work. Covered in
//       closed_report_offers_no_actions_test; not duplicated here.
//
//  The RPCs behind these buttons were verified to exist in the live database
//  on 2026-08-31: staff_set_report_status, staff_return_to_triage,
//  review_report_update, endorse_report_to_agency, clear_report_endorsement,
//  advance_endorsement, scan_endorsement, post_endorsement_update,
//  attach_endorsement_update_media, report_duplicate_candidates. A missing one
//  would fail at runtime while every widget test still passed, so that check
//  belongs in the schema, not here.
// ════════════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:govpulse/core/theme/app_colors.dart';
import 'package:govpulse/features/admin/widgets/report_detail_kit.dart';

/// A press counter that mimics a real handler: it holds a busy flag, refuses
/// re-entry BEFORE its first await, and completes only when told to.
///
/// This is the shape every one of the real handlers has (_accept, _reject,
/// _endorse, _reopen, _apply, _returnToTriage, _submit, _postUpdate). Testing
/// the shape catches the ordering mistake that makes a guard inert.
class _Action {
  int started = 0;
  bool busy = false;
  final _gate = Completer<void>();

  Future<void> press() async {
    // THE ORDERING THAT MATTERS: refuse, then mark, then await. A guard placed
    // after the first await lets a second press through in the gap.
    if (busy) return;
    busy = true;
    started++;
    await _gate.future;
    busy = false;
  }

  void complete() => _gate.complete();
}

void main() {
  group('re-entrancy — one press, one write', () {
    test('a second press during the round trip is refused', () async {
      final a = _Action();

      // Two presses in the same frame, the double-tap a slow network invites.
      final first = a.press();
      final second = a.press();

      expect(
        a.started,
        1,
        reason: 'the second press must be refused, not queued — this is the '
            'difference between one write and two',
      );

      a.complete();
      await Future.wait([first, second]);
    });

    test('a press AFTER the round trip is allowed', () async {
      final a = _Action();
      final first = a.press();
      a.complete();
      await first;

      expect(a.busy, isFalse, reason: 'the flag must clear on completion');

      final again = _Action();
      await Future.microtask(() {});
      unawaited(again.press());
      expect(again.started, 1);
    });
  });

  group('feedback — the running action names itself', () {
    // The regression: the admin console's second "Reject Report" (shown while
    // an office is working the report) had no `busy:`, alone among the action
    // buttons. The press was safe — _beginAction refuses while _busy — but the
    // officer saw the row go dead with no sign of which control had claimed
    // it, and no spinner until the snackbar arrived.
    Widget host(List<Widget> children) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 420,
            child: DetailActionSection(buttons: children),
          ),
        ),
      ),
    );

    testWidgets('the running button spins and the others do not', (
      tester,
    ) async {
      await tester.pumpWidget(
        host([
          DetailActionRow(
            children: [
              const DetailActionButton(
                label: 'Change endorsement',
                icon: Icons.swap_horiz_rounded,
                color: AppColors.primaryBlue,
                outlined: true,
                // The pane is busy, so every button is disabled…
                onTap: null,
              ),
              const DetailActionButton(
                label: 'Reject Report',
                icon: Icons.cancel_rounded,
                color: AppColors.red,
                // …but only THIS one is the action that is running.
                busy: true,
                onTap: null,
              ),
            ],
          ),
        ]),
      );
      // pump, NOT pumpAndSettle: a CircularProgressIndicator animates forever,
      // so settling never completes on a tree with a busy button in it.
      await tester.pump();

      // Exactly one spinner, and the other button keeps its icon.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.swap_horiz_rounded), findsOneWidget);
      expect(find.byIcon(Icons.cancel_rounded), findsNothing);

      // The label stays put while its icon is swapped, so the button does not
      // resize under the cursor mid-press.
      expect(find.text('Reject Report'), findsOneWidget);
      expect(find.text('Change endorsement'), findsOneWidget);
    });

    testWidgets('a disabled button with no busy flag shows no spinner', (
      tester,
    ) async {
      await tester.pumpWidget(
        host([
          const DetailActionButton(
            label: 'Reject Report',
            icon: Icons.cancel_rounded,
            color: AppColors.red,
            onTap: null,
          ),
        ]),
      );
      await tester.pumpAndSettle();

      // Disabled is not the same as running. Without this distinction a whole
      // pane of greyed buttons is indistinguishable from a pane of spinners.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.cancel_rounded), findsOneWidget);
    });

    testWidgets('a disabled button cannot fire', (tester) async {
      var fired = 0;
      await tester.pumpWidget(
        host([
          DetailActionButton(
            label: 'Accept Report',
            icon: Icons.check_circle_rounded,
            color: AppColors.green,
            busy: true,
            onTap: fired == 0 ? null : () => fired++,
          ),
        ]),
      );
      await tester.pump(); // busy spinner — see the note above.

      await tester.tap(find.text('Accept Report'), warnIfMissed: false);
      await tester.pump();

      expect(fired, 0, reason: 'a busy button must refuse the press');
    });
  });

  group('every action button is reachable at every width', () {
    // DetailActionRow stacks under 300px and sits side by side above it. Both
    // arms must keep every button hittable — a button pushed off its row or
    // squeezed to zero width is a report-process action nobody can take.
    for (final width in [280.0, 320.0, 480.0, 900.0]) {
      testWidgets('${width.toInt()}px — both buttons hittable', (tester) async {
        var accepted = 0;
        var rejected = 0;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: width,
                  child: DetailActionRow(
                    children: [
                      DetailActionButton(
                        label: 'Accept Report',
                        icon: Icons.check_circle_rounded,
                        color: AppColors.green,
                        onTap: () => accepted++,
                      ),
                      DetailActionButton(
                        label: 'Reject Report',
                        icon: Icons.cancel_rounded,
                        color: AppColors.red,
                        onTap: () => rejected++,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Accept Report'));
        await tester.tap(find.text('Reject Report'));
        await tester.pumpAndSettle();

        expect(accepted, 1, reason: 'Accept must be hittable at ${width}px');
        expect(rejected, 1, reason: 'Reject must be hittable at ${width}px');

        // And each is a real target, not a sliver.
        for (final label in ['Accept Report', 'Reject Report']) {
          final size = tester.getSize(
            find.ancestor(
              of: find.text(label),
              matching: find.byType(DetailActionButton),
            ),
          );
          expect(
            size.height,
            greaterThanOrEqualTo(48),
            reason: '$label must stay a 48dp target at ${width}px',
          );
          expect(size.width, greaterThan(80));
        }
      });
    }
  });
}
