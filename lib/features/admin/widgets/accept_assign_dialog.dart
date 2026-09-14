import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../staff/data/staff_departments.dart';
import '../theme/admin_ui.dart';
import 'admin_dialog_keyboard.dart';
import 'admin_responsive_dialog.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Accept & Assign — the triage-desk decision that routes a valid report to the
//  LGU office that will act on it.
//
//  Unlike the plain list picker it replaces, this is a considered choice: the
//  action can't be undone, so the office options are shown as illustrated cards,
//  the category's recommended office comes pre-selected, and the copy under
//  "Select Office" reflects whether the admin has kept the recommendation or
//  overridden it.
//
//  Responsiveness — one dialog, three shapes:
//    • wide web/desktop → all four cards on one row inside a 860-wide card;
//    • tablet / narrow web → cards wrap to two columns;
//    • phone → the dialog fills the width (small inset) and cards go two-up,
//      with the header and footer stacking so nothing clips.
//  The body always scrolls, so a short viewport never traps the buttons.
// ════════════════════════════════════════════════════════════════════════════

/// Matches the screenshot's richer green (the app's [AppColors.green] reads a
/// touch light for a primary action this consequential) and the selection blue.
const Color _confirmGreen = Color(0xFF16A34A);
const Color _selectBlue = Color(0xFF2563EB);

/// One internal office as shown on a card: the illustration and the one-line
/// remit that tells the admin what it handles. Names come from
/// [StaffDepartments.internal] so routing stays in sync with staff accounts.
class _OfficeCardData {
  final String name;
  final String asset;
  final String blurb;
  const _OfficeCardData(this.name, this.asset, this.blurb);
}

const List<_OfficeCardData> _offices = [
  _OfficeCardData(
    'Engineering Office',
    'assets/images/report/engineering.webp',
    'Infrastructure and engineering works',
  ),
  _OfficeCardData(
    'Sanitation Office',
    'assets/images/report/hand-sanitizer.webp',
    'Waste management and sanitation',
  ),
  _OfficeCardData(
    'Environment Office',
    'assets/images/report/reuse.webp',
    'Environmental protection and compliance',
  ),
  _OfficeCardData(
    "Mayor's Office",
    'assets/images/report/politician.webp',
    'Policy and administrative concerns',
  ),
];

/// Shows the Accept & Assign dialog and resolves to the chosen office name, or
/// `null` if the admin cancels / dismisses.
///
/// [recommendedOffice] starts selected and is badged as such. It comes from
/// `AdminReport.suggestedDepartment`, which prefers the model's recommendation
/// and falls back to the category lookup — callers should not re-derive it, or
/// two surfaces end up naming different offices for the same report.
///
/// [isAiRecommendation] says which of those two produced it, so the badge can
/// be honest about its source. [aiReason] is the model's short justification and
/// [miscategorizedAs] the category it read the report as when that disagrees
/// with the citizen's pick; both are null when there is nothing to say.
Future<String?> showAcceptAssignDialog(
  BuildContext context, {
  required String recommendedOffice,
  bool isAiRecommendation = false,
  String? aiReason,
  String? miscategorizedAs,
}) {
  return showAppDialog<String>(
    context: context,
    builder: (_) => _AcceptAssignDialog(
      recommendedOffice: recommendedOffice,
      isAiRecommendation: isAiRecommendation,
      aiReason: aiReason,
      miscategorizedAs: miscategorizedAs,
    ),
  );
}

class _AcceptAssignDialog extends StatefulWidget {
  final String recommendedOffice;
  final bool isAiRecommendation;
  final String? aiReason;
  final String? miscategorizedAs;

  const _AcceptAssignDialog({
    required this.recommendedOffice,
    this.isAiRecommendation = false,
    this.aiReason,
    this.miscategorizedAs,
  });

  @override
  State<_AcceptAssignDialog> createState() => _AcceptAssignDialogState();
}

class _AcceptAssignDialogState extends State<_AcceptAssignDialog> {
  late String _selected = widget.recommendedOffice;

  bool get _onRecommendation => _selected == widget.recommendedOffice;

