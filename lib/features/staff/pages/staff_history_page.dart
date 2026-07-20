import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../admin/providers/admin_reports_provider.dart'
    show ReportStatus, reportStatusLabel;
import '../data/staff_repository.dart';
import '../providers/staff_providers.dart';
import '../theme/staff_ui.dart';
import '../widgets/staff_common.dart';

/// A read-only log of the staff member's closed work — resolved conversations
/// and completed reports — fronted by a small summary of the two counts so the
/// screen reads as a dashboard rather than a bare list.
class StaffHistoryPage extends ConsumerWidget {
  const StaffHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(staffIdentityProvider).valueOrNull;
    final isExternal = identity?.isExternal ?? false;

    final convos =
        (ref.watch(staffConversationsProvider).valueOrNull ?? const [])
            .where((c) => c.isResolved)
            .toList();
    final reportsSrc = isExternal
        ? (ref.watch(staffEndorsementsProvider).valueOrNull ?? const [])
        : (ref.watch(staffReportsProvider).valueOrNull ?? const []);
    final reports = reportsSrc
        .where((r) =>
            r.status == ReportStatus.resolved ||
            r.status == ReportStatus.rejected)
        .toList();

    final empty = convos.isEmpty && reports.isEmpty;

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
          if (empty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: StaffEmptyState(
                icon: Icons.history_rounded,
                title: 'Nothing here yet',
                subtitle:
                    'Resolved chats and completed reports will show up here.',
              ),
            )
          else ...[
            // ── Summary ────────────────────────────────────────────────────
            // IntrinsicHeight bounds the cross-axis so `stretch` (which
            // equalises the two tile heights) doesn't demand infinite height
            // inside the scroll view.
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!isExternal) ...[
                    Expanded(
                      child: _SummaryTile(
                        icon: Icons.forum_rounded,
                        label: 'Resolved chats',
                        count: convos.length,
                        color: StaffUi.accent,
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
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

            // ── Resolved conversations ─────────────────────────────────────
            if (!isExternal && convos.isNotEmpty) ...[
              _SectionHeader(
                icon: Icons.forum_outlined,
                title: 'Resolved conversations',
                count: convos.length,
              ),
              const SizedBox(height: 12),
              for (final c in convos)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ConversationCard(convo: c),
                ),
              const SizedBox(height: 22),
            ],

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

class _ConversationCard extends StatelessWidget {
  final StaffConversation convo;
  const _ConversationCard({required this.convo});

  @override
  Widget build(BuildContext context) {
    final c = convo;
    final photo = c.photoUrl;
    final leading = (photo != null && photo.isNotEmpty)
        ? ClipOval(
            child: SizedBox(
              width: 40,
              height: 40,
              child: CachedNetworkImage(
                imageUrl: photo,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => _avatarFallback,
              ),
            ),
          )
        : _avatarFallback;

    return StaffCard(
      padding: const EdgeInsets.all(13),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.citizenLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: StaffUi.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        c.category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: StaffUi.textMuted,
                        ),
                      ),
                    ),
                    if (c.rating != null) ...[
                      const SizedBox(width: 8),
                      StaffStarRow(c.rating!, size: 12),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const StaffPill(
                label: 'Resolved',
                color: StaffUi.online,
                icon: Icons.check_circle_rounded,
              ),
              const SizedBox(height: 6),
              Text(
                staffAgo(c.updatedAt ?? c.createdAt),
                style: const TextStyle(fontSize: 11, color: StaffUi.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget get _avatarFallback => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: StaffUi.accentWash,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.forum_rounded,
            size: 18, color: StaffUi.accent),
      );
}

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
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(Icons.flag_rounded, size: 18, color: color),
          ),
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
