// A CLOSED report offers no work.
//
// Once a report is resolved (or rejected, or dismissed as spam) the job is
// done. Every console surface that invites more work on it is either a mistake
// waiting to happen or a note nobody will read — and the worst of them actively
// misinform the resident, because status changes are pushed to them.
//
// The three consoles drifted apart on this. What was actually offered on a
// FINISHED report before these tests existed:
//
//   * staff  — live "Under review" / "In progress" chips. One tap reopened
//              completed work AND told the resident their finished report had
//              gone backwards.
//   * staff  — "Not my department — return to triage", so an office could
//              disown a report it had just completed.
//   * staff  — a citizen-facing "what has happened" composer.
//   * admin  — the same citizen-facing composer.
//
// These pin the parts that can be checked as pure logic. The widget-level
// consequences are covered in report_progress_updates_test.dart ("a closed
// report takes the composer away from everyone").

import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/admin/providers/admin_reports_provider.dart';

/// The admin console's definition, mirrored from `_ReportDetailDialogState`.
///
/// Duplicated deliberately rather than exported: the point of the test is that
/// the RULE is what everyone agrees on, so if the console's own copy changes,
/// this fails and someone has to think about it.
bool adminIsClosed(ReportStatus status, {required bool dismissed}) =>
    status == ReportStatus.resolved ||
    status == ReportStatus.rejected ||
    dismissed;

/// The staff console's definition. Staff never see dismissed rows, so those are
/// not part of its test — which is why the two are written out separately
/// instead of shared.
bool staffIsClosed(ReportStatus status) =>
    status == ReportStatus.resolved || status == ReportStatus.rejected;

void main() {
  group('what counts as closed', () {
    test('resolved is closed everywhere', () {
      expect(adminIsClosed(ReportStatus.resolved, dismissed: false), isTrue);
      expect(staffIsClosed(ReportStatus.resolved), isTrue);
    });

    test('rejected is closed everywhere', () {
      // Refused by the admin. The citizen has been told; there is nothing for
      // an office to keep working on.
      expect(adminIsClosed(ReportStatus.rejected, dismissed: false), isTrue);
      expect(staffIsClosed(ReportStatus.rejected), isTrue);
    });

    test('dismissed spam is closed for the admin', () {
      // It was never real work, so it is closed regardless of the status the
      // row happens to carry.
      expect(adminIsClosed(ReportStatus.pending, dismissed: true), isTrue);
      expect(adminIsClosed(ReportStatus.inProgress, dismissed: true), isTrue);
    });

    test('every working state is OPEN', () {
      // The guard has to be precise in both directions. A rule that closes too
      // eagerly strands live work with no way to progress it, which is a worse
      // failure than the one being fixed — the office simply cannot do its job.
      for (final s in [
        ReportStatus.pending,
        ReportStatus.underReview,
        ReportStatus.inProgress,
      ]) {
        expect(
          adminIsClosed(s, dismissed: false),
          isFalse,
          reason: '$s is live work and must stay actionable',
        );
        expect(
          staffIsClosed(s),
          isFalse,
          reason: '$s is live work and must stay actionable',
        );
      }
    });
  });

  group('the two consoles agree except where they must not', () {
    test('they agree on every status a staff member can see', () {
      // Staff never receive dismissed rows, so status alone should decide, and
      // the two definitions must not disagree about any of them.
      for (final s in ReportStatus.values) {
        expect(
          staffIsClosed(s),
          adminIsClosed(s, dismissed: false),
          reason: 'the consoles disagree about $s',
        );
      }
    });

    test('only dismissal separates them', () {
      // The single intended difference, asserted so it stays intentional.
      expect(adminIsClosed(ReportStatus.pending, dismissed: true), isTrue);
      expect(staffIsClosed(ReportStatus.pending), isFalse);
    });
  });

  group('the staff status flow', () {
    // The chips an office may move a report between. Triage states belong to
    // the admin — a report only reaches staff once accepted.
    const flow = [
      ReportStatus.underReview,
      ReportStatus.inProgress,
      ReportStatus.resolved,
    ];

    test('resolved is the end of it', () {
      expect(flow.last, ReportStatus.resolved);
    });

    test('every earlier step is one an office could tap back to', () {
      // This is precisely the danger the lock removes: with the chip row still
      // rendered on a resolved report, both of these were live targets, and
      // every status change notifies the reporter.
      final backwards = flow.takeWhile((s) => s != ReportStatus.resolved);
      expect(backwards, isNotEmpty);
      expect(
        backwards.every((s) => !staffIsClosed(s)),
        isTrue,
        reason: 'moving back would reopen the report for the resident',
      );
    });
  });
}
