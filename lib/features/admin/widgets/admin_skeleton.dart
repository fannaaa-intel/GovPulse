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
