import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../theme/citizen_ui.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Quick-action split panel — the citizen WEB modal chrome.
//
//  A quick action opened from the citizen web shell is a two-column working
//  surface: a wide LEFT panel that holds the actual work (a stepper, an
//  instruction block, the form sections) and a narrower RIGHT rail that
//  summarises what has been filled in and carries the buttons.
//
//  ── Why this file exists ──────────────────────────────────────────────────
//  The four quick-action forms (Report, Suggestion, Feedback, Events) are the
//  SAME widgets the mobile app pushes as full pages. Their section builders are
//  private methods on their State classes, so the split layout cannot be
//  assembled from outside those files — but the *chrome* around it can, and it
//  is identical for all four. It lives here, once, as pure layout: every widget
//  below is stateless, reads no model and owns no form state.
//
//  ── Why not import the admin kit ──────────────────────────────────────────
//  The admin console's report detail (features/admin/widgets/report_detail_kit)
//  is the visual reference for all of this — titled panes, an accent stepper,
//  icon-led summary rows, an "Action" heading over a button stack. But it is
//  built on AdminUi tokens, and CitizenUi's class doc is explicit that the
//  citizen side should not reach into another console's palette. So the shapes
//  are rebuilt here on CitizenUi. The two token sets carry identical
//  surface/border/text values today, so the result reads as the same system.
//
//  ── Web only ──────────────────────────────────────────────────────────────
//  Nothing here is imported by a mobile entrypoint. Every consumer reaches it
//  through a `splitPanel: true` branch that only the citizen web shell passes.
// ════════════════════════════════════════════════════════════════════════════

/// Below this width the two columns stack.
///
/// Measured on the panel's OWN available width, not the viewport — the dialog
/// has already taken its inset and padding out by the time this is read. At 880
/// the split still gives the working area 17/27 × (880 − 14) ≈ 545px and the
/// rail ≈ 321px, which is the narrowest either reads at before the category
/// grid crowds and the rail starts wrapping labels onto their values.
///
/// In viewport terms that is roughly a 1000px-wide browser window, since the
/// dialog takes 90% of the viewport less 48px of inset and 40px of padding.
const double kQaSplitCollapseBelow = 880;

/// Gap between the two columns, and between stacked blocks inside them.
const double kQaGap = 14;

/// The height the side-by-side panel is ALWAYS drawn at.
///
/// ── Why a fixed number and not the content ────────────────────────────────
/// The four steps of a quick action are four views of one form, not four
/// pages. Sizing the panel to whichever step is showing made the modal resize
/// under the pointer on every Continue — Category 510, Location 902, Details
/// 787, Review 714 — so the frame, the buttons and the citizen's place on the
/// screen all moved each time they advanced. A form that changes shape while
/// you fill it in reads as jitter no matter how correct each individual size
/// is. One height, held across all four, is the whole point.
///
/// ── Why 820 ───────────────────────────────────────────────────────────────
/// Measured, not guessed: it is the tallest of Report's four steps, which is
/// Review once an attachment is on it — and that is every real Review, since a
/// report cannot be filed without one. Every step therefore draws in full, and
/// nothing scrolls in its normal state. `no step overflows the fixed height` in
/// report_split_panel_test.dart is that claim, kept honest on every run.
///
/// Both directions are worth defending when this file changes. Raise what the
/// TALLEST step needs and it starts scrolling; lower it, or let a short step
/// stay short, and the surplus turns back into the empty band this number
/// exists to avoid. That is why the location step gave up its duplicate
/// heading and its phone-proportioned map, why the Review thumbnails are
/// capped by extent instead of stretching four-across, and why the category
/// tiles are drawn as large as they are: the frame is fixed, so every pixel
/// reclaimed from the tallest step and every pixel earned by the shortest one
/// is emptiness removed from the middle.
///
/// A surplus that survives all that is split evenly above and below the step's
/// content — see `_splitScrollable` in report_issue_screen.dart — rather than
/// pooling at the bottom, where it reads as the panel having run out.
///
/// It is a CAP as much as a target: [QaSplitPanel] takes the smaller of this
/// and the height actually on offer, so on a short window the dialog's own
/// viewport limit binds first — and binds identically on every step, which is
/// what keeps the size constant there too.
const double kQaSplitPanelHeight = 820;

/// The two-column shell.
///
/// Wide: ~1.7fr : 1fr, both columns stretched to the taller one so the rail's
/// action stack stays anchored at a predictable place instead of floating in
/// the middle of a tall dialog. Narrow: left over right, each its own card.
///
/// ── Why builders rather than widgets ──────────────────────────────────────
/// The two modes ask their children for different SHAPES, and a child that
/// ignores the difference lays out wrong. Side by side, each column is drawn to
/// the fixed frame: the working area keeps its own scroll view and the panel's
/// head and the rail's buttons stay put while the middle scrolls. Stacked, the
/// panel becomes three zones (below), and the two children play different parts
/// in it. Passing `stacked` down is what lets a child pick the right one.
///
/// ── The stacked panel is three zones, not one long scroll ─────────────────
/// It used to be one outer [SingleChildScrollView] holding both cards. That put
/// the action stack at the BOTTOM of a page-length scroll: on a phone the
/// citizen filled a step, then had to scroll past the whole summary to find
/// Continue — and the rail's own inner scroll view ended up nested inside the
/// outer one, so a drag over the rail was arbitrated between two scrollables.
///
/// Stacked is now:
///
///   1. header — the title and the stepper, fixed, inside `left`'s card.
///   2. body   — `left`'s working area, the ONLY scroller, bounded to the
///               panel rather than to the window.
///   3. action — `right`, pinned to the bottom of the panel and never scrolled
///               away, so Continue/Submit is always on screen.
///
/// Zones 1 and 2 are `left`'s to build (it owns the card they share); this
/// widget supplies the bounded frame that makes "fixed" and "pinned" mean
/// anything, by giving `left` an [Expanded] and letting `right` size itself.
/// Which is why the stacked branch needs a BOUNDED height — see the fallback in
/// [build] for what happens when it does not get one.

