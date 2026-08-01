import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

import '../../../core/config/app_config.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../core/widgets/qr_view.dart';
import '../providers/admin_reports_provider.dart';
import '../theme/admin_ui.dart';
import '../utils/endorsement_letter_pdf.dart';

// ════════════════════════════════════════════════════════════════════════════
//  "Endorsement sent" — the one and only time the PIN is ever shown
//
//  This dialog exists because of a hard constraint in the backend: only a
//  bcrypt hash of the PIN is stored, so the plaintext lives exactly as long as
//  this widget does. If the admin closes it without noting the PIN down, the
//  agency can never confirm receipt and the report has to be re-endorsed (which
//  mints a new PIN and invalidates the letter already printed).
//
//  So the design does three things, in this order of prominence:
//    1. shows the PIN large, monospaced and copyable, with the warning that it
//       will not be shown again;
//    2. makes clear it travels SEPARATELY from the letter — the QR on the paper
//       and the PIN are two factors, and mailing them together collapses them
//       into one;
//    3. offers the letter itself to download or print.
//
//  The close affordance is deliberately a considered one ("I've saved the PIN")
//  rather than an X in the corner, because a stray click here costs real work.
// ════════════════════════════════════════════════════════════════════════════

const Color _ok = Color(0xFF16A34A);
const Color _warnBg = Color(0xFFFFF7ED);
const Color _warnBorder = Color(0xFFFED7AA);
const Color _warnInk = Color(0xFF9A3412);

Future<void> showEndorsementSuccessDialog(
  BuildContext context, {
  required AdminReport report,
  required EndorsementCredentials credentials,
  required String reason,
}) {
  return showAppDialog<void>(
    context: context,
    // The PIN is unrecoverable once this closes, so a tap on the scrim must not
    // be able to throw it away.
    barrierDismissible: false,
    builder: (_) => _EndorsementSuccessDialog(
      report: report,
      credentials: credentials,
      reason: reason,
    ),
  );
}

class _EndorsementSuccessDialog extends StatefulWidget {
  final AdminReport report;
  final EndorsementCredentials credentials;
  final String reason;

  const _EndorsementSuccessDialog({
    required this.report,
    required this.credentials,
    required this.reason,
  });

  @override
  State<_EndorsementSuccessDialog> createState() =>
      _EndorsementSuccessDialogState();
}

class _EndorsementSuccessDialogState extends State<_EndorsementSuccessDialog> {
  bool _busy = false;

  String get _scanUrl => AppConfig.scanUrl(widget.credentials.token);

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final narrow = media.size.width < 640;

