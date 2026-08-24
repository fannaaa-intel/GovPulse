// lib/core/widgets/Home/Account/account_web_kit.dart
//
// ════════════════════════════════════════════════════════════════════════════
//  The ACCOUNT pages' web layout kit.
//
//  The five entries in the citizen shell's ACCOUNT rail — Edit Profile, Change
//  Password, My Submissions, Contact Support, About — are five destinations in
//  one section of one product. They should look like it. This is the small set
//  of pieces they are all built from, so "consistent" is a property of the code
//  rather than something five files have to keep agreeing about by hand.
//
//  ── Why a kit and not a base page ─────────────────────────────────────────
//  These five have very little in common structurally: one is a long form, one
//  is a list with tabs, one is a wizard step, two are mostly prose. A shared
//  BASE would have to be bent for each of them. What they actually share is
//  smaller and more stable — the page width, the title block, the shape of a
//  card, the look of a field, where the buttons go, when to stop being two
//  columns. So those are the parts that live here.
//
//  ── Its scope has widened, and that is fine ───────────────────────────────
//  It was built for the five ACCOUNT pages and is still named for them, but
//  Terms, Privacy, My Reports and the submission detail screens now draw their
//  headings from it too. They are all citizen-web pages living in the same
//  shell, and the alternative was each one restating the same 24/w700/-0.4
//  title and hoping it stayed in step. Reuse is what "consistent" means here.
//
//  ── WEB ONLY ──────────────────────────────────────────────────────────────
//  Nothing in this file is reachable from the mobile app. Every caller uses it
//  from behind a `kIsWeb` branch, and the mobile layouts in those same files
//  are untouched. That separation is the whole reason these pages could be
//  redesigned at all: the screens are shared with the app, so the only safe
//  place to put a web opinion is one the app never reads.
//
//  Colours come from [CitizenUi] — see that file's rule about not inventing new
//  greys, which this file obeys.
// ════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../../../theme/citizen_ui.dart';
import '../../loading/loading_overlay.dart' show AppShimmerBox;

/// Content cap for every account page, and the width the page CENTRES.
///
/// One number for all of them, because the rail switches between these pages in
/// place: a column that changed width on every click would make the whole
/// section feel unstable, even though each individual width might be
/// defensible.
///
/// ── Why 880, and why the page centres rather than the sections ────────────
/// It was 1120, with narrower content left-aligned inside it. That put the
/// title at the container's left edge and the cards at their own, and hung the
/// entire visual mass off the left of a much wider column with nothing to its
/// right. Two different problems with one cause: the page was one width and the
/// content another.
///
/// So there is now a single width, and the WHOLE page — title, sections,
/// footer — sits inside it and is centred as one block. Everything shares a
/// left edge, everything shares a right edge, and the block is in the middle of
/// the space it is given.
///
/// 880 is the narrowest width that still seats the widest thing any of these
/// pages holds — three name fields on one row in Edit Profile, which get about
/// 268 each — while keeping a settings row from stretching so far that its
/// label and its switch end up a thousand pixels apart with nothing between.
const double kAccountMaxWidth = CitizenUi.recordBand;

/// Below this CONTENT width, every multi-column arrangement becomes one column.
///
/// Measured on the content box, not the viewport. Inside the shell those differ
/// by the width of the left rail, and the page only ever gets the former.
const double kAccountStackBelow = 720;

/// Gutter between the content band and the edge of the page.
///
/// Paired with [kAccountMaxWidth] this is what fixes the CONTENT measure: 880
/// less two 32s is 816, and 816 is the number every citizen record page is
/// meant to land on — the lists and the detail pages both. Tapping a card used
/// to change it (My Reports 1112 → detail 722, My Submissions 816 → detail
/// 722), so the page appeared to shrink around the record you had just opened.
///
/// The tight value is for panes below [kAccountStackBelow], where 32 a side is
/// a tenth of the screen.
const double kAccountPageGutter = CitizenUi.recordGutter;
const double kAccountPageGutterTight = CitizenUi.recordGutterTight;

/// Gap between columns in a row, and between rows.
const double kAccountGap = 18;

/// Gap between one section and the next.
const double kAccountSectionGap = 24;

/// Corner radius shared by every card here. Matches [CitizenUi.cardRadius].
const double kAccountRadius = 14;

/// Side of the compact [AccountBackLink] chevron, and the gap after it.
///
/// Public because [AccountPageTitle] indents its subtitle by exactly these to
/// sit under the title rather than under the chevron — but only in the compact
/// shape. Prefer [AccountHeaderIndent] over doing that arithmetic at a call
/// site: above [kAccountBackLabelAbove] the correct indent is zero.
const double kAccountBackChevron = 36;
const double kAccountBackChevronGap = 14;

/// At or above this CONTENT width the back control NAMES its destination and
/// takes its own line above the title. Below it, it stays the bare chevron
/// sitting level with the title.
///
/// ── Why a labelled link, and why only when there is room ─────────────────
/// The compact chevron says only "back". WHERE it goes is written in the
/// Semantics label — 'Back to My Submissions' — which reaches precisely the
/// audience that cannot see it. On a phone-width pane that is a fair trade:
/// there is one plausible destination, and a line of vertical space is worth
/// more than the words. On a desktop pane it is not. There is room to say it,
/// and a record detail reachable from two different lists — My Submissions and
/// My Reports — is exactly the case where "back" alone is ambiguous.
///
/// Moving it onto its own line is what makes the labelled shape work. Level
/// with the title, a ~210px control would shove a 24px heading into the middle
/// of the header and drag the subtitle's indent out with it. Above the title it
/// reads as the breadcrumb it is — and because nothing then has to be indented
/// past it, the title, the subtitle and the pills all line up with the left
/// edge of the cards below, which the indented shape never did.
///
/// 560, not [kAccountStackBelow]: this is not a question about columns. It is
/// where the link plus the title stops feeling cramped, and it keeps the
/// labelled shape on the ~730 content box the shell hands a detail page — a
/// threshold at 720 would sit one rounding away from flipping between the two
/// shapes there.
const double kAccountBackLabelAbove = 560;

