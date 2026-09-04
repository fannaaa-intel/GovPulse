import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The Settings screen builds its rows twice: a web variant (_webAboutSection,
// using AccountRow) and a mobile variant (_buildAboutSection, using _buildTile).
// A row added to only one of them compiles, analyzes and tests clean while being
// invisible on the platform that renders the other — which is exactly what
// happened to "Replay intro": it shipped in the web section and never appeared
// on the phone.
//
// The intro is mobile-only by design: splash_screen.dart guards the whole
// onboarding branch with `if (!kIsWeb)`, so a web visitor never sees the tour
// and has nothing to replay. The row therefore belongs in the mobile section
// and must stay out of the web one.
void main() {
  late String src;
  late String webBody;
  late String mobileBody;

  setUpAll(() {
    src = File(
      'lib/features/home/settings/settings_screen.dart',
    ).readAsStringSync();

    final webStart = src.indexOf('Widget _webAboutSection(');
    final mobileStart = src.indexOf('Widget _buildAboutSection(');
    expect(webStart, greaterThan(-1), reason: '_webAboutSection not found');
    expect(mobileStart, greaterThan(-1), reason: '_buildAboutSection not found');

    // A section body runs until the next "Widget _" declaration.
    String bodyFrom(int start) {
      final next = src.indexOf('\n  Widget _', start + 10);
      return src.substring(start, next == -1 ? src.length : next);
    }

    webBody = bodyFrom(webStart);
    mobileBody = bodyFrom(mobileStart);
  });

  test('the mobile About section has the Replay intro row', () {
    expect(
      mobileBody.contains("title: 'Replay intro'"),
      isTrue,
      reason: 'the mobile About section has no "Replay intro" row — it would '
          'be invisible on every phone',
    );
    expect(
      mobileBody.contains("'/intro'"),
      isTrue,
      reason: 'the mobile row does not push /intro',
    );
    expect(
      mobileBody.contains("arguments: 'replay'"),
      isTrue,
      reason: 'the mobile row must pass the replay argument, or the intro will '
          'sign a logged-in user out on exit',
    );
  });

  test('the web About section does NOT offer it', () {
    // Matches the row itself, not the comment explaining why it is absent.
    expect(
      webBody.contains("title: 'Replay intro'"),
      isFalse,
      reason: 'onboarding is skipped on web (see the !kIsWeb guard in '
          'splash_screen.dart), so a replay row there offers a tour the '
          'visitor was never shown',
    );
    expect(
      webBody.contains("arguments: 'replay'"),
      isFalse,
      reason: 'the web About section still pushes /intro with replay',
    );
  });

  test('onboarding really is mobile-only, which is why the row is too', () {
    final splash = File(
      'lib/features/onboarding/splash_screen.dart',
    ).readAsStringSync();
    expect(
      splash.contains('if (!kIsWeb)'),
      isTrue,
      reason: 'the splash no longer guards onboarding with !kIsWeb — if the '
          'intro now runs on web, the web About section needs the row back',
    );
  });
}
