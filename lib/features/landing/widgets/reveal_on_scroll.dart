import 'dart:async';

import 'package:flutter/material.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Scroll-triggered entrance animation.
//
//  ── What it does ───────────────────────────────────────────────────────────
//  A child wrapped in [RevealOnScroll] starts invisible and slightly low, and
//  fades up into place the first time it enters the viewport. It NEVER plays in
//  reverse: once a section has been seen, scrolling back past it leaves it
//  alone. Re-animating on every pass is the single most common way this effect
//  turns from "polished" into "restless", and it also makes the page unusable
//  for anyone who scrolls up to re-read something.
//
//  ── Why a VisibilityDetector is not used ───────────────────────────────────
//  That would be another dependency for something the framework already
//  reports. This subscribes to the enclosing [Scrollable]'s ScrollPosition and
//  compares the child's own paint box against the live viewport on every tick —
//  see [_position] and [_check].
//
//  NOT a NotificationListener, which is the obvious way to write this and is
//  wrong: scroll notifications bubble UP from the Scrollable, so a listener
//  nested inside it never hears them. See the note on [_position].
//
//  ── Reduced motion ─────────────────────────────────────────────────────────
//  [MediaQuery.disableAnimationsOf] reports the OS "reduce motion" setting,
//  which on the web is `prefers-reduced-motion`. When it is on, the child is
//  rendered at its final position immediately — no fade, no travel, no
//  controller. This is not a nicety: motion sensitivity is a real
//  accessibility need, and a civic platform is exactly the kind of site that
//  must not make a citizen unwell to read it.
// ════════════════════════════════════════════════════════════════════════════

class RevealOnScroll extends StatefulWidget {
  final Widget child;

  /// How far the child rises as it fades in. Small on purpose: 24px reads as
  /// "settling into place", while the 60-80px travel that tutorials like turns
  /// a long page into a series of lurches.
  final double offset;

  /// Delay before this child begins, used to stagger siblings within a row.
  final Duration delay;

  final Duration duration;

  /// Fraction of the child's height that must be inside the viewport before it
  /// starts. 0.1 means "as soon as a tenth of it shows" — enough that the
  /// animation is visible rather than already finished when it scrolls in.
  final double visibleFraction;

  const RevealOnScroll({
    super.key,
    required this.child,
    this.offset = 24,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 620),
    this.visibleFraction = 0.1,
  });

  @override
  State<RevealOnScroll> createState() => _RevealOnScrollState();
}

