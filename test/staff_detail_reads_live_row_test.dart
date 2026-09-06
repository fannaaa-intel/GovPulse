// test/staff_detail_reads_live_row_test.dart
//
// ════════════════════════════════════════════════════════════════════════════
//  The staff report detail rendered a SNAPSHOT, so a report closed underneath
//  it still offered work.
//
//  ── The defect ──────────────────────────────────────────────────────────
//  `_ReportDetailState` seeds `_status` from `widget.report.status` once, and
//  every other pane reads `widget.report` directly. Both are the row as it
//  stood when the officer TAPPED it. But the detail stays open across:
//
//    * the queue's own 30s interval poll, and
//    * the console's silentRefresh on tab switch / report events,
//
//  and — critically — across writes made by SOMEONE ELSE. The admin rejecting a
//  report, or another officer in the same office resolving it, both land in the
//  queue on the next poll. The open detail never hears about it.
//
//  What that leaves on screen, on a report that is already CLOSED:
//    * live "Under review" / "In progress" chips — one tap reopens finished
//      work and pushes a backwards status change to the resident;
//    * "Not my department — return to triage", so an office can disown a
//      report the admin already refused;
//    * the citizen-facing progress composer and the internal note box.
//
//  `_isClosed` is the guard that is supposed to remove all four, and it is
//  correct — it is reading a stale status, so it never fires.
//
//  The admin console does not have this bug: `_ReportDetailDialogState.report`
//  re-reads the row through `byId(widget.report.id)` on every render path,
//  precisely so the panes describe the report as it stands NOW. The staff
//  console has no equivalent.
//
//  ── What these tests pin ────────────────────────────────────────────────
//  The lookup rule, as pure logic: a detail must resolve its row out of the
//  live queue by id, and fall back to the snapshot only when the row has left
//  the queue entirely (returned to triage, re-endorsed elsewhere) — never
//  render a stale copy of a row that is still there.
// ════════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/admin/providers/admin_reports_provider.dart'
    show ReportStatus;
import 'package:govpulse/features/staff/data/staff_repository.dart';

StaffReport _report({
  String id = 'r1',
  ReportStatus status = ReportStatus.underReview,
  String? assigned = 'Engineering Office',
  String? endorsed,
}) =>
    StaffReport(
      id: id,
      shortId: id.toUpperCase(),
      categoryKey: 'road',
      category: 'Road',
      barangay: 'Centro',
      address: null,
      remarks: 'pothole',
      status: status,
      isAnonymous: false,
      mediaCount: 0,
      createdAt: DateTime.now(),
      endorsedToDepartment: endorsed,
      assignedToDepartment: assigned,
      assignedAt: DateTime.now(),
    );

/// The rule the staff detail must follow, mirrored here the way
/// closed_report_offers_no_actions_test.dart mirrors `_isClosed`: if the
/// console's own copy changes, this fails and someone has to think about it.
StaffReport liveRow(List<StaffReport> queue, StaffReport snapshot) {
  for (final r in queue) {
    if (r.id == snapshot.id) return r;
  }
  return snapshot;
}

bool staffIsClosed(ReportStatus s) =>
    s == ReportStatus.resolved || s == ReportStatus.rejected;

void main() {
  group('the detail resolves its row out of the live queue', () {
    test('a report REJECTED by the admin while open reads as closed', () {
      // The officer opened it while it was live work.
      final snapshot = _report(status: ReportStatus.underReview);
      // The admin refused it; the next poll brought that home.
      final queue = [_report(status: ReportStatus.rejected)];

      expect(
        staffIsClosed(snapshot.status),
        isFalse,
        reason: 'the snapshot is what the bug renders from',
      );
      expect(
        staffIsClosed(liveRow(queue, snapshot).status),
        isTrue,
        reason: 'a refused report must take the status chips and the '
            'return-to-triage button away',
      );
    });

    test('a report RESOLVED by a colleague in the same office reads as closed',
        () {
      // Two officers share a department queue, so both can have the same
      // report open. The second must not be able to reopen it.
      final snapshot = _report(status: ReportStatus.inProgress);
      final queue = [_report(status: ReportStatus.resolved)];

      expect(staffIsClosed(liveRow(queue, snapshot).status), isTrue);
    });

    test('live work stays actionable — the guard must not close too eagerly',
        () {
      // The opposite failure is worse: an office that cannot progress its own
      // work. A status that merely MOVED is still open.
      final snapshot = _report(status: ReportStatus.underReview);
      final queue = [_report(status: ReportStatus.inProgress)];

      final live = liveRow(queue, snapshot);
      expect(live.status, ReportStatus.inProgress);
      expect(staffIsClosed(live.status), isFalse);
    });
  });

  group('falling back to the snapshot', () {
    test('a row that has LEFT the queue falls back rather than vanishing', () {
      // returnToTriage nulls both department columns, so the row drops out of
      // this office's queue entirely. The detail is still on screen; it must
      // keep rendering the report it was opened on rather than throwing.
      final snapshot = _report(status: ReportStatus.underReview);
      expect(liveRow(const [], snapshot).id, snapshot.id);
      expect(liveRow(const [], snapshot).status, ReportStatus.underReview);
    });

    test('another report in the queue is never mistaken for this one', () {
      final snapshot = _report(id: 'r1');
      final queue = [_report(id: 'r2', status: ReportStatus.resolved)];
      expect(liveRow(queue, snapshot).id, 'r1');
      expect(liveRow(queue, snapshot).status, ReportStatus.underReview);
    });
  });

  group('a close landing mid-action is refused, not silently dropped', () {
    // Both writes on this pane open a dialog or await a round trip first, so a
    // close can land in the gap between the officer reading the screen and the
    // write going out. The guard is the same in both places; what differs is
    // how wide the window is.
    test('a status change is refused once the live row reads closed', () {
      final snapshot = _report(status: ReportStatus.underReview);
      final queue = [_report(status: ReportStatus.rejected)];
      expect(staffIsClosed(liveRow(queue, snapshot).status), isTrue);
    });

    test('return-to-triage is refused once the live row reads closed', () {
      // The widest window: the reason dialog stands open while the officer
      // types. Bouncing a rejected report back to triage would reopen it.
      final snapshot = _report(status: ReportStatus.inProgress);
      final queue = [_report(status: ReportStatus.rejected)];
      expect(staffIsClosed(liveRow(queue, snapshot).status), isTrue);
    });

    test('neither is refused while the report is genuinely still open', () {
      final snapshot = _report(status: ReportStatus.underReview);
      final queue = [_report(status: ReportStatus.underReview)];
      expect(staffIsClosed(liveRow(queue, snapshot).status), isFalse);
    });
  });

  group('the routing columns are read live too, not just the status', () {
    test('a report re-endorsed away from this office reflects the new owner',
        () {
      // The admin endorsing an ASSIGNED report clears assigned_to_department
      // and sets endorsed_to_department (endorse_report_to_agency mirrors both
      // onto the row). An internal office's open detail showed it as still
      // theirs.
      final snapshot = _report(assigned: 'Engineering Office');
      final queue = [_report(assigned: null, endorsed: 'DPWH')];

      final live = liveRow(queue, snapshot);
      expect(live.assignedToDepartment, isNull);
      expect(live.endorsedToDepartment, 'DPWH');
    });
  });
}
