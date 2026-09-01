// An anonymous report, across all three surfaces that handle one.
//
// ── WHY THIS TEST EXISTS ────────────────────────────────────────────────────
// Anonymity on this platform has already failed once in production. Migration
// 20260722000000 records it: staff held a plain SELECT policy on `reports`, so
// an office could read `user_id` on a row whose `is_anonymous` was true, and
// the same citizen's named report sat one row away — enough to correlate the
// two and put a name on the anonymous one. Anonymity was enforced only by the
// Dart column list, which is not enforcement at all.
//
// So the rule is not "the screen does not show a name". It is that the three
// surfaces are each incapable of showing one, by different means:
//
//   ADMIN  holds identity legitimately (they are the accountable party), but
//          never resolves a profile for an anonymous row — the id is not even
//          sent to the lookup — and can only reveal deliberately, through a
//          role-gated, password-gated, reason-required, audited RPC.
//   STAFF  reads through a SECURITY DEFINER view that nulls user_id on
//          is_anonymous, and its model carries no name field to populate.
//   SCAN   (the anon QR page) calls one definer RPC whose projection contains
//          no identity column of any kind, anonymous or not.
//
// These tests pin the two layers this suite can reach: the MODEL cannot carry
// an identity it should not have, and the WIDGETS render the withheld state
// rather than an empty one. The database layer is pinned by the migrations'
// own guarantees and was probed live against production on 2026-09-01 — anon
// gets `{"valid": false}` from scan_endorsement for an unknown token, `[]` from
// reports, and "permission denied for view staff_reports_view".
//
// Supabase is never reached here: every assertion stops at the widget tree.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ReportStatus is declared alongside AdminReport; the staff repository imports
// the same enum, which is what lets one report cross both consoles.
import 'package:govpulse/features/admin/providers/admin_reports_provider.dart';
import 'package:govpulse/features/staff/data/staff_repository.dart';

/// The same underlying report, as each console's model sees it.
AdminReport _adminAnon() => AdminReport(
      id: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      shortId: 'AAAAAAAA',
      categoryKey: 'drainage',
      category: 'Drainage',
      barangay: 'Macanaya',
      address: 'Near the lyceum',
      remarks: 'Culvert blocked after the storm.',
      status: ReportStatus.underReview,
      isAnonymous: true,
      // The provider passes null for all three on an anonymous row: the id is
      // excluded from `namedIds` before the profile query is even built, and
      // then guarded a second time at construction. Both layers must hold.
      submitterName: null,
      submitterPhotoUrl: null,
      submitterRole: null,
      mediaCount: 1,
      createdAt: DateTime(2026, 9, 1, 6, 56),
      assignedToDepartment: 'Engineering Office',
      assignedAt: DateTime(2026, 9, 1, 7, 3),
    );

StaffReport _staffAnon() => StaffReport(
      id: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      shortId: 'AAAAAAAA',
      categoryKey: 'drainage',
      category: 'Drainage',
      barangay: 'Macanaya',
      address: 'Near the lyceum',
      remarks: 'Culvert blocked after the storm.',
      status: ReportStatus.underReview,
      isAnonymous: true,
      mediaCount: 1,
      createdAt: DateTime(2026, 9, 1, 6, 56),
      endorsedToDepartment: null,
      assignedToDepartment: 'Engineering Office',
      assignedAt: DateTime(2026, 9, 1, 7, 3),
    );