// ════════════════════════════════════════════════════════════════════════════
//  Page scaffold
// ════════════════════════════════════════════════════════════════════════════

/// Scrolls, centres and pads an account page, and tells its [builder] whether
/// there is room for more than one column.
///
/// The `stack` flag comes from a [LayoutBuilder], NOT from `MediaQuery`. Inside
/// the shell the MediaQuery a pane sees has already been overridden once to
/// describe the centre column; reading it here would be trusting a value two
/// layers of indirection away from the box this content is actually given. The
/// constraint is the ground truth, so the page asks it directly.
class AccountPageBody extends StatelessWidget {
  /// Receives `stack: true` when the content box is narrower than
  /// [kAccountStackBelow].
  final Widget Function(BuildContext context, bool stack) builder;

  const AccountPageBody({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stack = constraints.maxWidth < kAccountStackBelow;
        final pad = stack ? kAccountPageGutterTight : kAccountPageGutter;

        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kAccountMaxWidth),
              child: Padding(
                padding: EdgeInsets.fromLTRB(pad, stack ? 20 : 28, pad, 56),
                child: builder(context, stack),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The heading every account page opens with.
///
/// No back affordance by DEFAULT. On web the five rail pages are DESTINATIONS:
/// the rail highlights the one you are on, each has a real URL, and the
/// browser's own Back works. A chevron there would be a second, weaker answer
/// to a question already answered — and because the parent of
/// `/settings/<page>` is `/settings`, the answer it gave was to teleport you to
/// a page you had not asked for.
///
/// [onBack] is the one exception, and this is the only place it can be turned
/// on. Terms of Service and Privacy Policy are PUSHED over the Settings pane by
/// `pushLegacy`, which writes no URL — so the rail still reads Settings and
/// browser Back leaves the account area rather than closing the page. They are
/// not destinations; they are rooms that would otherwise have no door.
class AccountPageTitle extends StatelessWidget {
  final String title;

  /// One line on what the page is for. Keep it a sentence, not a paragraph.
  final String subtitle;

  /// Pops this screen. Supply it ONLY on a pushed screen with no rail entry —
  /// Terms of Service and Privacy Policy. Leave it null on the rail
  /// destinations, for the reason above.
  ///
  /// ── Why the chevron belongs here and not on its own line ────────────────
  /// It sat above the heading first, and that reads as two separate things: a
  /// stray control, then a page. Level with the title it reads as one header —
  /// the chevron is plainly the way out OF THIS PAGE, because it is holding the
  /// page's name. It also stops costing a whole line at the top of a narrow
  /// pane, which is where these screens are usually seen.
  final VoidCallback? onBack;

  /// Names the destination for screen readers, e.g. 'Back to Settings'. The
  /// chevron shows no text, so this is the only place the destination is said.
  final String backLabel;

  const AccountPageTitle({
    super.key,
    required this.title,
    required this.subtitle,
    this.onBack,
    this.backLabel = 'Back',
  });

  @override
  Widget build(BuildContext context) {
    final titleText = Text(
      title,
      style: const TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: CitizenUi.textPrimary,
        letterSpacing: -0.4,
      ),
    );

    final subtitleText = Text(
      subtitle,
      style: const TextStyle(
        fontSize: 13.5,
        color: CitizenUi.textMuted,
        height: 1.4,
      ),
    );

    if (onBack == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [titleText, const SizedBox(height: 4), subtitleText],
        ),
      );
    }

    // The shape is read off the CONTENT BOX through a LayoutBuilder — the same
    // rule as [AccountPageBody]'s `stack` flag, and for the same reason: inside
    // the shell the MediaQuery this page sees describes the centre column,
    // which is two layers of indirection away from the box this header is
    // actually given.
    return LayoutBuilder(
      builder: (context, constraints) {
        final labelled = constraints.maxWidth >= kAccountBackLabelAbove;

        // Breadcrumb shape. Nothing is indented: the link sits above the block
        // rather than beside it, so the title, the subtitle and whatever the
        // caller hangs underneath all start at the page's left edge.
        if (labelled) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: AccountBackLink(
                    label: backLabel,
                    onTap: onBack!,
                    showLabel: true,
                  ),
                ),
                const SizedBox(height: 16),
                titleText,
                const SizedBox(height: 4),
                subtitleText,
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── The chevron shares the TITLE's row, not the whole block's ──
              //
              // Centring it against title-plus-subtitle would park it between
              // the two lines, attached to neither. Centring it on the title
              // line alone is also the only version that survives a text-scale
              // change: there is no hand-computed offset here to go stale when
              // the user's browser font size is not 100%.
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  AccountBackLink(label: backLabel, onTap: onBack!),
                  const SizedBox(width: kAccountBackChevronGap),
                  Expanded(child: titleText),
                ],
              ),
              const SizedBox(height: 4),
              // Indented by exactly the chevron and its gap, so the subtitle
              // starts under the TITLE. Left at the page edge it would sit
              // under the chevron and read as a caption for the button.
              Padding(
                padding: const EdgeInsets.only(
                  left: kAccountBackChevron + kAccountBackChevronGap,
                ),
                child: subtitleText,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Indents [child] to line up with the title of the [AccountPageTitle] above
/// it, whichever shape that title took.
///
/// Call sites used to write `EdgeInsets.only(left: kAccountBackChevron +
/// kAccountBackChevronGap)` by hand for the row of pills under a header. That
/// is only right while the back control sits BESIDE the title; at
/// [kAccountBackLabelAbove] and up it sits above it and the correct indent is
/// zero. This measures the same box the title measured, so the two cannot
/// disagree — which by hand they immediately would have.
class AccountHeaderIndent extends StatelessWidget {
  final Widget child;

  const AccountHeaderIndent({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Padding(
        padding: EdgeInsets.only(
          left: constraints.maxWidth >= kAccountBackLabelAbove
              ? 0
              : kAccountBackChevron + kAccountBackChevronGap,
        ),
        child: child,
      ),
    );
  }
}

/// The one back affordance this section allows, and the rule for when.
///
/// ── Why [AccountPageTitle] has none by default and this exists anyway ─────
/// The five ACCOUNT rail pages are DESTINATIONS. The rail highlights the one
/// you are on, each has a real URL, and browser Back works — so a chevron there
/// is a second, weaker answer to a question already answered, and the answer it
/// gave was to pop to a `/settings` you never asked for.
///
/// Terms of Service and Privacy Policy are the exception. They are PUSHED over
/// the Settings pane by `pushLegacy`, which writes no URL — so the rail still
/// reads Settings and browser Back leaves the account area rather than closing
/// the page. Without this they are a room with no door.
///
/// ── Two shapes ───────────────────────────────────────────────────────────
/// [showLabel] false is the compact chevron: a bare square, because it never
/// stands alone — the page's own name sits immediately to its right, and a
/// label there would be a second heading on the same line. [label] still names
/// the destination for screen readers, which is the one audience that cannot
/// see the title beside it.
///
/// [showLabel] true is the same control with the destination written on it, for
/// the breadcrumb position above the title. [AccountPageTitle] picks between
/// them by content width — see [kAccountBackLabelAbove] for why.
///
/// Either way it responds to the pointer. A bordered box on a web page that
/// does nothing under the cursor reads as a static badge, and this one is the
/// way out of the page.
class AccountBackLink extends StatefulWidget {
  /// Names the destination, e.g. 'Back to My Submissions'. Read aloud by screen
  /// readers in both shapes, and printed on the control in the labelled one —
  /// so write it as the words a reader should SEE, not as an aside.
  final String label;

  final VoidCallback onTap;

  /// Writes [label] on the control. Set by [AccountPageTitle] from the content
  /// width; see [kAccountBackLabelAbove].
  final bool showLabel;

  const AccountBackLink({
    super.key,
    required this.label,
    required this.onTap,
    this.showLabel = false,
  });

  @override
  State<AccountBackLink> createState() => _AccountBackLinkState();
}

class _AccountBackLinkState extends State<AccountBackLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(CitizenUi.controlRadius);
    final icon = Icon(
      Icons.arrow_back_rounded,
      size: widget.showLabel ? 17 : 18,
      color: _hover ? CitizenUi.accent : CitizenUi.textSecondary,
    );

    return Semantics(
      button: true,
      label: widget.label,
      // The label is already spoken by Semantics above; excluding the visible
      // copy stops a screen reader announcing the destination twice.
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: radius,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 130),
              height: kAccountBackChevron,
              // Square when it is only a chevron; sized to its words otherwise.
              width: widget.showLabel ? null : kAccountBackChevron,
              padding: widget.showLabel
                  ? const EdgeInsets.symmetric(horizontal: 13)
                  : null,
              // No `alignment` here, deliberately: a Container given one
              // EXPANDS to its parent's bounded width, which turned the
              // labelled link into a full-width bar the first time round. The
              // Row's mainAxisSize.min sizes it to its words instead, and a
              // bare Icon centres its own glyph in the square.
              decoration: BoxDecoration(
                // Hover TINTS rather than shades. Two greyer variants were
                // tried first — `subtle` as the fill, then a firmer border and
                // a drop shadow — and both were invisible in a screenshot at
                // 1x, which is the size a reader actually sees this at. A
                // white control on a grey page going greyer also reads as
                // being disabled, which is the opposite of the message. The
                // accent wash says "navigation", which is what this is.
                color: _hover ? CitizenUi.accentWash : CitizenUi.surface,
                borderRadius: radius,
                border: Border.all(
                  color: _hover
                      ? CitizenUi.accent.withValues(alpha: .35)
                      : CitizenUi.border,
                ),
              ),
              child: widget.showLabel
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        icon,
                        const SizedBox(width: 8),
                        Text(
                          widget.label,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: _hover
                                ? CitizenUi.accent
                                : CitizenUi.textSecondary,
                            letterSpacing: -0.1,
                          ),
                        ),
                      ],
                    )
                  : icon,
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Cards and sections
// ════════════════════════════════════════════════════════════════════════════

