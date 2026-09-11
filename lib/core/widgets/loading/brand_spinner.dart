import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// The GovPulse mark centred in a slowly rotating brand-gradient arc.
///
/// The ring carries the "still working" signal; the logo carries the identity.
/// One implementation on purpose — this is the app's loading language, and it
/// should read the same whether the wait is a sign-out, a cold start, or the
/// HTML splash that `web/index.html` restates in CSS before Flutter has booted.
///
/// Extracted from `logout_confirm_dialog.dart`, which owned it privately while
/// the citizen web shell showed a plain `CircularProgressIndicator` for the
/// same kind of wait — so one cold load could show a bare spinner and then the
/// branded ring seconds later, which reads as two different products.
class BrandSpinner extends StatefulWidget {
  const BrandSpinner({super.key, this.size = 84, this.onDark = true});

  /// Outer diameter of the ring.
  final double size;

  /// Whether this sits on a dark ground.
  ///
  /// Only affects the faint TRACK behind the arc — the gradient arc and the
  /// logo are identical either way. The track exists to keep the ring's circle
  /// readable where the arc isn't, so on the logout overlay's frosted black
  /// barrier it is white at 8%, and on a white page that is invisible: there it
  /// takes [AppColors.stroke], the same hairline the rest of the app uses.
  final bool onDark;

  @override
  State<BrandSpinner> createState() => _BrandSpinnerState();
}

class _BrandSpinnerState extends State<BrandSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final logo = size * 0.69; // white disc sits inside the ring's track
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) => CustomPaint(
                size: Size(size, size),
                painter: _RingPainter(
                  rotation: _c.value * 2 * math.pi,
                  onDark: widget.onDark,
                ),
              ),
            ),
          ),
          ClipOval(
            child: Container(
              width: logo,
              height: logo,
              color: Colors.white,
              padding: EdgeInsets.all(logo * 0.1),
              child: Image.asset(
                'assets/images/applogocrop.webp',
                fit: BoxFit.contain,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A rounded arc sweeping the brand blue→green gradient, rotated by [rotation].
/// A faint full track underneath keeps the ring visible where the arc isn't.
class _RingPainter extends CustomPainter {
  const _RingPainter({required this.rotation, required this.onDark});

  final double rotation;
  final bool onDark;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 4.0;
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = onDark
          ? Colors.white.withValues(alpha: 0.08)
          : AppColors.stroke;
    canvas.drawCircle(center, radius, track);

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(
        colors: [AppColors.primaryBlue, AppColors.green, AppColors.primaryBlue],
      ).createShader(rect);

    // ~70% of the circle, rotating — a clear moving gap reads as progress.
    canvas.drawArc(rect, rotation, math.pi * 1.4, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.rotation != rotation || old.onDark != onDark;
}