void main() {
  group('the model cannot carry what it must not know', () {
    test('admin: an anonymous row resolves no profile', () {
      final r = _adminAnon();
      expect(r.isAnonymous, isTrue);
      // Not "is empty" — NULL. An empty string would mean "we looked and found
      // nothing", which is a different and wrong statement: for an anonymous
      // row the lookup is never performed.
      expect(r.submitterName, isNull);
      expect(r.submitterPhotoUrl, isNull);
      expect(r.submitterRole, isNull);
    });

    test('staff: the model has no identity field to populate', () {
      final r = _staffAnon();
      expect(r.isAnonymous, isTrue);

      // ── Read the SOURCE, not the object ──────────────────────────────────
      //
      // The guarantee here is structural: StaffReport declares no name, photo,
      // role or user_id at all, so there is nothing a future fetch could fill
      // in. Dart cannot ask an object what fields it has without mirrors, and
      // an earlier version of this test tried `toString()` instead — which
      // returns "Instance of 'StaffReport'" for a class with no override, so
      // it passed just as happily with a `submitterName` field injected. A
      // check that cannot fail is worse than no check: it reports safety it
      // never verified.
      //
      // So the class body is parsed out of the file and its field declarations
      // are read. Coarse, but it fails for the right reason the day someone
      // adds an identity column here — at which point the definer view, the
      // fetch and this test all have to be reconsidered together.
      final src = File(
        'lib/features/staff/data/staff_repository.dart',
      ).readAsStringSync();

      final start = src.indexOf('class StaffReport {');
      expect(start, isNot(-1), reason: 'StaffReport was renamed or moved.');
      final body = src.substring(start, src.indexOf('\n}', start));

      const forbidden = [
        'user_id',
        'userId',
        'submitterName',
        'submitterPhoto',
        'contactName',
        'contactNumber',
        'reporterName',
      ];
      for (final f in forbidden) {
        expect(
          body.contains(f),
          isFalse,
          reason: 'StaffReport gained `$f`. Staff read through '
              'staff_reports_view, which nulls user_id on is_anonymous — and '
              'the console has never fetched a profile for the rest. If this '
              'model can now hold an identity, check what fills it before '
              'deleting this test.',
        );
      }

      // The control: the parse actually found a class body with fields in it,
      // so an empty `body` cannot make the loop above pass by default.
      expect(body, contains('final bool isAnonymous;'));
    });

    test('a NAMED report still carries its identity on the admin side', () {
      // The negative control. A test that only proves "no name anywhere" would
      // also pass if the identity pipeline were broken outright, which is a
      // different bug that would hide this one.
      final named = AdminReport(
        id: 'ffffffff-0000-1111-2222-333333333333',
        shortId: 'FFFFFFFF',
        categoryKey: 'road',
        category: 'Road & Infrastructure',
        barangay: 'Macanaya',
        address: 'Near the lyceum',
        remarks: 'Pothole.',
        status: ReportStatus.underReview,
        isAnonymous: false,
        submitterName: 'Mark Reduca',
        submitterPhotoUrl: 'https://example.test/p.jpg',
        submitterRole: 'citizen',
        mediaCount: 0,
        createdAt: DateTime(2026, 9, 1),
      );
      expect(named.isAnonymous, isFalse);
      expect(named.submitterName, 'Mark Reduca');
    });
  });

  group('the QR scan page is handed no identity to leak', () {
    // The SQL is read, not restated. An earlier version of this test listed the
    // projection as two Dart string sets and asserted they did not intersect —
    // which is a statement about two literals in this file and would keep
    // passing with `user_id` added to the real function tomorrow. A test that
    // cannot fail is worse than no test.
    test('scan_endorsement projects no identity column', () {
      // 20260831000001 rewrote the function whole; it is the live definition.
      final sql = File(
        'supabase/migrations/20260831000001_scan_endorsement_photos.sql',
      ).readAsStringSync();

      final start = sql.indexOf('create or replace function public.scan_endorsement');
      expect(start, isNot(-1), reason: 'scan_endorsement moved to another file.');
      final body = sql.substring(start, sql.indexOf(r'$function$;', start));

      // Comments discuss `user_id` legitimately (explaining why it is absent),
      // so they are stripped before the search — otherwise the prose defending
      // the guarantee would be what breaks it.
      final code = body
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('--'))
          .join('\n');

      const forbidden = [
        'user_id',
        'contact_name',
        'contact_number',
        'contact_email',
        'first_name',
        'last_name',
        'citizen_details',
        'public_user_profiles',
      ];
      for (final f in forbidden) {
        expect(
          code.contains(f),
          isFalse,
          reason: 'scan_endorsement now references `$f`. This function is '
              'executable by ANON — the widest surface on the platform. '
              'Anything it selects is world-readable to whoever holds a token.',
        );
      }

      // The control: the parse found the real projection, so an empty `code`
      // cannot make the loop above pass by default.
      expect(code, contains("'reference',    e.reference_code"));
      expect(code, contains("'barangay',    r.barangay"));
    });
  });

  group('an anonymous reporter is still told about their own report', () {
    // ── REGRESSION, fixed by 20260901000002 ──────────────────────────────────
    //
    // Both citizen-facing update triggers used to end with
    // `and r.is_anonymous = false`, under a comment reading "An anonymous
    // report has no one to tell". That is the one thing it is not.
    //
    // reports.user_id is still SET on an anonymous row — it is withheld from
    // the consoles, not erased. owns_report() resolves purely on
    // user_id = auth.uid() and deliberately ignores is_anonymous, so
    // report_updates_read grants the anonymous reporter SELECT on every
    // approved update on their own report. my_reports_screen.dart filters on
    // user_id alone.
    //
    // So the database SHOWED an anonymous citizen the agency's update and then
    // these triggers declined to tell them it had arrived. The update sat in
    // the app; the only way to find it was to reopen the report and look.
    //
    // These read the migration SQL because that is where the defect lived —
    // there is no Dart layer between the trigger and the citizen to assert on.
    String fnBody(String path, String fn) {
      final sql = File(path).readAsStringSync();
      final start = sql.indexOf('create or replace function public.$fn');
      expect(start, isNot(-1), reason: '$fn is not defined in $path.');
      final body = sql.substring(start, sql.indexOf(r'$$;', start));
      // Comments here EXPLAIN the anonymity rule at length, so they must be
      // stripped or the explanation is what fails the test.
      return body
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('--'))
          .join('\n');
    }

    const fixPath =
        'supabase/migrations/20260901000002_anonymous_reporters_get_their_updates.sql';

    for (final fn in const [
      'notify_report_update_decision',
      'notify_citizen_of_approved_insert',
    ]) {
      test('$fn does not gate the citizen out for being anonymous', () {
        final code = fnBody(fixPath, fn);

        expect(
          code.contains('is_anonymous'),
          isFalse,
          reason: '$fn consults is_anonymous again. An anonymous report still '
              'belongs to the person who filed it, and RLS already shows them '
              'the update — re-adding this gate means they can read the '
              'update in the app but are never told it arrived.',
        );

        // The negative control, and the condition that SHOULD be tested: a
        // report filed with no account genuinely has nobody to notify. If this
        // ever disappears the trigger starts inserting notifications with a
        // null user_id.
        expect(
          code.contains('r.user_id is not null'),
          isTrue,
          reason: '$fn no longer checks for an account to notify.',
        );

        // The control: the parse found a real body.
        expect(code, contains('insert into public.notifications'));
      });
    }

    test('the fix changes nothing but that predicate', () {
      // The staff-author branch shares notify_report_update_decision with the
      // citizen branch. It is the part of the function that was NOT the bug,
      // and rewriting the function whole is how it could be damaged silently.
      final code = fnBody(fixPath, 'notify_report_update_decision');

      expect(code, contains('new.author_id is not null'));
      expect(code, contains('Your progress update was approved'));
      expect(code, contains('Your progress update was returned'));
      // The house rule: a notification failure never rolls back the update.
      expect(code, contains('exception when others then null'));
    });
  });
}
