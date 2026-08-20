/// Non-web build of [phone_dialer]. Nothing here is reachable: both members are
/// called from behind a `kIsWeb` check, and this file only exists so the mobile
/// and desktop builds still compile without `package:web`.
library;

/// See `phone_dialer_web.dart`.
void dialFromBrowser(String number) {
  throw UnsupportedError('dialFromBrowser is web-only');
}

/// See `phone_dialer_web.dart`.
bool browserReportsTouchDevice() => false;
