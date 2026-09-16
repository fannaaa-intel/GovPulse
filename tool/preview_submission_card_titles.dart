// Preview target: what the My Submissions cards CALL a submission.
//
//   flutter build web --release -t tool/preview_submission_card_titles.dart
//
// The bug arrived as a picture — a detail header reading "The bridge on the
// national highway has collapsed" where a category belongs — so the fix is
// verified as a picture too. 788e731 fixed that for ReportItem; this screen has
// its OWN private _Report/_Suggestion models and kept the bug on its cards,
// and suggestions had it in both places until 20260917000000 gave them an
// `ai_category` to fix it with.
//
// Frames: the reports tab and the suggestions tab, each at desktop and phone
// width, every card being an "Others" submission whose `category_other` holds
// a sentence. What to look for:
//   • NO card title is a sentence — each reads as a category
//   • the card with no ai_category still shows the citizen's words (the
//     fallback, deliberately — it is all we have for that row)
//   • an invented AI key ("bridge_collapse") never reaches a title
//   • titles stay on one line and ellipsize; nothing overflows at 360px
//
// The screen fetches its own rows, so this stubs PostgREST the same way
// test/my_submissions_card_category_test.dart does.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:govpulse/features/home/settings/my-submission/my_submissions_screen.dart';

const _kUserId = '11111111-2222-3333-4444-555555555555';

class _FakeSessionStorage extends LocalStorage {
  const _FakeSessionStorage();

