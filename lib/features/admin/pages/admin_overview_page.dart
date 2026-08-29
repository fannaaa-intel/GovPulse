import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/admin_dashboard_provider.dart';
import '../providers/admin_feedback_provider.dart'
    show AdminFeedback, adminFeedbackProvider;
import '../providers/admin_reports_provider.dart'
    show ReportStatus, AdminReport, adminReportsProvider;
import '../providers/admin_suggestions_provider.dart'
    show AdminSuggestion, adminSuggestionsProvider;
import '../theme/admin_ui.dart';
import '../utils/analytics_pdf.dart';
import '../widgets/activity_visuals.dart';
import '../widgets/admin_skeleton.dart';
import '../widgets/admin_snackbar.dart';
import '../widgets/admin_submission_ui.dart';
import 'admin_recent_activity_page.dart';
import '../../../core/widgets/app_dialog.dart';

/// The dashboard's one transition length, collapsed to zero when the OS asks
/// for reduced motion (`prefers-reduced-motion` on web, "Remove animations" on
/// iOS/Android). Everything here animates a colour or an opacity, so removing
/// the tween just makes the change instant — nothing is lost but the movement.
Duration _motion(BuildContext context) => MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : const Duration(milliseconds: 150);

// Nav tab indices owned by the shell (AdminDashboardScreen.navItems). That list
// is private to the shell's State, so pages can't resolve it by label. Aliased
// to the activity feed's copies rather than re-declared: two independent sets
// of the same four numbers is exactly how a nav reorder breaks one caller and
// not the other.
const int _kTabReports = kActivityTabReports;
const int _kTabSuggestions = kActivityTabSuggestions;
const int _kTabFeedback = kActivityTabFeedback;

class AdminOverviewPage extends ConsumerStatefulWidget {
  final int selectedIndex;

  /// Lets the dashboard jump the shell to another section (e.g. Reports = 1).
  /// Wired by the dashboard screen; null elsewhere → tiles simply aren't tappable.
  ///
  /// [highlightId] deep-links to one row on the destination page, which scrolls
  /// it into view and flashes it — so tapping an insight lands on the exact
  /// feedback/report it was computed from, not just the right list.
  final void Function(int index, {String? highlightId})? onNavigate;

  const AdminOverviewPage({
    super.key,
    required this.selectedIndex,
    this.onNavigate,
  });

  @override
  ConsumerState<AdminOverviewPage> createState() => _AdminOverviewPageState();
}

class _AdminOverviewPageState extends ConsumerState<AdminOverviewPage> {
  // Trend window in days. Drives client-side bucketing of report dates, so the
  // toggle is instant and needs no refetch.
  int _rangeDays = 30;

  // True while a CSV export is being built/saved, so the button can't be
  // double-triggered and shows a spinner.
  bool _exporting = false;

  // Which dashboard section is shown, on narrow screens only (see below).
  int _tab = 0;
  static const List<String> _tabLabels = [
    'Overview',
    'Reports',
    'AI',
    'Ratings',
  ];