/// A plain white card. The surface everything on these pages sits on.
class AccountCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  /// Adds the soft lift used by a page's leading card, so it reads as the
  /// header of the page rather than as the first of a list of equals.
  final bool raised;

  const AccountCard({
    super.key,
    required this.child,
    this.padding,
    this.raised = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: CitizenUi.surface,
        borderRadius: BorderRadius.circular(kAccountRadius),
        border: Border.all(color: CitizenUi.border),
        boxShadow: raised
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}

/// The small grey label above a card.
///
/// Grey and 11.5, not blue and bold: a section label names the group below it
/// and should be quieter than the content it names. The blue uppercase headings
/// these pages used to carry were heavier than their own rows.
class AccountSectionLabel extends StatelessWidget {
  final String text;
  const AccountSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      // No left inset. The label, the card beneath it and the page title above
      // it all start at the same x — three edges two pixels apart read as a
      // mistake, not as a hierarchy.
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.9,
          color: CitizenUi.textMuted,
        ),
      ),
    );
  }
}

/// A labelled card holding a GRID of form fields.
///
/// [rows] is a list of rows, each a list of fields laid out as equal columns.
/// Rows are lists rather than a flat list with a column count so one section
/// can mix a three-up row with a two-up one — and so a [SizedBox.shrink] can
/// hold a column open, which is what stops a lone phone number from stretching
/// into a 1000px input.
///
/// When [stack] the grid flattens to one field per line and those spacers are
/// dropped rather than drawn as empty gaps.
class AccountFieldSection extends StatelessWidget {
  final String title;
  final bool stack;
  final List<List<Widget>> rows;

