// lib/core/widgets/events/event_slide_in.dart
//
// The lifecycle of the event slide-in card: when it appears, where it sits,
// how long it stays, and what happens as the citizen moves around the app.
//
// ── Why this is app-wide rather than a Home widget ───────────────────────────
//
// The first two drafts of this feature lived on Home and tore the card down the
// moment the citizen navigated. That was backwards: the person who opens the
// app and immediately taps into My Reports is precisely the one who never saw
// the card, and cancelling it punished them for moving fast.
//
// So the entry goes into the ROOT overlay, above the navigator, and rides along
// from screen to screen for its own 8 seconds. Home only starts the check; it
// does not own the card.
//
// This is only possible because main.dart registers `homeRouteObserver` on
// MaterialApp, so it already sees every route in the app.
//
// ── What lives where ─────────────────────────────────────────────────────────
//
//   event_popup_rules.dart  — which event, if any (pure, heavily tested)
//   event_slide_in_card.dart — what it looks like (pure, tested at 3 widths)
//   this file                — when, where, and for how long

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../router/app_router.dart' show homeRouteObserver;
import '../../router/legacy_nav.dart';
import '../../../features/home/Quick-action/Events/events_screen.dart'
    show EventItem;
import '../../services/events_service.dart';
import 'event_popup_rules.dart';
import 'event_slide_in_card.dart';

/// Routes the card must never appear over.
///
/// Each entry earns its place:
///   * `/emergency`      — someone is calling for help.
///   * verification flows — a live camera and OCR; a floating card over the
///                          frame is a failed scan.
///   * `/login`, `/signup`, `/guest` — not a citizen yet, and no user id to
///                          record anything against.
///   * `/events`, `/event_detail` — they are already looking at events.
///   * `/scan`           — an account-less agency flow that is not theirs.
///
/// Checked on every navigation rather than once at launch: walking from
/// Settings onto a face scan mid-dwell must hide the card on the way in.
const Set<String> kEventPopupBlockedRoutes = {
  '/emergency',
  '/login',
  '/signup',
  '/guest',
  '/events',
  '/event_detail',
  '/scan',
  '/intro',
  '/verification',
  '/verification_id_selection',
  '/verification_photo_instruction',
  '/verification_upload_id',
  '/verification_scan',
  '/verification_review',
  '/verification_identity',
  '/verification_face_scan',
};

/// How long the card stays if the citizen does nothing.
const Duration kEventPopupDwell = Duration(seconds: 8);

/// Entrance and exit. The pairing — `easeOutCubic` in, `easeInCubic` out — is
/// the house convention (app_dialog, app_snackbar, home_top_nav).
const Duration kEventPopupEnter = Duration(milliseconds: 420);
const Duration kEventPopupExit = Duration(milliseconds: 360);

/// Ceiling on the eligibility query. Past this the check is abandoned rather
/// than a card arriving long after the citizen has settled into a screen.
const Duration kEventPopupQueryBudget = Duration(seconds: 4);

/// Fraction of the card's width a drag must pass to count as a dismissal.
const double kEventPopupSwipeFraction = 0.4;

/// Traces one step of the eligibility decision.
///
/// Every refusal path in [EventSlideIn.maybeShow] is a bare `return`, which on
/// a device is indistinguishable from "the feature is broken". These lines are
/// what make a silent card explainable: filter with
/// `adb logcat -s flutter` and read the reason.
///
/// ── Why this is not behind kDebugMode ────────────────────────────────────
///
/// A `kDebugMode` guard is the usual choice and would be wrong here. The build
/// being tested on a device is a RELEASE build — that is the point, it is the
/// artifact that ships — and a debug-only log prints nothing in it. The whole
/// reason for these lines is to explain a silent card on a real handset, which
/// is precisely the situation a debug guard would leave undiagnosable.
///
/// The cost is small and bounded: a handful of `debugPrint` calls that run once
/// per app open, on a code path that already awaits a network query. If they
/// ever need to go, gate them behind an explicit flag rather than build mode,
/// so a release diagnostic build stays possible.
void _log(String message) {
  debugPrint('[EventPopup] $message');
}