  /// The one breakpoint the dashboard has. Below it — phones, and mobile web —
  /// the grid is replaced by tabs, so each section is one short screen instead
  /// of a single long scroll. At or above it there is room for the full
  /// two-column grid, and the tab bar does not render at all.
  static const double _kTabbedMaxWidth = 1024;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(adminDashboardProvider);
    return LayoutBuilder(
      builder: (context, c) {
        final pad = c.maxWidth < 600 ? 16.0 : 24.0;
        return c.maxWidth < _kTabbedMaxWidth
            ? _buildTabbedLayout(async, pad)
            : _buildFullLayout(async, pad);
      },
    );
  }

  // ── Wide / web layout: stat cards over a two-column grid ──────────────────
  //
  // Left (2fr) carries the reporting narrative — what came in, what happened,
  // what it was about, how citizens rated it. Right (1fr) is the AI rail, led
  // by the one card that asks for a decision, so the actionable item is the
  // first thing in the reading path rather than the last.
  Widget _buildFullLayout(AsyncValue<AdminDashboardData> async, double pad) {
    return RefreshIndicator(
      onRefresh: () => ref.read(adminDashboardProvider.notifier).refresh(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(pad, pad, pad, pad + 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: 20),
                if (async.hasError) ...[
                  _buildErrorBanner(),
                  const SizedBox(height: 16),
                ],
                _buildKpiRow(async, wide: true),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: _gap(_buildMainColumn(async)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: _gap(_buildAiRail(async)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The left column's cards, top to bottom.
  List<Widget> _buildMainColumn(AsyncValue<AdminDashboardData> async) => [
    _buildTrendCard(async),
    _buildStatusCard(async),
    _buildActivityCard(async),
    _buildCategoriesCard(async),
    _buildSatisfactionCard(async),
  ];

  /// Inserts the standard 16px gutter between a column's cards.
  static List<Widget> _gap(List<Widget> children) => [
    for (var i = 0; i < children.length; i++) ...[
      children[i],
      if (i != children.length - 1) const SizedBox(height: 16),
    ],
  ];

  // ── Narrow / app layout: pinned header + tabs to minimise scrolling ───────
  Widget _buildTabbedLayout(AsyncValue<AdminDashboardData> async, double pad) {
    return Column(
      children: [
        // Pinned zone — greeting, range toggle and the tab bar stay put while
        // only the tab's content scrolls beneath them.
        Padding(
          padding: EdgeInsets.fromLTRB(pad, pad, pad, 0),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 16),
                  _buildTabBar(),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () =>
                ref.read(adminDashboardProvider.notifier).refresh(),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(pad, 16, pad, pad + 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1400),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (async.hasError) ...[
                        _buildErrorBanner(),
                        const SizedBox(height: 16),
                      ],
                      ..._buildTabSections(async),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Tab bar + per-tab content (narrow layout only) ────────────────────────
  Widget _buildTabBar() => AdminSegmentedTabs(
    labels: _tabLabels,
    selected: _tab,
    onSelect: (i) => setState(() => _tab = i),
  );

  /// The sections shown under the active tab. Each tab is deliberately short so
  /// it fits with little scrolling (the whole point of the split):
  ///  • Overview — headline KPIs + recent activity
  ///  • Reports  — volume trend, status mix, top categories
  ///  • AI       — the AI rail, in the same order as the wide layout's
  ///  • Ratings  — citizen satisfaction
  List<Widget> _buildTabSections(AsyncValue<AdminDashboardData> async) {
    switch (_tab) {
      case 1:
        return _gap([
          _buildTrendCard(async),
          _buildStatusCard(async),
          _buildCategoriesCard(async),
        ]);
      case 2:
        return _gap(_buildAiRail(async));
      case 3:
        return [_buildSatisfactionCard(async)];
      case 0:
      default:
        return _gap([
          _buildKpiRow(async, wide: false),
          _buildActivityCard(async),
        ]);
    }
  }

  // ── Header band ────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    final now = DateTime.now();
    return LayoutBuilder(
      builder: (context, c) {
        final tight = c.maxWidth < 640;
        final greeting = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_dayPart(now)}, Admin',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: AdminUi.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${_formatDate(now)} · Aparri, Cagayan',
              style: const TextStyle(fontSize: 13, color: AdminUi.textMuted),
            ),
          ],
        );

        // Wrap, not Row: the 7d/30d/90d toggle plus "Export PDF" is wider than
        // a 320px phone once the text scales up, and a Row would simply
        // overflow to the right. Wrapping drops the export button onto its own
        // line there, and is a no-op at every width where both fit.
        final actions = Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [_buildRangeToggle(), _buildExportButton()],
        );

        if (tight) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [greeting, const SizedBox(height: 14), actions],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: greeting),
            actions,
          ],
        );
      },
    );
  }

  Widget _buildRangeToggle() {
    const options = [7, 30, 90];
    return Container(
      decoration: BoxDecoration(
        color: AdminUi.surface,
        borderRadius: BorderRadius.circular(AdminUi.controlRadius),
        border: Border.all(color: AdminUi.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final d in options)
            GestureDetector(
              onTap: () => setState(() => _rangeDays = d),
              child: AnimatedContainer(
                duration: _motion(context),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _rangeDays == d
                      ? AppColors.primaryBlue.withValues(alpha: 0.10)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(AdminUi.controlRadius),
                ),
                child: Text(
                  '${d}d',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: _rangeDays == d
                        ? FontWeight.w600
                        : FontWeight.w500,
                    color: _rangeDays == d
                        ? AppColors.primaryBlue
                        : AdminUi.textSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildExportButton() {
    return Material(
      color: AdminUi.surface,
      borderRadius: BorderRadius.circular(AdminUi.controlRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AdminUi.controlRadius),
        onTap: _exporting ? null : _exportReports,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AdminUi.controlRadius),
            border: Border.all(color: AdminUi.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_exporting)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AdminUi.textSecondary,
                  ),
                )
              else
                const Icon(
                  Icons.download_rounded,
                  size: 16,
                  color: AdminUi.textSecondary,
                ),
              const SizedBox(width: 6),
              Text(
                _exporting ? 'Generating…' : 'Export PDF',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AdminUi.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build a PDF findings report (reports, feedback, suggestions, and the AI
  /// forecast) for the selected range and export it as a file — no print dialog.
  /// On web this downloads the PDF; on mobile it opens the OS share sheet.
  Future<void> _exportReports() async {
    setState(() => _exporting = true);
    try {
      // Pull every dataset the report covers, concurrently.
      final results = await Future.wait([
        ref.read(adminReportsProvider.future),
        ref.read(adminFeedbackProvider.future),
        ref.read(adminSuggestionsProvider.future),
        ref.read(adminDashboardProvider.future),
      ]);
      final reportsAll = results[0] as List<AdminReport>;
      final feedbackAll = results[1] as List<AdminFeedback>;
      final suggestionsAll = results[2] as List<AdminSuggestion>;
      final dashboard = results[3] as AdminDashboardData;

      // Same window the trend chart uses: midnight, (days - 1) back to now.
      final now = DateTime.now();
      final start = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: _rangeDays - 1));
      bool inRange(DateTime? t) => t != null && !t.isBefore(start);

      // Dismissed (spam) rows never appear in the report, regardless of the
      // admin's current "Show dismissed" filter state.
      final reports = reportsAll
          .where((r) => inRange(r.createdAt) && !r.isDismissed)
          .toList();
      final feedback = feedbackAll
          .where((f) => inRange(f.createdAt) && !f.isDismissed)
          .toList();
      final suggestions = suggestionsAll
          .where((s) => inRange(s.createdAt) && !s.isDismissed)
          .toList();

      if (!mounted) return;
      if (reports.isEmpty && feedback.isEmpty && suggestions.isEmpty) {
        showAdminSnackBar(
          context,
          'Nothing to report in the last $_rangeDays days.',
          type: AdminSnackType.info,
        );
        return;
      }

      await exportAnalyticsPdf(
        rangeDays: _rangeDays,
        now: now,
        reports: reports,
        feedback: feedback,
        suggestions: suggestions,
        dashboard: dashboard,
      );

      if (!mounted) return;
      showAdminSnackBar(
        context,
        'Findings report generated.',
        type: AdminSnackType.success,
      );
    } catch (e) {
      if (!mounted) return;
      showAdminSnackBar(
        context,
        'Export failed: $e',
        type: AdminSnackType.error,
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 18, color: AppColors.red),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Couldn\'t load live dashboard data.',
              style: TextStyle(fontSize: 13, color: AppColors.red),
            ),
          ),
          TextButton(
            onPressed: () =>
                ref.read(adminDashboardProvider.notifier).refresh(),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  // ── 1. KPI row ───────────────────────────────────────────────────────────
  /// [wide] is the layout mode, not a width guess: the wide grid always gets
  /// four across and the tabbed layout always gets two. Re-deriving this from
  /// the row's own width put 4 cards on a 950px phone-web window, which is on
  /// the tabbed side of the breakpoint.
  Widget _buildKpiRow(
    AsyncValue<AdminDashboardData> async, {
    required bool wide,
  }) {
    final data = async.valueOrNull;
    final loading = async.isLoading && data == null;

    final cards = <Widget>[
      _KpiCard(
        label: 'Total reports',
        icon: Icons.flag_rounded,
        accent: AppColors.primaryBlue,
        loading: loading,
        value: data == null ? null : '${data.totalReports}',
        delta: null,
        caption: 'All citizen reports',
        onTap: widget.onNavigate == null ? null : () => widget.onNavigate!(3),
      ),
      _KpiCard(
        label: 'New this week',
        icon: Icons.trending_up_rounded,
        accent: AppColors.primaryBlue,
        loading: loading,
        value: data == null ? null : '${data.reportsThisWeek}',
        delta: data?.reportsWeekDeltaPct,
        deltaSuffix: '%',
        caption: 'vs last week',
      ),
      _KpiCard(
        label: 'Pending verification',
        icon: Icons.how_to_reg_rounded,
        accent: AppColors.orange,
        loading: loading,
        value: data == null ? null : '${data.pendingVerification}',
        delta: null,
        caption: 'Awaiting ID review',
        onTap: widget.onNavigate == null ? null : () => widget.onNavigate!(6),
      ),
      _KpiCard(
        label: 'Resolution rate',
        icon: Icons.task_alt_rounded,
        accent: AppColors.green,
        loading: loading,
        value: data == null ? null : '${(data.resolutionRate * 100).round()}%',
        delta: data?.resolutionRateDeltaPts,
        deltaSuffix: 'pts',
        caption: 'vs last week',
      ),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        // Single column only on genuinely tiny widths, where two cards would
        // squeeze the 28px figures into an ellipsis.
        final cols = wide ? 4 : (c.maxWidth >= 340 ? 2 : 1);
        return _kpiGrid(cards, cols);
      },
    );
  }

  Widget _buildTrendCard(AsyncValue<AdminDashboardData> async) {
    final data = async.valueOrNull;
    final loading = async.isLoading && data == null;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _CardTitle('Reports over time'),
              const Spacer(),
              Text(
                'last $_rangeDays days',
                style: const TextStyle(fontSize: 11, color: AdminUi.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 200,
            child: loading
                ? const AdminShimmer(child: _TrendSkeleton())
                : (data == null
                      ? const _EmptyHint(
                          'Trend unavailable.',
                          icon: Icons.show_chart_rounded,
                        )
                      : _TrendChart(dates: data.reportDates, days: _rangeDays)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(AsyncValue<AdminDashboardData> async) {
    final data = async.valueOrNull;
    final loading = async.isLoading && data == null;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle('Status breakdown'),
          const SizedBox(height: 18),
          if (loading)
            const AdminShimmer(child: _DonutSkeleton())
          else if (data == null || data.totalReports == 0)
            const _EmptyHint('No reports yet.', icon: Icons.flag_outlined)
          else
            _StatusDonut(counts: data.statusCounts, total: data.totalReports),
        ],
      ),
    );
  }

  Widget _buildSatisfactionCard(AsyncValue<AdminDashboardData> async) {
    final data = async.valueOrNull;
    final loading = async.isLoading && data == null;
    final s = data?.satisfaction;

    // Nothing rated yet is the normal state for a new LGU, so the panel becomes
    // a titled empty state rather than a titled card wrapped around a shrug.
    if (!loading && (s == null || s.responses == 0)) {
      return const _Card(
        child: _EmptyPanel(
          icon: Icons.star_border_rounded,
          title: 'Citizen satisfaction',
          message: "No citizen ratings yet — they'll appear here once submitted.",
        ),
      );
    }

    Widget body;
    if (loading || s == null) {
      body = AdminShimmer(
        child: Column(
          children: List.generate(3, (_) => const _CategorySkeletonRow()),
        ),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                s.overall == null ? '—' : s.overall!.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1,
                  color: AdminUi.textPrimary,
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 5, left: 2),
                child: Text(
                  '/ 5',
                  style: TextStyle(fontSize: 13, color: AdminUi.textMuted),
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _stars(s.overall ?? 0),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${s.responses} response${s.responses == 1 ? '' : 's'}',
            style: const TextStyle(fontSize: 11, color: AdminUi.textMuted),
          ),
          const SizedBox(height: 16),
          const _SectionLabel('SERVICE QUALITY DIMENSIONS'),
          const SizedBox(height: 12),
          _aspectBar('Staff attitude', s.staff),
          _aspectBar('Wait time', s.wait),
          _aspectBar('Process clarity', s.clarity),
          _aspectBar('Facility', s.facility),
        ],
      );
    }

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle('Citizen satisfaction'),
          const SizedBox(height: 16),
          body,
        ],
      ),
    );
  }

  Widget _aspectBar(String label, double? value) {
    final v = (value ?? 0) / 5.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AdminUi.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Container(
                height: 8,
                color: AdminUi.subtle,
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: v.clamp(0.0, 1.0),
                  child: Container(color: AppColors.primaryBlue),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 30,
            child: Text(
              value == null ? '—' : value.toStringAsFixed(1),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AdminUi.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoriesCard(AsyncValue<AdminDashboardData> async) {
    final data = async.valueOrNull;
    final loading = async.isLoading && data == null;

    Widget body;
    if (loading) {
      body = AdminShimmer(
        child: Column(
          children: List.generate(4, (_) => const _CategorySkeletonRow()),
        ),
      );
    } else if (data == null) {
      body = const _EmptyHint(
        'Categories unavailable.',
        icon: Icons.donut_small_rounded,
      );
    } else if (data.topCategories.isEmpty) {
      body = const _EmptyHint(
        'No reports yet.',
        icon: Icons.donut_small_rounded,
      );
    } else {
      const palette = <Color>[
        AppColors.red,
        AppColors.orange,
        AppColors.primaryBlue,
        AppColors.green,
      ];
      final cats = data.topCategories;
      body = Column(
        children: [
          for (int i = 0; i < cats.length; i++)
            _CategoryBar(
              stat: cats[i],
              color: cats[i].isAggregate
                  ? AppColors.grey
                  : palette[i % palette.length],
            ),
        ],
      );
    }

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle('Top reported categories'),
          const SizedBox(height: 16),
          body,
        ],
      ),
    );
  }

  // ── AI & NLP rail ─────────────────────────────────────────────────────────
  //
  // One card per insight, in a fixed order that both layouts share so the phone
  // app and the desktop grid read the same way. "Needs your attention" leads:
  // it is the only card here that asks the admin to *do* something, and burying
  // an action under three analytics panels is how it gets missed.
  //
  // Each panel owns its own empty state. A brand-new LGU has no feedback and no
  // forecast, so those two are empty far more often than not — they have to
  // look deliberate, not broken.
  List<Widget> _buildAiRail(AsyncValue<AdminDashboardData> async) {
    final data = async.valueOrNull;
    final loading = async.isLoading && data == null;
    final nlp = data?.nlp;
    final open = widget.onNavigate == null ? null : _openInsightItem;

    if (loading || nlp == null) {
      return [
        const _AiHeaderCard(null),
        _Card(child: const _NlpLoading()),
      ];
    }

    return [
      _AiHeaderCard(nlp),
      // Nothing to act on → no card. An "everything's fine" placeholder would
      // compete with the panels that do carry findings.
      if (nlp.focus.isNotEmpty || (nlp.aiSummary?.isNotEmpty ?? false))
        _NeedsAttentionCard(
          nlp,
          onOpenFocus: widget.onNavigate == null ? null : _openFocus,
        ),
      _Card(
        child: nlp.reportsAnalyzed == 0
            ? const _EmptyPanel(
                icon: Icons.priority_high_rounded,
                title: 'Urgency triage',
                message: 'Unlocks with citizen reports — 0 so far.',
              )
            : _NlpUrgency(
                nlp,
                onOpenItem: open == null
                    ? null
                    : (i) => open(i, isReport: true),
              ),
      ),
      _Card(
        child: nlp.analyzed == 0
            ? const _EmptyPanel(
                icon: Icons.sentiment_satisfied_alt_rounded,
                title: 'Citizen sentiment',
                message: 'Unlocks with citizen feedback — 0 so far.',
              )
            : _NlpSentiment(
                nlp,
                onOpenItem: open == null
                    ? null
                    : (i) => open(i, isReport: false),
              ),
      ),
      _Card(
        child: nlp.recentAvg == null && nlp.forecastRating == null
            ? _EmptyPanel(
                icon: Icons.insights_rounded,
                title: 'Predictive outlook',
                // Your mockup said "10+ dated entries", but the forecast gate
                // is 3 populated weekly buckets (or two 30-day windows) — see
                // the regression in AdminDashboardNotifier._nlp. Stating the
                // count that actually unlocks it keeps the promise honest.
                message:
                    'Forecasts unlock after 3 weeks of dated ratings — '
                    'you have ${nlp.forecastWeeks}.',
              )
            : _NlpOutlook(nlp),
      ),
      _Card(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: _aiFootnote(nlp),
      ),
    ];
  }

  Widget _aiFootnote(NlpInsights nlp) {
    final s = nlp.aiClassified > 0
        ? 'AI ${nlp.aiClassified}/${nlp.analyzed}'
        : '${nlp.analyzed}';
    final u = nlp.reportsAiClassified > 0
        ? 'AI ${nlp.reportsAiClassified}/${nlp.reportsAnalyzed}'
        : '${nlp.reportsAnalyzed}';
    return _NlpFootnote(
      'Sentiment · $s feedback   ·   Urgency · $u report'
      '${nlp.reportsAnalyzed == 1 ? '' : 's'}',
    );
  }

  /// Opens the console a focus area is about and flashes the newest submission
  /// behind it — the same deep-link treatment tapping a report or a
  /// notification gets, so the finding lands the admin on the actual row.
  ///
  /// A focus area covers a set of submissions, so the flashed row is the way
  /// in, not the whole finding; the destination's own filters take it from
  /// there. [highlightId] is null for AI-written focus, which still navigates.
  void _openFocus(OutlookFocus focus) {
    final index = switch (focus.target) {
      FocusTarget.reports => _kTabReports,
      FocusTarget.suggestions => _kTabSuggestions,
      FocusTarget.feedback => _kTabFeedback,
      null => null,
    };
    if (index == null) return;
    widget.onNavigate!(index, highlightId: focus.highlightId);
  }

  /// Sentiment rows are feedback; urgency rows are reports. Jump to the console
  /// that owns the item and flash it, so an insight is traceable to the exact
  /// submission behind it.
  void _openInsightItem(FeedbackInsightItem item, {required bool isReport}) {
    if (item.id.isEmpty) return; // nothing to deep-link to
    widget.onNavigate!(
      isReport ? _kTabReports : _kTabFeedback,
      highlightId: item.id,
    );
  }

  Widget _buildActivityCard(AsyncValue<AdminDashboardData> async) {
    final data = async.valueOrNull;
    final loading = async.isLoading && data == null;

    Widget body;
    if (loading) {
      body = AdminShimmer(
        child: Column(
          children: List.generate(4, (_) => const _ActivitySkeletonRow()),
        ),
      );
    } else if (data == null) {
      body = const _EmptyHint(
        'Activity unavailable.',
        icon: Icons.history_rounded,
      );
    } else if (data.recentActivity.isEmpty) {
      body = const _EmptyHint(
        'No recent activity yet.',
        icon: Icons.history_rounded,
      );
    } else {
      final items = data.recentActivity;
      body = Column(
        children: [
          for (int i = 0; i < items.length; i++)
            _ActivityRow(
              item: items[i],
              isLast: i == items.length - 1,
              onTap: _activityTap(items[i]),
            ),
        ],
      );
    }

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The title flexes and the link keeps its intrinsic width: on a
          // 320px phone at large text the two together are wider than the
          // card, and a bare Spacer has no give, so the row overflowed to the
          // right. Ellipsising the title is the right sacrifice — "View all"
          // is the control, and a clipped control is unusable.
          Row(
            children: [
              // Expanded, not Spacer: the title takes all the room the link
              // does not need and ellipsises inside it, which keeps "View all"
              // flush to the card's right edge. A Flexible plus a Spacer pushed
              // the link inward, and a bare Spacer had no give at all — at
              // 320px with large text the row overflowed to the right.
              const Expanded(child: _CardTitle('Recent activity')),
              const SizedBox(width: 8),
              if (widget.onNavigate != null)
                _LinkButton(label: 'View all', onTap: _openActivityFeed),
            ],
          ),
          const SizedBox(height: 16),
          body,
        ],
      ),
    );
  }

  /// Opens the full, filterable activity feed.
  ///
  /// NOT a jump to the Reports console. The feed mixes reports and ID
  /// verifications, so sending "View all" to Reports dropped every verification
  /// row the admin was just reading — the list they landed on did not contain
  /// what they had tapped from. The sheet shows the whole feed, and its rows
  /// deep-link onward exactly like the card's do.
  void _openActivityFeed() {
    showAdminRecentActivity(
      context,
      onOpen: (r) =>
          widget.onNavigate?.call(r.tabIndex, highlightId: r.highlightId),
    );
  }

  /// A row opens the console that owns that submission and flashes the row —
  /// the same deep-link treatment a notification gets, so an event in the feed
  /// is traceable to the exact record behind it. A row with no id is unlinkable
  /// and stays inert rather than navigating somewhere arbitrary.
  VoidCallback? _activityTap(ActivityItem a) {
    if (widget.onNavigate == null || a.id.isEmpty) return null;
    return () => widget.onNavigate!(
      activityTabFor(a.source),
      highlightId: a.id,
    );
  }

  // ── small helpers ──────────────────────────────────────────────────────────
  Widget _stars(double rating) {
    final full = rating.round().clamp(0, 5);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 1; i <= 5; i++)
          Icon(
            i <= full ? Icons.star_rounded : Icons.star_outline_rounded,
            size: 16,
            color: i <= full ? AppColors.orange : AdminUi.borderStrong,
          ),
      ],
    );
  }

  /// Lays out cards in rows of [cols], letting each card size to its own
  /// content. IntrinsicHeight equalises card heights within a row, so a delta
  /// chip or a longer caption never gets clipped — the fixed-aspect grid this
  /// replaced clipped tall content on narrow (single-column) layouts.
  Widget _kpiGrid(List<Widget> cards, int cols) {
    const gap = 14.0;
    final rows = <Widget>[];
    for (var i = 0; i < cards.length; i += cols) {
      final end = (i + cols) > cards.length ? cards.length : i + cols;
      final slice = cards.sublist(i, end);
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
      if (end < cards.length) rows.add(const SizedBox(height: gap));
    }
    return Column(children: rows);
  }

  static String _dayPart(DateTime t) {
    final h = t.hour;
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  static String _formatDate(DateTime t) {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${days[t.weekday - 1]}, ${t.day} ${months[t.month - 1]} ${t.year}';
  }
}

