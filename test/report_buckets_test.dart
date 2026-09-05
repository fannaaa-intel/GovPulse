// The bucket rules behind the Reports list's tabs. These are the definition of
// which pile a report lands in, so they're worth pinning independently of the
// widget: a report showing up in the wrong tab (or in two contradictory ones)
// would quietly mislead an admin about what's waiting on them.

import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/admin/providers/admin_reports_provider.dart';

AdminReport _report({
  ReportStatus status = ReportStatus.pending,
  String? assignedTo,
  String? endorsedTo,
  bool dismissed = false,
}) {
  return AdminReport(
    id: 'id',
    shortId: 'AAAAAAAA',
    categoryKey: 'road',
    category: 'Road & Infrastructure',
    barangay: 'Brgy. Maura',
    address: 'Zone 1',
    remarks: '',
    status: status,
    isAnonymous: false,
    submitterName: 'Mark Reduca',
    submitterPhotoUrl: null,
    submitterRole: 'citizen',
    mediaCount: 0,
    createdAt: DateTime(2026, 7, 15),
    assignedToDepartment: assignedTo,
    assignedAt: assignedTo == null ? null : DateTime(2026, 7, 15),
    endorsedToDepartment: endorsedTo,
    endorsedAt: endorsedTo == null ? null : DateTime(2026, 7, 15),
    dismissedAt: dismissed ? DateTime(2026, 7, 15) : null,
  );
}

/// Every bucket [r] belongs to, for readable whole-set assertions.
Set<ReportBucket> _bucketsOf(AdminReport r) => {
  for (final b in ReportBucket.values)
    if (reportInBucket(r, b)) b,
};

