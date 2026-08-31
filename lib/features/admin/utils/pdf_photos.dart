import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;

import '../providers/admin_reports_provider.dart';
import 'admin_pdf.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Report photographs, prepared for print
//
//  Shared by the internal dossier (report_pdf.dart) and the endorsement letter
//  (endorsement_letter_pdf.dart). Both had the same gap and would have grown
//  the same helper twice: they described the attachments in prose and a table,
//  and attached no imagery at all. The agency that receives an endorsement
//  letter has to FIND the problem on the ground; a paragraph saying "pothole,
//  Barangay Macanaya" is not what locates it.
//
//  ── WHY THE BYTES ARE FETCHED AND RE-ENCODED ──────────────────────────────
//  Three separate reasons, none optional:
//
//   1. `report-media` is a PRIVATE bucket. The urls on ReportMedia are SIGNED
//      and time-limited, so nothing but the bytes can be embedded — a link in
//      a printed letter is useless anyway.
//   2. Phone photos are 3-5 MB each at 4000px. Eight of them would make a
//      40 MB attachment that no mail server accepts, to print at 240px wide.
//   3. The `pdf` package embeds JPEG/PNG. A HEIC straight off an iPhone, or a
//      WebP, throws when handed to PdfImage — so anything not already JPEG is
//      decoded and re-encoded rather than trusted.
//
//  ── EVERY FAILURE IS SURVIVABLE ───────────────────────────────────────────
//  A dossier missing one photo is worth incomparably more than no dossier, and
//  an export that throws because one signed url expired mid-download is the
//  worst outcome available. Every step here degrades: a photo that cannot be
//  fetched, decoded or re-encoded is DROPPED, the rest print, and the caller is
//  told how many were lost so the page can say so in words.
// ════════════════════════════════════════════════════════════════════════════

/// The widest edge a printed photo is downscaled to, in pixels.
///
/// The plate a photo prints on is ~250pt across at most. At 2x for a 150dpi-ish
/// result that is ~500px; 900 leaves room to zoom on screen without carrying a
/// 4000px original into the file. Eight photos at this size land around 1.5 MB
/// total, which mails cleanly.
const int _kMaxEdge = 900;

/// JPEG quality for the re-encode. 78 is visually clean for photographs of
/// infrastructure and roughly a third the size of 95.
const int _kJpegQuality = 78;

/// How long to wait for one photo before giving up on it.
///
/// Bounded per photo rather than for the batch: a single stalled download must
/// not hold the whole export, and the officer pressing "Download" is watching a
/// spinner (see DetailActionButton.busy).
const Duration _kFetchTimeout = Duration(seconds: 12);

/// One report photograph, decoded and ready to place on a page.
class PreparedPhoto {
  final pw.MemoryImage image;

  /// 1-based position in the report's own attachment order, so a caption can
  /// say "Photo 2" and match the attachment table in the same document.
  final int number;

  /// Taken in-app with a live GPS stamp, rather than chosen from the gallery.
  /// Printed in the caption because it is the difference between evidence and
  /// an illustration.
  final bool gpsVerified;

  const PreparedPhoto({
    required this.image,
    required this.number,
    required this.gpsVerified,
  });
}

/// The outcome of preparing a report's photos for print.
class PreparedPhotos {
  final List<PreparedPhoto> photos;

  /// Photos that were attached to the report but could not be printed —
  /// fetch failed, format unreadable, or the signed url had expired.
  final int failed;

  /// Videos on the report. They cannot be printed at all, and saying so is
  /// better than silently showing fewer attachments than the table lists.
  final int videos;

  const PreparedPhotos({
    required this.photos,
    required this.failed,
    required this.videos,
  });

  bool get isEmpty => photos.isEmpty;

  static const empty = PreparedPhotos(photos: [], failed: 0, videos: 0);
}

/// Fetch, downscale and re-encode up to [limit] of [media] for embedding.
///
/// Downloads run CONCURRENTLY: eight photos fetched one after another at a
/// second each is eight seconds of the officer watching a spinner, and they are
/// independent requests.
Future<PreparedPhotos> preparePhotos(
  List<ReportMedia> media, {
  int limit = 8,
  http.Client? client,
}) async {
  final videos = media.where((m) => m.isVideo).length;
  final photos = [for (final m in media) if (!m.isVideo) m];
  if (photos.isEmpty) {
    return PreparedPhotos(photos: const [], failed: 0, videos: videos);
  }

  // Numbered against the FULL attachment list, before the cap, so "Photo 5"
  // means the same thing here as in the attachments table.
  final numbered = <({ReportMedia m, int n})>[];
  for (var i = 0; i < media.length; i++) {
    if (!media[i].isVideo) numbered.add((m: media[i], n: i + 1));
  }

  final take = numbered.take(limit).toList();
  final owned = client == null;
  final c = client ?? http.Client();
  try {
    final results = await Future.wait([
      for (final e in take) _prepareOne(c, e.m, e.n),
    ]);
    final ok = [for (final r in results) ?r];
    return PreparedPhotos(
      photos: ok,
      // Anything beyond the cap counts as not printed, so the page can say so.
      failed: (take.length - ok.length) + (numbered.length - take.length),
      videos: videos,
    );
  } finally {
    if (owned) c.close();
  }
}

