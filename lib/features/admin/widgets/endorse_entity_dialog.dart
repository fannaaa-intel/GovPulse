import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_dialog.dart';
import '../theme/admin_ui.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Endorse to External Entity — routes an out-of-LGU-scope report to the
//  national agency that owns it (PNP, BFP, DPWH, DENR, DOH).
//
//  The sibling of the Accept & Assign dialog and built on the same rules: an
//  illustrated card per option, a blue check on the current pick, a header that
//  states the action can't be undone, and one dialog that reshapes itself for
//  web, tablet, and phone. On top of that this one adds a search field (five
//  agencies today, but the list is meant to grow) and the notify-banner from the
//  design.
//
//  Contract with the caller (unchanged from the old picker so endorse logic
//  stays put): resolves to
//    • null  → cancelled / dismissed, do nothing;
//    • ''    → clear the current endorsement;
//    • name  → endorse to that agency's canonical [StaffDept] name.
//  Responsiveness mirrors the Accept dialog — see that file's header.
// ════════════════════════════════════════════════════════════════════════════

const Color _selectBlue = Color(0xFF2563EB);

/// One external agency as shown on a card. [name] is the canonical
/// [StaffDepartments.external] value returned to the caller; [display] is the
/// localized label ("PNP Aparri") and [full] the spelled-out agency name.
class _AgencyData {
  final String name;
  final String display;
  final String full;
  final String asset;
  final String tag;
  final Color tagBg;
  final Color tagFg;
  const _AgencyData(
    this.name,
    this.display,
    this.full,
    this.asset,
    this.tag,
    this.tagBg,
    this.tagFg,
  );

  /// Everything the search field matches against.
  String get haystack => '$display $full $tag $name'.toLowerCase();
}

const List<_AgencyData> _agencies = [
  _AgencyData(
    'PNP',
    'PNP Aparri',
    'Philippine National Police',
    'assets/images/report/pnp.webp',
    'Peace & Order',
    Color(0xFFEEF2FF),
    Color(0xFF4F46E5),
  ),
  _AgencyData(
    'BFP',
    'BFP Aparri',
    'Bureau of Fire Protection',
    'assets/images/report/bfp.webp',
    'Fire Safety & Rescue',
    Color(0xFFFFF3E8),
    Color(0xFFEA580C),
  ),
  _AgencyData(
    'DPWH',
    'DPWH',
    'Department of Public Works and Highways',
    'assets/images/report/dpwh.webp',
    'Infrastructure & Roads',
    Color(0xFFFDECEC),
    Color(0xFFDC2626),
  ),
  _AgencyData(
    'DENR',
    'DENR',
    'Department of Environment and Natural Resources',
    'assets/images/report/denr.webp',
    'Environment & Sustainability',
    Color(0xFFE9F9EE),
    Color(0xFF16A34A),
  ),
  _AgencyData(
    'DOH',
    'DOH',
    'Department of Health',
    'assets/images/report/doh.webp',
    'Public Health & Well-Being',
    Color(0xFFF3EEFF),
    Color(0xFF7C3AED),
  ),
];

/// Shows the Endorse dialog. [currentEndorsement] (if the report is already
/// endorsed) starts selected so "Change endorsement" opens on the current pick
/// and enables the clear affordance. See the contract in the file header for
/// the resolved value.
Future<String?> showEndorseEntityDialog(
  BuildContext context, {
  String? currentEndorsement,
}) {
  return showAppDialog<String>(
    context: context,
    builder: (_) =>
        _EndorseEntityDialog(currentEndorsement: currentEndorsement),
  );
}

class _EndorseEntityDialog extends StatefulWidget {
  final String? currentEndorsement;
  const _EndorseEntityDialog({this.currentEndorsement});

  @override
  State<_EndorseEntityDialog> createState() => _EndorseEntityDialogState();
}

class _EndorseEntityDialogState extends State<_EndorseEntityDialog> {
  late String? _selected = widget.currentEndorsement;
  String _query = '';

  List<_AgencyData> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _agencies;
    return _agencies.where((a) => a.haystack.contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final narrow = media.size.width < 640;
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
          maxWidth: 880,
          maxHeight: media.size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(narrow),
            const Divider(height: 1, color: AdminUi.border),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                    narrow ? 16 : 24, 18, narrow ? 16 : 24, 8),
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

