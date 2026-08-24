// Dev-only harness for the CITIZEN RECORD BAND — the one content measure the
// list pages and the detail page are supposed to share.
//
//   flutter build web --release -t tool/preview_record_band.dart
//
// ── What it is for ─────────────────────────────────────────────────────────
// My Reports, My Submissions and the report detail are three views of the same
// records, and they used to lay out at three different widths (1112, 816 and
// 722 of content). Opening a card visibly shrank the page. They now all resolve
// to kAccountMaxWidth less two kAccountPageGutters = 816, and the only way to
// see that is to put them side by side IN THE SAME PANE and compare the edges —
// which is what these frames do. The white strip drawn behind each frame is
// exactly 816 wide and centred, so a page that lands on the shared measure
// covers it exactly.
//
// The session and the database are faked at the two seams Supabase.initialize
// exposes — see tool/preview_my_reports_web.dart, which this borrows from.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:govpulse/core/widgets/Home/Account/account_web_kit.dart';
import 'package:govpulse/features/home/my_report/my_reports_screen.dart';
import 'package:govpulse/features/home/my_report/report_detail_screen.dart';

const _kUserId = '11111111-2222-3333-4444-555555555555';

/// The pane the shell hands a citizen page on an ordinary desktop.
const double _kPane = 1200;

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

class _FakeRest extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    final body = path.contains('/rest/v1/reports')
        ? jsonEncode(_reports)
        : '[]';
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      headers: const {'content-type': 'application/json; charset=utf-8'},
      request: request,
    );
  }
}

String _daysAgo(int d) =>
    DateTime.now().subtract(Duration(days: d)).toUtc().toIso8601String();

Map<String, dynamic> _row({
  required String id,
  required String category,
  required String status,
  required String createdAt,
  required String remarks,
  int media = 0,
}) => {
  'id': id,
  'category': category,
  'status': status,
  'created_at': createdAt,
  'barangay': 'Macanaya (Pescaria)',
  'address': 'Macanaya (Pescaria), Aparri, Cagayan',
  'remarks': remarks,
  'is_anonymous': false,
  'rejection_note': null,
  'report_media': [
    for (var i = 0; i < media; i++) {'id': 'm$i'},
  ],
};

final _reports = <Map<String, dynamic>>[
  _row(
    id: '3d1af001-0000-4000-8000-000000000001',
    category: 'environment',
    status: 'pending',
    createdAt: _daysAgo(0),
    remarks: 'concerning test only',
    media: 1,
  ),
  _row(
    id: '3d1af002-0000-4000-8000-000000000002',
    category: 'road',
    status: 'pending',
    createdAt: _daysAgo(32),
    remarks: 'Test Mingration 7',
    media: 1,
  ),
  _row(
    id: '3d1af003-0000-4000-8000-000000000003',
    category: 'road',
    status: 'resolved',
    createdAt: _daysAgo(34),
    remarks: 'Test Mingration 7 part 2',
    media: 1,
  ),
  _row(
    id: '3d1af004-0000-4000-8000-000000000004',
    category: 'road',
    status: 'pending',
    createdAt: _daysAgo(34),
    remarks: 'Test Migration 7',
    media: 1,
  ),
];

final _detailReport = ReportItem(
  id: '0CA73FC3',
  fullId: '3d1af001-0000-4000-8000-000000000001',
  category: 'Environment & Pollution',
  categoryKey: 'environment',
  barangay: 'Macanaya (Pescaria)',
  address: 'Macanaya (Pescaria), Aparri, Cagayan',
  remarks: 'concerning test only',
  status: ReportStatus.pending,
  dateReported: DateTime.now().subtract(const Duration(hours: 5)),
  mediaCount: 1,
);

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Citizen record band',
      home: Scaffold(
        backgroundColor: const Color(0xFF111827),
        body: SafeArea(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _pane('My Reports · list', const MyReportsBody()),
                _pane(
                  'Report detail',
                  ReportDetailScreen(report: _detailReport, username: 'Mark'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pane(String name, Widget child) {
    const band = kAccountMaxWidth - kAccountPageGutter * 2; // 816
    return Padding(
      padding: const EdgeInsets.all(8),
      child: SizedBox(
        width: _kPane,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                '$name · pane ${_kPane.toStringAsFixed(0)}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: Builder(
                builder: (context) {
                  final mq = MediaQuery.of(context);
                  return MediaQuery(
                    data: mq.copyWith(
                      size: Size(_kPane, mq.size.height),
                      padding: EdgeInsets.zero,
                      viewPadding: EdgeInsets.zero,
                    ),
                    child: Stack(
                      children: [
                        // The measure, drawn. A page on the shared band covers
                        // this strip exactly.
                        const Positioned.fill(
                          child: Center(
                            child: SizedBox(
                              width: band,
                              child: ColoredBox(color: Color(0xFFFDE68A)),
                            ),
                          ),
                        ),
                        Material(color: Colors.transparent, child: child),
                      ],
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
