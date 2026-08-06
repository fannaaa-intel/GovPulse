import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/core/widgets/resolve_by_id.dart';

// The contract that makes a detail URL survive a hard refresh:
//
//   • object in hand  → render it, never fetch  (in-session, and MOBILE)
//   • only an id      → fetch it, show progress (the reload case)
//   • id resolves to nothing → say so, don't crash or bounce
//
// These three are what let the router stop REQUIRING an in-memory object, which
// is the whole reason app_router's argRequiredRoutes guard has to bounce those
// routes to the splash today.

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('object in hand renders immediately and never fetches', (
    tester,
  ) async {
    var fetchCalls = 0;

    await tester.pumpWidget(
      _host(
        ResolveById<String>(
          initial: 'from-memory',
          fetch: () async {
            fetchCalls++;
            return 'from-network';
          },
          loadingLabel: 'Loading…',
          notFoundTitle: 'Not found',
          notFoundMessage: 'gone',
          builder: (_, value) => Text(value),
        ),
      ),
    );

    // Rendered on the FIRST frame — no loading flash for in-session navigation.
    expect(find.text('from-memory'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pumpAndSettle();
    expect(
      fetchCalls,
      0,
      reason: 'the fast path must not pay for the reload path — this is also '
          'what keeps the mobile app on its existing object-passing behaviour',
    );
  });

  testWidgets('only an id: shows progress, then the fetched subject', (
    tester,
  ) async {
    final completer = Completer<String?>();

    await tester.pumpWidget(
      _host(
        ResolveById<String>(
          initial: null, // the reload case: the object is gone
          fetch: () => completer.future,
          loadingLabel: 'Loading report…',
          notFoundTitle: 'Report not found',
          notFoundMessage: 'gone',
          builder: (_, value) => Text(value),
        ),
      ),
    );

    // Reconstructing, not bouncing.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Loading report…'), findsOneWidget);

    completer.complete('rebuilt-from-id');
    await tester.pumpAndSettle();

    expect(find.text('rebuilt-from-id'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('unknown id lands on a graceful not-found, not a crash', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ResolveById<String>(
          initial: null,
          fetch: () async => null, // no such row, or RLS hides it
          loadingLabel: 'Loading report…',
          notFoundTitle: 'Report not found',
          notFoundMessage: 'This report may have been removed.',
          builder: (_, value) => Text(value),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Report not found'), findsOneWidget);
    expect(find.text('This report may have been removed.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // NOT COVERED HERE: the failed-fetch / "Try again" branch.
  //
  // FutureBuilder forwards the errors it captures to the framework so they are
  // never silently swallowed, and flutter_test picks those up through the test
  // zone rather than through FlutterError.onError — so a deliberately-failing
  // fetch fails the test no matter how the expected error is filtered. The
  // branch is implemented and reachable (see _Message with onRetry in
  // resolve_by_id.dart); it just needs an integration-level test to assert,
  // which is not worth building for one error panel.
}
