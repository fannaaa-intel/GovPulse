// Two guarantees the automated ID check must never erode:
//
//   1. EVERY verification submission reaches an admin. The check advises; it
//      never approves, never rejects, and never files anything away.
//   2. An APPROVED citizen gets full access, exactly as before. The check has
//      no say in what a verified user can do.
//
// These are source-level guards, not widget tests, because the thing being
// protected is an ARCHITECTURAL rule: "no code path may write 'approved'
// except an admin action". A widget test can only prove one screen behaves;
// scanning the source proves no screen was quietly given the power.
//
// They exist because the scoring system is exactly the kind of feature that
// grows an "auto-approve high scores to save reviewer time" shortcut later.
// That would be a policy change with real consequences for citizens, and it
// must be a deliberate decision — not something that slips in.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every Dart file under lib/, so a new screen cannot dodge these rules.
List<File> _libFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

/// Strips `//` line comments so prose about approval is not mistaken for code.
///
/// Deliberately crude: it only needs to stop the many explanatory comments in
/// this codebase from tripping a source scan.
String _codeOnly(String source) => source
    .split('\n')
    .map((l) {
      final i = l.indexOf('//');
      return i == -1 ? l : l.substring(0, i);
    })
    .join('\n');

void main() {
  group('the admin owns the verification decision', () {
    test('every submission is inserted as pending, never pre-approved', () {
      // The citizen-facing insert is the only place a submission is created.
      final f = File(
        'lib/features/profileVerification/verification_face_scan_screen.dart',
      );
      final code = _codeOnly(f.readAsStringSync());

      expect(
        code.contains("'status': 'pending'"),
        isTrue,
        reason: 'submissions must enter the queue as pending',
      );
      expect(
        code.contains("'status': 'approved'"),
        isFalse,
        reason: 'the capture flow must never approve its own submission',
      );
    });

    test('no citizen-facing file approves a VERIFICATION submission', () {
      // Only admin code may set a verification submission approved. This scans
      // everything OUTSIDE the admin feature, so a new citizen screen cannot
      // grant itself verification.
      //
      // Scoped to files that actually touch `verification_submissions`:
      // `'status': 'approved'` is a legitimate write on OTHER tables — events
      // are published that way by an admin — and flagging those taught nothing
      // about verification while guaranteeing a false failure later.
      final offenders = <String>[];
      for (final f in _libFiles()) {
        final path = f.path.replaceAll(r'\', '/');
        if (path.contains('/features/admin/')) continue;

        final code = _codeOnly(f.readAsStringSync());
        if (!code.contains('verification_submissions')) continue;
        // The write shape, not a read: `.eq('status', 'approved')` and
        // comparisons are legitimate everywhere.
        if (code.contains("'status': 'approved'")) offenders.add(path);
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'these files approve a verification outside the admin feature: '
            '$offenders',
      );
    });

    test('the automated verdict never drives an approval', () {
      // `auto_accept` is the scorer's highest verdict. It means "nothing to
      // flag for the reviewer" — NOT "approve this person". If it ever reaches
      // an approval call or a status write, the machine has taken a decision
      // that belongs to a human.
      final offenders = <String>[];
      for (final f in _libFiles()) {
        final code = _codeOnly(f.readAsStringSync());
        if (!code.contains('auto_accept') && !code.contains('autoAccept')) {
          continue;
        }
        final path = f.path.replaceAll(r'\', '/');
        // The service that DEFINES the verdict, and the console that LABELS
        // it, are the only legitimate mentions.
        if (path.endsWith('core/services/id_check_service.dart')) continue;
        if (path.contains('/features/admin/')) continue;
        offenders.add(path);
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'the auto_accept verdict is referenced outside the service that '
            'defines it and the console that displays it: $offenders',
      );
    });

    test('approve and reject are gated only on a busy flag', () {
      // The admin's two controls must never become conditional on the
      // automated score. A reviewer has to be able to approve a card the
      // machine rejected, and reject one it passed.
      final code = _codeOnly(
        File('lib/features/admin/pages/admin_verification_page.dart')
            .readAsStringSync(),
      );

      expect(
        code.contains('onTap: _busy ? null : _approve'),
        isTrue,
        reason: 'approve must gate only on the double-submit guard',
      );
      expect(
        code.contains('onTap: _busy ? null : _reject'),
        isTrue,
        reason: 'reject must gate only on the double-submit guard',
      );

      // Nothing in the dialog may disable an action based on the check.
      for (final forbidden in [
        'checkVerdict == ',
        'checkScore >',
        'checkScore <',
      ]) {
        expect(
          code.contains(forbidden),
          isFalse,
          reason: 'the admin controls must not branch on the automated check '
              '(found "$forbidden")',
        );
      }
    });

    test('a rejected capture still leaves the citizen able to submit', () {
      // The strictest verdict the checker can return is `reject`, and that
      // only asks for a RETAKE — it must never end the citizen's attempt or
      // mark anything in the database. Proven by what the reject branch does:
      // it resets the capture state and returns.
      final code = _codeOnly(
        File(
          'lib/features/profileVerification/verification_scan_screen.dart',
        ).readAsStringSync(),
      );

      expect(
        code.contains('IdVerdict.reject'),
        isTrue,
        reason: 'the scan screen handles the reject verdict',
      );
      // No status write of any kind lives in the capture screen.
      expect(code.contains("'status':"), isFalse);
    });
  });

  group('an approved citizen keeps full access', () {
    test('verified status is derived from the DB status, not from the check', () {
      // What unlocks the app is `verification_submissions.status == approved`,
      // written only by an admin. The automated check has no route into this.
      final code = _codeOnly(
        File('lib/core/providers/user_profile_provider.dart').readAsStringSync(),
      );

      expect(
        code.contains("status == 'approved'"),
        isTrue,
        reason: 'verified access comes from the admin-set status',
      );
      // The provider must not consult the automated columns at all.
      for (final column in [
        'check_verdict',
        'check_score',
        'check_reasons',
      ]) {
        expect(
          code.contains(column),
          isFalse,
          reason: 'the profile provider must not read $column — access is the '
              "admin's decision, not the scorer's",
        );
      }
    });
  });
}
