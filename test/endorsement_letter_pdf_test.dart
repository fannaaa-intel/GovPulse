// The endorsement letter is generated on demand in front of an admin who has
// just endorsed a report — at which point the PIN has already been issued and
// the report already handed over. A build failure there is unrecoverable in the
// moment, so the document is assembled here instead, in CI.
//
// These are not golden tests. What they pin is that the letter BUILDS for the
// awkward inputs a real queue contains (missing address, empty description, a
// reason long enough to push onto a second page) and that the PIN never reaches
// the page.

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

  // THE security property of this document. The QR travels on the paper; the
  // PIN must not, or the two factors collapse into one and a photograph of the
  // letter is enough to close someone else's report.
  test('the PIN never appears in the letter', () async {
    final bytes = await buildEndorsementLetter(
      report: _report(),
      credentials: _credentials,
      reason: _reason,
      now: DateTime(2026, 8, 1),
    );

    // Uncompressed text is searchable in the raw bytes; the reference IS
    // expected to be there, which is what proves this search can find a short
    // string at all rather than passing vacuously.
    final raw = String.fromCharCodes(bytes);
    expect(raw.contains('END-3F2A1B6C'), isTrue,
        reason: 'control: the reference should be findable');
    expect(raw.contains(_credentials.pin), isFalse,
        reason: 'the PIN must never be printed on the letter');
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
