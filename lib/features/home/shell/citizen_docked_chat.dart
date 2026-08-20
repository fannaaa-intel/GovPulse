import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/services/chat_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/citizen_ui.dart';
import '../../../core/widgets/Home/Chat-bubbles/chat_bubbles_widget.dart';
import '../../../core/widgets/Home/Chat-bubbles/chat_panel_card.dart';
import '../../../core/widgets/Home/nav/nav_band.dart'
    show kNavPhoneShortestSide, kNavTopBreakpoint;

// ════════════════════════════════════════════════════════════════════════════
//  Docked chat window for the citizen web shell — Messenger-style.
//
//  Pinned to the bottom-right, floating above the three columns, and
//  deliberately NOT a dialog or a route: there is no barrier and no dimmed
//  backdrop, so the feed keeps scrolling and every rail item stays clickable
//  while the chat is open. That is the whole difference from the modal it
//  replaces.
//
//  ── What this reuses ──────────────────────────────────────────────────────
//  Everything that matters. This file contains no chat logic at all:
//
//    • [ChatService.I] is the single source of truth for messages, sending,
//      history, staff hand-off and realtime — untouched.
//    • [HomeChatPanelCard] renders the whole thread and the input row, and is
//      already "a pure view that listens to the service". It is the same widget
//      the draggable global bubble uses, so the docked window and the bubble
//      cannot drift apart.
//    • The header — agent avatar, name, and the green Online / "Connected to a
//      person" subtitle — comes from that card too. It only needed somewhere to
//      put minimise and close, which is the `headerActions` slot.
//    • [ChatAgentAvatar] for the minimised pill.
//
//  What is new here is only the WINDOW: where it sits, how big it is, and the
//  open / minimised / closed state. Nothing about chat itself.
//
//  ── Why not reuse HomeChatBubble ──────────────────────────────────────────
//  The global bubble (main.dart's overlay) does something related but
//  incompatible: it is draggable, it has a delete zone, and it paints a
//  full-screen scrim (`Color(0x61000000)`) that swallows taps behind it. Inside
//  the shell that scrim is exactly wrong — the page has to stay live. So this
//  reuses the bubble's PANEL while leaving its chrome alone. The bubble itself
//  is untouched and still serves the mobile app and the live web route.
// ════════════════════════════════════════════════════════════════════════════

/// Window size for the DOCKED (wide) band. Roughly Messenger's: wide enough for
/// a readable thread, short enough to leave the feed visible behind it.
const double _kChatWidth = 360;
const double _kChatHeight = 520;

/// Distance from the viewport's bottom-right corner.
const double _kDockInset = 20;

/// Below this the docked card stops making sense and the window goes
/// full-screen instead. See [_CitizenDockedChatState.build].
///
/// Reuses [kNavPhoneShortestSide] rather than inventing a number: 600 is
/// already where this shell declares a viewport too narrow for normal chrome
/// (it is the same line the user chip collapses to avatar-only at).
const double _kFullScreenBelow = kNavPhoneShortestSide;

/// At and above this the minimised chat is the docked PILL; below it, a
/// draggable chat head.
///
/// Reuses [kNavTopBreakpoint] rather than inventing a number: 900 is already
/// where this shell stops being a desktop — it is the same line the top nav
/// gives way to the drawer band. So "the shell looks like a desktop" and "the
/// minimised chat looks like a docked window" are one decision, and a tablet
/// gets the head for the same reason it gets the drawer.
const double _kChatHeadBelow = kNavTopBreakpoint;

/// Horizontal space a message bubble can never occupy, subtracted before the
/// fraction below is applied: the message list's own padding (14 each side)
/// plus the avatar and its gap (28 + 7) on whichever side the bubble sits.
const double _kBubbleChrome = 63;

/// Share of the REMAINING width a bubble may take in the full-screen sheet.
/// A normal chat proportion; 240 is kept as a floor so this can only ever
/// widen a bubble, never narrow one.
const double _kSheetBubbleFraction = 0.70;

/// The card's own default, repeated here as the floor. Kept in sync by the
/// floor's purpose rather than by import: the point is that the sheet never
/// renders a bubble narrower than every other caller already gets.
const double _kBubbleFloor = 240;

