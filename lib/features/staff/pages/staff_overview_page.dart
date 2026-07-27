import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../admin/providers/admin_reports_provider.dart' show ReportStatus;
import '../data/staff_repository.dart' show StaffConversation, StaffReport;
import '../providers/staff_providers.dart';
import '../theme/staff_ui.dart';
import '../widgets/staff_common.dart';

/// The staff landing page: a queue snapshot + quick jumps into the sections.
class StaffOverviewPage extends ConsumerWidget {
  /// Jump to a section by key: 'conversations' | 'reports' | 'endorsements'.
  final void Function(String key) onNavigate;
  const StaffOverviewPage({super.key, required this.onNavigate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(staffIdentityProvider).valueOrNull;
    final isExternal = identity?.isExternal ?? false;

    final convos = ref.watch(staffConversationsProvider).valueOrNull ?? const [];
    final reports = ref.watch(staffReportsProvider).valueOrNull ?? const [];
    final endorsed = ref.watch(staffEndorsementsProvider).valueOrNull ?? const [];

    // A poll that failed must be visible. A dashboard showing confident counts
    // from a refresh that silently died is worse than one admitting it is stale
    // — that is the exact silent-success failure this remediation kept finding.
    final staleSources = <String>[
      if (ref.watch(staffConversationsStaleProvider)) 'conversations',
      if (ref.watch(staffReportsStaleProvider)) 'reports',
      if (ref.watch(staffEndorsementsStaleProvider)) 'endorsements',
    ];

    // NOTE ON LATENCY: `waiting` is the counter served by the SLOWEST path.
    // A waiting ticket is by definition unassigned, and
    // trg_notify_staff_ticket_assigned only fires when
    // `assigned_staff_id IS NOT NULL AND is_ghost = false` — so an unassigned
    // ticket produces no notification, no ticketEvent bump, and no ~1s refresh.
    // It appears on the next 30s poll tick instead.
    //
    // That is exactly the case where nobody is on duty, i.e. the state most in
    // need of visibility is the one updated slowest. If someone asks why
    // Waiting lags while Active chats is instant, this is why. Fixing it needs
    // a trigger that fires on unassigned inserts too (or Broadcast in 7c), not
    // a change here.
    final waiting = convos.where((c) => c.isWaiting).length;
    final active = convos.where((c) => !c.isWaiting && !c.isResolved).length;
    final pendingReports =
        reports.where((r) => r.status != ReportStatus.resolved && r.status != ReportStatus.rejected).length;
    final resolvedReports =
        reports.where((r) => r.status == ReportStatus.resolved).length;
    final pendingEndorsed = endorsed
        .where((r) =>
            r.status != ReportStatus.resolved && r.status != ReportStatus.rejected)
        .length;

    // Live-queue rows for the dashboard: waiting chats first (most urgent), then
    // the staff member's active chats.
    final queue = [
      ...convos.where((c) => c.isWaiting),
      ...convos.where((c) => !c.isWaiting && !c.isResolved),
    ].take(5).toList();
    final recentReports = reports.take(5).toList();
    final recentEndorsed = endorsed.take(6).toList();

    return StaffPageBody(
      onRefresh: () async {
        await Future.wait([
          ref.read(staffConversationsProvider.notifier).refresh(),
          ref.read(staffReportsProvider.notifier).refresh(),
          ref.read(staffEndorsementsProvider.notifier).refresh(),
        ]);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (staleSources.isNotEmpty) ...[
            _StaleDashboardBanner(
              sources: staleSources,
              onRetry: () async {
                await Future.wait([
                  ref.read(staffConversationsProvider.notifier).poll(),
                  ref.read(staffReportsProvider.notifier).poll(),
                  ref.read(staffEndorsementsProvider.notifier).poll(),
                ]);
              },
            ),
            const SizedBox(height: 14),
          ],
          Text(
            '${_greeting()}${identity?.displayName != null ? ', ${identity!.displayName}' : ''}!',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: StaffUi.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            identity == null
                ? 'Your department queue'
                : '${identity.department}${isExternal ? ' · External entity' : ''}',
            style: const TextStyle(fontSize: 13.5, color: StaffUi.textMuted),
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, c) {
              final tiles = <Widget>[
                if (!isExternal) ...[
                  _StatTile(
                    label: 'Waiting',
                    value: '$waiting',
                    icon: Icons.hourglass_top_rounded,
                    color: StaffUi.warn,
                    onTap: () => onNavigate('conversations'),
                  ),
                  _StatTile(
                    label: 'Active chats',
                    value: '$active',
                    icon: Icons.forum_rounded,
                    color: StaffUi.accent,
                    onTap: () => onNavigate('conversations'),
                  ),
                  _StatTile(
                    label: 'Open reports',
                    value: '$pendingReports',
                    icon: Icons.flag_rounded,
                    color: const Color(0xFF2563EB),
                    onTap: () => onNavigate('reports'),
                  ),
                  _StatTile(
                    label: 'Resolved',
                    value: '$resolvedReports',
                    icon: Icons.check_circle_rounded,
                    color: StaffUi.online,
                    onTap: () => onNavigate('reports'),
                  ),
                ] else ...[
                  _StatTile(
                    label: 'Endorsed to us',
                    value: '${endorsed.length}',
                    icon: Icons.forward_to_inbox_rounded,
                    color: StaffUi.accent,
                    onTap: () => onNavigate('endorsements'),
                  ),
                  _StatTile(
                    label: 'Open',
                    value: '$pendingEndorsed',
                    icon: Icons.pending_actions_rounded,
                    color: StaffUi.warn,
                    onTap: () => onNavigate('endorsements'),
                  ),
                ],
              ];
              // Content-sized tiles laid out in IntrinsicHeight rows (mirrors the
              // admin dashboard) so they never bottom-overflow at any width. cols
              // is capped to the tile count so a 2-tile external view doesn't
              // stretch across 4 columns.
              final cols = (c.maxWidth >= 720 ? 4 : 2).clamp(1, tiles.length);
              return _statGrid(tiles, cols);
            },
          ),
          const SizedBox(height: 20),
          if (isExternal)
            _Panel(
              title: 'Recent endorsements',
              icon: Icons.forward_to_inbox_rounded,
              onViewAll: () => onNavigate('endorsements'),
              child: recentEndorsed.isEmpty
                  ? const _PanelEmpty(
                      icon: Icons.assignment_turned_in_outlined,
                      text: 'No endorsed reports yet.',
                    )
                  : Column(
                      children: [
                        for (final r in recentEndorsed)
                          _MiniReportRow(
                              report: r, onTap: () => onNavigate('endorsements')),
                      ],
                    ),
            )
          else
            LayoutBuilder(
              builder: (context, c) {
                final wide = c.maxWidth >= 720;
                final queuePanel = _Panel(
                  title: 'Live queue',
                  icon: Icons.forum_rounded,
                  onViewAll: () => onNavigate('conversations'),
                  child: queue.isEmpty
                      ? const _PanelEmpty(
                          icon: Icons.check_circle_outline_rounded,
                          text: "You're all caught up — no active chats.",
                        )
                      : Column(
                          children: [
                            for (final conv in queue)
                              _MiniConvRow(
                                conversation: conv,
                                onTap: () => onNavigate('conversations'),
                              ),
                          ],
                        ),
                );
                final reportsPanel = _Panel(
                  title: 'Recent reports',
                  icon: Icons.flag_rounded,
                  onViewAll: () => onNavigate('reports'),
                  child: recentReports.isEmpty
                      ? const _PanelEmpty(
                          icon: Icons.flag_outlined,
                          text: 'No reports for your department yet.',
                        )
                      : Column(
                          children: [
                            for (final r in recentReports)
                              _MiniReportRow(
                                  report: r, onTap: () => onNavigate('reports')),
                          ],
                        ),
                );
                if (!wide) {
                  return Column(
                    children: [
                      queuePanel,
                      const SizedBox(height: 14),
                      reportsPanel,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: queuePanel),
                    const SizedBox(width: 14),
                    Expanded(child: reportsPanel),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

/// A titled dashboard card with a header + "View all" affordance.
class _Panel extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onViewAll;
  final Widget child;
  const _Panel({
    required this.title,
    required this.icon,
    required this.onViewAll,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return StaffCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: StaffUi.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: StaffUi.textPrimary,
                  ),
                ),
              ),
              TextButton(
                onPressed: onViewAll,
                style: TextButton.styleFrom(
                  foregroundColor: StaffUi.accent,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('View all',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(padding: const EdgeInsets.only(right: 8), child: child),
        ],
      ),
    );
  }
}

class _PanelEmpty extends StatelessWidget {
  final IconData icon;
  final String text;
  const _PanelEmpty({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Row(
        children: [
          Icon(icon, size: 18, color: StaffUi.textMuted),
          const SizedBox(width: 10),
          Flexible(
            child: Text(text,
                style: const TextStyle(fontSize: 13, color: StaffUi.textMuted)),
          ),
        ],
      ),
    );
  }
}

/// A compact conversation row for the dashboard's live queue.
class _MiniConvRow extends StatelessWidget {
  final StaffConversation conversation;
  final VoidCallback onTap;
  const _MiniConvRow({required this.conversation, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            _MiniAvatar(
              label: c.citizenLabel,
              anonymous: c.isAnonymous,
              photoUrl: c.photoUrl,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.citizenLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: StaffUi.textPrimary,
                    ),
                  ),
                  Text(
                    c.category,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11.5, color: StaffUi.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (c.isWaiting)
              const StaffPill(label: 'New', color: StaffUi.warn)
            else
              Text(staffAgo(c.updatedAt ?? c.createdAt),
                  style: const TextStyle(fontSize: 10.5, color: StaffUi.textMuted)),
          ],
        ),
      ),
    );
  }
}

/// A compact report row for the dashboard's recent-reports / endorsements list.
class _MiniReportRow extends StatelessWidget {
  final StaffReport report;
  final VoidCallback onTap;
  const _MiniReportRow({required this.report, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final r = report;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: StaffUi.accentWash,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.report_gmailerrorred_rounded,
                  color: StaffUi.accent, size: 17),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.category,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: StaffUi.textPrimary,
                    ),
                  ),
                  Text(
                    staffAgo(r.createdAt),
                    style: const TextStyle(
                        fontSize: 11.5, color: StaffUi.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            StaffStatusPill(r.status),
          ],
        ),
      ),
    );
  }
}

