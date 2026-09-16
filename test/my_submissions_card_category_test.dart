// What the My Submissions CARDS call a submission — and what they must not.
//
// ── The bug, twice ─────────────────────────────────────────────────────────
// Tapping "Others" asks the citizen to specify the category, and the field's
// hint invited a sentence. So `category_other` holds prose — "The bridge on the
// national highway has collapsed" — and rendering it as the label made it the
// submission's TITLE. 788e731 fixed that for reports, in
// my_report/report_card.dart's ReportItem.
//
// It did NOT reach this screen. my_submissions_screen.dart declares its own
// private `_Report` and `_Suggestion` models with their own label logic, so:
//   * the report cards here still showed the sentence after 788e731 shipped;
//   * suggestions had the identical bug, never fixed, and now have an
//     `ai_category` of their own (20260917000000) to fix it with.
//
// Both are resolved on the model now, via `displayLabel`, so the mobile card,
// the web card and the detail header cannot disagree.
//
// ── Why this test drives the whole screen ──────────────────────────────────
// `_Report`/`_Suggestion`/`displayLabel` are all private to that file, so there
// is nothing to unit-test from outside. What IS observable is the text the card
// renders, which is the thing that was wrong. So this pumps the real screen
// against a faked PostgREST and asserts on what a citizen would read.
//
// The fakes answer every table from one router, because the screen fetches
// reports, suggestions and feedback in parallel on first build.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:govpulse/features/home/settings/my-submission/my_submissions_screen.dart';

import '_responsive_matrix.dart';

const _kUserId = '11111111-2222-3333-4444-555555555555';

/// The sentence a citizen typed into "specify the category". This must never
/// appear as a card's title.
const _kProse = 'The bridge on the national highway has collapsed';
const _kSuggestionProse =
    'Please install a streetlight along the Rizal Street corner';

/// A signed-in session: the screen filters on `user_id`, and an
/// unauthenticated client would make every fetch a no-op — which would pass
/// these tests by rendering nothing at all.
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
  Future<void> persistSession(String persistSessionString) async {}
  @override
  Future<void> removePersistedSession() async {}
}

/// Answers the three table reads the screen makes on build. Rows are handed in
/// per-test so each case controls exactly what the cards see.
class _FakeClient extends http.BaseClient {
  final List<Map<String, dynamic>> reports;
  final List<Map<String, dynamic>> suggestions;

  /// Set when a select names `ai_category`, so a test can prove the column is
  /// actually being requested rather than silently dropped.
  final List<String> seenSelects = [];

  _FakeClient({this.reports = const [], this.suggestions = const []});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final url = request.url.toString();
    final select = request.url.queryParameters['select'] ?? '';
    List<Map<String, dynamic>> body = const [];

    if (url.contains('/rest/v1/reports')) {
      seenSelects.add('reports:$select');
      body = reports;
    } else if (url.contains('/rest/v1/suggestions')) {
      seenSelects.add('suggestions:$select');
      body = suggestions;
    }
    // Everything else (feedbacks, media, realtime) answers empty.

    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
      request: request,
    );
  }
}

Map<String, dynamic> _reportRow({
  required String category,
  String? categoryOther,
  String? aiCategory,
}) => {
  'id': '00000000-0000-4000-8000-00000000000a',
  'user_id': _kUserId,
  'category': category,
  'category_other': categoryOther,
  'ai_category': aiCategory,
  'barangay': 'Macanaya',
  'remarks': 'remarks text',
  'status': 'pending',
  'created_at': '2026-09-17T01:00:00Z',
  'is_anonymous': false,
  'report_media': <dynamic>[],
};

Map<String, dynamic> _suggestionRow({
  required String category,
  String? categoryOther,
  String? aiCategory,
}) => {
  'id': '00000000-0000-4000-8000-00000000000b',
  'user_id': _kUserId,
  'category': category,
  'category_other': categoryOther,
  'ai_category': aiCategory,
  'details': 'details text',
  'barangay': 'Macanaya',
  'address': null,
  'latitude': null,
  'longitude': null,
  'created_at': '2026-09-17T01:00:00Z',
  'is_anonymous': false,
  'admin_response': null,
  'reviewed_at': null,
};

