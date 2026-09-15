import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/home/my_report/report_card.dart';

// What a report is CALLED, once the citizen picked "Others".
//
// ── The bug ─────────────────────────────────────────────────────────────────
// Tapping "Others" asks the citizen to specify the category, and the field's
// hint invited a sentence — "Describe it in a few words…". So people wrote a
// description, it was stored in `category_other`, and My Reports renders that
// as the report's LABEL. The detail header therefore read:
//
//     Report details
//     The bridge on the national highway has collapsed
//
// where a category belongs.
//
// classify-report already answers the question properly: it reads the report
// and writes `ai_category` — "what the report ACTUALLY is" — from the same
// closed vocabulary the picker offers. The admin console reads it. The citizen
// side never did, even though `select('*')` meant the column was in the row.
//
// ── What is pinned ──────────────────────────────────────────────────────────
// Both halves. The AI answer must be used when it is better, AND it must not
// be trusted blindly — a model that returns 'others', an empty string, or an
// invented key must not reach the header.
//
// Shared by web and mobile: the citizen shell and the legacy router build the
// same ReportItem from the same rows, so this covers both platforms.
ReportItem build({
  required String category,
  String? categoryOther,
  String? aiCategory,
}) {
  return ReportItem.fromMap({
    'id': '3f2504e0-4f89-11d3-9a0c-0305e82c3301',
    'category': category,
    'category_other': categoryOther,
    'ai_category': aiCategory,
    'barangay': 'San Antonio',
    'address': null,
    'remarks': 'The bridge on the national highway has collapsed',
    'status': 'pending',
    'created_at': DateTime.utc(2026, 9, 14, 16, 16).toIso8601String(),
    'is_anonymous': false,
  });
}

void main() {
  group('an "Others" report the AI recognised', () {
    test('is labelled by what it IS, not by what the citizen typed', () {
      final r = build(
        category: 'others',
        categoryOther: 'The bridge on the national highway has collapsed',
        aiCategory: 'road',
      );

      expect(r.category, 'Road & Infrastructure');
      expect(
        r.category,
        isNot(contains('bridge')),
        reason:
            'the typed text is a DESCRIPTION; rendering it as the label made '
            'the report detail header read like a paragraph',
      );
    });

    test('keeps the citizen\'s key, so routing is untouched', () {
      final r = build(
        category: 'others',
        categoryOther: 'The bridge has collapsed',
        aiCategory: 'road',
      );

      // report_department() in SQL and StaffDepartments.forReportCategory in
      // Dart both route on the stored category. Relabelling must never quietly
      // re-route a report in the UI while the database says otherwise.
      expect(r.categoryKey, 'others');
      expect(r.categoryOther, 'The bridge has collapsed');
    });
  });

  group('the AI answer is not trusted blindly', () {
    test('"others" from the AI changes nothing', () {
      final r = build(
        category: 'others',
        categoryOther: 'Stray animals',
        aiCategory: 'others',
      );

      // The AI agreeing it is miscellaneous tells us nothing the citizen did
      // not already say, so their own words stay.
      expect(r.category, 'Stray animals');
    });

    test('an invented key is ignored', () {
      final r = build(
        category: 'others',
        categoryOther: 'Stray animals',
        aiCategory: 'bridge_collapse',
      );

      expect(
        r.category,
        'Stray animals',
        reason:
            'a key outside the closed vocabulary must never reach the header',
      );
    });

    test('a null or blank ai_category changes nothing', () {
      expect(
        build(
          category: 'others',
          categoryOther: 'Stray animals',
          aiCategory: null,
        ).category,
        'Stray animals',
      );
      expect(
        build(
          category: 'others',
          categoryOther: 'Stray animals',
          aiCategory: '   ',
        ).category,
        'Stray animals',
      );
    });

    test('"Others" with nothing typed still reads as Others', () {
      expect(
        build(category: 'others', categoryOther: null).category,
        'Others',
      );
    });
  });

  group('a category the citizen picked directly', () {
    test('is never overridden by the AI', () {
      // The citizen tapped Waste; the model thinks it is road work. Their
      // answer stands — this fix only fills in for the one case where the
      // stored value is prose.
      final r = build(category: 'waste', aiCategory: 'road');

      expect(r.category, 'Waste & Garbage');
      expect(r.categoryKey, 'waste');
    });

    test('every picker key still maps to its own label', () {
      const expected = {
        'road': 'Road & Infrastructure',
        'waste': 'Waste & Garbage',
        'drainage': 'Drainage & Flooding',
        'streetlight': 'Streetlight Outage',
        'environment': 'Environment & Pollution',
      };
      expected.forEach((key, label) {
        expect(build(category: key).category, label, reason: 'for key $key');
      });
    });
  });
}