  const AccountFieldSection({
    super.key,
    required this.title,
    required this.stack,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    final flat = <Widget>[
      for (final row in rows)
        for (final field in row)
          if (field is! SizedBox) field,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AccountSectionLabel(title),
        AccountCard(
          padding: EdgeInsets.all(stack ? 16 : 20),
          child: stack
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < flat.length; i++) ...[
                      if (i > 0) const SizedBox(height: kAccountGap),
                      flat[i],
                    ],
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var r = 0; r < rows.length; r++) ...[
                      if (r > 0) const SizedBox(height: kAccountGap),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var c = 0; c < rows[r].length; c++) ...[
                            if (c > 0) const SizedBox(width: kAccountGap),
                            Expanded(child: rows[r][c]),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

/// A labelled card holding a vertical LIST of [AccountRow]s.
///
/// The peer of [AccountFieldSection] for pages that navigate and toggle rather
/// than collect input. Hairlines between rows are inserted here, so no caller
/// has to remember to leave one off the last row.
class AccountListSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const AccountListSection({
    super.key,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AccountSectionLabel(title),
        AccountCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0)
                  const Divider(
                    height: 1,
                    thickness: 1,
                    indent: 56,
                    color: CitizenUi.border,
                  ),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Stacks sections in one column, spaced evenly, at a readable measure.
///
/// ── Why one column and not two ────────────────────────────────────────────
/// Two columns was the first attempt and it was wrong. Sections are different
/// heights, so the moment the left column's first card is shorter than the
/// right's, every section below them sits at a different y than its neighbour
/// and the page reads as ragged rather than as a grid. Nothing lines up with
/// anything, which is exactly what a settings page should not look like.
///
/// One column gives every card the same left edge, the same right edge and an
/// even vertical rhythm, and it costs nothing: these pages hold a handful of
/// short sections, not enough content to need the width.
///
/// Sections fill [kAccountMaxWidth] rather than capping themselves: the PAGE
/// owns the measure now and centres it, so a section that set its own width
/// would only re-create the misalignment that width was meant to fix.
class AccountSectionList extends StatelessWidget {
  final List<Widget> sections;

  const AccountSectionList({super.key, required this.sections});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < sections.length; i++) ...[
          if (i > 0) const SizedBox(height: kAccountSectionGap),
          sections[i],
        ],
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Rows
// ════════════════════════════════════════════════════════════════════════════

/// One row inside an [AccountListSection].
///
/// The icon is a small muted glyph, not a pastel tile with a coloured border.
/// The tiles came from the phone layout, where a row is the whole width of the
/// screen and the icon is the only thing giving it a shape. On a web page they
/// read as decoration competing with the label beside them, and eleven of them
/// down a page is a toy.
///
/// A row is tappable, or it is not: pass [onTap] for a destination and a
/// [trailing] chevron appears; pass [trailing] alone for a switch or a value.
class AccountRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;

  /// A switch, a value, or null. When null and [onTap] is set, a chevron is
  /// supplied automatically.
  final Widget? trailing;

  final VoidCallback? onTap;

  /// Red treatment, for a row that destroys something.
  final bool danger;

  const AccountRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final ink = danger ? CitizenUi.danger : CitizenUi.textPrimary;
    final glyph = danger ? CitizenUi.danger : CitizenUi.textMuted;

    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      child: Row(
        children: [
          Icon(icon, size: 20, color: glyph),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: ink,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: CitizenUi.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (trailing != null)
            trailing!
          else if (onTap != null)
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: CitizenUi.textFaint,
            ),
        ],
      ),
    );

    if (onTap == null) return row;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: row),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Fields
// ════════════════════════════════════════════════════════════════════════════

/// The label above a field.
class AccountFieldLabel extends StatelessWidget {
  final String text;
  const AccountFieldLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Flush with the input below it, for the same reason.
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: CitizenUi.textMuted,
        ),
      ),
    );
  }
}

/// The one input treatment these pages use.
///
/// A visible outline is the whole point. These forms previously drew a caption
/// over a value with no border at all, which on a screen whose entire purpose
/// is typing reads as read-only text — nothing about it said "type here".
InputDecoration accountInputDecoration({
  required String hint,
  bool enabled = true,
  Widget? suffixIcon,
}) {
  OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(CitizenUi.controlRadius),
    borderSide: BorderSide(color: color, width: width),
  );

  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(
      fontSize: 14,
      color: CitizenUi.textFaint,
      fontWeight: FontWeight.w400,
    ),
    filled: true,
    // A disabled field is filled with the PAGE colour, so it reads as a hole
    // punched in the white card rather than as an input you have not clicked.
    fillColor: enabled ? CitizenUi.surface : CitizenUi.pageBg,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    suffixIcon: suffixIcon,
    suffixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 20),
    enabledBorder: border(CitizenUi.border, 1),
    disabledBorder: border(CitizenUi.border, 1),
    focusedBorder: border(CitizenUi.accent, 1.6),
    errorBorder: border(CitizenUi.danger, 1),
    focusedErrorBorder: border(CitizenUi.danger, 1.6),
    errorStyle: const TextStyle(fontSize: 11.5, height: 1.3),
  );
}

/// Text style for the value inside a field.
///
/// [CitizenUi.textMuted] when disabled, NOT textFaint. Faint was the first
/// choice and it was wrong: Edit Profile disables every field at once during
/// its 30-day lock, and at that contrast a page of real values — your own name,
/// your own number — read as a page of empty placeholders. Disabled still has
/// to be legible; the grey fill says it is disabled.
TextStyle accountFieldTextStyle({bool enabled = true}) => TextStyle(
  fontSize: 14.5,
  fontWeight: FontWeight.w500,
  color: enabled ? CitizenUi.textPrimary : CitizenUi.textMuted,
);

