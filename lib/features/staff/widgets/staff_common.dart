import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show KeyDownEvent, KeyEvent, KeyRepeatEvent, LogicalKeyboardKey;

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
  // A future-dated row yields a NEGATIVE difference, which used to fall through
  // the `< 60` check below and render as "just now". That silently masked
  // timestamps stored 8 hours ahead (client local time written as UTC) — every
  // message in the staff thread read "just now" regardless of age. Handled
  // explicitly so the clamp is a decision rather than an accident.
  if (d.isNegative) return 'just now';
  if (d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  return '${t.day}/${t.month}/${t.year}';
}

// ════════════════════════════════════════════════════════════════════════════
//  Segmented tabs
//
//  The staff-themed twin of AdminSegmentedTabs. Kept as its own widget rather
//  than imported from the admin console so the two feature folders stay
//  independent and each carries its own palette — the shape and the keyboard
//  behaviour are deliberately identical, because an operator who works both
//  consoles should not have to learn two switchers.
//
//  Keyboard: arrows move (and wrap, so the selection never dead-ends), Home /
//  End jump to the edges, and a roving tab stop means the bar costs ONE Tab
//  keystroke to enter rather than one per segment.
// ════════════════════════════════════════════════════════════════════════════

class StaffSegmentedTabs extends StatefulWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;

  const StaffSegmentedTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelect,
  });

  @override
  State<StaffSegmentedTabs> createState() => _StaffSegmentedTabsState();
}

class _StaffSegmentedTabsState extends State<StaffSegmentedTabs> {
  late List<FocusNode> _nodes;

  @override
  void initState() {
    super.initState();
    _nodes = _makeNodes(widget.labels.length);
  }

  @override
  void didUpdateWidget(covariant StaffSegmentedTabs old) {
    super.didUpdateWidget(old);
    // The label list changes with the signed-in office (an office that receives
    // no feedback has one tab fewer), so the nodes must be rebuilt or the
    // indices drift out of range.
    if (old.labels.length != widget.labels.length) {
      _disposeNodes();
      _nodes = _makeNodes(widget.labels.length);
    }
  }

  @override
  void dispose() {
    _disposeNodes();
    super.dispose();
  }

  List<FocusNode> _makeNodes(int n) => List.generate(
        n,
        (i) => FocusNode(debugLabel: 'StaffSegmentedTab $i')
          ..addListener(_onFocusChanged),
      );