  // ── Header: paper-plane seal, title, irreversible notice, and close ────────
  Widget _header(bool narrow) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        narrow ? 16 : 28,
        narrow ? 18 : 24,
        narrow ? 8 : 16,
        narrow ? 16 : 22,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: narrow ? 52 : 64,
            height: narrow ? 52 : 64,
            decoration: const BoxDecoration(
              color: Color(0xFFEAF1FF),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.send_rounded,
                size: narrow ? 24 : 28, color: _selectBlue),
          ),
          SizedBox(width: narrow ? 14 : 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Endorse to External Entity',
                  style: TextStyle(
                    fontSize: narrow ? 20 : 25,
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
                            'Send this report to the appropriate external '
                            'agency for action and follow-up. ',
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
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
            color: AdminUi.textMuted,
            splashRadius: 20,
            tooltip: 'Cancel',
          ),
        ],
      ),
    );
  }

  Widget _body(bool narrow) {
    final label = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Select External Entity',
          style: TextStyle(
            fontSize: narrow ? 16 : 18,
            fontWeight: FontWeight.w700,
            color: AdminUi.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Choose the agency or department that best handles this report.',
          style: TextStyle(fontSize: 12.5, color: AdminUi.textMuted),
        ),
      ],
    );

    final search = _searchField(narrow);
    final list = _filtered;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label left, search right on wide; stacked on phone.
        if (narrow) ...[
          label,
          const SizedBox(height: 12),
          search,
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: label),
              const SizedBox(width: 16),
              SizedBox(width: 240, child: search),
            ],
          ),
        const SizedBox(height: 16),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: Text(
                'No agency matches "${_query.trim()}".',
                style: const TextStyle(
                    fontSize: 13, color: AdminUi.textMuted),
              ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, c) {
              const gap = 12.0;
              // Two columns wherever a pair of cards fits, one when too narrow.
              final cols = c.maxWidth >= 260 ? 2 : 1;
              final itemW = (c.maxWidth - gap * (cols - 1)) / cols;
              // The roomy horizontal card needs width; below that a card is
              // laid out compact/vertical so a 2×2 on a phone still reads well.
              final compact = itemW < 300;
              return _equalRowsGrid(
                cols: cols,
                cards: [
                  for (final a in list) _agencyCard(a, compact: compact),
                ],
              );
            },
          ),
        const SizedBox(height: 18),
        _notifyBanner(),
      ],
    );
  }

  Widget _searchField(bool narrow) {
    return TextField(
      onChanged: (v) => setState(() => _query = v),
      style: const TextStyle(fontSize: 13.5, color: AdminUi.textPrimary),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Search agency…',
        hintStyle: const TextStyle(fontSize: 13.5, color: AdminUi.textMuted),
        prefixIcon: const Icon(Icons.search_rounded,
            size: 19, color: AdminUi.textMuted),
        prefixIconConstraints:
            const BoxConstraints(minWidth: 38, minHeight: 38),
        contentPadding: const EdgeInsets.symmetric(vertical: 11),
        filled: true,
        fillColor: AdminUi.subtle,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AdminUi.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AdminUi.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _selectBlue, width: 1.5),
        ),
      ),
    );
  }

  /// Lays [cards] out [cols]-per-row with every card in a row stretched to the
  /// same height, so a longer agency name never leaves its neighbour a
  /// different size. A short final row is padded with invisible spacers.
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

  Widget _agencyCard(_AgencyData a, {bool compact = false}) {
    final selected = _selected == a.name;

    final logo = SizedBox(
      width: 52,
      height: 52,
      child: Image.asset(a.asset, fit: BoxFit.contain),
    );

    final tag = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: a.tagBg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        a.tag,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: a.tagFg,
        ),
      ),
    );

    // Hollow ring / filled check — the same selection marker in both layouts.
    final check = Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: selected ? _selectBlue : null,
        shape: BoxShape.circle,
        border: selected
            ? null
            : Border.all(color: AdminUi.border, width: 1.5),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
          : null,
    );

    final deco = BoxDecoration(
      color: selected ? const Color(0xFFF3F7FF) : AdminUi.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: selected ? _selectBlue : AdminUi.border,
        width: selected ? 2 : 1,
      ),
    );

    // Compact (phone 2×2): logo on top, everything centered, the check tucked
    // into the top-right corner so the narrow card stays balanced.
    if (compact) {
      return InkWell(
        onTap: () => setState(() => _selected = a.name),
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.fromLTRB(12, 18, 12, 14),
          decoration: deco,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  logo,
                  const SizedBox(height: 12),
                  Text(
                    a.display,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: selected ? _selectBlue : AdminUi.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '(${a.full})',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.3,
                      color: AdminUi.textMuted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  tag,
                ],
              ),
              if (selected)
                Positioned(top: -8, right: -6, child: check),
            ],
          ),
        ),
      );
    }

    // Roomy (web/tablet): logo left, details, check right — the original card.
    return InkWell(
      onTap: () => setState(() => _selected = a.name),
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        decoration: deco,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            logo,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    a.display,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: selected ? _selectBlue : AdminUi.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '(${a.full})',
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.3,
                      color: AdminUi.textMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  tag,
                ],
              ),
            ),
            check,
          ],
        ),
      ),
    );
  }

  Widget _notifyBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD8E4FF)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Icon(Icons.info_outline_rounded, size: 18, color: _selectBlue),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'The selected agency will be notified and can view this report '
              'in their portal.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: _selectBlue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer(bool narrow) {
    final canSend = _selected != null && _selected!.isNotEmpty;
    // Only offered when there's an endorsement to clear (the "Change" flow).
    final canClear = (widget.currentEndorsement ?? '').isNotEmpty;

    final clear = TextButton.icon(
      onPressed: () => Navigator.of(context).pop(''),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.red,
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
      ),
      icon: const Icon(Icons.link_off_rounded, size: 17),
      label: const Text('Clear endorsement'),
    );

    final cancel = OutlinedButton(
      onPressed: () => Navigator.of(context).pop(),
      style: OutlinedButton.styleFrom(
        foregroundColor: AdminUi.textSecondary,
        side: const BorderSide(color: AdminUi.borderStrong),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      child: const Text('Cancel'),
    );

    final send = FilledButton.icon(
      onPressed: canSend ? () => Navigator.of(context).pop(_selected) : null,
      style: FilledButton.styleFrom(
        backgroundColor: _selectBlue,
        disabledBackgroundColor: const Color(0xFFB9C7E8),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      icon: const Icon(Icons.send_rounded, size: 17),
      label: const Text('Send Endorsement'),
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
                SizedBox(width: double.infinity, child: send),
                const SizedBox(height: 10),
                SizedBox(width: double.infinity, child: cancel),
                if (canClear) ...[
                  const SizedBox(height: 4),
                  clear,
                ],
              ],
            )
          : Row(
              children: [
                if (canClear) clear,
                const Spacer(),
                cancel,
                const SizedBox(width: 12),
                send,
              ],
            ),
    );
  }
}