// ── Charts ─────────────────────────────────────────────────────────────────

class _TrendChart extends StatelessWidget {
  final List<DateTime> dates;
  final int days;
  const _TrendChart({required this.dates, required this.days});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: days - 1));

    // Daily buckets across the window (zero-filled).
    final buckets = List<int>.filled(days, 0);
    for (final d in dates) {
      final day = DateTime(d.year, d.month, d.day);
      final idx = day.difference(start).inDays;
      if (idx >= 0 && idx < days) buckets[idx]++;
    }

    final spots = <FlSpot>[
      for (int i = 0; i < days; i++)
        FlSpot(i.toDouble(), buckets[i].toDouble()),
    ];
    final maxVal = buckets.fold<int>(0, (a, b) => a > b ? a : b);
    final maxY = (maxVal <= 4 ? 4.0 : (maxVal * 1.25).ceilToDouble());
    final yInterval = (maxY / 4).ceilToDouble().clamp(1.0, double.infinity);
    final xInterval = (days / 5).ceilToDouble();

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (days - 1).toDouble(),
        minY: 0,
        maxY: maxY,
        // Hard-clip everything to the plot area so a curved spline can never
        // draw the line/fill outside the card (the overshoot bug on filtering).
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: yInterval,
          getDrawingHorizontalLine: (v) =>
              const FlLine(color: AdminUi.border, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: yInterval,
              getTitlesWidget: (value, meta) {
                if (value % yInterval != 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    value.toInt().toString(),
                    style: const TextStyle(
                      fontSize: 10,
                      color: AdminUi.textMuted,
                    ),
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: xInterval,
              getTitlesWidget: (value, meta) {
                final i = value.round();
                if (i < 0 || i >= days) return const SizedBox.shrink();
                final d = start.add(Duration(days: i));
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _short(d),
                    style: const TextStyle(
                      fontSize: 10,
                      color: AdminUi.textMuted,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(enabled: true),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.25,
            // Keep the spline from bulging past its data points (below 0 / above
            // the peak), which is what pushed the line outside the container.
            preventCurveOverShooting: true,
            color: AppColors.primaryBlue,
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.primaryBlue.withValues(alpha: 0.10),
            ),
          ),
        ],
      ),
    );
  }

  static String _short(DateTime d) {
    const m = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${d.day} ${m[d.month - 1]}';
  }
}

