import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../staff/data/staff_departments.dart';
import '../theme/admin_ui.dart';

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
/// `null` if the admin cancels / dismisses. [recommendedOffice] is the office
/// the report's category maps to — it starts selected and is badged as such.
Future<String?> showAcceptAssignDialog(
  BuildContext context, {
  required String recommendedOffice,
}) {
  return showAppDialog<String>(
    context: context,
    builder: (_) => _AcceptAssignDialog(recommendedOffice: recommendedOffice),
  );
}

class _AcceptAssignDialog extends StatefulWidget {
  final String recommendedOffice;
  const _AcceptAssignDialog({required this.recommendedOffice});

  @override
  State<_AcceptAssignDialog> createState() => _AcceptAssignDialogState();
}

class _AcceptAssignDialogState extends State<_AcceptAssignDialog> {
  late String _selected = widget.recommendedOffice;

  bool get _onRecommendation => _selected == widget.recommendedOffice;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screenW = media.size.width;
    // Phone gets a near-full-bleed sheet-like card; web sits centered at 860.
    final narrow = screenW < 640;
    final inset = narrow
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 24)
        : const EdgeInsets.all(40);

    return Dialog(
      backgroundColor: AdminUi.surface,
      insetPadding: inset,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 860,
          maxHeight: media.size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(narrow),
            const Divider(height: 1, color: AdminUi.border),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(narrow ? 16 : 24, 18, narrow ? 16 : 24, 8),
                child: _body(narrow),
              ),
            ),
            const Divider(height: 1, color: AdminUi.border),
            _footer(narrow),
          ],
        ),
      ),
    );
  }

  // ── Header: green quality seal, title, and the irreversible-action notice ──
  Widget _header(bool narrow) {
    final icon = Container(
      width: narrow ? 56 : 72,
      height: narrow ? 56 : 72,
      decoration: const BoxDecoration(
        color: Color(0xFFDCFCE7),
        shape: BoxShape.circle,
      ),
      padding: EdgeInsets.all(narrow ? 12 : 16),
      child: Image.asset('assets/images/report/quality.webp'),
    );

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Accept & Assign',
          style: TextStyle(
            fontSize: narrow ? 22 : 26,
            fontWeight: FontWeight.w800,
            color: AdminUi.textPrimary,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.35,
              color: AdminUi.textSecondary,
            ),
            children: const [
              TextSpan(
                text:
                    'This report is valid and will be assigned to a department '
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
        ),
      ],
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        narrow ? 16 : 28,
        narrow ? 20 : 26,
        narrow ? 16 : 28,
        narrow ? 18 : 24,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          icon,
          SizedBox(width: narrow ? 14 : 20),
          Expanded(child: text),
        ],
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
        // The line the request asks for: reassuring on the recommended pick,
        // guiding once the admin steps off it.
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: _onRecommendation
              ? Row(
                  key: const ValueKey('rec'),
                  children: const [
                    Icon(Icons.auto_awesome_rounded,
                        size: 15, color: _confirmGreen),
                    SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'This is the best recommendation for this report.',
                        style: TextStyle(
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
        padding: const EdgeInsets.fromLTRB(14, 20, 14, 16),
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
            // Green "Recommended" star — top-left — marks the suggested office.
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
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star_rounded, size: 12, color: Colors.white),
                      SizedBox(width: 3),
                      Text(
                        'Recommended',
                        style: TextStyle(
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
    final cancel = OutlinedButton(
      onPressed: () => Navigator.of(context).pop(),
      style: OutlinedButton.styleFrom(
        foregroundColor: AdminUi.textSecondary,
        side: const BorderSide(color: AdminUi.borderStrong),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
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
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
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
          : Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                cancel,
                const SizedBox(width: 12),
                confirm,
              ],
            ),
    );
  }
}
