import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/core/config/app_config.dart';

// The clean-URL cutover, pinned at the two places it is observable from a
// unit test.
//
// ── What this is guarding ───────────────────────────────────────────────────
// `usePathUrlStrategy()` itself cannot be asserted here: it configures the
// browser's address bar, and `kIsWeb` is a compile-time false under
// `flutter test`, so the call is not even compiled into this binary. What CAN
// be pinned is everything that had to change WITH it — the URLs the app builds
// by hand, which are the ones that silently rot when the strategy changes
// underneath them.
//
// Both were real defects found during the cutover, not hypotheticals:
//
//   * AppConfig.scanUrl wrote `/#/scan/<token>` into a QR code printed on an
//     endorsement letter. Left alone, every code generated after the switch
//     would have opened the landing page instead of the scan screen.
//   * CitizenShell._shareEventLink built its link with `replace(fragment:)`,
//     so the one feature whose entire job is handing somebody a working link
//     would have copied a broken one.
void main() {
  group('the QR scan URL', () {
    test('is clean-path, not hash-routed', () {
      final url = AppConfig.scanUrl('abc123');

      expect(
        url,
        isNot(contains('/#/')),
        reason:
            'a hash URL now resolves to the landing page — PathUrlStrategy '
            'reads the pathname and discards the fragment',
      );
      expect(url, endsWith('/scan/abc123'));
    });

    test('is absolute, so a printed code works off any device', () {
      // The QR is scanned by an agency officer's phone, which has no notion of
      // the app's origin. A bare path would be unscannable.
      expect(AppConfig.scanUrl('t').startsWith('https://'), isTrue);
    });

    test('a base64url token survives intact', () {
      // Tokens are 32 random bytes, base64-encoded, with `+/=` translated to
      // `-_` (see the report_endorsements migration). The dashes and
      // underscores must not be mangled, and — because vercel.json rewrites by
      // looking for a file extension — a token must never contain a dot.
      //
      // ── Why this literal reads as obviously fake ──────────────────────────
      // The first version of this test used a realistic-looking random string,
      // and GitGuardian flagged the commit as a "Generic High Entropy Secret".
      // It was a false positive — the value was invented here and matches
      // nothing — but a scanner that cries wolf is one whose next alert gets
      // ignored, and THAT is the real cost. This keeps the exact shape the test
      // cares about (mixed case, dash, underscore, no dot) while saying in the
      // value itself that it is not a credential.
      const token = 'EXAMPLE-not_a_real-token_FOR-tests_only';
      final url = AppConfig.scanUrl(token);

      expect(url, endsWith('/scan/$token'));
      expect(
        token,
        isNot(contains('.')),
        reason:
            'a dot would make the rewrite treat the URL as a static file and '
            'serve a 404 instead of the app',
      );
    });
  });

  group('a shared event link', () {
    // _shareEventLink is private to CitizenShell and needs a pumped shell, so
    // this pins the CONSTRUCTION rule it follows rather than calling it: build
    // from the origin plus the route, never by replacing parts of Uri.base.
    String buildLink(Uri base, String path) => '${base.origin}$path';

    test('carries no fragment, inherited query, or trailing hash', () {
      // Uri.base on the feed genuinely looks like this — the feed's own deep
      // link puts `?post=` in the query.
      final base = Uri.parse('https://gov-pulse.app/home?post=99#/stale');

      expect(
        buildLink(base, '/home/event/42'),
        'https://gov-pulse.app/home/event/42',
      );
    });

    test('works on localhost, where the port is part of the origin', () {
      expect(
        buildLink(Uri.parse('http://localhost:57810/home'), '/home/event/42'),
        'http://localhost:57810/home/event/42',
      );
    });

    // The three shapes `Uri.replace` produced, each of which shipped a subtly
    // wrong link. Kept as a record of why the simpler construction is used.
    test('the replace-based forms it replaced were all wrong', () {
      final base = Uri.parse('https://gov-pulse.app/home?post=99#/stale');

      // Omitting `fragment` keeps the current page's fragment.
      expect(
        base.replace(path: '/home/event/42').toString(),
        contains('#/stale'),
      );
      // Passing an empty fragment renders a bare trailing '#'.
      expect(
        base.replace(path: '/home/event/42', fragment: '').toString(),
        endsWith('#'),
      );
      // Either way the unrelated query rides along.
      expect(
        base.replace(path: '/home/event/42', fragment: '').toString(),
        contains('post=99'),
      );
    });
  });
}