/// Shown when any of the dashboard's three background polls failed. Names WHICH
/// list is stale, because the dashboard aggregates three independent sources
/// and "couldn't refresh" alone would leave staff guessing which numbers to
/// distrust. Tapping retries all three.
class _StaleDashboardBanner extends StatelessWidget {
  final List<String> sources;
  final Future<void> Function() onRetry;
  const _StaleDashboardBanner({required this.sources, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final what = sources.length == 1
        ? sources.first
        : '${sources.take(sources.length - 1).join(', ')} and ${sources.last}';
    return Material(
      color: StaffUi.warn.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onRetry,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.sync_problem_rounded,
                  size: 18, color: StaffUi.warn),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Couldn't refresh $what — these figures may be out of date.",
                  style: const TextStyle(
                      fontSize: 12.5,
                      color: StaffUi.textPrimary,
                      fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: 8),
              const Text('Retry',
                  style: TextStyle(
                      fontSize: 12.5,
                      color: StaffUi.warn,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return StaffCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      // Content-sized (no fixed height) so the tile grows to fit its text
      // instead of clipping — the grid places these in IntrinsicHeight rows.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const Icon(Icons.arrow_outward_rounded,
                  size: 16, color: StaffUi.textMuted),
            ],
          ),
          const SizedBox(height: 14),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: StaffUi.textPrimary,
              )),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: StaffUi.textMuted)),
        ],
      ),
    );
  }
}

