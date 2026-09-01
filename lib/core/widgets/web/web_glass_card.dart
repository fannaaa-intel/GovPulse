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
Widget bleedOrCentre(bool bleed, Widget scroll) =>
    bleed ? _BleedFill(child: scroll) : Center(child: scroll);

/// Fills the viewport, and CENTRES a short form inside it.
///
/// Two things have to be true at once and they pull against each other:
///
///   * A short form — "Reset password" is a field and two buttons — must sit
///     in the middle of the screen. Left at the top it reads as a page that
///     failed to finish loading, with a third of the screen empty beneath it.
///   * A tall form — sign up, or any form with the keyboard open — must still
///     scroll from its top, never centred into a position that pushes its
///     first field off the top of the screen.
///
/// [child] is the caller's own scroll view, so this adds NO second Scrollable:
/// it stretches to the viewport and hands the scroll view a `Center`-ing
/// alignment to use once its content is shorter than the space available.
/// Nesting another scrollable here would give the page two competing scroll
/// positions on the one axis.
class _BleedFill extends StatelessWidget {
  final Widget child;
  const _BleedFill({required this.child});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        // Measured HERE because here is the last place it is knowable. This
        // sits outside the caller's scroll view, so its incoming maxHeight is
        // the space genuinely available — the keyboard already subtracted by
        // the Scaffold above, and the SafeArea's padding with it. One level
        // down, inside the scroll view, that number is gone: a scroll view
        // hands its child an unbounded height by definition.
        //
        // See [_VisibleHeight] for what reads it and why nothing else can
        // work it out on its own.
        builder: (context, constraints) => _VisibleHeight(
          height: constraints.maxHeight,
          child: SizedBox(
            width: double.infinity,
            height: double.infinity,
            child: child,
          ),
        ),
      );
}

/// The height actually visible to the user, published for descendants that are
/// inside a scroll view and therefore cannot measure it themselves.
///
/// Exists for one reason: a full-bleed [WebGlassCard] must fill the screen when
/// the keyboard is down, and must NOT keep demanding the full screen when the
/// keyboard is up — or it lays its own submit button out underneath the
/// keyboard. Neither MediaQuery nor its own constraints can tell it which case
/// it is in (see the long note in WebGlassCard's full-bleed branch), so the
/// number is passed down from the one widget that does know.
///
/// Null when there is no [_BleedFill] ancestor, which is the honest answer:
/// the card then falls back to the screen height it always used.
class _VisibleHeight extends InheritedWidget {
  final double height;
  const _VisibleHeight({required this.height, required super.child});

  static double? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_VisibleHeight>()
      ?.height;

  @override
  bool updateShouldNotify(_VisibleHeight old) => old.height != height;
}

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
      //
      // The surface filling is only half of it: the CONTENT then has to be
      // centred in the space that filling created. "Reset password" is a field
      // and two buttons; pinned to the top of a 904px phone screen it reads as
      // a page that failed to finish loading, with two-thirds of the screen
      // empty beneath it. Center inside the min-height box puts it in the
      // middle, and does nothing at all once the form is taller than the
      // screen — at which point the caller's scroll view takes over from its
      // top, so a long form never has its first field pushed off the screen.
      // ── The height asked for is the VISIBLE height, not the screen ──────
      //
      // This read `MediaQuery.sizeOf(context).height`, which is the whole
      // screen and does NOT shrink when the keyboard opens. So on an 800px
      // phone with a 320px keyboard the card went on demanding 800px inside a
      // viewport that was now 480px tall, and the `alignment: Alignment.center`
      // below centred the form in that oversized box. The bottom third of the
      // card — the part holding the submit button — was laid out underneath the
      // keyboard, and what the citizen saw was a band of blank card gradient
      // where the button should have been. It was scrollable, but only by the
      // few pixels that did not help, so it read as broken rather than tall.
      //
      // ── Why not viewInsets, and why not LayoutBuilder ─────────────────────
      // Both obvious fixes fail here, which is worth writing down because both
      // look right:
      //
      //   * Subtracting `MediaQuery.viewInsets.bottom` does nothing. Scaffold
      //     with resizeToAvoidBottomInset shrinks the body by the keyboard and
      //     ZEROES the inset it passes down, but leaves MediaQuery.size at the
      //     full screen height. Inside the body the pair is (800, 0), so the
      //     subtraction gives back 800 — the number that caused the bug.
      //
      //   * Reading the incoming constraints does nothing either. The caller's
      //     SingleChildScrollView hands its child an UNBOUNDED maxHeight, so a
      //     LayoutBuilder here measures Infinity, not the 480 that exists one
      //     level up outside the scroll view.
      //
      // The real height is known at [_BleedFill], which is outside the scroll
      // view and IS given the shrunken constraint. It publishes it through
      // [_VisibleHeight] so this card can read it without either of the above
      // guesses. When there is no such ancestor — a caller that mounts this
      // card without bleedOrCentre — the screen height stays the fallback,
      // which is exactly the old behaviour.
      final double available =
          _VisibleHeight.of(context) ?? MediaQuery.sizeOf(context).height;

      return ConstrainedBox(
        constraints: BoxConstraints(
          // Never negative: a keyboard taller than its viewport is not a real
          // configuration, but a negative minHeight throws and clamping costs
          // nothing.
          minHeight: available < 0 ? 0 : available,
        ),
        child: Container(
          width: double.infinity,
          alignment: Alignment.center,
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
