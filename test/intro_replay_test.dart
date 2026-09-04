import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:govpulse/core/router/app_router.dart';

// Replaying the intro from Settings must return to Settings.
//
// The first-launch exits replace the route with /login or /signup, which is
// correct before anyone is signed in. Reusing that path for replay would throw
// a signed-in citizen out of their own account, so the route takes a 'replay'
// argument and pops instead.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpAppAt(WidgetTester tester, Widget home) async {
    await tester.pumpWidget(
      MaterialApp(onGenerateRoute: onGenerateRoute, home: home),
    );
  }

  testWidgets('replay pops back and never lands on /login', (tester) async {
    await pumpAppAt(
      tester,
      Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () =>
                  Navigator.of(ctx).pushNamed('/intro', arguments: 'replay'),
              child: const Text('SETTINGS-MARKER'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('SETTINGS-MARKER'), findsOneWidget);

    await tester.tap(find.text('SETTINGS-MARKER'));
    await tester.pumpAndSettle();

    // The intro is up: the caller's screen is gone.
    expect(find.text('SETTINGS-MARKER'), findsNothing);
    expect(find.text('Skip'), findsOneWidget);

    // Leave via Skip, which on first launch would replace with /login.
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    // Back where we started, still inside the account.
    expect(
      find.text('SETTINGS-MARKER'),
      findsOneWidget,
      reason: 'replay did not return to the calling screen',
    );

    // And the flag stays set, so the intro does not reappear on next launch.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('seenOnboarding'), isTrue);
  });

  testWidgets('first launch (no argument) does NOT pop back', (tester) async {
    await pumpAppAt(
      tester,
      Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(ctx).pushNamed('/intro'),
              child: const Text('SPLASH-MARKER'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('SPLASH-MARKER'));
    await tester.pumpAndSettle();
    expect(find.text('Skip'), findsOneWidget);

    await tester.tap(find.text('Skip'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Without the 'replay' argument the exit replaces the route with /login,
    // so the caller must NOT come back. (/login itself needs Supabase, which a
    // widget test has no way to stand up, so this asserts only that the pop
    // path was not taken — which is the behaviour the replay flag switches.)
    tester.takeException();
    expect(
      find.text('SPLASH-MARKER'),
      findsNothing,
      reason: 'first-launch exit must replace, not pop',
    );
  });
}
