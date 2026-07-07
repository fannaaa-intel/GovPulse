import 'dart:convert';
import 'dart:typed_data';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

/// Web: build a Blob from the CSV bytes and click a hidden <a download> so the
/// browser downloads the file to the user's Downloads folder.
Future<void> saveCsv(String filename, String csv) async {
  // A UTF-8 BOM makes Excel open accented characters (barangay names) correctly.
  // Must be a Uint8List (typed array) — a plain List<int> gets stringified by
  // the Blob constructor into "239,187,191,..." instead of written as bytes.
  final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(csv)]);
  final blob = html.Blob(<dynamic>[bytes], 'text/csv');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}
