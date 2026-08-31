import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_dialog.dart';
import '../theme/admin_ui.dart';
import 'admin_dialog_keyboard.dart';
import 'admin_responsive_dialog.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Endorse to External Entity — routes an out-of-LGU-scope report to the
//  national agency that owns it (PNP, BFP, DPWH, DENR, DOH).
//
//  The sibling of the Accept & Assign dialog and built on the same rules: an
//  illustrated card per option, a blue check on the current pick, a header that
//  states what sending actually commits to, and one dialog that reshapes itself
//  for web, tablet, and phone. On top of that this one adds a search field (five
//  agencies today, but the list is meant to grow) and the notify-banner from the
//  design.
//
//  Contract with the caller: resolves to
//    • null                  → cancelled / dismissed, do nothing;
//    • EndorseChoice.clear   → clear the current endorsement;
//    • EndorseChoice(...)    → endorse to that agency's canonical [StaffDept]
//                              name, with the reason the admin typed.
//  Responsiveness mirrors the Accept dialog — see that file's header.
// ════════════════════════════════════════════════════════════════════════════

const Color _selectBlue = Color(0xFF2563EB);

/// Longest reason accepted. The reason is reproduced verbatim in the body of a
/// printed one-page letter, so this is a layout constraint as much as a data
/// one.
const int kEndorseReasonMaxLength = 600;

/// What the dialog resolves to. See the file header for the full contract.
class EndorseChoice {
  /// Canonical [StaffDepartments.external] name, or empty to clear.
  final String agency;

  /// Why the report is being endorsed. Required when [agency] is set; printed
  /// on the endorsement letter and shown on the agency's scan page.
  final String reason;

  const EndorseChoice({required this.agency, required this.reason});

  /// Drop the current endorsement and return the report to the LGU. [reason]
  /// carries the withdrawal justification, which is recorded on the
  /// endorsement's event log — see AdminReportsNotifier.clearEndorsement.
  static const EndorseChoice clear = EndorseChoice(agency: '', reason: '');

  /// A withdrawal with the admin's stated reason.
  static EndorseChoice clearWith(String reason) =>
      EndorseChoice(agency: '', reason: reason);

