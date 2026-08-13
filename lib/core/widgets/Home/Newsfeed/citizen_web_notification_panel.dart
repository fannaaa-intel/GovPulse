import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../../features/home/screen/notification_popup.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Citizen WEB notification panel.
//
//  The same presentation as the admin console's bell (a card anchored under the
//  top-right bell on desktop, a centred modal on a narrow viewport) so the two
//  web surfaces read alike. The phone app keeps [NotificationPopup] — its
//  full-bleed frosted sheet is the right shape for a thumb, and a dropdown
//  pinned to a corner is not.
//
//  Backed by the same NotificationService as every other citizen bell, so the
//  badge, realtime updates and read state are shared; only the shell differs.
// ════════════════════════════════════════════════════════════════════════════

/// Below this the panel stops being a dropdown and becomes a centred modal —
/// a 380px card pinned to a corner does not fit a narrow window, and in
/// landscape on a short viewport it would run off the bottom.
const double _kNarrowBelow = 560;

/// Opens the citizen bell in whichever shell fits the platform.
///
/// EVERY citizen surface must route through here. Home used to call
/// [NotificationPopup] directly with no `kIsWeb` check, so the same bell was a
/// centred frosted card on the Home page and a dropdown under the bell on My
/// Reports — the two presentations in the 2026-07-20 screenshots.
///
/// The split is by PLATFORM, then by width:
///   web, ≥ [_kNarrowBelow]  → card anchored under the bell
///   web, narrower           → centred modal (a corner dropdown doesn't fit)
///   phone app               → [NotificationPopup]'s full-bleed frosted sheet,
///                             which is the right shape for a thumb
///
/// [onTap] stays the caller's, because routing a notification differs per
/// screen (Home pushes within its own shell; the scaffold uses named routes).
/// Only the SHELL is shared — that is the part that was drifting.
Future<void> showCitizenNotifications(
  BuildContext context, {
  required double width,
  required void Function(AppNotification n) onTap,
}) async {
  if (kIsWeb) {
    await showCitizenWebNotifications(context, onTap: onTap);
  } else {
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Notifications',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, _, _) => NotificationPopup(width: width, onTap: onTap),
      transitionBuilder: (_, anim, _, child) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
          child: child,
        ),
      ),
    );
  }
  // Re-sync the badge from the DB once it closes, so a mid-animation realtime
  // event can't leave the count stale.
  await NotificationService.load();
}

/// Opens the panel. [anchorTop] is where the card hangs from on desktop,
/// measured from the top of the viewport (the height of the top nav).
Future<void> showCitizenWebNotifications(
  BuildContext context, {
  required void Function(AppNotification n) onTap,
  double anchorTop = 72,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Notifications',
    barrierColor: Colors.black.withValues(alpha: 0.18),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, _, _) =>
        _CitizenWebNotificationPanel(onTap: onTap, anchorTop: anchorTop),
    transitionBuilder: (context, anim, _, child) {
      final narrow = MediaQuery.of(context).size.width < _kNarrowBelow;
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: narrow
            // Centred modal grows from its middle.
            ? ScaleTransition(
                scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
                child: child,
              )
            // Dropdown slides down out of the bell.
            : SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, -0.02),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
      );
    },
  );
}

class _CitizenWebNotificationPanel extends StatefulWidget {
  final void Function(AppNotification n) onTap;
  final double anchorTop;

  const _CitizenWebNotificationPanel({
    required this.onTap,
    required this.anchorTop,
  });

  @override
  State<_CitizenWebNotificationPanel> createState() =>
      _CitizenWebNotificationPanelState();
}

