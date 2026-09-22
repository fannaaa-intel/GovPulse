import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../admin/providers/admin_reports_provider.dart' show ReportStatus;
import '../../admin/widgets/report_detail_kit.dart' show ReportCategoryIconBox;
import '../data/staff_repository.dart' show StaffConversation, StaffReport;
import '../providers/staff_engagement_providers.dart';
import '../providers/staff_providers.dart';
import '../theme/staff_ui.dart';
import '../widgets/staff_common.dart';
import '../widgets/staff_performance_panels.dart';

/// The staff landing page: a queue snapshot + quick jumps into the sections.
///
/// ── Layout ─────────────────────────────────────────────────────────────────
/// Below [_kTabbedMaxWidth] this takes the ADMIN dashboard's shape: the
/// greeting and a segmented tab bar stay PINNED while only the active tab's
/// content scrolls beneath them. One long column put six stat tiles, two list
/// panels and two performance cards on a single scroll, so the performance
/// panels — the thing a staff member opens this page to check — sat two
/// screens down. Splitting it means each tab is about one screen.
///
/// At or above that width the whole column is shown at once: a desktop console
/// has the room, and hiding half of it behind a tab would be strictly worse.
/// The threshold matches the admin console's so the two change shape together.
class StaffOverviewPage extends ConsumerStatefulWidget {
  /// Jump to a section by key: 'conversations' | 'reports' | 'endorsements'.
  final void Function(String key) onNavigate;
  const StaffOverviewPage({super.key, required this.onNavigate});

  @override
  ConsumerState<StaffOverviewPage> createState() => _StaffOverviewPageState();
}

class _StaffOverviewPageState extends ConsumerState<StaffOverviewPage> {
  static const double _kTabbedMaxWidth = 1024;

  int _tab = 0;

  void Function(String key) get onNavigate => widget.onNavigate;

  @override
  Widget build(BuildContext context) {
    // Identity is the ROOT: every list provider waits on it for the department.
    // Until it lands the page would render a greeting with no name and six
    // tiles reading 0, which is indistinguishable from an office with no work.
    final identityAsync = ref.watch(staffIdentityProvider);
    if (identityAsync.isLoading && !identityAsync.hasValue) {
      return const StaffPageBodyStatic(child: _DashboardSkeleton());
    }
    final identity = identityAsync.valueOrNull;
    final isExternal = identity?.isExternal ?? false;

    final convos = ref.watch(staffConversationsProvider).valueOrNull ?? const [];
    final reports = ref.watch(staffReportsProvider).valueOrNull ?? const [];
    final endorsed = ref.watch(staffEndorsementsProvider).valueOrNull ?? const [];

    // Engagement, internal offices only. External agencies hold neither inbox.
    final pendingSuggestions =
        isExternal ? 0 : ref.watch(staffPendingSuggestionsProvider);
    final lowRatings = isExternal ? 0 : ref.watch(staffLowRatingsProvider);
    final hasFeedback = !isExternal && ref.watch(staffHasFeedbackProvider);
    final myCard = ref.watch(staffMyScorecardProvider).valueOrNull;
    final deptRating = ref.watch(staffAverageRatingProvider);
    final trend = ref.watch(staffRatingTrendProvider).valueOrNull ?? const [];

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
    ];
    final recentReportsAll = reports;
    final recentEndorsedAll = endorsed;

    // Three rows per panel, and a "+N more" line when there are more. Five made
    // the two panels different heights whenever one list was shorter than the
    // other, which is what made the dashboard look ragged; a fixed three plus a
    // fixed overflow line means both panels are the same height at every load,
    // and the full list is one tap away behind "View all".
    const kPanelRows = 3;
    final queueShown = queue.take(kPanelRows).toList();
    final reportsShown = recentReportsAll.take(kPanelRows).toList();
    final endorsedShown = recentEndorsedAll.take(kPanelRows).toList();

    Future<void> refreshAll() => Future.wait([
          ref.read(staffConversationsProvider.notifier).refresh(),
          ref.read(staffReportsProvider.notifier).refresh(),
          ref.read(staffEndorsementsProvider.notifier).refresh(),
        ]);

    final stale = staleSources.isEmpty
        ? null
        : _StaleDashboardBanner(
            sources: staleSources,
            onRetry: () async {
              await Future.wait([
                ref.read(staffConversationsProvider.notifier).poll(),
                ref.read(staffReportsProvider.notifier).poll(),
                ref.read(staffEndorsementsProvider.notifier).poll(),
              ]);
            },
          );

