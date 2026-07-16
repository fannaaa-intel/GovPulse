import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../admin/providers/admin_reports_provider.dart'
    show ReportStatus, reportStatusLabel;
import '../providers/staff_providers.dart';
import '../theme/staff_ui.dart';
import '../widgets/staff_common.dart';

/// A read-only log of the staff member's closed work — resolved conversations
/// and completed reports.
class StaffHistoryPage extends ConsumerWidget {
  const StaffHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(staffIdentityProvider).valueOrNull;
    final isExternal = identity?.isExternal ?? false;

    final convos = (ref.watch(staffConversationsProvider).valueOrNull ?? const [])
        .where((c) => c.isResolved)
        .toList();
    final reportsSrc = isExternal
        ? (ref.watch(staffEndorsementsProvider).valueOrNull ?? const [])
        : (ref.watch(staffReportsProvider).valueOrNull ?? const []);
    final reports = reportsSrc
        .where((r) =>
            r.status == ReportStatus.resolved || r.status == ReportStatus.rejected)
        .toList();

    return StaffPageBody(
      onRefresh: () async {
        await Future.wait([
          ref.read(staffConversationsProvider.notifier).refresh(),
          if (isExternal)
            ref.read(staffEndorsementsProvider.notifier).refresh()
          else
            ref.read(staffReportsProvider.notifier).refresh(),
        ]);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (convos.isEmpty && reports.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: StaffEmptyState(
                icon: Icons.history_rounded,
                title: 'Nothing here yet',
                subtitle: 'Resolved chats and completed reports will show up here.',
              ),
            ),
          if (!isExternal && convos.isNotEmpty) ...[
            const _SectionTitle('Resolved conversations'),
            for (final c in convos)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: StaffCard(
                  padding: const EdgeInsets.all(13),
                  child: Row(
                    children: [
                      const Icon(Icons.forum_outlined,
                          size: 18, color: StaffUi.textMuted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${c.citizenLabel} · ${c.category}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, color: StaffUi.textPrimary),
                        ),
                      ),
                      if (c.rating != null) ...[
                        StaffStarRow(c.rating!, size: 12),
                        const SizedBox(width: 8),
                      ],
                      Text(staffAgo(c.updatedAt ?? c.createdAt),
                          style: const TextStyle(
                              fontSize: 11, color: StaffUi.textMuted)),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
          ],
          if (reports.isNotEmpty) ...[
            const _SectionTitle('Completed reports'),
            for (final r in reports)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: StaffCard(
                  padding: const EdgeInsets.all(13),
                  child: Row(
                    children: [
                      const Icon(Icons.flag_outlined,
                          size: 18, color: StaffUi.textMuted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${r.category} · #${r.shortId}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, color: StaffUi.textPrimary),
                        ),
                      ),
                      StaffPill(
                        label: reportStatusLabel(r.status),
                        color: staffReportStatusColor(r.status),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: StaffUi.textPrimary,
            )),
      );
}