/// A labelled text input.
class AccountTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final bool enabled;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final int maxLines;
  final bool obscureText;

  /// Trailing affordance inside the field — a show/hide eye, a unit, a state
  /// glyph. Kept as a slot rather than a `isPassword` flag so the caller owns
  /// what the button does.
  final Widget? suffixIcon;

  final bool autofocus;

  /// Lets a caller drive focus — needed to move focus programmatically, and to
  /// assert in a test that a focused field stays clear of the keyboard.
  final FocusNode? focusNode;

  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  const AccountTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    this.enabled = true,
    this.validator,
    this.keyboardType,
    this.onChanged,
    this.maxLines = 1,
    this.obscureText = false,
    this.suffixIcon,
    this.autofocus = false,
    this.textInputAction,
    this.onSubmitted,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AccountFieldLabel(label),
        TextFormField(
          controller: controller,
          focusNode: focusNode,
          enabled: enabled,
          validator: validator,
          keyboardType: keyboardType,
          onChanged: onChanged,
          onFieldSubmitted: onSubmitted,
          textInputAction: textInputAction,
          autofocus: autofocus,
          // A password field is single-line by construction; guarding here
          // stops a caller from asking for both and getting an assertion.
          maxLines: obscureText ? 1 : maxLines,
          obscureText: obscureText,
          style: accountFieldTextStyle(enabled: enabled),
          decoration: accountInputDecoration(
            hint: hint,
            enabled: enabled,
            suffixIcon: suffixIcon,
          ),
        ),
      ],
    );
  }
}

/// A field shown but never editable — an email, a username.
///
/// Drawn as a disabled input rather than as plain text so it lines up with the
/// editable fields beside it instead of floating at a different height.
class AccountReadonlyField extends StatelessWidget {
  final String label;
  final String value;

