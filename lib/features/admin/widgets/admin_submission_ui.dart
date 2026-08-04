import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/deeplink_highlight.dart';
import '../theme/admin_ui.dart';
import 'admin_skeleton.dart';
import '../../../core/widgets/app_dialog.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Shared UI kit for the admin "submission" consoles — Reports, Suggestions and
//  Feedback. One design language across all three: the same anonymous identity
//  treatment, the same Filters-button → sheet → active-chips pattern, the same
//  card/table shells, status pills and empty/skeleton states.
//
//  Anonymous privacy is a first-class visual concept here: an anonymous
//  submission never shows a name/photo (the provider never even fetches one),
//  and it gets a distinct "protected identity" look so it reads as anonymous at
//  a glance — not just a missing name.
// ════════════════════════════════════════════════════════════════════════════

/// The one colour that means "anonymous / protected identity" everywhere.
const Color kAnonColor = Color(0xFF64748B); // slate

// ── Anonymous identity ───────────────────────────────────────────────────────

/// Masked avatar for an anonymous submitter — a hidden-identity glyph on a
/// slate tint, deliberately different from a real person's photo/initial.
class AnonAvatar extends StatelessWidget {
  final double size;
  const AnonAvatar({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: kAnonColor.withValues(alpha: 0.14),
        shape: BoxShape.circle,
        border: Border.all(color: kAnonColor.withValues(alpha: 0.35)),
      ),
      child: Icon(
        Icons.visibility_off_rounded,
        size: size * 0.5,
        color: kAnonColor,
      ),
    );
  }
}

/// Compact "Anonymous" pill used in dense rows (table cells, card meta).
class AnonPill extends StatelessWidget {
  const AnonPill({super.key});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Anonymous — identity withheld',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: kAnonColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kAnonColor.withValues(alpha: 0.28)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.visibility_off_rounded, size: 12, color: kAnonColor),
            SizedBox(width: 5),
            Text(
              'Anonymous',
              maxLines: 1,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: kAnonColor,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// [AnonPill] made safe for a FLEXED cell.
///
/// The pill is a fixed ~98px, so a table column narrower than that reports
/// overflow instead of adapting. scaleDown shrinks it to fit by however much it
/// has to — usually a percent or two, which is invisible.
///
/// Deliberately NOT a LayoutBuilder, which is the obvious way to write this and
/// is wrong: these pills also sit inside [SubmissionListCard], whose
/// IntrinsicHeight asks its subtree for an intrinsic height, and a
/// LayoutBuilder cannot answer that — it throws. Same reason the overdue chip
/// uses this trick rather than measuring.
class ShrinkableAnonPill extends StatelessWidget {
  const ShrinkableAnonPill({super.key});

  @override
  Widget build(BuildContext context) => const Align(
        alignment: Alignment.centerLeft,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: AnonPill(),
        ),
      );
}

/// Real submitter avatar: profile photo, or a coloured initial fallback.
class IdentityAvatar extends StatelessWidget {
  final String name;
  final String? photoUrl;
  final double size;
  const IdentityAvatar({
    super.key,
    required this.name,
    this.photoUrl,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Text(
        initial,
        style: TextStyle(
          fontSize: size * 0.4,
          fontWeight: FontWeight.w700,
          color: AppColors.primaryBlue,
        ),
      ),
    );
    if (photoUrl == null || photoUrl!.isEmpty) return fallback;
    return ClipOval(
      child: Image.network(
        photoUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

String roleLabel(String? role) {
  switch (role) {
    case 'admin':
      return 'Admin';
    case 'staff':
      return 'Staff';
    default:
      return 'Citizen';
  }
}

class RoleChip extends StatelessWidget {
  final String? role;
  const RoleChip(this.role, {super.key});

  @override
  Widget build(BuildContext context) {
    final isOfficial = role == 'admin' || role == 'staff';
    final c = isOfficial ? AppColors.primaryBlue : AdminUi.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        roleLabel(role),
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: c),
      ),
    );
  }
}

/// Inline submitter for list rows/cards: the anonymous pill, or name + role
/// chip. Never renders a name for anonymous submissions.
class SubmitterInline extends StatelessWidget {
  final bool isAnonymous;
  final String? name;
  final String? role;
  const SubmitterInline({
    super.key,
    required this.isAnonymous,
    this.name,
    this.role,
  });

