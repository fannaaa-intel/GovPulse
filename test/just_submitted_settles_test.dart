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
  _LateRowRest({required this.emptyFeedbackReads});

  final int emptyFeedbackReads;

  /// Selects against `feedbacks`, counted so a test can prove the screen
  /// retried rather than gave up — and that it STOPPED retrying.
  int feedbackReads = 0;

  static const _row = {
    'id': 'ffffffff-0000-4000-8000-000000000001',
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
      if (feedbackReads > emptyFeedbackReads) body = jsonEncode([_row]);
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

Future<void> _open(WidgetTester tester, {required bool justSubmitted}) async {
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
Future<void> _advancePastRetries(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
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
      lessThanOrEqualTo(6),
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
}

/// Forwards to whichever [_LateRowRest] the current test installed.
class _RestProxy extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _rest.send(request);
}
