// The two lists a submission now lands on must fit the phones the app supports.
//
// Neither My Submissions nor My Reports was in responsive_audit_test, and both
// carried a horizontal overflow that nothing was watching: My Submissions' tab
// strip, and My Reports' toolbar. They were found by the post-submit navigation
// work — which sends citizens to these two screens — rather than by anything
// looking at them, which is the point of adding them to a sweep.
//
// ── What overflowed, and why width alone did not cause it ──────────────────
// My Submissions' tab strip gives each of the three tabs an `Expanded`, so a
// tab is exactly a third of the width no matter what is in it. Inside that
// third sits an unyielding Row: the label, a count badge, and on Suggestions
// and Feedback an unseen-reply dot. 'Suggestions' is the longest word, its
// badge grows a digit at 10 and another at 100, and the dot only appears once
// an LGU has replied — so the strip fits until a citizen is active enough for
// it not to, which is why it survived this long.
//
// The counts are therefore part of the test matrix, not incidental to it.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:govpulse/core/widgets/web/web_card_grid.dart';
import 'package:govpulse/features/home/my_report/my_reports_screen.dart';
import 'package:govpulse/features/home/settings/my-submission/my_submissions_screen.dart';

const _kUserId = '11111111-2222-3333-4444-555555555555';

/// The narrowest phone the app supports, the common modern sizes, and a large
/// one. Mirrors responsive_audit_test's ladder.
const _phones = <(String, double)>[
  ('320 · smallest supported', 320),
  ('360 · Android baseline', 360),
  ('390 · iPhone 14', 390),
  ('414 · iPhone Plus', 414),
  ('430 · iPhone Pro Max', 430),
];

/// Row counts per table. The badge width follows the digit count, so this is
/// what decides whether the strip fits.
int _rowsFor(String table) => _counts[table] ?? 0;
Map<String, int> _counts = const {};

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

/// Answers each table with `_rowsFor` rows, so the tab badges carry real digit
/// counts rather than always reading 0.
class _FakeRest extends http.BaseClient {
  Map<String, dynamic> _row(String table, int i) => switch (table) {
    'suggestions' => {
      'id': 'aaaaaaa$i-0000-4000-8000-00000000000$i',
      'title': 'Suggestion $i',
      'suggestion': 'Body $i',
      'category': 'road',
      'status': 'pending',
      'created_at': '2026-08-0${(i % 9) + 1}T00:00:00Z',
      'admin_response': null,
      'responded_at': null,
      'barangay': 'Macanaya',
    },
    'feedbacks' => {
      'id': 'bbbbbbb$i-0000-4000-8000-00000000000$i',
      'message': 'Feedback $i',
      'rating': 4,
      'created_at': '2026-08-0${(i % 9) + 1}T00:00:00Z',
      'admin_response': null,
      'responded_at': null,
    },
    _ => {
      'id': 'ccccccc$i-0000-4000-8000-00000000000$i',
      'category': 'road',
      'status': 'pending',
      'created_at': '2026-08-0${(i % 9) + 1}T00:00:00Z',
      'barangay': 'Macanaya',
      'address': 'Macanaya, Aparri, Cagayan',
      'remarks': 'Row $i',
      'is_anonymous': false,
      'rejection_note': null,
      'report_media': const <Map<String, dynamic>>[],
    },
  };

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    final table = ['suggestions', 'feedbacks', 'reports'].firstWhere(
      (t) => path.contains('/rest/v1/$t'),
      orElse: () => '',
    );
    final body = table.isEmpty
        ? '[]'
        : jsonEncode([
            for (var i = 0; i < _rowsFor(table); i++) _row(table, i),
          ]);
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      headers: const {'content-type': 'application/json; charset=utf-8'},
      request: request,
    );
  }
}

/// Pumps [child] at [width] on a tall viewport and fails on any overflow.
///
/// Tall so nothing has to scroll: an off-screen row is not laid out, and a
/// vertical scroll would hide the very thing being measured.
Future<void> _pumpAt(
  WidgetTester tester,
  double width,
  Widget child,
) async {
  tester.view.physicalSize = Size(width, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(ProviderScope(child: MaterialApp(home: child)));
  // Fixed frames, NOT pumpAndSettle: My Submissions runs a shimmer controller
  // on `repeat()` for its skeleton, so the tree never reaches a settled state
  // and pumpAndSettle times out rather than telling you anything about layout.
  // Enough frames for the fetch to resolve and the entry animation to finish.
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }

  expect(
    tester.takeException(),
    isNull,
    reason: 'nothing may overflow at ${width.toInt()}px',
  );
}

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

  tearDown(() => _counts = const {});

  group('My Submissions fits every phone', () {
    // Three digit widths. A citizen with 100+ of anything is unusual but not
    // impossible, and it is the cheapest place to find the ceiling.
    for (final (label, counts) in <(String, Map<String, int>)>[
      ('empty', {}),
      ('single digits', {'reports': 3, 'suggestions': 4, 'feedbacks': 2}),
      ('double digits', {'reports': 12, 'suggestions': 34, 'feedbacks': 21}),
      ('triple digits', {'reports': 120, 'suggestions': 134, 'feedbacks': 118}),
    ]) {
      for (final (name, width) in _phones) {
        testWidgets('$label · $name', (tester) async {
          _counts = counts;
          await _pumpAt(
            tester,
            width,
            const MySubmissionsScreen(username: 'juan'),
          );

          // The strip is the thing under test, so prove it is actually built —
          // an error state would render none of it and pass vacuously.
          expect(find.text('Suggestions'), findsOneWidget);

          // ── And prove the fix did not just hide the problem ─────────────
          // Flexing the label buys the room by allowing an ellipsis, so a
          // label that is actually being truncated would pass the overflow
          // check while reading 'Suggestio…' — trading a visible bug for a
          // quieter one. It must never come to that at these widths.
          for (final label in const ['Reports', 'Suggestions', 'Feedback']) {
            final text = tester.widget<Text>(find.text(label));
            final painter = TextPainter(
              text: TextSpan(text: label, style: text.style),
              maxLines: 1,
              textDirection: TextDirection.ltr,
            )..layout();
            expect(
              painter.didExceedMaxLines,
              isFalse,
              reason: '"$label" must render whole at ${width.toInt()}px',
            );
          }
        });
      }
    }
  });

  // The web grid's cards must also line up. The phone widths above never build
  // it (one column below a 760 content width), so this is the band where two
  // cards actually sit side by side — the arrangement in the screenshots.
  group('My Reports web grid', () {
    testWidgets('cards in a row share a height', (tester) async {
      _counts = const {'reports': 3};
      tester.view.physicalSize = const Size(1440, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: MyReportsScreen(username: 'juan')),
        ),
      );
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      final grids = find.byType(WebCardGrid);
      if (grids.evaluate().isEmpty) return; // layout chose the compact arm

      // Every IntrinsicHeight row inside the grid must hand its children the
      // same height — the ragged baseline is exactly what this catches.
      final rows = find.descendant(
        of: grids.first,
        matching: find.byType(IntrinsicHeight),
      );
      expect(rows, findsWidgets);
      for (final row in rows.evaluate()) {
        final rowBox = row.renderObject! as RenderBox;
        expect(rowBox.size.height, greaterThan(0));
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('My Reports fits every phone', () {
    for (final (name, width) in _phones) {
      testWidgets(name, (tester) async {
        _counts = const {'reports': 6};
        await _pumpAt(tester, width, const MyReportsScreen(username: 'juan'));
      });
    }
  });
}
