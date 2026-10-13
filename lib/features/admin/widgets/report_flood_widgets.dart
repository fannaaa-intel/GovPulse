// ════════════════════════════════════════════════════════════════════════════
//  Admin reports — report-flood widgets (20261014000000)
//
//  SimilarReportsChip: "N similar" on a ticket that looks like the same issue
//  as other open tickets. ReportSurgeBanner: raised over the queue when one
//  issue arrives many times in a short window. Both are advisory; the merge
//  itself is the admin's, from the report's detail pane.
// ════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/admin_reports_provider.dart';
import '../theme/admin_ui.dart';
import 'report_detail_kit.dart' show ChipDensity;

/// "N similar" — other open tickets that look like the same issue. Red when
/// the group is a surge (many in a short window), orange otherwise. Opening
/// the report shows them and the merge controls.
class SimilarReportsChip extends StatelessWidget {
  final int count;
  final bool surge;
  final ChipDensity density;
  const SimilarReportsChip(
    this.count, {
    super.key,
    this.surge = false,
    this.density = ChipDensity.full,
  });

  @override
  Widget build(BuildContext context) {
    final color = surge ? AppColors.red : AppColors.orange;
    final label = switch (density) {
      ChipDensity.full => '$count similar',
      ChipDensity.compact => '+$count',
      ChipDensity.icon => null,
    };
    final others = count == 1 ? 'report looks' : 'reports look';
    return Tooltip(
      message: surge
          ? '$count other open $others like the same issue, many of them in '
                'the last day. Open to review and merge.'
          : '$count other open $others like the same issue. Open to review '
                'and merge.',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: label == null ? 4 : 7,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.copy_all_rounded, size: 11, color: color),
            if (label != null) ...[
              const SizedBox(width: 3),
              Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Raised above the queue when one issue is arriving many times in a short
/// window — the shape a flood of reports takes, whether from one angry street
/// or a coordinated push. Each line opens a ticket from the group, where the
/// candidates and "Merge all" live.
class ReportSurgeBanner extends StatelessWidget {
  final List<ReportSurge> surges;
  final ValueChanged<AdminReport> onReview;
  const ReportSurgeBanner({
    super.key,
    required this.surges,
    required this.onReview,
  });

  @override
  Widget build(BuildContext context) {
    final shown = surges.take(3).toList();
    final more = surges.length - shown.length;
    final groups = more == 1 ? 'group' : 'groups';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AdminUi.cardRadius),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.campaign_rounded, size: 18, color: AppColors.red),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Many reports about the same issue',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AdminUi.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(26, 2, 6, 6),
            child: Text(
              'Open one to see them together and merge them into a single '
              'ticket. Nothing is merged until you say so.',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: AdminUi.textSecondary,
              ),
            ),
          ),
          for (final g in shown) _SurgeLine(group: g, onReview: onReview),
          if (more > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(26, 2, 6, 4),
              child: Text(
                '+$more more $groups. Look for the red "similar" chips in '
                'the list.',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AdminUi.textMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SurgeLine extends StatelessWidget {
  final ReportSurge group;
  final ValueChanged<AdminReport> onReview;
  const _SurgeLine({required this.group, required this.onReview});

  @override
  Widget build(BuildContext context) {
    final r = group.representative;
    final where = (r.barangay == null || r.barangay!.isEmpty)
        ? ''
        : ' in ${r.barangay}';
    return Padding(
      padding: const EdgeInsets.only(left: 26),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${group.recentCount} ${r.category}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: ' reports$where in the last day'),
                ],
              ),
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: AdminUi.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => onReview(r),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.red,
              minimumSize: const Size(44, 40),
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            child: const Text(
              'Review',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}