  void _disposeNodes() {
    for (final n in _nodes) {
      n
        ..removeListener(_onFocusChanged)
        ..dispose();
    }
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  void _select(int i) {
    widget.onSelect(i);
    _nodes[i].requestFocus();
  }

  /// Wraps, so the selection never dead-ends on the first or last segment.
  void _move(int delta) {
    final n = widget.labels.length;
    if (n == 0) return;
    _select((widget.selected + delta + n) % n);
  }

  KeyEventResult _onKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowDown) {
      _move(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowUp) {
      _move(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      _select(0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      _select(widget.labels.length - 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: StaffUi.surface,
          borderRadius: BorderRadius.circular(StaffUi.controlRadius),
          border: Border.all(color: StaffUi.border),
        ),
        child: Row(
          children: [
            for (var i = 0; i < widget.labels.length; i++)
              Expanded(child: _segment(context, widget.labels[i], i)),
          ],
        ),
      ),
    );
  }

  Widget _segment(BuildContext context, String label, int i) {
    final isSelected = i == widget.selected;
    final node = _nodes[i];
    node.skipTraversal = !isSelected;

    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 150);

    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      child: Focus(
        focusNode: node,
        onKeyEvent: (_, event) => _onKey(event),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _select(i),
          child: AnimatedContainer(
            duration: duration,
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected ? StaffUi.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(StaffUi.controlRadius - 3),
              // The focus ring must read against BOTH fills, so it is a
              // contrasting outline inside the segment rather than a tint.
              border: node.hasFocus
                  ? Border.all(
                      color: isSelected ? Colors.white : StaffUi.accent,
                      width: 2,
                    )
                  : Border.all(color: Colors.transparent, width: 2),
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? Colors.white : StaffUi.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  KPI tiles
//
//  The summary row at the top of a list page. Shared so Suggestions and
//  Feedback show the same shape — two pages that count different things should
//  still LOOK like the same console.
// ════════════════════════════════════════════════════════════════════════════

class StaffKpiTile extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;

  /// Tapping jumps somewhere useful (a filtered view). Null leaves the tile as
  /// a read-only figure rather than a dead button.
  final VoidCallback? onTap;

  const StaffKpiTile({
    super.key,
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return StaffCard(
      onTap: onTap,
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              // A hostile value ("1.2k", "—") must shrink rather than widen
              // the tile past its column.
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: StaffUi.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, color: StaffUi.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Lays KPI tiles out four-up, or two-up below [fourFrom].
///
/// Rows are IntrinsicHeight so a tile whose label wraps to two lines does not
/// leave its neighbours short — every tile in a row ends on the same edge.
class StaffKpiRow extends StatelessWidget {
  final List<Widget> tiles;
  final double fourFrom;
  const StaffKpiRow({super.key, required this.tiles, this.fourFrom = 720});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final perRow = c.maxWidth >= fourFrom ? 4 : 2;
        const gap = 10.0;
        final rows = <Widget>[];
        for (var i = 0; i < tiles.length; i += perRow) {
          final slice = tiles.skip(i).take(perRow).toList();
          rows.add(IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var j = 0; j < perRow; j++) ...[
                  Expanded(
                    child:
                        j < slice.length ? slice[j] : const SizedBox.shrink(),
                  ),
                  if (j < perRow - 1) const SizedBox(width: gap),
                ],
              ],
            ),
          ));
          if (i + perRow < tiles.length) rows.add(const SizedBox(height: gap));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: rows,
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  List-page skeleton
//
//  Mirrors the REAL layout of Suggestions / Feedback: header, KPI row, optional
//  panel, filter chips, then a two-pane list + detail above the breakpoint. A
//  skeleton that does not match the thing it stands in for makes the page JUMP
//  when data lands, which is worse than a plain spinner.
//
//  Every block is a StaffSkeletonBox on a plain background. Per the known
//  ShaderMask bug, a shimmer drawn over a white card repaints the card and the
//  whole thing reads as a solid slab — these sit on the page background only.
// ════════════════════════════════════════════════════════════════════════════

class StaffListPageSkeleton extends StatelessWidget {
  /// Height of the block between the KPI row and the filters (the rating mix
  /// panel on Feedback). Zero means no such panel.
  final double panelHeight;

  /// Where the layout becomes list + detail, matching the real page.
  final double twoPaneFrom;

  final int cardCount;
  final double cardHeight;

  const StaffListPageSkeleton({
    super.key,
    this.panelHeight = 0,
    this.twoPaneFrom = 900,
    this.cardCount = 4,
    this.cardHeight = 112,
  });

  @override
  Widget build(BuildContext context) {
    return StaffShimmer(
      child: LayoutBuilder(
        builder: (context, c) {
          final twoPane = c.maxWidth >= twoPaneFrom;
          final perRow = c.maxWidth >= 720 ? 4 : 2;
          const gap = 10.0;

          final list = Column(
            children: [
              for (var i = 0; i < cardCount; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: StaffSkeletonBox(
                      height: cardHeight, width: double.infinity),
                ),
            ],
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: title + subtitle.
              const StaffSkeletonBox(width: 160, height: 22),
              const SizedBox(height: 8),
              const StaffSkeletonBox(width: 260, height: 13),
              const SizedBox(height: 16),
              // KPI row.
              Row(
                children: [
                  for (var i = 0; i < perRow; i++) ...[
                    const Expanded(
                      child: StaffSkeletonBox(height: 68, radius: 12),
                    ),
                    if (i < perRow - 1) const SizedBox(width: gap),
                  ],
                ],
              ),
              if (panelHeight > 0) ...[
                const SizedBox(height: 14),
                StaffSkeletonBox(
                    height: panelHeight, width: double.infinity, radius: 12),
              ],
              const SizedBox(height: 14),
              // Filter chips + search.
              Row(
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    const StaffSkeletonBox(width: 86, height: 34, radius: 10),
                    const SizedBox(width: 8),
                  ],
                  const Spacer(),
                  const StaffSkeletonBox(width: 200, height: 34, radius: 10),
                ],
              ),
              const SizedBox(height: 14),
              if (!twoPane)
                list
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 380, child: list),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: StaffSkeletonBox(height: 300, radius: 14),
                    ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

/// [StaffPageBody] without pull-to-refresh, for a loading state.
///
/// A RefreshIndicator over a skeleton invites a pull that cannot refresh
/// anything, because the fetch it would trigger is already in flight.
class StaffPageBodyStatic extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  const StaffPageBodyStatic({
    super.key,
    required this.child,
    this.maxWidth = 1080,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final pad = width < 600 ? 14.0 : 24.0;
    return Container(
      color: StaffUi.pageBg,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(pad, pad, pad, pad + 40),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: child,
          ),
        ),
      ),
    );
  }
}
