// Dev-only: SEE the mobile-web ID-scan zoom bug, and see it fixed.
//
//   flutter run -d chrome -t tool/preview_scan_zoom.dart
//
// The bug is a geometry bug, so a camera is not needed to show it - what
// matters is how a source of known size is laid out. This renders a stand-in
// "video" (a numbered grid, so any crop or stretch is obvious) at the size a
// mobile browser reports for its camera track, through BOTH the old and the
// new arrangement, inside a phone-sized viewport.
//
// Why a preview target and not a screenshot test: the failure is "the picture
// is too big to use", which a passing widget test cannot tell you. Looking is
// the verification.
import 'package:flutter/material.dart';

/// The production rule, restated: on web the camera track is already in the
/// orientation the user is holding, so it is used exactly as reported. Mirrored
/// here rather than imported because `previewSourceSize` is
/// `@visibleForTesting` and tool/ is not a test.
Size previewSourceSizeWeb(Size track) => track;

/// What a mobile browser reports for its rear camera track, held upright.
const Size kWebTrack = Size(1080, 1920);

/// A phone viewport, in logical pixels.
const Size kViewport = Size(390, 780);

void main() => runApp(const _App());

class _App extends StatelessWidget {
  const _App();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFEEEEEE),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Wrap(
              spacing: 40,
              runSpacing: 24,
              alignment: WrapAlignment.center,
              children: [
                _Case(
                  title: 'BEFORE - transposed on web',
                  note: 'SizedBox(w: previewSize.height, h: previewSize.width)',
                  source: Size(kWebTrack.height, kWebTrack.width),
                ),
                _Case(
                  title: 'AFTER - previewSourceSize(isWeb: true)',
                  note: 'track reported as-is, already portrait',
                  source: previewSourceSizeWeb(kWebTrack),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One phone-sized viewport with the stand-in video laid out inside it.
class _Case extends StatelessWidget {
  final String title;
  final String note;
  final Size source;

  const _Case({
    required this.title,
    required this.note,
    required this.source,
  });

  @override
  Widget build(BuildContext context) {
    // What fraction of the source actually lands inside the viewport.
    final scale = (kViewport.width / source.width) > (kViewport.height / source.height)
        ? kViewport.width / source.width
        : kViewport.height / source.height;
    final renderedW = source.width * scale;
    final visible = (kViewport.width / renderedW).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: kViewport.width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                note,
                style: const TextStyle(fontSize: 11, color: Colors.black54),
              ),
              Text(
                'source ${source.width.toInt()}x${source.height.toInt()}  '
                '- ${(visible * 100).toStringAsFixed(0)}% of width visible',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: visible > 0.9 ? Colors.green.shade800 : Colors.red.shade700,
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
        // The phone viewport, and inside it the exact arrangement the screen
        // uses: SizedBox.expand > FittedBox(cover) > SizedBox(source).
        Container(
          width: kViewport.width,
          height: kViewport.height,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.black, width: 2),
            color: Colors.black,
          ),
          child: ClipRect(
            child: Stack(
              children: [
                SizedBox.expand(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: source.width,
                      height: source.height,
                      child: const _StandInVideo(),
                    ),
                  ),
                ),
                // The ID frame the user is asked to line the card up inside,
                // at the screen's real 320x200.
                Center(
                  child: Container(
                    width: 320,
                    height: 200,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.yellow, width: 3),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A stand-in for the camera image: a grid with a card-shaped target on it.
///
/// Anything that crops shows as missing grid; anything that stretches shows as
/// non-square cells and an out-of-shape card.
class _StandInVideo extends StatelessWidget {
  const _StandInVideo();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _GridPainter(), child: const SizedBox.expand());
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF1B3A5C),
    );

    // 120px grid in SOURCE pixels: square cells, so a stretch is visible.
    final line = Paint()
      ..color = Colors.white24
      ..strokeWidth = 2;
    for (double x = 0; x <= size.width; x += 120) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (double y = 0; y <= size.height; y += 120) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }

    // A CR80 card at the centre, the thing the user is trying to frame.
    const cardW = 640.0;
    final cardH = cardW / 1.586;
    final card = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: cardW,
      height: cardH,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(card, const Radius.circular(24)),
      Paint()..color = const Color(0xFFF2C14E),
    );

    // Edge markers, so it is obvious when the frame's edges are off-screen.
    final edge = Paint()..color = Colors.redAccent;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 24), edge);
    canvas.drawRect(
      Rect.fromLTWH(0, size.height - 24, size.width, 24),
      edge,
    );
    canvas.drawRect(Rect.fromLTWH(0, 0, 24, size.height), edge);
    canvas.drawRect(
      Rect.fromLTWH(size.width - 24, 0, 24, size.height),
      edge,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
