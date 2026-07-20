import 'package:flutter/material.dart';

/// ════════════════════════════════════════════════════════════════════════════
///  Deep-link highlight — "take me to the thing you're talking about".
///
///  When a tap navigates to a LIST that contains the item being discussed (a
///  notification about a reply, a dashboard insight row), landing on the list is
///  only half the job: the user still has to find the row. This scrolls it into
///  view and flashes it once, then lets the accent fade so the list returns to
///  normal and nothing stays visually stuck.
///
///  Extracted from My Submissions, which pioneered the pattern for reply
///  notifications. It lives here so every list flashes identically — same
///  timings, same accent — instead of each screen inventing its own.
///
///  Not for detail screens: when the whole screen IS the item, there is nothing
///  to pick out of a list, and a flash would be noise.
/// ════════════════════════════════════════════════════════════════════════════

/// Notification topics that navigate but never flash their target.
///
/// A reaction is ambient acknowledgement ("someone liked this"), not work
/// landing in a queue — accenting a row for one overstates it. Everything
/// actionable (reports, suggestions, feedback, comments, replies) does flash.
///
/// These are admin/staff `notifications.topic` values. The citizen bell uses a
/// different vocabulary on `notifications.type` — see `kHeartNotifTypes` in
/// notification_popup.dart, which encodes the same rule for that side.
const Set<String> kNonFlashingNotifTopics = {'post_heart', 'comment_heart'};

/// How long the accent holds at full strength before fading.
const kHighlightHold = Duration(milliseconds: 2200);

/// Cross-fade between the highlighted and normal decoration. Drive the target's
/// [AnimatedContainer] with this so the flash fades instead of snapping off.
const kHighlightFade = Duration(milliseconds: 450);

/// Scroll-into-view animation for the flashed row.
const kHighlightScroll = Duration(milliseconds: 450);

/// Where the target lands vertically: slightly below the top edge, so it reads
/// as "here it is" rather than being jammed under a header.
const kHighlightAlignment = 0.15;

/// The tint behind a flashed row, shared by both treatments below.
const kHighlightFill = Color(0xFFF0F9FF);

/// The flash accent for a STANDALONE card — one that already floats, with its
/// own radius and margins. Matches the My Submissions original.
///
/// Do NOT use this for a flush table row: see [highlightRowDecoration].
BoxDecoration highlightDecoration({
  required double radius,
  required Color accent,
}) =>
    BoxDecoration(
      color: kHighlightFill,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: accent, width: 1.6),
      boxShadow: [
        BoxShadow(
          color: accent.withValues(alpha: 0.18),
          blurRadius: 20,
          offset: const Offset(0, 9),
          spreadRadius: -6,
        ),
      ],
    );

/// The flash accent for a FLUSH TABLE ROW — one that sits edge-to-edge inside a
/// rounded, clipped results card, separated from its neighbours by a divider.
///
/// Such a row must not borrow [highlightDecoration]: a full border + drop shadow
/// pretends the row is a floating card, and the parent's `Clip.antiAlias` then
/// rounds the row's corners and swallows the shadow — the highlight visibly
/// fights the card's radius at the first and last row.
///
/// Tint + a left accent bar reads as "this one" while staying flush, and keeps
/// the row separator so the table doesn't lose a line while flashing.
BoxDecoration highlightRowDecoration({
  required Color accent,
  required BorderSide divider,
}) =>
    BoxDecoration(
      color: kHighlightFill,
      border: Border(
        left: BorderSide(color: accent, width: 3),
        bottom: divider,
      ),
    );

