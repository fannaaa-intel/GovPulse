import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/config/app_config.dart';
import '../providers/admin_reports_provider.dart';
import 'admin_pdf.dart' show pdfSafe;

// ════════════════════════════════════════════════════════════════════════════
//  Endorsement letter — the formal document handed to the external agency
//
//  This is NOT the admin_pdf.dart house style, and the difference is
//  deliberate. The dossier and the analytics report are internal working
//  documents: sans-serif, section numbers, fact tables, grey rules. This is an
//  outgoing government communication over the Mayor's signature — the reader is
//  a regional office of DPWH or DENR, and it has to look like every other
//  endorsement letter that crosses their desk.
//
//  So: Times, centred letterhead, one hairline rule, justified prose, and a
//  signature block. Strictly black on white — no coloured header, no filled
//  boxes, no chips. It is photocopied, faxed, and filed in a binder, and every
//  one of those steps destroys colour while leaving type intact.
//
//  Times is one of the PDF standard-14 core fonts, so it needs no asset, no
//  download, and no licence — but it only covers Latin-1, which is why every
//  string still goes through pdfSafe() to fold em dashes and smart quotes into
//  glyphs the font actually has.
//
//  ⚠ THE PIN IS NEVER PRINTED HERE. The QR and the PIN are two factors and this
//  sheet of paper is the first one; putting the second one beside it would make
//  the pair worth exactly as much as the paper. The PIN is shown once on screen
//  and sent to the agency separately.
// ════════════════════════════════════════════════════════════════════════════

/// Builds the endorsement letter for [report] and hands it to the platform's
/// share / print sheet.
Future<void> exportEndorsementLetter({
  required AdminReport report,
  required EndorsementCredentials credentials,
  required String reason,
  DateTime? now,
}) async {
  final bytes = await buildEndorsementLetter(
    report: report,
    credentials: credentials,
    reason: reason,
    now: now,
  );
  await Printing.sharePdf(
    bytes: bytes,
    filename: 'Endorsement-${credentials.reference}.pdf',
  );
}

/// The raw PDF, for the preview pane in the success dialog as well as export.
Future<Uint8List> buildEndorsementLetter({
  required AdminReport report,
  required EndorsementCredentials credentials,
  required String reason,
  DateTime? now,
}) async {
  final at = now ?? DateTime.now();
  final scanUrl = AppConfig.scanUrl(credentials.token);

  // Times, TimesBold, TimesItalic are PDF standard-14 core fonts: present in
  // every conforming reader, embedded by nobody, fetched from nowhere. That
  // last part matters — PdfGoogleFonts would pull a webfont over the network,
  // so an admin printing an endorsement on a bad connection would wait on
  // Google Fonts to produce a government letter. These are also metrically
  // Times New Roman, which is what the document is meant to look like.
  final base = pw.Font.times();
  final bold = pw.Font.timesBold();
  final italic = pw.Font.timesItalic();

  final seal = await _loadSeal();

  final doc = pw.Document(
    title: 'Endorsement Letter ${credentials.reference}',
    author: AppConfig.lguName,
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(64, 48, 64, 48),
      theme: pw.ThemeData.withFont(
        base: base,
        bold: bold,
        italic: italic,
      ).copyWith(
        defaultTextStyle: pw.TextStyle(font: base, fontSize: 11.5, height: 1.5),
      ),
      footer: (context) => _footer(context, credentials.reference),
      build: (context) => [
        _letterhead(seal),
        pw.SizedBox(height: 18),
        _title(),
        pw.SizedBox(height: 22),
        _referenceBlock(credentials.reference, at),
        pw.SizedBox(height: 20),
        _addressee(credentials.agency),
        pw.SizedBox(height: 18),
        ..._body(report, credentials.agency),
        pw.SizedBox(height: 14),
        ..._reasonSection(reason),
        pw.SizedBox(height: 14),
        ..._termsSection(credentials.agency),
        pw.SizedBox(height: 26),
        _signatureBlock(),
        pw.SizedBox(height: 24),
        _qrBlock(scanUrl, credentials.reference),
      ],
    ),
  );

  return doc.save();
}

