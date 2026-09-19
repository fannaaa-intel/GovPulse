// A just-filed submission must appear without a manual reload.
//
// ── The bug ────────────────────────────────────────────────────────────────
// A submission's row is written moments before My Submissions opens, and the
// first fetch could still miss it. The screen then showed "No feedback found"
// for the feedback the citizen had just sent, and it appeared on reload.
//
// Two things had to be wrong at once for it to stick, and both were:
//
//   1. `_subscribeRealtime` ran AFTER the queries came back, so a row written
//      during the fetch had its INSERT event go by with no listener attached.
//      Nothing then triggered a second fetch, ever.
//   2. Realtime is best-effort anyway — the tables have to be in the
//      publication and the socket has to be up — so it cannot be the only
//      recovery. "Pull to refresh" is not an answer to "where is the thing I
//      just sent".
//
// Feedback was the one that showed it because its INSERT fires an AFTER trigger
// that makes an outbound HTTP call (classify_feedback_on_insert), so its row
// takes the longest to become readable. Reports and suggestions were winning
// the same race, not avoiding it.
//
// The fix: subscribe before fetching, and carry a `justSubmitted` flag that
// makes the screen retry briefly when the tab it was sent to comes back empty.
//
// ── The half of it that was still broken ───────────────────────────────────
// "Comes back empty" was the wrong test, and it only ever worked for a citizen
// with nothing on the tab. Anyone who had filed before arrived at a tab that
// was non-empty the moment it loaded — their OLDER rows — so the wait was
// satisfied instantly, the retry never armed, and the thing they had just sent
// was missing until they refreshed by hand. The more someone used GovPulse,
// the more reliably it failed them, which is the opposite of how a bug like
// this is usually noticed.
//
// So the arrival now carries the id of the row it is waiting for, and the
// question becomes "is THAT row here" rather than "is anything here".

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:govpulse/features/home/settings/my-submission/my_submissions_screen.dart';

const _kUserId = '11111111-2222-3333-4444-555555555555';

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

/// Models the race: the feedbacks table reads EMPTY for the first
/// [emptyFeedbackReads] selects, then starts returning the row — exactly what a
/// row that is written but not yet readable looks like from the client.
class _LateRowRest extends http.BaseClient {
  _LateRowRest({required this.emptyFeedbackReads, this.withOlderRow = false});

  final int emptyFeedbackReads;

  /// Serves one OLDER feedback from the very first read, the way a returning
  /// citizen's tab actually looks. The new row still arrives late.
  ///
  /// This is what makes the tab non-empty immediately, and it is the whole
  /// difference between the bug reproducing and not.
  final bool withOlderRow;

  /// Selects against `feedbacks`, counted so a test can prove the screen
  /// retried rather than gave up — and that it STOPPED retrying.
  int feedbackReads = 0;

  /// The id the screen is told to wait for — the row filed seconds ago.
  static const kNewId = 'ffffffff-0000-4000-8000-000000000001';

  static const _older = {
    'id': 'aaaaaaaa-0000-4000-8000-00000000000a',
    'office_id': 'health',
    'office_label': 'Municipal Health Office',
    'service_name': 'Medical Certificate',
    'overall_rating': 4,
    'aspect_staff': null,
    'aspect_wait': null,
    'aspect_clarity': null,
    'aspect_facility': null,
    'photo_urls': <String>[],
    'visit_date': '2026-08-01',
    'created_at': '2026-08-01T00:00:00Z',
    'comment': 'Matagal ang pila pero maayos naman',
    'is_anonymous': false,
    'admin_response': null,
    'reviewed_at': null,
    'dismissed_at': null,
    'responder_photo_url': null,
  };

  static const _row = {
    'id': kNewId,
    'office_id': 'mayor',
    'office_label': "Mayor's Office",
    'service_name': 'Business Permit',
    'overall_rating': 5,
    'aspect_staff': null,
    'aspect_wait': null,
    'aspect_clarity': null,
    'aspect_facility': null,
    'photo_urls': <String>[],
    'visit_date': '2026-09-01',
    'created_at': '2026-09-01T00:00:00Z',
    'comment': 'Mabilis ang serbisyo',
    'is_anonymous': false,
    'admin_response': null,
    'reviewed_at': null,
    'dismissed_at': null,
    'responder_photo_url': null,
  };

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    var body = '[]';
    if (path.contains('/rest/v1/feedbacks')) {
      feedbackReads++;
      final arrived = feedbackReads > emptyFeedbackReads;
      final rows = [if (arrived) _row, if (withOlderRow) _older];
      body = jsonEncode(rows);
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      headers: const {'content-type': 'application/json; charset=utf-8'},
      request: request,
    );
  }
}

late _LateRowRest _rest;

Future<void> _open(
  WidgetTester tester, {
  required bool justSubmitted,
  String? newId,
}) async {
  tester.view.physicalSize = const Size(390, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: MySubmissionsScreen(
          username: 'juan',
          initialTab: 2,
          justSubmitted: justSubmitted,
          highlightId: newId,
        ),
      ),
    ),
  );
  // Fixed frames, not pumpAndSettle: the skeleton's shimmer runs on repeat() so
  // the tree never settles. Kept well under the 600ms retry gap so this shows
  // the state after the FIRST fetch only — the point a test wants to inspect
  // before any retry has had a chance to run.
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
}