class _RevealOnScrollState extends State<RevealOnScroll>
    with SingleTickerProviderStateMixin {
  // Created in [initState], NOT as a `late final` initialiser.
  //
  // A `late final` field is initialised on FIRST READ — and under reduced
  // motion [build] returns early, so nothing ever read it. The first read then
  // came from `dispose()`, which constructed an AnimationController against a
  // `vsync` whose element was already deactivated and threw "Looking up a
  // deactivated widget's ancestor is unsafe", failing the whole test tree.
  //
  // Building it up front costs one idle controller for a page that has at most
  // a few dozen, and removes the hazard entirely.
  late final AnimationController _controller;

  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _fade = CurvedAnimation(
      parent: _controller,
      // easeOut rather than easeInOut: the element should arrive decisively
      // and settle, not ease into its own start.
      curve: Curves.easeOut,
    );
    _slide =
        Tween<Offset>(
          // A unit tween, scaled to pixels in [build] — see the note there.
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(
            parent: _controller,
            // easeOutCubic gives the travel a little more deceleration than
            // the opacity, so the element comes to rest rather than stopping.
            curve: Curves.easeOutCubic,
          ),
        );
  }

  bool _started = false;

  /// The enclosing scroll view's position, subscribed to directly.
  ///
  /// ── Why not a NotificationListener ────────────────────────────────────────
  /// That was the original design and it never fired once. A
  /// [ScrollNotification] BUBBLES UP from the [Scrollable] toward the root, so
  /// only ancestors of the scroll view see it — and this widget is a
  /// DESCENDANT. The listener was below the very thing it was trying to hear,
  /// so every section past the first screen stayed at opacity 0 permanently,
  /// no matter how far the reader scrolled.
  ///
  /// It also cost nothing in any widget test that did not scroll, which is why
  /// it survived a green suite and only showed up in a real browser.
  ///
  /// [ScrollPosition] is a [Listenable] that ticks on every scroll frame, so
  /// subscribing to it is both correct and cheaper than notification bubbling.
  ScrollPosition? _position;

  /// Attaches to the nearest enclosing [Scrollable], detaching from any
  /// previous one. Called from [didChangeDependencies], which is what runs when
  /// the widget is moved or its inherited scroll view changes.
  ///
  /// Guarded on [mounted] because [didChangeDependencies] also fires as the
  /// element is being torn down, and [Scrollable.maybeOf] is an inherited-widget
  /// lookup — doing that on a deactivated element throws "Looking up a
  /// deactivated widget's ancestor is unsafe" and takes the whole tree with it.
  void _subscribe() {
    if (!mounted) return;
    final next = Scrollable.maybeOf(context)?.position;
    if (identical(next, _position)) return;
    _position?.removeListener(_onScroll);
    _position = next;
    _position?.addListener(_onScroll);
  }

  void _onScroll() => _check();

  /// The pending stagger delay, held so it can be CANCELLED on dispose.
  ///
  /// A bare `Future.delayed` was not enough. Its callback can be guarded with
  /// `mounted`, which keeps it from touching a dead State — but the TIMER
  /// itself stays alive and pending until it fires, and a timer that outlives
  /// the widget tree is a leak. It also fails any widget test that disposes the
  /// page inside the delay window, with "A Timer is still pending even after
  /// the widget tree was disposed" — which is exactly how this was found.
  Timer? _delayTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Under reduced motion [build] returns the child untouched and nothing is
    // ever animated, so there is nothing for a scroll subscription to drive.
    // Skipping it here also keeps this path from doing any inherited-widget
    // lookup at all, which is what the guard inside [_subscribe] protects.
    if (MediaQuery.disableAnimationsOf(context)) return;
    _subscribe();
  }

  @override
  void dispose() {
    _position?.removeListener(_onScroll);
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Starts the animation once, after [widget.delay].
  void _start() {
    if (_started) return;
    _started = true;
    if (widget.delay == Duration.zero) {
      _controller.forward();
      return;
    }
    _delayTimer = Timer(widget.delay, () {
      // The page can be scrolled away and disposed inside the delay.
      if (mounted) _controller.forward();
    });
  }

  /// True when enough of this widget's box overlaps the viewport.
  ///
  /// Measures the INTERSECTION of the child's box with the viewport, not merely
  /// whether its top edge is above the fold. An earlier version tested only
  /// `viewportHeight - top`, which is positive for anything scrolled off the
  /// TOP of the screen as well — so it answered "visible" for content the
  /// reader had already passed, and, worse, gave no correct answer at all for a
  /// child taller than the viewport.
  ///
  /// [viewportHeight] is read LIVE at each call rather than captured in
  /// [build]. See [_check].
  bool _isVisible(double viewportHeight) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return false;

    final top = box.localToGlobal(Offset.zero).dy;
    final height = box.size.height;
    if (height <= 0) return false;

    final bottom = top + height;
    final overlap =
        (bottom.clamp(0.0, viewportHeight)) - (top.clamp(0.0, viewportHeight));
    if (overlap <= 0) return false;

    // A section taller than the viewport can never show `visibleFraction` of
    // itself, so it would never start. Compare against whichever is smaller —
    // the child, or the screen it has to fit in.
    final reference = height < viewportHeight ? height : viewportHeight;
    return overlap >= reference * widget.visibleFraction;
  }

  /// Measures against the CURRENT viewport.
  ///
  /// ── Why the height is read here and not passed in ─────────────────────────
  /// It used to be captured once in [build] and handed to every later call.
  /// That was wrong in a way no widget test caught, because a widget test never
  /// scrolls a real viewport: `localToGlobal` returns SCREEN coordinates, which
  /// change on every scroll frame, so the comparison is only meaningful against
  /// the viewport as it is AT THAT MOMENT. Pairing live coordinates with a
  /// stale height meant the verdict for every section below the fold was
  /// computed against the wrong frame of reference, and they stayed invisible
  /// no matter how far the reader scrolled — the whole page below the hero was
  /// blank in a real browser.
  ///
  /// Reading it off the render view costs one lookup and cannot go stale.
  void _check() {
    // `mounted` guards the MediaQuery lookup below for the same reason
    // [_subscribe] guards its own: a scroll listener can fire while the element
    // is being torn down, and an inherited-widget lookup on a deactivated
    // element throws.
    if (_started || !mounted) return;
    final viewportHeight = MediaQuery.sizeOf(context).height;
    if (viewportHeight <= 0) return;
    if (_isVisible(viewportHeight)) _start();
  }

  /// How many post-layout frames to re-measure over before giving up and
  /// waiting for a scroll.
  ///
  /// Six is enough to outlast image decoding settling the page's heights, and
  /// small enough that an off-screen section costs almost nothing.
  static const int _maxChecks = 6;
  int _checksRun = 0;
  bool _checkScheduled = false;

  /// Measures after the current frame, and keeps measuring for a few frames
  /// while the page's layout is still settling. See the note in [build].
  void _scheduleCheck() {
    if (_started || _checkScheduled || _checksRun >= _maxChecks) return;
    _checkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScheduled = false;
      if (!mounted) return;
      _checksRun++;
      _check();
      if (!_started && _checksRun < _maxChecks) _scheduleCheck();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Honour the OS/browser reduced-motion setting: render the finished state.
    if (MediaQuery.disableAnimationsOf(context)) {
      return widget.child;
    }

    // The FIRST measurement has to happen after layout, because nothing above
    // knows this widget's position until it has one. Anything already on screen
    // at first paint therefore animates immediately, which is what makes the
    // hero and the top of the page animate on load with no separate code path.
    //
    // ── Why this retries, rather than measuring once ──────────────────────
    // A single post-frame check was not enough, and the failure was total: on
    // a real page load the hero's copy and every section below it stayed at
    // opacity 0 permanently.
    //
    // The first frame is laid out before the images have decoded, so sections
    // sit at positions that later change — and on a tall window there is no
    // scrollbar, so NO scroll notification ever arrives to correct the verdict.
    // The one measurement was taken against a layout that did not survive, and
    // nothing ever asked again. A page whose content is invisible until the
    // reader happens to scroll is worse than one with no animation at all.
    //
    // So this keeps asking for a few frames after mount. [_scheduleCheck] stops
    // itself the moment the answer is yes, and after [_maxChecks] regardless,
    // so an off-screen section costs a handful of cheap box lookups and then
    // nothing until it is actually scrolled to.
    _scheduleCheck();

    // No NotificationListener here: scroll is observed by subscribing to the
    // enclosing ScrollPosition instead. See [_position] for why the listener
    // could never have worked.
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _fade.value,
          child: Transform.translate(
            // The Tween runs 1 -> 0; scaling by the pixel offset here keeps
            // the travel a fixed distance regardless of the child's height.
            // A FractionalTranslation would make a tall section travel
            // further than a short one, which reads as inconsistent.
            offset: Offset(0, _slide.value.dy * widget.offset),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Staggers a list of children: each one reveals slightly after the last.
///
/// Used for rows of cards and the feature grid, where revealing all six at the
/// same instant looks like a single block appearing and reveals nothing about
/// the structure.
///
/// [step] is deliberately short. 70ms across three cards is 210ms end to end —
/// perceptible as a sweep, but finished before a reader has moved their eye.
List<Widget> staggered(
  List<Widget> children, {
  Duration step = const Duration(milliseconds: 70),
  double offset = 24,
}) {
  return <Widget>[
    for (final (index, child) in children.indexed)
      RevealOnScroll(delay: step * index, offset: offset, child: child),
  ];
}
