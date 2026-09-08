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

      // The frames are cropped to their artwork (commit 21f72fc), so they are
      // no longer the old uniform 500x500 - each is its own size, ~330-390px
      // on the long edge. Assert a sane band rather than an exact size: the
      // point is to catch a frame that is missing, upscaled, or wildly off,
      // not to re-pin a number every crop changes.
      final frame = await codec.getNextFrame();
      expect(frame.image.width, inInclusiveRange(280, 420),
          reason: '$path unexpected width');
      expect(frame.image.height, inInclusiveRange(280, 420),
          reason: '$path unexpected height');

      // The frames are drawn straight onto the #F4F7FB intro page, so the
      // background has to be REAL alpha, not baked-in white. A frame that
      // ships opaque looks like a white card floating on the page - which is
      // exactly the bug this guards, and it is invisible to `flutter
      // analyze`. Sampling the corner is enough: the build crops to the
      // artwork's bounding box, so the corner is always background.
      final bytes = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      expect(bytes, isNotNull, reason: '$path could not be read back');
      expect(bytes!.getUint8(3), 0,
          reason: '$path corner is opaque - the background was not keyed out');
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