  @override
  Widget build(BuildContext context) {
    if (isAnonymous) {
      // Shrinkable: this sits in a flexed table cell that can be narrower than
      // the pill's fixed width.
      return const ShrinkableAnonPill();
    }
    return Row(
      children: [
        Flexible(
          child: Text(
            (name == null || name!.isEmpty) ? 'Resident' : name!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AdminUi.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 6),
        RoleChip(role),
      ],
    );
  }
}

/// The larger submitter block for detail dialogs — avatar + name + role, or a
/// clear "Anonymous submission" panel. Same hard rule: no name/photo for anon.
class SubmitterBlock extends StatelessWidget {
  final bool isAnonymous;
  final String? name;
  final String? photoUrl;
  final String? role;
  const SubmitterBlock({
    super.key,
    required this.isAnonymous,
    this.name,
    this.photoUrl,
    this.role,
  });

  @override
  Widget build(BuildContext context) {
    if (isAnonymous) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kAnonColor.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kAnonColor.withValues(alpha: 0.30)),
        ),
        child: Row(
          children: [
            const AnonAvatar(size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Anonymous submission',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: kAnonColor,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Identity withheld and never retrieved',
                    style: TextStyle(fontSize: 11.5, color: AdminUi.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final display = (name == null || name!.isEmpty) ? 'Resident' : name!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AdminUi.subtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminUi.border),
      ),
      child: Row(
        children: [
          IdentityAvatar(name: display, photoUrl: photoUrl, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  display,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AdminUi.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                RoleChip(role),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Status pill ──────────────────────────────────────────────────────────────

/// The console's segmented pill tabs: a bordered track with the active segment
/// filled blue.
///
/// A SMALL-SCREEN control. It divides the width evenly between its segments, so
/// it only reads well with a few short labels and a phone-width track — stretch
/// it across a desktop and the labels float in oversized boxes. Wide layouts
/// (and any switcher with more than about four options) want
/// [AdminUnderlineTabs] instead.
///
/// Used by the dashboard's narrow layout and by the report detail's phone
/// pane switcher.
/// Keyboard-operable segmented control.
///
/// Follows the standard tab-list interaction: Tab moves the caret INTO the bar
/// (landing on the active segment, never stepping through all of them), then
/// the arrow keys move the selection, wrapping at both ends. Home/End jump to
/// the extremes. Selection follows focus, so an arrow press both moves the ring
/// and switches the pane — one key, one result.
class AdminSegmentedTabs extends StatefulWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;

  const AdminSegmentedTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelect,
  });

  @override
  State<AdminSegmentedTabs> createState() => _AdminSegmentedTabsState();
}

class _AdminSegmentedTabsState extends State<AdminSegmentedTabs> {
  late List<FocusNode> _nodes;

  @override
  void initState() {
    super.initState();
    _nodes = _makeNodes(widget.labels.length);
  }

  @override
  void didUpdateWidget(covariant AdminSegmentedTabs old) {
    super.didUpdateWidget(old);
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

  List<FocusNode> _makeNodes(int n) => List.generate(n, (i) {
    // Repaint the ring as focus arrives/leaves.
    return FocusNode(debugLabel: 'AdminSegmentedTab $i')
      ..addListener(_onFocusChanged);
  });

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

  /// Wraps, so the selection never dead-ends on the first/last segment.
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
    // Vertical arrows are accepted too: the bar stacks visually on narrow
    // screens, and pressing Down on a row of tabs is a common reflex.
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
          color: AdminUi.surface,
          borderRadius: BorderRadius.circular(AdminUi.controlRadius),
          border: Border.all(color: AdminUi.border),
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
    // Roving tab stop: only the active segment is reachable by Tab, so the bar
    // costs one keystroke to enter instead of one per tab.
    node.skipTraversal = !isSelected;

    final radius = BorderRadius.circular(AdminUi.controlRadius - 3);
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
              color: isSelected ? AppColors.primaryBlue : Colors.transparent,
              borderRadius: radius,
              // The ring has to read against BOTH fills — blue when selected,
              // white when not — so it sits inside the segment as a contrasting
              // outline rather than tinting the fill.
              border: node.hasFocus
                  ? Border.all(
                      color: isSelected ? Colors.white : AppColors.primaryBlue,
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
                color: isSelected ? Colors.white : AdminUi.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Text tabs with a blue underline on the active one and a rule across the
/// full width.
///
/// Unlike [AdminSegmentedTabs] these size to their labels and scroll when they
/// run out of room, so they work at ANY width and with any number of options —
/// nothing gets stretched on a desktop or crushed on a phone. This is the
/// switcher to reach for by default.
class AdminUnderlineTabs extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;

  /// Optional trailing count per label, e.g. `Needs triage 2`. Same length as
  /// [labels] when given. A zero still shows — "none waiting" is information.
  final List<int>? counts;

  const AdminUnderlineTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelect,
    this.counts,
  }) : assert(
          counts == null || counts.length == labels.length,
          'counts must line up with labels',
        );

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // The rule spans the pane even when the tabs themselves scroll past it.
        const Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Divider(height: 1, color: AdminUi.border),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < labels.length; i++) _tab(labels[i], i),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tab(String label, int i) {
    final isSelected = i == selected;
    final count = counts?[i];
    return InkWell(
      onTap: () => onSelect(i),
      child: Container(
        padding: const EdgeInsets.fromLTRB(2, 4, 2, 9),
        margin: EdgeInsets.only(right: i == labels.length - 1 ? 0 : 22),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              width: 2,
              color: isSelected ? AppColors.primaryBlue : Colors.transparent,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              maxLines: 1,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: isSelected ? AppColors.primaryBlue : AdminUi.textMuted,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primaryBlue.withValues(alpha: 0.12)
                      : AdminUi.subtle,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isSelected
                        ? AppColors.primaryBlue
                        : AdminUi.textMuted,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A distinctive pill "rail" for switching between piles/buckets — the primary
/// queue navigation on the Reports console.
///
/// Where [AdminUnderlineTabs] marks the active tab with a thin underline, this
/// fills the active pile as a solid blue chip against a row of white chips, so
/// "which pile am I in" reads at a glance on a desktop pane AND on a phone.
///
/// Chips size to their labels and scroll horizontally when they run out of room.
/// A soft fade appears at whichever edge still hides chips — the affordance the
/// bare scroll strip was missing — and selecting a chip (or arriving via a
/// deep-link) scrolls it into view, so the active pile is never stranded
/// off-screen on a narrow phone.
class AdminPillTabs extends StatefulWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;

  /// Optional trailing count per label, same length as [labels] when given.
  /// A zero still shows — "none waiting" is information.
  final List<int>? counts;

  /// The colour the edge fades resolve to; match whatever the rail sits on.
  /// Defaults to the admin page background.
  final Color fadeColor;

  const AdminPillTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelect,
    this.counts,
    this.fadeColor = AdminUi.pageBg,
  }) : assert(
          counts == null || counts.length == labels.length,
          'counts must line up with labels',
        );

  @override
  State<AdminPillTabs> createState() => _AdminPillTabsState();
}

class _AdminPillTabsState extends State<AdminPillTabs> {
  final _scroll = ScrollController();
  late List<GlobalKey> _keys;
  bool _fadeLeft = false;
  bool _fadeRight = false;

  @override
  void initState() {
    super.initState();
    _keys = List.generate(widget.labels.length, (_) => GlobalKey());
    _scroll.addListener(_updateFades);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealSelected(animate: false);
      _updateFades();
    });
  }

  @override
  void didUpdateWidget(AdminPillTabs old) {
    super.didUpdateWidget(old);
    if (widget.labels.length != _keys.length) {
      _keys = List.generate(widget.labels.length, (_) => GlobalKey());
    }
    if (widget.selected != old.selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected());
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_updateFades);
    _scroll.dispose();
    super.dispose();
  }

