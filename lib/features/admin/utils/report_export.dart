import '../providers/admin_reports_provider.dart';
import 'csv_saver.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Reports → CSV export
//
//  Turns a list of AdminReport rows into a spreadsheet-friendly CSV and hands it
//  to the platform saver (browser download on web, share sheet on mobile).
// ════════════════════════════════════════════════════════════════════════════

const List<String> _headers = [
  'Date',
  'Report ID',
  'Category',
  'Status',
  'Barangay',
  'Address',
  'Anonymous',
  'Submitter',
  'Role',
  'Media',
  'Description',
];

/// Build the full CSV text (header row + one row per report).
String buildReportsCsv(List<AdminReport> reports) {
  final rows = <String>[_headers.map(_csvCell).join(',')];
  for (final r in reports) {
    rows.add([
      _fmtDate(r.createdAt),
      r.shortId,
      r.category,
      reportStatusLabel(r.status),
      r.barangay ?? '',
      r.address ?? '',
      r.isAnonymous ? 'Yes' : 'No',
      r.isAnonymous ? 'Anonymous' : (r.submitterName ?? ''),
      r.isAnonymous ? '' : (r.submitterRole ?? ''),
      r.mediaCount.toString(),
      r.remarks,
    ].map(_csvCell).join(','));
  }
  return rows.join('\r\n');
}

/// Build the CSV and trigger the platform save/share.
Future<void> exportReportsCsv({
  required String filename,
  required List<AdminReport> reports,
}) => saveCsv(filename, buildReportsCsv(reports));

// ── helpers ──────────────────────────────────────────────────────────────────

/// RFC-4180 cell quoting: wrap in quotes when the value contains a comma, quote,
/// CR or LF, and double any embedded quotes.
String _csvCell(String value) {
  final needsQuoting =
      value.contains(',') ||
      value.contains('"') ||
      value.contains('\n') ||
      value.contains('\r');
  final escaped = value.replaceAll('"', '""');
  return needsQuoting ? '"$escaped"' : escaped;
}

String _fmtDate(DateTime? d) {
  if (d == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}
