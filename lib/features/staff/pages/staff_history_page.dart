import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../admin/providers/admin_reports_provider.dart'
    show ReportStatus, reportStatusLabel;
import '../../admin/widgets/report_detail_kit.dart' show ReportCategoryIconBox;
import '../data/staff_repository.dart';
import '../providers/staff_providers.dart';
import '../theme/staff_ui.dart';
import '../widgets/staff_common.dart';

/// A read-only log of the staff member's closed work — completed reports, or
/// closed endorsements for an external agency — fronted by a summary count so
/// the screen reads as a dashboard rather than a bare list.
class StaffHistoryPage extends ConsumerWidget {
  const StaffHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(staffIdentityProvider).valueOrNull;
    final isExternal = identity?.isExternal ?? false;

    final reportsSrc = isExternal
        ? (ref.watch(staffEndorsementsProvider).valueOrNull ?? const [])
        : (ref.watch(staffReportsProvider).valueOrNull ?? const []);
    final reports = reportsSrc
        .where((r) =>
            r.status == ReportStatus.resolved ||
            r.status == ReportStatus.rejected)
        .toList();

    final empty = reports.isEmpty;

    return StaffPageBody(
      onRefresh: () async {
        await Future.wait([
          if (isExternal)
            ref.read(staffEndorsementsProvider.notifier).refresh()
          else
            ref.read(staffReportsProvider.notifier).refresh(),
        ]);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (empty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: StaffEmptyState(
                icon: Icons.history_rounded,
                title: 'Nothing here yet',
                subtitle:
                    'Completed reports will show up here.',
              ),
            )
          else ...[
            // ── Summary ────────────────────────────────────────────────────
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _SummaryTile(
                      icon: Icons.flag_rounded,
                      label: isExternal
                          ? 'Endorsements closed'
                          : 'Completed reports',
                      count: reports.length,
                      color: StaffUi.online,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),

            // ── Completed reports ──────────────────────────────────────────
            if (reports.isNotEmpty) ...[
              _SectionHeader(
                icon: Icons.flag_outlined,
                title:
                    isExternal ? 'Closed endorsements' : 'Completed reports',
                count: reports.length,
              ),
              const SizedBox(height: 12),
              for (final r in reports)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ReportCard(report: r),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

// ── Summary tile ──────────────────────────────────────────────────────────────

class _SummaryTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final Color color;
  const _SummaryTile({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return StaffCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$count',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: StaffUi.textPrimary,
                    height: 1.1,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: StaffUi.textMuted,
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

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final int count;
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 17, color: StaffUi.textSecondary),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: StaffUi.textPrimary,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: StaffUi.subtle,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: StaffUi.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Resolved conversation card ────────────────────────────────────────────────

// ── Completed report card ─────────────────────────────────────────────────────

class _ReportCard extends StatelessWidget {
  final StaffReport report;
  const _ReportCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final r = report;
    final color = staffReportStatusColor(r.status);
    final barangay = (r.barangay ?? '').trim();

    return StaffCard(
      padding: const EdgeInsets.all(13),
      child: Row(
        children: [
          // The category's illustration, same as the Reports list — the card is
          // labelled by category, so the icon should say the same thing. The
          // status still reads from the pill beside the barangay.
          ReportCategoryIconBox(r.categoryKey, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.category,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: StaffUi.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    '#${r.shortId}',
                    if (barangay.isNotEmpty) barangay,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: StaffUi.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              StaffPill(label: reportStatusLabel(r.status), color: color),
              const SizedBox(height: 6),
              Text(
                staffAgo(r.createdAt),
                style: const TextStyle(fontSize: 11, color: StaffUi.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
