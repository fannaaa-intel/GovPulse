// Dev-only harness for the ADMIN "Activity log" surfaces.
//
// Not part of the app: nothing under lib/ imports it, and it is never a build
// target for a shipped bundle.
//
//   flutter build web --release -t tool/preview_admin_activity_log.dart
//   python -m http.server 57813 --directory build/web
//
// ── Why this exists ────────────────────────────────────────────────────────
// The admin console is login-gated and role-gated, so a fresh browser profile
// can never reach Settings. Both seams `Supabase.initialize` exposes are faked
// (see tool/preview_my_reports_web.dart for the full explanation): a persisted
// session whose access token is deliberately not a JWT, so it never expires or
// refreshes, and an http client that answers admin_activity_log from a canned
// list.
//
// ── What to look at ────────────────────────────────────────────────────────
//  * The Settings card lists exactly FIVE actions, then "View all".
//  * "View all" at >= 760 CSS px opens a centred pop-up modal over a frosted
//    console, with an X at the top right.
//  * "View all" below 760 pushes a full screen with the chevron back control.
// The width buttons drive a MediaQuery override so both branches can be seen
// without resizing the browser.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:govpulse/features/admin/pages/admin_settings_page.dart';
import 'package:govpulse/features/admin/theme/admin_ui.dart';

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
    final body = path.contains('/rest/v1/admin_activity_log')
        ? jsonEncode(_log)
        : '[]';
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      headers: const {'content-type': 'application/json; charset=utf-8'},
      request: request,
    );
  }
}

/// Nineteen rows across several days — enough that the Settings card has to
/// truncate and the history has to group by day.
final List<Map<String, dynamic>> _log = () {
  const actions = [
    ('user_reactivated', 'Rheinz', null),
    ('user_deactivated', 'Rheinz', 'Account inactive or dormant'),
    ('broadcast_sent', 'Hi', 'Reached 5 citizens'),
    ('identity_revealed', 'report 4D8D1A8E', 'test'),
    ('identity_revealed', 'suggestion D20F48F9', 'Test'),
    ('identity_revealed', 'feedback 38A27D9D', 'Test'),
    ('staff_created', 'Rheinz', null),
    ('identity_revealed', 'suggestion 31FF912B', 'This is test'),
    ('suspension_lifted', 'mark_reduca', null),
    ('user_suspended', 'mark_reduca', 'Violation of community guidelines'),
    ('restriction_lifted', 'juan_dc', null),
    ('user_restricted', 'juan_dc', 'Repeated spam reports'),
    ('broadcast_sent', 'Brownout advisory', 'Reached 128 citizens'),
    ('staff_created', 'Engr. Danao', null),
    ('user_reactivated', 'ana_p', null),
    ('user_deactivated', 'ana_p', 'Requested by the account holder'),
    ('identity_revealed', 'report 7C1B0E22', 'Flooded road'),
    ('suspension_lifted', 'pedro_s', null),
    ('user_suspended', 'pedro_s', 'Abusive comments'),
  ];
  final base = DateTime(2026, 8, 22, 11, 22);
  return [
    for (var i = 0; i < actions.length; i++)
      {
        'id': '00000000-0000-0000-0000-${i.toString().padLeft(12, '0')}',
        'action': actions[i].$1,
        'actor_name': 'Admin',
        'target_label': actions[i].$2,
        'detail': actions[i].$3,
        // Two or three rows per day, walking backwards.
        'created_at': base
            .subtract(Duration(days: i ~/ 3, hours: i % 3))
            .toUtc()
            .toIso8601String(),
      },
  ];
}();

// ── Harness ─────────────────────────────────────────────────────────────────

class _PreviewApp extends StatefulWidget {
  const _PreviewApp();
  @override
  State<_PreviewApp> createState() => _PreviewAppState();
}

class _PreviewAppState extends State<_PreviewApp> {
  // The widths the launcher switches on: 360, 420 and 700 must push a screen,
  // 900 and 1280 must open the modal. 360 is the tightest phone worth
  // supporting — the filter chips must still fit without clipping there.
  double _width = 1280;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF1F2937),
        body: Column(
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final w in const [360.0, 420.0, 700.0, 900.0, 1280.0])
                      FilledButton(
                        onPressed: () => setState(() => _width = w),
                        style: FilledButton.styleFrom(
                          backgroundColor: _width == w
                              ? Colors.white
                              : Colors.white24,
                          foregroundColor: _width == w
                              ? Colors.black
                              : Colors.white,
                        ),
                        child: Text('${w.toInt()} px'),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: SizedBox(
                  width: _width,
                  child: ClipRect(
                    child: Builder(
                      builder: (outer) {
                        final mq = MediaQuery.of(outer);
                        return MediaQuery(
                          // The launcher reads MediaQuery width, so the
                          // override is what decides modal vs pushed screen.
                          data: mq.copyWith(
                            size: Size(_width, mq.size.height - 70),
                          ),
                          child: Container(
                            color: AdminUi.pageBg,
                            // A nested Navigator so a pushed screen stays
                            // inside the simulated viewport.
                            child: Navigator(
                              onGenerateRoute: (_) => MaterialPageRoute(
                                builder: (_) => AdminSettingsPage(
                                  onLogout: () {},
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
