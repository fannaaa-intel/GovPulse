import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/config/app_config.dart';
import '../providers/admin_reports_provider.dart';
import 'pdf_photos.dart';
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
//  ── ⚠ THE PIN IS PRINTED ON THIS LETTER, AND THAT IS A DELIBERATE TRADE ────
//  It did not used to be. The original design kept the QR and the PIN as two
//  factors travelling by two channels, and the letter said so in as many words.
//  That is genuinely stronger — and it assumed a delivery channel (phone, SMS,
//  a separate email) that this deployment does not have. A second factor nobody
//  can deliver is not a second factor; it is a letter the agency cannot act on.
//
//  So the PIN is printed, in a ruled "detach and retain" box that an LGU which
//  CAN deliver it separately may simply cut off. What that costs is credential
//  secrecy: whoever holds this sheet, or a photograph of it, can advance the
//  endorsement. What replaces it:
//
//    * nothing the agency submits reaches the citizen unreviewed — every
//      progress update is held for admin approval, so a stolen letter can
//      submit for review but cannot publish;
//    * the 5-attempt / 15-minute lockout in advance_endorsement still applies;
//    * withdrawing an endorsement now REVOKES the token and PIN outright
//      (migration 20260829000000), so a letter loses its power the moment the
//      LGU takes the report back.
//
//  If a delivery channel ever exists, take the PIN box out and restore the
//  "issued separately" line in _qrBlock — nothing else here depends on it.
// ════════════════════════════════════════════════════════════════════════════

/// Long bond / Folio — 8.5 x 13 inches, at 72pt per inch.
///
/// The Philippine government standard sheet, and what an endorsement letter is
/// expected to be filed on. A4 (the previous format) is 8.27 x 11.69in, so it
/// is both narrower and nearly an inch and a half shorter — a letter laid out
/// for it prints short on the paper this office actually stocks.
///
/// Margins are carried over unchanged; the extra length becomes body room.
const PdfPageFormat kFolioPageFormat = PdfPageFormat(
  8.5 * PdfPageFormat.inch,
  13.0 * PdfPageFormat.inch,
  marginAll: 48,
);