/// One photo, or null if it could not be made printable for any reason.
Future<PreparedPhoto?> _prepareOne(
  http.Client client,
  ReportMedia m,
  int number,
) async {
  try {
    final res =
        await client.get(Uri.parse(m.url)).timeout(_kFetchTimeout);
    if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;

    final bytes = _downscale(res.bodyBytes);
    if (bytes == null) return null;

    return PreparedPhoto(
      image: pw.MemoryImage(bytes),
      number: number,
      gpsVerified: m.isGpsVerified,
    );
  } catch (_) {
    // Expired signature, DNS, timeout, a corrupt file — all the same answer:
    // this photo does not print, the others still do.
    return null;
  }
}

/// Decode, downscale to [_kMaxEdge] and re-encode as JPEG.
///
/// Returns null when the bytes are not a decodable image, which is the same
/// "drop it" signal as a failed fetch.
Uint8List? _downscale(Uint8List raw) {
  final decoded = img.decodeImage(raw);
  if (decoded == null) return null;

  // Rotate to match the EXIF orientation BEFORE measuring. A portrait phone
  // photo is stored landscape with an orientation flag, and the pdf package
  // does not read EXIF — so without this the evidence prints on its side.
  final upright = img.bakeOrientation(decoded);

  final longest =
      upright.width > upright.height ? upright.width : upright.height;
  final scaled = longest <= _kMaxEdge
      ? upright
      : img.copyResize(
          upright,
          width: upright.width >= upright.height ? _kMaxEdge : null,
          height: upright.height > upright.width ? _kMaxEdge : null,
          interpolation: img.Interpolation.average,
        );

  return img.encodeJpg(scaled, quality: _kJpegQuality);
}

/// The photographs as printable page content, two to a row.
///
/// Returned as a LIST of block-level widgets so the caller can splat it into a
/// MultiPage `build`. That matters for page breaks: MultiPage only breaks
/// BETWEEN children, so handing it one big Column would push the whole plate
/// to the next page (or overflow it). One row per child lets it break between
/// rows, which is where a break belongs.
///
/// [heading] is the numbered section title in the dossier's house style; pass
/// null in the letter, which numbers nothing.
List<pw.Widget> pdfPhotoPlates(
  PreparedPhotos prepared, {
  String? heading,
  String? emptyNote,
}) {
  final out = <pw.Widget>[];

  if (prepared.isEmpty) {
    if (heading != null) out.add(pdfH1(heading));
    final note = emptyNote ??
        (prepared.videos > 0
            ? 'No photographs are attached to this report. '
                '${prepared.videos} video attachment(s) cannot be reproduced '
                'in print.'
            : 'No photographs are attached to this report.');
    out.add(pdfEmpty(note));
    return out;
  }

  for (var i = 0; i < prepared.photos.length; i += 2) {
    final left = prepared.photos[i];
    final right =
        i + 1 < prepared.photos.length ? prepared.photos[i + 1] : null;
    final row = pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 10),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: _plate(left)),
            pw.SizedBox(width: 12),
            // An odd count leaves the last photo at half width rather than
            // stretched across the page, so the grid stays a grid.
            pw.Expanded(
              child: right == null ? pw.SizedBox() : _plate(right),
            ),
          ],
        ),
    );

    // The heading rides with the FIRST row as one child.
    //
    // Emitted separately, MultiPage broke between them — a page ending with
    // "6. Photographs" and the next opening with unannounced pictures. It
    // breaks only BETWEEN children, so a heading that must not separate from
    // its content has to be part of the same one. Only the first row is bound:
    // binding all of them makes the block taller than a page, which overflows
    // rather than flows.
    if (i == 0 && heading != null) {
      // pw.Inseparable, not a bare Column — MultiPage happily breaks INSIDE a
      // multi-child Column when the group does not fit, which is the very
      // thing that stranded the heading. canSpan defaults to false, which is
      // what "these move together" means here.
      out.add(
        pw.Inseparable(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [pdfH1(heading), row],
          ),
        ),
      );
    } else {
      out.add(row);
    }
  }

  // Anything not printed is stated. Silently showing three photos for a report
  // whose table lists five invites the reader to assume the other two do not
  // exist.
  final missing = <String>[];
  if (prepared.failed > 0) {
    missing.add('${prepared.failed} photograph(s) could not be reproduced');
  }
  if (prepared.videos > 0) {
    missing.add('${prepared.videos} video attachment(s) cannot be printed');
  }
  if (missing.isNotEmpty) {
    out.add(
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 2),
        child: pw.Text(
          '${missing.join('; ')}. See the attachments table above.',
          style: pw.TextStyle(fontSize: 8.5, color: pdfMuted),
        ),
      ),
    );
  }
  return out;
}

/// One framed photograph with its caption.
pw.Widget _plate(PreparedPhoto p) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Container(
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: pdfLine),
        ),
        padding: const pw.EdgeInsets.all(3),
        // A fixed box with BoxFit.contain, so a portrait and a landscape photo
        // occupy the same footprint and rows stay level. Without it a tall
        // photo drags its row's height and the grid staggers.
        child: pw.SizedBox(
          height: 150,
          width: double.infinity,
          child: pw.Center(
            child: pw.Image(p.image, fit: pw.BoxFit.contain),
          ),
        ),
      ),
      pw.SizedBox(height: 3),
      pw.Text(
        pdfSafe(
          'Photo ${p.number} - ${p.gpsVerified ? 'in-app camera, GPS-stamped' : 'from device gallery'}',
        ),
        style: pw.TextStyle(fontSize: 8, color: pdfMuted),
      ),
    ],
  );
}
