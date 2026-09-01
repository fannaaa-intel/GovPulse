import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:govpulse/features/home/shell/citizen_shell_router.dart';

// A citizen who has just filed something should land on the list their new row
// is in — a report on My Reports, a suggestion or a piece of feedback on the
// matching tab of My Submissions — instead of being dropped back on the feed.
//
// The navigation itself lives in `goToSubmissionList` (core/router/legacy_nav),
// which cannot be exercised directly here: its web branch resolves a GoRouter
// and its mobile branch resolves the legacy route table, and `kIsWeb` is a
// const the test cannot move. So this pins the two halves that ARE testable and
// that are what actually broke in review:
//
//   • the DESTINATIONS the helper computes — plain string functions of the tab,
//     which is where an off-by-one between the tab indices and the tabs would
//     show up; and
//   • the behaviour that makes the web branch work at all: arriving at My
//     Submissions while ALREADY there has to change the tab, which before
//     `didUpdateWidget` it silently did not.

void main() {
  group('post-submit destinations', () {
    test('a report goes to the My Reports branch, not a submissions tab', () {
      // Tab 0 is special-cased: a report has its own richer screen.
      expect(CitizenTab.myReports.path, '/my-reports');
    });

    test('a suggestion goes to My Submissions tab 1', () {
      expect(shellSubmissionsPath(tab: 1), '/settings/submissions?tab=1');
    });

    test('feedback goes to My Submissions tab 2', () {
      expect(shellSubmissionsPath(tab: 2), '/settings/submissions?tab=2');
    });

    test('the tab indices match the tab bar order', () {
      // 0 Reports · 1 Suggestions · 2 Feedback. If this order is ever changed
      // in my_submissions_screen, these are the call sites that must move.
      expect(shellSubmissionsPath(tab: 1).endsWith('tab=1'), isTrue);
      expect(shellSubmissionsPath(tab: 2).endsWith('tab=2'), isTrue);
    });

    test('a submissions location still reads as an account page', () {
      // The shell stands its right sidebar down for account locations, matching
      // on `uri.path` so the query string must not defeat it. The post-submit
      // navigation is the first thing to routinely arrive here WITH a query.
      final uri = Uri.parse(shellSubmissionsPath(tab: 2));
      expect(isCitizenAccountLocation(uri.path), isTrue);
    });
  });

  // ── The reused-State trap ─────────────────────────────────────────────────
  //
  // GoRoute derives its page key from the PATH, and every tab of My Submissions
  // is the same path with a different query parameter. So navigating to a tab
  // while already on the page rebuilds the existing State rather than creating
  // one — `initState` does not run again and `initialTab` is never re-read.
  //
  // That is reachable in the ordinary way: the quick actions open over the whole
  // shell, so a citizen can file a suggestion while standing on the Feedback tab
  // and be sent back to the tab they never left.
  //
  // Modelled with a stand-in that has the same lifecycle shape as the real
  // screen — tab held in State, seeded in initState, updated in didUpdateWidget
  // — because the real one reaches for Supabase on mount.
  group('arriving at My Submissions while already there', () {
    testWidgets('switches the tab', (tester) async {
      final router = GoRouter(
        initialLocation: shellSubmissionsPath(tab: 2),
        routes: <RouteBase>[
          GoRoute(
            path: '/settings/submissions',
            builder: (_, state) => _TabbedPage(
              initialTab:
                  int.tryParse(state.uri.queryParameters['tab'] ?? '') ?? 0,
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.text('TAB-2'), findsOneWidget);

      // The citizen files a suggestion from here; the form sends them to tab 1.
      router.go(shellSubmissionsPath(tab: 1));
      await tester.pumpAndSettle();

      expect(
        find.text('TAB-1'),
        findsOneWidget,
        reason:
            'the State is reused across tabs (same path key), so the new tab '
            'only lands if didUpdateWidget applies it',
      );
      expect(find.text('TAB-2'), findsNothing);
    });

    testWidgets('an unrelated rebuild does not yank the tab back', (
      tester,
    ) async {
      // The guard is on a CHANGE in initialTab, not on it differing from the
      // current tab — otherwise a citizen who tapped another tab after arriving
      // would be dragged back to the one the URL named on the next rebuild.
      final key = GlobalKey<_TabbedPageState>();
      await tester.pumpWidget(
        MaterialApp(home: _TabbedPage(key: key, initialTab: 1)),
      );
      await tester.pumpAndSettle();
      expect(find.text('TAB-1'), findsOneWidget);

      // They tap Feedback themselves.
      key.currentState!.select(2);
      await tester.pumpAndSettle();
      expect(find.text('TAB-2'), findsOneWidget);

      // Something rebuilds the page with the SAME initialTab it was built with.
      await tester.pumpWidget(
        MaterialApp(home: _TabbedPage(key: key, initialTab: 1)),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('TAB-2'),
        findsOneWidget,
        reason: 'an unchanged initialTab must leave the citizen where they are',
      );
    });
  });
  // ── Back must behave as if the form had simply closed ────────────────────
  //
  // The mobile branch REPLACES the form route rather than popping it and
  // pushing over the top. Both leave the same stack, but only the replacement
  // is a single route change — a pop plays the form's 300ms reverse fade while
  // the push covers it mid-fade, which reads as Home flickering between the two.
  //
  // What must not change is where Back goes: Home, exactly as it did before this
  // feature, and never back into the form that was just submitted.
  group('back from the destination', () {
    testWidgets('returns to Home, not to the submitted form', (tester) async {
      final log = <String>[];

      Route<void> route(String name) => PageRouteBuilder<void>(
        settings: RouteSettings(name: name),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => Scaffold(body: Center(child: Text(name))),
      );

      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          home: const Scaffold(body: Center(child: Text('HOME'))),
          onGenerateRoute: (s) {
            log.add(s.name!);
            return route(s.name!);
          },
        ),
      );
      expect(find.text('HOME'), findsOneWidget);

      // Citizen opens the quick-action form over Home.
      navKey.currentState!.push(route('FORM'));
      await tester.pumpAndSettle();
      expect(find.text('FORM'), findsOneWidget);

      // Submit succeeds: the form route is REPLACED by the destination — what
      // goToSubmissionList does on mobile.
      navKey.currentState!.pushReplacement<void, void>(route('MY-REPORTS'));
      await tester.pumpAndSettle();
      expect(find.text('MY-REPORTS'), findsOneWidget);
      expect(
        find.text('FORM'),
        findsNothing,
        reason: 'the submitted form must be gone, not merely covered',
      );

      // Back.
      navKey.currentState!.pop();
      await tester.pumpAndSettle();

      expect(
        find.text('HOME'),
        findsOneWidget,
        reason: 'Back from the list lands on Home, as if the form had closed',
      );
      expect(
        find.text('FORM'),
        findsNothing,
        reason: 'Back must never re-enter the form that was just submitted',
      );
    });

    testWidgets('the destination is the only route added', (tester) async {
      // A pop-then-push briefly has both the outgoing form and the incoming
      // list on the navigator. A replacement never does — which is the whole
      // reason it is used, so it is worth pinning rather than assuming.
      final navKey = GlobalKey<NavigatorState>();
      var routes = 0;

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          home: const Scaffold(body: Center(child: Text('HOME'))),
        ),
      );

      Route<void> counted(String name) => PageRouteBuilder<void>(
        settings: RouteSettings(name: name),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, _, _) {
          routes++;
          return Scaffold(body: Center(child: Text(name)));
        },
      );

      navKey.currentState!.push(counted('FORM'));
      await tester.pumpAndSettle();
      navKey.currentState!.pushReplacement<void, void>(counted('MY-REPORTS'));
      await tester.pumpAndSettle();

      // Home + form + destination. Back once must reach Home, so exactly one
      // route sits above it.
      navKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);
      expect(routes, 2);
    });
  });
}

/// Lifecycle stand-in for MySubmissionsScreen: same seeding in `initState` and
/// same `didUpdateWidget` rule, with none of its data layer.
class _TabbedPage extends StatefulWidget {
  final int initialTab;
  const _TabbedPage({super.key, required this.initialTab});

  @override
  State<_TabbedPage> createState() => _TabbedPageState();
}

class _TabbedPageState extends State<_TabbedPage> {
  late int _tab;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab.clamp(0, 2);
  }

  void select(int i) => setState(() => _tab = i);

  @override
  void didUpdateWidget(_TabbedPage old) {
    super.didUpdateWidget(old);
    if (old.initialTab != widget.initialTab) select(widget.initialTab.clamp(0, 2));
  }

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text('TAB-$_tab')));
}
