// Cross-platform "save this CSV" entry point. The real implementation is chosen
// at compile time: a browser download on web, a share sheet on mobile/desktop.
//   • web    → csv_saver_web.dart  (Blob + <a download>)
//   • io      → csv_saver_io.dart   (temp file + share_plus)
export 'csv_saver_io.dart' if (dart.library.html) 'csv_saver_web.dart';