class _StatusDonut extends StatelessWidget {
  final Map<ReportStatus, int> counts;
  final int total;
  const _StatusDonut({required this.counts, required this.total});

  @override
  Widget build(BuildContext context) {
    final segments = <_Seg>[
      _Seg('Resolved', counts[ReportStatus.resolved] ?? 0, AppColors.green),
      _Seg(
        'In progress',
        counts[ReportStatus.inProgress] ?? 0,
        AppColors.primaryBlue,
      ),
      _Seg(
        'Under review',
        counts[ReportStatus.underReview] ?? 0,
        AppColors.orange,
      ),
      _Seg('Pending', counts[ReportStatus.pending] ?? 0, AppColors.grey),
      _Seg('Rejected', counts[ReportStatus.rejected] ?? 0, AppColors.red),
    ];
    final visible = segments.where((s) => s.value > 0).toList();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 120,
          height: 120,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 36,
                  startDegreeOffset: -90,
                  sections: [
                    for (final s in visible)
                      PieChartSectionData(
                        value: s.value.toDouble(),
                        color: s.color,
                        radius: 16,
                        showTitle: false,
                      ),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$total',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AdminUi.textPrimary,
                    ),
                  ),
                  const Text(
                    'total',
                    style: TextStyle(fontSize: 10, color: AdminUi.textMuted),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final s in segments)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: s.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          s.label,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AdminUi.textSecondary,
                          ),
                        ),
                      ),
                      Text(
                        total == 0
                            ? '0%'
                            : '${(s.value / total * 100).round()}%',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AdminUi.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Seg {
  final String label;
  final int value;
  final Color color;
  const _Seg(this.label, this.value, this.color);
}

// ── KPI card ─────────────────────────────────────────────────────────────────

class _KpiCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color accent;
  final bool loading;
  final String? value;
  final double? delta;
  final String deltaSuffix;
  final String caption;
  final VoidCallback? onTap;

  const _KpiCard({
    required this.label,
    required this.icon,
    required this.accent,
    required this.loading,
    required this.value,
    required this.delta,
    this.deltaSuffix = '',
    required this.caption,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _Card(
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AdminUi.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: accent),
              ),
            ],
          ),
          if (loading)
            const AdminShimmer(child: _Skeleton(width: 56, height: 26))
          else
            Text(
              value ?? '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: value == null ? AdminUi.textMuted : AdminUi.textPrimary,
              ),
            ),
          Row(
            children: [
              if (delta != null) ...[
                _DeltaChip(delta: delta!, suffix: deltaSuffix),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AdminUi.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DeltaChip extends StatelessWidget {
  final double delta;
  final String suffix;
  const _DeltaChip({required this.delta, required this.suffix});

  @override
  Widget build(BuildContext context) {
    final up = delta >= 0;
    final color = up ? AppColors.green : AppColors.red;
    final rounded = delta.abs() >= 10
        ? delta.abs().round().toString()
        : delta.abs().toStringAsFixed(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
            size: 11,
            color: color,
          ),
          const SizedBox(width: 2),
          Text(
            '$rounded$suffix',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Category bar ─────────────────────────────────────────────────────────────

class _CategoryBar extends StatelessWidget {
  final CategoryStat stat;
  final Color color;
  const _CategoryBar({required this.stat, required this.color});

  @override
  Widget build(BuildContext context) {
    final pct = '${(stat.share * 100).round()}%';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(
              stat.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: AdminUi.textSecondary,
                fontStyle: stat.isAggregate
                    ? FontStyle.italic
                    : FontStyle.normal,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Container(
                height: 8,
                color: AdminUi.subtle,
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: stat.share.clamp(0.0, 1.0),
                  child: Container(color: color),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 36,
            child: Text(
              pct,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AdminUi.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Activity row ─────────────────────────────────────────────────────────────

class _ActivityRow extends StatelessWidget {
  final ActivityItem item;
  final bool isLast;
  final VoidCallback? onTap;
  const _ActivityRow({required this.item, required this.isLast, this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = activityKindColor(item.kind);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: EdgeInsets.only(
            top: 4,
            bottom: isLast ? 4 : 14,
            left: 4,
            right: 4,
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(activityKindIcon(item.kind), size: 16, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AdminUi.textPrimary,
                      ),
                    ),
                    Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AdminUi.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _relativeTime(item.timestamp),
                style: const TextStyle(fontSize: 11, color: AppColors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _relativeTime(DateTime? t) {
    if (t == null) return '';
    final diff = DateTime.now().difference(t);
    if (diff.isNegative) return 'now';
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }
}

// ── AI & NLP insights ────────────────────────────────────────────────────────
//
// GovPulse's NLP layer classifies feedback by sentiment and reports by urgency,
// and projects a rating trend (see the research paper). Everything below is
// computed from real submissions — on-device when the Edge Functions haven't
// labelled a row, AI when they have. The rail's cards are assembled by
// _AdminOverviewPageState._buildAiRail; each one here renders a single insight.

/// Test seam for the predictive-outlook panel. Lets tests render the real
/// widget from plain [NlpInsights] and read back the copy an admin would see,
/// without standing up the whole dashboard page and its providers.
@visibleForTesting
Widget nlpOutlookForTesting(NlpInsights nlp) => _NlpOutlook(nlp);

/// Test seam for the "Needs your attention" card — the recommended-focus copy
/// moved here out of the outlook panel, so its assertions moved with it.
@visibleForTesting
Widget needsAttentionForTesting(NlpInsights nlp) => _NeedsAttentionCard(nlp);

/// The rail's section header: what these panels are, and where their labels
/// came from (a real model vs. the on-device fallback).
class _AiHeaderCard extends StatelessWidget {
  final NlpInsights? nlp;
  const _AiHeaderCard(this.nlp);

  @override
  Widget build(BuildContext context) {
    final usesAi = nlp?.usesAi ?? false;
    // Three states, not two. "Hybrid AI" is for genuinely mixed provenance
    // (some rows model-labelled, some on the on-device rule); at full coverage
    // it read as a degraded pipeline when nothing was degraded.
    final fullyAi = nlp?.fullyAi ?? false;
    final label = fullyAi
        ? 'AI'
        : usesAi
            ? 'Hybrid AI'
            : 'On-device NLP';
    return _Card(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), AppColors.primaryBlue],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              size: 20,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Wraps rather than truncates: the rail is the narrow column,
                // and the provenance badge is not something to clip away.
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text(
                      'AI & NLP insights',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                        color: AdminUi.textPrimary,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryBlue.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            usesAi ? Icons.bolt_rounded : Icons.memory_rounded,
                            size: 12,
                            color: AppColors.primaryBlue,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            label,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primaryBlue,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                const Text(
                  'Sentiment · urgency · rating forecast',
                  style: TextStyle(fontSize: 12, color: AdminUi.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The rail's one actionable card: the data-backed focus areas, each with a
/// concrete suggested action.
///
/// Green 2px border, deliberately heavier than every other card's hairline —
/// this is the only panel asking the admin to *do* something, and it has to win
/// the eye against four analytics panels sitting under it.
class _NeedsAttentionCard extends StatelessWidget {
  final NlpInsights nlp;

  /// Opens the console that owns a finding. Null → the rows stay inert (no
  /// navigation wired, e.g. in tests).
  final void Function(OutlookFocus)? onOpenFocus;
  const _NeedsAttentionCard(this.nlp, {this.onOpenFocus});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AdminUi.surface,
        borderRadius: BorderRadius.circular(AdminUi.cardRadius),
        border: Border.all(color: AppColors.green, width: 2),
        boxShadow: AdminUi.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.arrow_right_alt_rounded,
                size: 18,
                color: AppColors.green,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Needs your attention',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AdminUi.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Says whether the recommendations were AI-written or derived
              // on-device, same as they carried inside the outlook panel.
              _OutlookSourceChip(usesAi: nlp.outlookUsesAi),
            ],
          ),
          if (nlp.aiSummary?.isNotEmpty ?? false) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.18),
                ),
              ),
              child: Text(
                nlp.aiSummary!,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: AdminUi.textSecondary,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          for (final f in nlp.focus)
            _FocusCard(
              f,
              onTap: (onOpenFocus == null || f.target == null)
                  ? null
                  : () => onOpenFocus!(f),
            ),
        ],
      ),
    );
  }
}

/// Loading shimmer that mirrors the populated card's rough height.
class _NlpLoading extends StatelessWidget {
  const _NlpLoading();

  @override
  Widget build(BuildContext context) {
    return const AdminShimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: 120, height: 12),
          SizedBox(height: 10),
          SkeletonBox(width: double.infinity, height: 12, radius: 6),
          SizedBox(height: 18),
          SkeletonBox(width: 100, height: 12),
          SizedBox(height: 10),
          SkeletonBox(width: double.infinity, height: 28, radius: 8),
          SizedBox(height: 18),
          SkeletonBox(width: 110, height: 12),
          SizedBox(height: 10),
          SkeletonBox(width: double.infinity, height: 20),
        ],
      ),
    );
  }
}

// Shared sentiment palette.
const Color _kSentPos = AppColors.green;
const Color _kSentNeu = Color(0xFF94A3B8);
const Color _kSentNeg = AppColors.red;

Color _sentimentColor(String s) => switch (s) {
  'positive' => _kSentPos,
  'negative' => _kSentNeg,
  _ => _kSentNeu,
};
Color _urgencyColor(String u) => switch (u) {
  'high' => AppColors.red,
  'medium' => AppColors.orange,
  _ => AppColors.green,
};

// Urgency sort rank so the breakdown reads High→Medium→Low, matching the bars.
// (Sentiment is ordered by star rating instead — see _NlpSentimentState.)
int _urgRank(String u) => u == 'high' ? 0 : (u == 'medium' ? 1 : 2);
String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Compact "how long ago" label (2m / 3h / 5d / 2w) for breakdown rows, so two
/// otherwise-identical items (same category + same barangay, no description)
/// are still told apart at a glance. Empty when the timestamp is missing.
String _relTimeShort(DateTime? t) {
  if (t == null) return '';
  final diff = DateTime.now().difference(t);
  if (diff.isNegative || diff.inMinutes < 1) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  return '${(diff.inDays / 7).floor()}w';
}

List<FeedbackInsightItem> _sortedBy(
  List<FeedbackInsightItem> items,
  int Function(FeedbackInsightItem) rank,
) {
  final out = [...items];
  out.sort((a, b) {
    final r = rank(a).compareTo(rank(b));
    if (r != 0) return r;
    final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
    final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
    return bt.compareTo(at); // newest first within a bucket
  });
  return out;
}

// ── Sentiment split — filterable bars + ordered feedback breakdown ───────────
class _NlpSentiment extends StatefulWidget {
  final NlpInsights nlp;
  final void Function(FeedbackInsightItem)? onOpenItem;
  const _NlpSentiment(this.nlp, {this.onOpenItem});

  @override
  State<_NlpSentiment> createState() => _NlpSentimentState();
}

class _NlpSentimentState extends State<_NlpSentiment> {
  String? _filter; // null = all; else 'positive' | 'neutral' | 'negative'

  void _toggle(String f) => setState(() => _filter = _filter == f ? null : f);

  @override
  Widget build(BuildContext context) {
    final nlp = widget.nlp;
    // Order the responses by star rating, highest → lowest (5 → 0). Negating
    // the rating turns the ascending sort into descending; ties fall back to
    // newest-first inside [_sortedBy].
    final sorted = _sortedBy(nlp.sentimentItems, (i) => -i.rating);
    final filtered = _filter == null
        ? sorted
        : sorted.where((i) => i.sentiment == _filter).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _NlpSectionLabel(
          icon: Icons.sentiment_satisfied_alt_rounded,
          label: 'Citizen sentiment',
          hint: '${nlp.analyzed} feedback',
        ),
        const SizedBox(height: 10),
        _InsightBarRow(
          color: _kSentPos,
          label: 'Positive',
          count: nlp.positive,
          share: nlp.positiveShare,
          selected: _filter == 'positive',
          filterActive: _filter != null,
          onTap: nlp.positive == 0 ? null : () => _toggle('positive'),
        ),
        _InsightBarRow(
          color: _kSentNeu,
          label: 'Neutral',
          count: nlp.neutral,
          share: nlp.neutralShare,
          selected: _filter == 'neutral',
          filterActive: _filter != null,
          onTap: nlp.neutral == 0 ? null : () => _toggle('neutral'),
        ),
        _InsightBarRow(
          color: _kSentNeg,
          label: 'Negative',
          count: nlp.negative,
          share: nlp.negativeShare,
          selected: _filter == 'negative',
          filterActive: _filter != null,
          onTap: nlp.negative == 0 ? null : () => _toggle('negative'),
        ),
        _InsightBreakdown(
          items: filtered,
          urgencyMode: false,
          headerLabel: _filter == null
              ? 'RESPONSES'
              : '${_cap(_filter!)} · ${filtered.length}',
          sheetTitle: _filter == null
              ? 'All responses'
              : '${_cap(_filter!)} feedback',
          accent: _filter == null
              ? AdminUi.textMuted
              : _sentimentColor(_filter!),
          onOpenItem: widget.onOpenItem,
        ),
      ],
    );
  }
}

// ── Urgency triage — filterable bars + ordered report breakdown ──────────────
class _NlpUrgency extends StatefulWidget {
  final NlpInsights nlp;
  final void Function(FeedbackInsightItem)? onOpenItem;
  const _NlpUrgency(this.nlp, {this.onOpenItem});

  @override
  State<_NlpUrgency> createState() => _NlpUrgencyState();
}

class _NlpUrgencyState extends State<_NlpUrgency> {
  String? _filter; // null = all; else 'high' | 'medium' | 'low'

  void _toggle(String f) => setState(() => _filter = _filter == f ? null : f);

  @override
  Widget build(BuildContext context) {
    final nlp = widget.nlp;
    final total = nlp.reportsAnalyzed;
    double share(int n) => total == 0 ? 0 : n / total;
    final sorted = _sortedBy(nlp.urgencyItems, (i) => _urgRank(i.urgency));
    final filtered = _filter == null
        ? sorted
        : sorted.where((i) => i.urgency == _filter).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _NlpSectionLabel(
          icon: Icons.priority_high_rounded,
          label: 'Urgency triage',
          hint: '${nlp.reportsAnalyzed} reports',
        ),
        const SizedBox(height: 10),
        _InsightBarRow(
          color: AppColors.red,
          label: 'High',
          count: nlp.urgentHigh,
          share: share(nlp.urgentHigh),
          selected: _filter == 'high',
          filterActive: _filter != null,
          onTap: nlp.urgentHigh == 0 ? null : () => _toggle('high'),
        ),
        _InsightBarRow(
          color: AppColors.orange,
          label: 'Medium',
          count: nlp.urgentMedium,
          share: share(nlp.urgentMedium),
          selected: _filter == 'medium',
          filterActive: _filter != null,
          onTap: nlp.urgentMedium == 0 ? null : () => _toggle('medium'),
        ),
        _InsightBarRow(
          color: AppColors.green,
          label: 'Low',
          count: nlp.urgentLow,
          share: share(nlp.urgentLow),
          selected: _filter == 'low',
          filterActive: _filter != null,
          onTap: nlp.urgentLow == 0 ? null : () => _toggle('low'),
        ),
        _InsightBreakdown(
          items: filtered,
          urgencyMode: true,
          headerLabel: _filter == null
              ? 'REPORTS'
              : '${_cap(_filter!)} · ${filtered.length}',
          sheetTitle: _filter == null
              ? 'All reports'
              : '${_cap(_filter!)} urgency',
          accent: _filter == null ? AdminUi.textMuted : _urgencyColor(_filter!),
          onOpenItem: widget.onOpenItem,
        ),
      ],
    );
  }
}

/// One KPI summary row that doubles as a filter: [dot + label] · [bar] · [count+%].
/// Tapping filters the breakdown below to this bucket (tap again to clear); the
/// active bucket is highlighted and the others dim so the filter state is clear.
class _InsightBarRow extends StatelessWidget {
  final Color color;
  final String label;
  final int count;
  final double share; // 0..1
  final bool selected;
  final bool filterActive;
  final VoidCallback? onTap;
  const _InsightBarRow({
    required this.color,
    required this.label,
    required this.count,
    required this.share,
    this.selected = false,
    this.filterActive = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Dim the non-selected rows while a filter is active, so the chosen bucket
    // stands out.
    final dim = filterActive && !selected;
    final row = AnimatedOpacity(
      duration: _motion(context),
      opacity: dim ? 0.45 : 1,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.10) : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 74,
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w600,
                        color: selected ? color : AdminUi.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  height: 8,
                  color: color.withValues(alpha: 0.14),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: share.clamp(0.0, 1.0),
                    child: Container(color: color),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Fixed width keeps the bars aligned down the column; the
            // scale-down keeps a wide value ("128 100%") inside it instead of
            // overflowing the row.
            SizedBox(
              width: 50,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${(share * 100).round()}%',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AdminUi.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (onTap == null) return row;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: row,
      ),
    );
  }
}

/// The always-visible breakdown list under a sentiment/urgency summary, ordered
/// to match the bars. Shows up to [_maxItems]; if more don't fit, a "+N more"
/// row opens the full (filtered) list in a sheet — the only tap needed.
class _InsightBreakdown extends StatelessWidget {
  static const _maxItems = 6;
  final List<FeedbackInsightItem> items;
  final bool urgencyMode;
  final String headerLabel;
  final String sheetTitle;
  final Color accent;

  /// Opens one item on its own console, flashed. Null → rows stay inert.
  final void Function(FeedbackInsightItem)? onOpenItem;
  const _InsightBreakdown({
    required this.items,
    required this.urgencyMode,
    required this.headerLabel,
    required this.sheetTitle,
    required this.accent,
    this.onOpenItem,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Divider(height: 1, color: AdminUi.subtle),
            SizedBox(height: 10),
            Text(
              'No items in this bucket.',
              style: TextStyle(fontSize: 11.5, color: AdminUi.textMuted),
            ),
          ],
        ),
      );
    }
    final shown = items.take(_maxItems).toList();
    final more = items.length - shown.length;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1, color: AdminUi.subtle),
          const SizedBox(height: 8),
          Text(
            headerLabel.toUpperCase(),
            style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: AdminUi.textMuted,
            ),
          ),
          const SizedBox(height: 4),
          for (final it in shown)
            _BreakdownRow(
              item: it,
              urgencyMode: urgencyMode,
              onOpen: onOpenItem == null ? null : () => onOpenItem!(it),
            ),
          if (more > 0)
            _SeeAllRow(
              label: 'View all ${items.length}',
              onTap: () => _showBreakdownSheet(
                context,
                title: sheetTitle,
                accent: accent,
                urgencyMode: urgencyMode,
                items: items,
                onOpenItem: onOpenItem,
              ),
            ),
        ],
      ),
    );
  }
}

