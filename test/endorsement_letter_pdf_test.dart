// The endorsement letter is generated on demand in front of an admin who has
// just endorsed a report — at which point the PIN has already been issued and
// the report already handed over. A build failure there is unrecoverable in the
// moment, so the document is assembled here instead, in CI.
//
// These are not golden tests. What they pin is that the letter BUILDS for the
// awkward inputs a real queue contains (missing address, empty description, a
// reason long enough to push onto a second page), that it is laid out on long
// bond paper, and that the PIN DOES reach the page (see the inverted test
// below and the header of endorsement_letter_pdf.dart for why).

import 'dart:io';

import 'package:pdf/pdf.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/admin/providers/admin_reports_provider.dart';
import 'package:govpulse/features/admin/utils/endorsement_letter_pdf.dart';

AdminReport _report({
  String? barangay = 'Macanaya',
  String? address = 'Corner of Rizal St.',
  String remarks = 'Large pothole across both lanes of the national road.',
  int confirmCount = 0,
}) => AdminReport(
  id: '3f2a1b6c-8d4e-4f7a-9b1c-2e5d6a7b8c9d',
  shortId: '3F2A1B6C',
  categoryKey: 'road',
  category: 'Road & Infrastructure',
  barangay: barangay,
  address: address,
  remarks: remarks,
  status: ReportStatus.underReview,
  isAnonymous: false,
  submitterName: 'Maria Santos',
  submitterPhotoUrl: null,
  submitterRole: 'citizen',
  mediaCount: 2,
  createdAt: DateTime(2026, 7, 28, 14, 32),
  confirmCount: confirmCount,
);

const _credentials = EndorsementCredentials(
  token: 'Zm9vYmFyYmF6cXV4LTEyMzQ1Njc4OTBhYmNkZWZnaGk',
  pin: '4821',
  reference: 'END-3F2A1B6C',
  agency: 'DPWH',
);

const _reason =
    'The affected carriageway forms part of the Maharlika Highway, a national '
    'road under DPWH jurisdiction, and is outside the maintenance authority of '
    'this Municipality.';

/// The inflated content of ONE page's stream, zero-indexed.
///
/// Content streams are written in page order, so the Nth inflatable stream is
/// the Nth page — which is what lets a test ask "is this on page one?" rather
/// than "does this appear before that in the whole document", a question that
/// answers wrong whenever a word occurs twice.
String _pdfPageText(List<int> bytes, int page) {
  final pages = _pdfStreams(bytes);
  return page < pages.length ? pages[page] : '';
}

/// Every page's text, concatenated — for assertions that do not care which
/// page a string landed on.
String _pdfText(List<int> bytes) => _pdfStreams(bytes).join();