    return Dialog(
      backgroundColor: AdminUi.surface,
      insetPadding: narrow
          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 24)
          : const EdgeInsets.all(40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 720,
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
                  narrow ? 16 : 24,
                  18,
                  narrow ? 16 : 24,
                  18,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _pinCard(narrow),
                    const SizedBox(height: 18),
                    _letterCard(narrow),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: AdminUi.border),
            _footer(narrow),
          ],
        ),
      ),
    );
  }

  Widget _header(bool narrow) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        narrow ? 16 : 28,
        narrow ? 18 : 24,
        narrow ? 16 : 28,
        narrow ? 16 : 22,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: narrow ? 46 : 56,
            height: narrow ? 46 : 56,
            decoration: const BoxDecoration(
              color: Color(0xFFE8F7EE),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check_rounded,
              size: narrow ? 24 : 28,
              color: _ok,
            ),
          ),
          SizedBox(width: narrow ? 14 : 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Endorsement sent',
                  style: TextStyle(
                    fontSize: narrow ? 20 : 24,
                    fontWeight: FontWeight.w800,
                    color: AdminUi.textPrimary,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'RPT-${widget.report.shortId} has been endorsed to '
                  '${widget.credentials.agency}. '
                  'Reference ${widget.credentials.reference}.',
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.35,
                    color: AdminUi.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── The PIN ───────────────────────────────────────────────────────────────

  Widget _pinCard(bool narrow) {
    final pin = widget.credentials.pin;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _warnBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _warnBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.key_rounded, size: 18, color: _warnInk),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Confirmation PIN — shown only once',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: _warnInk,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 14,
            runSpacing: 12,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _warnBorder),
                ),
                child: SelectableText(
                  pin,
                  style: TextStyle(
                    fontSize: narrow ? 34 : 42,
                    fontWeight: FontWeight.w800,
                    // Tabular figures and wide tracking: this gets read aloud
                    // over a phone and typed into another device, so 0/O and
                    // 1/7 must not be a guess.
                    fontFeatures: const [FontFeature.tabularFigures()],
                    letterSpacing: 10,
                    color: AdminUi.textPrimary,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: pin));
                  if (!mounted) return;
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                    const SnackBar(content: Text('PIN copied')),
                  );
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: _warnInk,
                  side: const BorderSide(color: _warnBorder),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Copy'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Send this PIN to the agency separately from the letter — by phone, '
            'SMS, or a separate email. It is not printed on the endorsement, '
            'and it is what stops anyone who merely photographs the QR code '
            'from changing the report\'s status.',
            style: TextStyle(fontSize: 12.5, height: 1.45, color: _warnInk),
          ),
          const SizedBox(height: 8),
          const Text(
            'It cannot be recovered after this dialog closes. If it is lost, '
            'endorse the report again to issue a new PIN and letter.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: _warnInk,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ── The letter ────────────────────────────────────────────────────────────

  Widget _letterCard(bool narrow) {
    final qr = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(border: Border.all(color: AdminUi.border)),
          child: QrView(data: _scanUrl, size: 148),
        ),
        const SizedBox(height: 8),
        const SizedBox(
          width: 148,
          child: Text(
            'Scan to confirm receipt and update status.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, height: 1.3, color: AdminUi.textMuted),
          ),
        ),
      ],
    );

    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Endorsement letter',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AdminUi.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'A formal letter for the Mayor\'s signature, with this QR code '
          'printed at the bottom.',
          style: TextStyle(fontSize: 12.5, height: 1.4, color: AdminUi.textMuted),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _download,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 13,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              icon: const Icon(Icons.download_rounded, size: 17),
              label: const Text('Download PDF'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _print,
              style: OutlinedButton.styleFrom(
                foregroundColor: AdminUi.textSecondary,
                side: const BorderSide(color: AdminUi.borderStrong),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 13,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              icon: const Icon(Icons.print_rounded, size: 17),
              label: const Text('Print'),
            ),
          ],
        ),
        if (_busy) ...[
          const SizedBox(height: 12),
          const SizedBox(
            height: 2,
            width: 160,
            child: LinearProgressIndicator(),
          ),
        ],
      ],
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AdminUi.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminUi.border),
      ),
      child: narrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [copy, const SizedBox(height: 18), Center(child: qr)],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: copy),
                const SizedBox(width: 20),
                qr,
              ],
            ),
    );
  }

  Widget _footer(bool narrow) {
    final done = FilledButton(
      onPressed: () => Navigator.of(context).pop(),
      style: FilledButton.styleFrom(
        backgroundColor: AdminUi.textPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      child: const Text("I've saved the PIN"),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        narrow ? 16 : 24,
        14,
        narrow ? 16 : 24,
        narrow ? 16 : 18,
      ),
      child: narrow
          ? SizedBox(width: double.infinity, child: done)
          : Row(children: [const Spacer(), done]),
    );
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _download() async {
    setState(() => _busy = true);
    try {
      await exportEndorsementLetter(
        report: widget.report,
        credentials: widget.credentials,
        reason: widget.reason,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Could not build the letter: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _print() async {
    setState(() => _busy = true);
    try {
      final bytes = await buildEndorsementLetter(
        report: widget.report,
        credentials: widget.credentials,
        reason: widget.reason,
      );
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Could not print: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