/// A tappable "View all N" row shown when the breakdown overflows the card.
class _SeeAllRow extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SeeAllRow({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          child: Row(
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryBlue,
                ),
              ),
              const SizedBox(width: 2),
              const Icon(
                Icons.chevron_right_rounded,
                size: 15,
                color: AppColors.primaryBlue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the full (filtered) breakdown list — a bottom sheet on phones, a
/// centered dialog on wider screens.
void _showBreakdownSheet(
  BuildContext context, {
  required String title,
  required Color accent,
  required bool urgencyMode,
  required List<FeedbackInsightItem> items,
  void Function(FeedbackInsightItem)? onOpenItem,
}) {
  final mq = MediaQuery.of(context);
  final narrow = mq.size.width < 640;
  final content = _BreakdownSheet(
    title: title,
    accent: accent,
    urgencyMode: urgencyMode,
    items: items,
    // Dismiss the sheet before jumping, or the destination opens underneath it.
    onOpenItem: onOpenItem == null
        ? null
        : (item) {
            Navigator.of(context).pop();
            onOpenItem(item);
          },
  );
  if (narrow) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AdminUi.surface,
      isScrollControlled: true,
      // A drag handle + capped height keep the sheet usable, and the inner
      // SafeArea(bottom) makes it sit above the phone's system navigation —
      // whether the device uses 3-button or gesture navigation.
      showDragHandle: true,
      constraints: BoxConstraints(maxHeight: mq.size.height * 0.85),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => content,
    );
  } else {
    showAppDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: AdminUi.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 600),
          child: content,
        ),
      ),
    );
  }
}

