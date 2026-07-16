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
Set<ReportBucket> _bucketsOf(AdminReport r) =>
    {for (final b in ReportBucket.values) if (reportInBucket(r, b)) b};

void main() {
  test('a freshly filed report is the admin\'s to-do', () {
    expect(
      _bucketsOf(_report()),
      {ReportBucket.all, ReportBucket.needsTriage},
    );
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

  test('endorsing hands it out of the LGU queue entirely', () {
    // Endorsed rows drop out of All: they are not the LGU's work any more, so
    // counting them in the live queue would overstate the backlog.
    final r = _report(status: ReportStatus.underReview, endorsedTo: 'DPWH');
    expect(_bucketsOf(r), {ReportBucket.endorsed});
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
}