  void _updateFades() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final left = pos.pixels > 0.5;
    final right = pos.pixels < pos.maxScrollExtent - 0.5;
    if (left != _fadeLeft || right != _fadeRight) {
      setState(() {
        _fadeLeft = left;
        _fadeRight = right;
      });
    }
  }

  void _revealSelected({bool animate = true}) {
    final i = widget.selected;
    if (i < 0 || i >= _keys.length) return;
    final ctx = _keys[i].currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: animate ? const Duration(milliseconds: 250) : Duration.zero,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          // Vertical room so the selected chip's soft shadow isn't clipped by
          // the scroll viewport, which otherwise hugs the chip height exactly.
          padding: const EdgeInsets.fromLTRB(0, 6, 0, 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < widget.labels.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                _chip(i),
              ],
            ],
          ),
        ),
        if (_fadeLeft) _edgeFade(left: true),
        if (_fadeRight) _edgeFade(left: false),
      ],
    );
  }

  Widget _edgeFade({required bool left}) => Positioned(
        left: left ? 0 : null,
        right: left ? null : 0,
        top: 0,
        bottom: 0,
        child: IgnorePointer(
          child: Container(
            width: 28,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: left ? Alignment.centerLeft : Alignment.centerRight,
                end: left ? Alignment.centerRight : Alignment.centerLeft,
                colors: [
                  widget.fadeColor,
                  widget.fadeColor.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
      );

  // One shared tempo for everything that moves when selection changes — the
  // fill, the border, and the count's grow-and-fade — so the old pill shrinking
  // and the new pill growing read as a single motion instead of separate bumps.
  static const _transition = Duration(milliseconds: 260);
  static const _curve = Curves.easeInOutCubic;

  Widget _chip(int i) {
    final isSelected = i == widget.selected;
    final count = widget.counts?[i];
    return AnimatedContainer(
      key: _keys[i],
      duration: _transition,
      curve: _curve,
      decoration: BoxDecoration(
        color: isSelected ? AppColors.primaryBlue : AdminUi.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected ? AppColors.primaryBlue : AdminUi.border,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: AppColors.primaryBlue.withValues(alpha: 0.22),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => widget.onSelect(i),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.labels[i],
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? Colors.white : AdminUi.textSecondary,
                  ),
                ),
                // Show the count on the active pile only. A single switcher
                // both fades AND widens the badge in (and reverses on the pill
                // you leave), so the pill grows and shrinks as one smooth move.
                AnimatedSwitcher(
                  duration: _transition,
                  switchInCurve: _curve,
                  switchOutCurve: _curve,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SizeTransition(
                      axis: Axis.horizontal,
                      axisAlignment: -1,
                      sizeFactor: anim,
                      child: child,
                    ),
                  ),
                  child: (count != null && isSelected)
                      ? Padding(
                          key: const ValueKey('badge'),
                          padding: const EdgeInsets.only(left: 7),
                          child: _CountBadge(count: count),
                        )
                      : const SizedBox(key: ValueKey('none'), height: 20),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The count badge on the selected pill — a translucent-white chip on the blue
/// fill. Only the active pile shows its count, so this never renders in the
/// unselected state.
class _CountBadge extends StatelessWidget {
  final int count;
  const _CountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Side of one square tile in a details-pane attachment grid, for a row of
/// [maxWidth].
///
/// Fits as many ~92px columns as the width allows, then lets them share the
/// leftover so a row ends flush against the pane instead of trailing a ragged
/// gap. Clamped at both ends: a thumb never shrinks below a comfortably
/// tappable size on a phone, nor balloons into a hero on a wide pane.
///
/// Shared so Reports, Suggestions and Feedback grid identically — and so the
/// skeleton placeholders can be shaped with the same number.
double attachmentTileSize(double maxWidth, {double gap = 10}) {
  const target = 92.0, minTile = 84.0, maxTile = 116.0;
  // An unbounded or degenerate row (an unconstrained Wrap, a zero-width pane
  // mid-layout) has nothing to divide — fall back to the target.
  if (!maxWidth.isFinite || maxWidth <= 0) return target;
  final cols = ((maxWidth + gap) / (target + gap)).floor().clamp(1, 8);
  final tile = (maxWidth - gap * (cols - 1)) / cols;
  return tile.clamp(minTile, maxTile);
}

class StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  const StatusPill({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// ── Cards / shells ───────────────────────────────────────────────────────────

/// The white results card that wraps a table or a card list.
class AdminResultsCard extends StatelessWidget {
  final Widget child;
  const AdminResultsCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AdminUi.surface,
        borderRadius: BorderRadius.circular(AdminUi.cardRadius),
        boxShadow: AdminUi.cardShadow,
      ),
      // The border is a FOREGROUND decoration so it paints on top of the child.
      // A Container paints its `decoration` BEHIND its child, so with the border
      // in there the table header's opaque fill painted straight over the card's
      // top border and rounded corners — squaring off the top of every results
      // card while the borderless bottom looked fine.
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AdminUi.cardRadius),
        border: Border.all(color: AdminUi.border),
      ),
      // Clips the header's fill to the rounded corners. Uses `decoration`'s
      // radius, which is why that has to keep its borderRadius too.
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// A single stacked list card. Anonymous submissions get a slate left-accent +
/// faint tint so they're distinguishable from named ones at a glance.
class SubmissionListCard extends StatelessWidget {
  final bool isAnonymous;
  final VoidCallback onTap;
  final Widget child;

  /// Set when this card is a deep-link target: it flashes on arrival, then
  /// fades back to its normal look. See [DeepLinkHighlightMixin].
  final bool highlighted;
  const SubmissionListCard({
    super.key,
    required this.isAnonymous,
    required this.onTap,
    required this.child,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: kHighlightFade,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: highlighted
          ? highlightDecoration(radius: 12, accent: AppColors.primaryBlue)
          : BoxDecoration(
              color: isAnonymous
                  ? kAnonColor.withValues(alpha: 0.04)
                  : AdminUi.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isAnonymous
                    ? kAnonColor.withValues(alpha: 0.28)
                    : AdminUi.border,
              ),
            ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left accent — slate for anonymous, invisible otherwise.
                Container(
                  width: 4,
                  color: isAnonymous ? kAnonColor : Colors.transparent,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Toolbar: search + filters button + active chips ──────────────────────────

class AdminSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  const AdminSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 13, color: AdminUi.textMuted),
        prefixIcon: const Icon(Icons.search_rounded, size: 18),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded, size: 16),
                onPressed: onClear,
              ),
        contentPadding: const EdgeInsets.symmetric(vertical: 11),
        filled: true,
        fillColor: AdminUi.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AdminUi.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AdminUi.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primaryBlue),
        ),
      ),
    );
  }
}

