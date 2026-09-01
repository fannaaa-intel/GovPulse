// The two submission lists, WITH CONTENT IN THEM, across every size.
//
// ── Why this exists next to responsive_audit_test ──────────────────────────
// That file states its own limit plainly: Supabase is not initialised there, so
// every screen settles into its EMPTY state and "a populated list is not
// covered here". It is the right trade for a sweep of thirty screens — the
// chrome is what the viewport-width bug deformed — but it means the rows
// themselves, which is where a citizen's own text and a growing count land,
// have never been measured at all.
//
// Both bugs already found on these screens were in that uncovered half:
//   • My Submissions' tab strip overflowed once it carried count badges.
//   • My Reports' Report History header overflowed with the count beside it.
// Neither is reachable with an empty list, which is why nothing caught them.
//
// So this sweeps the same matrix — every phone, both orientations, three text
// scales — with rows actually present, and adds the WEB widths, where the
// two-column grid exists at all.
//
// ── What the rows are chosen to be ─────────────────────────────────────────
// Deliberately hostile but real: the longest category label the app ships, a
// two-line Aparri address, a remark long enough to clamp, and counts in the
// hundreds so every badge is at its widest. A citizen writes worse than a
// fixture does, and the fixture is the only defence.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:govpulse/features/home/my_report/my_reports_screen.dart';
import 'package:govpulse/features/home/settings/my-submission/my_submissions_screen.dart';

import '_responsive_matrix.dart';

const _kUserId = '11111111-2222-3333-4444-555555555555';

/// Android's "Largest" is 1.3; 1.0 is what everything is designed at.
const _textScales = <double>[1.0, 1.15, 1.3];

/// A long-but-plausible barangay + street, the shape that wraps to two lines.
const _longAddress =
    'Macanaya (Pescaria), Barangay Macanaya, Near lyceum of aparri, '
    'Aparri, Cagayan';

/// Long enough to clamp, in the language citizens actually file in.
const _longRemark =
    'Sirang sira na po mga kalsada dito halos di na madaanan ng mga tao '
    'kawawa naman po yung mga bata na dumadaan dito araw araw papuntang '
    'eskwelahan, sana po ay maaksyunan agad ito ng LGU natin salamat po.';

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
  Future<void> persistSession(String s) async {}
}

/// Serves rows for all three tables. Row COUNT is what drives the tab badges,
/// so it is a knob rather than a constant.
class _PopulatedRest extends http.BaseClient {
  _PopulatedRest({this.rows = 3});

  final int rows;

  /// A mix of statuses so every badge variant is laid out, not just 'pending'.
  static const _statuses = ['pending', 'in_progress', 'resolved', 'rejected'];

  Map<String, dynamic> _report(int i) => {
    'id': 'ccccccc${i % 10}-0000-4000-8000-00000000000${i % 10}',
    'category': 'road',
    'status': _statuses[i % _statuses.length],
    'created_at': '2026-08-0${(i % 9) + 1}T00:00:00Z',
    'barangay': 'Macanaya (Pescaria)',
    'address': _longAddress,
    'remarks': _longRemark,
    'is_anonymous': false,
    'rejection_note': i % 4 == 3 ? 'Duplicate of an earlier report.' : null,
    'report_media': const [
      {'id': 'm1'},
    ],
  };

  Map<String, dynamic> _suggestion(int i) => {
    'id': 'aaaaaaa${i % 10}-0000-4000-8000-00000000000${i % 10}',
    'category': 'others',
    'category_other': 'Peace and Order / Public Safety',
    'details': _longRemark,
    'barangay': 'Macanaya (Pescaria)',
    'address': _longAddress,
    'latitude': 18.35,
    'longitude': 121.63,
    'created_at': '2026-08-0${(i % 9) + 1}T00:00:00Z',
    'is_anonymous': false,
    'admin_response': i.isEven ? 'Thank you, forwarded to the office.' : null,
    'reviewed_at': i.isEven ? '2026-08-10T00:00:00Z' : null,
    'dismissed_at': null,
    'responder_photo_url': null,
  };

  Map<String, dynamic> _feedback(int i) => {
    'id': 'fffffff${i % 10}-0000-4000-8000-00000000000${i % 10}',
    'office_id': 'mayor',
    'office_label': "Office of the Municipal Mayor — Aparri, Cagayan",
    'service_name': 'Business Permit and Licensing',
    'overall_rating': (i % 5) + 1,
    'aspect_staff': 4,
    'aspect_wait': 3,
    'aspect_clarity': 5,
    'aspect_facility': 4,
    'photo_urls': const <String>[],
    'visit_date': '2026-08-0${(i % 9) + 1}',
    'created_at': '2026-08-0${(i % 9) + 1}T00:00:00Z',
    'comment': _longRemark,
    'is_anonymous': false,
    'admin_response': i.isEven ? 'Salamat po sa inyong feedback.' : null,
    'reviewed_at': i.isEven ? '2026-08-10T00:00:00Z' : null,
    'dismissed_at': null,
    'responder_photo_url': null,
  };

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    Map<String, dynamic> Function(int)? make;
    if (path.contains('/rest/v1/reports')) {
      make = _report;
    } else if (path.contains('/rest/v1/suggestions')) {
      make = _suggestion;
    } else if (path.contains('/rest/v1/feedbacks')) {
      make = _feedback;
    }
    final body = make == null
        ? '[]'
        : jsonEncode([for (var i = 0; i < rows; i++) make(i)]);
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      headers: const {'content-type': 'application/json; charset=utf-8'},
      request: request,
    );
  }
}