/// Builds the endorsement letter for [report] and hands it to the platform's
/// share / print sheet.
Future<void> exportEndorsementLetter({
  required AdminReport report,
  required EndorsementCredentials credentials,
  required String reason,
  List<ReportMedia> media = const [],
  http.Client? client,
  DateTime? now,
}) async {
  final bytes = await buildEndorsementLetter(
    report: report,
    credentials: credentials,
    reason: reason,
    media: media,
    client: client,
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
  List<ReportMedia> media = const [],

  /// Injected only by tests, which cannot reach a real signed url. Production
  /// passes nothing and [preparePhotos] opens (and closes) its own client.
  http.Client? client,
  DateTime? now,
}) async {
  final at = now ?? DateTime.now();
  final scanUrl = AppConfig.scanUrl(credentials.token);

  // The citizen's photographs. Defaults to empty so every existing caller (and
  // the dialog's preview pane) keeps working unchanged and simply prints the
  // letter it printed before.
  //
  // Capped at FOUR rather than the dossier's eight. This is correspondence, not
  // a case file: the agency needs enough to recognise the site, and a letter
  // that runs to four pages of plates stops reading as a letter.
  final shots = await preparePhotos(media, limit: 4, client: client);

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
      pageFormat: kFolioPageFormat,
      // Bottom margin 24 rather than 30. On a 13-inch sheet that is still a
      // third of an inch of clear paper below the footer, and the six points
      // are body room on a document whose length is set by two free-text
      // fields.
      margin: const pw.EdgeInsets.fromLTRB(64, 42, 64, 24),
      theme: pw.ThemeData.withFont(
        base: base,
        bold: bold,
        italic: italic,
      ).copyWith(
        // 1.42 rather than 1.5. Generous enough to read as an official letter
        // rather than a form, tight enough that a long citizen description does
        // not run the body an extra page on its own.
        defaultTextStyle:
            pw.TextStyle(font: base, fontSize: 11.5, height: 1.42),
      ),
      footer: (context) => _footer(context, credentials.reference),
      // ── The spacing budget ────────────────────────────────────────────────
      // Each gap here was individually reasonable and collectively they cost
      // ~30pt. Trimmed by 2-4pt apiece: imperceptible on any single join, and
      // together they buy back most of a body paragraph.
      build: (context) => [
        _letterhead(seal),
        pw.SizedBox(height: 12),
        _title(),
        pw.SizedBox(height: 14),
        _referenceBlock(credentials.reference, at),
        pw.SizedBox(height: 13),
        _addressee(credentials.agency),
        pw.SizedBox(height: 12),
        ..._body(report, credentials.agency),
        pw.SizedBox(height: 10),
        ..._reasonSection(reason),
        pw.SizedBox(height: 10),
        ..._termsSection(credentials.agency),
        // ── The enclosure, before the closing ──────────────────────────────
        //
        // Placed here for the same reason the closing is built as one
        // unbreakable row: a signature must be the last thing on the letter.
        // Photographs appended AFTER it would read as an afterthought stapled
        // past the Mayor's name.
        //
        // Nothing here identifies the reporter. The plates carry a number and
        // whether the shot was GPS-stamped - the same two facts the attachments
        // table already prints - and the letter has never named the citizen.
        ..._photoEnclosure(shots),
        // ── Why the closing is not forced onto page one ────────────────────
        //
        // It was tempting, and it is the wrong goal. The letter's length is
        // driven by two fields an admin types — the citizen's description and
        // the basis for endorsement — so ANY spacing budget tuned to make one
        // sample fit is defeated by the next slightly longer reason. Chasing it
        // produces a document that looks cramped on short letters and still
        // breaks on long ones.
        //
        // So the closing is built to be CORRECT wherever it lands: one
        // unbreakable row, so page two can never carry a signature split from
        // its name or a QR split from its PIN. What was actually wrong before
        // was not the break — it was that the closing was ~425pt of stacked
        // sections, so page two held a signature stranded above five-sixths of
        // empty paper. At ~110pt in a single row it reads as a proper closing
        // block wherever it sits.
        pw.SizedBox(height: 12),
        // ── The closing is ONE row, signature beside the panel ─────────────
        //
        // It used to be two stacked entries, ~425pt tall between them, against
        // a typical ~80pt of room left after the terms. So the signature moved
        // to page two, page one ended with a hand-sized gap, and page two was
        // five-sixths empty with the Mayor's name floating at the top of it. A
        // government letter whose signature is stranded on its own sheet reads
        // as unfinished, and the earlier attempt to fix it by reclaiming margin
        // only postponed the problem to the next slightly longer reason.
        //
        // Side by side, the closing costs ~150pt instead of ~425 and fits under
        // the terms on nearly every letter. It is also the better arrangement
        // on its own merits: the confirmation panel reads as an enclosure
        // sitting beside the signature — which is what it is — rather than as a
        // second, unrelated section appended below it.
        //
        // Still ONE child, so MultiPage cannot split the signature from the
        // Mayor's name or the QR from its PIN. When it genuinely does not fit,
        // the whole closing moves together and page two carries a complete
        // block rather than a fragment.
        ..._closingBlock(scanUrl, credentials.reference, credentials.pin),
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
      pw.SizedBox(height: 56, width: 56, child: _seal(seal)),
      pw.SizedBox(height: 8),
      _centred(AppConfig.republic, size: 11.5),
      _centred(AppConfig.lguName, size: 14, bold: true),
      _centred(AppConfig.province, size: 11.5),
      pw.SizedBox(height: 10),
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
  // Wording follows the PIN's actual location. It used to read "issued
  // separately to that office", which stopped being true when the PIN moved
  // onto the letter — a term of an official document contradicting the box
  // printed a few inches below it.
  _numbered(2, 'The receiving office is requested to acknowledge receipt of '
      'this endorsement, to record its progress, and to record its completion, '
      'by scanning the code printed below and entering the confirmation PIN '
      'that accompanies it.'),
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
  pw.SizedBox(height: 10),
  _para(
    'Your prompt and appropriate action on this matter is earnestly requested.',
  ),
];

// ══ Closing: signature + confirmation panel, side by side ═══════════════════

/// The whole closing as ONE unbreakable row.
///
/// Left: the confirmation panel the agency acts on. Right: the signature.
/// Reading order on a letter runs to the signature LAST, and the signature is
/// conventionally on the right — so the panel takes the left column and the
/// eye finishes on the Mayor's name, as it should.
/// ⚠ Returns TWO children, and that is the whole trick.
///
/// MultiPage decides a break by measuring each child against the space left,
/// and it does that BEFORE drawing. With the separator rule inside the same
/// Column as the row, the block measured ~150pt as one indivisible unit — so
/// even with 150pt of clear paper below the last paragraph, the comparison
/// came out just short and the entire closing jumped to page two, which then
/// carried nothing else.
///
/// Splitting the rule out leaves the ROW as the only thing that has to fit.
/// The row is still one unbreakable child, so the signature can never separate
/// from the Mayor's name, nor the QR from its PIN.
List<pw.Widget> _closingBlock(String scanUrl, String reference, String pin) {
  return [
    pw.Container(height: 0.5, color: PdfColors.grey600),
    pw.SizedBox(height: 10),
    pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(child: _confirmationPanel(scanUrl, reference, pin)),
        pw.SizedBox(width: 24),
        _signatureBlock(),
      ],
    ),
  ];
}

