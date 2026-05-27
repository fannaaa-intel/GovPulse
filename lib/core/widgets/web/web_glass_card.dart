// lib/core/widgets/web/web_glass_card.dart
//
// Glassmorphism surfaces for the WEB auth flow ONLY (login / signup / phone).
// Simple + recognizable: calm tinted backdrop, clearly-frosted card with sheen.
//
//   • WebGlassSurface — soft tinted backdrop with two gentle glows behind the
//     card, giving the frost + rim something to read against.
//   • WebGlassCard     — frosted card. Shadow OUTSIDE the clip (so it lifts),
//     directional sheen fill (the key "glass" tell), bright rim.
//
// Tuning dials (change intensity only, don't add elements):
//   • glow alphas (0.16 / 0.12) → how colourful the backdrop reads
//   • fill alphas (0.60 / 0.42) → see-through vs solid
//   • blur sigma  (24)          → frost strength
//
// Mobile never imports this — used only inside each screen's `kIsWeb` branch.
//
// WIRING (one line, in web.dart barrel):
//     export 'web_glass_card.dart';

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// Soft radial glow with true alpha falloff (no hard circle edges).
class _SoftOrb extends StatelessWidget {
  final double size;
  final Color color;
  const _SoftOrb({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
      ),
    );
  }
}

/// Calm tinted backdrop. Soft tonal gradient + two gentle glows positioned so
/// they sit partly behind the card — enough colour for the frost to register,
/// not so much that it looks busy.
/// Fills its parent; pass the form/card as [child].
class WebGlassSurface extends StatelessWidget {
  final Widget child;
  const WebGlassSurface({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Soft blue-grey tonal base — a touch more colour than pure neutral.
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFEDF1FA), Color(0xFFD8E2F2)],
              ),
            ),
          ),
        ),

        // Primary glow — upper area, partly behind the card.
        Positioned(
          top: -80,
          left: 40,
          right: 40,
          child: Center(
            child: _SoftOrb(
              size: 480,
              color: AppColors.primaryBlue.withValues(alpha: 0.16),
            ),
          ),
        ),

        // Secondary glow — lower, soft accent.
        Positioned(
          bottom: -100,
          right: -40,
          child: _SoftOrb(
            size: 300,
            color: AppColors.green.withValues(alpha: 0.12),
          ),
        ),

        Positioned.fill(child: child),
      ],
    );
  }
}

/// Frosted glass card (no BackdropFilter → transition-safe, never pops).
/// Translucent gradient fill + bright rim reads as glass on the calm surface.
class WebGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  const WebGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(34, 40, 34, 40),
    this.radius = 24,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        // Slightly higher alpha than the blurred version, since there's no
        // blur softening the surface behind — keeps it reading as frosted.
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.78),
            Colors.white.withValues(alpha: 0.62),
          ],
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.80),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.10),
            blurRadius: 50,
            spreadRadius: -12,
            offset: const Offset(0, 24),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}