Future<_FakeClient> _pump(
  WidgetTester tester, {
  List<Map<String, dynamic>> reports = const [],
  List<Map<String, dynamic>> suggestions = const [],
  Device device = kModernPhone,
  /// 0 Reports · 1 Suggestions. The screen only BUILDS the active tab's cards,
  /// so a suggestion assertion against the default tab finds nothing and looks
  /// like a label bug.
  int tab = 0,
}) async {
  final client = _FakeClient(reports: reports, suggestions: suggestions);
  SharedPreferences.setMockInitialValues({});
  await Supabase.initialize(
    url: 'https://vxvflhjbafqwehuxnmeq.supabase.co',
    anonKey: 'sb_publishable_ZBDaQPQdFyC5kOHGbce9Ig_zdtIi6Mo',
    httpClient: client,
    authOptions: const FlutterAuthClientOptions(
      localStorage: _FakeSessionStorage(),
      autoRefreshToken: false,
    ),
  );
  addTearDown(() async {
    await Supabase.instance.dispose();
  });

  await pumpAt(tester, device, () {
    return MaterialApp(
      home: MySubmissionsScreen(username: 'Juan', initialTab: tab),
    );
  });
  // The screen fetches on build; let the futures land and the list rebuild.
  await tester.pump(const Duration(milliseconds: 800));
  return client;
}

void main() {
  group('report cards — 788e731 never reached this screen', () {
    testWidgets('an "Others" report shows the AI category, not the sentence',
        (tester) async {
      await _pump(tester, reports: [
        _reportRow(
          category: 'others',
          categoryOther: _kProse,
          aiCategory: 'road',
        ),
      ]);

      // THE assertion. This is the bug as it was reported: a paragraph where a
      // category belongs.
      expect(find.text(_kProse), findsNothing,
          reason: 'the citizen\'s sentence must never be a card title');
      expect(find.text('Road & Infrastructure'), findsWidgets);
    });

    testWidgets('without an AI category it still falls back to the sentence',
        (tester) async {
      // Not ideal, but it is the citizen's own words and the only thing we
      // have. The point is that this is the FALLBACK, not the default.
      await _pump(tester, reports: [
        _reportRow(category: 'others', categoryOther: _kProse),
      ]);
      expect(find.text(_kProse), findsWidgets);
    });

    testWidgets('the AI never overrides a category the citizen picked',
        (tester) async {
      await _pump(tester, reports: [
        _reportRow(category: 'waste', aiCategory: 'road'),
      ]);
      expect(find.textContaining('Waste'), findsWidgets);
      expect(find.text('Road & Infrastructure'), findsNothing);
    });

    testWidgets('an invented AI key cannot reach the title', (tester) async {
      // A model that answers outside the closed vocabulary must be ignored
      // rather than printed raw.
      await _pump(tester, reports: [
        _reportRow(
          category: 'others',
          categoryOther: _kProse,
          aiCategory: 'bridge_collapse',
        ),
      ]);
      expect(find.text('bridge_collapse'), findsNothing);
      // Falls back to the citizen's words, not to an unknown key.
      expect(find.text(_kProse), findsWidgets);
    });
  });

  group('suggestion cards — the same bug, never fixed until now', () {
    testWidgets('an "Others" suggestion shows the AI category', (tester) async {
      await _pump(tester, tab: 1, suggestions: [
        _suggestionRow(
          category: 'others',
          categoryOther: _kSuggestionProse,
          aiCategory: 'infrastructure',
        ),
      ]);
      expect(find.text(_kSuggestionProse), findsNothing,
          reason: 'the citizen\'s sentence must never be a card title');
      expect(find.textContaining('Infrastructure'), findsWidgets);
    });

    testWidgets("the AI agreeing it is 'others' changes nothing",
        (tester) async {
      // 'others' from the model says nothing the citizen did not already say,
      // so it must not displace their words.
      await _pump(tester, tab: 1, suggestions: [
        _suggestionRow(
          category: 'others',
          categoryOther: _kSuggestionProse,
          aiCategory: 'others',
        ),
      ]);
      expect(find.text(_kSuggestionProse), findsWidgets);
    });

    testWidgets('the suggestions select asks for ai_category', (tester) async {
      // Reports get the column free via select('*'); suggestions name their
      // columns explicitly, so a missing name here is a silent regression —
      // every card would quietly fall back to the sentence forever.
      final client = await _pump(tester, tab: 1, suggestions: [
        _suggestionRow(category: 'others', categoryOther: _kSuggestionProse),
      ]);
      expect(
        client.seenSelects.any(
          (s) => s.startsWith('suggestions:') && s.contains('ai_category'),
        ),
        isTrue,
        reason: 'select was: ${client.seenSelects}',
      );
    });
  });
}