/// Button that opens the filter sheet; shows a count badge when filters are on.
class FilterButton extends StatelessWidget {
  final int activeCount;
  final VoidCallback onTap;
  const FilterButton({super.key, required this.activeCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final active = activeCount > 0;
    final c = AppColors.primaryBlue;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: active ? c.withValues(alpha: 0.10) : AdminUi.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active ? c.withValues(alpha: 0.45) : AdminUi.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.tune_rounded,
                size: 17,
                color: active ? c : AdminUi.textSecondary,
              ),
              const SizedBox(width: 7),
              Text(
                'Filters',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: active ? c : AdminUi.textSecondary,
                ),
              ),
              if (active) ...[
                const SizedBox(width: 7),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$activeCount',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A single removable active-filter chip shown above the results.
class ActiveChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;
  final bool emphasize; // anonymous / high-signal chips
  const ActiveChip({
    super.key,
    required this.label,
    required this.onRemove,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = emphasize ? kAnonColor : AppColors.primaryBlue;
    return Container(
      padding: const EdgeInsets.only(left: 10, right: 4, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: c,
            ),
          ),
          const SizedBox(width: 2),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(20),
            child: Icon(Icons.close_rounded, size: 15, color: c),
          ),
        ],
      ),
    );
  }
}

/// A labelled row of single-select choice chips, used inside the filter sheet
/// (replaces cramped dropdowns). [value] == null selects the "All" chip.
class FilterChoiceRow<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<({T? value, String text})> options;
  final ValueChanged<T?> onSelected;
  const FilterChoiceRow({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: AdminUi.textMuted,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final o in options)
              _ChoiceChip(
                text: o.text,
                selected: o.value == value,
                onTap: () => onSelected(o.value),
              ),
          ],
        ),
      ],
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  final String text;
  final bool selected;
  final VoidCallback onTap;
  const _ChoiceChip({
    required this.text,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.primaryBlue;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? c.withValues(alpha: 0.12) : AdminUi.subtle,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? c.withValues(alpha: 0.5) : AdminUi.border,
            ),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? c : AdminUi.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// A full-width toggle row for a boolean filter (e.g. "Anonymous only").
class FilterSwitchRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const FilterSwitchRow({
    super.key,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: value ? kAnonColor.withValues(alpha: 0.06) : AdminUi.subtle,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: value ? kAnonColor.withValues(alpha: 0.35) : AdminUi.border,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: value ? kAnonColor : AdminUi.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AdminUi.textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11.5, color: AdminUi.textMuted),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: Colors.white,
              activeTrackColor: kAnonColor,
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows [content] as a bottom sheet on phones and a centered dialog on wider
/// screens — responsive across devices/platforms. [onReset] adds a Reset action.
Future<void> openAdminFilterSheet(
  BuildContext context, {
  required String title,
  required Widget content,
  VoidCallback? onReset,
}) {
  final narrow = MediaQuery.of(context).size.width < 720;
  final shell = _FilterSheetShell(
    title: title,
    onReset: onReset,
    child: content,
  );
  if (narrow) {
    // Cap the sheet so a long filter list (e.g. feedback's Office options)
    // stays a contained, rounded-top bottom sheet that scrolls internally —
    // instead of stretching full-screen with its header sliding under the
    // status bar. Keeps every filter sheet (reports / suggestions / feedback)
    // looking and behaving the same.
    final maxSheetHeight = MediaQuery.of(context).size.height * 0.85;
    return showModalBottomSheet(
      context: context,
      backgroundColor: AdminUi.surface,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: BoxConstraints(maxHeight: maxSheetHeight),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: shell,
      ),
    );
  }
  return showAppDialog(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: AdminUi.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: shell,
      ),
    ),
  );
}