    final greeting = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
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
      ],
    );

    // ── The three section groups ───────────────────────────────────────────
    final statsSection = <Widget>[
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
                  _StatTile(
                    label: 'Suggestions to answer',
                    value: '$pendingSuggestions',
                    icon: Icons.lightbulb_outline_rounded,
                    color: pendingSuggestions > 0
                        ? StaffUi.warn
                        : StaffUi.textMuted,
                    onTap: () => onNavigate('suggestions'),
                  ),
                  // Omitted entirely for an office no feedback can reach: a
                  // permanent 0 invites someone to go looking for the list
                  // behind it, and there isn't one.
                  if (hasFeedback)
                    _StatTile(
                      label: 'Low ratings (7d)',
                      value: '$lowRatings',
                      icon: Icons.trending_down_rounded,
                      color:
                          lowRatings > 0 ? StaffUi.danger : StaffUi.textMuted,
                      onTap: () => onNavigate('feedback'),
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
              // admin dashboard) so they never bottom-overflow at any width.
              //
              // The column count DIVIDES the tile count where it can. Six tiles
              // in a 4-wide grid leaves a 4 + 2 split whose second row is half
              // empty — a dead gap the eye reads as a missing card. Six into
              // three is 3 + 3, which fills both rows. cols is also capped to
              // the tile count so a 2-tile external view doesn't stretch across
              // four columns.
              final int cols;
              if (c.maxWidth < 720) {
                cols = 2;
              } else if (tiles.length % 4 == 0) {
                cols = 4;
              } else if (tiles.length % 3 == 0) {
                cols = 3;
              } else {
                cols = 4;
              }
              return _statGrid(tiles, cols.clamp(1, tiles.length));
            },
          ),
        ];

    final queueSection = <Widget>[
          if (isExternal)
            _Panel(
              title: 'Recent endorsements',
              icon: Icons.forward_to_inbox_rounded,
              onViewAll: () => onNavigate('endorsements'),
              child: endorsedShown.isEmpty
                  ? const _PanelEmpty(
                      icon: Icons.assignment_turned_in_outlined,
                      text: 'No endorsed reports yet.',
                    )
                  : Column(
                      children: [
                        for (final r in endorsedShown)
                          _MiniReportRow(
                              report: r, onTap: () => onNavigate('endorsements')),
                        _MoreRow(
                          hidden: recentEndorsedAll.length - endorsedShown.length,
                          onTap: () => onNavigate('endorsements'),
                        ),
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
                  child: queueShown.isEmpty
                      ? const _PanelEmpty(
                          icon: Icons.check_circle_outline_rounded,
                          text: "You're all caught up — no active chats.",
                        )
                      : Column(
                          children: [
                            for (final conv in queueShown)
                              _MiniConvRow(
                                conversation: conv,
                                onTap: () => onNavigate('conversations'),
                              ),
                            _MoreRow(
                              hidden: queue.length - queueShown.length,
                              onTap: () => onNavigate('conversations'),
                            ),
                          ],
                        ),
                );
                final reportsPanel = _Panel(
                  title: 'Recent reports',
                  icon: Icons.flag_rounded,
                  onViewAll: () => onNavigate('reports'),
                  child: reportsShown.isEmpty
                      ? const _PanelEmpty(
                          icon: Icons.flag_outlined,
                          text: 'No reports for your department yet.',
                        )
                      : Column(
                          children: [
                            for (final r in reportsShown)
                              _MiniReportRow(
                                  report: r, onTap: () => onNavigate('reports')),
                            _MoreRow(
                              hidden: recentReportsAll.length -
                                  reportsShown.length,
                              onTap: () => onNavigate('reports'),
                            ),
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
                // stretch, NOT IntrinsicHeight: both cards take the height of
                // the taller one, so the row finishes on a single straight
                // edge. With CrossAxisAlignment.start each card kept its own
                // height and an empty Live queue beside a full Recent reports
                // left a visible step between the two columns.
                //
                // IntrinsicHeight would also equalise them, but it interrogates
                // every child for an intrinsic height, and any LayoutBuilder in
                // the subtree throws rather than answering. stretch needs no
                // such query — see the performance row below, where that is
                // exactly what crashed.
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: queuePanel),
                      const SizedBox(width: 14),
                      Expanded(child: reportsPanel),
                    ],
                  ),
                );
              },
            ),
        ];

    // Performance: this person's own card only. The ranked comparison against
    // colleagues is an ADMIN surface — a leaderboard pushed down to everyone
    // mostly produces gaming and resentment.
    final performanceSection = <Widget>[
          if (!isExternal && myCard != null)
            LayoutBuilder(
              builder: (context, c) {
                final scorecard = ScorecardPanel(
                  card: myCard,
                  // Half the row, so the four metric tiles get ~half the width.
                  compact: c.maxWidth < kMetricsCompactBelow * 2,
                  departmentRating: deptRating,
                  departmentReceivesRatings: hasFeedback,
                );
                // Only an office that receives ratings has a trend to draw.
                if (!hasFeedback || trend.isEmpty) return scorecard;
                final trendPanel = RatingTrendPanel(points: trend);
                // Same 720 threshold and the same even split as the queue /
                // reports row above. A 3:2 here against a 1:1 there put two
                // different column edges on one page, which is what made the
                // dashboard look ragged.
                if (c.maxWidth < 720) {
                  return Column(
                    children: [
                      scorecard,
                      const SizedBox(height: 14),
                      trendPanel,
                    ],
                  );
                }
                // Same rule as the queue / reports row above: the scorecard and
                // the trend chart end on one edge instead of the chart
                // stopping short.
                //
                // NO IntrinsicHeight here. ScorecardPanel lays its metric tiles
                // out with a LayoutBuilder, and a LayoutBuilder cannot report an
                // intrinsic dimension — wrapping this row in one throws
                // "LayoutBuilder does not support returning intrinsic
                // dimensions" at layout time and the whole dashboard fails to
                // render. A Row with CrossAxisAlignment.stretch already gives
                // both children the height of the taller one, which is all that
                // was wanted; it sizes from the natural row height instead of
                // interrogating each child for its intrinsic one.
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: scorecard),
                      const SizedBox(width: 14),
                      Expanded(child: trendPanel),
                    ],
                  ),
                );
              },
            ),
        ];

    // Tabs exist only where scrolling is the problem. An external agency has
    // one panel and no scorecard, so tabbing it would add a control that hides
    // nothing — and a one-tab bar is just a label.
    final tabs = <String>[
      'Overview',
      // An external agency has two stat tiles and ONE panel. Splitting that
      // across tabs hides nothing and costs a tap, and "Queue" is the wrong
      // word for an endorsement list anyway.
      if (!isExternal) 'Queue',
      if (performanceSection.isNotEmpty) 'Performance',
    ];
    // The label list shrinks when the scorecard has not loaded, so a stale
    // index must not point past the end.
    final tab = _tab.clamp(0, tabs.length - 1);

    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth >= _kTabbedMaxWidth || tabs.length < 2) {
          return StaffPageBody(
            onRefresh: refreshAll,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (stale != null) ...[stale, const SizedBox(height: 14)],
                greeting,
                const SizedBox(height: 18),
                ...statsSection,
                const SizedBox(height: 20),
                ...queueSection,
                if (performanceSection.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  ...performanceSection,
                ],
              ],
            ),
          );
        }

        final sections = switch (tabs[tab]) {
          'Queue' => queueSection,
          'Performance' => performanceSection,
          _ => statsSection,
        };
        final width = MediaQuery.of(context).size.width;
        final pad = width < 600 ? 14.0 : 24.0;

        return Container(
          color: StaffUi.pageBg,
          child: Column(
            children: [
              // Pinned: the greeting and the tab bar stay put so switching
              // tabs never means scrolling back up to find the control.
              Padding(
                padding: EdgeInsets.fromLTRB(pad, pad, pad, 0),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1080),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (stale != null) ...[
                          stale,
                          const SizedBox(height: 14),
                        ],
                        greeting,
                        const SizedBox(height: 16),
                        StaffSegmentedTabs(
                          labels: tabs,
                          selected: tab,
                          onSelect: (i) => setState(() => _tab = i),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  color: StaffUi.accent,
                  onRefresh: refreshAll,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(pad, 16, pad, pad + 40),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1080),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: sections,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
            // The category's illustration, same as the Reports list — the row
            // is labelled by category, so the icon should say the same thing.
            ReportCategoryIconBox(r.categoryKey, size: 32),
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

/// The "+N more" line that closes a dashboard panel.
///
/// Renders an empty slot of the same height when nothing is hidden, so two
/// panels side by side finish at the same y whether one list is longer than
/// the other or not. A panel that grows with its content made the two columns
/// different heights on every load, which is what read as ragged.
class _MoreRow extends StatelessWidget {
  final int hidden;
  final VoidCallback onTap;
  const _MoreRow({required this.hidden, required this.onTap});

  static const double height = 30;

  @override
  Widget build(BuildContext context) {
    if (hidden <= 0) return const SizedBox(height: height);
    return SizedBox(
      height: height,
      child: Align(
        alignment: Alignment.centerLeft,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Text(
              '+$hidden more',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: StaffUi.accent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}


/// Mirrors the dashboard's real shape: greeting, a six-tile grid, then two
/// side-by-side panels. Sized to the layout it stands in for, so nothing jumps
/// when the data lands.
class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return StaffShimmer(
      child: LayoutBuilder(
        builder: (context, c) {
          final cols = c.maxWidth < 720 ? 2 : 3;
          const gap = 12.0;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const StaffSkeletonBox(width: 240, height: 26),
              const SizedBox(height: 8),
              const StaffSkeletonBox(width: 150, height: 14),
              const SizedBox(height: 18),
              for (var r = 0; r < 2; r++) ...[
                Row(
                  children: [
                    for (var i = 0; i < cols; i++) ...[
                      const Expanded(
                        child: StaffSkeletonBox(height: 96, radius: 14),
                      ),
                      if (i < cols - 1) const SizedBox(width: gap),
                    ],
                  ],
                ),
                if (r == 0) const SizedBox(height: gap),
              ],
              const SizedBox(height: 20),
              if (c.maxWidth < 720)
                const Column(
                  children: [
                    StaffSkeletonBox(height: 150, radius: 14),
                    SizedBox(height: 14),
                    StaffSkeletonBox(height: 150, radius: 14),
                  ],
                )
              else
                const Row(
                  children: [
                    Expanded(child: StaffSkeletonBox(height: 170, radius: 14)),
                    SizedBox(width: 14),
                    Expanded(child: StaffSkeletonBox(height: 170, radius: 14)),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}