/// Carries "a soft keyboard is open" ACROSS the dialog boundary.
///
/// ── Why MediaQuery cannot answer this inside the panel ────────────────────
/// Flutter's [Dialog] pads itself by `MediaQuery.viewInsets` and then wraps its
/// child in `MediaQuery.removeViewInsets(removeBottom: true, ...)` — see
/// dialog.dart, which does this so a dialog's contents are not asked to dodge a
/// keyboard the dialog has already dodged for them. The consequence here is
/// absolute: anywhere inside the panel, `viewInsets.bottom` is ZERO, no matter
/// what the keyboard is doing. A check written against it is not merely
/// unreliable, it is dead code that always takes the same branch.
///
/// The host builds the [Dialog], so its own context is ABOVE that strip and can
/// still see the real inset. It reads it there and puts the answer in here.
///
/// Defaults to FALSE with no scope present, so the panel keeps its pinned
/// actions anywhere it is mounted without a host — tests, previews, and the
/// side-by-side desktop layout, which never has a keyboard over it anyway.
class QaKeyboardScope extends InheritedWidget {
  final bool keyboardUp;

  const QaKeyboardScope({
    super.key,
    required this.keyboardUp,
    required super.child,
  });

  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<QaKeyboardScope>()
          ?.keyboardUp ??
      false;

  @override
  bool updateShouldNotify(QaKeyboardScope oldWidget) =>
      oldWidget.keyboardUp != keyboardUp;
}

/// Carries "this panel IS the page" down to the chrome.
///
/// ── Why the chrome cannot work this out for itself ────────────────────────
/// A rounded, bordered card floating on the shell's grey is right when there is
/// a shell behind it to float over. Once the host presents the panel
/// fullscreen there is nothing behind it: the "floating" card is drawn on a
/// grey band the citizen reads as the page, inside a viewport the card is
/// already filling. On a phone that band cost 12px of inset a side plus a 14px
/// trough between the two zones — visible in the browser as a modal hovering
/// over nothing.
///
/// Only the HOST knows which presentation it chose (see
/// `showCitizenSplitPanelDialog`), and the chrome is several widgets down from
/// it, so the answer is handed down rather than re-derived from a width. That
/// matters: a second `MediaQuery.sizeOf(context) < …` inside [QaPanelCard]
/// would be a copy of the host's threshold, free to drift out of step with the
/// presentation it is describing.
///
/// Defaults to FALSE with no scope present, so every host that does not opt in
/// — tests, previews, the side-by-side dialog — keeps the cards it has always
/// drawn, pixel for pixel.
class QaFullBleedScope extends InheritedWidget {
  final bool fullBleed;

  const QaFullBleedScope({
    super.key,
    required this.fullBleed,
    required super.child,
  });

  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<QaFullBleedScope>()
          ?.fullBleed ??
      false;

  @override
  bool updateShouldNotify(QaFullBleedScope oldWidget) =>
      oldWidget.fullBleed != fullBleed;
}

class QaSplitPanel extends StatelessWidget {
  final Widget Function(bool stacked) left;

  /// The rail, or the pinned action zone once stacked.
  ///
  /// Nullable so a pane that has NO actions can say so, rather than returning
  /// an empty box the panel then has to frame. Three of the four quick actions
  /// use it: their Summary pane carries nothing to press, and under a
  /// [QaFullBleedScope] the zone is separated by a hairline rather than by a
  /// gap — a rule drawn above an empty box is a stray line across the bottom of
  /// the screen. A builder that always returns a widget is unaffected, and
  /// still assigns to this type.
  final Widget? Function(bool stacked) right;
  final double collapseBelow;

