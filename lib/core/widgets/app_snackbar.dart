import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Semantic kind of a toast — drives its colour + icon.
enum AppSnackType { success, error, info }

// Only one toast is visible at a time. Tracked module-wide so a new toast
// cleanly replaces the previous one instead of stacking.
OverlayEntry? _activeToast;
GlobalKey<_TopToastState>? _activeKey;

/// App-wide toast that appears at the **top** of the screen, just below the
/// status bar, coloured from the shared palette (green / red / blue). Used by
/// both the citizen app and the admin console so toasts look and behave
/// identically everywhere.
///
/// It is rendered in the root [Overlay] (not as a floating SnackBar). A
/// floating SnackBar pushed to the top with a near-full-height bottom margin
/// grows *upward*, so a tall / multi-line message clips off the top edge (or
/// overlaps the status bar). Rendering in the overlay lets us anchor the card
/// at a safe top inset and let it grow **downward**, so it always sits fully
/// on-screen on mobile, tablet and web/desktop. On wide screens it's centred
/// and capped to a comfortable phone width.
///
/// It slides + fades DOWN into place on show, and on dismiss plays that same
/// motion in reverse — pulling back up the way it came in.
/// Pass [overlay] — captured from a still-mounted context BEFORE an async gap
/// (`Overlay.of(context, rootOverlay: true)`) — to toast from a callback whose
/// own widget has since unmounted (e.g. an admin approving a request card that
/// then leaves the list). The root overlay lives for the app's lifetime, so the
/// toast still shows; a root-navigator context can't be used here because the
/// overlay is a *descendant* of that navigator, not an ancestor. When [overlay]
/// is null the nearest root overlay above [context] is used instead.
void showAppSnackBar(
  BuildContext? context,
  String message, {
  AppSnackType type = AppSnackType.info,
  OverlayState? overlay,
}) {
  final ov = overlay ??
      (context != null ? Overlay.maybeOf(context, rootOverlay: true) : null);
  if (ov == null) return;

  final (Color bg, IconData icon) = switch (type) {
    AppSnackType.success => (AppColors.green, Icons.check_circle_rounded),
    AppSnackType.error => (AppColors.red, Icons.error_outline_rounded),
    AppSnackType.info => (AppColors.primaryBlue, Icons.info_outline_rounded),
  };

  // Ask any existing toast to animate out (reverse of its entrance); it removes
  // itself when the exit finishes, while the new one slides in.
  _activeKey?.currentState?.dismiss();

  final key = GlobalKey<_TopToastState>();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _TopToast(
      key: key,
      message: message,
      background: bg,
      icon: icon,
      onRemoved: () {
        entry.remove();
        if (_activeToast == entry) {
          _activeToast = null;
          _activeKey = null;
        }
      },
    ),
  );
  _activeToast = entry;
  _activeKey = key;
  ov.insert(entry);
}

class _TopToast extends StatefulWidget {
  final String message;
  final Color background;
  final IconData icon;

  /// Called once the exit animation has finished — removes the overlay entry.
  final VoidCallback onRemoved;

  const _TopToast({
    super.key,
    required this.message,
    required this.background,
    required this.icon,
    required this.onRemoved,
  });

  @override
  State<_TopToast> createState() => _TopToastState();
}

class _TopToastState extends State<_TopToast>
    with SingleTickerProviderStateMixin {
  // One controller drives both slide + fade. Playing it forward is the
  // entrance; reversing it is the exit, so the toast "pulls back" up the exact
  // path it came in on.
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    reverseDuration: const Duration(milliseconds: 240),
  );

  Timer? _timer;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _ctrl.forward();
    _timer = Timer(const Duration(seconds: 3), dismiss);
  }

  /// Reverse the entrance, then remove the overlay entry.
  void dismiss() {
    if (_dismissing) return;
    _dismissing = true;
    _timer?.cancel();
    if (!mounted) {
      widget.onRemoved();
      return;
    }
    _ctrl.reverse().whenComplete(widget.onRemoved);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screenW = media.size.width;

    // Cap the width on wide screens so it reads as a phone-sized toast; hug the
    // edges (16px) on phones.
    const maxWidth = 460.0;
    final horizontal = screenW > maxWidth + 32
        ? (screenW - maxWidth) / 2
        : 16.0;

    final curve = CurvedAnimation(
      parent: _ctrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return Positioned(
      // Just below the status bar / notch. The card grows DOWNWARD from here,
      // so long / multi-line messages never clip off the top edge.
      top: media.padding.top + 12,
      left: horizontal,
      right: horizontal,
      child: FadeTransition(
        opacity: curve,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -0.4),
            end: Offset.zero,
          ).animate(curve),
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: dismiss,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: widget.background,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(widget.icon, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