class _FilterSheetShell extends StatelessWidget {
  final String title;
  final Widget child;
  final VoidCallback? onReset;
  const _FilterSheetShell({
    required this.title,
    required this.child,
    this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AdminUi.textPrimary,
                  ),
                ),
                const Spacer(),
                if (onReset != null)
                  TextButton(
                    onPressed: onReset,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primaryBlue,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                    ),
                    child: const Text(
                      'Reset',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                  color: AdminUi.textMuted,
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AdminUi.border),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: child,
            ),
          ),
          const Divider(height: 1, color: AdminUi.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'Show results',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Respond-to-citizen panel (suggestions & feedback) ───────────────────────

/// The primary admin action for suggestions/feedback: reply to the submitter
/// and keep an internal note. Every reply goes out as a push + bell
/// notification, named or anonymous alike; anonymous submissions show a notice
/// above the composer clarifying that their identity still stays hidden.
class RespondPanel extends StatefulWidget {
  final bool isAnonymous;
  final DateTime? respondedAt;
  final String? existingResponse;

  /// Quick-fill reply suggestions.
  final List<String> templates;

  /// Pre-populated internal note controller (owned by the caller).
  final TextEditingController noteController;

  final Future<void> Function(String message) onSendResponse;
  final Future<void> Function() onSaveNote;

  const RespondPanel({
    super.key,
    required this.isAnonymous,
    required this.respondedAt,
    required this.existingResponse,
    required this.templates,
    required this.noteController,
    required this.onSendResponse,
    required this.onSaveNote,
  });

  @override
  State<RespondPanel> createState() => _RespondPanelState();
}

class _RespondPanelState extends State<RespondPanel> {
  final _replyCtrl = TextEditingController();
  bool _sending = false;
  bool _savingNote = false;

  @override
  void dispose() {
    _replyCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_replyCtrl.text.trim().isEmpty) return;
    setState(() => _sending = true);
    try {
      await widget.onSendResponse(_replyCtrl.text.trim());
      _replyCtrl.clear(); // only on success
    } catch (_) {
      // The caller surfaces the error (snackbar); keep the text so it's not lost.
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _saveNote() async {
    setState(() => _savingNote = true);
    try {
      await widget.onSaveNote();
    } finally {
      if (mounted) setState(() => _savingNote = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('RESPOND TO CITIZEN'),
        const SizedBox(height: 10),
        if (widget.isAnonymous) ...[
          _anonNotice(),
          const SizedBox(height: 12),
        ],
        if (widget.respondedAt != null) _sentBanner(),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in widget.templates)
              _TemplateChip(
                text: t,
                onTap: () {
                  _replyCtrl.text = t;
                  _replyCtrl.selection = TextSelection.collapsed(
                    offset: t.length,
                  );
                  setState(() {});
                },
              ),
          ],
        ),
        const SizedBox(height: 10),
        _field(
          _replyCtrl,
          widget.respondedAt == null
              ? 'Write a reply the citizen will receive…'
              : 'Send another reply…',
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.send_rounded, size: 16),
            label: Text(widget.respondedAt == null
                ? 'Send response'
                : 'Send again'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            ),
          ),
        ),
        const SizedBox(height: 22),
        _title('INTERNAL NOTE'),
        const SizedBox(height: 4),
        const Text(
          'Only visible to admins — never sent to the citizen.',
          style: TextStyle(fontSize: 11.5, color: AdminUi.textMuted),
        ),
        const SizedBox(height: 8),
        _field(widget.noteController, 'Add an internal note…'),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: _savingNote ? null : _saveNote,
            icon: _savingNote
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sticky_note_2_outlined, size: 16),
            label: const Text('Save note'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryBlue,
              side: const BorderSide(color: AdminUi.border),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            ),
          ),
        ),
      ],
    );
  }

  Widget _anonNotice() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kAnonColor.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kAnonColor.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: const [
          Icon(Icons.visibility_off_rounded, size: 20, color: kAnonColor),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Anonymous submission — your reply reaches the submitter on their '
              'own device just like a named one. Their identity stays hidden '
              'from you and the public unless it is formally revealed.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: kAnonColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sentBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.green.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  size: 16, color: AppColors.green),
              const SizedBox(width: 6),
              Text(
                'Replied · ${adminShortDate(widget.respondedAt)}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.green,
                ),
              ),
            ],
          ),
          if (widget.existingResponse != null &&
              widget.existingResponse!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              widget.existingResponse!,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AdminUi.textPrimary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _title(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: AdminUi.textMuted,
        ),
      );

  Widget _field(TextEditingController c, String hint) {
    return TextField(
      controller: c,
      maxLines: 4,
      minLines: 3,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 13, color: AdminUi.textMuted),
        filled: true,
        fillColor: AdminUi.subtle,
        contentPadding: const EdgeInsets.all(12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AdminUi.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AdminUi.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primaryBlue),
        ),
      ),
    );
  }
}