/// Open / minimised / closed, owned by the shell so the window survives tab
/// switches and the "Chat with Agent" action can restore it.
enum DockedChatState { closed, open, minimised }

class CitizenDockedChat extends StatefulWidget {
  final DockedChatState state;

  /// Minimise ⇄ restore, and dismiss. The shell owns the state so that closing
  /// the window does not lose the conversation — [ChatService] keeps it either
  /// way, but the window position and the unread count live here.
  final VoidCallback onMinimise;
  final VoidCallback onRestore;
  final VoidCallback onClose;

  const CitizenDockedChat({
    super.key,
    required this.state,
    required this.onMinimise,
    required this.onRestore,
    required this.onClose,
  });

  @override
  State<CitizenDockedChat> createState() => _CitizenDockedChatState();
}

class _CitizenDockedChatState extends State<CitizenDockedChat>
    with TickerProviderStateMixin {
  /// Incoming messages that arrived while minimised. Cleared on restore.
  int _unread = 0;

  /// How many incoming messages this widget has already accounted for.
  ///
  /// The badge is a DELTA, not a total: what matters is how many arrived since
  /// the citizen last had the window open, and the conversation itself outlives
  /// every minimise. Keeping a watermark is also what makes the count survive a
  /// history reload — the list can grow by ten at once without ten badges.
  int _seenIncoming = 0;

  // ── Why this listens to the service, not to the chat panel ────────────────
  // The badge counts replies that arrive WHILE MINIMISED, and minimised is
  // exactly when the chat panel is not in the tree: [_window] and
  // [_fullScreenSheet] are only built in the open state, so the
  // `onAgentMessage` callback they carry can never fire at the one moment the
  // count exists to describe. That is why the pill's badge never appeared.
  //
  // [ChatService] is a [ChangeNotifier] that outlives all three states — it is
  // what keeps the conversation across a minimise in the first place — so
  // subscribing to it here is the only vantage point that is actually alive
  // when a reply lands. It also means the count is derived from the messages
  // themselves rather than from a callback that has to be re-wired into every
  // new host.

  @override
  void initState() {
    super.initState();
    ChatService.I.addListener(_onChatChanged);
    // A chat that opens with the shell is already open; it has no entrance to
    // play, and nothing to unmount.
    _windowMounted = widget.state == DockedChatState.open;
    // Start level with whatever is already in the conversation, so re-entering
    // a long history does not open with a badge for messages already read.
    _seenIncoming = _incomingCount();
  }

  @override
  void dispose() {
    ChatService.I.removeListener(_onChatChanged);
    _headSnapCtrl?.dispose();
    _headSpawnCtrl?.dispose();
    _windowCtrl?.dispose();
    super.dispose();
  }

  /// Messages from the bot or a live staff member — everything the citizen did
  /// not send themselves.
  int _incomingCount() => ChatService.I.messages.where((m) => !m.isUser).length;

  void _onChatChanged() {
    if (!mounted) return;
    final now = _incomingCount();

    // A shorter list means the conversation was cleared or replaced (a new
    // ticket, a fresh session). There is nothing unread about a history that no
    // longer exists, so drop the watermark to it rather than going negative.
    if (now < _seenIncoming) {
      setState(() {
        _seenIncoming = now;
        _unread = 0;
      });
      return;
    }

    if (widget.state == DockedChatState.minimised) {
      if (now > _seenIncoming) {
        setState(() => _unread += now - _seenIncoming);
      }
    } else if (_unread != 0) {
      // Open or closed: an open window is being read, and a closed one has no
      // pill to carry a badge.
      setState(() => _unread = 0);
    }
    _seenIncoming = now;
  }

  @override
  void didUpdateWidget(covariant CitizenDockedChat old) {
    super.didUpdateWidget(old);

    // ── The transitions between the three states ────────────────────────────
    // Each direction plays the motion that belongs to what is ARRIVING, so the
    // controllers stay owned by the thing they animate rather than by whatever
    // happened to be on screen before.
    if (widget.state != old.state) {
      if (widget.state == DockedChatState.open) {
        // Mount first, then grow — the window has to exist before it can
        // animate into existence.
        _windowMounted = true;
        _windowAnim.forward(from: 0);
      } else if (old.state == DockedChatState.open) {
        // Leaving the conversation, to the head or to nothing. Play it out and
        // unmount only when it has finished, so minimising and closing both
        // read as the window being put away rather than deleted.
        _windowAnim.reverse(from: 1).whenComplete(() {
          if (mounted) setState(() => _windowMounted = false);
        });
      }

      if (widget.state == DockedChatState.minimised) {
        // The head springs out at the same moment, not after — both layers are
        // mounted for the overlap. See [build].
        _initHeadControllers();
        _headNeedsSettle = true;
        _headSpawnCtrl!.forward(from: 0);
      }
    }

    if (widget.state == DockedChatState.open &&
        old.state != DockedChatState.open) {
      // Restoring IS seeing them. Re-level the watermark at the same time, or
      // the next minimise would re-count everything read in between.
      _unread = 0;
      _seenIncoming = _incomingCount();
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    // ── Narrow: full-screen sheet ──────────────────────────────────────────
    //
    // A 360-wide card docked 20px off the corner is a floating window when
    // there is a page to float over, and nothing but a cramped obstruction when
    // there is not. At 435 it covered 83% of the viewport while still drawing
    // itself as a corner card; below ~380 it simply clipped against the Stack
    // edge. Narrow gets the sheet idiom instead: edge to edge, square corners,
    // no dock inset.
    final fullscreen = size.width < _kFullScreenBelow;

    // Minimised below the desktop band is a chat head, not a pill — see
    // [_chatHeadLayer]. It places itself, so it does not take the dock corner.
    final headBand = size.width < _kChatHeadBelow;

    // Closed AND finished playing out: nothing at all.
    if (widget.state == DockedChatState.closed && !_windowMounted) {
      return const SizedBox.shrink();
    }

    // ── Both layers, so a transition can show both at once ─────────────────
    // The conversation and the thing it minimises into are two states of one
    // object, and the old build swapped them on a single frame — which is why
    // opening "just popped". Mounting both while the transition runs is what
    // lets the window shrink toward the corner at the same moment the head
    // springs out of it, instead of one being destroyed before the other is
    // built. [_windowMounted] is what keeps the window alive past the state
    // change for exactly as long as its exit takes.
    //
    // Neither layer is a barrier: the fill paints nothing and holds no gesture,
    // so the feed, the rails and the top nav keep receiving pointer events —
    // which is what makes this non-blocking where the old modal was not.
    return Positioned.fill(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (widget.state == DockedChatState.minimised)
            headBand
                ? _chatHeadLayer(context)
                : Positioned(
                    right: _kDockInset,
                    bottom: _kDockInset,
                    child: _spawnMinimised(_minimisedPill()),
                  ),
          if (_windowMounted)
            fullscreen
                ? Positioned.fill(
                    child: _riseFromDock(_fullScreenSheet(context)),
                  )
                : Positioned(
                    right: _kDockInset,
                    bottom: _kDockInset,
                    child: _growFromDock(_window()),
                  ),
        ],
      ),
    );
  }

  /// The narrow-band window: fills the viewport rather than floating in it.
  ///
  /// Size comes from MediaQuery and is reduced by the safe-area padding and the
  /// keyboard inset, so it can never exceed the viewport — which is what fixes
  /// both the below-380 horizontal clip and the latent short-window vertical
  /// clip the fixed 520 height carried.
  Widget _fullScreenSheet(BuildContext context) {
    final mq = MediaQuery.of(context);
    final pad = mq.padding;
    final w = mq.size.width - pad.left - pad.right;
    final h = mq.size.height - pad.top - pad.bottom - mq.viewInsets.bottom;

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: HomeChatPanelCard(
          panelW: w,
          panelH: h,
          // Square: the card meets every viewport edge, so rounded corners
          // would leave the page showing through in four notches.
          borderRadius: BorderRadius.zero,
          // The card's 240 default is right for a 360-wide docked window and
          // too narrow once the sheet spans the viewport. Widen it in
          // proportion to the space actually available to a bubble, floored at
          // 240 so the narrow end of the band is untouched.
          bubbleMaxWidth: math.max(
            _kBubbleFloor,
            (w - _kBubbleChrome) * _kSheetBubbleFraction,
          ),
          onAgentMessage: _onChatChanged,
          headerActions: [
            _headerButton(
              icon: Icons.remove_rounded,
              tooltip: 'Minimise',
              onTap: widget.onMinimise,
            ),
            _headerButton(
              icon: Icons.close_rounded,
              tooltip: 'Close chat',
              onTap: widget.onClose,
            ),
          ],
        ),
      ),
    );
  }

  Widget _window() {
    return Material(
      color: Colors.transparent,
      child: HomeChatPanelCard(
        panelW: _kChatWidth,
        panelH: _kChatHeight,
        onAgentMessage: _onChatChanged,
        headerActions: [
          _headerButton(
            icon: Icons.remove_rounded,
            tooltip: 'Minimise',
            onTap: widget.onMinimise,
          ),
          _headerButton(
            icon: Icons.close_rounded,
            tooltip: 'Close chat',
            onTap: widget.onClose,
          ),
        ],
      ),
    );
  }

  Widget _headerButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 18,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 18, color: CitizenUi.textMuted),
        ),
      ),
    );
  }

  /// Collapsed state: a compact bar that keeps the conversation one click away
  /// and shows how many agent messages landed while it was away.
  // ── Chat head (narrow bands only) ─────────────────────────────────────────
  //
  //  Mirrors the mobile app's [HomeChatBubble] — the same 58px blue circle with
  //  the white agent glyph, the same online dot, the same red delete zone it is
  //  dropped on to dismiss, and the same motion: a spring on the way in, an
  //  eased snap back to whichever edge it was let go nearest.
  //
  //  ── Why the pill is wrong below the desktop band ────────────────────────
  //  The pill is 280px of avatar, name and a close button. On a laptop it sits
  //  in dead space in the corner and reads as a docked window that happens to
  //  be rolled up — which is exactly what it is. On a phone, 280px is most of
  //  the width: it stops being a marker for a window and becomes a bar across
  //  the bottom of the page, permanently covering whatever is under it, in the
  //  one band where there is least room to spare. A head is 58px, moves out of
  //  the way when it is in the way, and is the idiom every phone user already
  //  knows.
  //
  //  ── Mirrored, not imported ──────────────────────────────────────────────
  //  [HomeChatBubble] paints a full-screen scrim that swallows taps behind it
  //  (see this file's header), which is exactly wrong inside the shell — the
  //  page has to stay live. So the LOOK and the MOTION are reproduced here and
  //  the widget is not imported. What can be shared safely is: [ChatOnlineDot]
  //  is the same widget, and the glyph is the same asset at the same fraction.
  //  The mobile app and the live web route are untouched.

  /// Diameter of the head. The mobile bubble's `_bubbleSize`.
  static const double _kHeadSize = 58;

  /// Gap between the head and the viewport edge it snaps to.
  static const double _kHeadMargin = 12;

  /// The mobile bubble's `_dotSize`, so the online dot lands in the same place
  /// relative to the circle.
  static const double _kDotSize = 14;

  /// The delete zone's two sizes — the mobile bubble's `_deleteNormal` and
  /// `_deleteHover`.
  static const double _kDeleteNormal = _kHeadSize + 2;
  static const double _kDeleteHover = _kHeadSize + 8;

  /// How far up from the bottom the delete zone sits. The mobile bubble's 88.
  static const double _kDeleteBottom = 88;

  /// Where the head sits, in viewport coordinates. Null until the first layout
  /// has a size to place it against.
  double? _headLeft;
  double? _headTop;

  /// A drag in progress, and whether it is currently over the delete zone.
  bool _headDragging = false;
  bool _headOverDelete = false;

  /// Set when the head (re)appears, and cleared by the first layout that acts
  /// on it.
  ///
  /// A head only ever RESTS against a side — the middle is somewhere it passes
  /// through, never somewhere it stops. Coming back from the conversation is an
  /// appearance like any other, so it re-settles rather than reappearing at
  /// whatever coordinate it happened to hold. Deferred to layout because the
  /// decision needs the box's real width, which [didUpdateWidget] does not
  /// have.
  bool _headNeedsSettle = false;

  /// Drives the eased snap back to an edge once the head is let go.
  ///
  /// A `setState` that simply assigns the new left would TELEPORT the head to
  /// the edge; what makes it feel like a physical thing is that it travels
  /// there. Same controller shape and same curve as the mobile bubble's
  /// `_animateTo`.
  AnimationController? _headSnapCtrl;
  Animation<double>? _headSnapLeft;
  Animation<double>? _headSnapTop;

  /// Drives the spring the head arrives on, and the shrink it leaves on.
  AnimationController? _headSpawnCtrl;

  /// Whether the conversation is still in the tree.
  ///
  /// Not the same as `state == open`. Leaving the conversation has to be SEEN,
  /// and a widget the shell has already stopped asking for cannot animate
  /// itself away — so this stays true from the moment the state leaves `open`
  /// until the exit finishes, and the window is unmounted then rather than on
  /// the frame the state changed.
  bool _windowMounted = false;

  /// Drives the window growing out of the corner it was minimised into.
  ///
  /// Open and minimised are two shapes of one thing, and swapping them on a
  /// single frame reads as one widget being destroyed and another appearing
  /// somewhere else. Growing from the dock corner is what makes it read as the
  /// SAME conversation being unrolled — which is the whole promise the head
  /// makes when it sits there holding an unread count.
  AnimationController? _windowCtrl;

  void _initHeadControllers() {
    _headSnapCtrl ??=
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 320),
        )..addListener(() {
          final l = _headSnapLeft, t = _headSnapTop;
          if (l == null || t == null) return;
          setState(() {
            _headLeft = l.value;
            _headTop = t.value;
          });
        });

    _headSpawnCtrl ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
      reverseDuration: const Duration(milliseconds: 200),
      value: 1,
    );
  }

  /// Created on demand, but seeded to wherever the chat already is — so a
  /// widget that mounts straight into the open state does not play an entrance
  /// for something that was never closed.
  AnimationController get _windowAnim {
    return _windowCtrl ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 200),
      value: widget.state == DockedChatState.open ? 1 : 0,
    );
  }

  /// Seeds the head's position the first time, and keeps it inside the
  /// viewport afterwards.
  ///
  /// The clamp is not defensive dressing: a browser window is resized far more
  /// often than a phone is rotated, and a head parked against the right edge of
  /// a 1200px window is off-screen entirely at 500px. Re-clamping on every
  /// layout is what stops a narrowing window from stranding it.
  void _ensureHeadPosition(Size screen) {
    final maxLeft = math.max(
      _kHeadMargin,
      screen.width - _kHeadSize - _kHeadMargin,
    );
    final maxTop = math.max(
      _kHeadMargin,
      screen.height - _kHeadSize - _kHeadMargin,
    );
    if (_headLeft == null || _headTop == null) {
      // Right-hand side, a little above the middle — the mobile bubble's own
      // opening position, and the corner the docked window used.
      _headLeft = maxLeft;
      _headTop = screen.height * 0.44;
      _headNeedsSettle = false;
    }
    // Never fight a snap in flight; it is already heading somewhere legal.
    if (_headSnapCtrl?.isAnimating ?? false) return;
    _headLeft = _headLeft!.clamp(_kHeadMargin, maxLeft);
    _headTop = _headTop!.clamp(_kHeadMargin, maxTop);

    // Reappearing: put it back against whichever side it is nearer, so the head
    // is never left standing in open space. Not animated — this is where it
    // ARRIVES, and travelling there from a position it was never seen in would
    // be motion with nothing behind it.
    if (_headNeedsSettle) {
      _headNeedsSettle = false;
      _headLeft = (_headLeft! + _kHeadSize / 2) < screen.width / 2
          ? _kHeadMargin
          : maxLeft;
    }
  }

  /// Travels the head to [left], [top] instead of jumping it there.
  void _animateHeadTo(double left, double top) {
    final ctrl = _headSnapCtrl!;
    ctrl.stop();
    _headSnapLeft = Tween<double>(
      begin: _headLeft,
      end: left,
    ).animate(CurvedAnimation(parent: ctrl, curve: Curves.easeOutCubic));
    _headSnapTop = Tween<double>(
      begin: _headTop,
      end: top,
    ).animate(CurvedAnimation(parent: ctrl, curve: Curves.easeOutCubic));
    ctrl.forward(from: 0);
  }

  /// Lets go of the head: dismiss if it was dropped on the delete zone,
  /// otherwise snap to whichever side it is nearest.
  void _onHeadDragEnd(Size screen) {
    if (_headOverDelete) {
      setState(() {
        _headDragging = false;
        _headOverDelete = false;
      });
      // Shrink out before the shell drops the widget, so dismissing reads as
      // the head being put away rather than as it blinking off.
      _headSpawnCtrl!.reverse().whenComplete(() {
        if (!mounted) return;
        _headSpawnCtrl!.value = 1;
        widget.onClose();
      });
      return;
    }
    final mid = (_headLeft ?? 0) + _kHeadSize / 2;
    setState(() => _headDragging = false);
    _animateHeadTo(
      mid < screen.width / 2
          ? _kHeadMargin
          : screen.width - _kHeadSize - _kHeadMargin,
      _headTop!,
    );
  }

  bool _isOverDelete(Size screen) {
    final centre = Offset(
      _headLeft! + _kHeadSize / 2,
      _headTop! + _kHeadSize / 2,
    );
    final target = Offset(
      screen.width / 2,
      screen.height - _kDeleteBottom - _kDeleteNormal / 2,
    );
    // Generous radius: requiring a precise overlap would make dismissing a game
    // of accuracy on the surface with the least pointing precision.
    return (centre - target).distance < 62;
  }

  /// True when the head is on the LEFT half of the viewport.
  ///
  /// Decided by the head's CENTRE against the midpoint, not by its left edge
  /// against zero: a head snapped to the left rests at [_kHeadMargin], never at
  /// 0, so an `x < 1` test would report "right" for every position it can
  /// actually come to rest in — and the badge would sit off the viewport on the
  /// one side where it matters.
  bool _isHeadOnLeft(Size screen) =>
      (_headLeft ?? 0) + _kHeadSize / 2 < screen.width / 2;

  /// The whole narrow-band minimised state: the head, plus the delete zone that
  /// only exists while it is being dragged.
  ///
  /// [Positioned.fill] rather than a corner [Positioned], because the head moves
  /// anywhere in the viewport and the zone is centred at the bottom. Neither
  /// child is a barrier — the fill paints nothing and holds no gesture — so the
  /// feed behind stays live exactly as it does with the pill.
  Widget _chatHeadLayer(BuildContext context) {
    _initHeadControllers();

    return Positioned.fill(
      // ── Measure the BOX, never MediaQuery ────────────────────────────────
      // The head's left/top are coordinates in this [Positioned.fill]'s own
      // space, so the width it snaps against has to be that box's width. It is
      // NOT `MediaQuery.sizeOf`: the shell overrides the reported size for its
      // columns (see citizen_shell's centre-column MediaQuery, and
      // ResponsiveNavScaffold's constrained body), so on those subtrees the
      // query answers with a width the Stack does not have. Seeding "the right
      // edge" from a width narrower than the real one is what parked the head
      // in the middle of the page after a minimise instead of against a side.
      //
      // `constraints.biggest` is the box itself and cannot disagree with it, at
      // any nesting, under any override.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final screen = constraints.biggest;
          _ensureHeadPosition(screen);
          return _chatHeadStack(screen);
        },
      ),
    );
  }

  Widget _chatHeadStack(Size screen) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // ── The delete zone ─────────────────────────────────────────────
        // Faded rather than added and removed, so it arrives and leaves
        // smoothly instead of popping into the layout mid-drag.
        Positioned(
          bottom: _kDeleteBottom,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: _headDragging ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 180),
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: _headOverDelete ? _kDeleteHover : _kDeleteNormal,
                  height: _headOverDelete ? _kDeleteHover : _kDeleteNormal,
                  decoration: BoxDecoration(
                    color: _headOverDelete
                        ? Colors.red
                        : Colors.red.withValues(alpha: 0.75),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.delete_rounded,
                    color: Colors.white,
                    size: _headOverDelete ? 26 : 22,
                  ),
                ),
              ),
            ),
          ),
        ),

        // ── The head ────────────────────────────────────────────────────
        Positioned(left: _headLeft, top: _headTop, child: _chatHead(screen)),
      ],
    );
  }

  Widget _chatHead(Size screen) {
    // A spring on the way in and a shrink on the way out, both from one
    // controller — the mobile bubble's `_bubbleSpawn` scale/opacity pair.
    final spawn = CurvedAnimation(
      parent: _headSpawnCtrl!,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onRestore,
        onPanStart: (_) {
          _headSnapCtrl!.stop();
          setState(() => _headDragging = true);
        },
        onPanUpdate: (d) {
          setState(() {
            _headLeft = (_headLeft ?? 0) + d.delta.dx;
            _headTop = (_headTop ?? 0) + d.delta.dy;
            _headOverDelete = _isOverDelete(screen);
          });
        },
        onPanEnd: (_) => _onHeadDragEnd(screen),
        onPanCancel: () => _onHeadDragEnd(screen),
        child: AnimatedBuilder(
          animation: spawn,
          builder: (_, child) => Opacity(
            opacity: spawn.value.clamp(0.0, 1.0),
            child: Transform.scale(
              scale: spawn.value.clamp(0.0, 1.2),
              alignment: Alignment.center,
              child: child,
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // The circle. Blue normally, red and 15% larger over the delete
              // zone — the mobile bubble's own two states.
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: _headOverDelete ? _kHeadSize * 1.15 : _kHeadSize,
                height: _headOverDelete ? _kHeadSize * 1.15 : _kHeadSize,
                decoration: BoxDecoration(
                  color: _headOverDelete ? Colors.red : AppColors.primaryBlue,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color:
                          (_headOverDelete ? Colors.red : AppColors.primaryBlue)
                              .withValues(alpha: _headDragging ? 0.40 : 0.28),
                      blurRadius: _headDragging ? 18 : 14,
                      offset: Offset(0, _headDragging ? 8 : 5),
                    ),
                  ],
                ),
                child: Center(
                  child: Image.asset(
                    'assets/images/customer.webp',
                    width: _kHeadSize * 0.50,
                    height: _kHeadSize * 0.50,
                    color: Colors.white,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.support_agent_rounded,
                      color: Colors.white,
                      size: _kHeadSize * 0.50,
                    ),
                  ),
                ),
              ),

              // Online dot, same widget and same offsets as the mobile bubble.
              const Positioned(
                bottom: -_kDotSize / 2 + _kHeadSize * 0.15,
                right: -_kDotSize / 2 + _kHeadSize * 0.15,
                child: ChatOnlineDot(),
              ),

              // ── The unread count ────────────────────────────────────────
              // The mobile badge's look — an 18px red disc ringed in white,
              // springing in on `elasticOut` — but carrying the NUMBER rather
              // than a bare "!", which is the whole point of counting. It sits
              // on whichever side is away from the viewport edge, so parking the
              // head on the left does not push the badge off-screen.
              if (_unread > 0)
                Positioned(
                  top: -4,
                  right: _isHeadOnLeft(screen) ? null : -4,
                  left: _isHeadOnLeft(screen) ? -4 : null,
                  child: TweenAnimationBuilder<double>(
                    key: ValueKey(_unread),
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.elasticOut,
                    builder: (_, v, child) =>
                        Transform.scale(scale: v, child: child),
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 20),
                      height: 20,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Text(
                        _unread > 9 ? '9+' : '$_unread',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Raises [child] into place from the bottom of the viewport.
  ///
  /// The phone's counterpart to [_growFromDock]. A full-screen sheet has no
  /// corner to grow out of — it IS the screen — so scaling it from a corner
  /// would read as the page zooming rather than as a sheet arriving. It rises
  /// instead, which is the motion every full-screen sheet on a phone makes, and
  /// the one that says "this came from the bottom, and that is where it goes
  /// back to".
  ///
  /// The three channels are deliberately not the same curve: the fade leads so
  /// the sheet is already legible while it is still settling, and the slide
  /// carries most of the distance. The slight scale is what stops it feeling
  /// like a card being pushed on a rail.
  Widget _riseFromDock(Widget child) {
    return AnimatedBuilder(
      animation: _windowAnim,
      builder: (_, inner) {
        final v = _windowAnim.value.clamp(0.0, 1.0);
        final slide = Curves.easeOutCubic.transform(v);
        final fade = Curves.easeOut.transform(math.min(1.0, v * 1.35));
        return Opacity(
          opacity: fade,
          child: Transform.translate(
            offset: Offset(0, (1 - slide) * 56),
            child: Transform.scale(
              scale: 0.98 + 0.02 * slide,
              alignment: Alignment.bottomCenter,
              child: inner,
            ),
          ),
        );
      },
      child: child,
    );
  }

  /// Springs [child] in as the minimised affordance arrives.
  ///
  /// Driven by the HEAD's spawn controller rather than the window's, and the
  /// distinction is not cosmetic: [_growFromDock] maps the window's progress
  /// straight onto opacity, so a pill wrapped in it would fade out in step with
  /// the window and then sit at zero — invisible, in the state whose entire job
  /// is to be the thing you can still see. The two controllers run over the
  /// same moment in opposite directions, which is what makes the swap a cross-
  /// fade rather than a blink.
  ///
  /// The head does not go through this: it applies the same controller itself,
  /// inside [_chatHead], because it also has a drag scale to compose with.
  Widget _spawnMinimised(Widget child) {
    _initHeadControllers();
    return AnimatedBuilder(
      animation: _headSpawnCtrl!,
      builder: (_, inner) {
        final v = _headSpawnCtrl!.value.clamp(0.0, 1.0);
        return Opacity(
          opacity: v,
          child: Transform.scale(
            scale: 0.92 + 0.08 * v,
            alignment: Alignment.bottomRight,
            child: inner,
          ),
        );
      },
      child: child,
    );
  }

  /// Grows [child] out of the dock corner, and shrinks it back into it.
  ///
  /// Anchored bottom-right because that is where the head and the pill both
  /// sit, so the window appears to unroll from the thing that was just there
  /// rather than from the middle of the page — and, on the way out, to fold
  /// back into the thing that replaces it. Scale starts at 0.9 rather than 0,
  /// since a window that grows from nothing reads as a notification popping up;
  /// this reads as one being unfolded.
  ///
  /// The pill goes through it too. It is the wide band's minimised state, so it
  /// arrives exactly when the window leaves, and giving it the same fade means
  /// the two cross over instead of one blinking in on top of the other.
  Widget _growFromDock(Widget child) {
    return AnimatedBuilder(
      animation: _windowAnim,
      builder: (_, inner) {
        final v = _windowAnim.value.clamp(0.0, 1.0);
        final t = Curves.easeOutCubic.transform(v);
        return Opacity(
          opacity: t,
          child: Transform.scale(
            scale: 0.9 + 0.1 * t,
            alignment: Alignment.bottomRight,
            child: inner,
          ),
        );
      },
      child: child,
    );
  }

  Widget _minimisedPill() {
    final connected = ChatService.I.isConnectedToStaff;
    final name = connected
        ? (ChatService.I.connectedStaffName?.trim().isNotEmpty ?? false)
              ? ChatService.I.connectedStaffName!.trim()
              : 'LGU Staff'
        : 'LGU Aparri Agent';

    return Material(
      color: CitizenUi.surface,
      elevation: 8,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: widget.onRestore,
        child: Container(
          height: 52,
          constraints: const BoxConstraints(maxWidth: 280),
          padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: CitizenUi.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ChatAgentAvatar(
                size: 34,
                photoUrl: connected
                    ? ChatService.I.connectedStaffPhotoUrl
                    : null,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: CitizenUi.textPrimary,
                  ),
                ),
              ),
              if (_unread > 0) ...[
                const SizedBox(width: 8),
                Container(
                  constraints: const BoxConstraints(minWidth: 20),
                  height: 20,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: CitizenUi.badge,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _unread > 9 ? '9+' : '$_unread',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 4),
              _headerButton(
                icon: Icons.close_rounded,
                tooltip: 'Close chat',
                onTap: widget.onClose,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
