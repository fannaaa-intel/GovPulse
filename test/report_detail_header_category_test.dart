import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:govpulse/features/home/my_report/report_card.dart';
import 'package:govpulse/features/home/my_report/report_detail_screen.dart';

import '_responsive_matrix.dart';

// What the report detail HEADER actually renders.
//
// ── Why this exists alongside report_category_label_test ────────────────────
// That one pins the model: ReportItem.category resolves to the AI's answer for
// an "Others" report. This one pins the SCREEN — that the string reaching the
// big white title under "Report details" is that category, and not the sentence
// the citizen typed.
//
// Worth separating because the bug arrived as a picture: a header reading "The
// bridge on the national highway has collapsed" where a category belongs. A
// model test alone would not catch a header wired to `categoryOther`, and a
// correctly-wired header over a model that resolves wrong looks identical on
// screen.
//
// Shared by web and mobile — the citizen shell and the legacy router build this
// same screen from this same ReportItem — so these cover both platforms.

const _kUserId = '11111111-2222-3333-4444-555555555555';

/// The screen reads its own live data (progress updates, media), so Supabase
/// has to exist or the first build throws. Faked at the two seams
/// `Supabase.initialize` exposes, the same way my_reports_filter_stability_test
/// does it — the header under test is built from the ReportItem passed in, not
/// from anything fetched, so empty responses are exactly right.
class _FakeSessionStorage extends LocalStorage {
  const _FakeSessionStorage();

  static final String _session = jsonEncode({
    'access_token': 'test-not-a-jwt',
    'token_type': 'bearer',
    'refresh_token': 'test-refresh',
    'user': {
      'id': _kUserId,
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': 'test@govpulse.local',
      'app_metadata': <String, dynamic>{},
      'user_metadata': <String, dynamic>{},
      'created_at': '2026-01-01T00:00:00Z',
    },
  });

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async => true;

  @override
  Future<String?> accessToken() async => _session;

  @override
  Future<void> removePersistedSession() async {}

  @override
  Future<void> persistSession(String persistSessionString) async {}
}

class _FakeRest extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream.value(utf8.encode('[]')),
      200,
      headers: const {'content-type': 'application/json; charset=utf-8'},
      request: request,
    );
  }
}

ReportItem buildReport({
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

Widget host(ReportItem report) => MaterialApp(
  home: ReportDetailScreen(report: report, username: 'juan_dela_cruz'),
);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://vxvflhjbafqwehuxnmeq.supabase.co',
      anonKey: 'sb_publishable_ZBDaQPQdFyC5kOHGbce9Ig_zdtIi6Mo',
      httpClient: _FakeRest(),
      authOptions: const FlutterAuthClientOptions(
        localStorage: _FakeSessionStorage(),
        autoRefreshToken: false,
        detectSessionInUri: false,
      ),
      debug: false,
    );
  });

  group('the header shows a category, not the citizen sentence', () {
    testWidgets('an AI-classified "Others" report reads as its real category', (
      tester,
    ) async {
      final report = buildReport(
        category: 'others',
        categoryOther: 'The bridge on the national highway has collapsed',
        aiCategory: 'road',
      );

      await pumpAt(tester, kModernPhone, () => host(report));

      // The header renders the category at w * .054 in white on the banner.
      // Matching on that style rather than on the string alone, because the
      // description legitimately appears further down in Details — an earlier
      // version of this test asserted the sentence was absent from the whole
      // page and failed on the body copy, which is the one place it belongs.
      final headerTitle = find.byWidgetPredicate(
        (w) =>
            w is Text &&
            w.style?.color == Colors.white &&
            (w.style?.fontWeight == FontWeight.w800) &&
            (w.data?.isNotEmpty ?? false),
        description: 'the white bold header title',
      );

      final titles = tester
          .widgetList<Text>(headerTitle)
          .map((t) => t.data)
          .toList();

      expect(
        titles,
        contains('Road & Infrastructure'),
        reason: 'the header must name the category the AI recognised',
      );
      expect(
        titles,
        isNot(contains('The bridge on the national highway has collapsed')),
        reason:
            'the exact bug, as reported: the typed description was the page '
            'title. It belongs in Details, never in the header.',
      );
    });

    testWidgets('a normally-picked category is unchanged', (tester) async {
      await pumpAt(
        tester,
        kModernPhone,
        () => host(buildReport(category: 'waste', aiCategory: 'road')),
      );

      // The citizen's own pick always wins; the AI only fills in for Others.
      expect(find.text('Waste & Garbage'), findsWidgets);
      expect(find.text('Road & Infrastructure'), findsNothing);
    });

    testWidgets('an unclassified "Others" still shows what they typed', (
      tester,
    ) async {
      await pumpAt(
        tester,
        kModernPhone,
        () => host(
          buildReport(category: 'others', categoryOther: 'Stray animals'),
        ),
      );

      // With no AI answer there is nothing better to show, and a short name is
      // exactly what the field now asks for.
      expect(find.text('Stray animals'), findsWidgets);
    });
  });

  group('the header holds at every size', () {
    // A category label is longer than the key it replaces — "Environment &
    // Pollution" against "others" — and it sits at w * .054 inside a coloured
    // banner, so it is the string most likely to overflow the header.
    ReportItem longest() => buildReport(
      category: 'others',
      categoryOther: 'x',
      aiCategory: 'environment',
    );

    for (final device in kAllPhones) {
      testWidgets('no overflow at $device', (tester) async {
        final errors = await pumpAt(tester, device, () => host(longest()));
        expect(errors, isEmpty, reason: errors.join('\n'));
      });
    }

    testWidgets('no overflow on a tablet', (tester) async {
      final errors = await pumpAt(tester, kTablet, () => host(longest()));
      expect(errors, isEmpty, reason: errors.join('\n'));
    });

    for (final scale in [1.3, 1.6, 2.0]) {
      testWidgets('no overflow at 320px with ${scale}x text', (tester) async {
        final errors = await pumpAt(
          tester,
          kSmallPhone,
          () => host(longest()),
          textScale: scale,
        );
        expect(errors, isEmpty, reason: errors.join('\n'));
      });
    }

    testWidgets('a long typed name does not overflow either', (tester) async {
      // The field caps at 50 characters, so this is the worst case a citizen
      // can actually submit.
      final errors = await pumpAt(
        tester,
        kSmallPhone,
        () => host(buildReport(category: 'others', categoryOther: 'A' * 50)),
      );
      expect(errors, isEmpty, reason: errors.join('\n'));
    });
  });
}