// ══ Letterhead ════════════════════════════════════════════════════════════════

/// The municipal seal, if one has been configured.
///
/// Returns null when [AppConfig.sealAssetPath] is unset or the asset is missing,
/// and the letterhead then draws a labelled placeholder ring. A missing seal
/// must never fail the export — an admin needs the letter more than they need
/// the crest.
Future<pw.ImageProvider?> _loadSeal() async {
  final path = AppConfig.sealAssetPath;
  if (path.isEmpty) return null;
  try {
    final data = await rootBundle.load(path);
    return pw.MemoryImage(data.buffer.asUint8List());
  } catch (_) {
    return null;
  }
}

pw.Widget _letterhead(pw.ImageProvider? seal) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      pw.SizedBox(height: 64, width: 64, child: _seal(seal)),
      pw.SizedBox(height: 10),
      _centred(AppConfig.republic, size: 11.5),
      _centred(AppConfig.lguName, size: 14, bold: true),
      _centred(AppConfig.province, size: 11.5),
      pw.SizedBox(height: 12),
      // The single hairline rule. The whole document's structure rests on
      // spacing and type weight; this is the only drawn line above the footer.
      pw.Container(height: 0.75, color: PdfColors.black),
    ],
  );
}

/// Placeholder crest: a double ring with the municipality's initials.
///
/// Vector, so it stays crisp at any print resolution and costs nothing in file
/// size. Reads as an intentional placeholder rather than a broken image, which
/// is the honest thing for a document that may be sent before real artwork
/// exists.
pw.Widget _seal(pw.ImageProvider? seal) {
  if (seal != null) return pw.Image(seal, fit: pw.BoxFit.contain);

  return pw.Container(
    decoration: pw.BoxDecoration(
      shape: pw.BoxShape.circle,
      border: pw.Border.all(width: 1.2),
    ),
    child: pw.Center(
      child: pw.Container(
        margin: const pw.EdgeInsets.all(4),
        decoration: pw.BoxDecoration(
          shape: pw.BoxShape.circle,
          border: pw.Border.all(width: 0.5),
        ),
        child: pw.Center(
          child: pw.Text(
            'LGU\nAPARRI',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 7, height: 1.25),
          ),
        ),
      ),
    ),
  );
}

pw.Widget _centred(String text, {double size = 11.5, bool bold = false}) =>
    pw.Text(
      pdfSafe(text),
      textAlign: pw.TextAlign.center,
      style: pw.TextStyle(
        fontSize: size,
        letterSpacing: bold ? 0.4 : 0,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    );

pw.Widget _title() => pw.Center(
  child: pw.Text(
    'ENDORSEMENT LETTER',
    style: pw.TextStyle(
      fontSize: 14.5,
      fontWeight: pw.FontWeight.bold,
      letterSpacing: 1.6,
    ),
  ),
);

// ══ Reference + addressee ═════════════════════════════════════════════════════

pw.Widget _referenceBlock(String reference, DateTime at) {
  return pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        'Reference No.: $reference',
        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
      ),
      pw.Text(
        DateFormat('d MMMM yyyy').format(at),
        style: const pw.TextStyle(fontSize: 11),
      ),
    ],
  );
}

pw.Widget _addressee(String agency) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        'THE REGIONAL / DISTRICT OFFICER',
        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
      ),
      pw.Text(pdfSafe(agency), style: const pw.TextStyle(fontSize: 11)),
      pw.Text('Province of Cagayan', style: const pw.TextStyle(fontSize: 11)),
      pw.SizedBox(height: 12),
      pw.Text('Sir / Madam:', style: const pw.TextStyle(fontSize: 11.5)),
    ],
  );
}