class _TemplateChip extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _TemplateChip({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.primaryBlue.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.primaryBlue.withValues(alpha: 0.30),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_rounded,
                  size: 14, color: AppColors.primaryBlue),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.primaryBlue,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── States & helpers ─────────────────────────────────────────────────────────

class AdminResultsMessage extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  final Widget? action;
  const AdminResultsMessage({
    super.key,
    required this.icon,
    required this.color,
    required this.text,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 52, horizontal: 16),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30, color: color),
            const SizedBox(height: 10),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AdminUi.textMuted),
            ),
            if (action != null) ...[const SizedBox(height: 8), action!],
          ],
        ),
      ),
    );
  }
}

class AdminListSkeleton extends StatelessWidget {
  const AdminListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: AdminShimmer(
        child: Column(
          children: [
            _SkeletonRow(),
            _SkeletonRow(),
            _SkeletonRow(),
            _SkeletonRow(),
            _SkeletonRow(),
          ],
        ),
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonCircle(size: 34),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 140, height: 12),
                SizedBox(height: 8),
                SkeletonBox(width: 90, height: 10),
              ],
            ),
          ),
          SizedBox(width: 60, child: SkeletonBox(width: 60, height: 20, radius: 20)),
        ],
      ),
    );
  }
}

const List<String> _kMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String adminShortDate(DateTime? t) {
  if (t == null) return '—';
  return '${_kMonths[t.month - 1]} ${t.day}, ${t.year}';
}

/// Clock time on its own, e.g. "10:30 AM".
String adminClockTime(DateTime? t) {
  if (t == null) return '—';
  final h24 = t.hour;
  final h = h24 % 12 == 0 ? 12 : h24 % 12;
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m ${h24 < 12 ? 'AM' : 'PM'}';
}

/// Date and clock time together, e.g. "Jul 8, 2026 10:30 AM" — for the report
/// timeline, where an admin needs to see exactly when a stage was reached.
String adminLongDateTime(DateTime? t) {
  if (t == null) return '—';
  return '${adminShortDate(t)} ${adminClockTime(t)}';
}