void main() {
  test('a freshly filed report is the admin\'s to-do', () {
    expect(_bucketsOf(_report()), {ReportBucket.all, ReportBucket.needsTriage});
  });

  test('accepting into an office moves it from triage to working', () {
    final r = _report(
      status: ReportStatus.underReview,
      assignedTo: 'Engineering Office',
    );
    expect(_bucketsOf(r), {ReportBucket.all, ReportBucket.working});
  });

  test('in progress is still working', () {
    final r = _report(
      status: ReportStatus.inProgress,
      assignedTo: 'Engineering Office',
    );
    expect(_bucketsOf(r), {ReportBucket.all, ReportBucket.working});
  });

  test('resolved leaves working and lands in resolved', () {
    final r = _report(
      status: ReportStatus.resolved,
      assignedTo: 'Engineering Office',
    );
    expect(_bucketsOf(r), {ReportBucket.all, ReportBucket.resolved});
  });

  test('a rejected report is closed — neither working nor resolved', () {
    final r = _report(status: ReportStatus.rejected);
    expect(_bucketsOf(r), {ReportBucket.all});
  });

  test('endorsing moves it out of the LGU piles but NOT out of All', () {
    // CHANGED 2026-08-31. All used to exclude endorsed rows, on the reasoning
    // that they were no longer the LGU's work. Two things broke because of it:
    // the count on the All tab silently omitted work the municipality is still
    // answerable for, and a progress-update notification deep-linked to a
    // report the page could not display — the highlight found no row and the
    // tap did nothing at all, which read as a broken notification.
    //
    // All now means all. `working` and `resolved` stay LGU-scoped, because the
    // Endorsed tab answers the same question for the agency.
    final r = _report(status: ReportStatus.underReview, endorsedTo: 'DPWH');
    expect(_bucketsOf(r), {ReportBucket.all, ReportBucket.endorsed});
  });

  test('dismissed spam only ever appears in its own bucket', () {
    final r = _report(dismissed: true);
    expect(_bucketsOf(r), {ReportBucket.dismissed});
  });

  test('dismissing beats every other bucket, even when endorsed', () {
    final r = _report(endorsedTo: 'DPWH', dismissed: true);
    expect(_bucketsOf(r), {ReportBucket.dismissed});
  });

  test('a pending but already-assigned report is not on the triage desk', () {
    // Assigned means an admin already accepted it, so it is nobody's to-do even
    // though the status hasn't moved yet.
    final r = _report(assignedTo: 'Engineering Office');
    expect(_bucketsOf(r), {ReportBucket.all});
  });

  group('the piles an admin switches between are exclusive', () {
    // All deliberately overlaps (it's the live queue). The rest must not: a
    // report in two tabs at once would be counted twice.
    final exclusive = ReportBucket.values
        .where((b) => b != ReportBucket.all)
        .toList();

    final samples = <String, AdminReport>{
      'filed': _report(),
      'assigned': _report(assignedTo: 'Engineering Office'),
      'under review': _report(
        status: ReportStatus.underReview,
        assignedTo: 'Engineering Office',
      ),
      'in progress': _report(
        status: ReportStatus.inProgress,
        assignedTo: 'Engineering Office',
      ),
      'resolved': _report(
        status: ReportStatus.resolved,
        assignedTo: 'Engineering Office',
      ),
      'rejected': _report(status: ReportStatus.rejected),
      'endorsed': _report(endorsedTo: 'DPWH'),
      'dismissed': _report(dismissed: true),
    };

    for (final entry in samples.entries) {
      test('${entry.key} sits in at most one', () {
        final hits = exclusive.where((b) => reportInBucket(entry.value, b));
        expect(hits.length, lessThanOrEqualTo(1), reason: '$hits');
      });
    }
  });

  // ── The deep-link reachability contract ────────────────────────────────────
  //
  // AdminReportsNotifier.revealReport walks the buckets in tab order to find one
  // that holds the report a notification points at, so the row can be shown and
  // flashed. Its first candidate is `all`. If `all` ever stops holding a live
  // report again, that tap silently goes back to doing nothing — the exact
  // failure this replaced, and one no widget test would catch because nothing
  // throws and nothing looks wrong.
  //
  // So the property is pinned here, on the pure rules, rather than left to be
  // rediscovered from a screenshot.
  group('every live report is reachable from All', () {
    final live = <String, AdminReport>{
      'pending': _report(),
      'assigned': _report(assignedTo: 'Engineering Office'),
      'under review': _report(
        status: ReportStatus.underReview,
        assignedTo: 'Engineering Office',
      ),
      'in progress': _report(
        status: ReportStatus.inProgress,
        assignedTo: 'Engineering Office',
      ),
      'resolved': _report(
        status: ReportStatus.resolved,
        assignedTo: 'Engineering Office',
      ),
      'rejected': _report(status: ReportStatus.rejected),
      'endorsed': _report(endorsedTo: 'DPWH'),
      'endorsed and in progress': _report(
        status: ReportStatus.inProgress,
        endorsedTo: 'DPWH',
      ),
    };

    for (final entry in live.entries) {
      test('${entry.key} is in All', () {
        expect(reportInBucket(entry.value, ReportBucket.all), isTrue);
      });
    }

    test('dismissed spam is the one live-ish row All still excludes', () {
      expect(
        reportInBucket(_report(dismissed: true), ReportBucket.all),
        isFalse,
      );
    });
  });

  // The header sits directly above the bucket rail, so the two have to agree.
  // They didn't: the header counted every non-duplicate row (dismissed spam
  // included) while `all` excluded dismissed, so a console with one dismissed
  // report read "4 reports" over an `All` pill showing 3 — and no tab the
  // admin could press accounted for the missing one. Counts are how they judge
  // whether the queue is being worked, so a phantom row is not cosmetic.
  test('the header total and the All tab count the same ledger', () {
    final rows = [
      _report(),
      _report(status: ReportStatus.inProgress, assignedTo: 'Engineering'),
      _report(status: ReportStatus.resolved, assignedTo: 'Engineering'),
      _report(dismissed: true),
    ];

    // What the All tab shows.
    final inAll = rows.where((r) => reportInBucket(r, ReportBucket.all)).length;
    // What the header shows, by the same rule the provider now applies.
    final header = rows.where((r) => !r.isDuplicate && !r.isDismissed).length;

    expect(inAll, 3, reason: 'dismissed spam stays out of the working queue');
    expect(
      header,
      inAll,
      reason:
          'the header promised a report the bucket rail cannot show — the '
          'admin has no tab to press to find it',
    );
  });

  test('a dismissed report is reachable in exactly the Dismissed tab', () {
    // The row is not lost, just moved: it must still be findable, which is
    // what makes excluding it from the header honest rather than a cover-up.
    expect(_bucketsOf(_report(dismissed: true)), {ReportBucket.dismissed});
  });
}
