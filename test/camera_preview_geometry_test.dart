// The camera preview geometry behind the "uncontrollable zoom" on mobile web.
//
// `kIsWeb` is a compile-time false under `flutter test`, so the web branch can
// never be reached by pumping the screen - which is exactly how the bug shipped.
// [previewSourceSize] takes `isWeb` as an ARGUMENT for that reason: it makes the
// web geometry a pure function this suite can evaluate directly.
//
// The second group pins the layout rule that made the whole class of bug
// possible - a tight constraint silently defeats `CameraPreview`'s internal
// `AspectRatio` - so that if Flutter ever changes it, the screens that now
// depend on it fail here rather than in someone's hands.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/profileVerification/verification_scan_screen.dart';

/// The scale `BoxFit.cover` applies fitting [src] into [dst].
double _coverScale(Size src, Size dst) {
  final byWidth = dst.width / src.width;
  final byHeight = dst.height / src.height;
  return byWidth > byHeight ? byWidth : byHeight;
}

void main() {
  // A phone held upright, in a mobile browser: the video track is reported
  // PORTRAIT, because the track is what the screen is showing.
  const webTrack = Size(1080, 1920);
  // The same phone in the native app: a LANDSCAPE sensor buffer regardless of
  // how the device is held.
  const mobileBuffer = Size(1920, 1080);
  const viewport = Size(390, 780);

  group('previewSourceSize', () {
    test('web keeps the track orientation as reported', () {
      expect(previewSourceSize(webTrack, isWeb: true), webTrack);
    });

    test('mobile transposes the landscape sensor buffer to portrait', () {
      expect(
        previewSourceSize(mobileBuffer, isWeb: false),
        const Size(1080, 1920),
      );
    });

    test('web preview is portrait, so cover barely scales it', () {
      final src = previewSourceSize(webTrack, isWeb: true);
      expect(src.width < src.height, isTrue, reason: 'must stay portrait');

      // 1080x1920 is TALLER than 390x780 in proportion, so cover is decided by
      // the height ratio and the small overflow is horizontal.
      final scale = _coverScale(src, viewport);
      expect(scale, closeTo(780 / 1920, 0.0001));

      // The point of the fix: the frame now fills the viewport with only a
      // modest crop, instead of overflowing it several times over.
      expect(src.height * scale, closeTo(viewport.height, 0.5));
      expect(src.width * scale, greaterThanOrEqualTo(viewport.width));
      expect(src.width * scale, lessThan(viewport.width * 1.2));
    });

    test('the old double-transpose over-zoomed the web preview by ~1.8x', () {
      // What the screen used to build on web: previewSize transposed, giving a
      // LANDSCAPE box that cover then had to blow up to fill a tall viewport.
      final broken = Size(webTrack.height, webTrack.width);
      final brokenScale = _coverScale(broken, viewport);
      final fixedScale = _coverScale(
        previewSourceSize(webTrack, isWeb: true),
        viewport,
      );

      expect(brokenScale / fixedScale, closeTo(1920 / 1080, 0.001));

      // Concretely: a 1920x1080 box covering 390x780 renders 1386 wide into a
      // 390-wide window, so only ~28% of the frame was ever visible.
      final renderedWidth = broken.width * brokenScale;
      expect(renderedWidth, closeTo(1386.7, 0.5));
      expect(viewport.width / renderedWidth, closeTo(0.281, 0.005));
    });

    test('mobile geometry is unchanged by the fix', () {
      // The mobile arm must still produce what the original transpose did,
      // or a fix for web would have regressed every phone.
      final src = previewSourceSize(mobileBuffer, isWeb: false);
      expect(src, Size(mobileBuffer.height, mobileBuffer.width));
      expect(_coverScale(src, viewport), closeTo(780 / 1920, 0.0001));
    });
  });

  group('layout rule this depends on', () {
    testWidgets('a tight SizedBox overrides a child AspectRatio', (
      tester,
    ) async {
      final child = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 240,
              height: 330,
              // What CameraPreview builds for a portrait-locked screen given a
              // portrait web track: the WRONG, transposed 16:9.
              child: AspectRatio(
                aspectRatio: 1080 / 1920,
                child: Container(key: child, color: const Color(0xFF000000)),
              ),
            ),
          ),
        ),
      );

      // The ratio is not honoured - it cannot be, against a tight constraint.
      // This is why the fix works by sizing the box, and equally why the
      // face-scan oval was stretching its preview before _coverPreview.
      expect(tester.getSize(find.byKey(child)), const Size(240, 330));
    });

    testWidgets('FittedBox(cover) over a sized child restores the ratio', (
      tester,
    ) async {
      final inner = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 240,
              height: 330,
              child: FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: webTrack.width,
                  height: webTrack.height,
                  child: Container(
                    key: inner,
                    color: const Color(0xFF000000),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // The child keeps its own 1080x1920 shape; FittedBox scales it uniformly,
      // so nothing is stretched - only cropped, which is what cover means.
      expect(tester.getSize(find.byKey(inner)), webTrack);
    });
  });
}
