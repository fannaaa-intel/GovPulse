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
    )..repeat();
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
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: const [
                kSkeletonBase,
                kSkeletonHighlight,
                kSkeletonBase,
              ],
              stops: const [0.25, 0.5, 0.75],
              transform: _SlideTransform(_controller.value),
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Slides the shimmer gradient from left to right across the wrapped bounds.
class _SlideTransform extends GradientTransform {
  final double t; // 0..1
  const _SlideTransform(this.t);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    final dx = (t * 2 - 1) * bounds.width;
    return Matrix4.translationValues(dx, 0, 0);
  }
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
      decoration: BoxDecoration(
        color: kSkeletonBase,
        borderRadius: BorderRadius.circular(radius),
      ),
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
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: kSkeletonBase,
            borderRadius: BorderRadius.circular(radius),
          ),
          child: const SizedBox.expand(),
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
      decoration: const BoxDecoration(
        color: kSkeletonBase,
        shape: BoxShape.circle,
      ),
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
