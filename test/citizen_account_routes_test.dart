import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:govpulse/features/home/shell/citizen_shell_router.dart';

// The ACCOUNT rail's five destinations stopped being dialogs and became routes
// under the Settings branch. This pins the parts of that contract which are
// easy to break silently later.
//
// Two halves, deliberately:
//
//  • The path/gate facts come from the REAL [CitizenAccountPage] — they are
//    pure and need neither Supabase nor Riverpod.
//
//  • The nesting behaviour is checked against a router that mirrors the SHAPE
//    of the real tree with trivial builders, exactly as shell_deep_link_test
//    does. The real builders reach for a session; the structure does not, and
//    the structure is what this is about.

GoRouter _mirrorRouter(String initialLocation, List<String> log) {
  const tabs = ['home', 'my-reports', 'emergency', 'settings'];
  return GoRouter(
    initialLocation: initialLocation,
    routes: <RouteBase>[
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => Scaffold(
          appBar: AppBar(title: const Text('SHELL-CHROME')),
          body: navigationShell,
        ),
        branches: <StatefulShellBranch>[
          for (final tab in tabs)
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: '/$tab',
                  builder: (_, _) {
                    log.add('branch:$tab');
                    return Text('BRANCH-$tab');
                  },
                  routes: <RouteBase>[
                    if (tab == 'settings')
                      for (final page in CitizenAccountPage.values)
                        GoRoute(
                          path: page.segment,
                          builder: (_, _) {
                            log.add('account:${page.segment}');
                            return Text('ACCOUNT-${page.segment}');
                          },
                        ),
                  ],
                ),
              ],
            ),
        ],
      ),
    ],
  );
}

void main() {
  group('paths', () {
    test('every account page hangs off the Settings tab', () {
      for (final page in CitizenAccountPage.values) {
        expect(page.path, startsWith('${CitizenTab.settings.path}/'));
        expect(page.path, equals('/settings/${page.segment}'));
      }
    });

    test('segments are unique', () {
      final segments = CitizenAccountPage.values.map((p) => p.segment).toList();
      expect(segments.toSet().length, segments.length);
    });

    test('isCitizenAccountLocation recognises exactly the five', () {
      for (final page in CitizenAccountPage.values) {
        expect(isCitizenAccountLocation(page.path), isTrue, reason: page.name);
      }
      // The tabs themselves are NOT account pages — /settings in particular,
      // which is the branch root these five sit under. If it matched, the right
      // sidebar would stand down on the Settings pane too.
      for (final tab in CitizenTab.values) {
        expect(isCitizenAccountLocation(tab.path), isFalse, reason: tab.name);
      }
      expect(isCitizenAccountLocation('/settings/edit-profile/extra'), isFalse);
      expect(isCitizenAccountLocation('/home'), isFalse);
    });
  });

  group('verification gate', () {
    test('gates exactly Edit Profile and My Submissions', () {
      // Mirrors the mobile Settings page. Contact Support especially must stay
      // open: an unverified citizen struggling to verify needs it most.
      final gated = CitizenAccountPage.values
          .where((p) => p.verifyMessage != null)
          .toSet();
      expect(gated, {
        CitizenAccountPage.editProfile,
        CitizenAccountPage.submissions,
      });
    });
  });

  group('My Submissions deep link', () {
    test('bare path carries no trailing "?"', () {
      final path = shellSubmissionsPath();
      expect(path, CitizenAccountPage.submissions.path);
      // A trailing '?' would leave uri.path intact but is worth pinning: it
      // would show up in the address bar and in every pasted link.
      expect(path, isNot(contains('?')));
      expect(isCitizenAccountLocation(path), isTrue);
    });

    test('tab and highlight ride in the query, not the path', () {
      final uri = Uri.parse(
        shellSubmissionsPath(tab: 2, highlightId: 'abc-123'),
      );
      expect(uri.path, CitizenAccountPage.submissions.path);
      expect(uri.queryParameters['tab'], '2');
      expect(uri.queryParameters['highlight'], 'abc-123');
      // The sidebar stand-down compares uri.path, so a query must not defeat it.
      expect(isCitizenAccountLocation(uri.path), isTrue);
    });

    test('omitted highlight is absent rather than empty', () {
      final uri = Uri.parse(shellSubmissionsPath(tab: 0));
      expect(uri.queryParameters.containsKey('highlight'), isFalse);
      expect(uri.queryParameters['tab'], '0');
    });
  });

  group('routing', () {
    testWidgets('a cold load on an account page builds it inside the shell', (
      tester,
    ) async {
      final log = <String>[];
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: _mirrorRouter('/settings/edit-profile', log),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('SHELL-CHROME'),
        findsOneWidget,
        reason: 'an account page is a pane, not a replacement for the shell',
      );
      expect(find.text('ACCOUNT-edit-profile'), findsOneWidget);
    });

    testWidgets('every account page resolves', (tester) async {
      for (final page in CitizenAccountPage.values) {
        final log = <String>[];
        await tester.pumpWidget(
          MaterialApp.router(routerConfig: _mirrorRouter(page.path, log)),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('ACCOUNT-${page.segment}'),
          findsOneWidget,
          reason: page.path,
        );
      }
    });

    testWidgets('back from an account page returns to /settings', (
      tester,
    ) async {
      final log = <String>[];
      final router = _mirrorRouter('/settings', log);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.text('BRANCH-settings'), findsOneWidget);

      router.go(CitizenAccountPage.submissions.path);
      await tester.pumpAndSettle();
      expect(find.text('ACCOUNT-submissions'), findsOneWidget);

      // What the hosted screens' own back chevrons do — `Navigator.pop` from a
      // context INSIDE the page, which resolves to the branch's navigator, not
      // the root one. That is the whole reason those screens needed no changes
      // to stop being dialogs, so it is the pop worth testing.
      Navigator.of(tester.element(find.text('ACCOUNT-submissions'))).pop();
      await tester.pumpAndSettle();
      expect(find.text('BRANCH-settings'), findsOneWidget);
      expect(find.text('SHELL-CHROME'), findsOneWidget);
    });
  });
}
