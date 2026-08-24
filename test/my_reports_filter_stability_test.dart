// The stat row must not resize when a filter is selected.
//
// ── The bug this pins ──────────────────────────────────────────────────────
// The four stat cards carried their selection as `border: Border.all(width:
// selected ? 2 : 1)` inside the card's `decoration`. A border there insets the
// child, so selecting a card made it 2px taller. The four sit in a Row whose
// height is its tallest child, so the row grew — and every pixel of the page
// below it moved down.
//
// Switching between filters was worse than selecting one: for the 320ms of the
// AnimatedContainer, one card is shrinking while another grows, so the row's
// height wobbles and the whole screen shakes. That is what "the whole element
// shakes when I tap All / Pending / Resolved / Rejected" was.
//
// The ring moved to `foregroundDecoration`, which paints over the child and
// takes no part in layout. These assertions are on SIZE, not on the ring, so
// they hold whichever way a future version chooses to draw it.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:govpulse/features/home/my_report/my_reports_screen.dart';

const _kUserId = '11111111-2222-3333-4444-555555555555';

/// The page renders its error state — and no stat row at all — if the fetch
/// fails, so the session and the rows are both faked, at the two seams
/// `Supabase.initialize` exposes. Same trick as tool/preview_my_reports_web.dart.
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
    final body = request.url.path.contains('/rest/v1/reports')
        ? jsonEncode(_rows)
        : '[]';
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      headers: const {'content-type': 'application/json; charset=utf-8'},
      request: request,
    );
  }
}

// All PENDING on purpose. A status badge repeats its own word, so this leaves
// 'Resolved' and 'Rejected' unique to the stat cards — the date chips are All /
// Today / This Week / This Month / Last 3 Months, which do not collide either.
final _rows = <Map<String, dynamic>>[
  for (var i = 1; i <= 3; i++)
    {
      'id': '3d1af00$i-0000-4000-8000-00000000000$i',
      'category': 'road',
      'status': 'pending',
      'created_at': DateTime.now()
          .subtract(Duration(days: i))
          .toUtc()
          .toIso8601String(),
      'barangay': 'Macanaya',
      'address': 'Macanaya, Aparri, Cagayan',
      'remarks': 'Canned row $i',
      'is_anonymous': false,
      'rejection_note': null,
      'report_media': const <Map<String, dynamic>>[],
    },
];

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

  testWidgets('selecting a stat filter never resizes the stat row', (
    tester,
  ) async {
    // A phone viewport: `kIsWeb` is a compile-time false in the VM, so this
    // exercises the MOBILE arm — which is the right place for it, because the
    // stat card is one widget shared by both arms and the wobble was in the
    // card, not in either layout around it. Tall so nothing has to scroll.
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // The BODY, not the screen: the screen wraps itself in the shell's nav
    // scaffold, which wants a router and a rail this test has no use for.
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          // Every glyph in the widget-test font is a SQUARE of the font size,
          // so a real 14-character heading measures ~2x what it does on a
          // device and the page's rows overflow for reasons that have nothing
          // to do with the page. 0.6 is the compensation the rest of this
          // suite uses — see test/account_web_kit_test.dart.
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(0.6)),
            child: child!,
          ),
          home: const Scaffold(body: MyReportsBody()),
        ),
      ),
    );
    // The fetch resolves on a microtask, then the entrance animation runs.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));

    Rect cardOf(String label) => tester.getRect(
      find
          .ancestor(
            of: find.text(label),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );

    final resolvedAtRest = cardOf('Resolved');
    final rejectedAtRest = cardOf('Rejected');

    await tester.tap(find.text('Resolved'));
    await tester.pump();

    // Mid-flight is where the wobble lived: the card being selected and the
    // card being deselected are both part-way through their 320ms curve.
    await tester.pump(const Duration(milliseconds: 160));
    expect(cardOf('Resolved').size, resolvedAtRest.size);
    expect(cardOf('Rejected'), rejectedAtRest);

    // And settled.
    await tester.pump(const Duration(milliseconds: 400));
    expect(cardOf('Resolved').size, resolvedAtRest.size);
    expect(
      cardOf('Rejected'),
      rejectedAtRest,
      reason: 'a card nobody touched must not have moved OR resized',
    );
  });
}
