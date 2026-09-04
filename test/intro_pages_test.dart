import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/onboarding/intro_screen.dart';

void main() {
  testWidgets('intro renders six pages and the first frame', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: IntroScreen(onSignUpClick: () {}, onLoginClick: () {}),
      ),
    );
    await tester.pump();

    final images = tester
        .widgetList<Image>(find.byType(Image))
        .map((i) => i.image)
        .whereType<AssetImage>()
        .map((a) => a.assetName)
        .toList();

    // The first storyboard frame is on screen, and nothing points at the
    // deleted GIFs.
    expect(
      images.any((n) => n.contains('storyboard/all_in_one.webp')),
      isTrue,
      reason: 'first intro frame not rendered; got $images',
    );
    expect(images.any((n) => n.contains('onboard')), isFalse);

    // Six dots in the page indicator => six pages.
    final state = tester.state(find.byType(IntroScreen)) as dynamic;
    expect(state.pages.length, 6);
  });
}