/// Shows the event slide-in card, at most once per app open.
///
/// Static, like [QuickActionTutorial], because there must be exactly one card
/// in the app at a time and the caller should not have to hold an instance to
/// guarantee that.
class EventSlideIn {
  EventSlideIn._();

  static OverlayEntry? _entry;
  static bool _running = false;

  /// True while a card is on screen or animating.
  static bool get isRunning => _running;

  // ── Prefs keys ─────────────────────────────────────────────────────────────
  //
  // Per-user, because two citizens sharing a handset is normal in an LGU
  // context: a bare key would let one person's swipe silence the event for the
  // other. Same fix `my_sub_seen_*` already applies.

  /// The signed-in citizen's id, or null for a guest, a signed-out visitor, or
  /// an uninitialised client.
  ///
  /// Guarded rather than a bare read because `Supabase.instance` ASSERTS when
  /// the client has not been initialised — it does not return null. In the
  /// shipped app that cannot happen, but an assertion escaping from here would
  /// break the one contract this whole feature rests on: that a failure to
  /// decide means no card, never an error in a citizen's face.
  static String? _uid() {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  static String _shownKey(String uid) => 'event_popup_shown_$uid';
  static String _dismissedKey(String uid) => 'event_popup_dismissed_$uid';
  static String _lastSeenKey(String uid) => 'event_popup_last_seen_$uid';

  /// Clears in-flight state without touching the stored history.
  ///
  /// The exit path clears `_running` itself, but a card torn down some other
  /// way — the app disposed mid-dwell, a hot restart — never reaches it. Left
  /// stuck true, no card could ever show again for the life of the process.
  static void abandon() {
    try {
      _entry?.remove();
    } catch (_) {
      // Already removed, or the overlay is gone. Nothing to do.
    }
    _entry = null;
    _running = false;
  }

  /// For manual re-testing on a device: call, then reopen the app.
  static Future<void> reset() async {
    abandon();
    final uid = _uid();
    if (uid == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_shownKey(uid));
      await prefs.remove(_dismissedKey(uid));
      await prefs.remove(_lastSeenKey(uid));
    } catch (_) {}
  }

  // ── Stored state ───────────────────────────────────────────────────────────