  const AccountReadonlyField({
    super.key,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AccountFieldLabel(label),
        TextFormField(
          initialValue: value,
          enabled: false,
          style: accountFieldTextStyle(enabled: false),
          decoration: accountInputDecoration(
            hint: '',
            enabled: false,
            suffixIcon: const Icon(
              Icons.lock_outline_rounded,
              size: 16,
              color: CitizenUi.textFaint,
            ),
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Notices
// ════════════════════════════════════════════════════════════════════════════

enum AccountNoticeTone { info, warning, danger, success }

/// A one-line notice strip.
///
/// Deliberately small. The banner this replaces was a gradient panel with a
/// headline, a sentence, a date row, a progress bar and a drop shadow, sized
/// proportionally to the page — which on a desktop page made a ~180px slab of
/// colour above the form it was describing. A notice should inform at the
/// weight of the cards around it, not outshout them.
class AccountNotice extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  /// A pill, a button, or nothing.
  final Widget? trailing;

  final AccountNoticeTone tone;
  final bool stack;

  const AccountNotice({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.stack,
    this.trailing,
    this.tone = AccountNoticeTone.info,
  });

  ({Color wash, Color line, Color ink}) get _palette => switch (tone) {
    AccountNoticeTone.warning => (
      wash: const Color(0xFFFFFBEB),
      line: CitizenUi.warn.withValues(alpha: 0.35),
      ink: CitizenUi.pending,
    ),
    AccountNoticeTone.danger => (
      wash: CitizenUi.danger.withValues(alpha: 0.07),
      line: CitizenUi.danger.withValues(alpha: 0.30),
      ink: CitizenUi.danger,
    ),
    AccountNoticeTone.success => (
      wash: const Color(0xFFF0FDF4),
      line: const Color(0xFF86EFAC),
      ink: CitizenUi.success,
    ),
    AccountNoticeTone.info => (
      wash: CitizenUi.accentWash,
      line: CitizenUi.accent.withValues(alpha: 0.25),
      ink: CitizenUi.accent,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final p = _palette;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: p.ink,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          message,
          style: TextStyle(
            fontSize: 12.5,
            height: 1.35,
            color: p.ink.withValues(alpha: 0.85),
          ),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: p.wash,
        borderRadius: BorderRadius.circular(CitizenUi.controlRadius + 2),
        border: Border.all(color: p.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: p.ink.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 19, color: p.ink),
          ),
          const SizedBox(width: 12),
          Expanded(
            // Narrow: the trailing pill drops under the message rather than
            // squeezing it, because the pill is the part that must not wrap.
            child: trailing == null
                ? body
                : stack
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      body,
                      const SizedBox(height: 10),
                      Align(alignment: Alignment.centerLeft, child: trailing!),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: body),
                      const SizedBox(width: 14),
                      trailing!,
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// The small rounded count/label that rides at the end of a notice.
class AccountNoticePill extends StatelessWidget {
  final String label;
  final Color color;

  const AccountNoticePill({
    super.key,
    required this.label,
    this.color = CitizenUi.pending,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Actions
// ════════════════════════════════════════════════════════════════════════════

ButtonStyle accountPrimaryButtonStyle() => ElevatedButton.styleFrom(
  backgroundColor: CitizenUi.accent,
  disabledBackgroundColor: CitizenUi.accent.withValues(alpha: 0.4),
  foregroundColor: Colors.white,
  disabledForegroundColor: Colors.white,
  elevation: 0,
  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 16),
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(CitizenUi.controlRadius),
  ),
  textStyle: const TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.2,
  ),
);

ButtonStyle accountSecondaryButtonStyle() => OutlinedButton.styleFrom(
  foregroundColor: CitizenUi.textSecondary,
  side: const BorderSide(color: CitizenUi.border),
  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(CitizenUi.controlRadius),
  ),
  textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
);

/// The action pair at the foot of a form.
///
/// Right-aligned when there is room; full width and stacked, primary FIRST,
/// when there is not. A right-aligned pair is a desktop convention that assumes
/// space to the right of it — at a phone width it just crowds two buttons into
/// the corner.
class AccountActions extends StatelessWidget {
  final bool stack;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  /// Swaps the primary label for a spinner. The button keeps its width, so
  /// nothing on the row shifts when a save starts.
  final bool busy;

  const AccountActions({
    super.key,
    required this.stack,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final primary = ElevatedButton(
      onPressed: onPrimary,
      style: accountPrimaryButtonStyle(),
      child: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : Text(primaryLabel),
    );

    if (secondaryLabel == null) {
      return stack
          ? SizedBox(width: double.infinity, child: primary)
          : Row(mainAxisAlignment: MainAxisAlignment.end, children: [primary]);
    }

    final secondary = OutlinedButton(
      onPressed: onSecondary,
      style: accountSecondaryButtonStyle(),
      child: Text(secondaryLabel!),
    );

    return stack
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [primary, const SizedBox(height: 10), secondary],
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [secondary, const SizedBox(width: 12), primary],
          );
  }
}

/// The inline error strip a form shows when a submit fails.
class AccountErrorStrip extends StatelessWidget {
  final String message;
  const AccountErrorStrip(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CitizenUi.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(CitizenUi.controlRadius),
        border: Border.all(color: CitizenUi.danger.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: CitizenUi.danger,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 13, color: CitizenUi.danger),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Multi-step flows
// ════════════════════════════════════════════════════════════════════════════

/// Progress through a short flow: a segmented bar and a caption.
///
/// ── Why a flow needs this on web and did not on a phone ───────────────────
/// On a phone each step is a full screen you navigated to, so the back gesture
/// and the header answer "where am I" implicitly. In a pane inside the shell
/// the surrounding chrome never changes — the rail still highlights Change
/// Password, the URL still reads /settings/password — so without a marker the
/// three steps are indistinguishable from one screen that keeps replacing its
/// own contents.
///
/// A bar rather than numbered circles: this measures how much is left, and
/// three labelled circles is more furniture than a sixty-second task deserves.
class AccountStepper extends StatelessWidget {
  /// Zero-based index of the step being shown.
  final int step;

  /// One short label per step, in order.
  final List<String> labels;

  const AccountStepper({super.key, required this.step, required this.labels});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 0; i < labels.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: i <= step ? CitizenUi.accent : CitizenUi.border,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Step ${step + 1} of ${labels.length}  ·  ${labels[step]}',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: CitizenUi.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// The labels every step of the change-password flow shares, so the three
/// screens cannot disagree about what the flow is called or how long it is.
const List<String> kChangePasswordSteps = [
  'Confirm your email',
  'Enter the code',
  'Choose a new password',
];

/// The labels every step of the profile-verification wizard shares.
///
/// -- Why three, when the wizard is eight screens ---------------------------
/// The eight routes are not eight things to do. They group cleanly, and the app
/// already groups them this way:
///
///   1. Upload ID               id_selection, photo_instruction, upload_id, scan
///   2. Additional Information  review
///   3. Identity Verification   identity, face_scan
///
/// The order is the surprising part and worth writing down, because it is not
/// the order the file names suggest: the REVIEW screen comes before the
/// identity form, and the face scan is LAST.
///
///   verification -> id_selection -> photo_instruction -> upload_id
///                -> scan -> review -> identity -> face_scan
///
/// Numbering the eight routes instead would count "get your ID ready" as a step
/// of equal weight to "confirm your details", and would tell someone on screen
/// two that they are one eighth of the way through a form they have not started.
const List<String> kVerificationSteps = [
  'Upload ID',
  'Additional Information',
  'Identity Verification',
];

/// At or below this VIEWPORT width, the verification wizard offers the CAMERA as
/// the primary way to capture an ID or a selfie; above it, a file picker.
///
/// -- Why this is measured on the viewport, and why it is not [kAccountStackBelow]
/// Every other breakpoint in this file describes a LAYOUT and is measured on the
/// content box, because layout is about the box the content is given. This one
/// describes a DEVICE - "is there plausibly a camera pointed at the world" - so
/// it reads the window, which is the closest thing to a device signal available.
/// 1024 is the tablet/desktop line rather than 720, because a tablet in landscape
/// is still a thing you pick up and point at an ID.
///
/// -- It is a guess, and it is never the only way through -------------------
/// Width is a poor proxy for hardware. A desktop browser dragged narrow has no
/// rear camera; a tablet can have its camera blocked by policy. So this only
/// chooses which method is offered FIRST: both screens that use it also offer
/// the other method as a secondary action, and neither is ever a dead end.
const double kVerificationCameraMaxWidth = 1024;

// ════════════════════════════════════════════════════════════════════════════
//  Tabs and filters
// ════════════════════════════════════════════════════════════════════════════

/// Gap between two tabs in an [AccountTabBar]. Also the gap the tab row of
/// [AccountPageSkeleton] draws, so the two strips measure the same.
const double kAccountTabGap = 28;

/// One entry in an [AccountTabBar].
class AccountTab {
  final String label;

  /// Shown as a small pill after the label. Null hides the pill entirely,
  /// which is what a page still loading its counts should pass — a `0` that
  /// turns into `12` a moment later is worse than no number at all.
  final int? count;

  /// A small red dot after the count, for "something in here is new".
  final bool dot;

  const AccountTab(this.label, {this.count, this.dot = false});
}

/// The tab strip a list page uses to switch between sibling collections.
///
/// ── Why underlines and not a segmented pill group ─────────────────────────
/// A segmented control is a control: it looks like something you set, like the
/// filter chips below it, and having two rows of pills stacked on top of each
/// other made the tabs and the filters read as one confusing bank of toggles.
/// Underlined tabs read as SECTIONS of the page instead, which is what they
/// are — and the hairline they sit on is the same line that separates the page
/// header from the list, so the strip costs no extra vertical space.
///
/// Left-aligned, not stretched across the measure. At 880px three stretched
/// tabs put their labels at the centre of three 290px cells, which lines up
/// with nothing. Starting them at the page's left edge keeps rule one: title,
/// tabs, chips and cards all begin at the same x.
class AccountTabBar extends StatelessWidget {
  final int index;
  final List<AccountTab> tabs;
  final ValueChanged<int> onChanged;

  /// Optional control parked at the far right of the strip — a refresh button,
  /// typically. Dropped when [stack] is true, where there is no spare width.
  final Widget? trailing;

  final bool stack;

  const AccountTabBar({
    super.key,
    required this.index,
    required this.tabs,
    required this.onChanged,
    this.trailing,
    this.stack = false,
  });

  @override
  Widget build(BuildContext context) {
    final strip = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < tabs.length; i++) ...[
          // Separated by a gap rather than by padding INSIDE each tab. Padding
          // would inset the first label from the page's left edge, and the
          // title, the chips and the cards all start there — the one rule this
          // kit has a test for.
          if (i > 0) const SizedBox(width: kAccountTabGap),
          _AccountTabButton(
            tab: tabs[i],
            active: i == index,
            onTap: () => onChanged(i),
          ),
        ],
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            // Scrolls rather than overflows: three labels with counts need
            // roughly 380px, and the stacked layout can be narrower than that.
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: strip,
              ),
            ),
            if (trailing != null && !stack) ...[
              const SizedBox(width: 12),
              trailing!,
            ],
          ],
        ),
        const Divider(height: 1, thickness: 1, color: CitizenUi.border),
      ],
    );
  }
}

class _AccountTabButton extends StatelessWidget {
  final AccountTab tab;
  final bool active;
  final VoidCallback onTap;