class _BreakdownSheet extends StatelessWidget {
  final String title;
  final Color accent;
  final bool urgencyMode;
  final List<FeedbackInsightItem> items;
  const _BreakdownSheet({
    required this.title,
    required this.accent,
    required this.urgencyMode,
    required this.items,
    this.onOpenItem,
  });

  final void Function(FeedbackInsightItem)? onOpenItem;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 10),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AdminUi.textPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${items.length}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AdminUi.textMuted,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                  color: AdminUi.textMuted,
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AdminUi.border),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              itemCount: items.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, color: AdminUi.subtle),
              itemBuilder: (_, i) => _BreakdownRow(
                item: items[i],
                urgencyMode: urgencyMode,
                onOpen: onOpenItem == null ? null : () => onOpenItem!(items[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  final FeedbackInsightItem item;
  final bool urgencyMode;

  /// Opens this item on its own console (Feedback / Reports), flashed. Null
  /// when the shell didn't wire navigation → the row stays inert.
  final VoidCallback? onOpen;
  const _BreakdownRow({
    required this.item,
    required this.urgencyMode,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final color = urgencyMode
        ? _urgencyColor(item.urgency)
        : _sentimentColor(item.sentiment);
    // Urgency: two same-category, same-barangay reports used to render
    // identically (only the barangay was shown). Compose location + the
    // citizen's own description so each report reads distinctly.
    final String? subtitle;
    if (urgencyMode) {
      final loc = item.service.trim();
      final desc = item.comment?.trim() ?? '';
      final parts = [loc, desc].where((s) => s.isNotEmpty).toList();
      subtitle = parts.isEmpty ? null : parts.join(' · ');
    } else {
      final desc = item.comment?.trim() ?? '';
      final svc = item.service.trim();
      subtitle = desc.isNotEmpty ? desc : (svc.isNotEmpty ? svc : null);
    }
    final time = _relTimeShort(item.createdAt);

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(top: 4, right: 8),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AdminUi.textPrimary,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AdminUi.textMuted,
                    ),
                  ),
                // Cluster escalation: the urgency shown is above the report's
                // own label, so say why or the bump reads as a mislabel.
                if (item.escalationNote != null)
                  Text(
                    '↑ Escalated — ${item.escalationNote}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontStyle: FontStyle.italic,
                      color: AppColors.orange,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Trailing: urgency word (reports) or star rating (feedback), with a
          // compact "time ago" beneath so rows are never ambiguous.
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (urgencyMode)
                Text(
                  item.urgency,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                )
              else if (item.rating > 0)
                _MiniStars(item.rating)
              else
                Text(
                  item.sentiment,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              if (time.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  time,
                  style: const TextStyle(fontSize: 10, color: AppColors.grey),
                ),
              ],
            ],
          ),
        ],
      ),
    );

    if (onOpen == null) return row;
    // An insight is a claim about specific submissions; make it traceable back
    // to them. Hover feedback matters here — this is a desktop console, and the
    // row is otherwise indistinguishable from static text.
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onOpen,
        behavior: HitTestBehavior.opaque,
        child: row,
      ),
    );
  }
}

