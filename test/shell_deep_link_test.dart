import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// Diagnostic for the cold-load (F5) path on a detail URL.
//
// Mirrors the SHAPE of citizen_shell_router's route tree — a redirect route, a
// StatefulShellRoute.indexedStack, absolute branch paths, and a relative detail
// child — with trivial builders, so this isolates "does the route tree resolve a
// deep link into the shell" from anything Supabase or Riverpod does at runtime.
//
// If this passes, the structure is fine and a blank cold load is a runtime
// failure inside the real builders. If it fails, the structure is the bug.

const prefix = '/shell-preview';

final _tabs = ['home', 'my-reports', 'emergency', 'settings'];

GoRouter _buildRouter(String initialLocation, List<String> log) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: <RouteBase>[
      GoRoute(path: prefix, redirect: (_, _) => '$prefix/home'),
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
                  path: '$prefix/$tab',
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
      MaterialApp.router(routerConfig: _buildRouter('$prefix/my-reports', log)),
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
          routerConfig: _buildRouter('$prefix/my-reports/detail/$id', log),
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

  testWidgets('bare prefix redirects into the shell', (tester) async {
    final log = <String>[];
    await tester.pumpWidget(
      MaterialApp.router(routerConfig: _buildRouter(prefix, log)),
    );
    await tester.pumpAndSettle();

    expect(find.text('SHELL-CHROME'), findsOneWidget);
    expect(find.text('BRANCH-home'), findsOneWidget);
  });
}