// ══ Body ══════════════════════════════════════════════════════════════════════

/// The report narrated as prose rather than tabulated.
///
/// A fact table is the right shape for the internal dossier and the wrong shape
/// here: this paragraph is what a receiving officer reads to understand what
/// they are being asked to act on, and it has to survive being read aloud in a
/// meeting.
List<pw.Widget> _body(AdminReport r, String agency) {
  final filed = r.createdAt == null
      ? 'on a date not recorded'
      : 'on ${DateFormat('d MMMM yyyy').format(r.createdAt!)} at '
            '${DateFormat('h:mm a').format(r.createdAt!)}';

  final where = _place(r);
  final description = r.remarks.trim();

  return [
    _para(
      'Respectfully endorsing to your good office the herein described citizen '
      'report received by the ${AppConfig.lguName} through the GovPulse '
      'community reporting system, the subject matter of which falls within '
      'the mandate and jurisdiction of $agency.',
    ),
    pw.SizedBox(height: 12),
    _heading('PARTICULARS OF THE REPORT'),
    pw.SizedBox(height: 6),
    _fact('Report Reference', 'RPT-${r.shortId}'),
    _fact('Nature of Report', r.category),
    _fact('Date and Time Filed', _capitalise(filed.replaceFirst('on ', ''))),
    _fact('Place of Incident', where ?? 'Not specified by the reporter'),
    _fact(
      'Corroboration',
      r.isCorroborated
          ? '${r.reporterCount} separate citizens have reported this same '
                'matter.'
          : 'Filed by one citizen.',
    ),
    pw.SizedBox(height: 10),
    _heading('DESCRIPTION AS REPORTED'),
    pw.SizedBox(height: 6),
    if (description.isEmpty)
      _para(
        'The reporter submitted no written description. Supporting photographs '
        'are retained by this office and are available on request.',
        italic: true,
      )
    else
      // Quoted, because it is the citizen's own account and must not read as
      // the LGU's characterisation of the facts.
      _para('"$description"'),
  ];
}

List<pw.Widget> _reasonSection(String reason) => [
  _heading('BASIS FOR ENDORSEMENT'),
  pw.SizedBox(height: 6),
  _para(reason),
];

/// The terms the endorsement is made under.
///
/// Plain undertakings, not legalese: what the LGU is asking for, what it will
/// keep doing, and how the receiving office acknowledges and closes the matter.
List<pw.Widget> _termsSection(String agency) => [
  _heading('TERMS OF THIS ENDORSEMENT'),
  pw.SizedBox(height: 6),
  _numbered(1, 'Primary responsibility for acting on the matter described '
      'above is hereby transferred to $agency upon acknowledgement of receipt.'),
  _numbered(2, 'The receiving office is requested to acknowledge receipt of '
      'this endorsement, and to record its completion, by scanning the code '
      'printed below and entering the confirmation PIN issued separately to '
      'that office by this Municipality.'),
  _numbered(3, 'The ${AppConfig.lguName} shall retain the original report, its '
      'supporting evidence, and the identity of the reporting citizen, and '
      'shall make these available to the receiving office upon written '
      'request.'),
  _numbered(4, 'The identity of the reporting citizen is withheld from this '
      'endorsement as a matter of policy and, where the report was filed '
      'anonymously, is not held by this Municipality at all.'),
  _numbered(5, 'This Municipality shall inform the reporting citizen of the '
      'progress of the matter as recorded through the confirmation process '
      'described in item 2.'),
  pw.SizedBox(height: 12),
  _para(
    'Your prompt and appropriate action on this matter is earnestly requested.',
  ),
];

// ══ Signature ═════════════════════════════════════════════════════════════════

