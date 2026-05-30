import 'dart:math' as math;
import 'package:flutter/material.dart';

class HomeHeroBand extends StatelessWidget {
  final double height;
  const HomeHeroBand({super.key, this.height = 90});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0A1628),
              Color(0xFF0D2352),
              Color(0xFF10337A),
              Color(0xFF1147A8),
            ],
            stops: [0.0, 0.30, 0.65, 1.0],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Subtle dot-grid overlay ───────────────────────────────
            CustomPaint(painter: _DotGridPainter()),
            // ── Accent shimmer lines ──────────────────────────────────
            CustomPaint(painter: _ShimmerPainter()),
            // ── Bottom gradient fade into page ───────────────────────
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                height: height * 0.55,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xFFF0F4FF)],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Dot grid pattern ──────────────────────────────────────────────────────────
class _DotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.07)
      ..style = PaintingStyle.fill;

    const spacing = 22.0;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.0, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

// ── Diagonal shimmer lines ────────────────────────────────────────────────────
class _ShimmerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    // Two soft glowing diagonals
    const angles = [0.22, 0.68]; // relative X positions
    for (final pos in angles) {
      final x = size.width * pos;
      linePaint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withOpacity(0.0),
          Colors.white.withOpacity(0.13),
          Colors.white.withOpacity(0.0),
        ],
      ).createShader(Rect.fromLTWH(x - 1, 0, 2, size.height));
      canvas.drawLine(
        Offset(x - size.height * 0.15, 0),
        Offset(x + size.height * 0.15, size.height),
        linePaint,
      );
    }

    // Faint arc top-left
    final arcPaint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..strokeWidth = 60
      ..style = PaintingStyle.stroke;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(-40, -20), radius: 200),
      0,
      math.pi / 2,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(_) => false;
}
