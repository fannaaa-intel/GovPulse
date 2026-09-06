import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

// ════════════════════════════════════════════════════════════════════════════
//  Admin PDF house style
//
//  The shared look every printed GovPulse document uses, so the analytics
//  findings report and a single-report dossier read as the same stationery
//  rather than two designs that happen to be PDFs.
//
//  Deliberately PLAIN: black ink on white, hairline rules, grey section
//  labels. No coloured banner, no icons, no emoji — this is a document an LGU
//  prints, files and attaches to correspondence, and colour that carries
//  meaning on screen becomes noise (or a photocopier smudge) on paper. Meaning
//  is carried by words: a status says "Rejected", it does not rely on red.
// ════════════════════════════════════════════════════════════════════════════

// ── Palette ─────────────────────────────────────────────────────────────────
final pdfInk = PdfColor.fromInt(0xFF1F2937);
final pdfMuted = PdfColor.fromInt(0xFF6B7280);
final pdfLine = PdfColor.fromInt(0xFFE5E7EB);
final pdfSubtle = PdfColor.fromInt(0xFFF3F4F6);

/// Glyphs that have a good ASCII/Latin-1 equivalent. Anything mapped here keeps
/// its meaning on the page; anything *not* mapped and outside Latin-1 is caught
/// by the backstop in [pdfSafe] below.
///
/// Kept deliberately small: this is for characters where a blind substitution
/// would lose information (a "->" really does read as an arrow), not a general
/// transliteration table.
const _pdfGlyphMap = <String, String>{
  // Dashes and hyphens. The AI narrative is the main source of these — models
  // emit U+2011 (non-breaking hyphen) and U+2212 (minus) freely.
  '–': '-', // – en dash
  '—': '-', // — em dash
  '‐': '-', // ‐ hyphen
  '‑': '-', // ‑ non-breaking hyphen
  '−': '-', // − minus
  // Quotes and punctuation.
  '“': '"', // “
  '”': '"', // ”
  '„': '"', // „
  '‘': "'", // ‘
  '’': "'", // ’
  '‚': "'", // ‚
  '…': '...', // …
  '•': '-', // • bullet
  '·': '-', // · middle dot (Latin-1, but reads as a separator here)
  '′': "'", // ′ prime
  '″': '"', // ″ double prime
  // Symbols that carry meaning.
  '★': ' / 5', // ★ rating mark
  '☆': ' / 5', // ☆
  '→': '->', // →
  '←': '<-', // ←
  '≥': '>=', // ≥
  '≤': '<=', // ≤
  '≠': '!=', // ≠
  '≈': '~', // ≈
  '₱': 'PHP ', // ₱ peso — the LGU currency, and NOT in Latin-1
  '€': 'EUR ', // €
  '™': '(TM)', // ™
  '℗': '(P)', // ℗
  // Whitespace that isn't a space. Escaped rather than pasted literally:
  // these are invisible in an editor, and a bare one in source is
  // indistinguishable from the space beside it.
  '\u00A0': ' ', // non-breaking space
  '\u2007': ' ', // figure space
  '\u202F': ' ', // narrow no-break space
  '\u2009': ' ', // thin space
  '\u200B': '', // zero-width space
  '\u200C': '', // zero-width non-joiner
  '\u200D': '', // zero-width joiner
  '\uFEFF': '', // BOM / zero-width no-break space
};

/// PDF-safe text.
///
/// The standard-14 PDF fonts this document uses (Helvetica, Times) are Type1
/// fonts whose encoding covers **exactly U+0000-U+00FF** — `isRuneSupported`
/// in the `pdf` package is literally a `0x00..0xff` range check. Every
/// codepoint above that renders as a blank "tofu" box on the page.
///
/// This runs in two passes:
///
///  1. Map the glyphs that have a meaningful equivalent (see [_pdfGlyphMap]).
///  2. **Backstop:** drop anything still outside Latin-1.
///
/// Pass 2 is the important one. Section 4 of the findings report prints text
/// written by the AI model, which is free-form output that will keep finding
/// new glyphs a hand-maintained list has never seen — an allowlist is the only
/// version of this that stays correct. Combining marks are dropped rather than
/// replaced (so "é" typed as e+U+0301 degrades to "e", not "e?"); anything
/// else unmapped becomes "?" so a dropped character is visible to whoever
/// proofreads the document rather than silently changing the text.
String pdfSafe(String s) {
  if (s.isEmpty) return s;

  // Fast path: pure ASCII, which is the overwhelming majority of the document.
  var needsWork = false;
  for (final unit in s.codeUnits) {
    if (unit > 0x7F) {
      needsWork = true;
      break;
    }
  }
  if (!needsWork) return s;

  var mapped = s;
  for (final entry in _pdfGlyphMap.entries) {
    if (mapped.contains(entry.key)) {
      mapped = mapped.replaceAll(entry.key, entry.value);
    }
  }

  final buf = StringBuffer();
  for (final rune in mapped.runes) {
    if (rune <= 0xFF) {
      buf.writeCharCode(rune);
      continue;
    }
    // Combining marks (and the variation selectors / joiners that decorate
    // emoji) add nothing on their own — dropping one leaves the base letter
    // readable, where a "?" would corrupt the word.
    if (_isCombining(rune) || _isFormatting(rune)) continue;
    buf.write('?');
  }
  return buf.toString();
}