  const QaSplitPanel({
    super.key,
    required this.left,
    required this.right,
    this.collapseBelow = kQaSplitCollapseBelow,
  });

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      // Every scroll view inside the panel is an *inner* one: the working
      // area's middle, the review list, whatever a form nests. On desktop the
      // material behaviour hangs a scrollbar on each of them, and a track
      // running down the inside edge of a card reads as a seam in the card
      // rather than as a control. The wheel, the trackpad and the keyboard are
      // untouched — only the painted bar goes. Scoped to this panel, so no
      // page or sheet elsewhere loses its scrollbar.
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: LayoutBuilder(
        builder: (context, c) {
          if (c.maxWidth < collapseBelow) {
            // Stacked: the rail goes BELOW the working area — it summarises it,
            // so leading with it would put "Not set yet" above the fields that
            // set it. `left` takes everything that is left over and scrolls
            // inside it; `right` keeps its intrinsic height at the bottom,
            // which is what pins the actions.
            //
            // ── The action zone stands down while the keyboard is up ──────
            //
            // The host [Dialog] already shrinks by `viewInsets`, so when the
            // keyboard opens the panel loses that height. The pinned zone,
            // though, keeps its full intrinsic height — Continue over Back over
            // Cancel is three stacked buttons, well over 200px — and it takes
            // that out of the ONE part that needed the room. On a phone browser
            // the working area collapsed to a sliver of the step notice and the
            // field being typed into was pushed off the bottom, so the citizen
            // was typing into something they could not see.
            //
            // Pinning exists so Continue is always reachable. While the keyboard
            // is up it is not reachable anyway — the keyboard is over it — so
            // the pin is costing height and buying nothing. Standing the zone
            // down gives the body every pixel the keyboard left, which is what
            // lets the framework scroll the focused field back into view. It
            // comes straight back when the keyboard closes.
            //
            // From [QaKeyboardScope], NOT from MediaQuery. This was written as
            // `MediaQuery.viewInsetsOf(context).bottom > 0` and shipped, and it
            // never once fired: [Dialog] strips viewInsets from its subtree, so
            // the value read here is always zero. See QaKeyboardScope.
            //
            // Web-only by construction — `splitPanel: true` is passed in exactly
            // one place, the citizen web shell — so the app never runs this.
            final keyboardUp = QaKeyboardScope.of(context);

            // Fullscreen, the two zones are two halves of one sheet, not two
            // cards on a page: the [kQaGap] trough between them is grey the
            // page no longer has, so it reads as a seam in the middle of the
            // screen. A hairline says the same thing — "the actions are a
            // separate zone" — in 1px instead of 14, and the height it gives
            // back goes to the list, which is the part the citizen came for.
            final fullBleed = QaFullBleedScope.of(context);

            // Built once, so the null check and the child are the same call:
            // asking twice would run a builder that may read form state twice
            // per frame, and could disagree with itself.
            final actions = right(true);

            final zones = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: left(true)),
                // Animated, not switched. Dropping the zone between two frames
                // made the whole panel jump at the same moment the keyboard was
                // sliding up, and two unrelated movements at once read as a
                // glitch. [AnimatedSize] collapses the zone's HEIGHT instead, so
                // the buttons slide out of the bottom of the panel while the
                // working area grows into the space they leave — one continuous
                // movement, and the reverse on the way back.
                //
                // ── Instant OUT, animated BACK ────────────────────────────
                //
                // Animating the collapse while the keyboard rises put two
                // animations on the same dimension, on different clocks, and
                // the body height went down 58px, back UP 55, then down 53
                // again — measured, and felt as a shake. The Scaffold shrinks
                // the panel at the keyboard's speed; a 260ms collapse frees the
                // zone's height on its own, so early in the rise the panel
                // outruns the collapse and later the collapse overtakes it.
                //
                // On the way OUT there must therefore be exactly one moving
                // part, and it has to be the keyboard's: the zone goes at once,
                // leaving the Scaffold's resize as the only thing animating,
                // which is monotonic.
                //
                // On the way BACK there is nothing to race — `keyboardUp` only
                // clears once the inset reaches zero, so the keyboard has
                // already finished — and an instant return would snap 224px in
                // one frame. That is the direction worth easing.
                AnimatedSize(
                  //
                  // Not `Duration.zero`: AnimatedSize completes a zero-duration
                  // controller synchronously inside its own performLayout and
                  // asserts "RenderAnimatedSize was mutated in its own
                  // performLayout". A single millisecond finishes on the next
                  // frame instead — instant to the eye, legal to the framework.
                  duration: keyboardUp
                      ? const Duration(milliseconds: 1)
                      : const Duration(milliseconds: 260),
                  curve: Curves.easeInOutCubic,
                  alignment: Alignment.topCenter,
                  child: (keyboardUp || actions == null)
                      ? const SizedBox.shrink()
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (fullBleed)
                              const _QaZoneRule()
                            else
                              const SizedBox(height: kQaGap),
                            actions,
                          ],
                        ),
                ),
              ],
            );
            // A pinned zone needs a bottom to be pinned to. Every real host
            // gives the panel one (the dialog caps at 85% of the viewport,
            // fullscreen hands it the viewport itself), so this is the
            // degradation for an unbounded host rather than an expected path:
            // borrow the same frame the side-by-side layout uses, so the
            // three zones still have a height to divide instead of throwing on
            // the [Expanded].
            return c.hasBoundedHeight
                ? zones
                : SizedBox(height: kQaSplitPanelHeight, child: zones);
          }

          // Side by side, the frame is [kQaSplitPanelHeight] — the same on
          // every step, so advancing changes what is INSIDE the panel and
          // nothing about the panel itself.
          //
          // `stretch` then hands both columns that height as a tight
          // constraint, which is what keeps the two cards level with each
          // other and the rail's action stack anchored. Inside the left card
          // the working area is a `Flexible` scroll view, so a short step
          // renders top-aligned with the surplus below it rather than being
          // stretched to fill.
          //
          // `math.min` because the height on offer is the hard limit: on a
          // short window the dialog's own 85%-of-viewport cap is smaller than
          // this, and exceeding it would overflow the dialog. That cap does
          // not vary by step either, so the panel stays one size there too.
          final height = c.hasBoundedHeight
              ? math.min(kQaSplitPanelHeight, c.maxHeight)
              : kQaSplitPanelHeight;

          return SizedBox(
            height: height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 17, child: left(false)),
                const SizedBox(width: kQaGap),
                // Side by side the rail is never absent — the summary is half
                // of what the layout is FOR — so this fallback is only the
                // type's, not a state any of the four reaches.
                Expanded(flex: 10, child: right(false) ?? const SizedBox()),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The hairline that separates the two zones when the panel is the page.
///
/// A [Container] with an explicit height rather than a [Divider], which brings
/// 16px of its own vertical padding and would put most of the trough back.
class _QaZoneRule extends StatelessWidget {
  const _QaZoneRule();

  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: CitizenUi.border);
}

/// One of the two rounded cards. Hairline border, no shadow — these sit on the
/// dialog's own grey, not on the page, and a shadow at this size reads as grime.
///
/// Under a [QaFullBleedScope] there is no grey for them to sit on: the panel is
/// the whole viewport, so the border and the corner radius are the only things
/// still drawing a card, around content that reaches every screen edge. Both
/// go, and what is left is a plain white sheet — the shape a full-screen
/// surface has everywhere else in this app (see the docked chat's own
/// `BorderRadius.zero` sheet). The padding is untouched either way: that is the
/// content's own margin, not the card's outline.
class QaPanelCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const QaPanelCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  @override
  Widget build(BuildContext context) {
    final fullBleed = QaFullBleedScope.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: CitizenUi.surface,
        borderRadius: fullBleed
            ? BorderRadius.zero
            : BorderRadius.circular(CitizenUi.cardRadius),
        border: fullBleed ? null : Border.all(color: CitizenUi.border),
      ),
      child: child,
    );
  }
}

