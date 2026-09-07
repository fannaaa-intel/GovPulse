part of 'quick_action_tutorial.dart';

/// The five steps, in the order they appear on the card.
///
/// Titles and accents are duplicated from HomeQuickActionsSection rather than
/// imported: the tour teaches a fixed script, and a silent copy-drift here is
/// caught by the widget test that asserts these match the section's list.
const List<_Step> _kSteps = [
  _Step(
    title: 'Report Issue',
    body:
        'Spotted a pothole, a broken streetlight, or uncollected garbage? '
        'Report it here with a photo and your location, and your LGU sees it '
        'right away.',
    accent: Color(0xFFEF4444),
  ),
  _Step(
    title: 'Chat with Agent',
    body:
        'Talk to an LGU support agent when you need help or have a question '
        'that is not a report.',
    accent: Color(0xFF3B82F6),
  ),
  _Step(
    title: 'Events',
    body:
        'Browse what is happening near you: barangay assemblies, clean-up '
        'drives, medical missions and more.',
    accent: Color(0xFF22C55E),
  ),
  _Step(
    title: 'Suggestion',
    body:
        'Have an idea to improve your community? Send it straight to the LGU '
        'here.',
    accent: Color(0xFF60A5FA),
  ),
  _Step(
    title: 'Feedback',
    body: 'Already used an LGU service? Rate it and tell them how it went.',
    accent: Color(0xFF8B5CF6),
  ),
];

class _Step {
  final String title;
  final String body;
  final Color accent;
  const _Step({required this.title, required this.body, required this.accent});
}

/// Below this height the float would leave no room for the caption, so the tour
/// keeps the card where it is and only spotlights.
const double _kFloatMinHeight = 640;

/// Vertical room the caption needs.
///
/// The caption is now a FIXED size — its body area is sized to the longest
/// step's copy — so this is one number for the whole tour rather than a
/// per-step measurement. Still only a starting estimate: the real height
/// depends on how the copy wraps at this width, and the layer measures it on
/// the first frame.
const double _kCaptionReserve = 228;

/// Gap between whatever the caption docks under and the caption itself. Shared
/// by the float maths and the caption's own placement so the two cannot
/// disagree about where the caption lands.
const double _kCaptionGap = 16;

/// Smallest gap between the status bar and the floated card. Centring gives
/// more than this on a tall phone; this is the floor on a short one.
const double _kMinTopInset = 12;

/// Gap between the caption and the bottom of the usable screen. Keeps the
/// caption a consistent distance off the gesture bar instead of hanging
/// directly under the card with dead space beneath it.
const double _kBottomInset = 20;

/// How dark the backdrop gets.
///
/// Heavy enough that the spotlit row is clearly the subject, light enough that
/// the page is still legible behind it — the tour is pointing at part of a
/// screen the citizen is meant to keep their bearings in, not replacing it.
const double _kScrimOpacity = 0.55;

/// The tour's own chrome colour.
///
/// Deliberately NOT the step's accent. Tinting the primary button per step made
/// it flash red, blue, green, blue, purple as the citizen tapped through, which
/// reads as five different buttons rather than one Next. The accent still marks
/// the step — in the caption's dot and the spotlight ring — where changing
/// colour is the point.
const Color _kChrome = Color(0xFF2563EB);

class _TutorialLayer extends StatefulWidget {
  final GlobalKey anchorKey;
  final Rect originRect;
  final VoidCallback onFinished;

  /// Scrolls the host page so the real card is on screen, and returns where it
  /// ended up. Run BEFORE the settle, so the floated copy can glide to the
  /// card's revealed position rather than to wherever it was when the tour
  /// started — which may by then be off-screen.
  final Future<Rect?> Function() onReveal;

  const _TutorialLayer({
    required this.anchorKey,
    required this.originRect,
    required this.onFinished,
    required this.onReveal,
  });

  @override
  State<_TutorialLayer> createState() => _TutorialLayerState();
}

