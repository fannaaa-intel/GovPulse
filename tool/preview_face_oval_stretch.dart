// Dev-only: SEE the face-scan oval preview stretch, and see it fixed.
//
//   flutter run -d chrome -t tool/preview_face_oval_stretch.dart
//
// The web face-scan oval is a FIXED 168x228 box (see `_webPreview`), so this
// case is identical on a phone browser and a desktop one - which is the whole
// question this harness answers. The mobile-native oval is bigger but has the
// same 1 : 1.36 shape, so it is shown too.
//
// A bare `CameraPreview` inside a tight SizedBox has its internal AspectRatio
// IGNORED (a tight constraint cannot be violated), so the stream was drawn at
// the oval's 0.735 instead of its native 0.562. That is the stretch. The face
// below is drawn from perfect CIRCLES: anything that is not round is the bug.
import 'package:flutter/material.dart';

/// A portrait camera track, as a mobile browser reports it.
const Size kTrack = Size(1080, 1920);

void main() => runApp(const _App());

class _App extends StatelessWidget {
  const _App();

  @override
  Widget build(BuildContext context) {
    // The two oval sizes the app actually uses.
    const web = Size(168, 168 * 1.36);
    final mobile = Size(390 * 0.62, 390 * 0.62 * 1.36);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFEEEEEE),
        body: Center(
          child: Wrap(
            spacing: 48,
            runSpacing: 32,
            alignment: WrapAlignment.center,
            children: [
              _Case(
                title: 'WEB oval - BEFORE',
                note: 'bare CameraPreview in a tight 168x228 box',
                box: web,
                stretched: true,
              ),
              _Case(
                title: 'WEB oval - AFTER',
                note: '_coverPreview(168, 228)',
                box: web,
                stretched: false,
              ),
              _Case(
                title: 'MOBILE oval - BEFORE',
                note: 'bare CameraPreview in a tight box',
                box: mobile,
                stretched: true,
              ),
              _Case(
                title: 'MOBILE oval - AFTER',
                note: '_coverPreview(ovalW, ovalH)',
                box: mobile,
                stretched: false,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Case extends StatelessWidget {
  final String title;
  final String note;
  final Size box;
  final bool stretched;

  const _Case({
    required this.title,
    required this.note,
    required this.box,
    required this.stretched,
  });

  @override
  Widget build(BuildContext context) {
    // BEFORE: the tight box wins and the source is squashed to fit it.
    // AFTER: FittedBox(cover) scales the source uniformly, then crops.
    final Widget inner = stretched
        ? const _StandInFace()
        : FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: kTrack.width,
              height: kTrack.height,
              child: const _StandInFace(),
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: box.width + 40,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              Text(
                note,
                style: const TextStyle(fontSize: 10, color: Colors.black54),
              ),
              Text(
                stretched ? 'drawn at 0.735 (STRETCHED)' : 'native 0.562 kept',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: stretched ? Colors.red.shade700 : Colors.green.shade800,
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.white,
          child: SizedBox(
            width: box.width,
            height: box.height,
            child: ClipOval(child: inner),
          ),
        ),
      ],
    );
  }
}

/// A face built from perfect circles, so any stretch is unmistakable.
class _StandInFace extends StatelessWidget {
  const _StandInFace();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _FacePainter(), child: const SizedBox.expand());
  }
}

class _FacePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF1B3A5C),
    );

    final cx = size.width / 2;
    final cy = size.height / 2;
    // Radius from the SHORT side, so the head is a circle in source space.
    final r = (size.width < size.height ? size.width : size.height) * 0.30;

    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()..color = const Color(0xFFF2C14E),
    );
    final eye = Paint()..color = const Color(0xFF1B3A5C);
    canvas.drawCircle(Offset(cx - r * 0.35, cy - r * 0.25), r * 0.12, eye);
    canvas.drawCircle(Offset(cx + r * 0.35, cy - r * 0.25), r * 0.12, eye);
    canvas.drawCircle(Offset(cx, cy + r * 0.30), r * 0.16, eye);

    // A reference circle at the edge: round means correct, oval means stretched.
    canvas.drawCircle(
      Offset(cx, cy),
      r * 1.55,
      Paint()
        ..color = Colors.white70
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