/// The left panel's title.
class QaPanelTitle extends StatelessWidget {
  final String text;
  const QaPanelTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w800,
        color: CitizenUi.textPrimary,
        letterSpacing: -0.4,
      ),
    );
  }
}

// ── Stepper ──────────────────────────────────────────────────────────────────

/// Horizontal numbered stepper.
///
/// [onSelect] reports a tap on a number and nothing more — this widget has no
/// opinion about whether the move is allowed, and must not grow one. Deciding
/// that needs the form's own per-step rules, so the host answers it (see
/// `_onStepperTap` in report_issue_screen.dart); putting a second set of
/// conditions here is how a stepper and its form start disagreeing about what
/// is missing.
class QaStepper extends StatelessWidget {
  final List<String> labels;
  final int current;
  final ValueChanged<int>? onSelect;

  /// Lets the step columns narrow below [_stepWidth] when the row cannot
  /// afford four of them. Default false, which is the geometry this widget has
  /// always drawn.
  ///
  /// ── It is the same stepper, not a different one ──────────────────────────
  /// Circles, numbers, checks, labels underneath, connectors between: all
  /// unchanged, and so is the tap contract. The ONLY thing this licences is
  /// giving up column width, and the clamp below means it gives up none until
  /// the row genuinely cannot seat four 82px columns — so at every width where
  /// the fixed geometry fit, this draws the fixed geometry, pixel for pixel.
  ///
  /// It exists because 4 × 82 plus connectors is ~350px before anything else,
  /// and the stacked panel on a phone has ~300. Without it the stepper simply
  /// overflows its card. All four labels stay in the tree and stay tappable at
  /// every width; a label with nowhere left to go ellipsizes.
  final bool compact;

  const QaStepper({
    super.key,
    required this.labels,
    required this.current,
    this.onSelect,
    this.compact = false,
  });

  static const double _circle = 30;

  /// The width a step column is drawn at when there is room for it.
  static const double _stepWidth = 82;

  /// The narrowest a column may be squeezed to: wide enough for the [_circle]
  /// and a couple of ellipsized characters under it.
  static const double _minStepWidth = 34;

  /// The gap reserved for each connector before width is taken off the columns.
  static const double _minConnector = 8;

  @override
  Widget build(BuildContext context) {
    if (!compact) return _row(_stepWidth, 4);
    return LayoutBuilder(
      builder: (context, c) {
        final n = labels.length;
        if (!c.hasBoundedWidth || n == 0) return _row(_stepWidth, 4);
        // Exactly the budget the row has: n columns plus (n − 1) connectors.
        // Above the clamp this returns _stepWidth and the connectors go back to
        // absorbing the surplus — i.e. the untouched layout.
        final w = ((c.maxWidth - _minConnector * (n - 1)) / n).clamp(
          _minStepWidth,
          _stepWidth,
        );
        return _row(w, w < _stepWidth ? 2 : 4);
      },
    );
  }

  /// One row of [labels], each column [stepWidth] wide, each connector inset by
  /// [connectorInset] a side.
  Widget _row(double stepWidth, double connectorInset) {
    return Row(
      // Top-aligned so the connectors land on the circles' centre line rather
      // than drifting down to the labels — a step column is much taller than a
      // 2px line. Same reasoning as the admin console's stepper rail.
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  top: _circle / 2 - 1,
                  left: connectorInset,
                  right: connectorInset,
                ),
                child: Container(
                  height: 2,
                  color: i <= current ? CitizenUi.accent : CitizenUi.border,
                ),
              ),
            ),
          _QaStep(
            index: i,
            label: labels[i],
            width: stepWidth,
            done: i < current,
            active: i == current,
            onTap: onSelect == null ? null : () => onSelect!(i),
          ),
        ],
      ],
    );
  }
}

