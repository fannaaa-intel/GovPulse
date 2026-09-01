// Where a citizen lands after a submission succeeds.
//
// Filing something used to just dismiss the form, dropping the citizen back on
// the feed with no sign of what they had just done. Now the three quick actions
// send them to the list their new row is in: a report to My Reports, a
// suggestion or a piece of feedback to the matching tab of My Submissions.
//
// This drives the REAL `goToSubmissionList` through the REAL legacy route table
// and mounts the REAL destinations, so a renamed route, a changed argument
// shape or a lost tab fails here rather than in a citizen's hands.
//
// `kIsWeb` is a compile-time false in the VM, so what runs is the MOBILE branch
// — which is the half that does the route surgery, and therefore the half where
// the back stack and the transition can break. The web branch is a `go` into
// the shell and is covered structurally in post_submit_destination_test.
//
// Supabase is faked at the two seams `Supabase.initialize` exposes, the same
// trick my_reports_filter_stability_test and tool/preview_my_reports_web use —
// without it the destinations throw as they build and nothing can be asserted.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:govpulse/core/router/app_router.dart' show onGenerateRoute;
import 'package:govpulse/core/router/legacy_nav.dart';
import 'package:govpulse/features/home/my_report/my_reports_screen.dart'
    show MyReportsScreen;
import 'package:govpulse/features/home/settings/my-submission/my_submissions_screen.dart'
    show MySubmissionsScreen;

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
  Future<void> persistSession(String persistSessionString) async {}
}

/// Every table answers with an empty list. The destinations are checked for
/// IDENTITY here, not for what they list — an empty list still mounts the
/// screen, which is all these assertions need.
class _FakeRest extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream.value(utf8.encode('[]')),
      200,
      headers: const {'content-type': 'application/json; charset=utf-8'},
      request: request,
    );
  }
}

/// Hosts the helper the way a quick-action form does: a route pushed over Home
/// that calls `goToSubmissionList` when its submission succeeds.
class _FakeForm extends StatelessWidget {
  final int tab;
  const _FakeForm({required this.tab});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ElevatedButton(
        onPressed: () =>
            goToSubmissionList(context, tab: tab, username: 'juan'),
        child: const Text('SUBMIT'),
      ),
    ),
  );
}

/// Counts what sits above Home, so "the form was REPLACED" is checkable as a
/// depth rather than inferred from what happens to be on screen.
class _StackObserver extends NavigatorObserver {
  final List<Route<dynamic>> stack = [];

  // '/' is MaterialApp's own `home`, standing in for the feed the citizen
  // opened the form from. It is the floor, not part of what the helper does.
  bool _isHome(Route<dynamic> r) => r.settings.name == '/';

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previous) {
    if (!_isHome(route)) stack.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previous) =>
      stack.remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previous) =>
      stack.remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) stack.remove(oldRoute);
    if (newRoute != null && !_isHome(newRoute)) stack.add(newRoute);
  }
}

