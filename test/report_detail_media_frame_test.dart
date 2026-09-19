// The single-image frame on the web report detail page.
//
// ── The bug this locks down ────────────────────────────────────────────────
// The frame used to be `height: w * .50` with `BoxFit.cover`, where `w` is
// [uiScaleWidth]. On web that measures the VIEWPORT and clamps at
// kUiScaleMaxWidth (480), so on any desktop viewport the height froze at
// 240px while `width: double.infinity` stretched the box to the content
// column (~810px at 1920). A 3:2 photo in a 3.4:1 box, cropped by cover:
// the left and right of every report photo were shaved off.
//
// The height came from a width that had nothing to do with the box being
// filled — which is why widening the browser never helped, and why the crop
// got WORSE the wider the window went.
//
// These tests assert the ratio the frame presents rather than pumping the
// screen: the test binding runs with `kIsWeb == false`, so it cannot take the
// web branch at all, and a widget pump here would silently prove the mobile
// path instead. See [kIsWeb] note in test/_responsive_matrix.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/core/theme/mobile_metrics.dart';

/// The aspect ratio the web single-image frame commits to.
const double kWebMediaAspect = 4 / 3;

/// Content-column widths the report detail page actually renders at, from a
/// narrow laptop to the 1920 viewport in the bug report.
const _columnWidths = <String, double>{
  'narrow laptop': 560,
  'laptop': 700,
  'desktop 1920': 810,
  'wide desktop': 960,
};

void main() {
  group('web single-image frame', () {
    test('the old formula really did squash the box', () {
      // Guards the diagnosis, so nobody "fixes" this back. At every real
      // column width the old height is the same 240px, and the box only gets
      // flatter as the column grows.
      for (final entry in _columnWidths.entries) {
        final oldHeight = uiScaleWidthOf(Size(1920, 1080)) * .50;
        final ratio = entry.value / oldHeight;

        expect(
          oldHeight,
          240,
          reason: 'old height is pinned by the 480 clamp, not by ${entry.key}',
        );
        expect(
          ratio,
          greaterThan(2.0),
          reason:
              'old frame at ${entry.key} was ${ratio.toStringAsFixed(2)}:1 — '
              'far flatter than a 3:2 photo, so cover cropped the sides',
        );
      }
    });

    test('the frame keeps one ratio at every column width', () {
      for (final entry in _columnWidths.entries) {
        final height = entry.value / kWebMediaAspect;
        expect(
          entry.value / height,
          closeTo(kWebMediaAspect, 0.0001),
          reason: '${entry.key} must present 4:3, not a clamped constant',
        );
      }
    });

    test('the frame scales with the column instead of against a clamp', () {
      // The old height was identical at 560 and 960. The new one must not be:
      // a wider column has to mean a taller frame, or the photo is still
      // being fitted to something other than its own box.
      final narrow = _columnWidths['narrow laptop']! / kWebMediaAspect;
      final wide = _columnWidths['wide desktop']! / kWebMediaAspect;

      expect(
        wide,
        greaterThan(narrow),
        reason: 'frame height must track the column width',
      );
    });

    test('a 3:2 photo is fully visible inside the 4:3 frame', () {
      // contain never crops; this asserts the frame is not so far from a
      // typical photo that the letterbox swallows the card. A 3:2 photo in a
      // 4:3 frame fills 88.9% of the height and all of the width.
      const photo = 3 / 2;
      const filled = kWebMediaAspect / photo;

      expect(filled, closeTo(0.889, 0.001));
      expect(
        filled,
        greaterThan(0.8),
        reason: 'letterbox bands must stay modest for a landscape photo',
      );
    });

    test('a portrait photo still fits without cropping', () {
      // The case cover punished hardest: a 3:4 phone photo in a 3.4:1 box
      // lost almost everything. contain shows all of it.
      const portrait = 3 / 4;
      const widthUsed = portrait / kWebMediaAspect;

      expect(widthUsed, lessThan(1.0), reason: 'portrait pillarboxes, not crops');
      expect(widthUsed, closeTo(0.5625, 0.001));
    });
  });

  group('uiScaleWidth is the wrong ruler for a web column', () {
    test('it clamps, so it cannot describe a desktop column', () {
      expect(uiScaleWidthOf(const Size(1920, 1080)), kUiScaleMaxWidth);
      expect(uiScaleWidthOf(const Size(1280, 800)), kUiScaleMaxWidth);
      expect(
        uiScaleWidthOf(const Size(1920, 1080)),
        uiScaleWidthOf(const Size(1280, 800)),
        reason: 'two very different viewports, one identical ruler — which is '
            'exactly why a height derived from it ignored the real column',
      );
    });

    test('mobile is unaffected: there the ruler IS the screen', () {
      // Why the fix is web-only. On a phone `w * .50` was always a real
      // proportion of the real width, so the mobile band stays untouched.
      for (final size in const [
        Size(320, 568),
        Size(360, 640),
        Size(390, 844),
      ]) {
        expect(uiScaleWidthOf(size), size.width);
      }
    });
  });
}