/// Unicode combining-mark blocks: diacritics that modify the preceding letter.
bool _isCombining(int rune) =>
    (rune >= 0x0300 && rune <= 0x036F) || // combining diacritical marks
    (rune >= 0x1AB0 && rune <= 0x1AFF) ||
    (rune >= 0x1DC0 && rune <= 0x1DFF) ||
    (rune >= 0x20D0 && rune <= 0x20FF) ||
    (rune >= 0xFE20 && rune <= 0xFE2F);

/// Zero-width formatting characters and emoji modifiers, which carry no ink.
bool _isFormatting(int rune) =>
    (rune >= 0xFE00 && rune <= 0xFE0F) || // variation selectors
    (rune >= 0xE0100 && rune <= 0xE01EF) ||
    (rune >= 0x1F3FB && rune <= 0x1F3FF); // skin-tone modifiers

/// The masthead: wordmark, document title, a row of meta chips, and the issuing
/// LGU. Ruled off with a heavy black underline — the document's only strong
/// line, and what makes it read as letterhead without a colour bar.
pw.Widget pdfTitleBlock({
  required String title,
  required List<({String label, String value})> chips,
}) {
  return pw.Container(
    padding: const pw.EdgeInsets.only(bottom: 14),
    decoration: pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: pdfInk, width: 2)),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'GovPulse',
          style: pw.TextStyle(
            fontSize: 24,
            fontWeight: pw.FontWeight.bold,
            color: pdfInk,
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          pdfSafe(title),
          style: pw.TextStyle(fontSize: 14, color: pdfInk),
        ),
        pw.SizedBox(height: 10),
        pw.Row(
          children: [
            for (var i = 0; i < chips.length; i++) ...[
              if (i > 0) pw.SizedBox(width: 10),
              pdfMetaChip(chips[i].label, chips[i].value),
            ],
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Local Government Unit of Aparri, Cagayan',
          style: pw.TextStyle(fontSize: 9, color: pdfMuted),
        ),
      ],
    ),
  );
}

pw.Widget pdfMetaChip(String label, String value) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: pw.BoxDecoration(
      color: pdfSubtle,
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          pdfSafe(label.toUpperCase()),
          style: pw.TextStyle(
            fontSize: 6.5,
            color: pdfMuted,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 0.4,
          ),
        ),
        pw.SizedBox(height: 1),
        pw.Text(pdfSafe(value), style: pw.TextStyle(fontSize: 9, color: pdfInk)),
      ],
    ),
  );
}

/// Numbered section heading.
pw.Widget pdfH1(String text) => pw.Padding(
  padding: const pw.EdgeInsets.only(bottom: 8),
  child: pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.only(bottom: 4),
    decoration: pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: pdfLine, width: 1)),
    ),
    child: pw.Text(
      pdfSafe(text),
      style: pw.TextStyle(
        fontSize: 15,
        fontWeight: pw.FontWeight.bold,
        color: pdfInk,
      ),
    ),
  ),
);

/// Small grey label above a table.
pw.Widget pdfH2(String text) => pw.Padding(
  padding: const pw.EdgeInsets.only(top: 12, bottom: 5),
  child: pw.Text(
    pdfSafe(text.toUpperCase()),
    style: pw.TextStyle(
      fontSize: 9,
      fontWeight: pw.FontWeight.bold,
      color: pdfMuted,
      letterSpacing: 0.5,
    ),
  ),
);

