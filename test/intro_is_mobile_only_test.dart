import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The intro/storyboard is a MOBILE-ONLY flow. Web is getting a landing page
// instead, so nothing on that platform should route to it, render it, or pay
// to download its assets.
//
// There are only three ways to reach the intro. Each is asserted here so a
// later change cannot quietly put it back on web.
void main() {
  String read(String path) => File(path).readAsStringSync();

  test('1. the splash only auto-routes to the intro off web', () {
    final splash = read('lib/features/onboarding/splash_screen.dart');
    final guard = splash.indexOf('if (!kIsWeb)');
    final decision = splash.indexOf("goToIntro = !(prefs.getBool");

    expect(guard, greaterThan(-1),
        reason: 'the !kIsWeb guard around the onboarding branch is gone');
    expect(decision, greaterThan(guard),
        reason: 'goToIntro is now decided outside the !kIsWeb guard, so web '
            'visitors would be sent through onboarding');
  });

  test('2. the splash does not warm storyboard frames on web', () {
    final splash = read('lib/features/onboarding/splash_screen.dart');
    final firstFrame = splash.indexOf('storyboard/all_in_one.webp');
    expect(firstFrame, greaterThan(-1),
        reason: 'the precache no longer references the first intro frame');

    // The nearest preceding !kIsWeb must sit between the precache block's
    // start and the frame, i.e. the frame is inside a web guard.
    final guardBefore = splash.lastIndexOf('if (!kIsWeb)', firstFrame);
    final precacheStart = splash.indexOf('Future<void> _start()');
    expect(
      guardBefore > precacheStart,
      isTrue,
      reason: 'the storyboard precache is not inside a !kIsWeb guard — a web '
          'visitor would download intro frames that platform never shows',
    );
  });

  test('3. only the mobile Settings section links to the intro', () {
    final settings = read('lib/features/home/settings/settings_screen.dart');

    String sectionBody(String decl) {
      final start = settings.indexOf(decl);
      expect(start, greaterThan(-1), reason: '$decl not found');
      final next = settings.indexOf('\n  Widget _', start + 10);
      return settings.substring(start, next == -1 ? settings.length : next);
    }

    expect(
      sectionBody('Widget _buildAboutSection(').contains("'/intro'"),
      isTrue,
      reason: 'the mobile About section lost its Replay intro row',
    );
    expect(
      sectionBody('Widget _webAboutSection(').contains("'/intro'"),
      isFalse,
      reason: 'the web About section routes to the intro again — web is a '
          'landing page now and has no onboarding to replay',
    );
  });
}
