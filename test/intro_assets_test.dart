import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Verifies every intro frame is (a) declared in the pubspec so it loads at
// runtime, and (b) a real animated image the engine can actually decode.
// `flutter analyze` cannot catch a missing or corrupt asset; this can.
void main() {
  const frames = <String>[
    'assets/images/storyboard/all_in_one.webp',
    'assets/images/storyboard/report.webp',
    'assets/images/storyboard/feedback.webp',
    'assets/images/storyboard/news_events.webp',
    'assets/images/storyboard/kuya_gov.webp',
    'assets/images/storyboard/emergency_call.webp',
  ];

  test('every intro frame is bundled and decodes as an animation', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final path in frames) {
      final ByteData data = await rootBundle.load(path);
      expect(data.lengthInBytes, greaterThan(0), reason: '$path is empty');

      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
      );
      expect(codec.frameCount, greaterThan(1),
          reason: '$path decoded as a still image, not an animation');

      final frame = await codec.getNextFrame();
      expect(frame.image.width, 500, reason: '$path unexpected width');
      expect(frame.image.height, 500, reason: '$path unexpected height');
    }
  });

  test('the superseded onboarding GIFs are gone from the bundle', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final old in const [
      'assets/images/onboard1.gif',
      'assets/images/onboard2.gif',
      'assets/images/onboard3.gif',
    ]) {
      await expectLater(() => rootBundle.load(old), throwsA(anything));
    }
  });
}
