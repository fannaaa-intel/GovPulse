// Not a test: a renderer. Writes both PDFs to the scratchpad so they can be
// rasterised and LOOKED at, which is the only thing that catches a stranded
// signature or a plate that overflows its page.
//
// Skipped by default so it never runs in CI — flip _kWrite to true, or run
// with `--dart-define=WRITE_PDFS=true`.
@Tags(['probe'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/admin/providers/admin_reports_provider.dart';
import 'package:govpulse/features/admin/utils/endorsement_letter_pdf.dart';
import 'package:govpulse/features/admin/utils/report_pdf.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

const _kOut = r'C:\Users\DELL\AppData\Local\Temp\claude'
    r'\c--Users-DELL-govpulse\831c8796-9f4a-413d-9c5e-6779a5b74858\scratchpad';

/// Photo-like test images: a coloured field with a marker, so orientation and
/// ordering are visible in a raster.
Uint8List _shot(int w, int h, int seed) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(60 + seed * 30, 110, 150 - seed * 12));
  img.fillRect(im,
      x1: 10, y1: 10, x2: w ~/ 2, y2: h ~/ 3,
      color: img.ColorRgb8(240, 200 - seed * 20, 60));
  img.drawString(im, 'PHOTO ${seed + 1}',
      font: img.arial48, x: 20, y: h ~/ 2, color: img.ColorRgb8(255, 255, 255));
  return img.encodeJpg(im, quality: 85);
}

class _ShotClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final n = int.tryParse(
            RegExp(r'(\d+)\.jpg').firstMatch(request.url.toString())?.group(1) ??
                '0') ??
        0;
    // Alternate portrait and landscape — the mixed case is what makes a naive
    // grid stagger.
    final bytes = n.isEven ? _shot(1600, 1200, n) : _shot(1200, 1600, n);
    return http.StreamedResponse(Stream.value(bytes), 200);
  }
}

AdminReport _report({int media = 4}) => AdminReport(
      id: '3f2a1b6c-8d4e-4f7a-9b1c-2e5d6a7b8c9d',
      shortId: '3F2A1B6C',
      categoryKey: 'road',
      category: 'Road & Infrastructure',
      barangay: 'Macanaya',
      address: 'Corner of Rizal St. and Maharlika Highway',
      remarks: 'Large pothole spanning both lanes of the national road. '
          'Two motorcycles have already fallen. It floods and becomes '
          'invisible after rain.',
      status: ReportStatus.underReview,
      isAnonymous: false,
      submitterName: 'Maria Santos',
      submitterPhotoUrl: null,
      submitterRole: 'citizen',
      mediaCount: media,
      createdAt: DateTime(2026, 7, 28, 14, 32),
      confirmCount: 3,
    );

List<ReportMedia> _media(int n) => [
      for (var i = 0; i < n; i++)
        ReportMedia(
          url: 'https://example.invalid/$i.jpg',
          mimeType: 'image/jpeg',
          source: i.isEven ? 'camera' : 'upload',
        ),
    ];

/// A video sitting FIRST, then photos — the ordering that catches caption
/// numbering drifting out of step with the attachments table.
List<ReportMedia> _mixed() => [
      ReportMedia(url: 'https://example.invalid/clip.mp4', mimeType: 'video/mp4'),
      ReportMedia(
          url: 'https://example.invalid/1.jpg',
          mimeType: 'image/jpeg',
          source: 'camera'),
      ReportMedia(
          url: 'https://example.invalid/2.jpg',
          mimeType: 'image/jpeg',
          source: 'upload'),
    ];

/// Nothing but a video: the report has an attachment, and the PDF has no way
/// to show it.
List<ReportMedia> _videoOnly() => [
      ReportMedia(url: 'https://example.invalid/clip.mp4', mimeType: 'video/mp4'),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const write = bool.fromEnvironment('WRITE_PDFS');

  test('write the letter and the dossier for visual inspection', () async {
    for (final n in [0, 1, 3, 4]) {
      final bytes = await buildEndorsementLetter(
        report: _report(media: n),
        credentials: const EndorsementCredentials(
          token: 'Zm9vYmFyYmF6cXV4LTEyMzQ1Njc4OTBhYmNkZWZnaGk',
          pin: '4821',
          reference: 'END-3F2A1B6C',
          agency: 'DPWH',
        ),
        reason: 'The affected carriageway forms part of the Maharlika '
            'Highway, a national road under DPWH jurisdiction, and is outside '
            'the maintenance authority of this Municipality.',
        media: _media(n),
        client: _ShotClient(),
        now: DateTime(2026, 8, 31, 10, 0),
      );
      File('$_kOut\\letter_$n.pdf').writeAsBytesSync(bytes);
    }

    // Mixed and video-only, which is where the caption/table numbering and the
    // "cannot be printed" line have to hold.
    File('$_kOut\\dossier_mixed.pdf').writeAsBytesSync(await buildReportPdf(
      report: _report(media: 3),
      media: _mixed(),
      notes: const [],
      client: _ShotClient(),
      now: DateTime(2026, 8, 31, 10, 0),
    ));
    File('$_kOut\\dossier_videoonly.pdf').writeAsBytesSync(await buildReportPdf(
      report: _report(media: 1),
      media: _videoOnly(),
      notes: const [],
      client: _ShotClient(),
      now: DateTime(2026, 8, 31, 10, 0),
    ));

    for (final n in [0, 5]) {
      final bytes = await buildReportPdf(
        report: _report(media: n),
        media: _media(n),
        notes: const [],
        client: _ShotClient(),
        now: DateTime(2026, 8, 31, 10, 0),
      );
      File('$_kOut\\dossier_$n.pdf').writeAsBytesSync(bytes);
    }
  }, skip: write ? false : 'probe only; run with --dart-define=WRITE_PDFS=true');
}
