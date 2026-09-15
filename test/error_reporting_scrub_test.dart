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
// Both are the query string, which is why the sanitiser drops it.
//
// The PATH used to be kept verbatim, on the grounds that it is what makes two
// crashes groupable — sound while the app was hash-routed, because every route
// argument then lived in the fragment, which was already dropped. Turning on
// clean URLs moves those arguments into the path, so `/#/scan/<token>` becomes
// `/scan/<token>` and an endorsement token would ride out to a third party on
// any crash carrying a URL.
//
// So the path is now kept STRUCTURALLY: route names survive, identifier-shaped
// segments become [redacted]. Both halves of that are pinned below — the
// leak must be closed AND the grouping must survive, because a sanitiser that
// redacts everything is safe and useless.
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
      // The route SHAPE is kept — that is what makes two crashes groupable —
      // but `abc.jpg` is a storage key, so the filename itself is redacted.
      expect(safe, contains('/storage/v1/object/sign/reports/'));
      expect(safe, isNot(contains('abc.jpg')));
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

    // ── The clean-URL form ────────────────────────────────────────────────
    // The test above only ever covered the HASH form. On its own it would keep
    // passing after `usePathUrlStrategy()` while the real case leaked, because
    // the token moves from the fragment (dropped) into the path (kept). This
    // pins the form the app is moving to.
    test('an endorsement token in the PATH is redacted too', () {
      final safe = sanitizeUrlForReport(
        'https://gov-pulse-rose.vercel.app/scan/SECRET-TOKEN-123',
      );

      expect(
        safe,
        isNot(contains('SECRET-TOKEN-123')),
        reason: 'a scan token opens a page describing one citizen\'s report',
      );
      // The route survives, so every crash on the scan page still groups.
      expect(safe, contains('/scan/'));
      expect(safe, contains('[redacted]'));
    });

    test('a report id in the path is redacted, the route is not', () {
      final safe = sanitizeUrlForReport(
        'https://gov-pulse-rose.vercel.app/my-reports/detail/8821',
      );

      expect(safe, isNot(contains('8821')));
      expect(safe, contains('/my-reports/detail/'));
    });

    // ── Grouping must survive ─────────────────────────────────────────────
    // A sanitiser that redacts everything is safe and useless: Sentry would
    // collapse every crash in the app into one bucket. These pin the other
    // half of the contract.
    test('route names and API segments are kept intact', () {
      expect(
        sanitizeUrlForReport('https://x.supabase.co/rest/v1/reports'),
        'https://x.supabase.co/rest/v1/reports',
      );
      expect(
        sanitizeUrlForReport('https://x.supabase.co/functions/v1/chat-agent'),
        'https://x.supabase.co/functions/v1/chat-agent',
      );
      expect(
        sanitizeUrlForReport('https://example.org/settings'),
        'https://example.org/settings',
      );
    });

    test('two crashes on the same screen still group together', () {
      final a = sanitizeUrlForReport('https://x.app/my-reports/detail/11');
      final b = sanitizeUrlForReport('https://x.app/my-reports/detail/99');

      expect(a, equals(b), reason: 'differing only by id must not split');
    });

    test('a uuid is treated as an identifier', () {
      final safe = sanitizeUrlForReport(
        'https://x.app/home/event/3f2504e0-4f89-11d3-9a0c-0305e82c3301',
      );

      expect(safe, isNot(contains('3f2504e0')));
      expect(safe, contains('/home/event/'));
    });

    test('a URL with no query is left readable', () {
      // `reports` is a route name and survives; `42` is an id and does not.
      expect(
        sanitizeUrlForReport('https://example.org/reports/42'),
        'https://example.org/reports/[redacted]',
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
