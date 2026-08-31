// test/report_process_lifecycle_test.dart
//
// ════════════════════════════════════════════════════════════════════════════
//  The report process, as a state machine and a set of write payloads.
//
//  A report moves through four surfaces:
//
//      citizen files it
//          -> pending ................. the admin's triage desk
//      admin ACCEPTS into an office
//          -> under_review ............ the office can now see it
//      office works it
//          -> in_progress -> resolved
//
//  with three ways out of the middle: the admin REJECTS (terminal, citizen
//  notified), the admin ENDORSES to an outside agency (the QR + PIN handoff),
//  or the office RETURNS it to triage because it is not theirs.
//
//  ── What these tests are, and are not ─────────────────────────────────────
//  Every one of these actions is a network write, and mounting the real
//  consoles needs Supabase and a signed-in admin/officer. So this is NOT an
//  end-to-end test and does not pretend to be one.
//
//  What it pins is the layer that decides what gets WRITTEN — the status
//  vocabulary, the exact payload of each transition, and which fields each one
//  is obliged to clear. That layer is where a silent bug does the most damage:
//  a missing `endorsed_to_department: null` on accept does not throw, does not
//  fail a widget test, and leaves a report both assigned to an office AND
//  endorsed to an agency, with two parties believing they own it.
//
//  The payloads below are transcribed from AdminReportsNotifier and from the
//  live function bodies of staff_return_to_triage and
//  endorse_report_to_agency (read 2026-09-01). Transcribed deliberately rather
//  than imported: if someone edits a payload, this file disagrees and a human
//  has to decide which is right — the same reasoning triage_write_degradation
//  _test.dart uses for its own duplicated predicate.
//
//  ── Verified live, and why it is not repeated here ────────────────────────
//  Two questions were answered against the real database on a rolled-back
//  transaction, and the findings are encoded as tests at the bottom:
//
//    * re-endorsing MINTS A NEW token and PIN and destroys the old row
//      (UNIQUE(report_id) + ON CONFLICT DO UPDATE), so a previously printed
//      QR scans as invalid. Measured: old token valid=true before, false after.
//
//    * reopening a rejected report does NOT wipe the work done before it was
//      rejected. report_updates and report_notes are separate tables and
//      reopen touches only six columns on `reports`. Measured: 2 updates and
//      4 notes, unchanged across reject -> reopen.
// ════════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';

import 'package:govpulse/features/admin/providers/admin_reports_provider.dart'
    show
        EndorsementCredentials,
        ReportStatus,
        reportStatusFromDb,
        reportStatusLabel,
        reportStatusToDb;
import 'package:govpulse/features/admin/widgets/endorse_entity_dialog.dart'
    show EndorseChoice;

// ── The payloads, transcribed from the production write paths ──────────────

/// AdminReportsNotifier.accept — admin takes a pending report INTO an office.
Map<String, dynamic> acceptPayload(String department, String now, String? uid) =>
    {
      'assigned_to_department': department,
      'assigned_at': now,
      'assigned_by': uid,
      // Accepting internally CANCELS any external endorsement.
      'endorsed_to_department': null,
      'endorsed_at': null,
      'endorsed_by': null,
      'status': reportStatusToDb(ReportStatus.underReview),
    };

/// AdminReportsNotifier.reject — terminal, with a citizen-facing reason.
Map<String, dynamic> rejectPayload(String note) => {
  'status': reportStatusToDb(ReportStatus.rejected),
  'rejection_note': note.trim(),
};

/// AdminReportsNotifier.reopen — back to the triage desk, unowned.
Map<String, dynamic> reopenPayload() => {
  'status': reportStatusToDb(ReportStatus.pending),
  'rejection_note': null,
  'assigned_to_department': null,
  'assigned_at': null,
  'endorsed_to_department': null,
  'endorsed_at': null,
};

/// public.staff_return_to_triage — the office hands a mis-routed report back.
Map<String, dynamic> returnToTriagePayload() => {
  'status': 'pending',
  'assigned_to_department': null,
  'endorsed_to_department': null,
};

