import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Shared skeleton-loading primitives for the admin console.
///
/// Every admin surface that fetches data shows a shaped placeholder while the
/// request is in flight instead of a bare spinner, so the layout doesn't jump
/// once data lands. Wrap a group of [SkeletonBox] / [SkeletonCircle] shapes in
/// a single [AdminShimmer] — one animation controller drives a light band that
/// sweeps across the whole group, keeping the effect consistent everywhere.

/// Base fill for skeleton shapes — reads as a placeholder on white cards.
const Color kSkeletonBase = Color(0xFFE7EBF1);

/// The moving highlight swept across the base by [AdminShimmer].
const Color kSkeletonHighlight = Color(0xFFF5F7FB);

// ── WHY THIS IS NOT A ShaderMask ────────────────────────────────────────────
//
// It was, until 2026-08-31. `ShaderMask(blendMode: BlendMode.srcATop)` wrapped
// the whole group and swept a gradient across it. On paper that only tints
// pixels the child already painted — the skeleton shapes — and leaves the gaps
// between them alone.
//
// In the WEB renderer it does not. The mask composites against everything
// already on the canvas within its bounds, so any opaque surface BEHIND the
// group is tinted too. Wrap a group of placeholders in a white card and the
// card's own fill is repainted skeleton-grey, at which point the shapes are the
// same colour as the space between them and the card renders as one solid slab.
// Not a subtle degradation: the skeleton disappears completely.
//
// Every admin surface that puts placeholders on a card was affected. It went
// unnoticed because a skeleton is visible for a few hundred milliseconds, and
// because nothing but looking at a screenshot can catch it — the analyzer, the
// widget tests and the layout are all perfectly happy.
//
// So the sweep now travels with each SHAPE instead. AdminShimmer supplies a
// clock (via an InheritedWidget) and paints nothing at all; SkeletonBox and
// SkeletonCircle read it and animate their own gradient fill. Nothing behind
// them is touched, on any renderer. The public API is unchanged.

/// Broadcasts the shimmer clock to the [SkeletonBox] / [SkeletonCircle] shapes
/// beneath it, so one controller drives a whole group and their sweeps stay in
/// step.
class _ShimmerClock extends InheritedWidget {
  final double t; // 0..1
  const _ShimmerClock({required this.t, required super.child});

  static double? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_ShimmerClock>()
      ?.t;

  @override
  bool updateShouldNotify(_ShimmerClock old) => old.t != t;
}

class AdminShimmer extends StatefulWidget {
  final Widget child;

  /// When false the child renders without the animated sweep (still shaped),
  /// handy for tests / reduced-motion.
  final bool enabled;

  const AdminShimmer({super.key, required this.child, this.enabled = true});

  @override
  State<AdminShimmer> createState() => _AdminShimmerState();
}

class _AdminShimmerState extends State<AdminShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1250),
    );
    if (widget.enabled) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant AdminShimmer old) {
    super.didUpdateWidget(old);
    if (widget.enabled != old.enabled) {
      widget.enabled ? _controller.repeat() : _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) =>
          _ShimmerClock(t: _controller.value, child: child!),
      child: widget.child,
    );
  }
}

/// The animated fill a skeleton shape paints when it is inside an
/// [AdminShimmer], and the flat base colour when it is not.
///
/// The band is placed by sliding the gradient's stops rather than by a
/// [GradientTransform], so it is positioned relative to THIS shape. A transform
/// keyed to the shared clock would put a 40px bar and a full-width bar at
/// different phases of the same sweep, which reads as several unrelated things
/// blinking instead of one band crossing the group.
Decoration _shimmerFill(BuildContext context, BorderRadius? radius,
    {BoxShape shape = BoxShape.rectangle}) {
  final t = _ShimmerClock.maybeOf(context);
  if (t == null) {
    return BoxDecoration(
      color: kSkeletonBase,
      borderRadius: radius,
      shape: shape,
    );
  }
  // Runs the band from fully off the left edge to fully off the right, so every
  // shape spends part of the cycle at rest rather than permanently lit.
  final centre = t * 2 - 0.5;
  return BoxDecoration(
    borderRadius: radius,
    shape: shape,
    gradient: LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: const [kSkeletonBase, kSkeletonHighlight, kSkeletonBase],
      stops: [
        (centre - 0.28).clamp(0.0, 1.0),
        centre.clamp(0.0, 1.0),
        (centre + 0.28).clamp(0.0, 1.0),
      ],
    ),
  );
}