/// The grey box that opens a section: the whole thing in one or two sentences,
/// for a reader who will not read the tables.
pw.Widget pdfSummaryLine(String text) => pw.Container(
  width: double.infinity,
  padding: const pw.EdgeInsets.all(9),
  decoration: pw.BoxDecoration(
    color: pdfSubtle,
    borderRadius: pw.BorderRadius.circular(5),
  ),
  child: pw.Text(
    pdfSafe(text),
    style: pw.TextStyle(fontSize: 10, color: pdfInk, lineSpacing: 2),
  ),
);

pw.Widget pdfPara(String text) => pw.Padding(
  padding: const pw.EdgeInsets.only(top: 2),
  child: pw.Text(
    pdfSafe(text),
    style: pw.TextStyle(fontSize: 10, color: pdfInk, lineSpacing: 2.5),
  ),
);

pw.Widget pdfEmpty(String text) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(vertical: 6),
  child: pw.Text(
    pdfSafe(text),
    style: pw.TextStyle(
      fontSize: 10,
      color: pdfMuted,
      fontStyle: pw.FontStyle.italic,
    ),
  ),
);

/// A "Findings" bullet list. Blank entries are dropped, so callers can build
/// the list with inline conditionals.
pw.Widget pdfFindings(List<String> items, {String heading = 'Findings'}) {
  final visible = items.where((s) => s.trim().isNotEmpty).toList();
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pdfH2(heading),
      ...visible.map(
        (s) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // A drawn dot rather than a "•" glyph — the built-in font has no
              // bullet, so the character alone would render as a blank box.
              //
              // The dot needs BOTH a width and an alignment. Without the
              // alignment the inner box stretches to fill the 10pt gutter and
              // the "circle" prints as a stubby arrow-like smear rather than a
              // bullet — which is what it did on every report filed so far.
              pw.Container(
                width: 10,
                padding: const pw.EdgeInsets.only(top: 4),
                alignment: pw.Alignment.topLeft,
                child: pw.Container(
                  width: 3,
                  height: 3,
                  decoration: pw.BoxDecoration(
                    color: pdfMuted,
                    shape: pw.BoxShape.circle,
                  ),
                ),
              ),
              pw.Expanded(
                child: pw.Text(
                  pdfSafe(s),
                  style: pw.TextStyle(fontSize: 10, color: pdfInk, lineSpacing: 2),
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

/// A bordered table. [numeric] right-aligns those column indices; [flex] gives
/// custom column widths (index → flex weight).
pw.Widget pdfTable(
  List<String> headers,
  List<List<String>> rows, {
  Set<int> numeric = const {},
  Map<int, double> flex = const {},
}) {
  final alignments = <int, pw.Alignment>{
    for (var i = 0; i < headers.length; i++)
      i: numeric.contains(i) ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
  };
  final widths = <int, pw.TableColumnWidth>{
    for (final e in flex.entries) e.key: pw.FlexColumnWidth(e.value),
  };

  return pw.TableHelper.fromTextArray(
    headers: [for (final h in headers) pdfSafe(h)],
    data: [
      for (final row in rows) [for (final cell in row) pdfSafe(cell)],
    ],
    border: pw.TableBorder.all(color: pdfLine, width: 0.5),
    headerStyle: pw.TextStyle(
      fontSize: 8.5,
      fontWeight: pw.FontWeight.bold,
      color: pdfInk,
    ),
    headerDecoration: pw.BoxDecoration(color: pdfSubtle),
    cellStyle: pw.TextStyle(fontSize: 9, color: pdfInk),
    cellHeight: 16,
    headerAlignments: alignments,
    cellAlignments: alignments,
    columnWidths: widths.isEmpty ? null : widths,
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
  );
}

/// A two-column "label / value" table — the shape most of a single record's
/// facts take. Right column is given the room, since that's where the prose is.
pw.Widget pdfFactTable(List<({String label, String value})> facts) => pdfTable(
  const ['Field', 'Value'],
  [
    for (final f in facts) [f.label, f.value],
  ],
  flex: const {0: 1.6, 1: 3.4},
);

pw.Widget pdfFooter(pw.Context context) => pw.Container(
  alignment: pw.Alignment.centerRight,
  margin: const pw.EdgeInsets.only(top: 8),
  padding: const pw.EdgeInsets.only(top: 4),
  decoration: pw.BoxDecoration(
    border: pw.Border(top: pw.BorderSide(color: pdfLine, width: 0.5)),
  ),
  child: pw.Text(
    pdfSafe(
      'GovPulse - Aparri, Cagayan   —   '
      'Page ${context.pageNumber} of ${context.pagesCount}',
    ),
    style: pw.TextStyle(fontSize: 8, color: pdfMuted),
  ),
);
