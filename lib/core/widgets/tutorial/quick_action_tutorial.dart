import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'quick_action_tutorial_layer.dart';

/// First-run coached walkthrough of the Home Quick Action card.
///
/// The interaction, in one sentence: the Quick Action card FLOATS out of the
/// scrolling page up to the top of the screen so all five rows are visible at
/// once, each row is spotlighted in turn, and on exit the card glides back to
/// where it really lives.
///
/// Why a float rather than scrolling the page: the card sits low enough in the
/// mobile body that spotlighting a row in place would need the page scrolled,
/// and a scroll under a dimmed backdrop reads as the app moving on its own. The
/// page behind the tutorial never moves; only a painted copy of the card does.
///
/// The card on screen during the tour is a *copy* painted into the Overlay. The
/// real one stays in the tree (invisible, so the page keeps its exact layout and
/// scroll extent) which is what makes the settle land pixel-exactly on the
/// original position, and what makes an interrupted tour a no-op for the page.
class QuickActionTutorial {
  QuickActionTutorial._();

  /// Device-local rather than a profile column on purpose. A profile column
  /// needs a network write the instant the tour ends, and that write can fail
  /// (offline, slow link, RLS): the failure modes are "replay anyway", which is
  /// what local storage already gives us, or "swallow it and never show the
  /// tour again", which is worse. Cost of the local choice is a replay on a new
  /// device, which for a five-step tour is acceptable.
  static const String _seenKey = 'quick_action_tutorial_seen_v1';

  static bool _running = false;

  /// True while the tour owns the screen. Read by callers that must not open
  /// something on top of it — notably Home's 3-minute verification reminder.
  static bool get isRunning => _running;

  static Future<bool> hasSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_seenKey) ?? false;
    } catch (_) {
      // A prefs read can throw on a wedged platform channel. Treat an unknown
      // state as "seen": silently skipping the tour is a far smaller failure
      // than replaying it on every launch.
      return true;
    }
  }

  static Future<void> markSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_seenKey, true);
    } catch (_) {
      // Nothing to do: worst case the tour runs once more next launch.
    }
  }

  /// For manual re-testing on a device: call, then hot-restart.
  static Future<void> reset() async {
    _running = false;
    _ghostBuilder = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_seenKey);
    } catch (_) {}
  }

  /// Clears the in-flight state without touching the seen flag.
  ///
  /// `_running` is a static, and it is cleared on the tour's own exit path. If
  /// the overlay is ever torn down some other way — the route popped from under
  /// it, the host state disposed mid-tour — that path does not run, and a stuck
  /// `true` would silently refuse every future tour for the life of the
  /// process. The host calls this from dispose so that cannot happen.
  static void abandon() {
    _running = false;
    _ghostBuilder = null;
  }

  /// Builds the card drawn on the overlay during the tour.
  ///
  /// The real card stays in the page (invisible) so the page keeps its exact
  /// layout and scroll extent, which is what lets the settle land pixel-exactly
  /// on the original position. The overlay therefore needs its own copy, and
  /// the caller supplies it rather than this file importing the Home tree.
  static WidgetBuilder? _ghostBuilder;

  /// Shows the tour if it has never been seen.
  ///
  /// [anchorKey] must be attached to the Quick Action card itself, and
  /// [ghostBuilder] must build a visually identical copy of it. The caller is
  /// responsible for only calling this once the card is actually laid out and
  /// settled — see [HomePage]'s entry-animation gate.
  ///
  /// Returns when the tour has fully finished, including the settle.
  static Future<void> maybeShow(
    BuildContext context, {
    required GlobalKey anchorKey,
    required WidgetBuilder ghostBuilder,
    required ValueChanged<bool> onVisibilityChanged,
    required Future<Rect?> Function() onReveal,
  }) async {
    if (_running) return;
    if (await hasSeen()) return;
    if (!context.mounted) return;

    final overlay = Overlay.of(context, rootOverlay: true);

    // Geometry is read ONCE, here, from the real card. If the card is not laid
    // out yet (or has zero size) there is nothing meaningful to spotlight, and
    // guessing a rect would put the highlight over empty space.
    final box = anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || box.size.isEmpty) return;
    final origin = box.localToGlobal(Offset.zero) & box.size;

    _running = true;
    _ghostBuilder = ghostBuilder;
    onVisibilityChanged(true);

    final completer = Completer<void>();
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _TutorialLayer(
        anchorKey: anchorKey,
        originRect: origin,
        onReveal: onReveal,
        onFinished: () {
          entry.remove();
          _running = false;
          _ghostBuilder = null;
          onVisibilityChanged(false);
          markSeen();
          if (!completer.isCompleted) completer.complete();
        },
      ),
    );

    overlay.insert(entry);
    return completer.future;
  }
}
