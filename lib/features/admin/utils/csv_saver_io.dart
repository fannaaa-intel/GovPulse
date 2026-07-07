import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Mobile / desktop: write the CSV to a temp file and open the share sheet so
/// the admin can save it to Files, email it, etc.
Future<void> saveCsv(String filename, String csv) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsString(csv);
  await Share.shareXFiles(
    [XFile(file.path, mimeType: 'text/csv', name: filename)],
    subject: filename,
  );
}