Future<(_StackObserver, GlobalKey<NavigatorState>)> _submit(
  WidgetTester tester,
  int tab,
) async {
  final observer = _StackObserver();
  final navKey = GlobalKey<NavigatorState>();

  // A phone viewport: this is the MOBILE arm (`kIsWeb` is false in the VM), and
  // the default 800x600 test window is a size no handset has. Same thing
  // my_reports_filter_stability_test does. Tall so nothing has to scroll to be
  // found. Both destinations are held to every supported phone width by
  // submission_lists_fit_every_phone_test.
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    // My Reports is a Consumer — identity comes from userProfileProvider.
    ProviderScope(
      child: MaterialApp(
        navigatorKey: navKey,
        navigatorObservers: [observer],
        // The REAL table, so the destinations resolve exactly as in the app.
        // Note the helper does not come through here — `pushLegacy` resolves
        // names against app_router's resolver directly, which is what makes a
        // legacy name work under either router — so this serves the test's own
        // pushes and guarantees the same resolver is in play.
        onGenerateRoute: onGenerateRoute,
        home: const Scaffold(body: Center(child: Text('HOME'))),
      ),
    ),
  );

  navKey.currentState!.push(
    MaterialPageRoute<void>(builder: (_) => _FakeForm(tab: tab)),
  );
  await tester.pumpAndSettle();
  expect(find.text('SUBMIT'), findsOneWidget);
  expect(observer.stack, hasLength(1), reason: 'the form is above Home');

  await tester.tap(find.text('SUBMIT'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));

  return (observer, navKey);
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

  group('a submitted form is replaced by its destination', () {
    testWidgets('a report goes to My Reports', (tester) async {
      final (observer, _) = await _submit(tester, 0);

      expect(find.byType(MyReportsScreen), findsOneWidget);
      expect(
        observer.stack,
        hasLength(1),
        reason:
            'the destination REPLACED the form — one route above Home, not two',
      );
      expect(
        find.text('SUBMIT'),
        findsNothing,
        reason: 'the submitted form must be gone, not merely covered',
      );
    });

    testWidgets('a suggestion goes to My Submissions, Suggestions tab', (
      tester,
    ) async {
      final (observer, _) = await _submit(tester, 1);

      final screen = tester.widget<MySubmissionsScreen>(
        find.byType(MySubmissionsScreen),
      );
      expect(screen.initialTab, 1);
      expect(screen.username, 'juan');
      expect(observer.stack, hasLength(1));
      expect(find.text('SUBMIT'), findsNothing);
    });

    testWidgets('feedback goes to My Submissions, Feedback tab', (
      tester,
    ) async {
      final (observer, _) = await _submit(tester, 2);

      final screen = tester.widget<MySubmissionsScreen>(
        find.byType(MySubmissionsScreen),
      );
      expect(
        screen.initialTab,
        2,
        reason:
            'landing a citizen on a list that is right but showing the wrong '
            'tab is the failure that is hardest to notice',
      );
      expect(observer.stack, hasLength(1));
      expect(find.text('SUBMIT'), findsNothing);
    });
  });

  group('back from the destination', () {
    testWidgets('one Back reaches Home, never the submitted form', (
      tester,
    ) async {
      final (observer, navKey) = await _submit(tester, 1);
      expect(find.byType(MySubmissionsScreen), findsOneWidget);

      // One pop must be enough. A pop-then-push would have left the form on the
      // stack and needed two — landing the citizen back inside a form they had
      // already submitted.
      navKey.currentState!.pop();
      await tester.pumpAndSettle();

      expect(
        observer.stack,
        isEmpty,
        reason: 'nothing above Home is left after one Back',
      );
      expect(find.text('HOME'), findsOneWidget);
      expect(
        find.text('SUBMIT'),
        findsNothing,
        reason: 'Back must never re-enter the submitted form',
      );
    });

    testWidgets('the same holds for a report', (tester) async {
      final (observer, navKey) = await _submit(tester, 0);

      navKey.currentState!.pop();
      await tester.pumpAndSettle();

      expect(observer.stack, isEmpty);
      expect(find.text('HOME'), findsOneWidget);
      expect(find.text('SUBMIT'), findsNothing);
    });
  });

  group('the transition', () {
    testWidgets('is ONE route change, not a pop followed by a push', (
      tester,
    ) async {
      // The reason the helper replaces rather than pops-then-pushes. A pop plays
      // the form route's 300ms reverse fade while the push covers it mid-fade,
      // and Home shows through the gap — seen as a flicker between the form and
      // the list. A replacement cannot produce one: the destination is in place
      // before the form route comes down.
      final observer = _StackObserver();
      final navKey = GlobalKey<NavigatorState>();

      tester.view.physicalSize = const Size(390, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            navigatorKey: navKey,
            navigatorObservers: [observer],
            onGenerateRoute: onGenerateRoute,
            home: const Scaffold(body: Center(child: Text('HOME'))),
          ),
        ),
      );

      navKey.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const _FakeForm(tab: 1)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('SUBMIT'));

      // Sampled ACROSS the hand-over, well past the form route's own 300ms
      // reverse duration — which is where a flash would live.
      final depths = <int>[];
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 40));
        depths.add(observer.stack.length);
      }

      expect(
        depths,
        everyElement(1),
        reason:
            'exactly one route sits above Home for the whole hand-over: never '
            'two (form and list both up — a pop-then-push) and never zero '
            '(Home showing through — the flicker)',
      );
    });

    testWidgets('the destination animates its own content in', (tester) async {
      // The app's convention (see `_instant` / `_slideUp` in app_router) is an
      // instant route swap with the SCREEN animating its own content, so there
      // is no double-slide. My Submissions does that with `_slideCtrl`.
      await _submit(tester, 2);

      expect(
        find.descendant(
          of: find.byType(MySubmissionsScreen),
          matching: find.byType(SlideTransition),
        ),
        findsWidgets,
        reason: 'the content slides up on arrival rather than hard-cutting',
      );
      expect(
        find.descendant(
          of: find.byType(MySubmissionsScreen),
          matching: find.byType(FadeTransition),
        ),
        findsWidgets,
      );
    });
  });
}
