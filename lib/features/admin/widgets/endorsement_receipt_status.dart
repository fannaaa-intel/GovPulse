import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../theme/admin_ui.dart';

// ════════════════════════════════════════════════════════════════════════════
//  "Has the agency actually picked this up?"
//
//  Endorsing a report hands it to an office with no account, reachable only by
//  a printed letter. Until now the console could say a report WAS endorsed and
//  nothing about what happened next — an admin chasing DPWH had no way to tell
//  a letter that never arrived from one being worked on, short of phoning.
//
//  report_endorsements has carried the answer since 20260801000000 (state,
//  received_at, completed_at) and admins have held a SELECT policy on it the
//  whole time. Nothing read it. This does.
//
//  Renders nothing when there is no endorsement row, so it is safe to drop into
//  a detail pane unconditionally.
// ════════════════════════════════════════════════════════════════════════════

class EndorsementReceiptStatus extends StatefulWidget {
  final String reportId;
  const EndorsementReceiptStatus({super.key, required this.reportId});

  @override
  State<EndorsementReceiptStatus> createState() =>
      _EndorsementReceiptStatusState();
}

class _EndorsementReceiptStatusState extends State<EndorsementReceiptStatus> {
  Map<String, dynamic>? _row;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Supabase.instance.client
          .from('report_endorsements')
          .select('reference_code, agency, state, endorsed_at, received_at, '
              'completed_at')
          .eq('report_id', widget.reportId)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _row = r;
        _loading = false;
      });
    } catch (_) {
      // Never a blocker: this is supplementary detail beside the routing facts
      // the dialog already shows from the report row itself.
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Label, colour, and what it means in plain words — keyed on the agency-side
  /// lifecycle, not on reports.status. The two are mirrored but not identical:
  /// an admin chasing a letter needs the letter's state.
  ({String label, Color color, String meaning}) _stateFacts(String s) {
    switch (s) {
      case 'received':
        return (
          label: 'Received by the agency',
          color: AppColors.primaryBlue,
          meaning: 'They scanned the letter and confirmed they have it.',
        );
      case 'completed':
        return (
          label: 'Completed by the agency',
          color: AppColors.green,
          meaning: 'They marked the work finished.',
        );
      case 'withdrawn':
        return (
          label: 'Withdrawn',
          color: AdminUi.textMuted,
          meaning:
              'The endorsement was taken back. The printed letter no longer '
              'works.',
        );
      default:
        return (
          label: 'Awaiting acknowledgement',
          color: const Color(0xFFEA580C),
          meaning:
              'The letter has been issued but nobody has scanned it yet.',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _row == null) return const SizedBox.shrink();

    final row = _row!;
    final facts = _stateFacts((row['state'] as String?) ?? 'endorsed');
    final reference = (row['reference_code'] as String?) ?? '';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: facts.color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: facts.color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Wrap, not Row: the label plus a reference code plus a timestamp
          // outgrows a 360px phone, and this pane is also rendered on one.
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(Icons.mark_email_read_outlined,
                  size: 16, color: facts.color),
              Text(
                facts.label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: facts.color,
                ),
              ),
              if (reference.isNotEmpty)
                Text(
                  reference,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AdminUi.textMuted,
                    letterSpacing: 0.4,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            facts.meaning,
            style: const TextStyle(
              fontSize: 12,
              height: 1.4,
              color: AdminUi.textSecondary,
            ),
          ),
          for (final e in [
            ('Letter issued', row['endorsed_at']),
            ('Acknowledged', row['received_at']),
            ('Completed', row['completed_at']),
          ])
            if (e.$2 != null) ...[
              const SizedBox(height: 4),
              Text(
                '${e.$1}: ${_stamp('${e.$2}')}',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AdminUi.textMuted,
                ),
              ),
            ],
        ],
      ),
    );
  }

  String _stamp(String raw) {
    final d = DateTime.tryParse(raw)?.toLocal();
    if (d == null) return raw;
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.day}/${d.month}/${d.year} $hh:$mm';
  }
}