/// A segmented control for switching between PANES of one surface.
///
/// The shape is the admin console's own segmented control
/// (`AdminSegmentedTabs`, used by the report detail's phone pane switcher): a
/// bordered track with 4px of padding, segments dividing it evenly, and the
/// active one filled and reversed out in white. Rebuilt on CitizenUi rather
/// than imported, for the reason given at the top of this file — the two token
/// sets carry the same values, so it reads as the same control.
///
/// ── What it is NOT ───────────────────────────────────────────────────────
/// Not a stepper, and not a substitute for one. This switches which pane you
/// are LOOKING at, and every pane is always available; a [QaStepper] moves you
/// through a sequence whose steps are earned and can be refused. The stacked
/// panel carries both — "Report | Summary" here, the four gated steps inside
/// the Report pane — so keeping the two visually distinct is what stops the
/// tabs from reading as something the form will argue with.
///
/// Segments are [Expanded], so however many there are they come to exactly the
/// width on offer: nothing overflows and nothing needs scrolling sideways.
class QaSegmentedTabs extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;

  const QaSegmentedTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelect,
  });

  /// Below this much width per segment the bar tightens its padding and type.
  /// A density switch inside one layout, not a second layout.
  static const double _denseSegment = 110;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final n = labels.length;
        final dense =
            n > 0 && c.hasBoundedWidth && (c.maxWidth / n) < _denseSegment;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: CitizenUi.subtle,
            borderRadius: BorderRadius.circular(CitizenUi.controlRadius),
            border: Border.all(color: CitizenUi.border),
          ),
          child: Row(
            children: [
              for (var i = 0; i < n; i++)
                Expanded(
                  child: _QaSegmentedTab(
                    label: labels[i],
                    active: i == selected,
                    dense: dense,
                    onTap: () => onSelect(i),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _QaSegmentedTab extends StatelessWidget {
  final String label;
  final bool active;
  final bool dense;
  final VoidCallback onTap;

  const _QaSegmentedTab({
    required this.label,
    required this.active,
    required this.dense,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(CitizenUi.controlRadius - 3);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          padding: EdgeInsets.symmetric(
            vertical: dense ? 8 : 9,
            horizontal: dense ? 4 : 6,
          ),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? CitizenUi.accent : Colors.transparent,
            borderRadius: radius,
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: dense ? 12 : 13,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? Colors.white : CitizenUi.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _QaStep extends StatelessWidget {
  final int index;
  final String label;
  final double width;
  final bool done;
  final bool active;
  final VoidCallback? onTap;

  const _QaStep({
    required this.index,
    required this.label,
    required this.width,
    required this.done,
    required this.active,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final filled = done || active;
    final circle = Container(
      width: QaStepper._circle,
      height: QaStepper._circle,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled ? CitizenUi.accent : CitizenUi.surface,
        shape: BoxShape.circle,
        border: Border.all(
          color: filled ? CitizenUi.accent : CitizenUi.borderStrong,
          width: 1.5,
        ),
      ),
      child: done
          ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
          : Text(
              '${index + 1}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: filled ? Colors.white : CitizenUi.textFaint,
              ),
            ),
    );

    final column = SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          circle,
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.25,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active
                  ? CitizenUi.accent
                  : done
                  ? CitizenUi.textSecondary
                  : CitizenUi.textFaint,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return column;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: column,
      ),
    );
  }
}

/// Small muted line introducing a block inside a panel — the replacement for a
/// nested titled card once the stepper already says which step this is.
class QaFieldLabel extends StatelessWidget {
  final String text;
  final String? hint;

  /// Colour for [hint]. Defaults to the faint tier, which is right for an
  /// aside ("Optional", "0/6"); pass the danger colour when the hint is a
  /// REQUIREMENT, so "Required" reads as a rule rather than as a footnote.
  final Color? hintColor;

  const QaFieldLabel(this.text, {super.key, this.hint, this.hintColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          // ── Flexible, because the longest of these does not always fit ────
          // The label was a bare [Text] beside the hint's [Expanded]: laid out
          // with an unbounded main axis, so it took its full one-line width and
          // ran the Row past its box rather than wrapping. "Street name &
          // detailed location" is the one that reaches that first, on the
          // location step at a phone's width.
          //
          // Loose, so nothing moves where there is room: below its share the
          // label still takes its intrinsic width and the hint still starts
          // immediately after it — the hint is left-aligned inside its own box,
          // so a box that now ends earlier changes nothing about where its text
          // is drawn. Above its share the label wraps to a second line instead
          // of overflowing.
          Flexible(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.1,
                color: CitizenUi.textPrimary,
              ),
            ),
          ),
          if (hint != null) ...[
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                hint!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: hintColor == null
                      ? FontWeight.w500
                      : FontWeight.w600,
                  color: hintColor ?? CitizenUi.textFaint,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A pickable tile in a choice grid — the category tiles on Report.
///
/// ── Hover is deliberate and web-only ─────────────────────────────────────
/// [MouseRegion] only reports enter/exit for a real pointer, so this reads as a
/// plain tile on touch. It lives in this file rather than in the shared form so
/// the mobile and embedded branches — which build their own tiles and never
/// import this — keep exactly the tap-only affordance they had.
class QaChoiceTile extends StatefulWidget {
  final Widget icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const QaChoiceTile({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  State<QaChoiceTile> createState() => _QaChoiceTileState();
}

class _QaChoiceTileState extends State<QaChoiceTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    // Selected wins over hover: a solid accent edge reads as a committed
    // choice, the tinted one as "you are about to".
    final borderColor = selected
        ? CitizenUi.accent
        : _hover
        ? CitizenUi.accent.withValues(alpha: 0.55)
        : CitizenUi.border;
    // ── Constant in EVERY state, on purpose ─────────────────────────────────
    // A `Container`'s border is drawn inside its box and insets the child by
    // its width, so a border that thickens on selection drags the icon and the
    // label inward by the difference — and because `AnimatedContainer` lerps
    // the decoration, it drags them across every intermediate width on the way.
    // Under a pointer that reads as the tile shivering. Selection is carried by
    // colour and by the ring below instead, neither of which touches layout.
    const borderWidth = 1.5;
    // Depends on SELECTION only. The hover wash is painted by the [InkWell]
    // below instead of by this decoration — see the build for why.
    final fill = selected
        ? CitizenUi.accent.withValues(alpha: 0.06)
        : CitizenUi.surface;
    final tint = selected || _hover
        ? CitizenUi.accent
        : CitizenUi.textSecondary;
    // The icon sits on its own disc rather than bare on the card. It gives the
    // artwork — six unrelated illustrations at six different weights — one
    // shared silhouette, so the row reads as a set of choices instead of as a
    // row of stickers.
    final discColor = selected
        ? CitizenUi.accent.withValues(alpha: 0.12)
        : CitizenUi.subtle;

    // ── Why the hover wash is the InkWell's and not this widget's ───────────
    // Hand-rolling it as `MouseRegion` → `setState` → colour made the tint a
    // function of THIS State object, and a State that is rebuilt from scratch
    // starts life with `_hover == false`. Anything that re-created the element
    // mid-hover therefore dropped the tint on the floor, the region immediately
    // reported a fresh enter, and the tile flashed blue, went plain, then came
    // back — the flicker, exactly as described.
    //
    // [InkWell.hoverColor] is painted by the enclosing [Material]'s ink
    // features, which live on the Material's render object rather than on this
    // State, and it cross-fades on its own. So the wash survives a rebuild, and
    // nothing about it can double-trigger. `onHover` is still listened to for
    // the BORDER tint, guarded so an unchanged value never calls `setState` at
    // all; paired with the stable per-category key the grid now passes, the
    // element is no longer re-created under the pointer either way.
    final radius = BorderRadius.circular(14);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: radius,
        border: Border.all(color: borderColor, width: borderWidth),
        // The "committed" ring. A shadow spreads OUTSIDE the box, so it costs
        // the layout nothing and can be animated freely — which is what the
        // thicker border used to be doing, expensively.
        boxShadow: selected
            ? [
                BoxShadow(
                  color: CitizenUi.accent.withValues(alpha: 0.35),
                  spreadRadius: 1.5,
                ),
              ]
            : const [],
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: radius,
        child: InkWell(
          onTap: widget.onTap,
          onHover: (h) {
            if (h == _hover) return;
            setState(() => _hover = h);
          },
          borderRadius: radius,
          hoverColor: CitizenUi.accent.withValues(alpha: 0.045),
          splashColor: CitizenUi.accent.withValues(alpha: 0.10),
          highlightColor: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOut,
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: discColor,
                    shape: BoxShape.circle,
                  ),
                  child: IconTheme(
                    data: IconThemeData(size: 32, color: tint),
                    child: widget.icon,
                  ),
                ),
                const SizedBox(height: 12),
                // Animated so the label travels WITH the card instead of
                // snapping to the accent a beat before the fill has moved —
                // two changes at two speeds is what the eye reports as a blink.
                //
                // The weight is deliberately not part of it: a w600 → w700 lerp
                // re-measures the text on every frame and can re-wrap a
                // two-line label mid-animation. It steps once, on selection,
                // which is a click and not a hover.
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOut,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.25,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected || _hover
                        ? CitizenUi.accent
                        : CitizenUi.textPrimary,
                  ),
                  child: Text(
                    widget.label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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

// ── Blocks ───────────────────────────────────────────────────────────────────

/// The accent-tinted block under the stepper that says what this step is for.
class QaInstructionBlock extends StatelessWidget {
  final String title;
  final String body;
  final Color accent;

  const QaInstructionBlock({
    super.key,
    required this.title,
    required this.body,
    this.accent = CitizenUi.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 15, 18, 16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The block is advice, not a warning or an error, and an unlabelled
          // tinted rectangle does not say which. The info glyph does, before a
          // word of it is read.
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.info_outline_rounded, size: 19, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: CitizenUi.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Small info/status callout for the rail.
class QaCallout extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color accent;

  const QaCallout({
    super.key,
    required this.icon,
    required this.text,
    this.accent = CitizenUi.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 17, 16, 18),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: CitizenUi.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Right rail ───────────────────────────────────────────────────────────────

/// Rail header: the title, and the round close button.
class QaRailHeader extends StatelessWidget {
  final String title;
  final VoidCallback onClose;

  /// Draws the dismiss control as a LEADING back chevron instead of a trailing
  /// ×, for the fullscreen phone panel.
  ///
  /// ── Same action, different promise ───────────────────────────────────────
  /// It calls [onClose] either way: the discard guard, the confirmation, the
  /// pop — all unchanged, and there is no new route or history entry behind it.
  /// What changes is what the glyph promises. An × is what you press on a card
  /// floating over a page you can still see; once the panel IS the page, the ×
  /// is claiming to close something that no longer looks closeable, and the
  /// control every phone user reaches for is the chevron. It leads, because a
  /// back affordance parked on the right-hand edge reads as a mistake.
  final bool useBackArrow;

  const QaRailHeader({
    super.key,
    required this.title,
    required this.onClose,
    this.useBackArrow = false,
  });

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onClose,
        child: Tooltip(
          message: useBackArrow ? 'Back' : 'Close',
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: const Border.fromBorderSide(
                BorderSide(color: CitizenUi.border),
              ),
            ),
            child: Icon(
              useBackArrow
                  ? Icons.arrow_back_ios_new_rounded
                  : Icons.close_rounded,
              size: 18,
              color: CitizenUi.textSecondary,
            ),
          ),
        ),
      ),
    );

    final label = Expanded(
      child: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: CitizenUi.textPrimary,
          letterSpacing: -0.3,
        ),
      ),
    );

    return Row(
      children: useBackArrow
          ? [button, const SizedBox(width: 12), label]
          : [label, const SizedBox(width: 8), button],
    );
  }
}

/// One summarised field, as a single ruled line: leading icon, uppercase label
/// on the left, value right-aligned against it.
///
/// ── Why one line and not two ──────────────────────────────────────────────
/// Stacked label-over-value, the four rows read as four little paragraphs and
/// the rail competes with the working area for attention. Ruled and aligned to
/// a right edge they read as what they are: a checklist of four slots, three
/// empty. The eye runs down the values alone and sees what is left to do.
///
/// [value] null or empty renders [placeholder] in the faint italic tier, which
/// is what makes an unfilled rail read as pending rather than as broken.
class QaSummaryRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final String placeholder;
  final int maxLines;

  /// Hairline under the row. The last row in a rail can drop it — but the
  /// default is on, because a list of four that rules only three reads as an
  /// accident.
  final bool divider;

  const QaSummaryRow({
    super.key,
    required this.icon,
    required this.label,
    this.value,
    this.placeholder = 'Not set yet',
    this.maxLines = 2,
    this.divider = true,
  });

  @override
  Widget build(BuildContext context) {
    final v = value?.trim();
    final isSet = v != null && v.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          // Generous and EQUAL top and bottom, so the four rows read as one
          // evenly ruled stack rather than as four lines that happen to be
          // near each other. It is also most of what stops the rail from
          // ending halfway up a fixed-height panel.
          padding: const EdgeInsets.symmetric(vertical: 23),
          // ── Why the label is measured and not just laid out ──────────────
          // The label used to be a bare [Text] between the icon and the value's
          // [Expanded]: unconstrained, so it took its intrinsic width and could
          // not ellipsize. "ATTACHMENTS" is ~115px, and once the row is
          // narrower than the icon + gaps + that, the Row overflows — which is
          // reachable now that the rail's rows also render inside the stacked
          // panel's summary section.
          //
          // Capping it at HALF the row is what fixes that without moving
          // anything at the widths the rail actually gets: the narrowest
          // side-by-side rail is ~281px of content, so the cap is ~140 against
          // a ~115px label and never binds. Giving the label a [Flexible]
          // instead would have taken the value out of "the leftover" and into
          // "a share", which changes the value's width — and with it the right
          // edge these four rows are aligned to — at EVERY width.
          child: LayoutBuilder(
            builder: (context, c) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Plain and grey in every state. A badge or an accent tint here
                // makes the icon the loudest thing in the row, when the row
                // exists to be read label-then-value; the glyph is only there
                // to say which field this is at a glance.
                Icon(icon, size: 20, color: CitizenUi.textSecondary),
                const SizedBox(width: 16),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: c.hasBoundedWidth
                        ? c.maxWidth / 2
                        : double.infinity,
                  ),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                      color: CitizenUi.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isSet ? v : placeholder,
                    textAlign: TextAlign.right,
                    maxLines: maxLines,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.3,
                      fontWeight: isSet ? FontWeight.w600 : FontWeight.w400,
                      fontStyle: isSet ? FontStyle.normal : FontStyle.italic,
                      color: isSet
                          ? CitizenUi.textPrimary
                          : CitizenUi.textFaint,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (divider)
          const Divider(height: 1, thickness: 1, color: CitizenUi.border),
      ],
    );
  }
}

/// The "Action" heading over a vertical button stack.
class QaActionStack extends StatelessWidget {
  final List<Widget> children;

  /// Drops the heading and tightens the gaps, for the stacked panel's PINNED
  /// action zone. Default false — the side-by-side rail is unchanged.
  ///
  /// ── Why the heading goes rather than shrinks ─────────────────────────────
  /// "Action" earns its place in the rail, where it is the last of several
  /// titled blocks and says which one you have reached: summary, then callout,
  /// then the things you can do. Pinned to the bottom of a phone, the zone is
  /// two or three buttons and nothing else — there is no block above it to be
  /// distinguished from, and a heading over a permanently visible bar labels
  /// what the buttons already say. It is the one part of this zone that can
  /// leave without taking any information with it, and at ~35px including its
  /// gap it is the largest single saving available.
  final bool compact;

  const QaActionStack({
    super.key,
    required this.children,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!compact) ...[
          const Text(
            'Action',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
              color: CitizenUi.textPrimary,
            ),
          ),
          const SizedBox(height: 18),
        ],
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(height: compact ? 8 : 14),
          children[i],
        ],
      ],
    );
  }
}

