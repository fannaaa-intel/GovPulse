// Responsive sweep for the My Submissions cards.
//
// The card title now comes from `displayLabel`, which can return a LONGER
// string than before — a category label ("Road & Infrastructure") in place of
// a truncated sentence — so every row it sits in has to be re-checked. Both
// tabs, both layouts (the mobile card and the separate web card), five sizes,
// three font scales.
//
// ── What this found ────────────────────────────────────────────────────────
// A pre-existing overflow, not caused by the label change: the "My Submissions"
// page header sized its title off the VIEWPORT (w * 0.052) while the glyphs
// grow with the user's font scale, so at 1.3x it overflowed the back-button row
// by 55px and by more at 1.6x. An unconstrained Text in a Row has nothing to
// give up. Fixed with Expanded + ellipsis.
//
// Each case initialises Supabase itself: the screen fetches on build, and
// sharing one client across tests in a file leaks between them.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:govpulse/features/home/settings/my-submission/my_submissions_screen.dart';
import '_responsive_matrix.dart';

const _kUserId = '11111111-2222-3333-4444-555555555555';

class _S extends LocalStorage {
  const _S();
  static final String _j = jsonEncode({
    'access_token': 'x', 'token_type': 'bearer', 'refresh_token': 'y',
    'user': {'id': _kUserId, 'aud': 'authenticated', 'role': 'authenticated',
      'email': 'a@b.c', 'app_metadata': {}, 'user_metadata': {},
      'created_at': '2026-01-01T00:00:00Z'},
  });
  @override Future<void> initialize() async {}
  @override Future<bool> hasAccessToken() async => true;
  @override Future<String?> accessToken() async => _j;
  @override Future<void> persistSession(String s) async {}
  @override Future<void> removePersistedSession() async {}
}

final _reports = [{
  'id': '00000000-0000-4000-8000-00000000000a', 'user_id': _kUserId,
  'category': 'others',
  'category_other': 'The bridge on the national highway has collapsed',
  'ai_category': 'road', 'barangay': 'Macanaya',
  'remarks': 'x', 'status': 'pending', 'created_at': '2026-09-17T01:00:00Z',
  'is_anonymous': false, 'report_media': [],
}];
final _suggs = [{
  'id': '00000000-0000-4000-8000-00000000000b', 'user_id': _kUserId,
  'category': 'others',
  'category_other': 'Please install a streetlight along Rizal Street corner',
  'ai_category': 'community_program', 'details': 'x', 'barangay': 'Macanaya',
  'address': null, 'latitude': null, 'longitude': null,
  'created_at': '2026-09-17T01:00:00Z', 'is_anonymous': false,
  'admin_response': null, 'reviewed_at': null,
}];

class _R extends http.BaseClient {
  @override Future<http.StreamedResponse> send(http.BaseRequest r) async {
    final u = r.url.toString();
    var b = <Map<String, dynamic>>[];
    if (u.contains('/rest/v1/reports')) {
      b = _reports;
    } else if (u.contains('/rest/v1/suggestions')) {
      b = _suggs;
    }
    return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(b))), 200,
        headers: const {'content-type': 'application/json; charset=utf-8'}, request: r);
  }
}

void main() {
  Future<void> init() async {
    await Supabase.initialize(
      url: 'https://vxvflhjbafqwehuxnmeq.supabase.co',
      anonKey: 'sb_publishable_ZBDaQPQdFyC5kOHGbce9Ig_zdtIi6Mo',
      httpClient: _R(),
      authOptions: const FlutterAuthClientOptions(
          localStorage: _S(), autoRefreshToken: false),
    );
    addTearDown(() async => Supabase.instance.dispose());
  }

  const devices = [kSmallPhone, kPhone, kModernPhone, kBigPhone, kTablet];
  for (final tab in [0, 1]) {
    final name = tab == 0 ? 'reports' : 'suggestions';
    for (final d in devices) {
      for (final scale in [1.0, 1.3, 1.6]) {
        testWidgets('$name @ ${d.name} x$scale', (t) async {
          await init();
          final errs = await pumpAt(t, d,
            () => MaterialApp(home: MySubmissionsScreen(username: 'J', initialTab: tab)),
            textScale: scale);
          await t.pump(const Duration(milliseconds: 600));
          expect(errs, isEmpty, reason: errs.join('\n'));
        });
      }
    }
    // Desktop/web layout too — a different card widget entirely.
    for (final w in [900.0, 1100.0, 1440.0]) {
      testWidgets('$name @ web ${w.toInt()}', (t) async {
        await init();
        final errs = await pumpAt(t, Device('web', Size(w, 900)),
          () => MaterialApp(home: MySubmissionsScreen(username: 'J', initialTab: tab)));
        await t.pump(const Duration(milliseconds: 600));
        expect(errs, isEmpty, reason: errs.join('\n'));
      });
    }
  }
}
