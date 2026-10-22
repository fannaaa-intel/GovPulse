/// Non-web build of [file_download]. Nothing here is reachable: the member is
/// called from behind a `kIsWeb` check, and this file only exists so the mobile
/// and desktop builds still compile without `package:web`.
library;

/// See `file_download_web.dart`.
void downloadFromBrowser(String url, String filename) {
  throw UnsupportedError('downloadFromBrowser is web-only');
}
