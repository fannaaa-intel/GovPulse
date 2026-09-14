import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../landing_theme.dart';
import 'brand_mark.dart';

/// The landing page's top bar: the mark, three anchors, and the primary CTA.
///
/// ── Not the citizen top nav ────────────────────────────────────────────────
/// That bar is built for a signed-in citizen — notifications, a profile menu,
/// the four tabs — and none of it means anything to a visitor with no account.
/// This one has exactly two jobs: let someone jump to a section, and let them
/// start.
///
/// ── Three tiers ────────────────────────────────────────────────────────────
///     >= [LandingUi.navBreak]         links inline at full size
///     >= [LandingUi.navCompactBreak]  links inline, tighter padding and type
///     below that                      links move into the overflow menu
///
/// Both breaks are the NAV's own and both are measured overflow edges, not
/// device classes. This used to borrow [LandingUi.mobileBreak] — the HERO's
/// break — which put a hamburger on an 800px window whose bar had room for
/// everything twice over.
///
/// Wrapping the links to a second row is the other way to fit them, and it is
/// rejected: it doubles the height of a bar pinned above the content on exactly
/// the screens that can least afford the vertical space.
///
/// ── The bar spans the window, up to a point ────────────────────────────────
/// Unlike every section on the page, the nav is not clamped to
/// [LandingUi.contentBand] — it is chrome, and chrome belongs to the window's
/// edges. It runs gutter-to-gutter on every phone, tablet and laptop.
///
/// Past [_kNavBand] it stops, though: on a 1920+ monitor a fully-bled bar
/// stranded its two ends hundreds of pixels outside every section below it.
/// See the note in [build].
class LandingNav extends StatelessWidget {
  /// Ceiling on the bar's own content width.
  ///
  /// Deliberately WIDER than [LandingUi.contentBand] (1180). The nav is chrome
  /// and should visibly outrun the copy it sits above — matching the body band
  /// exactly is what made the bar read as a centred island in the first place.
  /// But it is finite, so on a 1920 or 2560 monitor the mark and the CTA stop
  /// travelling outward instead of stranding themselves hundreds of pixels
  /// clear of every section below.
  ///
  /// 1324 = contentBand + 144, i.e. about 72px of overhang each side. Enough to
  /// read as deliberate, not so much that the ends detach from the page.
  static const double _kNavBand = 1324;

  final VoidCallback onFeatures;
  final VoidCallback onHowItWorks;
  final VoidCallback onFaq;
  final VoidCallback onGetStarted;

  const LandingNav({
    super.key,
    required this.onFeatures,
    required this.onHowItWorks,
    required this.onFaq,
    required this.onGetStarted,
  });