/// How a [QaActionButton] is painted. `primary` fills with the accent,
/// `secondary` is an outline, `danger` is bare text in the danger colour.
enum QaActionKind { primary, secondary, danger }

class QaActionButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final QaActionKind kind;
  final Color? color;
  final VoidCallback? onTap;

  /// Replaces the label with a spinner and disables the button.
  final bool busy;

  /// Draws the button at the height a PINNED bar wants rather than the height a
  /// rail wants. Default false — the side-by-side rail is unchanged.
  ///
  /// ── Why the rail's height is wrong once it is pinned ─────────────────────
  /// 18px of vertical padding makes a ~53px button, which is right in a rail:
  /// there it sits under a summary and a callout with the whole panel's height
  /// to share, and a generous target is the last thing you press. Lifted into a
  /// full-width bar across the bottom of a phone, the same button is both wider
  /// and permanently on screen, and three of them take a third of the viewport
  /// away from the step being filled in. Wider needs LESS height, not the same:
  /// the shape reads as a bar rather than as a stack of slabs.
  ///
  /// It does not shrink the TAP TARGET. The painted box comes down to ~45px and
  /// the button keeps its default [MaterialTapTargetSize.padded], which holds
  /// the touchable area at 48 — so this trims what is drawn, never what can be
  /// hit.
  final bool compact;

  const QaActionButton({
    super.key,
    required this.label,
    this.icon,
    this.kind = QaActionKind.primary,
    this.color,
    this.onTap,
    this.busy = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final c =
        color ??
        (kind == QaActionKind.danger ? CitizenUi.danger : CitizenUi.accent);

    final style = ButtonStyle(
      // A rail button is the end of a step, not a toolbar control — the mockup
      // draws all three at the same generous height so the stack reads as one
      // block of choices. Pinned, see [compact].
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 12, vertical: compact ? 14 : 18),
      ),
      // Only compact carries a floor, so the rail's style map is untouched. The
      // height is a minimum rather than a fixed size: a label that wraps or a
      // larger text scale still gets the room it needs.
      minimumSize: compact ? const WidgetStatePropertyAll(Size(0, 46)) : null,
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CitizenUi.controlRadius),
        ),
      ),
    );

    final Widget content = busy
        ? const SizedBox(
            height: 17,
            width: 17,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16),
                const SizedBox(width: 7),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          );

    final onPressed = busy ? null : onTap;

    return SizedBox(
      width: double.infinity,
      child: switch (kind) {
        QaActionKind.primary => FilledButton(
          onPressed: onPressed,
          style: style.merge(FilledButton.styleFrom(backgroundColor: c)),
          child: content,
        ),
        QaActionKind.secondary => OutlinedButton(
          onPressed: onPressed,
          style: style.merge(
            OutlinedButton.styleFrom(
              foregroundColor: c,
              side: BorderSide(color: c.withValues(alpha: 0.45)),
            ),
          ),
          child: content,
        ),
        // Outlined in a NEUTRAL border rather than in its own red: the stack
        // is Continue / Back / Cancel, and three buttons of the same shape
        // read as three equal offers. The hairline gives Cancel the same
        // footprint as the others while the red text keeps it the one you have
        // to mean.
        QaActionKind.danger => OutlinedButton(
          onPressed: onPressed,
          style: style.merge(
            OutlinedButton.styleFrom(
              foregroundColor: c,
              side: const BorderSide(color: CitizenUi.border),
            ),
          ),
          child: content,
        ),
      },
    );
  }
}