/// The 32px dashboard live-queue avatar: citizen photo, default person icon
/// (anonymous), or name initial.
class _MiniAvatar extends StatelessWidget {
  final String label;
  final bool anonymous;
  final String? photoUrl;
  const _MiniAvatar({
    required this.label,
    required this.anonymous,
    required this.photoUrl,
  });

  @override
  Widget build(BuildContext context) {
    const d = 32.0;
    if (anonymous) {
      return Container(
        width: d,
        height: d,
        decoration:
            const BoxDecoration(color: StaffUi.subtle, shape: BoxShape.circle),
        child: const Icon(Icons.person_rounded, size: 18, color: StaffUi.textMuted),
      );
    }
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return Container(
        width: d,
        height: d,
        decoration: const BoxDecoration(shape: BoxShape.circle),
        clipBehavior: Clip.antiAlias,
        child: CachedNetworkImage(
          imageUrl: photoUrl!,
          fit: BoxFit.cover,
          errorWidget: (_, _, _) => _initial(),
        ),
      );
    }
    return _initial();
  }

  Widget _initial() {
    final t = label.trim();
    final ch = t.isEmpty ? 'C' : t.substring(0, 1).toUpperCase();
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: StaffUi.accent.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Text(ch,
          style: const TextStyle(
              color: StaffUi.accent, fontWeight: FontWeight.w700, fontSize: 13)),
    );
  }
}

/// Time-of-day greeting (local device time), matching the admin dashboard's
/// thresholds: morning < 12:00, afternoon < 18:00, evening after.
String _greeting() {
  final h = DateTime.now().hour;
  if (h < 12) return 'Good morning';
  if (h < 18) return 'Good afternoon';
  return 'Good evening';
}

/// Lays out stat tiles in [cols]-wide IntrinsicHeight rows so every tile in a
/// row shares the tallest one's height and none bottom-overflow — the same
/// content-sized approach used by the admin dashboard's KPI grid.
Widget _statGrid(List<Widget> tiles, int cols) {
  const gap = 12.0;
  final rows = <Widget>[];
  for (var i = 0; i < tiles.length; i += cols) {
    final end = (i + cols) > tiles.length ? tiles.length : i + cols;
    final slice = tiles.sublist(i, end);
    final children = <Widget>[];
    for (var j = 0; j < cols; j++) {
      children.add(
        Expanded(child: j < slice.length ? slice[j] : const SizedBox()),
      );
      if (j < cols - 1) children.add(const SizedBox(width: gap));
    }
    rows.add(
      IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
    if (end < tiles.length) rows.add(const SizedBox(height: gap));
  }
  return Column(children: rows);
}