/// Draws the flash as a ring AROUND [child] instead of replacing its
/// decoration.
///
/// For rows that already own a surface (a card with its own fill, border and
/// radius): swapping their decoration for [highlightDecoration] would erase
/// that styling mid-flash, so the accent goes outside instead. Rows that draw
/// their own plain background (table rows) should switch decoration directly.
///
/// Always an [AnimatedContainer], including when not highlighted — that's what
/// lets the accent fade out rather than snap off when the hold expires.
Widget highlightRing({
  required bool highlighted,
  required double radius,
  required Color accent,
  required Widget child,
}) =>
    AnimatedContainer(
      duration: kHighlightFade,
      decoration: highlighted
          ? highlightDecoration(radius: radius, accent: accent)
          : const BoxDecoration(),
      child: child,
    );

/// Adds "scroll to a row and flash it once" to a list screen's [State].
///
/// Usage:
///  1. key each row with [highlightKey] (`key: highlightKey(item.id)`),
///  2. pick its decoration with [isHighlighted] inside an [AnimatedContainer]
///     whose duration is [kHighlightFade],
///  3. call [flashHighlight] once the rows are actually built — after the fetch
///     resolves, not in `initState`, or there is no row to scroll to yet.
mixin DeepLinkHighlightMixin<T extends StatefulWidget> on State<T> {
  String? _highlightId;
  String? _lastFlashRequest;
  final Map<String, GlobalKey> _highlightKeys = {};

  bool isHighlighted(String id) => _highlightId != null && id == _highlightId;

  /// Stable key per row id, so [flashHighlight] can find the row to scroll to.
  GlobalKey highlightKey(String id) =>
      _highlightKeys.putIfAbsent(id, () => GlobalKey());

  /// Scrolls [id] into view and flashes it, clearing after [kHighlightHold].
  /// A null/empty id is a no-op, so callers can pass an optional target
  /// straight through without a guard.
  void flashHighlight(String? id) {
    if (id == null || id.isEmpty || !mounted) return;
    setState(() => _highlightId = id);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final ctx = _highlightKeys[id]?.currentContext;
      // A missing context means the row isn't on screen — it may be filtered
      // out or on another tab. Still flash: if it appears while the hold is
      // running the user sees it, and if not, the timer just clears silently.
      if (ctx != null) {
        await Scrollable.ensureVisible(
          ctx,
          alignment: kHighlightAlignment,
          duration: kHighlightScroll,
          curve: Curves.easeOutCubic,
        );
      }
      await Future.delayed(kHighlightHold);
      // Only clear the highlight we started: a second deep-link arriving mid-
      // hold owns the accent now, and this stale timer must not cancel it.
      if (mounted && _highlightId == id) {
        setState(() => _highlightId = null);
      }
    });
  }

  /// Flashes [id] once per distinct target, deferred past the current frame.
  /// Safe to call from `build` on every rebuild — repeats for the same id are
  /// ignored, so filtering, polling and refreshes don't re-flash.
  ///
  /// Prefer this over a local `bool didFlash` guard. A page whose tab is ALREADY
  /// open isn't rebuilt from scratch when a second deep-link arrives — Flutter
  /// updates the existing State, so `initState` never re-runs and a bool latch
  /// stays true forever, silently swallowing every later notification. Keying on
  /// the target id instead re-arms automatically when the target changes.
  ///
  /// Call it once the list actually has rows; before then there's nothing to
  /// scroll to and the request is wasted.
  void flashHighlightOnce(String? id) {
    if (id == null || id.isEmpty || _lastFlashRequest == id) return;
    _lastFlashRequest = id;
    WidgetsBinding.instance.addPostFrameCallback((_) => flashHighlight(id));
  }

  /// Re-arms [flashHighlightOnce] so the SAME id can flash again.
  ///
  /// Keying on the id is right for rebuilds — polling and filtering must not
  /// re-flash — but wrong for a deliberate repeat: tapping the same "X liked
  /// your post" notification twice is two separate requests to go look at it,
  /// and the second was being silently dropped. Call this from `didUpdateWidget`
  /// when a fresh deep-link target arrives, not from `build`.
  void rearmHighlight() => _lastFlashRequest = null;
}