// ── Predictive outlook — trend headline + aligned Prior/Recent/Forecast rows ─
class _NlpOutlook extends StatelessWidget {
  final NlpInsights nlp;
  const _NlpOutlook(this.nlp);

  @override
  Widget build(BuildContext context) {
    final (icon, color, word) = switch (nlp.trend) {
      InsightTrend.improving => (
        Icons.trending_up_rounded,
        AppColors.green,
        'Improving',
      ),
      InsightTrend.declining => (
        Icons.trending_down_rounded,
        AppColors.red,
        'Declining',
      ),
      InsightTrend.stable => (
        Icons.trending_flat_rounded,
        AppColors.primaryBlue,
        'Stable',
      ),
      InsightTrend.unknown => (
        Icons.help_outline_rounded,
        AdminUi.textMuted,
        'Not enough data',
      ),
    };

    final recent = nlp.recentAvg;
    final forecast = nlp.forecastRating;
    final delta = nlp.trendDelta;

    // Equal-height cards come from IntrinsicHeight in the parent Row, which can
    // hand this content 1px less than it measured (sub-pixel rounding).
    //
    // A ClipRect does NOT fix that: it clips the painting, but the Column is
    // still laid out against the too-short constraint and still throws
    // "RenderFlex overflowed". Scrolling is what actually fixes it — the
    // viewport gives the Column unbounded height, so it lays out at its natural
    // size and can never overflow. Physics are disabled because there is nothing
    // to scroll to: the only thing past the edge is that rounding remainder.
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _NlpSectionLabel(
            icon: Icons.insights_rounded,
            label: 'Predictive outlook',
          ),
          const SizedBox(height: 10),
          if (recent == null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AdminUi.subtle,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AdminUi.border),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.hourglass_empty_rounded,
                    size: 15,
                    color: AdminUi.textMuted,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Not enough dated feedback to forecast yet.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AdminUi.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            // Trend headline chip + signed delta.
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 15, color: color),
                      const SizedBox(width: 5),
                      Text(
                        word,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (delta != null)
                  Text(
                    '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}★',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _outlookRow('Prior 30 days', nlp.priorAvg, AdminUi.textSecondary),
            _outlookRow('Recent 30 days', recent, color, emphasize: true),
            // Only a real extrapolation earns the "projected" label. With one
            // window there is nothing to project from, so explain the gap instead
            // of printing a copy of the recent average as if it were a forecast.
            if (forecast != null) ...[
              _outlookRow(
                'Forecast',
                forecast,
                color,
                emphasize: true,
                italicNote: 'projected',
              ),
              // Show the working. A projected star rating with no stated basis
              // reads as authority it hasn't earned — especially at barangay
              // sample sizes, where two responses can swing it a full star.
              Padding(
                padding: const EdgeInsets.only(left: 4, right: 4, top: 1),
                child: Text(
                  _forecastBasis(nlp),
                  style: const TextStyle(
                    fontSize: 10.5,
                    height: 1.35,
                    color: AdminUi.textMuted,
                  ),
                ),
              ),
            ] else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 5, horizontal: 4),
                child: Text(
                  'No forecast yet — needs rated feedback spread across at '
                  'least 3 different weeks, or two consecutive 30-day windows, '
                  'to project a trend.',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: AdminUi.textMuted,
                  ),
                ),
              ),
          ],
          // The recommended-focus block used to sit here. It moved up the rail
          // into "Needs your attention" (_NeedsAttentionCard) so the one
          // actionable thing on the dashboard isn't the last thing on it.
        ],
      ),
    );
  }

  /// Plain-language basis for the projected rating: the arithmetic, the
  /// evidence behind it, and any caveat that changes how much weight it
  /// deserves. Only called when a real two-window forecast exists.
  static String _forecastBasis(NlpInsights nlp) {
    final parts = <String>[];
    final int responses;
    if (nlp.forecastWeeks >= 3) {
      // Regression path: a trend line over weekly average ratings.
      responses = nlp.forecastResponses;
      parts.add(
        'Trend line fitted over ${nlp.forecastWeeks} weekly averages '
        '($responses rated ${responses == 1 ? 'response' : 'responses'}, '
        'last 12 weeks), projected one week ahead.',
      );
    } else {
      // Fallback path: too few populated weeks, so the older two-window
      // extrapolation produced the number — both windows exist here.
      final delta = nlp.trendDelta!;
      final sign = delta >= 0 ? '+' : '';
      final recent = nlp.recentCount;
      final prior = nlp.priorCount;
      responses = recent + prior;
      parts
        ..add(
          'Carries the $sign${delta.toStringAsFixed(1)}★ change from the prior '
          'window forward one period.',
        )
        ..add(
          'Based on $recent recent and $prior prior rated '
          '${recent == 1 && prior == 1 ? 'response' : 'responses'}.',
        );
    }
    if (nlp.forecastClamped) {
      parts.add('Capped at the 1–5★ scale.');
    }
    if (responses < 5) {
      parts.add('Small sample — treat as directional.');
    }
    return parts.join(' ');
  }

  Widget _outlookRow(
    String label,
    double? value,
    Color valueColor, {
    bool emphasize = false,
    String? italicNote,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AdminUi.textSecondary,
                  ),
                ),
                if (italicNote != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    italicNote,
                    style: const TextStyle(
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                      color: AdminUi.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value == null ? '—' : value.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: emphasize ? 15 : 13.5,
                  fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
                  color: emphasize ? valueColor : AdminUi.textPrimary,
                ),
              ),
              Text(
                '★',
                style: TextStyle(
                  fontSize: 10,
                  color: emphasize
                      ? valueColor.withValues(alpha: 0.8)
                      : AdminUi.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Tiny chip marking whether the recommendations are AI-written or on-device.
class _OutlookSourceChip extends StatelessWidget {
  final bool usesAi;
  const _OutlookSourceChip({required this.usesAi});

  @override
  Widget build(BuildContext context) {
    final color = usesAi ? const Color(0xFF6366F1) : AdminUi.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            usesAi ? Icons.auto_awesome_rounded : Icons.memory_rounded,
            size: 10,
            color: color,
          ),
          const SizedBox(width: 3),
          Text(
            usesAi ? 'AI' : 'On-device',
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// One recommended-focus card: a coloured severity dot, the issue + its metric,
/// and the concrete suggested action beneath.
///
/// Tapping it opens the console holding the submissions behind the finding —
/// the card tells the admin to "review and reply with a decision", so it has to
/// be the thing that takes them there. Inert only when the focus carries no
/// [OutlookFocus.target].
class _FocusCard extends StatelessWidget {
  final OutlookFocus focus;
  final VoidCallback? onTap;
  const _FocusCard(this.focus, {this.onTap});

  Color get _color => switch (focus.severity) {
    'high' => AppColors.red,
    'medium' => AppColors.orange,
    _ => AppColors.green,
  };

  /// Names the destination, so the row promises only what the tap delivers.
  String get _actionLabel => switch (focus.target) {
    FocusTarget.reports => 'Review reports',
    FocusTarget.suggestions => 'Review suggestions',
    FocusTarget.feedback => 'Review feedback',
    null => '',
  };

  @override
  Widget build(BuildContext context) {
    final color = _color;
    final card = _buildCard(color);
    if (onTap == null) return card;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Semantics(
        button: true,
        label: '${focus.title}. $_actionLabel',
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: card,
        ),
      ),
    );
  }

  Widget _buildCard(Color color) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  focus.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AdminUi.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                focus.metric,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          // WHERE the finding applies + how much evidence backs it. Aligned to
          // the title (past the severity dot) so it reads as the title's
          // subtitle rather than a second bullet.
          if (focus.scope != null && focus.scope!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 14, top: 2),
              child: Text(
                focus.scope!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AdminUi.textMuted,
                ),
              ),
            ),
          const SizedBox(height: 5),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.arrow_right_alt_rounded,
                size: 15,
                color: color.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  focus.suggestion,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: AdminUi.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          // Without this the card looks like a static callout — the advice to
          // "reply with a decision" reads as instructions to go find it
          // yourself rather than as something to click.
          if (onTap != null) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  _actionLabel,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 16, color: color),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniStars extends StatelessWidget {
  final int rating;
  const _MiniStars(this.rating);

  @override
  Widget build(BuildContext context) {
    final color = rating <= 1
        ? AppColors.red
        : (rating == 2 ? AppColors.orange : const Color(0xFFF59E0B));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            i <= rating ? Icons.star_rounded : Icons.star_outline_rounded,
            size: 13,
            color: i <= rating ? color : AdminUi.border,
          ),
      ],
    );
  }
}