void main() {
  // ══ 1. The status vocabulary ═════════════════════════════════════════════
  //
  // Two vocabularies exist — the Dart enum and the DB's snake_case strings —
  // and every write crosses between them. A mismatch here is a status that
  // silently never applies.
  group('the status vocabulary round-trips', () {
    const dbNames = {
      ReportStatus.pending: 'pending',
      ReportStatus.underReview: 'under_review',
      ReportStatus.inProgress: 'in_progress',
      ReportStatus.resolved: 'resolved',
      ReportStatus.rejected: 'rejected',
    };

    test('every status has a DB name, and it survives the round trip', () {
      // Iterating ReportStatus.values rather than the map's keys: adding a
      // sixth status without a DB name fails here rather than at runtime.
      for (final s in ReportStatus.values) {
        expect(
          dbNames.containsKey(s),
          isTrue,
          reason: '$s has no DB name — every status must be storable',
        );
        expect(reportStatusToDb(s), dbNames[s]);
        expect(reportStatusFromDb(dbNames[s]), s);
      }
    });

    test('an unknown or null DB value degrades to pending, never throws', () {
      // A row written by an older/newer deployment must not crash the console.
      for (final junk in [null, '', 'archived', 'IN_PROGRESS', 'in progress']) {
        expect(reportStatusFromDb(junk), ReportStatus.pending);
      }
    });

    test('every status has a human label', () {
      for (final s in ReportStatus.values) {
        expect(reportStatusLabel(s).trim(), isNotEmpty);
      }
    });
  });

  // ══ 2. Accept ════════════════════════════════════════════════════════════
  group('accept — into an office', () {
    final p = acceptPayload('Engineering Office', '2026-09-01T00:00:00Z', 'u1');

    test('routes to the chosen office and releases it to them', () {
      expect(p['assigned_to_department'], 'Engineering Office');
      expect(p['assigned_at'], isNotNull);
      // under_review, NOT pending: the office must be able to see it, and a
      // report left pending sits looking ignored on both desks.
      expect(p['status'], 'under_review');
    });

    test('CANCELS any external endorsement — all three columns', () {
      // The bug this guards: clearing endorsed_to_department but leaving
      // endorsed_at/endorsed_by behind leaves a report that reads as endorsed
      // to some views and assigned to others. Ownership must land in exactly
      // one place.
      expect(p['endorsed_to_department'], isNull);
      expect(p['endorsed_at'], isNull);
      expect(p['endorsed_by'], isNull);
    });

    test('does not touch the rejection note', () {
      // Accept is not a closure path; clearing it here would silently erase
      // the record of a prior rejection.
      expect(p.containsKey('rejection_note'), isFalse);
    });
  });

  // ══ 3. Reject ════════════════════════════════════════════════════════════
  group('reject — terminal, and the citizen is told why', () {
    test('carries the trimmed reason, which the citizen sees', () {
      final p = rejectPayload('  Duplicate of an existing report.  ');
      expect(p['status'], 'rejected');
      // Trimmed: this string is rendered verbatim in the citizen's
      // notification, so stray whitespace is a visible defect.
      expect(p['rejection_note'], 'Duplicate of an existing report.');
    });

    test('does NOT clear the assignment', () {
      // Deliberate: a report rejected while an office was working it keeps its
      // assignment, so the history of who held it survives the closure. reopen
      // is what clears it (see below), because pending-but-assigned is the
      // limbo state that must not persist.
      final p = rejectPayload('Not actionable.');
      expect(p.containsKey('assigned_to_department'), isFalse);
      expect(p.containsKey('endorsed_to_department'), isFalse);
    });
  });

  // ══ 4. Reopen ════════════════════════════════════════════════════════════
  group('reopen — back to triage, unowned', () {
    final p = reopenPayload();

    test('returns to pending and clears the rejection reason', () {
      expect(p['status'], 'pending');
      expect(p['rejection_note'], isNull);
    });

    test('clears BOTH kinds of ownership — no pending-but-assigned limbo', () {
      // A report rejected mid-work keeps its assignment (see reject above).
      // Reopening without clearing it would put a report on the triage desk
      // that an office still believes it owns.
      expect(p.containsKey('assigned_to_department'), isTrue);
      expect(p['assigned_to_department'], isNull);
      expect(p['assigned_at'], isNull);
      expect(p.containsKey('endorsed_to_department'), isTrue);
      expect(p['endorsed_to_department'], isNull);
      expect(p['endorsed_at'], isNull);
    });

    test('touches ONLY the report row — never the work history', () {
      // ── Verified live 2026-09-01, on a rolled-back transaction ──────────
      // The question was whether reopening a report that had been worked
      // before it was rejected wipes that work. It does not:
      //
      //     updates  before reject 2 -> after reject 2 -> after reopen 2
      //     notes    before reject 4 -> after reject 4 -> after reopen 4
      //
      // because report_updates and report_notes are SEPARATE TABLES. Their
      // ON DELETE CASCADE fires only if the report itself is deleted, and
      // reopen is an UPDATE.
      //
      // This test is the guard: the day someone adds a cleanup to reopen,
      // this list is what they have to change on purpose.
      expect(
        p.keys.toSet(),
        {
          'status',
          'rejection_note',
          'assigned_to_department',
          'assigned_at',
          'endorsed_to_department',
          'endorsed_at',
        },
        reason: 'reopen must write these six columns and nothing else — the '
            'office history lives in other tables and must survive',
      );
    });
  });

  // ══ 5. Return to triage (the office's own exit) ══════════════════════════
  group('return to triage — the office says "not mine"', () {
    final p = returnToTriagePayload();

    test('lands back on the triage desk, unowned', () {
      expect(p['status'], 'pending');
      expect(p['assigned_to_department'], isNull);
      expect(p['endorsed_to_department'], isNull);
    });

    test('the ORDER of operations is load-bearing', () {
      // Not a payload assertion — a statement of the rule the SQL depends on,
      // kept here because it is invisible at every call site.
      //
      // staff_return_to_triage calls revoke_endorsement BEFORE nulling the
      // columns, and staff_repository inserts its audit note BEFORE calling
      // the RPC. Both for the same reason: the RLS path resolves through
      // staff_can_see_report(), which stops matching the instant those columns
      // are null. Reorder either and the write silently affects zero rows.
      //
      // The assertion is only that the payload nulls both columns — the fact
      // that makes the ordering matter.
      expect(
        p.values.where((v) => v == null).length,
        2,
        reason: 'both ownership columns are nulled, which is exactly what '
            'breaks staff_can_see_report() for anything sequenced after',
      );
    });
  });

  // ══ 6. The lifecycle as a whole ══════════════════════════════════════════
  group('the lifecycle holds together', () {
    /// Applies a payload to a report row, the way PostgREST would.
    Map<String, dynamic> apply(
      Map<String, dynamic> row,
      Map<String, dynamic> patch,
    ) => {...row, ...patch};

    test('file -> accept -> work -> resolve', () {
      var row = <String, dynamic>{
        'status': 'pending',
        'assigned_to_department': null,
        'endorsed_to_department': null,
        'rejection_note': null,
      };

      row = apply(row, acceptPayload('Sanitation Office', 'now', 'u1'));
      expect(row['status'], 'under_review');
      expect(row['assigned_to_department'], 'Sanitation Office');

      // The office's own transitions — staff_set_report_status.
      for (final s in [ReportStatus.inProgress, ReportStatus.resolved]) {
        row = apply(row, {'status': reportStatusToDb(s)});
      }
      expect(row['status'], 'resolved');
      // The office still owns it at the end — that is the record of who did
      // the work.
      expect(row['assigned_to_department'], 'Sanitation Office');
    });

    test('the full reject -> reopen -> re-accept round trip', () {
      var row = <String, dynamic>{
        'status': 'in_progress',
        'assigned_to_department': 'Engineering Office',
        'assigned_at': 'then',
        'endorsed_to_department': null,
        'endorsed_at': null,
        'rejection_note': null,
      };

      row = apply(row, rejectPayload('Closed in error.'));
      expect(row['status'], 'rejected');
      // Still assigned — the record of who held it survives the closure.
      expect(row['assigned_to_department'], 'Engineering Office');

      row = apply(row, reopenPayload());
      expect(row['status'], 'pending');
      expect(row['rejection_note'], isNull);
      expect(
        row['assigned_to_department'],
        isNull,
        reason: 'a reopened report must not still be owned by the office that '
            'was working it before it was closed',
      );

      // And it can be routed somewhere else entirely.
      row = apply(row, acceptPayload("Mayor's Office", 'now', 'u1'));
      expect(row['status'], 'under_review');
      expect(row['assigned_to_department'], "Mayor's Office");
    });

    test('accept after an endorsement leaves ONE owner', () {
      var row = <String, dynamic>{
        'status': 'under_review',
        'assigned_to_department': null,
        'assigned_at': null,
        'endorsed_to_department': 'DPWH',
        'endorsed_at': 'then',
        'endorsed_by': 'u9',
      };

      row = apply(row, acceptPayload('Engineering Office', 'now', 'u1'));

      // The whole point: never both.
      expect(row['assigned_to_department'], 'Engineering Office');
      expect(row['endorsed_to_department'], isNull);
      expect(row['endorsed_at'], isNull);
      expect(row['endorsed_by'], isNull);
    });

    test('an office returning a report undoes the accept exactly', () {
      var row = <String, dynamic>{
        'status': 'under_review',
        'assigned_to_department': 'Engineering Office',
        'endorsed_to_department': null,
      };

      row = apply(row, returnToTriagePayload());

      // Indistinguishable from a freshly-filed report as far as ownership
      // goes, which is what puts it back in Needs-triage.
      expect(row['status'], 'pending');
      expect(row['assigned_to_department'], isNull);
      expect(row['endorsed_to_department'], isNull);
    });
  });

  // ══ 7. The endorsement credential ════════════════════════════════════════
  group('the QR + PIN handoff', () {
    // ── Verified live 2026-09-01, on a rolled-back transaction ────────────
    // The question was what happens to a PRINTED letter when the admin changes
    // the endorsement. Measured against the real database:
    //
    //     old token scans BEFORE the change ......... valid = true
    //     new token differs from old ................ true
    //     rows for this report ...................... 1
    //     old token row still exists ................ 0   (destroyed)
    //     OLD token scans AFTER the change .......... valid = false
    //     NEW token scans ........................... valid = true
    //     old PIN matches the new row ............... 0   (dead)
    //
    // Two mechanisms make that true, and both are schema-level:
    //   * UNIQUE (report_id) on report_endorsements, so there is at most one
    //     endorsement row per report, ever;
    //   * endorse_report_to_agency uses ON CONFLICT (report_id) DO UPDATE,
    //     overwriting token and pin_hash rather than inserting a second row.
    //
    // These cannot be asserted from Dart — they are database facts. What IS
    // asserted here is the invariant the UI must not contradict, so a future
    // change that starts caching or re-showing an old token fails.

    test('the credentials model carries the PIN but nothing persists it', () {
      // The PIN IS held client-side, briefly and deliberately: the admin has
      // to see it once to print the letter and read it to the agency. What
      // must never happen is it being WRITTEN anywhere — a preference, a
      // cache, a local database — because the row keeps only a bcrypt hash and
      // the printed letter is meant to be the only copy.
      //
      // An earlier version of this test asserted `clientKnowsPin == false`,
      // which was simply wrong: EndorsementCredentials.pin exists and is used
      // by the letter PDF and the success dialog. Asserting a hardcoded false
      // proved nothing and mis-stated the design.
      //
      // So this constructs the real model and pins the shape instead.
      const c = EndorsementCredentials(
        token: 'tok_abc',
        pin: '0429',
        reference: 'END-1A2B3C4D',
        agency: 'DPWH',
      );

      expect(c.pin, '0429');
      expect(c.token, 'tok_abc');

      // The guard that matters is a grep, not an assertion: no persistence
      // call anywhere takes these fields. Checked 2026-09-01 — the only
      // consumers are endorsement_letter_pdf.dart (prints it) and
      // endorsement_success_dialog.dart (shows it, offers a clipboard copy).
      // Neither writes to disk. If that changes, this comment is the thing
      // the next reader should re-check.
      expect(
        c.reference.startsWith('END-'),
        isTrue,
        reason: 'the reference is the durable identifier — it is what survives '
            'in the letter and the event log, unlike the PIN',
      );
    });

    test('re-endorsing means the old printed letter is waste paper', () {
      // ── This is a DATABASE fact, restated where a Dart reader will see it ──
      //
      // It cannot be asserted from here: UNIQUE(report_id) and ON CONFLICT
      // DO UPDATE live in the schema, and Dart has no view of them. What the
      // Dart side CAN pin is the contract the UI is written against — that a
      // withdrawal and a re-endorsement are both destructive to the previous
      // credential, so no code path should offer to "resend the old link".
      //
      // EndorseChoice is that contract: it resolves to either a NEW agency
      // (mint) or a clear (revoke). There is deliberately no third case that
      // reuses an existing token.
      const fresh = EndorseChoice(agency: 'DENR', reason: 'Re-routed.');
      final cleared = EndorseChoice.clearWith('DPWH declined.');

      expect(fresh.isClear, isFalse);
      expect(fresh.agency, 'DENR');

      expect(cleared.isClear, isTrue);
      expect(
        cleared.reason,
        'DPWH declined.',
        reason: 'a withdrawal records WHY, because it voids a signed letter',
      );

      // No "keep the existing token" state exists, and that is the point.
      expect(
        EndorseChoice.clear.agency,
        isEmpty,
        reason: 'clearing is the only non-minting outcome — there is no path '
            'that reuses a previously issued token',
      );
    });
  });
}