  const _AccountTabButton({
    required this.tab,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ink = active ? CitizenUi.accent : CitizenUi.textMuted;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          // Bottom padding is 0 — the 2px indicator below is what separates the
          // label from the hairline, so an active and an inactive tab are
          // exactly the same height and nothing shifts when you switch.
          padding: const EdgeInsets.only(top: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tab.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                      color: ink,
                    ),
                  ),
                  if (tab.count != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: active
                            ? CitizenUi.accent.withValues(alpha: 0.10)
                            : CitizenUi.subtle,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${tab.count}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: active
                              ? CitizenUi.accent
                              : CitizenUi.textFaint,
                        ),
                      ),
                    ),
                  ],
                  if (tab.dot) ...[
                    const SizedBox(width: 7),
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: CitizenUi.danger,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Container(
                height: 2,
                color: active ? CitizenUi.accent : Colors.transparent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One option in an [AccountChipRow].
class AccountChip {
  final String value;
  final String label;
  const AccountChip(this.value, this.label);
}

/// A single-choice filter row.
///
/// Wraps rather than scrolling horizontally. A horizontal scroller is a phone
/// affordance — it works because you can flick it — and on a desktop page it
/// hides options behind an edge with no scrollbar and no hint they are there.
/// At this measure every option fits anyway.
class AccountChipRow extends StatelessWidget {
  final List<AccountChip> chips;
  final String value;
  final ValueChanged<String> onChanged;

  const AccountChipRow({
    super.key,
    required this.chips,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final chip in chips)
          _AccountChipButton(
            label: chip.label,
            active: chip.value == value,
            onTap: () => onChanged(chip.value),
          ),
      ],
    );
  }
}

class _AccountChipButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _AccountChipButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? CitizenUi.accent : CitizenUi.surface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active ? CitizenUi.accent : CitizenUi.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: active ? Colors.white : CitizenUi.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Prose
// ════════════════════════════════════════════════════════════════════════════

/// Widest a paragraph is allowed to be set, regardless of the page measure.
///
/// [kAccountMaxWidth] is right for cards, rows and a field grid, but a card at
/// 880 sets a line about 130 characters long, and the eye loses its place
/// finding the start of the next one. About, Terms and Privacy are almost
/// entirely paragraphs, so their body copy is capped here — around 75
/// characters — while the card it sits in keeps the page's measure. The card
/// stays aligned with everything else on the page; only the text stops early.
const double kAccountProseMeasure = 660;

/// A titled paragraph — the unit About, Terms of Service and Privacy Policy are
/// almost entirely built from.
///
/// The icon is a small muted glyph for the same reason [AccountRow]'s is: the
/// mobile pages draw a pastel tile with a coloured border beside every heading,
/// and fourteen of them down a policy page is decoration competing with the
/// text it is supposed to be introducing.
class AccountProseBlock extends StatelessWidget {
  final IconData? icon;
  final String title;
  final String body;

  const AccountProseBlock({
    super.key,
    this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            // Nudged down to sit on the title's optical centre rather than its
            // ascender line.
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 20, color: CitizenUi.textMuted),
            ),
            const SizedBox(width: 18),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: CitizenUi.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: kAccountProseMeasure,
                  ),
                  child: Text(
                    body,
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.65,
                      color: CitizenUi.textSecondary,
                    ),
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

// ════════════════════════════════════════════════════════════════════════════
//  Empty and error states
// ════════════════════════════════════════════════════════════════════════════

