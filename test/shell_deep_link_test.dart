import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// Diagnostic for the cold-load (F5) path on a detail URL.
//
// Mirrors the SHAPE of citizen_shell_router's route tree — a '/' route, a
// StatefulShellRoute.indexedStack, absolute branch paths, and a relative detail
// child — with trivial builders, so this isolates "does the route tree resolve a
// deep link into the shell" from anything Supabase or Riverpod does at runtime.
//
// If this passes, the structure is fine and a blank cold load is a runtime
// failure inside the real builders. If it fails, the structure is the bug.
//
// The shell lives at the citizen entry point now, so tabs are bare paths:
// '/home', '/my-reports', …. '/' is no longer a redirect route — where it goes
// depends on auth, which the router's top-level redirect decides — so here it
// just builds the startup placeholder the real tree builds.

final _tabs = ['home', 'my-reports', 'emergency', 'settings'];

GoRouter _buildRouter(String initialLocation, List<String> log) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (_, _) {
          log.add('starting');
          return const Text('STARTING');
        },
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          log.add('shell');
          return Scaffold(
            appBar: AppBar(title: const Text('SHELL-CHROME')),
            body: navigationShell,
          );
        },
        branches: <StatefulShellBranch>[
          for (final tab in _tabs)
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: '/$tab',
                  builder: (_, _) {
                    log.add('branch:$tab');
                    return Text('BRANCH-$tab');
                  },
                  routes: <RouteBase>[
                    if (tab == 'my-reports')
                      GoRoute(
                        path: 'detail/:reportId',
                        builder: (_, state) {
                          final id = state.pathParameters['reportId']!;
                          log.add('detail:$id');
                          return Text('DETAIL-$id');
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
  testWidgets('cold load on a branch ROOT builds the shell', (tester) async {
    final log = <String>[];
    await tester.pumpWidget(
      MaterialApp.router(routerConfig: _buildRouter('/my-reports', log)),
    );
    await tester.pumpAndSettle();

    expect(find.text('SHELL-CHROME'), findsOneWidget);
    expect(log, contains('shell'));
  });

  testWidgets(
    'cold load DEEP on a detail child builds the shell AND the detail',
    (tester) async {
      final log = <String>[];
      const id = '3f2a9c10-8b4d-4e77-9a21-c5e0d1b7f480';

      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: _buildRouter('/my-reports/detail/$id', log),
        ),
      );
      await tester.pumpAndSettle();

      // The whole shell must rebuild on a cold deep link, not just the detail.
      expect(
        find.text('SHELL-CHROME'),
        findsOneWidget,
        reason: 'a deep-linked detail must build INSIDE the shell',
      );
      expect(find.text('DETAIL-$id'), findsOneWidget);
      expect(log, contains('shell'));
      expect(log, contains('detail:$id'));
    },
  );

  testWidgets('bare / builds the startup placeholder, not the shell', (
    tester,
  ) async {
    final log = <String>[];
    await tester.pumpWidget(
      MaterialApp.router(routerConfig: _buildRouter('/', log)),
    );
    await tester.pumpAndSettle();

    // '/' is a holding view, not a destination: the real router's top-level
    // redirect sends it to /home or /login once auth is known. Mounting the
    // shell here would defeat the guard.
    expect(find.text('STARTING'), findsOneWidget);
    expect(find.text('SHELL-CHROME'), findsNothing);
    expect(log, contains('starting'));
  });

  testWidgets('a tab path resolves to its own branch', (tester) async {
    final log = <String>[];
    await tester.pumpWidget(
      MaterialApp.router(routerConfig: _buildRouter('/emergency', log)),
    );
    await tester.pumpAndSettle();

    expect(find.text('SHELL-CHROME'), findsOneWidget);
    expect(find.text('BRANCH-emergency'), findsOneWidget);
  });
}