/// Advances past the retry window (4 tries, 600ms apart) with margin.
/// Pumps past the whole retry window with room to spare.
///
/// The gap widens per attempt (400ms, 800ms, 1.2s …), so six tries span about
/// 8.4s rather than a flat 2.4s. This walks ~12s in small steps, because a
/// timer only fires if the clock actually passes it — one big pump would skip
/// the intermediate fetches and measure the wrong thing.
Future<void> _advancePastRetries(WidgetTester tester) async {
  for (var i = 0; i < 80; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    _rest = _LateRowRest(emptyFeedbackReads: 0);
    await Supabase.initialize(
      url: 'https://vxvflhjbafqwehuxnmeq.supabase.co',
      anonKey: 'sb_publishable_ZBDaQPQdFyC5kOHGbce9Ig_zdtIi6Mo',
      // The client holds this instance, so the tests swap its FIELDS rather
      // than the object.
      httpClient: _RestProxy(),
      authOptions: const FlutterAuthClientOptions(
        localStorage: _FakeSessionStorage(),
        autoRefreshToken: false,
        detectSessionInUri: false,
      ),
      debug: false,
    );
  });

  testWidgets('a row that is not readable yet still appears, no reload', (
    tester,
  ) async {
    // Misses the first two reads — the shape of the reported bug.
    _rest = _LateRowRest(emptyFeedbackReads: 2);

    await _open(tester, justSubmitted: true);

    // The first fetch found nothing, exactly as it did in production.
    expect(_rest.feedbackReads, 1);
    expect(find.text('No feedback found'), findsOneWidget);

    await _advancePastRetries(tester);

    expect(
      find.text('No feedback found'),
      findsNothing,
      reason:
          'the retry has to surface a row the first fetch missed — this is the '
          'whole bug: the citizen saw an empty list for what they just sent',
    );
    expect(find.textContaining('Mabilis ang serbisyo'), findsOneWidget);
  });

  testWidgets('the retry gives up rather than polling forever', (tester) async {
    // Never returns the row. The screen must stop asking.
    _rest = _LateRowRest(emptyFeedbackReads: 1 << 30);

    await _open(tester, justSubmitted: true);
    await _advancePastRetries(tester);
    final settled = _rest.feedbackReads;

    // Well past the window — nothing more may be issued.
    await _advancePastRetries(tester);

    expect(
      _rest.feedbackReads,
      settled,
      reason:
          'the budget is spent once; re-arming it would poll the database for '
          'as long as the screen is open',
    );
    expect(
      settled,
      lessThanOrEqualTo(7),
      reason: 'one initial fetch plus a small fixed number of retries',
    );
    expect(
      find.text('No feedback found'),
      findsOneWidget,
      reason: 'a genuinely empty tab still ends on the honest empty state',
    );
  });

  testWidgets('an ordinary visit does not retry at all', (tester) async {
    // Someone opening My Submissions on an empty Feedback tab is not waiting on
    // anything, so the empty state must be immediate and final.
    _rest = _LateRowRest(emptyFeedbackReads: 1 << 30);

    await _open(tester, justSubmitted: false);
    expect(_rest.feedbackReads, 1);
    expect(find.text('No feedback found'), findsOneWidget);

    await _advancePastRetries(tester);

    expect(
      _rest.feedbackReads,
      1,
      reason: 'no submission was made, so there is nothing to wait for',
    );
  });

  // ── The returning citizen ────────────────────────────────────────────────

  testWidgets('a late row arrives even when the tab already has older ones', (
    tester,
  ) async {
    // THE regression. One older feedback is served from the first read, so the
    // tab is non-empty immediately — which is what silently satisfied the old
    // "has anything on it" test and stopped the retry from ever arming.
    _rest = _LateRowRest(emptyFeedbackReads: 2, withOlderRow: true);

    await _open(tester, justSubmitted: true, newId: _LateRowRest.kNewId);

    // The tab is NOT empty — there is no empty state to notice — and yet the
    // thing the citizen just sent is not on it. That is the bug exactly: it
    // looks like a finished list.
    expect(find.text('No feedback found'), findsNothing);
    expect(find.textContaining('Matagal ang pila'), findsOneWidget);
    expect(
      find.textContaining('Mabilis ang serbisyo'),
      findsNothing,
      reason:
          'the new row has not been written yet — this is the starting '
          'state the citizen actually saw',
    );

    await _advancePastRetries(tester);

    expect(
      find.textContaining('Mabilis ang serbisyo'),
      findsOneWidget,
      reason:
          'the wait is for THIS row, not for the tab to be non-empty — a '
          'citizen who has filed before must not have to refresh by hand',
    );
  });

  testWidgets('waiting for a named row still stops', (tester) async {
    // The row never becomes readable. Naming one must not turn the retry into
    // an unbounded poll just because the tab has other rows on it forever.
    _rest = _LateRowRest(emptyFeedbackReads: 1 << 30, withOlderRow: true);

    await _open(tester, justSubmitted: true, newId: _LateRowRest.kNewId);
    await _advancePastRetries(tester);
    final settled = _rest.feedbackReads;

    await _advancePastRetries(tester);

    expect(
      _rest.feedbackReads,
      settled,
      reason: 'the budget is spent once, named row or not',
    );
    expect(settled, lessThanOrEqualTo(7));
    expect(
      find.textContaining('Matagal ang pila'),
      findsOneWidget,
      reason: 'giving up leaves the rows that DID load, not an error',
    );
  });

  testWidgets('an ordinary visit does not retry even with an id', (
    tester,
  ) async {
    // A deep link from a reply notification also carries a highlight id, but
    // it is not an arrival from a submission. Nothing may be waited for.
    _rest = _LateRowRest(emptyFeedbackReads: 1 << 30, withOlderRow: true);

    await _open(tester, justSubmitted: false, newId: _LateRowRest.kNewId);
    expect(_rest.feedbackReads, 1);

    await _advancePastRetries(tester);

    expect(
      _rest.feedbackReads,
      1,
      reason: 'justSubmitted is what arms the wait; an id alone must not',
    );
  });
}

/// Forwards to whichever [_LateRowRest] the current test installed.
class _RestProxy extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _rest.send(request);
}
