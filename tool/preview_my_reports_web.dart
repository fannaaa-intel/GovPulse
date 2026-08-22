// Dev-only harness for the CITIZEN WEB "My Reports" page.
//
// Not part of the app: nothing under lib/ imports it, and it is never a build
// target for a shipped bundle.
//
//   flutter build web --release -t tool/preview_my_reports_web.dart
//   python -m http.server 57811 --directory build/web
//
// ── Why this exists ────────────────────────────────────────────────────────
// The page's whole layout sits behind `kIsWeb`, so `flutter test` (the VM,
// where kIsWeb is a compile-time false) can never reach it, and the real app
// cannot be loaded either — every route is login-gated and a fresh browser
// profile has no Supabase session, so the page renders its error state instead
// of itself.
//
// So the session and the database are both faked, at the two seams
// `Supabase.initialize` already exposes:
//
//   * `authOptions.localStorage` — a [LocalStorage] handing back a hand-written
//     persisted session. `Session.expiresAt` is read by parsing the access
//     token as a JWT, and a token that is NOT a JWT parses to null, which
//     `isExpired` reads as "never expires" — so a nonsense token is exactly
//     what keeps the fake session from trying to refresh itself.
//   * `httpClient` — a [http.BaseClient] answering PostgREST by table name.
//     Every `maybeSingle()` on this page is a plain GET that the client
//     post-processes, so an empty array is a valid "no row" for all of them.
//
// Nothing here touches the network. The realtime socket still tries (the screen
// subscribes on mount) and fails, which is harmless and not what is being
// looked at.
//
// ── What to look at ────────────────────────────────────────────────────────
// The panes are the widths the layout switches on. `_kWebCompactPane` is 620,
// measured against the CONTENT COLUMN, so 620 and below must show the mobile
// arrangement (four stat cards on one row sized off the pane, the date chips on
// a single scrolling row inside one Report History card) and 768 and up must
// show the desktop one, unchanged.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:govpulse/core/theme/citizen_ui.dart';
import 'package:govpulse/features/home/my_report/my_reports_screen.dart';

const _kUserId = '11111111-2222-3333-4444-555555555555';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://vxvflhjbafqwehuxnmeq.supabase.co',
    anonKey: 'sb_publishable_ZBDaQPQdFyC5kOHGbce9Ig_zdtIi6Mo',
    httpClient: _FakeRest(),
    authOptions: const FlutterAuthClientOptions(
      localStorage: _FakeSessionStorage(),
      autoRefreshToken: false,
      detectSessionInUri: false,
    ),
  );
  runApp(const ProviderScope(child: _PreviewApp()));
}

// ── Fake session ────────────────────────────────────────────────────────────

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
  Future<void> removePersistedSession() async {}

  @override
  Future<void> persistSession(String persistSessionString) async {}
}

// ── Fake PostgREST ──────────────────────────────────────────────────────────

class _FakeRest extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    final body = path.contains('/rest/v1/reports')
        ? jsonEncode(_reports)
        // Every other read on this page is a `maybeSingle()`, which PostgREST
        // answers with an array and the client narrows itself.
        : '[]';
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      headers: const {'content-type': 'application/json; charset=utf-8'},
      request: request,
    );
  }
}

Map<String, dynamic> _row({
  required String id,
  required String category,
  required String status,
  required String createdAt,
  required String remarks,
  int media = 0,
  String? rejectionNote,
}) => {
  'id': id,
  'category': category,
  'status': status,
  'created_at': createdAt,
  'barangay': 'Poblacion',
  'address': '123 Rizal Street, Poblacion',
  'remarks': remarks,
  'is_anonymous': false,
  'rejection_note': rejectionNote,
  'report_media': [
    for (var i = 0; i < media; i++) {'id': 'm$i'},
  ],
};

String _daysAgo(int d) =>
    DateTime.now().subtract(Duration(days: d)).toUtc().toIso8601String();

// Six reports, spread across the four stat buckets so none of them reads zero,
// and dated across the chip ranges so Today / This Week / This Month each
// filter to something different.
final _reports = <Map<String, dynamic>>[
  _row(
    id: '3d1af001-0000-4000-8000-000000000001',
    category: 'road',
    status: 'pending',
    createdAt: _daysAgo(0),
    remarks: 'Large pothole on the northbound lane near the public market.',
    media: 2,
  ),
  _row(
    id: '3d1af002-0000-4000-8000-000000000002',
    category: 'waste',
    status: 'under_review',
    createdAt: _daysAgo(2),
    remarks: 'Uncollected garbage piling up behind the barangay hall.',
    media: 1,
  ),
  _row(
    id: '3d1af003-0000-4000-8000-000000000003',
    category: 'streetlight',
    status: 'in_progress',
    createdAt: _daysAgo(9),
    remarks: 'Three streetlights out along the whole block.',
  ),
  _row(
    id: '3d1af004-0000-4000-8000-000000000004',
    category: 'drainage',
    status: 'resolved',
    createdAt: _daysAgo(20),
    remarks: 'Clogged canal flooding the street after every rain.',
    media: 3,
  ),
  _row(
    id: '3d1af005-0000-4000-8000-000000000005',
    category: 'environment',
    status: 'rejected',
    createdAt: _daysAgo(45),
    remarks: 'Open burning of household waste in the vacant lot.',
    rejectionNote: 'Outside the LGU scope — referred to the DENR hotline.',
  ),
  _row(
    id: '3d1af006-0000-4000-8000-000000000006',
    category: 'others',
    status: 'resolved',
    createdAt: _daysAgo(70),
    remarks: 'Stray dogs gathering around the elementary school gate.',
  ),
];

// ── The pane matrix ─────────────────────────────────────────────────────────

class _Pane {
  final String name;
  final double width;
  const _Pane(this.name, this.width);
}

const _panes = <_Pane>[
  _Pane('320 · smallest phone', 320),
  _Pane('390 · phone', 390),
  _Pane('412 · the screenshot', 412),
  _Pane('620 · compact edge', 620),
  _Pane('768 · tablet portrait', 768),
  _Pane('1160 · desktop band', 1160),
];

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'My Reports · web panes',
      home: Scaffold(
        backgroundColor: const Color(0xFF111827),
        body: SafeArea(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [for (final p in _panes) _pane(p)],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pane(_Pane p) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: SizedBox(
        width: p.width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                p.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            // Mirrors the shell: the centre column overrides MediaQuery so the
            // pane reports ITS width, not the viewport's.
            Expanded(
              child: Builder(
                builder: (context) {
                  final mq = MediaQuery.of(context);
                  return MediaQuery(
                    data: mq.copyWith(
                      size: Size(p.width, mq.size.height),
                      padding: EdgeInsets.zero,
                      viewPadding: EdgeInsets.zero,
                    ),
                    child: const Material(
                      color: CitizenUi.pageBg,
                      child: MyReportsBody(),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