  static Future<EventPopupState?> _readState(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawShown = prefs.getStringList(_shownKey(uid)) ?? const <String>[];
      final shown = <EventShowRecord>[];
      for (final raw in rawShown) {
        final r = EventShowRecord.decode(raw);
        // A corrupt entry decodes to null and is simply skipped — see the
        // decoder's own note on why that is safer than throwing.
        if (r != null) shown.add(r);
      }
      final dismissed =
          (prefs.getStringList(_dismissedKey(uid)) ?? const <String>[]).toSet();
      final lastRaw = prefs.getString(_lastSeenKey(uid));

      return EventPopupState(
        shown: shown,
        dismissed: dismissed,
        lastSeenAt: lastRaw == null ? null : DateTime.tryParse(lastRaw),
      );
    } catch (_) {
      // A wedged platform channel must not break the app. No state means no
      // card, which is the correct failure for a promotional surface.
      return null;
    }
  }

  /// Records that [event] was shown, and advances the newness watermark.
  ///
  /// Called only once the entrance animation has COMPLETED — never when it
  /// starts. A citizen who navigates away at 1000ms saw nothing, and must not
  /// have the event burned; see [_show].
  static Future<void> _markShown(
    String uid,
    EventModel event,
    List<EventModel> candidates,
    EventPopupState state,
    DateTime now,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final shown = pruneShown([
        ...state.shown,
        EventShowRecord(
          eventId: event.id,
          wasFeatured: event.isFeatured,
          shownOn: dayOf(now),
        ),
      ], now);
      await prefs.setStringList(
        _shownKey(uid),
        shown.map((r) => r.encode()).toList(),
      );

      // The watermark deliberately does not advance to `now` — an event held
      // back by the daily cap must stay new. See advanceWatermark.
      final mark = advanceWatermark(
        candidates,
        state,
        now,
        shownNow: event,
      );
      if (mark != null) {
        await prefs.setString(_lastSeenKey(uid), mark.toIso8601String());
      }
    } catch (_) {}
  }

  static Future<void> _markDismissed(
    String uid,
    String eventId,
    List<EventModel> candidates,
    Set<String> current,
    DateTime now,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final next = pruneDismissed({...current, eventId}, candidates, now);
      await prefs.setStringList(_dismissedKey(uid), next.toList());
    } catch (_) {}
  }

  // ── Entry point ────────────────────────────────────────────────────────────

  /// Checks for an eligible event and, if there is one, slides in a card.
  ///
  /// Safe to call unconditionally: every gate that could refuse is inside.
  /// Returns without doing anything — and without throwing — whenever the card
  /// should not appear, which is the common case.
  ///
  /// The caller (Home, after its entry animation) is responsible only for the
  /// surface gates it can see: phone band, portrait, no blocking modal.
  static Future<void> maybeShow(BuildContext context) async {
    _log('check starting');

    if (_running) {
      _log('SKIP: a card is already running');
      return;
    }

    // Citizens only. A guest is a Firebase anonymous user with no Supabase
    // session, so there is no stable id to record dismissals against — and an
    // unrecorded dismissal means the same card returns forever.
    final uid = _uid();
    if (uid == null) {
      _log('SKIP: no signed-in citizen (guest, signed out, or no session)');
      return;
    }

    final state = await _readState(uid);
    if (state == null) {
      _log('SKIP: could not read stored state');
      return;
    }
    _log(
      'state: ${state.shown.length} shown, ${state.dismissed.length} dismissed, '
      'lastSeen=${state.lastSeenAt ?? "never (first run)"}',
    );

    final List<EventModel> candidates;
    try {
      candidates = await EventsService.instance
          .fetchPopupCandidates()
          .timeout(kEventPopupQueryBudget);
    } catch (e) {
      // Offline, slow, or an RLS surprise. Any failure means no card: a
      // promotional popup must never surface an error to a citizen.
      _log('SKIP: query failed or timed out - $e');
      return;
    }

    final now = DateTime.now();
    _log('query returned ${candidates.length} upcoming event(s)');
    for (final c in candidates) {
      _log(
        '  - "${c.title}" featured=${c.isFeatured} status=${c.status.name} '
        'date=${c.eventDate.toIso8601String().substring(0, 10)} '
        'eligible=${isEligible(c, state, now)}',
      );
    }
    _log('cards shown today: ${cardsShownToday(state, now)} / $kMaxCardsPerDay');

    final picked = pickEvent(candidates, state, now);
    if (picked == null) {
      _log('SKIP: no event qualified — nothing to show');
      return;
    }

    if (!context.mounted) {
      _log('SKIP: the screen went away while deciding');
      return;
    }

    _log('SHOWING: "${picked.title}"');
    _show(context, uid, picked, candidates, state, now);
  }

  static void _show(
    BuildContext context,
    String uid,
    EventModel event,
    List<EventModel> candidates,
    EventPopupState state,
    DateTime now,
  ) {
    final overlay = Overlay.of(context, rootOverlay: true);

    _running = true;
    _entry = OverlayEntry(
      builder: (_) => _EventSlideInHost(
        event: event,
        onShown: () => _markShown(uid, event, candidates, state, now),
        onDismiss: () =>
            _markDismissed(uid, event.id, candidates, state.dismissed, now),
        onFinished: abandon,
      ),
    );
    overlay.insert(_entry!);
  }
}