/// A rounded rectangular placeholder. Give [width] `double.infinity` to fill
/// the available width responsively.
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;

  const SkeletonBox({
    super.key,
    this.width,
    this.height = 12,
    this.radius = 6,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: _shimmerFill(context, BorderRadius.circular(radius)),
    );
  }
}

/// A remote image that shimmers while it loads, then fades in — the image
/// equivalent of the shaped placeholders above.
///
/// Backed by [CachedNetworkImage], the same as the citizen side: it keeps a
/// disk cache on mobile, so a photo survives an app restart instead of being
/// re-downloaded. NOTE that its cache key is the URL — a signed URL that gets
/// re-minted per view defeats it entirely, so whoever supplies [url] has to
/// hand back a stable one (see AdminReportsNotifier.fetchMedia).
///
/// [errorChild] renders when the fetch fails. Sizing comes from the parent —
/// give it a bounded box.
class SkeletonNetworkImage extends StatelessWidget {
  final String url;
  final BoxFit fit;

  /// Corner radius of the *placeholder* only; clip the widget itself if the
  /// loaded image needs rounding too.
  final double radius;
  final Widget? errorChild;

  const SkeletonNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.radius = 0,
    this.errorChild,
  });

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: url,
      // fit belongs to CachedNetworkImage itself, which hands it to the image
      // it builds. Wrapping the image by hand to fade it in is what previously
      // cost it its tight constraints and let a portrait photo letterbox.
      fit: fit,
      fadeInDuration: const Duration(milliseconds: 240),
      placeholder: (_, _) => _placeholder(),
      errorWidget: (_, _, _) =>
          errorChild ??
          const ColoredBox(
            color: kSkeletonBase,
            child: Center(
              child: Icon(
                Icons.broken_image_rounded,
                size: 20,
                color: Color(0xFF8A94A6),
              ),
            ),
          ),
    );
  }

  Widget _placeholder() => AdminShimmer(
        // Builder so the DecoratedBox reads the clock this AdminShimmer just
        // published — a context from ABOVE it would find no _ShimmerClock and
        // render the flat base colour, unanimated.
        child: Builder(
          builder: (context) => DecoratedBox(
            decoration: _shimmerFill(context, BorderRadius.circular(radius)),
            child: const SizedBox.expand(),
          ),
        ),
      );
}

/// A circular placeholder (avatars, icon chips).
class SkeletonCircle extends StatelessWidget {
  final double size;
  const SkeletonCircle({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      // No borderRadius with BoxShape.circle — BoxDecoration asserts on the
      // pair.
      decoration: _shimmerFill(context, null, shape: BoxShape.circle),
    );
  }
}

/// Neutral default silhouette shown when a user has no profile photo.
const Color _kAvatarBg = Color(0xFFE5E7EB);
const Color _kAvatarFg = Color(0xFF9CA3AF);

/// Circular profile avatar for admin surfaces (Citizen / Team lists and the
/// user-actions sheet). Shows a shimmering skeleton while the photo loads, the
/// real photo once ready, and a neutral default profile silhouette when there's
/// no photo or the fetch fails. Sizing is fully caller-driven so it stays
/// responsive on web, tablet and phone.
class AdminAvatar extends StatelessWidget {
  final double size;
  final String? photoUrl;
  const AdminAvatar({super.key, required this.size, this.photoUrl});

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: _kAvatarBg,
      ),
      clipBehavior: Clip.antiAlias,
      child: hasPhoto
          ? SkeletonNetworkImage(
              url: photoUrl!,
              fit: BoxFit.cover,
              radius: size,
              errorChild: _default(),
            )
          : _default(),
    );
  }

  Widget _default() => Container(
        color: _kAvatarBg,
        alignment: Alignment.center,
        child: Icon(Icons.person_rounded, size: size * 0.6, color: _kAvatarFg),
      );
}