class _CitizenWebNotificationPanelState
    extends State<_CitizenWebNotificationPanel> {
  bool _loading = true;
  List<AppNotification> _items = const [];

  @override
  void initState() {
    super.initState();
    NotificationService.load().then((_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _items = List.of(NotificationService.notifications);
      });
    });
    // A panel left open is a live view, not a snapshot: a notification arriving
    // (or being cleared from another tab) has to land in the list, not just in
    // the badge behind it. Mirrors the admin/staff panels' revision listener.
    NotificationService.revision.addListener(_onRevision);
  }

  @override
  void dispose() {
    NotificationService.revision.removeListener(_onRevision);
    super.dispose();
  }

  void _onRevision() {
    if (!mounted) return;
    // Never re-raises the skeleton: the list is already on screen and the
    // service has been refreshed by whoever bumped the revision.
    setState(() => _items = List.of(NotificationService.notifications));
  }

  Future<void> _markAllRead() async {
    final unread = _items.where((n) => !n.read).toList();
    if (unread.isEmpty) return;
    setState(() {
      _items = [for (final n in _items) n.read ? n : n.copyWith(read: true)];
    });
    for (final n in unread) {
      await NotificationService.markRead(n);
    }
  }

  Future<void> _clearAll() async {
    if (_items.isEmpty) return;
    setState(() => _items = const []);
    await NotificationService.clearAll();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final narrow = size.width < _kNarrowBelow;

    // Width: a fixed card on desktop, inset from both edges when narrow.
    final double w = narrow ? size.width - 32 : 380;

    // Height: never taller than what is actually on screen. Subtracting the
    // anchor and the keyboard/safe-area insets is what keeps the panel whole
    // in landscape on a short viewport, where a fixed height would overflow.
    final double vertical = narrow ? 24 : widget.anchorTop + 24;
    final double available =
        size.height - vertical - media.viewInsets.bottom - media.padding.bottom;
    final double h = available.clamp(240.0, narrow ? 560.0 : 520.0);

    final card = Material(
      color: Colors.transparent,
      child: Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 28,
              offset: const Offset(0, 12),
              spreadRadius: -8,
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            _header(),
            const Divider(height: 1, color: Color(0xFFE5E7EB)),
            Expanded(child: _body()),
          ],
        ),
      ),
    );

    // Tapping the backdrop closes; taps inside the card must not bubble to it.
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
          ),
        ),
        if (narrow)
          Center(
            child: GestureDetector(onTap: () {}, child: card),
          )
        else
          Positioned(
            top: widget.anchorTop,
            right: 24,
            child: GestureDetector(onTap: () {}, child: card),
          ),
      ],
    );
  }

  Widget _header() {
    final hasUnread = _items.any((n) => !n.read);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          const Text(
            'Notifications',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827),
            ),
          ),
          const Spacer(),
          if (hasUnread) _headerAction('Mark all read', _markAllRead),
          if (hasUnread && _items.isNotEmpty) const SizedBox(width: 12),
          if (_items.isNotEmpty)
            _headerAction(
              'Clear all',
              _clearAll,
              color: const Color(0xFFDC2626),
            ),
          IconButton(
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, color: Color(0xFF6B7280)),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _headerAction(
    String label,
    VoidCallback onTap, {
    Color color = const Color(0xFF2563EB),
  }) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    ),
  );

  Widget _body() {
    if (_loading) return const _NotifListSkeleton();
    if (_items.isEmpty) {
      return const Center(
        child: Text(
          'No notifications',
          style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
        ),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: _items.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: Color(0xFFF3F4F6)),
      itemBuilder: (_, i) => _row(_items[i]),
    );
  }

  Widget _row(AppNotification n) {
    final unread = !n.read;
    final photo = n.actorPhotoUrl;

    final Widget leading = (photo != null && photo.isNotEmpty)
        ? ClipOval(
            child: SizedBox(
              width: 34,
              height: 34,
              child: CachedNetworkImage(
                imageUrl: photo,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => _iconLeading(n),
              ),
            ),
          )
        : _iconLeading(n);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onTap(n),
        child: Container(
          color: unread ? const Color(0xFFF5F9FF) : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              leading,
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      n.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                        color: unread
                            ? const Color(0xFF111827)
                            : const Color(0xFF4B5563),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      n.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B7280),
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      n.formatTimeAgo(n.time),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                  ],
                ),
              ),
              if (unread) ...[
                const SizedBox(width: 8),
                Container(
                  margin: const EdgeInsets.only(top: 5),
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: n.color,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconLeading(AppNotification n) => Container(
    width: 34,
    height: 34,
    decoration: BoxDecoration(
      color: n.color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Icon(n.icon, color: n.color, size: 18),
  );
}

// ── Loading skeleton ────────────────────────────────────────────────────────
//
// The rest of the app answers "the data is on its way" with a shaped
// placeholder, never a spinner: admin's _NotifListSkeleton, staff's, and the
// phone popup's _NotifLoadingSkeleton all draw rows in the shape of the real
// ones, so the list doesn't jump when the data lands. This panel was the last
// citizen surface still spinning.
//
// The shape mirrors [_row]: a 34px leading square, then three text bars. The
// two lower bars are FRACTIONS of the row rather than fixed widths, because
// this panel is 380px on desktop but stretches to the viewport (up to ~528px)
// as a narrow-screen modal — fixed bars would sit stranded on the left there.

/// Base fill of the placeholder shapes, and the highlight swept across it.
/// Same pair the admin/staff/phone skeletons use, so all four read as one
/// effect.
const Color _kSkeletonBase = Color(0xFFE7EBF1);
const Color _kSkeletonHighlight = Color(0xFFF5F7FB);

class _NotifListSkeleton extends StatelessWidget {
  const _NotifListSkeleton();

  /// One placeholder row: 34px leading, 46px of bars, 11px padding each side.
  static const double _rowExtent = 68;

  @override
  Widget build(BuildContext context) {
    // Draw only as many rows as actually fit, then clip. The panel's height is
    // whatever the viewport allows (240–560), so a fixed count would overflow a
    // short window — a landscape phone browser is the tight case.
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxH = constraints.maxHeight.isFinite
            ? constraints.maxHeight - 12 // the 6+6 outer padding below
            : _rowExtent * 6;
        final count = (maxH / _rowExtent).floor().clamp(1, 8);
        return _PanelShimmer(
          child: ClipRect(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(count, (_) => const _NotifSkeletonRow()),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NotifSkeletonRow extends StatelessWidget {
  const _NotifSkeletonRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      // Matches _row's own padding, so the bars land where the text will.
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SkeletonBox(width: 34, height: 34, radius: 10),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkeletonBox(width: double.infinity, height: 12),
                SizedBox(height: 7),
                _SkeletonBar(widthFactor: 0.62, height: 11),
                SizedBox(height: 7),
                _SkeletonBar(widthFactor: 0.28, height: 9),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;

  const _SkeletonBox({this.width, required this.height, this.radius = 6});

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: _kSkeletonBase,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

/// A bar sized as a share of the row — keeps its proportions whether the panel
/// is the 380px desktop dropdown or a stretched narrow-screen modal.
class _SkeletonBar extends StatelessWidget {
  final double widthFactor;
  final double height;

  const _SkeletonBar({required this.widthFactor, required this.height});

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: FractionallySizedBox(
      widthFactor: widthFactor,
      child: _SkeletonBox(height: height),
    ),
  );
}

/// Sweeps one highlight band across everything inside it, so a group of shapes
/// animates as a single surface instead of each shape pulsing on its own.
class _PanelShimmer extends StatefulWidget {
  final Widget child;
  const _PanelShimmer({required this.child});

  @override
  State<_PanelShimmer> createState() => _PanelShimmerState();
}

class _PanelShimmerState extends State<_PanelShimmer>
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
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: const [
            _kSkeletonBase,
            _kSkeletonHighlight,
            _kSkeletonBase,
          ],
          stops: const [0.25, 0.5, 0.75],
          // Reused from the phone popup — same sweep, one implementation.
          transform: GradientTranslation(
            (_controller.value * 2 - 1) * bounds.width,
          ),
        ).createShader(bounds),
        child: child,
      ),
      child: widget.child,
    );
  }
}
