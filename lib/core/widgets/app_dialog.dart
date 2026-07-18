import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

// ════════════════════════════════════════════════════════════════════════════
//  App dialog route — how every pop-up in GovPulse comes and goes.
//
//  Flutter's showDialog fades over 150ms, straight-curved, in and out. That is
//  tuned for a small AlertDialog; on the cards this app actually uses — a report
//  detail, an event form, a reason picker — it reads as the pop-up blinking out
//  of existence rather than closing. It is worst exactly where it matters most:
//  when the close is the RESULT of something you just did (rejecting a report,
//  saving an event), the thing you were reading vanishes with nothing tying its
//  disappearance to your tap.
//
//  [showAppDialog] is a drop-in replacement for showDialog with the same
//  signature. Prefer it everywhere; a plain showDialog is a pop-up that leaves
//  differently from every other pop-up.
//
//  WEB vs APP: this governs anything presented as a floating dialog, which is
//  every pop-up on web/desktop and most of them in the app. Full-screen routes
//  (the admin detail on a phone, sub-screens) are NOT dialogs and animate as
//  pages — see AdminDetailScaffold, whose fade-out is deliberately matched to
//  [kAppDialogDuration] so a detail leaves at the same speed either way.
// ════════════════════════════════════════════════════════════════════════════

/// Long enough to read as a movement rather than a cut, short enough that a
/// second tap never has to wait on it. Shared with the full-screen routes so
/// the app and the web console feel the same.
const Duration kAppDialogDuration = Duration(milliseconds: 220);

/// How hard the page behind a pop-up frosts over. Matched to the citizen
/// notification popup (the reference the rest of the app follows): enough that
/// the surroundings clearly recede behind the card, not so much that context is
/// lost. Ramped by the route's own animation so the blur grows on the way in
/// and melts away on the way out — never a hard on/off.
const double kAppDialogBlurSigma = 7;

/// A full-screen blur whose strength tracks [animation] (0 → none, 1 → full).
/// Sits *behind* a pop-up so everything painted earlier — the page and the
/// barrier tint — is frosted. At the animation's resting ends it drops the
/// filter entirely, so there's no idle blur layer (and no zero-sigma saveLayer)
/// once the dialog is fully gone.
class _AnimatedBlurBackdrop extends StatelessWidget {
  final Animation<double> animation;
  final double sigma;
  final Widget child;
  const _AnimatedBlurBackdrop({
    required this.animation,
    required this.sigma,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        // Same easing as the card so blur and scale move together.
        final v = Curves.easeOutCubic.transform(
          animation.value.clamp(0.0, 1.0),
        );
        if (v <= 0.001) return child!;
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: sigma * v, sigmaY: sigma * v),
          child: child,
        );
      },
      child: child,
    );
  }
}

/// Wraps [child] so the same receding, frosted backdrop as [showAppDialog] sits
/// behind it — for pop-ups presented with a hand-rolled [showGeneralDialog]
/// (dropdown panels, command palettes) instead of the shared dialog route.
///
/// Drop it around the widget a `transitionBuilder` returns; the blur ramps with
/// that route's [animation] and fills the screen behind the panel, on top of
/// whatever `barrierColor` the panel already sets.
Widget withDialogBlur(
  Animation<double> animation,
  Widget child, {
  double sigma = kAppDialogBlurSigma,
}) {
  return Stack(
    children: [
      Positioned.fill(
        child: _AnimatedBlurBackdrop(
          animation: animation,
          sigma: sigma,
          // A transparent filler gives the BackdropFilter its full-screen size
          // without painting anything itself — the barrier tint shows through.
          child: const SizedBox.expand(),
        ),
      ),
      child,
    ],
  );
}

/// The shared open/close animation: a fade, plus a slight scale so the card
/// settles in and recedes out and the eye has something to follow.
Widget buildAppDialogTransition(Animation<double> animation, Widget child) {
  final curved = CurvedAnimation(
    parent: animation,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  return FadeTransition(
    opacity: curved,
    child: ScaleTransition(
      scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
      child: child,
    ),
  );
}

/// [DialogRoute] with GovPulse's transition. Push this directly only when you
/// need the route object; otherwise call [showAppDialog].
class AppDialogRoute<T> extends DialogRoute<T> {
  AppDialogRoute({
    required super.context,
    required super.builder,
    super.themes,
    super.barrierColor = Colors.black54,
    super.barrierDismissible,
    super.barrierLabel,
    super.useSafeArea,
    super.settings,
    super.anchorPoint,
    super.traversalEdgeBehavior,
  });

  @override
  Duration get transitionDuration => kAppDialogDuration;

  // Frost the page behind the card. Wrapping the stock barrier keeps its
  // tap-to-dismiss and semantics intact; the blur ramps with the route's
  // animation, so it grows as the card arrives and clears as it leaves.
  @override
  Widget buildModalBarrier() {
    final barrier = super.buildModalBarrier();
    final anim = animation;
    if (anim == null) return barrier;
    return _AnimatedBlurBackdrop(
      animation: anim,
      sigma: kAppDialogBlurSigma,
      child: barrier,
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => buildAppDialogTransition(animation, child);
}

/// Drop-in for `showDialog`, with GovPulse's open/close animation.
///
/// Mirrors showDialog's own body — including the [InheritedTheme.capture], which
/// is what carries a theme wrapping the page across to the overlay. Skipping it
/// is the classic way a hand-pushed dialog ends up unthemed.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor = Colors.black54,
  String? barrierLabel,
  bool useSafeArea = true,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  Offset? anchorPoint,
  TraversalEdgeBehavior? traversalEdgeBehavior,
}) {
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  return navigator.push<T>(
    AppDialogRoute<T>(
      context: context,
      builder: builder,
      barrierColor: barrierColor,
      barrierDismissible: barrierDismissible,
      barrierLabel:
          barrierLabel ??
          MaterialLocalizations.of(context).modalBarrierDismissLabel,
      useSafeArea: useSafeArea,
      settings: routeSettings,
      anchorPoint: anchorPoint,
      traversalEdgeBehavior: traversalEdgeBehavior,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
    ),
  );
}