// ── Shared field chrome ──────────────────────────────────────────────────────
//
// Everything below was private to report_issue_screen.dart while Report was the
// only quick action laid out as a split panel. Suggestion, Feedback and Events
// now draw the same panel, and a form-shaped box or a dropzone tile copied per
// form is three chances for the four surfaces to drift apart. So they moved
// here, unchanged: Report's own `_split*` helpers forward to them, which is why
// its rendering — and its test suite — is untouched by the move.

/// Shared chrome for a panel input, so every textarea, name box and picker
/// field across the four quick actions is the same control.
InputDecoration qaInputDecoration({required String hint}) {
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(CitizenUi.controlRadius),
    borderSide: BorderSide(color: c, width: w),
  );
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontSize: 13, color: CitizenUi.textFaint),
    border: border(CitizenUi.border),
    enabledBorder: border(CitizenUi.border),
    focusedBorder: border(CitizenUi.accent, 1.6),
    contentPadding: const EdgeInsets.all(12),
    counterStyle: const TextStyle(fontSize: 11, color: CitizenUi.textFaint),
    isDense: true,
  );
}

/// A field-shaped read-only container — the same border, radius and padding as
/// [qaInputDecoration], so a reviewed value reads as the input it came from
/// rather than as plain text on the card.
class QaReviewBox extends StatelessWidget {
  final Widget child;
  final double? minHeight;

