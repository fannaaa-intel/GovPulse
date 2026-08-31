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

/// Viewport width below which an auth screen stops being a card on a page and
/// becomes the page itself.
///
/// Every auth screen is ONE form on an otherwise empty backdrop, so on a phone
/// browser the card is a frame drawn around content that already fills the
/// screen: a rim, a 24px gutter and 40px of card padding, all spent on a 390px
/// viewport before the first field starts. The form is the page there.
///
/// 600 matches the threshold login already used to pick its own gutter, and
/// sits well under the 1000 where the two-panel hero layout begins, so the
/// desktop and split layouts are untouched.
const double kAuthFullBleedBelow = 600;

/// Whether [context]'s viewport should draw auth screens edge to edge.
bool authIsFullBleed(BuildContext context) =>
    MediaQuery.sizeOf(context).width < kAuthFullBleedBelow;

/// Stretch [scroll] to fill when [bleed], otherwise centre it.
///
/// A full-bleed page must NOT be vertically centred: [Center] pins the scroll
/// child to its own height, so the white surface stops where the form stops and
/// the backdrop shows through above and below — which reads as a very wide card
/// rather than as a page. Only the card layout wants centring.
Widget bleedOrCentre(bool bleed, Widget scroll) => bleed
    ? SizedBox(width: double.infinity, height: double.infinity, child: scroll)
    : Center(child: scroll);

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

  /// Force the card shape on regardless of width.
  ///
  /// For the rare surface that is genuinely a card ON something rather than a
  /// page of its own. Nothing in the auth flow passes it today.
  final bool alwaysCard;

  const WebGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(34, 40, 34, 40),
    this.radius = 24,
    this.alwaysCard = false,
  });

  @override
  Widget build(BuildContext context) {
    // ── Below kAuthFullBleedBelow the card IS the page ────────────────────
    //
    // No rim, no radius, no shadow, and the horizontal padding drops to a
    // reading margin rather than a card inset. The gradient stays, because the
    // backdrop behind it (WebGlassSurface) keeps its glows either way and a
    // transparent form over them is unreadable.
    //
    // Decided HERE rather than at each call site: eight screens mount this
    // widget — login, signup, the Facebook username step, guest, and the four
    // reset steps through WebAuthCard — and a per-screen flag would be seven
    // chances to forget one.
    if (!alwaysCard && authIsFullBleed(context)) {
      final EdgeInsets p = padding.resolve(Directionality.of(context));
      // minHeight, so a short form still paints its surface to the bottom of
      // the viewport. Without it the white stops under the last button and the
      // backdrop's glows show through beneath — which is the seam that makes a
      // full-bleed page read as a very wide card after all.
      return ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: MediaQuery.sizeOf(context).height,
        ),
        child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(20, p.top, 20, p.bottom),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0.78),
              Colors.white.withValues(alpha: 0.62),
            ],
          ),
        ),
        child: child,
        ),
      );
    }

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