late _PopulatedRest _rest;

/// Forwards to whichever fixture the current test installed — the Supabase
/// client keeps the instance it was given at initialize().
class _RestProxy extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _rest.send(request);
}

Widget _shell(Widget screen) => ProviderScope(
  child: MaterialApp(debugShowCheckedModeBanner: false, home: screen),
);

/// Sweeps [build] across every phone, both orientations and every text scale,
/// returning one line per combination that overflowed.
Future<List<String>> _sweepPhones(
  WidgetTester tester,
  Widget Function() build,
) async {
  final failures = <String>[];
  for (final device in kAllPhones) {
    for (final scale in _textScales) {
      final errors = await pumpAt(
        tester,
        device,
        () => _shell(build()),
        textScale: scale,
      );
      for (final e in errors.toSet()) {
        failures.add('$device @ ${scale}x — $e');
      }
    }
  }
  // Dispose the last tree so its controllers and debounces do not outlive the
  // test and get reported as a pending timer. Same reason responsive_audit
  // does it.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
  return failures;
}

/// The desktop/tablet widths the citizen web shell actually renders at.
///
/// 768 and 1024 straddle the point where the compact arm hands over to the
/// two-column grid; 1280 and 1440 are ordinary laptop widths; 1920 is the
/// widest the band is designed for.
const _webSizes = <Device>[
  Device('web 768', Size(768, 1024)),
  Device('web 1024', Size(1024, 900)),
  Device('web 1280', Size(1280, 900)),
  Device('web 1440', Size(1440, 900)),
  Device('web 1920', Size(1920, 1080)),
];

Future<List<String>> _sweepWeb(
  WidgetTester tester,
  Widget Function() build,
) async {
  final failures = <String>[];
  for (final device in _webSizes) {
    // 1.3 as well as 1.0: a browser zoom / OS text size lands here too, and it
    // is the setting that breaks a row that only just fitted.
    for (final scale in const [1.0, 1.3]) {
      final errors = await pumpAt(
        tester,
        device,
        () => _shell(build()),
        textScale: scale,
      );
      for (final e in errors.toSet()) {
        failures.add('$device @ ${scale}x — $e');
      }
    }
  }
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
  return failures;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    _rest = _PopulatedRest();
    await Supabase.initialize(
      url: 'https://vxvflhjbafqwehuxnmeq.supabase.co',
      anonKey: 'sb_publishable_ZBDaQPQdFyC5kOHGbce9Ig_zdtIi6Mo',
      httpClient: _RestProxy(),
      authOptions: const FlutterAuthClientOptions(
        localStorage: _FakeSessionStorage(),
        autoRefreshToken: false,
        detectSessionInUri: false,
      ),
      debug: false,
    );
  });

  // ── Mobile ────────────────────────────────────────────────────────────────

  group('mobile · with rows', () {
    testWidgets('MyReportsScreen fits every phone', (tester) async {
      _rest = _PopulatedRest(rows: 4);
      final failures = await _sweepPhones(
        tester,
        () => const MyReportsScreen(username: 'juandelacruz'),
      );
      expect(failures, isEmpty, reason: '\n${failures.join('\n')}');
    });

    testWidgets('MySubmissionsScreen fits every phone, on every tab', (
      tester,
    ) async {
      // Every tab: the strip is the same on all three, but the LIST under it is
      // not, and each has its own card.
      _rest = _PopulatedRest(rows: 4);
      final failures = <String>[];
      for (var tab = 0; tab < 3; tab++) {
        failures.addAll(
          await _sweepPhones(
            tester,
            () => MySubmissionsScreen(
              username: 'juandelacruz',
              initialTab: tab,
            ),
          ).then((f) => f.map((e) => 'tab $tab · $e')),
        );
      }
      expect(failures, isEmpty, reason: '\n${failures.join('\n')}');
    });

    testWidgets('a three-digit count does not break the tab strip', (
      tester,
    ) async {
      // The badge is the widest thing in the strip and grows with the count.
      // 100+ of anything is unusual but not impossible, and it is the cheapest
      // place to find the ceiling.
      _rest = _PopulatedRest(rows: 128);
      final failures = await _sweepPhones(
        tester,
        () => const MySubmissionsScreen(username: 'juandelacruz'),
      );
      expect(failures, isEmpty, reason: '\n${failures.join('\n')}');
    });
  });

  // ── Web ───────────────────────────────────────────────────────────────────

  group('web · with rows', () {
    testWidgets('MyReportsScreen fits every web width', (tester) async {
      // 3 rows on purpose: an ODD count is what leaves a short last row in the
      // two-column grid, which is the arrangement that read as misaligned.
      _rest = _PopulatedRest(rows: 3);
      final failures = await _sweepWeb(
        tester,
        () => const MyReportsScreen(username: 'juandelacruz'),
      );
      expect(failures, isEmpty, reason: '\n${failures.join('\n')}');
    });

    testWidgets('MySubmissionsScreen fits every web width, on every tab', (
      tester,
    ) async {
      _rest = _PopulatedRest(rows: 3);
      final failures = <String>[];
      for (var tab = 0; tab < 3; tab++) {
        failures.addAll(
          await _sweepWeb(
            tester,
            () => MySubmissionsScreen(
              username: 'juandelacruz',
              initialTab: tab,
            ),
          ).then((f) => f.map((e) => 'tab $tab · $e')),
        );
      }
      expect(failures, isEmpty, reason: '\n${failures.join('\n')}');
    });
  });
}
