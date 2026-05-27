import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import 'web_constants.dart';
import 'web_responsive.dart'; // fluid()

const List<(IconData, String)> _kDefaultFeatures = [
  (Icons.campaign_outlined, "Report community issues"),
  (Icons.event_outlined, "Discover local events"),
  (Icons.emergency_outlined, "Emergency SOS services"),
  (Icons.chat_bubble_outline_rounded, "Live agent support"),
];

const List<(String, String)> _kDefaultStats = [
  ("50K+", "Citizens"),
  ("24/7", "Support"),
  ("100%", "Secure"),
];

/// The dark animated hero panel shown on the left of wide web layouts.
///
/// [headline] and [subtitle] are required so each screen supplies its own
/// message. The badge, feature list, and stats fall back to sensible defaults.
///
/// RESPONSIVE BEHAVIOUR (the fix):
///   • Content is wrapped in a scroll-safe shell — it can NEVER overflow/clip,
///     no matter how short the inspector window gets; it scrolls if it must.
///   • The headline font eases between 30 → 48 px with the panel width, so it
///     stays comfortable right at the 1000px breakpoint (where the hero is
///     only ~560px wide) instead of being pinned at 50px and cramming.
///   • The feature list and stats progressively hide on short viewports so the
///     headline + subtitle always stay readable.
class WebHeroPanel extends StatelessWidget {
  final AnimationController bgController;
  final String headline;
  final String subtitle;
  final String badgeText;
  final List<(IconData, String)> features;
  final List<(String, String)> stats;

  const WebHeroPanel({
    super.key,
    required this.bgController,
    required this.headline,
    required this.subtitle,
    this.badgeText = "Official Government Portal",
    this.features = _kDefaultFeatures,
    this.stats = _kDefaultStats,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: bgController,
      builder: (context, _) {
        final t = bgController.value;
        return DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [kHeroBgTop, kHeroBgBottom],
            ),
          ),
          child: Stack(
            children: [
              // Subtle brand-colored glow orbs
              Positioned(
                left: -140 + (t * 60),
                top: -90 + (t * 40),
                child: GlowOrb(
                  size: 520,
                  color: AppColors.primaryBlue.withValues(alpha: 0.30),
                ),
              ),
              Positioned(
                right: -90,
                bottom: -120 + (t * 60),
                child: GlowOrb(
                  size: 420,
                  color: AppColors.green.withValues(alpha: 0.14),
                ),
              ),
              Positioned(
                left: 220 + (t * 30),
                top: 300 + (math.sin(t * math.pi) * 20),
                child: GlowOrb(
                  size: 200,
                  color: AppColors.primaryBlue.withValues(alpha: 0.12),
                ),
              ),

              // Faint dot-grid overlay
              Positioned.fill(child: CustomPaint(painter: GridPainter())),

              // Content — responsive + overflow-proof
              Positioned.fill(child: _buildContent(context)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildContent(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final double h = c.maxHeight;
        final double w = c.maxWidth;

        final double pad = h < 640 ? 36 : 64;

        // Headline eases from 28 (cramped breakpoint) up to 48 (wide desktop).
        final double headlineSize = fluid(
          w,
          min: 28,
          max: 48,
          fromW: 520,
          toW: 1400,
        ).clamp(24.0, 48.0);

        // Only show the lower content when there's genuinely room, so short
        // panels (e.g. Nest Hub 1024×600) fit without scrolling OR overflowing.
        final bool showFeatures = h > 740;
        final bool showStats = h > 560;

        // No IntrinsicHeight, no Spacer: a Column with no flex children sizes to
        // its content. ConstrainedBox(minHeight) + mainAxisAlignment.center
        // centers it when the panel is tall, and the SingleChildScrollView
        // scrolls it if it ever exceeds the panel — it can never clip.
        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: h),
            child: Padding(
              padding: EdgeInsets.all(pad),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _badge(),
                  SizedBox(height: h < 640 ? 24 : 40),
                  Text(
                    headline,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.96),
                      fontSize: headlineSize,
                      fontWeight: FontWeight.w800,
                      height: 1.06,
                      letterSpacing: -1.6,
                    ),
                  ),
                  SizedBox(height: h < 640 ? 12 : 20),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.50),
                      fontSize: 15,
                      height: 1.6,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0.1,
                    ),
                  ),
                  if (showFeatures) ...[
                    SizedBox(height: h < 820 ? 32 : 48),
                    ...features.map(_featureRow),
                  ],
                  if (showStats) ...[
                    SizedBox(height: showFeatures ? 24 : 36),
                    Container(
                      height: 0.5,
                      color: Colors.white.withValues(alpha: 0.08),
                      margin: const EdgeInsets.only(bottom: 28),
                    ),
                    Row(
                      children: [
                        for (int i = 0; i < stats.length; i++) ...[
                          if (i > 0) const SizedBox(width: 40),
                          StatItem(value: stats[i].$1, label: stats[i].$2),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _badge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        borderRadius: BorderRadius.circular(100),
        color: Colors.white.withValues(alpha: 0.04),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.green,
              boxShadow: [
                BoxShadow(
                  color: AppColors.green.withValues(alpha: 0.6),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 9),
          Text(
            badgeText,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _featureRow((IconData, String) item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
            ),
            child: Icon(
              item.$1,
              size: 16,
              color: Colors.white.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(width: 14),
          Flexible(
            child: Text(
              item.$2,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.62),
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A soft circular glow used in web hero backgrounds.
class GlowOrb extends StatelessWidget {
  final double size;
  final Color color;
  const GlowOrb({super.key, required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

/// Faint dot-grid overlay for web hero backgrounds.
class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.035)
      ..strokeWidth = 1;
    const spacing = 40.0;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// A value + label stat block (e.g. "50K+" / "Citizens").
class StatItem extends StatelessWidget {
  final String value;
  final String label;
  const StatItem({super.key, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.92),
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.38),
            fontSize: 12,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}