pw.Widget _signatureBlock() {
  return pw.SizedBox(
    width: 236,
    child: pw.Column(
      // ⚠ START, not center. "Very truly yours," is a complimentary close: it
      // belongs at the LEFT EDGE of the signature column, above the rule.
      // Centred over a 240pt box it floated into the middle of the block,
      // reading as a caption for the signature rather than as the line that
      // closes the letter.
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Very truly yours,',
          style: const pw.TextStyle(fontSize: 11.5),
        ),
        // Room for a wet signature above the rule. 22pt is still a comfortable
        // band for a pen — Philippine government correspondence routinely
        // allows less — and this is the single largest block of reclaimable
        // white on the page.
        pw.SizedBox(height: 22),
        pw.Container(height: 0.75, width: 236, color: PdfColors.black),
        pw.SizedBox(height: 5),
        // The name and title CENTRE on the rule, which is the convention — the
        // close aligns left, the signatory sits under the middle of the line
        // they signed above.
        pw.Container(
          width: 236,
          alignment: pw.Alignment.center,
          child: pw.Text(
            pdfSafe(AppConfig.mayorName).toUpperCase(),
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Container(
          width: 236,
          alignment: pw.Alignment.center,
          child: pw.Text(
            AppConfig.mayorTitle,
            style: const pw.TextStyle(fontSize: 11),
          ),
        ),
      ],
    ),
  );
}

// ══ Confirmation panel ═══════════════════════════════════════════════════════

/// QR + PIN, boxed as the enclosure it is.
///
/// Previously a centred stack running the full width of the page under the
/// signature, which read as a third section of the letter rather than as the
/// tear-off instrument the agency uses. Ruled and left-aligned beside the
/// signature, it is unmistakably an attachment to the letter above it.
pw.Widget _confirmationPanel(String scanUrl, String reference, String pin) {
  return pw.Container(
    padding: const pw.EdgeInsets.fromLTRB(11, 8, 11, 9),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(width: 0.5, color: PdfColors.grey600),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        // No 'AGENCY CONFIRMATION' caption. The instruction line below already
        // says what the panel is for, and a heading that only restates the
        // sentence under it costs ~18pt — which is most of what stood between
        // this letter and closing on a single sheet.
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            pw.BarcodeWidget(
              barcode: pw.Barcode.qrCode(
                errorCorrectLevel: pw.BarcodeQRCorrectionLevel.medium,
              ),
              data: scanUrl,
              width: 68,
              height: 68,
              drawText: false,
              color: PdfColors.black,
            ),
            pw.SizedBox(width: 10),
            pw.Expanded(child: _pinBox(pin)),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          'Scan to acknowledge receipt, record progress, and completion.',
          textAlign: pw.TextAlign.center,
          style: const pw.TextStyle(fontSize: 8.5, height: 1.3),
        ),

      ],
    ),
  );
}

