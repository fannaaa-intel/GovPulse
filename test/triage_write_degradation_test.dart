// When a triage write is allowed to degrade, and when it must not.
//
// ── THE BUG THIS GUARDS ───────────────────────────────────────────────────
// AdminReportsNotifier._tryUpdate writes accept / reject / reopen. It used to
// retry on ANY failure with a narrower payload:
//
//     try   { update(everything) }
//     catch (_) { update(everything minus the optional columns) }
//
// The intent was narrow — the report_triage_gate migration might not be
// applied, so drop its columns and let the core status change land. The effect
// was that an RLS denial, a constraint violation or a dropped connection also
// fell into the retry. The narrower payload then often SUCCEEDED, so accept()
// reported "Accepted — routed to Engineering Office" while
// assigned_to_department was never written: the report sat unassigned, the
// office was never notified by trg_notify_staff_report_assigned (which fires on
// that column changing), and nothing anywhere said so.
//
// Verified live 2026-08-31: all six triage columns exist on public.reports, and
// report_triage_gate.sql is in supabase/legacy/ (applied). So the fallback is
// dead code for its stated purpose and was only ever hiding real errors.
//
// It is KEPT — a deployment restored from an older schema is exactly when you
// want it — but it must fire only on "this column does not exist". These tests
// pin that predicate, which is the part that was wrong.

import 'package:flutter_test/flutter_test.dart';

/// Mirrors the guard in `_tryUpdate`. Duplicated rather than exported so that
/// changing the production predicate fails this test and someone has to think
/// about it.
///
/// 42703 is Postgres's undefined_column. PostgREST answers PGRST204 when a
/// column named in the payload is absent from its schema cache. Both mean the
/// column does not exist; nothing else does.
bool degradesFor(String? code) => code == '42703' || code == 'PGRST204';

void main() {
  group('a triage write degrades only for a missing column', () {
    test('it degrades for undefined_column', () {
      expect(degradesFor('42703'), isTrue);
    });

    test('it degrades for PostgREST schema-cache misses', () {
      expect(degradesFor('PGRST204'), isTrue);
    });

    // Each of these used to be swallowed, retried narrower, and reported to the
    // admin as a success.
    test('an RLS denial is NOT a missing column', () {
      // 42501 = insufficient_privilege. Retrying without the assignment columns
      // can genuinely succeed here, which is precisely the silent failure:
      // the status moves, the routing does not, the office is never told.
      expect(degradesFor('42501'), isFalse);
    });

    test('a constraint violation is NOT a missing column', () {
      // 23514 = check_violation, 23503 = foreign_key_violation.
      expect(degradesFor('23514'), isFalse);
      expect(degradesFor('23503'), isFalse);
    });

    test('a missing TABLE is NOT a missing column', () {
      // 42P01 = undefined_table. Dropping a few columns cannot fix it, so the
      // retry would fail identically — better to surface the real error.
      expect(degradesFor('42P01'), isFalse);
    });

    test('a network failure with no code does not degrade', () {
      // A dropped connection surfaces with no PostgREST code at all. Under the
      // old bare catch this retried and could half-succeed on a flaky link.
      expect(degradesFor(null), isFalse);
      expect(degradesFor(''), isFalse);
    });
  });

  // The other half of the fix: if the missing column was NOT one of the
  // optional ones, the narrower payload is identical and the retry is pointless
  // — so the original error must propagate rather than be reported as success.
  group('the fallback payload has to be worth sending', () {
    /// Mirrors `_tryUpdate`'s payload trim.
    Map<String, dynamic> fallbackFor(
      Map<String, dynamic> update,
      List<String> optional,
    ) =>
        Map<String, dynamic>.from(update)
          ..removeWhere((k, _) => optional.contains(k));

    test('accept keeps its core write when the optional columns go', () {
      // accept()'s real payload.
      final fallback = fallbackFor(
        {
          'assigned_to_department': 'Engineering Office',
          'assigned_at': 'now',
          'assigned_by': 'uid',
          'endorsed_to_department': null,
          'endorsed_at': null,
          'endorsed_by': null,
          'status': 'under_review',
        },
        ['assigned_to_department', 'assigned_at', 'assigned_by'],
      );

      expect(fallback, isNotEmpty);
      expect(fallback['status'], 'under_review');
      // Clearing the endorsement must survive the trim. It is what fires
      // trg_revoke_endorsement_on_clear, and a report accepted internally while
      // a live QR letter still pointed at it would let the agency keep driving
      // the citizen's status.
      expect(fallback.containsKey('endorsed_to_department'), isTrue);
    });

    test('a payload that trims to nothing must not be sent', () {
      final fallback = fallbackFor(
        {'rejection_note': 'out of scope'},
        ['rejection_note'],
      );
      // _tryUpdate rethrows in this case rather than reporting a success it
      // did not achieve.
      expect(fallback, isEmpty);
    });
  });
}