  static final String _session = jsonEncode({
    'access_token': 'preview-not-a-jwt',
    'token_type': 'bearer',
    'refresh_token': 'preview-refresh',
    'user': {
      'id': _kUserId,
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': 'preview@govpulse.local',
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
  Future<void> persistSession(String s) async {}
  @override
  Future<void> removePersistedSession() async {}
}

String _id(int n) =>
    '00000000-0000-4000-8000-0000000000${n.toRadixString(16).padLeft(2, '0')}';

/// Every row is an "Others" submission whose category_other is prose — the
/// exact shape that produced the bug — differing only in what the AI said.
final _reports = <Map<String, dynamic>>[
  {
    'id': _id(1),
    'user_id': _kUserId,
    'category': 'others',
    'category_other': 'The bridge on the national highway has collapsed',
    'ai_category': 'road',
    'barangay': 'Macanaya',
    'remarks': 'The bridge on the national highway has collapsed.',
    'status': 'pending',
    'created_at': '2026-09-17T01:00:00Z',
    'is_anonymous': false,
    'report_media': <dynamic>[],
  },
  {
    // No AI yet → falls back to the citizen's words. Deliberate.
    'id': _id(2),
    'user_id': _kUserId,
    'category': 'others',
    'category_other': 'Stray dogs near the school gate every morning',
    'ai_category': null,
    'barangay': 'Punta',
    'remarks': 'Stray dogs near the school gate.',
    'status': 'under_review',
    'created_at': '2026-09-16T01:00:00Z',
    'is_anonymous': false,
    'report_media': <dynamic>[],
  },
  {
    // Invented key → must be ignored, never printed.
    'id': _id(3),
    'user_id': _kUserId,
    'category': 'others',
    'category_other': 'Deep hole swallowing half the lane after the rain',
    'ai_category': 'bridge_collapse',
    'barangay': 'Maura',
    'remarks': 'Deep hole in the road.',
    'status': 'pending',
    'created_at': '2026-09-15T01:00:00Z',
    'is_anonymous': false,
    'report_media': <dynamic>[],
  },
];

final _suggestions = <Map<String, dynamic>>[
  {
    'id': _id(11),
    'user_id': _kUserId,
    'category': 'others',
    'category_other':
        'Please install a streetlight along the Rizal Street corner',
    'ai_category': 'infrastructure',
    'details': 'It is very dark near the covered court at night.',
    'barangay': 'Macanaya',
    'address': 'Rizal St.',
    'latitude': null,
    'longitude': null,
    'created_at': '2026-09-17T02:00:00Z',
    'is_anonymous': false,
    'admin_response': null,
    'reviewed_at': null,
  },
  {
    // AI agrees it is 'others' → says nothing new, so the citizen's words stay.
    'id': _id(12),
    'user_id': _kUserId,
    'category': 'others',
    'category_other': 'Maybe a suggestion box in every barangay hall',
    'ai_category': 'others',
    'details': 'So residents can drop ideas anytime.',
    'barangay': 'Punta',
    'address': null,
    'latitude': null,
    'longitude': null,
    'created_at': '2026-09-16T02:00:00Z',
    'is_anonymous': false,
    'admin_response': null,
    'reviewed_at': null,
  },
  {
    'id': _id(13),
    'user_id': _kUserId,
    'category': 'others',
    'category_other':
        'Ang pila sa business permit ay sobrang haba tuwing umaga',
    'ai_category': 'public_service',
    'details': 'Baka pwedeng dagdagan ang counter.',
    'barangay': 'Maura',
    'address': null,
    'latitude': null,
    'longitude': null,
    'created_at': '2026-09-15T02:00:00Z',
    'is_anonymous': false,
    'admin_response': null,
    'reviewed_at': null,
  },
];

class _FakeRest extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final url = request.url.toString();
    List<Map<String, dynamic>> body = const [];
    if (url.contains('/rest/v1/reports')) {
      body = _reports;
    } else if (url.contains('/rest/v1/suggestions')) {
      body = _suggestions;
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      200,
      headers: const {'content-type': 'application/json; charset=utf-8'},
      request: request,
    );
  }
}

Future<void> main() async {
  await Supabase.initialize(
    url: 'https://vxvflhjbafqwehuxnmeq.supabase.co',
    anonKey: 'sb_publishable_ZBDaQPQdFyC5kOHGbce9Ig_zdtIi6Mo',
    httpClient: _FakeRest(),
    authOptions: const FlutterAuthClientOptions(
      localStorage: _FakeSessionStorage(),
      autoRefreshToken: false,
    ),
  );
  final w = double.tryParse(Uri.base.queryParameters['w'] ?? '');
  final t = int.tryParse(Uri.base.queryParameters['tab'] ?? '');
  runApp(_App(single: w, singleTab: t));
}

class _App extends StatelessWidget {
  final double? single;
  final int? singleTab;
  const _App({this.single, this.singleTab});

  @override
  Widget build(BuildContext context) {
    final frames = <({String label, double width, int tab})>[
      if (single != null)
        (label: 'w=$single', width: single!, tab: singleTab ?? 0)
      else ...[
        (label: 'Reports · desktop', width: 1100, tab: 0),
        (label: 'Reports · phone', width: 390, tab: 0),
        (label: 'Suggestions · desktop', width: 1100, tab: 1),
        (label: 'Suggestions · phone', width: 360, tab: 1),
      ],
    ];
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF2B2F3A),
        body: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final f in frames) ...[
                _Frame(label: f.label, width: f.width, tab: f.tab),
                const SizedBox(width: 24),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Frame extends StatelessWidget {
  final String label;
  final double width;
  final int tab;
  const _Frame({required this.label, required this.width, required this.tab});

  @override
  Widget build(BuildContext context) {
    const height = 1000.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: width,
          child: Text(
            '${width.toInt()} — $label',
            style: const TextStyle(
                color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: width,
          height: height,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(6)),
          // The screen picks its mobile/web layout off the viewport, so each
          // frame declares its own rather than inheriting the browser's.
          child: MediaQuery(
            data: MediaQueryData(size: Size(width, height)),
            child: Navigator(
              onGenerateRoute: (_) => MaterialPageRoute(
                builder: (_) =>
                    MySubmissionsScreen(username: 'Juan', initialTab: tab),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