  @override
  Widget build(BuildContext context) {
    // ── Three tiers, not two ────────────────────────────────────────────────
    // The bar used to be full-or-hamburger with the switch at 720, and measured
    // that was honest: the links at their full size need ~700px and overflow
    // below it. But "does not fit at this size" is not the same as "does not
    // fit", and collapsing three short words into a menu on a 600px window —
    // where the bar is more than half empty — hides the page's own navigation
    // behind an extra tap for no reason.
    //
    // So there is a middle tier. Between [LandingUi.navCompactBreak] and
    // [LandingUi.navBreak] the links stay inline with tighter padding and
    // slightly smaller type; below that they finally move into the menu.
    //
    // The labels never change. Abbreviating "How it Works" to fit is worse than
    // either alternative: a nav whose words rewrite themselves as the window
    // moves is harder to learn than one that is simply denser.
    final width = MediaQuery.sizeOf(context).width;
    final narrow = width < LandingUi.navCompactBreak;
    final compact = !narrow && width < LandingUi.navBreak;

    return Container(
      decoration: const BoxDecoration(
        color: LandingUi.surface,
        boxShadow: LandingUi.navShadow,
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          // ── The bar spans the WINDOW, not the content band ────────────────
          // Every section on the page centres its content in a 1180 band, and
          // the nav used to do the same. For body copy that is right — a
          // measure that runs the full width of a 1920 monitor is unreadable.
          // For the nav it is wrong, and visibly so: on a wide screen the mark
          // sat 370px in from the left edge with white space either side, so
          // the bar read as a narrow centred island rather than as the page's
          // chrome.
          //
          // A nav is furniture: it belongs to the WINDOW's edges, which is
          // where a reader's eye and cursor go looking for it. So the band
          // clamp is gone and the bar is padded to the page gutter instead —
          // the mark hard against the left, the CTA (and the menu button
          // beside it on a phone) hard against the right.
          //
          // ── But NOT all the way out on a very wide desktop ────────────────
          // Pinned to the gutter at every width, a 1920 or 2560 monitor put the
          // mark and the CTA hundreds of pixels outside everything below them:
          // the hero, the features, every section is still centred in
          // [LandingUi.contentBand], so the bar's two ends floated alone in the
          // margins and the header stopped looking attached to the page.
          //
          // So the bar's own content has a ceiling — [_kNavBand] — set WIDER
          // than the content band, so the nav still reads as chrome that
          // outruns the copy, but finite, so past that width the ends stop
          // travelling and the margin grows evenly instead.
          //
          //     <= 1372   gutter-to-gutter, full bleed
          //     > 1372    content held at 1324, centred
          //
          // Below the ceiling nothing changes, so every phone, tablet and
          // laptop keeps the edge-to-edge bar.
          padding: const EdgeInsets.symmetric(
            horizontal: LandingUi.gutter,
            vertical: 12,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _kNavBand),
              child: Row(
                children: [
                  // Flexible, so the mark yields when the bar is tight. At
                  // 320px the mark, the CTA and the menu button together are
                  // wider than the viewport, and the mark is the piece that can
                  // give — [BrandMark] scales itself down rather than clipping.
                  // The button's label and the menu's touch target cannot.
                  //
                  // Measured: without this the nav Row overflowed by 111px at
                  // 390 and 181px at 320.
                  //
                  // ── The mark may SHRINK but must not GROW ───────────────────
                  // Flexible defaults to flex: 1, and that does two things, only
                  // one of which is wanted. It lets the mark be smaller than its
                  // natural size when the bar is tight (needed — see the measured
                  // overflows above), and it also makes the mark claim a share of
                  // the row's FREE space alongside the Spacer (not wanted).
                  //
                  // On a narrow bar there is no free space, so the second effect
                  // is invisible. On a wide one the mark's box swelled with the
                  // window and pushed the links and the CTA inward with it.
                  // Measured at 2560: the Row correctly spanned 48..2512 while
                  // the CTA still ended at 1802 — 758px short of the right
                  // gutter. That reads exactly like a leftover content-band
                  // clamp, which is what sent me hunting in the wrong file twice.
                  //
                  // Dropping to flex: 0 fixes the wide bar and immediately breaks
                  // the narrow one — 152px of overflow at 320. Capping the CHILD
                  // with a ConstrainedBox does not help either: the cap binds the
                  // mark, not the flex box around it, so the box still swells and
                  // still pushes.
                  //
                  // So the Flexible keeps its flex, and the mark is pinned to the
                  // LEFT inside whatever box it is given. On a wide bar the box
                  // grows and the mark simply stays on the gutter; on a narrow one
                  // the box is squeezed and BrandMark's own FittedBox scales the
                  // lockup down as before.
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: const BrandMark(),
                    ),
                  ),
                  const Spacer(),
                  if (!narrow) ...[
                    _NavLink('Features', onFeatures, compact: compact),
                    SizedBox(width: compact ? 0 : 4),
                    _NavLink('How it Works', onHowItWorks, compact: compact),
                    SizedBox(width: compact ? 0 : 4),
                    _NavLink('FAQ', onFaq, compact: compact),
                    SizedBox(width: compact ? 10 : 20),
                  ],
                  // The CTA tightens in the compact tier too — it is the widest
                  // single item on the bar, so leaving it at full size would
                  // spend the room the links just saved.
                  _GetStartedButton(
                    onPressed: onGetStarted,
                    compact: narrow || compact,
                  ),
                  if (narrow) ...[
                    const SizedBox(width: 2),
                    // ── Pulled back into the gutter ──────────────────────────
                    // A PopupMenuButton is an IconButton, whose tap target is a
                    // 48px square with the 24px glyph centred in it. That target
                    // is correct and must not shrink — it is the minimum for a
                    // finger — but it means the visible hamburger stops 12px
                    // short of the target's own edge, ON TOP of the bar's 24px
                    // gutter.
                    //
                    // Measured, that put the bar's right-hand content 74px from
                    // the screen edge while the brand mark sat at 24: the bar
                    // read as visibly lopsided on every phone, with the mark
                    // tight to its edge and the controls floating away from
                    // theirs.
                    //
                    // The fix is inside [_OverflowMenu], which trims the
                    // IconButton's own horizontal padding so the glyph lands on
                    // the gutter. It cannot be done here with a negative margin
                    // (Container rejects one) or a Transform (which would move
                    // the paint without moving the tap target).
                    _OverflowMenu(
                      onFeatures: onFeatures,
                      onHowItWorks: onHowItWorks,
                      onFaq: onFaq,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One anchor link. A [TextButton] rather than a bare [GestureDetector] so it
/// is focusable and operable from the keyboard, and announces as a button.
class _NavLink extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  /// Tightens the horizontal padding and the type a little, for the band where
  /// the links only just fit. See [LandingNav.build].
  final bool compact;

  const _NavLink(this.label, this.onPressed, {this.compact = false});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: LandingUi.textBody,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 14,
          vertical: 12,
        ),
        // 44px minimum, per WCAG 2.5.5. The padding above gives about 34, and
        // "FAQ" was the worst case at 41x34 — a small target for the shortest
        // label, which is also the one a thumb is most likely to miss.
        minimumSize: const Size(0, 44),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LandingUi.controlRadius),
        ),
      ),
      child: Text(
        label,
        // The label itself is never abbreviated — "How it Works" does not
        // become "How" to save room. A nav whose words change with the window
        // is harder to use than one that simply gets tighter.
        maxLines: 1,
        style: TextStyle(
          fontSize: compact ? 13.5 : 14.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// The green "Get Started" pill from the design.
///
/// [compact] tightens the horizontal padding for the narrow bar, where the
/// mark, this button and the menu share a phone's width. The LABEL is never
/// shortened: "Get Started" is the one instruction on the bar, and trimming it
/// to "Start" to save 18 pixels trades the clearest thing on the page for
/// padding.
class _GetStartedButton extends StatelessWidget {
  final VoidCallback onPressed;
  final bool compact;

  const _GetStartedButton({required this.onPressed, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: LandingUi.ctaGreen,
        foregroundColor: Colors.white,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 14 : 22,
          vertical: compact ? 13 : 15,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LandingUi.controlRadius),
        ),
      ),
      child: Text(
        'Get Started',
        // Never wraps to two lines, which would make the bar taller than the
        // mark beside it and visibly misalign the whole header.
        maxLines: 1,
        style: TextStyle(
          fontSize: compact ? 13.5 : 14.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// The narrow-screen home for the three section anchors, plus the sign-in link
/// the bar has no room to show inline.
class _OverflowMenu extends StatelessWidget {
  final VoidCallback onFeatures;
  final VoidCallback onHowItWorks;
  final VoidCallback onFaq;

  /// Width of a menu row's content.
  ///
  /// Measured from the longest label ("How it Works" at 14.5/w600 ~ 96px)
  /// plus the 30px icon chip and its 12px gap, with slack for a fallback font
  /// or a longer translation.
  ///
  /// This sizes the ROW, which is not quite the same as sizing the panel:
  /// Material applies its own minimum width to a PopupMenuItem, and where that
  /// minimum is the larger of the two it wins. Screenshotting the built page
  /// at 412px shows the panel settling around 220px — comfortably clear of the
  /// screen edge, which was the actual complaint — rather than the 164 below.
  /// Left here because it still bounds the row's own content and keeps the
  /// labels from stretching; it is deliberately NOT the panel's width.
  static const double _kRowWidth = 164;

  const _OverflowMenu({
    required this.onFeatures,
    required this.onHowItWorks,
    required this.onFaq,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: 'Menu',
      icon: const Icon(Icons.menu_rounded, color: LandingUi.textPrimary),
      // ── Trimmed to the right, so the glyph sits on the page gutter ────────
      // A PopupMenuButton is an IconButton: a 48px square with the 24px glyph
      // centred, which puts 12px of dead padding between the glyph and the
      // target's edge. Stacked on the bar's own 24px gutter, that left the
      // hamburger 74px from the screen edge while the brand mark sat at 24 —
      // the bar read as lopsided on every phone.
      //
      // Only the RIGHT inset is removed. The constraints then hold the target
      // at 44px in BOTH axes — the WCAG 2.5.5 minimum — which the default
      // IconButton ink box (40x40) does not meet on its own. Width 44 with 12px
      // of left padding still lands the glyph on the page gutter.
      padding: const EdgeInsets.only(left: 12),
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      // The ink splash follows the constraints rather than staying a 40px
      // circle inside a larger box, so the visual feedback matches the target.
      style: IconButton.styleFrom(
        minimumSize: const Size(44, 44),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
      // ── The panel ─────────────────────────────────────────────────────────
      // The default PopupMenuButton panel is a square-ish grey slab of bare
      // label text: no icons, hairline dividers edge-to-edge, and Material's
      // stock 8px radius. Against a landing page built entirely from soft
      // 16px cards on white it read as a piece of raw framework furniture
      // rather than part of the product.
      //
      // These four properties restate the page's own card language — white
      // ground, [LandingUi.cardRadius], a hairline border and the same wide,
      // faint [LandingUi.cardShadow] every marketing card carries. elevation 0
      // because the shadow is supplied by the shape, not by Material's tint.
      color: LandingUi.surface,
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LandingUi.cardRadius),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      // Breathing room at the panel's top and bottom, so the first and last
      // rows are not jammed against the rounded corners.
      menuPadding: const EdgeInsets.symmetric(vertical: 8),
      // Clear of the bar, and pulled LEFT off the screen edge.
      //
      // Material anchors the panel to the button, which sits on the page
      // gutter — so the panel's right edge landed flush against the screen
      // with no gutter of its own, and its rounded corners had nothing to
      // breathe into. -8 restores a visible margin on the right.
      //
      // NOTE: the panel's width is NOT set here. `constraints` on a
      // PopupMenuButton sizes the BUTTON's tap target (see the 44x44 above),
      // not the menu — setting it for the panel silently shrinks the
      // hamburger's touch target back under the WCAG minimum. The rows size
      // the panel themselves, and _kRowWidth below holds that width down.
      offset: const Offset(-8, 52),
      onSelected: (value) {
        switch (value) {
          case 0:
            onFeatures();
          case 1:
            onHowItWorks();
          case 2:
            onFaq();
          case 3:
            context.go('/login');
        }
      },
      itemBuilder: (_) => <PopupMenuEntry<int>>[
        // The three section anchors: same weight as each other, because they
        // are peers. An icon each because a four-row list of bare words gives
        // the eye nothing to land on — the glyph is what makes the menu
        // scannable at a glance rather than readable only word by word.
        _item(value: 0, icon: Icons.grid_view_rounded, label: 'Features'),
        _item(value: 1, icon: Icons.route_rounded, label: 'How it Works'),
        _item(value: 2, icon: Icons.help_outline_rounded, label: 'FAQ'),

        // Inset so the rule stops short of the panel's rounded corners; a
        // full-bleed divider inside a 16px radius clips visibly at both ends.
        const PopupMenuDivider(height: 9, indent: 12, endIndent: 12),

        // Sign in is NOT a peer of the three above — it is the one row that
        // leaves the page, and the only reason a returning citizen opens this
        // menu at all. It takes the brand blue and a filled icon chip so it
        // reads as the menu's action, matching the bar's own CTA treatment.
        _item(
          value: 3,
          icon: Icons.login_rounded,
          label: 'Sign in',
          accent: true,
        ),
      ],
    );
  }

  /// One menu row.
  ///
  /// Height 48 rather than Material's default 48-with-tight-padding: the rows
  /// are a phone's primary navigation here, so they take a full touch target
  /// and the horizontal padding the panel's radius needs.
  static PopupMenuItem<int> _item({
    required int value,
    required IconData icon,
    required String label,
    bool accent = false,
  }) {
    final Color fg = accent ? LandingUi.accent : LandingUi.textPrimary;
    return PopupMenuItem<int>(
      value: value,
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: SizedBox(
        // Bounds the row's own content so the labels do not stretch. See
        // [_kRowWidth] — this is not the same thing as the panel's width,
        // which Material's PopupMenuItem minimum also has a say in.
        width: _kRowWidth,
        child: Row(
          children: <Widget>[
            // A tinted chip behind the glyph on the accent row, so Sign in
            // carries weight without needing a second type size.
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: accent
                    ? LandingUi.accent.withValues(alpha: 0.10)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Icon(
                icon,
                size: 19,
                color: accent ? LandingUi.accent : LandingUi.textMuted,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: accent ? FontWeight.w700 : FontWeight.w600,
                  color: fg,
                  height: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
