// Layout invariants for the admin console's remote images.
//
// Coverage note: SkeletonNetworkImage is backed by CachedNetworkImage, whose
// cache manager can't do real I/O under flutter_test — so its *loaded* and
// *error* branches can't be reached here without injecting a fake cache
// manager, which would mean widening the widget's API purely for tests. What is
// covered is the part that actually broke: the placeholder, and the sizing rule
// that a wrapped image silently loses.

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/admin/widgets/admin_skeleton.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(
        body: Center(child: SizedBox(width: 88, height: 88, child: child)),
      ),
    );

/// Serves a decoded image of a fixed size, so a test can check how a real
/// (non-square) photo is laid out.
class _FakeImage extends ImageProvider<_FakeImage> {
  final int width;
  final int height;
  _FakeImage({required this.width, required this.height});

  @override
  Future<_FakeImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_FakeImage>(this);

  @override
  ImageStreamCompleter loadImage(_FakeImage key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(_frame());

  Future<ImageInfo> _frame() async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = const Color(0xFF00FF00),
    );
    final image = await recorder.endRecording().toImage(width, height);
    return ImageInfo(image: image);
  }
}

void main() {
  testWidgets('shimmers in the photo\'s own box while it loads',
      (tester) async {
    await tester.pumpWidget(
      _host(const SkeletonNetworkImage(url: 'https://127.0.0.1:1/slow.png')),
    );
    await tester.pump();

    // The placeholder occupies the full tile, so the real photo landing can't
    // reflow anything around it.
    expect(find.byType(AdminShimmer), findsOneWidget);
    expect(tester.getSize(find.byType(AdminShimmer)), const Size(88, 88));
  });

  // Regression: a hand-rolled fade used to wrap the image in a LOOSE stack,
  // which stopped it being told to fill its box. It fell back to preserving its
  // aspect ratio, so a portrait photo rendered ~29x88 inside an 88x88 tile and
  // left the tile showing beside it. The rule this pins: `fit` only does its job
  // when the image itself receives the parent's tight constraints.
  testWidgets('a portrait photo fills its square box, never letterboxes',
      (tester) async {
    await tester.pumpWidget(
      _host(
        Image(
          image: _FakeImage(width: 40, height: 120), // tall and narrow
          fit: BoxFit.cover,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(RawImage)), const Size(88, 88));
  });

  testWidgets('wrapping an image in a loose stack is what breaks the fill',
      (tester) async {
    await tester.pumpWidget(
      _host(
        Stack(
          // The default AnimatedSwitcher layout. Loose, so the image is no
          // longer told to fill — this is the shape of the original bug.
          children: [
            Image(
              image: _FakeImage(width: 40, height: 120),
              fit: BoxFit.cover,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byType(RawImage)).width,
      lessThan(88),
      reason: 'a loose stack should reproduce the letterboxing',
    );
  });
}
