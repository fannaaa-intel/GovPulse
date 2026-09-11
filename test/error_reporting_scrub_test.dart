// Does the error reporter refuse to leak citizen data?
//
// This is a government service holding names, addresses, ID photographs and
// report locations, and an error reporter is a pipe out of the app to a third
// party. The privacy promises in error_reporting.dart are only worth anything
// if something checks them, so the two that carry real risk are pinned here:
//
//   1. A Supabase SIGNED MEDIA URL carries a bearer token in its query string.
//      Sent whole, a crash report would hand a third party a working link to a
//      citizen's ID photograph.
//   2. A search URL carries whatever the citizen typed.
//
// Both are the query string, which is why _safeUrl drops it and keeps only the
// path — enough to group "every crash on /report/detail" without carrying the
// payload.
//
// The scrubbers are private, so these exercise them through the one seam that
// is observable from a test: sanitizeUrlForReport, which is the same function
// _scrub and _scrubCrumb call.
import 'package:flutter_test/flutter_test.dart';

import 'package:govpulse/core/config/app_config.dart';
import 'package:govpulse/core/services/error_reporting.dart';

void main() {
  group('URL sanitising', () {
    test('drops the query string that carries a signed-media bearer token', () {
      const signed =
          'https://vxvflhjbafqwehuxnmeq.supabase.co/storage/v1/object/sign/'
          'reports/abc.jpg?token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.leak';

      final safe = sanitizeUrlForReport(signed);

      expect(safe, isNot(contains('eyJhbGci')), reason: 'token must not survive');
      expect(safe, isNot(contains('token=')));
      // The path is kept: that is what makes two crashes groupable.
      expect(safe, contains('/storage/v1/object/sign/reports/abc.jpg'));
      // And the fact that something was dropped stays visible.
      expect(safe, endsWith('?[redacted]'));
    });

    test('drops free text the citizen typed into a search', () {
      final safe = sanitizeUrlForReport(
        'https://example.org/search?q=my%20full%20name%20and%20address',
      );

      expect(safe, isNot(contains('full')));
      expect(safe, isNot(contains('address')));
      expect(safe, startsWith('https://example.org/search'));
    });

    test('strips basic-auth userinfo', () {
      final safe = sanitizeUrlForReport('https://user:hunter2@example.org/x');

      expect(safe, isNot(contains('hunter2')));
      expect(safe, isNot(contains('user:')));
    });

    test('drops a fragment, where a hash-routed app carries its route args', () {
      final safe = sanitizeUrlForReport(
        'https://gov-pulse-rose.vercel.app/#/scan/SECRET-TOKEN-123',
      );

      expect(safe, isNot(contains('SECRET-TOKEN-123')));
    });

    test('a URL with no query is left readable', () {
      expect(
        sanitizeUrlForReport('https://example.org/reports/42'),
        'https://example.org/reports/42',
      );
    });

    test('unparseable input redacts rather than passing through', () {
      expect(sanitizeUrlForReport('::: not a url :::'), '[redacted]');
    });
  });

  group('configuration', () {
    test('reporting is OFF unless a DSN was supplied at build time', () {
      // No --dart-define in a test run, so this must be inert. A default DSN
      // would put every test's deliberately-thrown exception into the
      // production issue feed.
      expect(AppConfig.sentryDsn, isEmpty);
      expect(AppConfig.errorReportingEnabled, isFalse);
    });

    test('the environment tag defaults to production', () {
      expect(AppConfig.sentryEnvironment, 'production');
    });

    test('reporting calls are safe no-ops when unconfigured', () {
      // Every one of these runs on a real device before any DSN exists.
      expect(() => setErrorReportingUser('user-123'), returnsNormally);
      expect(() => setErrorReportingUser(null), returnsNormally);
      expect(
        () => reportHandledError(Exception('boom'), StackTrace.current),
        returnsNormally,
      );
    });
  });
}