/// The animated, gesture-handling, route-aware host for one card.
///
/// Separated from [EventSlideIn] because everything here needs a State: a
/// ticker for the entrance, a timer for the dwell, and subscriptions to both
/// the route observer and the app lifecycle.
class _EventSlideInHost extends StatefulWidget {
  final EventModel event;

  /// Called once the entrance has completed — the moment the card counts as
  /// genuinely seen.
  final VoidCallback onShown;

  /// Called when the citizen swipes it away or taps into it.
  final VoidCallback onDismiss;

  /// Called when the card is finished and the entry should be removed.
  final VoidCallback onFinished;

  const _EventSlideInHost({
    required this.event,
    required this.onShown,
    required this.onDismiss,
    required this.onFinished,
  });

  @override
  State<_EventSlideInHost> createState() => _EventSlideInHostState();
}

class _EventSlideInHostState extends State<_EventSlideInHost>
    with TickerProviderStateMixin, WidgetsBindingObserver, RouteAware {
  late final AnimationController _slide;
  late final AnimationController _dwell;

  /// Horizontal drag offset while a finger is down.
  double _dragX = 0;
  bool _dragging = false;

  /// True while a blocked route is on top. The overlay stays alive but renders
  /// nothing, so the card can come back when the citizen leaves that screen.
  bool _hidden = false;

  bool _leaving = false;
  bool _marked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _slide = AnimationController(vsync: this, duration: kEventPopupEnter);
    _dwell = AnimationController(vsync: this, duration: kEventPopupDwell);

    _slide.addStatusListener((status) {
      if (status != AnimationStatus.completed || _marked) return;
      // The event counts as SHOWN only now. A citizen who navigated away at
      // 1000ms saw nothing, and the event must still be waiting for them.
      _marked = true;
      widget.onShown();
      _dwell.forward();
    });

    _dwell.addStatusListener((status) {
      if (status == AnimationStatus.completed) _exit();
    });

    _slide.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is ModalRoute<void>) {
      homeRouteObserver.subscribe(this, route);
    }
    _syncBlocked();
  }

  @override
  void dispose() {
    homeRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _slide.dispose();
    _dwell.dispose();
    super.dispose();
  }

  // ── Route awareness ────────────────────────────────────────────────────────
  //
  // The card RIDES ACROSS routes rather than being cancelled by them, so these
  // callbacks only re-check the blocklist. The dwell is never restarted: its 8
  // seconds are its own, wherever the citizen happens to be.

  @override
  void didPush() => _syncBlocked();
  @override
  void didPopNext() => _syncBlocked();
  @override
  void didPushNext() => _syncBlocked();
  @override
  void didPop() => _syncBlocked();

  void _syncBlocked() {
    final name = ModalRoute.of(context)?.settings.name;
    final blocked = name != null && kEventPopupBlockedRoutes.contains(name);
    if (blocked == _hidden) return;

    setState(() => _hidden = blocked);

    // The dwell keeps running while hidden on purpose: a card the citizen
    // could not see should not outstay its welcome once they come back, and
    // holding it indefinitely would mean an event ambushing them minutes later.
    if (blocked) {
      _dwell.stop();
    } else if (_marked && !_leaving) {
      _dwell.forward();
    }
  }

  // ── App lifecycle ──────────────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // Never let the 8 seconds elapse in a pocket.
      _dwell.stop();
    } else if (state == AppLifecycleState.resumed &&
        _marked &&
        !_leaving &&
        !_hidden &&
        !_dragging) {
      _dwell.forward();
    }
  }

  // ── Exit ───────────────────────────────────────────────────────────────────

  Future<void> _exit({bool instant = false}) async {
    if (_leaving) return;
    _leaving = true;
    _dwell.stop();

    if (instant) {
      widget.onFinished();
      return;
    }

    _slide.duration = kEventPopupExit;
    await _slide.reverse();
    widget.onFinished();
  }

  void _open() {
    if (_leaving) return;
    // Opening counts as engaging with it: this event is finished either way.
    widget.onDismiss();

    final ctx = context;
    _exit(instant: true);

    // Pushed ON TOP of wherever the citizen was, so back returns them to the
    // exact screen and scroll position they left.
    //
    // EventItem, not EventModel. The `/event_detail` route casts its argument
    // to EventItem — the screen's own UI model — so handing it the Supabase
    // EventModel is a failed cast that renders a blank screen with no visible
    // error. EventItem.fromModel is the conversion the Events list already
    // uses for exactly this hop.
    pushLegacy(
      ctx,
      '/event_detail',
      arguments: {
        'event': EventItem.fromModel(widget.event),
        // Stored but unread by EventDetailScreen. Left empty rather than
        // threaded through from Home, because the card is app-wide and has no
        // reliable Home context to read a username from.
        'username': '',
        // The popup is the ONE entry point that earns the "View more events"
        // link: it drops the citizen into a single event with no list behind
        // it, so without this their only move is Back to wherever they were.
        'showMoreEventsLink': true,
      },
    );
  }

  void _dismiss() {
    if (_leaving) return;
    widget.onDismiss();
    _exit();
  }

  // ── Drag ───────────────────────────────────────────────────────────────────

  void _onDragStart(DragStartDetails _) {
    if (_leaving) return;
    _dragging = true;
    // Pause while a finger is down: a slow reader must never be cut off
    // mid-swipe.
    _dwell.stop();
  }

  void _onDragUpdate(DragUpdateDetails d, double width) {
    if (_leaving || !_dragging) return;
    setState(() {
      // Rightward is the dismiss direction; leftward resists so the gesture
      // reads as one-way without being hard-blocked.
      final next = _dragX + d.delta.dx;
      _dragX = next < 0 ? next / 4 : next;
    });
  }

  void _onDragEnd(DragEndDetails d, double width) {
    if (_leaving || !_dragging) return;
    _dragging = false;

    final past = _dragX > width * kEventPopupSwipeFraction;
    final flung = d.velocity.pixelsPerSecond.dx > 700;

    if (past || flung) {
      _dismiss();
      return;
    }

    setState(() => _dragX = 0);
    if (_marked && !_hidden) _dwell.forward();
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();

    final media = MediaQuery.of(context);
    // viewPadding, not padding: the app's bottom bar is drawn UNDERNEATH the
    // Android system navigation (targetSdk 36 forces edge-to-edge), so this is
    // the only thing that says how much of the bottom is covered. In landscape
    // the 3-button bar moves to a SIDE and .right becomes ~48 instead.
    final viewPad = media.viewPadding;
    final width = EventSlideInCard.widthFor(context);

    return Positioned(
      right: 14 + viewPad.right,
      bottom: kBottomNavigationBarHeight + viewPad.bottom + 12,
      child: AnimatedBuilder(
        animation: Listenable.merge([_slide, _dwell]),
        builder: (context, child) {
          final t = Curves.easeOutCubic.transform(_slide.value);
          final offset = (1 - t) * (width + 40) + _dragX;
          final fade = _dragX > 0
              ? (1 - (_dragX / (width * 0.9))).clamp(0.0, 1.0)
              : 1.0;

          return Transform.translate(
            offset: Offset(offset, 0),
            child: Opacity(opacity: _slide.value * fade, child: child),
          );
        },
        child: GestureDetector(
          // Horizontal only: a vertical drag must pass through to the page
          // underneath, which is what stops the card from eating scrolls.
          onHorizontalDragStart: _onDragStart,
          onHorizontalDragUpdate: (d) => _onDragUpdate(d, width),
          onHorizontalDragEnd: (d) => _onDragEnd(d, width),
          child: Material(
            color: Colors.transparent,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1A000000),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 30,
                    offset: Offset(0, 12),
                    spreadRadius: -10,
                  ),
                ],
              ),
              child: EventSlideInCard(
                event: widget.event,
                onTap: _open,
                dwellRemaining: _marked && !_dragging
                    ? 1 - _dwell.value
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