  const QaReviewBox({super.key, required this.child, this.minHeight});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: minHeight ?? 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CitizenUi.subtle,
        borderRadius: BorderRadius.circular(CitizenUi.controlRadius),
        border: Border.all(color: CitizenUi.border),
      ),
      child: child,
    );
  }
}

/// A read-only placeholder line for [QaReviewBox] — "No description written",
/// "Nothing attached". Italic and faint, so an unfilled value is visibly a gap
/// rather than a value that happens to read oddly.
class QaReviewEmpty extends StatelessWidget {
  final String text;
  const QaReviewEmpty(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return QaReviewBox(
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12.5,
          fontStyle: FontStyle.italic,
          color: CitizenUi.textFaint,
        ),
      ),
    );
  }
}

/// The inline message under the field a step gate refused.
///
/// Renders nothing when [message] is null, so a caller can hand it the live
/// gate result unconditionally instead of branching at every field.
class QaFieldError extends StatelessWidget {
  final String? message;
  const QaFieldError(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    final text = message;
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 15,
            color: CitizenUi.danger,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: CitizenUi.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Submit anonymously" as a single compact row.
///
/// Pure chrome: it reports the switch and nothing more. Turning anonymity ON
/// must show the form's consent dialog first and turning it OFF must not, but
/// that consent copy is the form's, so [onChanged] carries the raw value and
/// each form keeps its own gate. Putting the gate here would give three forms a
/// fourth opinion about when consent is needed.
class QaAnonymousRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  /// What the citizen is agreeing to. Defaults to the public-feed wording the
  /// three forms share; Feedback overrides it, since feedback is not published
  /// to the feed and saying so would be wrong.
  final String subtitle;

  const QaAnonymousRow({
    super.key,
    required this.value,
    required this.onChanged,
    this.subtitle = 'Your name is hidden from the public feed',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: CitizenUi.subtle,
        borderRadius: BorderRadius.circular(CitizenUi.controlRadius),
        border: Border.all(color: CitizenUi.border),
      ),
      child: Row(
        children: [
          Icon(
            value ? Icons.visibility_off_rounded : Icons.person_rounded,
            size: 19,
            color: value ? CitizenUi.accent : CitizenUi.textFaint,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Submit anonymously',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: CitizenUi.textPrimary,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: CitizenUi.textFaint,
                  ),
                ),
              ],
            ),
          ),
          Transform.scale(
            scale: 0.8,
            child: Switch(
              value: value,
              activeTrackColor: CitizenUi.accent,
              activeThumbColor: Colors.white,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

/// The leading "Add file" tile in a panel's attachment grid.
class QaDropzoneTile extends StatefulWidget {
  final int count;
  final int max;
  final VoidCallback onTap;

  const QaDropzoneTile({
    super.key,
    required this.count,
    required this.max,
    required this.onTap,
  });

  @override
  State<QaDropzoneTile> createState() => _QaDropzoneTileState();
}

class _QaDropzoneTileState extends State<QaDropzoneTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: _hover
                ? CitizenUi.accent.withValues(alpha: 0.10)
                : CitizenUi.accentWash,
            borderRadius: BorderRadius.circular(CitizenUi.controlRadius),
            border: Border.all(
              color: CitizenUi.accent.withValues(alpha: _hover ? 0.60 : 0.32),
              width: _hover ? 1.8 : 1.4,
            ),
          ),
          // ── The tile's floor, enforced from the inside ───────────────────
          // A grid cell is a tight box: the icon, the label and the counter
          // come to ~57px tall and ~46 wide, and below that the column has
          // nowhere to go and overflows. The grid picks its column count so
          // this should not happen (see the attachment grids), but a cell is
          // sized by whatever width the panel ends up with, and an overflowing
          // dropzone is a striped banner across the middle of a form. Scaling
          // down is the graceful floor: it costs nothing at any normal size —
          // BoxFit.scaleDown only ever shrinks — and cannot overflow at any
          // abnormal one.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.add_photo_alternate_rounded,
                  size: 24,
                  color: CitizenUi.accent,
                ),
                const SizedBox(height: 5),
                const Text(
                  'Add file',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: CitizenUi.accent,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '${widget.count}/${widget.max}',
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: CitizenUi.textFaint,
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
