import 'dart:async';

/// Collapses a burst of "something changed" signals into ONE refresh.
///
/// ── Why this exists ────────────────────────────────────────────────────────
/// Realtime delivers one event per ROW, not per user action. "Clear all
/// notifications" is a single tap that deletes every row the user has, so the
/// three notification centres each receive N DELETE events in a few
/// milliseconds — and a naive `callback: (_) => reload()` turns one tap into N
/// full refetches, all but the last of which are already stale by the time they
/// land.
///
/// This was latent until migration 20260813000000: before it, DELETE events
/// never reached any client at all (the `user_id` filter could not match a
/// primary-key-only identity), so the burst had nothing to fire. Making deletes
/// work is what made coalescing necessary.
///
/// ── Trailing edge, deliberately ────────────────────────────────────────────
/// The refresh runs [window] AFTER THE LAST signal, not on the first one. A
/// leading-edge call would fetch the state as it was at the START of the burst
/// — for a clear-all, the list before anything was deleted — and then have
/// nothing scheduled to correct it. The last state is the true one.
///
/// [window] is short enough to stay imperceptible and long enough to swallow a
/// multi-row delete.
class BurstCoalescer {
  BurstCoalescer({this.window = const Duration(milliseconds: 250)});

  final Duration window;
  Timer? _timer;

  /// Requests a run of [action]. Restarts the window, so a steady stream of
  /// signals runs [action] once after the stream stops.
  void schedule(void Function() action) {
    _timer?.cancel();
    _timer = Timer(window, action);
  }

  /// Drops any pending run. Call from the owner's teardown — a coalescer that
  /// fires after its owner is gone refreshes state nobody is showing.
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}
