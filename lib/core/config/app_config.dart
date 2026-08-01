// ════════════════════════════════════════════════════════════════════════════
//  Deployment-time configuration
//
//  Values that differ between a developer's machine and the deployed site, and
//  that therefore must NOT be hardcoded at a call site. Everything here is read
//  from `--dart-define`, with a default that keeps a local run working.
//
//    flutter build web \
//      --dart-define=SCAN_BASE_URL=https://govpulse.aparri.gov.ph \
//      --dart-define=LGU_MAYOR_NAME="Hon. Juan Dela Cruz"
// ════════════════════════════════════════════════════════════════════════════

class AppConfig {
  const AppConfig._();

  /// Origin the endorsement QR code points at.
  ///
  /// This is the one value that MUST be set for a real deployment. The QR is
  /// printed onto a paper letter and scanned by an agency's phone camera, which
  /// has no idea what "localhost" means — so a letter generated with the
  /// default is only ever useful on the machine that made it.
  ///
  /// No trailing slash; [scanUrl] adds the separator.
  static const String scanBaseUrl = String.fromEnvironment(
    'SCAN_BASE_URL',
    defaultValue: 'http://localhost:8080',
  );

  /// Full URL encoded into the QR for [token].
  ///
  /// HASH-ROUTED ON PURPOSE. Flutter web's default URL strategy is hash-based,
  /// and a hash URL is served correctly by any static host with no
  /// configuration at all — the whole path is `/`, so a deep link cannot 404 and
  /// a refresh on the scan page cannot break.
  ///
  /// The clean-path alternative (`/scan/<token>`) needs BOTH `usePathUrlStrategy()`
  /// at startup AND a server rewrite sending every unmatched path to
  /// /index.html. `firebase.json` currently has no `hosting` block at all, so
  /// today that form would 404 the instant anyone reloaded. If you add hosting
  /// with a `"rewrites": [{"source": "**", "destination": "/index.html"}]` rule
  /// and call usePathUrlStrategy(), drop the `/#` below and nothing else here
  /// changes.
  static String scanUrl(String token) => '$scanBaseUrl/#/scan/$token';

  // ── Endorsement letter ────────────────────────────────────────────────────
  // Printed on an official document over the Mayor's signature line, so these
  // are deployment configuration rather than constants in a PDF builder.

  static const String lguName = 'Municipality of Aparri';
  static const String province = 'Province of Cagayan';
  static const String republic = 'Republic of the Philippines';

  static const String mayorName = String.fromEnvironment(
    'LGU_MAYOR_NAME',
    defaultValue: 'Hon. [Municipal Mayor]',
  );

  static const String mayorTitle = 'Municipal Mayor';

  /// Asset path for the municipal seal on the letterhead.
  ///
  /// Empty by default: no seal artwork exists in `assets/images/` yet, and the
  /// letter draws a labelled placeholder ring instead of failing to load. Drop
  /// a monochrome PNG in, set the path here, and add it to pubspec assets — the
  /// letter picks it up with no other change. Keep it BLACK AND WHITE; the whole
  /// document is designed to photocopy and fax cleanly.
  static const String sealAssetPath = String.fromEnvironment(
    'LGU_SEAL_ASSET',
    defaultValue: '',
  );
}