/// The confirmation PIN, in a ruled box the receiving office can cut off and
/// file separately from the letter.
///
/// Scissors-marked and set in wide-tracked bold at a size that survives a
/// photocopy — the agency clerk who needs this is reading a third-generation
/// copy in a binder, not the original. See the file header for why it is on the
/// page at all.
pw.Widget _pinBox(String pin) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 9),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(width: 0.75, style: pw.BorderStyle.dashed),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          'CONFIRMATION PIN',
          style: pw.TextStyle(
            fontSize: 8,
            letterSpacing: 1.4,
            color: PdfColors.grey700,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          pdfSafe(pin),
          style: pw.TextStyle(
            fontSize: 20,
            fontWeight: pw.FontWeight.bold,
            // Tracked, but less than before: the box now shares a row with the
            // QR instead of spanning the page, and 6pt of tracking on four
            // digits overflowed the narrower column.
            letterSpacing: 4,
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          'Detach and retain.',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: 7,
            color: PdfColors.grey700,
            fontStyle: pw.FontStyle.italic,
          ),
        ),
      ],
    ),
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
    height: 1.42,
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
  // 4pt, not 7. Five terms make this the densest run of gaps in the letter,
  // and three points apiece is fifteen points overall — most of what stood
  // between the signature and page one. The items stay clearly separated
  // because each is a justified block with a hanging number.
  padding: const pw.EdgeInsets.only(bottom: 4),
  child: pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.SizedBox(width: 22, child: pw.Text('$n.', style: const pw.TextStyle(fontSize: 11.5))),
      pw.Expanded(
        child: pw.Text(
          pdfSafe(text),
          textAlign: pw.TextAlign.justify,
          style: const pw.TextStyle(fontSize: 11.5, height: 1.42),
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

// == Photographic enclosure ===================================================

/// The citizen's photographs, titled in the letter's own voice.
///
/// Returns an EMPTY list when there is nothing to show, so a report filed
/// without photos produces exactly the letter it produced before rather than a
/// heading over an apology. That asymmetry is deliberate: the dossier is a
/// record and says "no photographs are attached", whereas a letter that
/// announces an enclosure it does not have is simply wrong.
List<pw.Widget> _photoEnclosure(PreparedPhotos shots) {
  if (shots.isEmpty) return const [];
  final n = shots.photos.length;
  final plates = pdfPhotoPlates(shots);

  return [
    pw.SizedBox(height: 12),
    // The heading and the FIRST row of plates are one child.
    //
    // Rendered as separate children, MultiPage broke between them: page one
    // ended with "Enclosures: 4 photographs submitted by the reporting
    // citizen" and page two opened with four unannounced pictures. Same class
    // of break as the signature that used to strand itself on its own sheet —
    // MultiPage only breaks BETWEEN children, so anything that must not
    // separate has to be ONE.
    //
    // Only the first row is bound to the heading. Binding all of them would
    // make the whole enclosure unbreakable, which for four plates is taller
    // than a page and would overflow rather than flow.
    //
    // pw.Inseparable, not a bare Column: MultiPage breaks INSIDE a multi-child
    // Column when the whole thing does not fit, which is exactly what stranded
    // the heading in the first place. Inseparable (canSpan: false by default)
    // is the package's own way of saying "this group moves together".
    pw.Inseparable(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            n == 1
                ? 'Enclosure: photograph submitted by the reporting citizen'
                : 'Enclosures: $n photographs submitted by the reporting citizen',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            'Taken at the location described above and reproduced here so that '
            'the receiving office may identify the site before inspection.',
            style: pw.TextStyle(fontSize: 9.5, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 8),
          plates.first,
        ],
      ),
    ),
    ...plates.skip(1),
  ];
}