/// Every FlateDecode stream in [bytes], inflated, in page order. Streams that
/// are not zlib (embedded images) fail to inflate and are skipped.
List<String> _pdfStreams(List<int> bytes) {
  final raw = String.fromCharCodes(bytes);
  final out = <String>[];
  var i = 0;
  while (true) {
    final s = raw.indexOf('stream', i);
    if (s < 0) break;
    final e = raw.indexOf('endstream', s);
    if (e < 0) break;
    var start = s + 'stream'.length;
    while (start < e &&
        (raw.codeUnitAt(start) == 13 || raw.codeUnitAt(start) == 10)) {
      start++;
    }
    try {
      out.add(
        String.fromCharCodes(ZLibDecoder().convert(bytes.sublist(start, e))),
      );
    } catch (_) {
      // not a flate stream (image data, etc.)
    }
    i = e + 'endstream'.length;
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('builds a real PDF document', () async {
    final bytes = await buildEndorsementLetter(
      report: _report(),
      credentials: _credentials,
      reason: _reason,
      now: DateTime(2026, 8, 1),
    );

    // %PDF- magic. Proves a document was actually serialised rather than an
    // empty buffer returned.
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(2000));
  });

  // Long bond / Folio, not A4. The office files these on 8.5x13 stock, and a
  // letter laid out for A4 prints short on it. Asserted on the constant rather
  // than by parsing /MediaBox: the format is the decision, and the pdf package
  // is what turns it into page geometry.
  test('the letter is long bond paper, not A4', () {
    expect(kFolioPageFormat.width, closeTo(8.5 * 72, 0.01));
    expect(kFolioPageFormat.height, closeTo(13.0 * 72, 0.01));
    expect(kFolioPageFormat.height, greaterThan(PdfPageFormat.a4.height));
  });

  // ── INVERTED 2026-08-29, deliberately ──────────────────────────────────
  // This test used to assert the PIN never reached the paper, because the QR
  // and the PIN were two factors on two channels. That second channel does not
  // exist in this deployment (no SMS budget), and a credential nobody can
  // deliver is not a credential — it is a letter the agency cannot act on. The
  // PIN is now printed in a detachable box; see the header of
  // endorsement_letter_pdf.dart for what replaces the lost secrecy.
  //
  // The assertion is flipped rather than deleted so the property stays PINNED
  // in both directions: if someone later removes the PIN box without removing
  // this test, it fails loudly instead of silently changing the document.
  test('the PIN is printed on the letter', () async {
    final bytes = await buildEndorsementLetter(
      report: _report(),
      credentials: _credentials,
      reason: _reason,
      now: DateTime(2026, 8, 1),
    );

    // ⚠ Page content is zlib-compressed, so scanning the RAW bytes for a
    // printed word finds nothing and any "PIN is absent" assertion built on
    // that passes vacuously. Inflate first, then search. The control below
    // uses a word that appears ONLY in page text — not in the document title
    // metadata, which is stored uncompressed and would make a raw-bytes search
    // look like it works when it does not.
    //
    // The control word is taken from the BODY PROSE, not a heading: headings
    // carry letterSpacing, which the pdf package emits as separate text-showing
    // operators, so a spaced heading never appears as one contiguous string.
    // Body prose renders through the same path a leaked PIN would, which is
    // exactly what this control needs to exercise.
    final text = _pdfText(bytes);
    expect(text.contains('Maharlika'), isTrue,
        reason: 'control: printed page text must be searchable');

    // The PIN box sets the digits with letterSpacing, which the pdf package
    // emits as one text-showing operator per glyph — so the plaintext is NOT
    // contiguous in the inflated stream and a naive contains() would fail even
    // though the digits are on the page. Assert each digit in order instead,
    // which is what "the PIN is legible on the paper" actually means.
    var cursor = 0;
    for (final digit in _credentials.pin.split('')) {
      final at = text.indexOf(digit, cursor);
      expect(at, isNonNegative,
          reason: 'PIN digit "$digit" must be printed on the letter');
      cursor = at + 1;
    }

    expect(text.contains('CONFIRMATION'), isTrue,
        reason: 'the PIN must be labelled, not a bare number on the page');
  });

  // Caught by LOOKING at the rendered letter, not by any assertion above: the
  // terms still told the agency their PIN was "issued separately", a few inches
  // above the box printing it. An official document contradicting itself is a
  // defect, so the corrected wording is pinned here.
  test('the terms do not claim the PIN travels separately', () async {
    final bytes = await buildEndorsementLetter(
      report: _report(),
      credentials: _credentials,
      reason: _reason,
      now: DateTime(2026, 8, 1),
    );
    final text = _pdfText(bytes);

    expect(text.contains('issued'), isFalse,
        reason: 'the "issued separately to that office" term must be gone');
    // Single word, not a phrase: the terms are JUSTIFIED, and the pdf package
    // emits justified lines as one text-showing operator per word so it can
    // stretch the gaps. No multi-word string survives contiguously in the
    // stream — which is exactly how the first draft of this test failed.
    expect(text.contains('accompanies'), isTrue,
        reason: 'the terms must describe where the PIN actually is');
  });

  // Also a looking-not-asserting find: the signature block used to page-break
  // away from the letter, leaving the Mayor's name alone on an otherwise blank
  // sheet. The closing must stay with the prose it closes.
  test('the signature stays on the page the letter ends on', () async {
    final bytes = await buildEndorsementLetter(
      report: _report(),
      credentials: _credentials,
      reason: _reason,
      now: DateTime(2026, 8, 1),
    );

    // Per-PAGE, not by offset into the concatenated text. An offset comparison
    // is what the first draft of this test did, and it failed for a reason
    // worth recording: "confirm" also occurs in Term 2 ("the confirmation
    // PIN"), on page one, so the first match was never the scan panel. Probing
    // page one directly asks the question the defect was actually about —
    // which page is the signature on.
    final page1 = _pdfPageText(bytes, 0);

    expect(page1.contains('Mayor'), isTrue,
        reason: 'the signature must close the letter on page one, not orphan '
            'onto a sheet of its own');
    expect(page1.contains('Maharlika'), isTrue,
        reason: 'control: page one is the page carrying the letter body');
  });

  test('survives the awkward reports a real queue contains', () async {
    final cases = <String, AdminReport>{
      'no address at all': _report(barangay: null, address: null),
      'barangay only': _report(address: null),
      'no written description': _report(remarks: ''),
      'corroborated by many': _report(confirmCount: 12),
    };

    for (final entry in cases.entries) {
      final bytes = await buildEndorsementLetter(
        report: entry.value,
        credentials: _credentials,
        reason: _reason,
        now: DateTime(2026, 8, 1),
      );
      expect(bytes.length, greaterThan(2000), reason: entry.key);
    }
  });

  test('a reason long enough to need a second page still builds', () async {
    final bytes = await buildEndorsementLetter(
      report: _report(),
      credentials: _credentials,
      // The dialog caps the reason at kEndorseReasonMaxLength; this is that cap
      // spent entirely on unbroken prose, the worst case for pagination.
      reason: List.filled(60, 'jurisdictional considerations apply').join(' '),
      now: DateTime(2026, 8, 1),
    );
    expect(bytes.length, greaterThan(2000));
  });

  // Times has no glyph for an em dash or a smart quote, and pdf renders a
  // missing glyph as a blank box. Citizens' descriptions are full of both.
  test('non-Latin-1 punctuation in citizen text does not break the build',
      () async {
    final bytes = await buildEndorsementLetter(
      report: _report(
        remarks: 'The road — which floods every storm — is "impassable"… '
            'residents say it’s been years.',
      ),
      credentials: _credentials,
      reason: 'Outside LGU scope — national road.',
      now: DateTime(2026, 8, 1),
    );
    expect(bytes.length, greaterThan(2000));
  });
}
