import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The Settings screen builds its rows twice: a web variant (_webAboutSection,
// using AccountRow) and a mobile variant (_buildAboutSection, using _buildTile).
// A row added to only one of them compiles, analyzes and tests clean while being
// invisible on the platform that renders the other — which is exactly what
// happened to "Replay intro": it shipped in the web section and never appeared
// on the phone.
void main() {
  test('Replay intro is wired into both the web and mobile About sections', () {
    final src = File(
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

    final sections = {
      'web': bodyFrom(webStart),
      'mobile': bodyFrom(mobileStart),
    };

    for (final entry in sections.entries) {
      expect(
        entry.value.contains("title: 'Replay intro'"),
        isTrue,
        reason: 'the ${entry.key} About section has no "Replay intro" row',
      );
      expect(
        entry.value.contains("'/intro'"),
        isTrue,
        reason: 'the ${entry.key} row does not push /intro',
      );
      expect(
        entry.value.contains("arguments: 'replay'"),
        isTrue,
        reason: 'the ${entry.key} row must pass the replay argument, or the '
            'intro will sign a logged-in user out on exit',
      );
    }
  });
}