/// What a list shows when it has nothing to show — or could not load.
///
/// Inside a card, not floating on the page background. An empty tab that draws
/// nothing but a centred glyph reads as a page that failed to render; giving it
/// the same surface the rows would have had says "this is the list, and it is
/// empty", which is a different and truer message.
///
/// The error case is the same widget with a retry [onAction]: the shape of
/// "nothing here" and "nothing here yet, try again" is identical, and one
/// widget means they cannot drift apart.
class AccountEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const AccountEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return AccountCard(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 44),
      // Fills the measure. [AccountCard] is a Container with no width of its
      // own, so a centred Column inside it shrink-wraps to its widest line and
      // the card lands narrower than the rows it replaced — which is exactly
      // the "did this fail to render" look this widget exists to avoid.
      child: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: CitizenUi.subtle,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, size: 26, color: CitizenUi.textFaint),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: CitizenUi.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: CitizenUi.textFaint,
                ),
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              OutlinedButton(
                onPressed: onAction,
                style: accountSecondaryButtonStyle(),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Loading
// ════════════════════════════════════════════════════════════════════════════

/// The loading state for an account page, built from the SAME pieces as the
/// page itself.
///
/// ── Why this is not one of the SkeletonLayout entries ─────────────────────
/// It nearly was. `SkeletonLayout.changePassword` and `.editProfile` already
/// exist, and both were being shown here — but they are drawings of the MOBILE
/// screens: a centred avatar circle, a few stacked bars, a white full-height
/// panel. Once the web layout stopped being the mobile layout, those skeletons
/// stopped describing anything that was about to appear. A skeleton that
/// promises the wrong shape is worse than no skeleton, because the page visibly
/// rearranges itself the moment it loads.
///
/// The fix is not to draw a second fixed picture. It is to build the loading
/// state out of [AccountPageBody], [AccountCard] and the same paddings the real
/// page uses, so the two cannot drift: change the page's measure or its card
/// padding, and this follows automatically.
///
/// [sections] mirrors the page's own structure — one entry per section, each a
/// list of rows, each row the number of fields across. So Edit Profile's
/// `[[2], [3], [1], [1], [1]]` is exactly what its [AccountFieldSection] calls
/// describe.
class AccountPageSkeleton extends StatelessWidget {
  /// Leading raised card — the identity banner on Edit Profile.
  final bool banner;

  /// The segmented progress bar, for a page inside a flow.
  final bool stepper;

  /// One entry per section; each entry lists that section's rows, and each row
  /// is how many fields sit across it.
  final List<List<int>> sections;

  /// A notice strip between the first section and the rest.
  final bool notice;

  /// The action row at the foot of a form.
  final bool actions;

  /// The tab strip and its hairline, for a page that opens on [AccountTabBar].
  final bool tabs;

  /// The filter chip row that sits under the tabs.
  final bool chips;

  /// How many list-card placeholders to draw below the header. Mirrors the
  /// cards a list page is about to show, the way [sections] mirrors a form's
  /// field grid — so a tabbed LIST page gets a skeleton of a list rather than
  /// a skeleton of a form it will never render.
  final int cards;

  const AccountPageSkeleton({
    super.key,
    this.banner = false,
    this.stepper = false,
    this.sections = const [],
    this.notice = false,
    this.actions = false,
    this.tabs = false,
    this.chips = false,
    this.cards = 0,
  });

  static Widget _bar(double width, double height, {double radius = 8}) =>
      AppShimmerBox(width: width, height: height, radius: radius);

  @override
  Widget build(BuildContext context) {
    return AccountPageBody(
      builder: (context, stack) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Title block — same 24/4/13.5 rhythm as [AccountPageTitle].
          Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _bar(180, 24),
                const SizedBox(height: 8),
                _bar(stack ? 240 : 380, 13),
              ],
            ),
          ),
          const SizedBox(height: 22),

          if (stepper) ...[
            _bar(double.infinity, 4, radius: 999),
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerLeft, child: _bar(160, 12)),
            const SizedBox(height: 22),
          ],

          // Tabs and chips are drawn at the sizes [AccountTabBar] and
          // [AccountChipRow] actually occupy, so the header does not jump when
          // the real controls arrive underneath the cards.
          if (tabs) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 10),
                child: Row(
                  children: [
                    for (var i = 0; i < 3; i++) ...[
                      if (i > 0) const SizedBox(width: kAccountTabGap),
                      _bar(i == 0 ? 74 : 96, 14),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 2),
            const Divider(height: 1, thickness: 1, color: CitizenUi.border),
          ],

          if (chips) ...[
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  for (var i = 0; i < 4; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    _bar(i == 0 ? 54 : 88, 33, radius: 999),
                  ],
                ],
              ),
            ),
          ],

          if (banner) ...[
            AccountCard(
              raised: true,
              padding: EdgeInsets.all(stack ? 18 : 22),
              child: stack
                  ? Column(
                      children: [
                        const AppShimmerBox(width: 88, height: 88, radius: 44),
                        const SizedBox(height: 14),
                        _bar(160, 20),
                        const SizedBox(height: 10),
                        _bar(220, 13),
                        const SizedBox(height: 16),
                        _bar(double.infinity, 44, radius: 10),
                      ],
                    )
                  : Row(
                      children: [
                        const AppShimmerBox(width: 88, height: 88, radius: 44),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _bar(200, 20),
                              const SizedBox(height: 10),
                              _bar(280, 13),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        _bar(140, 44, radius: 10),
                      ],
                    ),
            ),
            const SizedBox(height: 28),
          ],

          for (var i = 0; i < sections.length; i++) ...[
            if (i > 0) const SizedBox(height: kAccountSectionGap),
            Align(alignment: Alignment.centerLeft, child: _bar(90, 11)),
            const SizedBox(height: 10),
            AccountCard(
              padding: EdgeInsets.all(stack ? 16 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var r = 0; r < sections[i].length; r++) ...[
                    if (r > 0) const SizedBox(height: kAccountGap),
                    // Stacked, a row of N fields becomes N rows of one, which
                    // is what the real section does at this width.
                    if (stack)
                      for (var c = 0; c < sections[i][r]; c++) ...[
                        if (c > 0) const SizedBox(height: kAccountGap),
                        _skeletonField(),
                      ]
                    else
                      Row(
                        children: [
                          for (var c = 0; c < sections[i][r]; c++) ...[
                            if (c > 0) const SizedBox(width: kAccountGap),
                            Expanded(child: _skeletonField()),
                          ],
                        ],
                      ),
                  ],
                ],
              ),
            ),
            if (notice && i == 0) ...[
              const SizedBox(height: 16),
              _bar(double.infinity, 66, radius: CitizenUi.controlRadius + 2),
            ],
          ],

          // One placeholder per list card: a leading glyph tile, a title line
          // with a trailing pill, and two meta lines — the shape every card on
          // a submissions-style list draws.
          for (var i = 0; i < cards; i++) ...[
            SizedBox(height: i == 0 ? 18 : 12),
            AccountCard(
              padding: EdgeInsets.all(stack ? 16 : 18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _bar(44, 44, radius: 12),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: _bar(double.infinity, 14)),
                            const SizedBox(width: 12),
                            _bar(78, 22, radius: 999),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _bar(double.infinity, 11),
                        const SizedBox(height: 8),
                        _bar(stack ? 140 : 220, 11),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (actions) ...[
            const SizedBox(height: 28),
            stack
                ? Column(
                    children: [
                      _bar(double.infinity, 48, radius: 10),
                      const SizedBox(height: 10),
                      _bar(double.infinity, 48, radius: 10),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _bar(110, 48, radius: 10),
                      const SizedBox(width: 12),
                      _bar(150, 48, radius: 10),
                    ],
                  ),
          ],
        ],
      ),
    );
  }

  /// Label above, input below — the shape [AccountTextField] draws.
  static Widget _skeletonField() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _bar(80, 11),
      const SizedBox(height: 6),
      _bar(double.infinity, 46, radius: CitizenUi.controlRadius),
    ],
  );
}
