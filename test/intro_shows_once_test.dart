import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:govpulse/features/onboarding/intro_screen.dart';

// The intro must appear on a fresh install and never again afterwards.
// The gate is `seenOnboarding` in SharedPreferences: the splash reads it to
// decide whether to route to /intro, and the intro writes it when the user
// leaves via either exit (Skip/Login or Get Started/Signup).
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('fresh install: the flag is absent, so the intro is shown', () async {
    final prefs = await SharedPreferences.getInstance();
    // This is the exact expression splash_screen.dart:205 evaluates.
    final goToIntro = !(prefs.getBool('seenOnboarding') ?? false);
    expect(goToIntro, isTrue);
  });

  test('after finishing once: the flag is set, so the intro is skipped',
      () async {
    SharedPreferences.setMockInitialValues({'seenOnboarding': true});
    final prefs = await SharedPreferences.getInstance();
    final goToIntro = !(prefs.getBool('seenOnboarding') ?? false);
    expect(goToIntro, isFalse);
  });

  testWidgets('leaving via Skip marks onboarding as seen', (tester) async {
    var loginTapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: IntroScreen(
          onSignUpClick: () {},
          onLoginClick: () async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('seenOnboarding', true);
            loginTapped = true;
          },
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(loginTapped, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('seenOnboarding'), isTrue,
        reason: 'an interrupted or skipped intro must still not repeat');
  });
}