class _NlpSectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;

  /// Optional trailing affordance (e.g. "tap to view") shown right-aligned.
  final String? hint;
  const _NlpSectionLabel({required this.icon, required this.label, this.hint});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: AdminUi.textMuted),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AdminUi.textSecondary,
          ),
        ),
        if (hint != null) ...[
          const Spacer(),
          Text(
            hint!,
            style: TextStyle(
              fontSize: 10.5,
              color: AdminUi.textMuted.withValues(alpha: 0.9),
            ),
          ),
        ],
      ],
    );
  }
}

class _NlpFootnote extends StatelessWidget {
  final String text;
  const _NlpFootnote(this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.verified_rounded, size: 13, color: AdminUi.textMuted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 11, color: AdminUi.textMuted),
          ),
        ),
      ],
    );
  }
}

// ── Shared presentational helpers ─────────────────────────────────────────────

/// A white rounded card with a hairline border + subtle elevation.
/// Optionally tappable (Material surface + InkWell) so hover works on web.
class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  const _Card({
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(AdminUi.cardRadius));

    if (onTap == null) {
      return Container(
        // A card owns its whole column. Without this it shrink-wraps its child,
        // so a panel holding nothing but "No reports yet." collapses into a
        // small box floating in the middle of the row — the dashboard looked
        // broken precisely when it had the least to show.
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: AdminUi.surface,
          borderRadius: radius,
          border: Border.all(color: AdminUi.border),
          boxShadow: AdminUi.cardShadow,
        ),
        child: child,
      );
    }

    return DecoratedBox(
      decoration: const BoxDecoration(
        borderRadius: radius,
        boxShadow: AdminUi.cardShadow,
      ),
      child: Material(
        color: AdminUi.surface,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: AdminUi.border),
        ),
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: double.infinity,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

class _CardTitle extends StatelessWidget {
  final String text;
  const _CardTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AdminUi.textPrimary,
      ),
    );
  }
}

class _LinkButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _LinkButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryBlue,
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: AdminUi.textMuted,
      ),
    );
  }
}

/// The "nothing here yet" body of a dashboard panel.
///
/// A brand-new LGU sees this in almost every panel, so it is the first
/// impression of the console — it has to read as "ready and waiting", not as a
/// half-loaded page. A bare line of grey text hugging the top-left did the
/// latter. The muted glyph and the floor height give the panel a body, so an
/// empty dashboard still looks like a dashboard.
class _EmptyHint extends StatelessWidget {
  final String text;
  final IconData icon;
  const _EmptyHint(this.text, {this.icon = Icons.inbox_rounded});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      // A floor, not a fixed height: a taller parent (the 200px trend slot)
      // still centres this, and nothing overflows when the card is short.
      constraints: const BoxConstraints(minHeight: 132),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AdminUi.subtle,
              shape: BoxShape.circle,
              border: Border.all(color: AdminUi.border),
            ),
            child: Icon(icon, size: 20, color: AdminUi.textMuted),
          ),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AdminUi.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// A whole panel in its "nothing yet" state: centred glyph, the panel's own
/// title, and one line saying what will make it fill in.
///
/// Distinct from [_EmptyHint], which is the empty *body* of a card that already
/// has a title above it. This one IS the card's content — used where a panel is
/// empty in the normal low-data state (a new LGU has no feedback and no
/// forecast for weeks), so it has to read as ready-and-waiting rather than as a
/// panel that failed to load. The title is what keeps it identifiable: a lone
/// grey sentence in a white box tells the admin nothing about which panel it is.
class _EmptyPanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  const _EmptyPanel({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 132),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AdminUi.subtle,
              shape: BoxShape.circle,
              border: Border.all(color: AdminUi.border),
            ),
            child: Icon(icon, size: 20, color: AdminUi.textMuted),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AdminUi.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              height: 1.4,
              color: AdminUi.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  final double? width;
  final double height;
  const _Skeleton({this.width, this.height = 12});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: kSkeletonBase,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}

class _TrendSkeleton extends StatelessWidget {
  const _TrendSkeleton();

  @override
  Widget build(BuildContext context) {
    // A baseline plus a few bars of varied height that read as a chart frame.
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: LayoutBuilder(
        builder: (context, c) {
          const heights = [0.45, 0.7, 0.35, 0.85, 0.55, 0.95, 0.6, 0.75];
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < heights.length; i++) ...[
                Expanded(
                  child: SkeletonBox(
                    height: (c.maxHeight * heights[i]).clamp(12.0, c.maxHeight),
                    radius: 6,
                  ),
                ),
                if (i != heights.length - 1) const SizedBox(width: 10),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _DonutSkeleton extends StatelessWidget {
  const _DonutSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 140,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SkeletonCircle(size: 120),
          SizedBox(width: 18),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: double.infinity, height: 11),
                SizedBox(height: 12),
                SkeletonBox(width: double.infinity, height: 11),
                SizedBox(height: 12),
                SkeletonBox(width: 120, height: 11),
                SizedBox(height: 12),
                SkeletonBox(width: 90, height: 11),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivitySkeletonRow extends StatelessWidget {
  const _ActivitySkeletonRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          SkeletonCircle(size: 36),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Skeleton(width: 140, height: 11),
                SizedBox(height: 6),
                _Skeleton(width: 90, height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategorySkeletonRow extends StatelessWidget {
  const _CategorySkeletonRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(width: 110, child: _Skeleton(width: 80, height: 11)),
          SizedBox(width: 8),
          Expanded(child: _Skeleton(height: 8)),
        ],
      ),
    );
  }
}