  /// The model disagreed with the citizen's category AND said something about
  /// why. Both halves are needed: a mismatch with no explanation is an
  /// unfalsifiable claim, and an explanation with no mismatch is noise on a
  /// report that was filed correctly.
  bool get _hasMismatchNotice =>
      widget.isAiRecommendation &&
      (widget.miscategorizedAs?.trim().isNotEmpty ?? false);

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // Full screen on a phone, modal above 640 — the console-wide rule. This
    // dialog is a 2-up grid of office cards, the same shape as the endorse
    // picker, and it was left as a "near-full-bleed sheet" with a 12px inset:
    // a barrier strip either side and a corner radius eating the grid, for no
    // gain over simply being the screen.
    final narrow = adminDialogIsFullscreen(context);

    final Widget body = Column(
          mainAxisSize: narrow ? MainAxisSize.max : MainAxisSize.min,
          children: [
            _header(context, narrow),
            const Divider(height: 1, color: AdminUi.border),
            // Expanded on the SCREEN form, Flexible on the modal.
            //
            // Flexible lets a child be SMALLER than the space offered, so on a
            // phone a short body left the action bar floating in the middle of
            // the screen with white below it, while a long one pushed it to the
            // bottom — the same dialog pinning its buttons in two different
            // places depending on how many cards it happened to be showing.
            // Accept & Assign has four office cards and did exactly this; the
            // endorse picker's five agency cards filled the screen and hid it.
            //
            // Expanded forces the scroll view to take everything left over, so
            // the bar sits on the bottom edge at every content length. The
            // modal keeps Flexible: there the dialog is sized to its content
            // and must be free to be shorter than the viewport.
            AdminDialogFlex(
              expand: narrow,
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                    narrow ? 16 : 24, 18, narrow ? 16 : 24, 8),
                child: _body(narrow),
              ),
            ),
            const Divider(height: 1, color: AdminUi.border),
            _footer(narrow),
          ],
    );

    if (narrow) {
      // A Scaffold, not a zero-inset Dialog — see AdminFullBleedDialog for
      // the keyboard race that distinction settles.
      return AdminFullBleedDialog(
        backgroundColor: AdminUi.surface,
        child: body,
      );
    }

    return Dialog(
      backgroundColor: AdminUi.surface,
      insetPadding: const EdgeInsets.all(40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 860,
          maxHeight: media.size.height * 0.9,
        ),
        child: body,
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  //
  // This dialog's header was the REFERENCE for the shape — chevron on its own
  // row, then the green quality seal beside the title and the
  // irreversible-action notice. It is now drawn by the shared
  // [AdminDialogScreenHeader] so Reject and Endorse cannot drift away from it
  // again, which is what they had done.
  Widget _header(BuildContext context, bool narrow) {
    final seal = Container(
      width: narrow ? 56 : 72,
      height: narrow ? 56 : 72,
      decoration: const BoxDecoration(
        color: Color(0xFFDCFCE7),
        shape: BoxShape.circle,
      ),
      padding: EdgeInsets.all(narrow ? 12 : 16),
      child: Image.asset('assets/images/report/quality.webp'),
    );

    final title = Text(
      'Accept & Assign',
      style: TextStyle(
        fontSize: narrow ? 21 : 26,
        fontWeight: FontWeight.w800,
        color: AdminUi.textPrimary,
        height: 1.1,
      ),
    );

    const description = Text.rich(
      TextSpan(
        style: TextStyle(
          fontSize: 13.5,
          height: 1.35,
          color: AdminUi.textSecondary,
        ),
        children: [
          TextSpan(
            text: 'This report is valid and will be assigned to a department '
                'for action. ',
          ),
          TextSpan(
            text: 'This action cannot be undone.',
            style: TextStyle(
              color: AppColors.red,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );

    return AdminDialogScreenHeader(
      full: narrow,
      seal: seal,
      title: title,
      description: description,
      padding: EdgeInsets.fromLTRB(
        narrow ? 16 : 28,
        narrow ? 20 : 26,
        narrow ? 16 : 28,
        narrow ? 18 : 24,
      ),
    );
  }

  // ── Body: the "Select Office" label, the adaptive recommendation copy, and
  //    the responsive grid of office cards. ────────────────────────────────
  Widget _body(bool narrow) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select Office',
          style: TextStyle(
            fontSize: narrow ? 16 : 18,
            fontWeight: FontWeight.w700,
            color: AdminUi.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        // Reassuring on the recommended pick, guiding once the admin steps off
        // it. The recommended-state wording distinguishes the two sources: a
        // model that read the report can claim to have read it, a lookup table
        // cannot, and an admin deciding whether to override deserves to know
        // which one is talking.
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: _onRecommendation
              ? Row(
                  key: const ValueKey('rec'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.auto_awesome_rounded,
                        size: 15, color: _confirmGreen),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        widget.isAiRecommendation
                            ? 'Recommended from the details of this report.'
                            : 'This is the best recommendation for this report.',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: _confirmGreen,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                )
              : const Text(
                  'Choose the office that best handles this report.',
                  key: ValueKey('override'),
                  style: TextStyle(fontSize: 12.5, color: AdminUi.textMuted),
                ),
        ),
        if (_hasMismatchNotice) ...[
          const SizedBox(height: 12),
          _mismatchNotice(narrow),
        ],
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, c) {
            // Clean layouts only, no orphan third column: the full row of four
            // on a wide dialog, a 2×2 on phones, and a single stack only when
            // it's genuinely too narrow for two cards.
            final int cols;
            if (c.maxWidth >= 640) {
              cols = 4;
            } else if (c.maxWidth >= 260) {
              cols = 2;
            } else {
              cols = 1;
            }
            return _equalRowsGrid(
              cols: cols,
              cards: [for (final o in _offices) _officeCard(o)],
            );
          },
        ),
      ],
    );
  }

  /// The mis-filed notice: the model read this report as a different category
  /// than the citizen picked. Before this existed a mis-categorised report was
  /// invisible — it routed to whatever office the wrong category mapped to and
  /// nothing anywhere said so.
  ///
  /// Amber, not red: this is information for the admin, not an error, and the
  /// citizen did nothing wrong. It sits above the office grid because it is the
  /// reason the pre-selected card may not be the one the category implies.
  ///
  /// Responsive: the icon stays top-aligned so a reason wrapping to three lines
  /// on a phone doesn't leave it floating mid-paragraph, and the text is free to
  /// wrap rather than being laid out on a fixed row.
  Widget _mismatchNotice(bool narrow) {
    final reason = widget.aiReason?.trim();
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: narrow ? 12 : 14, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.info_outline_rounded,
                size: 16, color: Color(0xFFB45309)),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: Color(0xFF92400E),
                    ),
                    children: [
                      const TextSpan(text: 'This may be filed under the wrong '
                          'category — it reads as '),
                      TextSpan(
                        text: widget.miscategorizedAs!.trim(),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const TextSpan(text: '.'),
                    ],
                  ),
                ),
                // The model's own words. Quoted and dimmed so it reads as
                // evidence the admin can weigh, not as a second instruction.
                if (reason != null && reason.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '"$reason"',
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      fontStyle: FontStyle.italic,
                      color: Color(0xFFB45309),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Lays [cards] out [cols]-per-row where every card in a row is stretched to
  /// the same height (via [IntrinsicHeight] + a stretched [Row]), so a longer
  /// blurb never leaves its neighbour a different size. A short final row is
  /// padded with invisible spacers so the remaining cards keep their width.
  Widget _equalRowsGrid({required int cols, required List<Widget> cards}) {
    const gap = 12.0;
    final rows = <Widget>[];
    for (var i = 0; i < cards.length; i += cols) {
      final items = <Widget>[];
      for (var j = 0; j < cols; j++) {
        final idx = i + j;
        items.add(
          Expanded(
            child: idx < cards.length ? cards[idx] : const SizedBox.shrink(),
          ),
        );
        if (j < cols - 1) items.add(const SizedBox(width: gap));
      }
      if (rows.isNotEmpty) rows.add(const SizedBox(height: gap));
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: items,
          ),
        ),
      );
    }
    return Column(children: rows);
  }

  Widget _officeCard(_OfficeCardData o) {
    final selected = _selected == o.name;
    final recommended = o.name == widget.recommendedOffice;

    return InkWell(
      onTap: () => setState(() => _selected = o.name),
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        // Extra headroom on the badged card. The badge is positioned at
        // top: -6 and overhangs INTO the card, so at the original flat 20 the
        // "AI Recommended" pill — wider and set in a heavier row than the old
        // "Recommended" — landed on the office illustration. Verified in the
        // browser, not inferred: the overflow probe passes either way, because
        // a Positioned child overlapping its Stack sibling is a legal layout,
        // just an ugly one. IntrinsicHeight equalises the row afterwards, so
        // the unbadged cards grow to match rather than sitting short.
        padding: EdgeInsets.fromLTRB(14, recommended ? 26 : 20, 14, 16),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF3F7FF) : AdminUi.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? _selectBlue : AdminUi.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  height: 52,
                  child: Image.asset(o.asset, fit: BoxFit.contain),
                ),
                const SizedBox(height: 14),
                Text(
                  o.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AdminUi.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  o.blurb,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.3,
                    color: AdminUi.textMuted,
                  ),
                ),
              ],
            ),
            // Blue check — top-right — marks the current selection.
            if (selected)
              Positioned(
                top: -6,
                right: -6,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(
                    color: _selectBlue,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_rounded,
                      size: 16, color: Colors.white),
                ),
              ),
            // Green badge — top-left — marks the suggested office. Names its
            // source: an admin overriding a recommendation should know whether
            // they are overriding a model that read the report or a fixed
            // category lookup. The sparkle is the same mark the app uses for AI
            // elsewhere; the star stays for the deterministic rule.
            if (recommended)
              Positioned(
                top: -6,
                left: -6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _confirmGreen,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        widget.isAiRecommendation
                            ? Icons.auto_awesome_rounded
                            : Icons.star_rounded,
                        size: 12,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        widget.isAiRecommendation
                            ? 'AI Recommended'
                            : 'Recommended',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Footer: Cancel + Confirm & Assign. Stacks on a phone so the primary
  //    action is never squeezed. ──────────────────────────────────────────
  Widget _footer(bool narrow) {
    // ── Taller on the phone form ──────────────────────────────────────────
    //
    // 14px of vertical padding is right for a modal, where the buttons sit in a
    // row at their natural width and read as a pair of controls. Stacked
    // full-width on a phone they are the two biggest targets on the screen and
    // 14 left them looking thin — a wide, short slab rather than a button. 17
    // brings them to a ~50px tap target, which is also the first size that
    // clears the 48dp Material minimum with the text's own line box.
    final double vPad = narrow ? 17 : 14;

    final cancel = OutlinedButton(
      onPressed: () => Navigator.of(context).pop(),
      style: OutlinedButton.styleFrom(
        foregroundColor: AdminUi.textSecondary,
        side: const BorderSide(color: AdminUi.borderStrong),
        padding: EdgeInsets.symmetric(horizontal: 22, vertical: vPad),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      child: const Text('Cancel'),
    );

    final confirm = FilledButton.icon(
      onPressed: () => Navigator.of(context).pop(_selected),
      style: FilledButton.styleFrom(
        backgroundColor: _confirmGreen,
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: vPad),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      icon: const Icon(Icons.send_rounded, size: 17),
      label: const Text('Confirm & Assign'),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        narrow ? 16 : 24,
        14,
        narrow ? 16 : 24,
        narrow ? 16 : 18,
      ),
      child: narrow
          ? Column(
              children: [
                SizedBox(width: double.infinity, child: confirm),
                const SizedBox(height: 10),
                SizedBox(width: double.infinity, child: cancel),
              ],
            )
          // Written as a Spacer rather than MainAxisAlignment.end so this
          // footer and the endorse dialog's are the same shape: both push the
          // action pair right, and endorse's leading slot happens to carry its
          // "Clear endorsement" link. Two idioms for one layout is how the two
          // drift apart the next time one of them grows a third button.
          : Row(
              children: [
                const Spacer(),
                cancel,
                const SizedBox(width: 12),
                confirm,
              ],
            ),
    );
  }
}