  bool get isClear => agency.isEmpty;
}

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
Future<EndorseChoice?> showEndorseEntityDialog(
  BuildContext context, {
  String? currentEndorsement,
}) {
  return showAppDialog<EndorseChoice>(
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

  final TextEditingController _reason = TextEditingController();

  /// Set once Send has been pressed with an empty reason, so the field only
  /// turns red after the admin has actually tried to submit — not while they
  /// are still picking an agency.
  bool _reasonTouched = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  String get _reasonText => _reason.text.trim();
  bool get _reasonMissing => _reasonText.isEmpty;

  /// Validates, then resolves the dialog. Endorsing hands ownership out of the
  /// LGU and mints a printed letter whose PIN is shown exactly once, so both
  /// fields are checked here as well as on the server.
  void _submit() {
    final agency = _selected;
    if (agency == null || agency.isEmpty) return;

    if (_reasonMissing) {
      setState(() => _reasonTouched = true);
      return;
    }

    Navigator.of(context).pop(
      EndorseChoice(agency: agency, reason: _reasonText),
    );
  }

  /// Withdrawing voids a signed letter and revokes the agency's credential, so
  /// it asks for a justification the same way endorsing does. The reason is
  /// recorded on the event log against the admin who withdrew it.
  Future<void> _confirmClear() async {
    // showAppDialog, not a bare showDialog: house rule (see app_dialog.dart) —
    // a plain showDialog is a pop-up that leaves differently from every other
    // pop-up, and skips the frosted backdrop the rest of the app uses.
    final reason = await showAppDialog<String>(
      context: context,
      builder: (_) => const _WithdrawEndorsementDialog(),
    );
    if (reason == null || !mounted) return;
    if (context.mounted) {
      Navigator.of(context).pop(EndorseChoice.clearWith(reason));
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // ── A modal on a desktop, a SCREEN on a phone ─────────────────────────
    //
    // This dialog is a form: a search field and a 2-up grid of agency cards.
    // On a 409px viewport the modal left it ~385px after its inset, minus its
    // own padding, floating on a barrier showing about 12px either side —
    // nothing gained by the float, and the grid paying for it twice, once in
    // the inset and once in the corner radius.
    //
    // `narrow` already drove every INTERNAL size at this same 640, so the
    // outer shape now changes on the same line rather than on a second one.
    final full = adminDialogIsFullscreen(context);

    // Read HERE, above the strip: this build's context sits outside the
    // [Dialog] returned below, so it still sees the real inset. Inside the
    // dialog it is always zero — see AdminDialogKeyboard.
    final keyboardUp = full && AdminDialogKeyboard.of(context);

    final Widget body = Column(
      mainAxisSize: full ? MainAxisSize.max : MainAxisSize.min,
      children: [
            _header(context, full),
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
              expand: full,
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                    full ? 16 : 24, 18, full ? 16 : 24, 8),
                child: _body(full),
              ),
            ),
            // The reason field is a 3-line textarea at the bottom of the body,
            // so the keyboard is up for most of the time this dialog is open.
            // While it is, the pinned bar is under the keyboard and unreachable
            // — it stands down and gives the body its height back.
            AdminKeyboardCollapse(
              keyboardUp: keyboardUp,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Divider(height: 1, color: AdminUi.border),
                  _footer(full),
                ],
              ),
            ),
      ],
    );

    if (full) {
      return Dialog(
        backgroundColor: AdminUi.surface,
        insetPadding: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: media.size.width,
          height: media.size.height,
          child: SafeArea(child: body),
        ),
      );
    }

    return Dialog(
      backgroundColor: AdminUi.surface,
      insetPadding: const EdgeInsets.all(40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 880,
          maxHeight: media.size.height * 0.9,
        ),
        child: body,
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  //
  // Delegates to [AdminDialogScreenHeader] so this dialog, Accept & Assign and
  // Reject all draw the SAME phone header: chevron on its own row, then the
  // seal beside the title and description. They had drifted into three
  // variations of it — see that widget's note.
  Widget _header(BuildContext context, bool narrow) {
    final seal = Container(
      width: narrow ? 52 : 64,
      height: narrow ? 52 : 64,
      decoration: const BoxDecoration(
        color: Color(0xFFEAF1FF),
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.send_rounded,
          size: narrow ? 24 : 28, color: _selectBlue),
    );

    final title = Text(
      'Endorse to External Entity',
      style: TextStyle(
        fontSize: narrow ? 18 : 25,
        fontWeight: FontWeight.w800,
        color: AdminUi.textPrimary,
        height: 1.1,
      ),
    );

    // The old copy read "This action cannot be undone", which was untrue in
    // three ways — this dialog's own Clear button, Accept-into-an-office, and a
    // staff bounce all withdraw an endorsement. What IS irreversible is the
    // letter: sending mints a PIN shown once, and withdrawing later voids the
    // printed QR rather than un-sending it.
    const description = Text.rich(
      TextSpan(
        style: TextStyle(
          fontSize: 13.5,
          height: 1.35,
          color: AdminUi.textSecondary,
        ),
        children: [
          TextSpan(
            text: 'Send this report to the appropriate external agency for '
                'action and follow-up. ',
          ),
          TextSpan(
            text: 'This issues a printed letter with a one-time PIN.',
            style: TextStyle(
              color: AppColors.red,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );

    final header = AdminDialogScreenHeader(
      full: narrow,
      seal: seal,
      title: title,
      description: description,
      padding: EdgeInsets.fromLTRB(
        narrow ? 16 : 28,
        narrow ? 18 : 24,
        narrow ? 16 : 28,
        narrow ? 16 : 22,
      ),
    );

    // ── The modal keeps NO ✕ either ────────────────────────────────────────
    //
    // The request asks for it gone at medium and large widths too. It was
    // always redundant here: the action bar carries an explicit Cancel, the
    // barrier is dismissible, and Esc pops the route — three ways out already,
    // and the ✕ was the only one that made the title share its row with a
    // control. Removing it lets the header block be identical at every width.
    return header;
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

    // ── No search field ───────────────────────────────────────────────────
    //
    // Five agencies, all of them on screen at once at every width. A search box
    // over a list you can already see in full is a control that can only ever
    // hide things, and on a phone it cost a row of height plus a keyboard the
    // picker never needed. If the roster grows past a screenful this comes
    // back — with the list, not ahead of it.
    final list = _agencies;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        label,
        const SizedBox(height: 16),
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
        const SizedBox(height: 20),
        _reasonField(narrow),
        const SizedBox(height: 18),
        _notifyBanner(),
      ],
    );
  }

  /// Required free-text justification.
  ///
  /// Not a formality: this sentence is reproduced verbatim in the body of the
  /// printed endorsement letter and shown to the receiving agency on the scan
  /// page, so it is the only place the LGU explains WHY the report is being
  /// handed over. The server enforces it too — a client-side-only requirement
  /// is not a requirement.
  Widget _reasonField(bool narrow) {
    final showError = _reasonTouched && _reasonMissing;

    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: c, width: w),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Flexible, not a bare Text: a Row hands its non-flex children an
        // UNBOUNDED main-axis constraint, so the label would never wrap and
        // would simply overflow once it outgrew the dialog — which it does on a
        // 360px phone at large system text scales.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: Text(
                'Reason for endorsement',
                style: TextStyle(
                  fontSize: narrow ? 16 : 18,
                  fontWeight: FontWeight.w700,
                  color: AdminUi.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              '*',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.red,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Explain why this report falls outside LGU scope. This appears on the '
          'printed endorsement letter.',
          style: TextStyle(fontSize: 12.5, color: AdminUi.textMuted),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _reason,
          maxLines: narrow ? 3 : 4,
          minLines: 3,
          maxLength: kEndorseReasonMaxLength,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) {
            // Once the admin starts typing, clear the error state on the first
            // keystroke rather than making them submit again to find out.
            if (_reasonTouched) setState(() {});
          },
          style: const TextStyle(fontSize: 13.5, color: AdminUi.textPrimary),
          decoration: InputDecoration(
            hintText:
                'e.g. The affected road is a national highway under DPWH '
                'jurisdiction, outside municipal maintenance authority.',
            hintStyle: const TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AdminUi.textMuted,
            ),
            errorText: showError
                ? 'A reason is required before this report can be endorsed.'
                : null,
            counterStyle: const TextStyle(
              fontSize: 11,
              color: AdminUi.textMuted,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            filled: true,
            fillColor: AdminUi.subtle,
            border: border(AdminUi.border),
            enabledBorder: border(showError ? AppColors.red : AdminUi.border),
            focusedBorder: border(
              showError ? AppColors.red : _selectBlue,
              1.5,
            ),
            errorBorder: border(AppColors.red),
            focusedErrorBorder: border(AppColors.red, 1.5),
          ),
        ),
      ],
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
    // ── Taller on the phone form ──────────────────────────────────────────
    //
    // 14px of vertical padding is right for a modal, where the buttons sit in a
    // row at their natural width and read as a pair of controls. Stacked
    // full-width on a phone they are the two biggest targets on the screen and
    // 14 left them looking thin — a wide, short slab rather than a button. 17
    // brings them to a ~50px tap target, which is also the first size that
    // clears the 48dp Material minimum with the text's own line box.
    final double vPad = narrow ? 17 : 14;

    final canSend = _selected != null && _selected!.isNotEmpty;
    // Only offered when there's an endorsement to clear (the "Change" flow).
    final canClear = (widget.currentEndorsement ?? '').isNotEmpty;

    final clear = TextButton.icon(
      onPressed: _confirmClear,
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
        padding: EdgeInsets.symmetric(horizontal: 22, vertical: vPad),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      child: const Text('Cancel'),
    );

    // Note the button stays ENABLED when the reason is blank. Greying it out
    // would leave the admin hunting for what is missing; pressing it surfaces
    // the error on the field itself, which says so.
    final send = FilledButton.icon(
      onPressed: canSend ? _submit : null,
      style: FilledButton.styleFrom(
        backgroundColor: _selectBlue,
        disabledBackgroundColor: const Color(0xFFB9C7E8),
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: vPad),
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

/// Withdraw an endorsement — a SCREEN on a phone, a modal above 640.
///
/// This was the last report-process dialog still drawn as a bare [AlertDialog].
/// It is a form with a required text field, so on a phone it had every problem
/// the others were fixed for: a small card floating on a barrier, an action bar
/// sitting on the keyboard while the officer typed, and buttons at Material's
/// bare minimum. It now takes the same shape as the reject and return-to-triage
/// forms — see admin_responsive_dialog.dart and AdminDialogKeyboard.
///
/// Resolves to the typed reason, or null on cancel. The reason is REQUIRED:
/// withdrawing voids a signed letter and revokes an agency's credential, and
/// the justification is recorded against the admin who did it.
class _WithdrawEndorsementDialog extends StatefulWidget {
  const _WithdrawEndorsementDialog();

  @override
  State<_WithdrawEndorsementDialog> createState() =>
      _WithdrawEndorsementDialogState();
}

class _WithdrawEndorsementDialogState
    extends State<_WithdrawEndorsementDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _canSubmit => _ctrl.text.trim().isNotEmpty;

  void _submit() {
    final v = _ctrl.text.trim();
    if (v.isEmpty) return;
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final full = adminDialogIsFullscreen(context);

    // Read HERE, above the strip: this build's context is outside the [Dialog]
    // returned below, so it still sees the real inset. Inside the dialog it is
    // always zero — see AdminDialogKeyboard.
    final keyboardUp = full && AdminDialogKeyboard.of(context);

    final body = Column(
      mainAxisSize: full ? MainAxisSize.max : MainAxisSize.min,
      children: [
        _header(full),
        const Divider(height: 1, color: AdminUi.border),
        AdminDialogFlex(
          expand: full,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(full ? 16 : 24, 18, full ? 16 : 24, 18),
            child: _field(),
          ),
        ),
        // One required textarea, so the keyboard is up for almost all of the
        // time this dialog is open. Under it the buttons are unreachable
        // anyway — they stand down and give the field the height.
        AdminKeyboardCollapse(
          keyboardUp: keyboardUp,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Divider(height: 1, color: AdminUi.border),
              _actions(full),
            ],
          ),
        ),
      ],
    );

    if (full) {
      return Dialog(
        backgroundColor: AdminUi.surface,
        insetPadding: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: media.size.width,
          height: media.size.height,
          child: SafeArea(child: body),
        ),
      );
    }

    return Dialog(
      backgroundColor: AdminUi.surface,
      insetPadding: const EdgeInsets.all(40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: media.size.height * 0.9,
        ),
        child: body,
      ),
    );
  }

  Widget _header(bool full) {
    final seal = Container(
      width: full ? 52 : 56,
      height: full ? 52 : 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.10),
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.link_off_rounded,
          size: full ? 24 : 26, color: AppColors.red),
    );

    final title = Text(
      'Withdraw this endorsement',
      style: TextStyle(
        fontSize: full ? 19 : 21,
        fontWeight: FontWeight.w800,
        color: AdminUi.textPrimary,
        height: 1.15,
      ),
    );

    const description = Text.rich(
      TextSpan(
        style: TextStyle(
          fontSize: 13,
          height: 1.4,
          color: AdminUi.textSecondary,
        ),
        children: [
          TextSpan(
            text: 'The report returns to the LGU and ',
          ),
          TextSpan(
            text: 'the printed letter stops working',
            style: TextStyle(
              color: AppColors.red,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(
            text: '. Say why — it is recorded against your account.',
          ),
        ],
      ),
    );

    return AdminDialogScreenHeader(
      full: full,
      seal: seal,
      title: title,
      description: description,
      padding: EdgeInsets.fromLTRB(
        full ? 16 : 24,
        full ? 18 : 22,
        full ? 16 : 24,
        full ? 16 : 20,
      ),
    );
  }

  Widget _field() {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: c, width: w),
    );

    return TextField(
      controller: _ctrl,
      autofocus: true,
      minLines: 3,
      maxLines: 5,
      maxLength: 300,
      textCapitalization: TextCapitalization.sentences,
      // The Withdraw button enables on the first keystroke rather than making
      // the admin press it to find out it is refused.
      onChanged: (_) => setState(() {}),
      style: const TextStyle(fontSize: 14, color: AdminUi.textPrimary),
      decoration: InputDecoration(
        hintText: 'e.g. DPWH confirmed the road is municipal after all.',
        hintStyle: const TextStyle(fontSize: 13, color: AdminUi.textMuted),
        counterStyle: const TextStyle(fontSize: 11, color: AdminUi.textMuted),
        contentPadding: const EdgeInsets.all(14),
        filled: true,
        fillColor: AdminUi.subtle,
        border: border(AdminUi.border),
        enabledBorder: border(AdminUi.border),
        focusedBorder: border(AppColors.red, 1.5),
      ),
    );
  }

  Widget _actions(bool full) {
    // Taller on the phone form — see the note in the reject dialog's
    // _actions(); the report-process footers must not disagree about a
    // button's height.
    final double vPad = full ? 17 : 14;

    final cancel = OutlinedButton(
      onPressed: () => Navigator.pop(context),
      style: OutlinedButton.styleFrom(
        foregroundColor: AdminUi.textSecondary,
        side: const BorderSide(color: AdminUi.borderStrong),
        padding: EdgeInsets.symmetric(horizontal: 22, vertical: vPad),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
      ),
      child: const Text('Cancel'),
    );

    final withdraw = FilledButton.icon(
      onPressed: _canSubmit ? _submit : null,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.red,
        disabledBackgroundColor: const Color(0xFFE8B4B4),
        padding: EdgeInsets.symmetric(horizontal: 22, vertical: vPad),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
      ),
      icon: const Icon(Icons.link_off_rounded, size: 17),
      label: const Text('Withdraw'),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        full ? 16 : 24,
        14,
        full ? 16 : 24,
        full ? 16 : 18,
      ),
      child: full
          ? Column(
              children: [
                SizedBox(width: double.infinity, child: withdraw),
                const SizedBox(height: 10),
                SizedBox(width: double.infinity, child: cancel),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [cancel, const SizedBox(width: 10), withdraw],
            ),
    );
  }
}
