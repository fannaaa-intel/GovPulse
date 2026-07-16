import 'package:flutter/material.dart';

import '../../admin/providers/admin_reports_provider.dart'
    show ReportStatus, reportStatusLabel;
import '../theme/staff_ui.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Small shared building blocks for the staff console pages.
// ════════════════════════════════════════════════════════════════════════════

Color staffReportStatusColor(ReportStatus s) => switch (s) {
      ReportStatus.pending => StaffUi.warn,
      ReportStatus.underReview => const Color(0xFF2563EB),
      ReportStatus.inProgress => StaffUi.accentSoft,
      ReportStatus.resolved => StaffUi.online,
      ReportStatus.rejected => StaffUi.danger,
    };

/// A small coloured status chip.
class StaffPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  const StaffPill({super.key, required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}

class StaffStatusPill extends StatelessWidget {
  final ReportStatus status;
  const StaffStatusPill(this.status, {super.key});
  @override
  Widget build(BuildContext context) => StaffPill(
        label: reportStatusLabel(status),
        color: staffReportStatusColor(status),
      );
}

/// A white rounded card with the staff border + shadow.
class StaffCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  const StaffCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final body = Container(
      decoration: BoxDecoration(
        color: StaffUi.surface,
        borderRadius: BorderRadius.circular(StaffUi.cardRadius),
        border: Border.all(color: StaffUi.border),
        boxShadow: StaffUi.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(StaffUi.cardRadius),
        child: body,
      ),
    );
  }
}

class StaffEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  const StaffEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: StaffUi.accentWash,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 28, color: StaffUi.accent),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: StaffUi.textPrimary,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: StaffUi.textMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A centred, scrollable, pull-to-refresh page body used by the list sections.
class StaffPageBody extends StatelessWidget {
  final Future<void> Function() onRefresh;
  final Widget child;
  final double maxWidth;
  const StaffPageBody({
    super.key,
    required this.onRefresh,
    required this.child,
    this.maxWidth = 1080,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final pad = width < 600 ? 14.0 : 24.0;
    return Container(
      color: StaffUi.pageBg,
      child: RefreshIndicator(
        color: StaffUi.accent,
        onRefresh: onRefresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(pad, pad, pad, pad + 40),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class StaffErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const StaffErrorState({super.key, required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 34, color: StaffUi.danger),
          const SizedBox(height: 10),
          Text(message,
              style: const TextStyle(fontSize: 13.5, color: StaffUi.textSecondary)),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(foregroundColor: StaffUi.accent),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

/// A compact filled/outline star row for a single 1–5 rating.
class StaffStarRow extends StatelessWidget {
  final int rating;
  final double size;
  const StaffStarRow(this.rating, {super.key, this.size = 14});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final on = i < rating;
        return Icon(
          on ? Icons.star_rounded : Icons.star_outline_rounded,
          size: size,
          color: on ? const Color(0xFFF5A623) : StaffUi.border,
        );
      }),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Skeleton loading — shown while a staff surface fetches data so the layout
//  doesn't jump from a bare spinner to content. Wrap a group of [StaffSkeletonBox]
//  / [StaffSkeletonCircle] shapes in a single [StaffShimmer]; one controller
//  sweeps a light band across the whole group. Mirrors the admin console's
//  skeleton primitives, staff-themed.
// ════════════════════════════════════════════════════════════════════════════

/// Base fill for staff skeleton shapes.
const Color kStaffSkeletonBase = Color(0xFFE7EBF1);

/// The moving highlight swept across the base by [StaffShimmer].
const Color kStaffSkeletonHighlight = Color(0xFFF5F7FB);

class StaffShimmer extends StatefulWidget {
  final Widget child;
  final bool enabled;
  const StaffShimmer({super.key, required this.child, this.enabled = true});

  @override
  State<StaffShimmer> createState() => _StaffShimmerState();
}

class _StaffShimmerState extends State<StaffShimmer>
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
                kStaffSkeletonBase,
                kStaffSkeletonHighlight,
                kStaffSkeletonBase,
              ],
              stops: const [0.25, 0.5, 0.75],
              transform: _StaffSlideTransform(_controller.value),
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _StaffSlideTransform extends GradientTransform {
  final double t; // 0..1
  const _StaffSlideTransform(this.t);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    final dx = (t * 2 - 1) * bounds.width;
    return Matrix4.translationValues(dx, 0, 0);
  }
}

/// A rounded rectangular placeholder. Give [width] `double.infinity` to fill
/// the available width responsively.
class StaffSkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  const StaffSkeletonBox({
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
        color: kStaffSkeletonBase,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// A circular placeholder (avatars, icon chips).
class StaffSkeletonCircle extends StatelessWidget {
  final double size;
  const StaffSkeletonCircle({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: kStaffSkeletonBase,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// Human "2h ago" style timestamp.
String staffAgo(DateTime? t) {
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  return '${t.day}/${t.month}/${t.year}';
}