pw.Widget _signatureBlock() {
  return pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.end,
    children: [
      pw.SizedBox(
        width: 240,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(
              'Very truly yours,',
              style: const pw.TextStyle(fontSize: 11.5),
            ),
            // Room for a wet signature above the rule.
            pw.SizedBox(height: 46),
            pw.Container(height: 0.75, width: 220, color: PdfColors.black),
            pw.SizedBox(height: 5),
            pw.Text(
              pdfSafe(AppConfig.mayorName).toUpperCase(),
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              AppConfig.mayorTitle,
              style: const pw.TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
    ],
  );
}

// ══ QR ════════════════════════════════════════════════════════════════════════

pw.Widget _qrBlock(String scanUrl, String reference) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      pw.Container(height: 0.5, color: PdfColors.grey600),
      pw.SizedBox(height: 14),
      pw.BarcodeWidget(
        barcode: pw.Barcode.qrCode(
          errorCorrectLevel: pw.BarcodeQRCorrectionLevel.medium,
        ),
        data: scanUrl,
        width: 108,
        height: 108,
        drawText: false,
        color: PdfColors.black,
      ),
      pw.SizedBox(height: 8),
      pw.Text(
        'Scan to confirm receipt and update status.',
        style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 3),
      pw.Text(
        'A confirmation PIN is required. It is issued to your office separately '
        'and does not appear on this letter.',
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          fontSize: 9,
          color: PdfColors.grey700,
          fontStyle: pw.FontStyle.italic,
        ),
      ),
      pw.SizedBox(height: 4),
      pw.Text(
        reference,
        style: pw.TextStyle(
          fontSize: 8.5,
          color: PdfColors.grey700,
          letterSpacing: 0.6,
        ),
      ),
    ],
  );
}

pw.Widget _footer(pw.Context context, String reference) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(top: 12),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          '${AppConfig.lguName} - $reference',
          style: pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700),
        ),
        pw.Text(
          'Page ${context.pageNumber} of ${context.pagesCount}',
          style: pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700),
        ),
      ],
    ),
  );
}

// ── Type helpers ─────────────────────────────────────────────────────────────

pw.Widget _heading(String text) => pw.Text(
  pdfSafe(text),
  style: pw.TextStyle(
    fontSize: 11,
    fontWeight: pw.FontWeight.bold,
    letterSpacing: 0.8,
  ),
);

pw.Widget _para(String text, {bool italic = false}) => pw.Paragraph(
  text: pdfSafe(text),
  textAlign: pw.TextAlign.justify,
  margin: pw.EdgeInsets.zero,
  style: pw.TextStyle(
    fontSize: 11.5,
    height: 1.55,
    fontStyle: italic ? pw.FontStyle.italic : pw.FontStyle.normal,
  ),
);

/// A label / value line in the particulars list. Fixed-width label column so
/// the values align down the page like a formal schedule.
pw.Widget _fact(String label, String value) => pw.Padding(
  padding: const pw.EdgeInsets.only(bottom: 3),
  child: pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.SizedBox(
        width: 132,
        child: pw.Text(
          '${pdfSafe(label)}:',
          style: const pw.TextStyle(fontSize: 11),
        ),
      ),
      pw.Expanded(
        child: pw.Text(
          pdfSafe(value),
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
      ),
    ],
  ),
);

pw.Widget _numbered(int n, String text) => pw.Padding(
  padding: const pw.EdgeInsets.only(bottom: 7),
  child: pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.SizedBox(width: 22, child: pw.Text('$n.', style: const pw.TextStyle(fontSize: 11.5))),
      pw.Expanded(
        child: pw.Text(
          pdfSafe(text),
          textAlign: pw.TextAlign.justify,
          style: const pw.TextStyle(fontSize: 11.5, height: 1.5),
        ),
      ),
    ],
  ),
);

String? _place(AdminReport r) {
  final b = r.barangay?.trim() ?? '';
  final a = r.address?.trim() ?? '';
  if (b.isEmpty && a.isEmpty) return null;
  if (b.isEmpty) return a;
  if (a.isEmpty) return 'Barangay $b';
  return '$a, Barangay $b';
}

String _capitalise(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