/// The tour deliberately has NO lifecycle handling.
///
/// An earlier version ended the tour on background and marked it seen, so a
/// screen timeout or an incoming call destroyed it permanently rather than
/// pausing it. The overlay is not a route, so backgrounding does not tear it
/// down: it stays mounted on the same step and is simply there again when the
/// app resumes, which is what a citizen expects. Both animation controllers
/// have long since finished (the float settles in 520ms), so there is nothing
/// to suspend either.
class _TutorialLayerState extends State<_TutorialLayer>
    with TickerProviderStateMixin {
  /// Drives the float out and the settle back. 0 = card in its real position,
  /// 1 = card floated to the top of the screen.
  late final AnimationController _floatCtrl;

  /// Drives the scrim fade, independent of the float so the dim can come up
  /// while the card is still travelling.
  late final AnimationController _scrimCtrl;

  /// Fades the caption. Separate from the scrim so the caption can leave first
  /// on the way out, uncovering the card before it starts moving.
  late final AnimationController _captionCtrl;

  /// Slides the spotlight from the previous row to the current one.
  ///
  /// Without this the hole simply appeared on the next row: the eye has nothing
  /// to follow, and on Back it is not obvious the tour moved rather than
  /// re-rendered. Travelling makes the direction legible.
  late final AnimationController _spotCtrl;

  /// The row the spotlight is travelling FROM. Null on the first step.
  Rect? _previousRow;

  int _index = 0;
  bool _exiting = false;

  /// Row rects in global coordinates, measured from the real card once.
  List<Rect> _rowRects = const [];

  /// Where the card ends up after the host scrolls it into view. Null until the
  /// exit begins; from then on it is the settle's destination, replacing the
  /// rect the tour started from.
  Rect? _revealedRect;

  /// The card's floated position, decided ONCE.
  ///
  /// Everything feeding this — the caption's measured height, which of the two
  /// placement rules applies — settles over the first couple of frames. Left
  /// live, the card jumped the moment the real measurement replaced the
  /// estimate. Cached, the card is placed once and never moves again, which is
  /// the behaviour the tour is supposed to have.
  double? _floatDy;

  /// Measures the caption so the balance maths uses its REAL height.
  ///
  /// `_kCaptionReserve` is the tallest any step's caption gets. Using that
  /// figure to centre the group overstates it for the shorter steps, the slack
  /// collapses to its minimum, and the card ends up pinned to the top with dead
  /// space below — which is exactly what it did.
  final GlobalKey _captionKey = GlobalKey();
  double _captionHeight = 0;

  void _measureCaption() {
    final box = _captionKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final h = box.size.height;
    // GROWS ONLY. Each step's copy is a different length, and letting the
    // reserve shrink again would move the card between steps: the citizen sees
    // the whole card creep downward as the spotlight walks down it, which is
    // exactly the drift this replaced. One band, sized to the tallest step
    // seen, keeps the card still for the whole tour.
    if (h > _captionHeight + 0.5) {
      setState(() => _captionHeight = h);
    }
  }

  @override
  void initState() {
    super.initState();

    _floatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _scrimCtrl = AnimationController(
      vsync: this,
      // Arriving: quick, so the tour announces itself immediately.
      duration: const Duration(milliseconds: 260),
      // Leaving: matched to the float, so the dim lifts exactly as the card
      // lands rather than clearing early and leaving it sliding over a bright
      // page.
      reverseDuration: const Duration(milliseconds: 520),
    );
    _captionCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _spotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
      value: 1,
    );

    // Measure BEFORE anything moves, and only then start the float.
    //
    // The row rects decide which placement rule applies, so a float begun
    // before they exist starts from one position and is corrected to another a
    // frame later — the card visibly jumped between step 1 and step 2. Both
    // measurements land in this callback, ahead of the first animated frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _measureRows();
      _measureCaption();
      // A second frame so the caption's real height is in before the card's
      // resting place is computed and locked.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        setState(() {});

        // Staggered entrance. All three at once read as one abrupt event; in
        // sequence the tour dims the page, lifts the card out of it, then
        // brings the caption in under it — each beat explaining the next.
        _scrimCtrl.forward();
        _floatCtrl.forward();

        // The caption arrives once the card is most of the way up, so it is
        // not sliding around underneath a still-moving card.
        await Future<void>.delayed(const Duration(milliseconds: 260));
        if (!mounted) return;
        _captionCtrl.forward();
      });
    });
  }

  @override
  void dispose() {
    _floatCtrl.dispose();
    _scrimCtrl.dispose();
    _captionCtrl.dispose();
    _spotCtrl.dispose();
    super.dispose();
  }

  /// Walks the real card's render tree to find the five row rects.
  ///
  /// Reading the live geometry rather than recomputing it from the section's
  /// `width * 0.035` constants means the spotlight cannot drift when the card's
  /// padding changes: the section owns its layout, the tour just measures it.
  void _measureRows() {
    final ctx = widget.anchorKey.currentContext;
    if (ctx == null) return;

    final rects = <Rect>[];
    void visit(Element el) {
      if (el.widget is GestureDetector) {
        final b = el.renderObject;
        if (b is RenderBox && b.hasSize) {
          rects.add(b.localToGlobal(Offset.zero) & b.size);
        }
      }
      el.visitChildren(visit);
    }

    ctx.visitChildElements(visit);
    if (rects.length >= _kSteps.length) {
      // Sorted top-to-bottom so the tour order matches what the citizen sees,
      // independent of tree-walk order.
      rects.sort((a, b) => a.top.compareTo(b.top));
      _rowRects = rects.take(_kSteps.length).toList();
    }
  }

  void _next() {
    if (_index < _kSteps.length - 1) {
      _goTo(_index + 1);
    } else {
      _finish();
    }
  }

  void _back() {
    if (_index > 0) _goTo(_index - 1);
  }

  void _goTo(int next) {
    setState(() {
      _previousRow = _rowRects.isEmpty ? null : _rowRects[_index];
      _index = next;
    });
    // Restart the travel from 0 so the hole slides out of the old row and into
    // the new one, in whichever direction the citizen went.
    _spotCtrl.forward(from: 0);
    _afterStepChange();
  }

  /// Each step's copy is a different length, so the caption's height — and with
  /// it the balance of the whole group — changes as the citizen moves through.
  void _afterStepChange() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measureCaption();
    });
  }

  /// The single exit path. Every way out of the tour (Skip, the final "Got it",
  /// back-press, a lifecycle change) comes through here, which is what
  /// guarantees the card is never left floating.
  Future<void> _finish({bool immediate = false}) async {
    if (_exiting) return;
    _exiting = true;

    if (immediate) {
      widget.onFinished();
      return;
    }

    // The exit is one continuous motion, in three overlapping beats. Done
    // sequentially it read as three separate events: the caption vanishing, the
    // page scrolling, then the card jumping back.

    // 1. The caption leaves first, on its own short fade. It is the thing the
    //    citizen has finished with, and clearing it early uncovers the card
    //    before the card starts moving.
    await _captionCtrl.reverse();
    if (!mounted) {
      widget.onFinished();
      return;
    }

    // 2. Scroll the real card into view. The copy is still floating and still
    //    lit, so there is something to follow while the page moves.
    final revealed = await widget.onReveal();
    if (!mounted) {
      widget.onFinished();
      return;
    }
    setState(() => _revealedRect = revealed);

    // 3. Card and scrim travel together, on the SAME duration, so the dim
    //    lifts exactly as the card lands rather than clearing early and
    //    leaving the card sliding over an undimmed page.
    _scrimCtrl.reverse();
    await _floatCtrl.reverse();
    if (!mounted) {
      widget.onFinished();
      return;
    }
    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screen = media.size;
    final canFloat = screen.height >= _kFloatMinHeight;

    // The card and the caption are treated as ONE group and centred in the
    // usable band between the status bar and the gesture pill, so the leftover
    // room is split evenly above and below. Pinning the card hard to the top
    // instead left the whole bottom of the screen empty.
    final double safeTop = media.padding.top;
    final double safeBottom = media.padding.bottom;
    final double usable = screen.height - safeTop - safeBottom;
    // The caption is a fixed size for the whole tour, so this is one number.
    // It must ALSO be stable across the first frames: the layer starts with the
    // estimate and measures the real height a frame later, and if that switch
    // changed the answer the card visibly jumped once, right after step 1.
    // Taking the larger of the two makes the decision the same before and
    // after the measurement lands.
    final double captionH = math.max(_captionHeight, _kCaptionReserve);
    final double groupHeight =
        widget.originRect.height + _kCaptionGap + captionH;
    // Never less than a minimum inset: on a screen where the group barely fits,
    // the card should still clear the status bar rather than tuck under it.
    final double slack = ((usable - groupHeight) / 2).clamp(
      _kMinTopInset,
      double.infinity,
    );
    final double targetTop = safeTop + slack;

    double floatDy =
        _floatDy ??
        (canFloat
            ? (targetTop - widget.originRect.top).clamp(
                -widget.originRect.top,
                0.0,
              )
            : 0.0);

    // On a small phone the card and the caption cannot both fit: an iPhone SE
    // is 667pt tall and the card alone is ~532pt, leaving far less than the
    // caption needs. Floating the whole card to the top there would dock the
    // caption ON TOP of the rows it is describing.
    //
    // So when there is not enough room, the card floats only as far as it takes
    // to clear the CURRENT row above the caption. The spotlighted row is always
    // visible; the rows below it may be covered, which is the right thing to
    // give up — the citizen is being shown one row at a time anyway.
    final double captionRoom = captionH + media.padding.bottom;
    final bool cardFits =
        widget.originRect.height + captionRoom + targetTop <= screen.height;

    if (_floatDy == null && canFloat && !cardFits && _rowRects.isNotEmpty) {
      // The card is taller than the band left once the caption is reserved, so
      // not every row can sit above the caption at one card position.
      //
      // It still gets ONE position for the whole tour, chosen so the LAST row
      // clears the caption — every earlier row then clears it too, since they
      // are higher up. Recomputing this per step is what made the card creep
      // downward as the spotlight walked down it.
      final lastRow = _rowRects.last;
      final firstRow = _rowRects.first;
      final double captionPin = screen.height - captionRoom;
      final double maxRowBottom = captionPin - _kCaptionGap;

      // Lift enough for the last row to clear the caption...
      final double wanted = math.min(0.0, maxRowBottom - lastRow.bottom);
      // ...but never so far that the FIRST row leaves the top of the screen.
      // Anchoring on the last row alone overshoots and pushes step 1 off.
      final double limit = safeTop + _kMinTopInset - firstRow.top;

      floatDy = math.max(wanted, limit);
    }

    // Lock it in once the rows have been measured; from here the card is fixed
    // and only the spotlight moves.
    if (_floatDy == null && _rowRects.isNotEmpty) {
      _floatDy = floatDy;
    }

    return PopScope(
      canPop: false,
      // Back acts as Skip. Stepping backward would still need an exit at step
      // one, which puts two behaviours on one gesture.
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finish();
      },
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _floatCtrl,
          _scrimCtrl,
          _captionCtrl,
          _spotCtrl,
        ]),
        builder: (context, _) {
          // easeOutCubic arriving (decisive, lands softly); easeInOutCubic
          // leaving (eases away AND eases in, so the card does not yank off its
          // spotlighted position the instant the citizen taps Got it).
          final t = _exiting
              ? Curves.easeInOutCubic.transform(_floatCtrl.value)
              : Curves.easeOutCubic.transform(_floatCtrl.value);

          // The settle's destination is where the card ACTUALLY is now. The
          // host may have scrolled the page to reveal it, so the rect the tour
          // floated away from is stale by the time it glides back; landing on
          // it would drop the copy onto empty space.
          final base = _revealedRect ?? widget.originRect;
          // `floatDy` was measured against the original rect. Re-derive the
          // travel against the live one so the copy ends exactly on the card.
          final double travel = _revealedRect == null
              ? floatDy
              : (widget.originRect.top + floatDy) - base.top;
          final dy = travel * t;
          final cardRect = base.shift(Offset(0, dy));
          Rect? rowRect = _rowRects.isEmpty
              ? null
              : _rowRects[_index].shift(Offset(0, dy));
          // Glide from the previous row rather than reappearing on the next.
          final from = _previousRow;
          if (rowRect != null && from != null && _spotCtrl.value < 1) {
            rowRect = Rect.lerp(
              from.shift(Offset(0, dy)),
              rowRect,
              Curves.easeInOutCubic.transform(_spotCtrl.value),
            );
          }

          return Material(
            type: MaterialType.transparency,
            child: Stack(
              children: [
                // ORDER MATTERS. The card is painted FIRST and the scrim over
                // it, so the dim actually falls on the rows and the punched
                // hole reads as a spotlight. With the scrim underneath, the
                // card covered it completely and every row stayed equally lit —
                // the tour dimmed the page but never highlighted anything.
                Positioned(
                  left: cardRect.left,
                  top: cardRect.top,
                  width: cardRect.width,
                  height: cardRect.height,
                  child: const IgnorePointer(child: _CardGhost()),
                ),

                // Scrim with the spotlight punched out. Absorbs taps so the
                // page underneath cannot be operated mid-tour.
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _next,
                    child: CustomPaint(
                      // The key carries the live hole so a test can observe the
                      // spotlight travelling without reaching into the painter.
                      key: ValueKey<Rect>(rowRect ?? cardRect),
                      painter: _ScrimPainter(
                        hole: rowRect ?? cardRect,
                        opacity: _scrimCtrl.value * _kScrimOpacity,
                        accent: _kSteps[_index].accent,
                        glow: _scrimCtrl.value,
                      ),
                    ),
                  ),
                ),

                // Caption, docked below the whole card rather than chasing each
                // row: a caption that jumps per step is what makes these tours
                // feel restless.
                if (_captionCtrl.value > 0)
                  _Caption(
                    captionKey: _captionKey,
                    // Normally the caption docks below the WHOLE card, so it
                    // does not jump from step to step. When the card is too
                    // tall to fit, it docks against the spotlighted row instead
                    // — otherwise it would be pushed off the bottom of a small
                    // screen, or sit on top of the card.
                    cardBottom: cardFits || rowRect == null
                        ? cardRect.bottom
                        : rowRect.bottom,
                    // Only set in the cramped case: lets the caption flip ABOVE
                    // the row when there is not enough room below it.
                    rowTop: cardFits ? null : rowRect?.top,
                    screen: screen,
                    bottomInset: media.padding.bottom,
                    step: _kSteps[_index],
                    index: _index,
                    total: _kSteps.length,
                    opacity: _captionCtrl.value,
                    onNext: _next,
                    onBack: _index > 0 ? _back : null,
                    onSkip: _finish,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Paints the dim and cuts the spotlight hole.
///
/// `Path.combine(difference)` rather than a BlendMode.clear layer: clear needs
/// a saveLayer, which on Impeller costs an offscreen pass every frame of the
/// float.
class _ScrimPainter extends CustomPainter {
  final Rect hole;
  final double opacity;
  final Color accent;
  final double glow;

  _ScrimPainter({
    required this.hole,
    required this.opacity,
    required this.accent,
    required this.glow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;

    final rrect = RRect.fromRectAndRadius(
      hole.inflate(6),
      const Radius.circular(14),
    );

    final scrim = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRRect(rrect),
    );

    canvas.drawPath(
      scrim,
      Paint()..color = Colors.black.withValues(alpha: opacity),
    );

    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = accent.withValues(alpha: glow),
    );
  }

  @override
  bool shouldRepaint(_ScrimPainter old) =>
      old.hole != hole ||
      old.opacity != opacity ||
      old.accent != accent ||
      old.glow != glow;
}

/// The card drawn on the overlay during the tour.
///
/// Filled in by the caller through [QuickActionTutorial._ghostBuilder] so this
/// file does not need to import the Home widget tree.
class _CardGhost extends StatelessWidget {
  const _CardGhost();

  @override
  Widget build(BuildContext context) {
    final b = QuickActionTutorial._ghostBuilder;
    return b == null ? const SizedBox.shrink() : b(context);
  }
}

class _Caption extends StatelessWidget {
  final Key captionKey;
  final double cardBottom;

  /// Top of the spotlighted row, when the card is too tall for the caption to
  /// simply dock beneath it. Null means there is room below and no flip is
  /// needed.
  final double? rowTop;
  final Size screen;
  final double bottomInset;
  final _Step step;
  final int index;
  final int total;
  final double opacity;
  final VoidCallback onNext;
  final VoidCallback? onBack;
  final VoidCallback onSkip;

  const _Caption({
    required this.captionKey,
    required this.cardBottom,
    required this.rowTop,
    required this.screen,
    required this.bottomInset,
    required this.step,
    required this.index,
    required this.total,
    required this.opacity,
    required this.onNext,
    required this.onBack,
    required this.onSkip,
  });

  /// Height of the tallest step's body text at this width.
  ///
  /// Measured rather than hard-coded: the copy wraps differently on a 360pt
  /// phone than a 430pt one, so a constant would either clip the long steps or
  /// leave dead space on the wide ones.
  static double _tallestBody(double maxWidth) {
    var tallest = 0.0;
    for (final s in _kSteps) {
      final tp = TextPainter(
        text: TextSpan(
          text: s.body,
          style: const TextStyle(fontSize: 13, height: 1.35),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: maxWidth);
      if (tp.height > tallest) tallest = tp.height;
    }
    return tallest;
  }

  @override
  Widget build(BuildContext context) {
    final isLast = index == total - 1;
    // The caption spans the screen less its side margins, and the card's own
    // horizontal padding.
    final double bodyHeight = _tallestBody(screen.width - 32 - 32);
    // Narrow phones cannot fit all three buttons plus the dots.
    final bool tight = screen.width < 370;
    // Docked below the card, but never off-screen: on a short device the
    // caption sits above the bottom edge instead.
    // The caption docks under [cardBottom]. `_kCaptionReserve` is the tallest a
    // step's caption gets, so this is the lowest its top may sit and still fit.
    final double maxTop = (screen.height - bottomInset - _kCaptionReserve).clamp(
      0.0,
      screen.height,
    );

    // Docked under the card, but pushed down to sit a consistent distance off
    // the bottom when there is spare room. Leaving it directly under the card
    // put the caption mid-screen with a large dead band beneath it, which is
    // what made the layout look bottom-heavy and unbalanced.
    final double restingTop =
        screen.height - bottomInset - _kBottomInset - _kCaptionReserve;
    double top = math.max(cardBottom + _kCaptionGap, math.min(restingTop, maxTop));

    // On a small phone the card cannot rise far enough for every row to have
    // caption-room beneath it: an iPhone SE is 667pt tall, the card ~532pt, and
    // the card's own top is already pinned under the status bar. For the lower
    // rows the only honest place left is ABOVE the row, over the dimmed part of
    // the card. Flipping is better than the alternatives — covering the row
    // being described, or pushing the buttons off the bottom of the screen.
    if (top > maxTop && rowTop != null) {
      final double above = rowTop! - _kCaptionGap - _kCaptionReserve;
      if (above >= 0) {
        top = above;
      } else {
        top = top.clamp(0.0, maxTop);
      }
    } else {
      top = top.clamp(0.0, maxTop);
    }

    return Positioned(
      left: 16,
      right: 16,
      top: top,
      child: Opacity(
        opacity: opacity,
        child: Container(
          key: captionKey,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .18),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: step.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      step.title,
                      // One line always. "Chat with Agent" wrapped to two on a
                      // narrow phone while the other four did not, which made
                      // that one step's caption 23pt taller than the rest.
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                    ),
                  ),
                  Text(
                    '${index + 1} of $total',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // FIXED height, sized to the longest step's copy at the narrowest
              // phone. Left to wrap freely the caption was 227pt on step 1 and
              // 155pt by step 5 — the whole box visibly shrank on every tap,
              // and the buttons walked up the screen with it.
              SizedBox(
                height: bodyHeight,
                width: double.infinity,
                child: Text(
                  step.body,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: Color(0xFF4B5563),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  // The dots absorb the leftover width and clip if there is
                  // none. On a 375pt phone the three buttons plus five dots
                  // overflow a fixed row, and the buttons are the part that
                  // must stay tappable. One Expanded (not Flexible + Spacer,
                  // which both claim the free space and overflow anyway) keeps
                  // the buttons hard right.
                  Expanded(
                    child: ClipRect(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(total, (i) {
                          final active = i == index;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.only(right: 5),
                            width: active ? 18 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: active
                                  ? _kChrome
                                  : const Color(0xFFD1D5DB),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                  if (onBack != null)
                    TextButton(
                      onPressed: onBack,
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF6B7280),
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Back'),
                    ),
                  // Skip yields before the row can overflow: on a 360pt phone
                  // Back + Skip + Next together do not fit. Back and Next are
                  // the navigation; Skip is also reachable by back-press and by
                  // finishing, so it is the one that can go.
                  if (!isLast && !tight)
                    TextButton(
                      onPressed: onSkip,
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF6B7280),
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Skip'),
                    ),
                  const SizedBox(width: 4),
                  FilledButton(
                    onPressed: onNext,
                    style: FilledButton.styleFrom(
                      backgroundColor: _kChrome,
                      minimumSize: const Size(0, 38),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(isLast ? 'Got it' : 'Next'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
