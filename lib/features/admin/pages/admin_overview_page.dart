import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/admin_dashboard_provider.dart';
import '../providers/admin_reports_provider.dart' show ReportStatus;
import '../theme/admin_ui.dart';

class AdminOverviewPage extends ConsumerStatefulWidget {
  final int selectedIndex;

  /// Lets the dashboard jump the shell to another section (e.g. Reports = 1).
  /// Wired by the dashboard screen; null elsewhere → tiles simply aren't tappable.
  final void Function(int index)? onNavigate;

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

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(adminDashboardProvider);

    return RefreshIndicator(
      onRefresh: () => ref.read(adminDashboardProvider.notifier).refresh(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
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
                _buildKpiRow(async),
                const SizedBox(height: 16),
                _buildChartsRow(async),
                const SizedBox(height: 16),
                _buildQualityRow(async),
                const SizedBox(height: 16),
                _buildInsightsRow(async),
              ],
            ),
          ),
        ),
      ),
    );
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

        final actions = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildRangeToggle(),
            const SizedBox(width: 10),
            _buildExportButton(),
          ],
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
                duration: const Duration(milliseconds: 150),
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
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Export coming soon'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AdminUi.controlRadius),
            border: Border.all(color: AdminUi.border),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.download_rounded,
                size: 16,
                color: AdminUi.textSecondary,
              ),
              SizedBox(width: 6),
              Text(
                'Export',
                style: TextStyle(
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
  Widget _buildKpiRow(AsyncValue<AdminDashboardData> async) {
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
        onTap: widget.onNavigate == null ? null : () => widget.onNavigate!(1),
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
        onTap: widget.onNavigate == null ? null : () => widget.onNavigate!(7),
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
        final cols = c.maxWidth > 900 ? 4 : (c.maxWidth > 520 ? 2 : 1);
        return _kpiGrid(cards, cols);
      },
    );
  }

  // ── 2. Charts row: trend + status donut ──────────────────────────────────
  Widget _buildChartsRow(AsyncValue<AdminDashboardData> async) {
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 860;
        final trend = _buildTrendCard(async);
        final donut = _buildStatusCard(async);
        if (wide) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 62, child: trend),
                const SizedBox(width: 16),
                Expanded(flex: 38, child: donut),
              ],
            ),
          );
        }
        return Column(children: [trend, const SizedBox(height: 16), donut]);
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
                ? const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : (data == null
                      ? const _EmptyHint('Trend unavailable.')
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
            const SizedBox(
              height: 140,
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (data == null || data.totalReports == 0)
            const _EmptyHint('No reports yet.')
          else
            _StatusDonut(counts: data.statusCounts, total: data.totalReports),
        ],
      ),
    );
  }

  // ── 3. Quality row: satisfaction + top categories ─────────────────────────
  Widget _buildQualityRow(AsyncValue<AdminDashboardData> async) {
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 860;
        final sat = _buildSatisfactionCard(async);
        final cats = _buildCategoriesCard(async);
        if (wide) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: sat),
                const SizedBox(width: 16),
                Expanded(child: cats),
              ],
            ),
          );
        }
        return Column(children: [sat, const SizedBox(height: 16), cats]);
      },
    );
  }

  Widget _buildSatisfactionCard(AsyncValue<AdminDashboardData> async) {
    final data = async.valueOrNull;
    final loading = async.isLoading && data == null;
    final s = data?.satisfaction;

    Widget body;
    if (loading) {
      body = Column(
        children: List.generate(3, (_) => const _CategorySkeletonRow()),
      );
    } else if (s == null || s.responses == 0) {
      body = const _EmptyHint('No citizen ratings yet.');
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
      body = Column(
        children: List.generate(4, (_) => const _CategorySkeletonRow()),
      );
    } else if (data == null) {
      body = const _EmptyHint('Categories unavailable.');
    } else if (data.topCategories.isEmpty) {
      body = const _EmptyHint('No reports yet.');
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

  // ── 4. Insights row: recent activity + AI/NLP (awaiting pipeline) ─────────
  Widget _buildInsightsRow(AsyncValue<AdminDashboardData> async) {
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 860;
        final activity = _buildActivityCard(async);
        final nlp = const _NlpInsightsCard();
        if (wide) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 55, child: activity),
                const SizedBox(width: 16),
                Expanded(flex: 45, child: nlp),
              ],
            ),
          );
        }
        return Column(children: [activity, const SizedBox(height: 16), nlp]);
      },
    );
  }

  Widget _buildActivityCard(AsyncValue<AdminDashboardData> async) {
    final data = async.valueOrNull;
    final loading = async.isLoading && data == null;

    Widget body;
    if (loading) {
      body = Column(
        children: List.generate(4, (_) => const _ActivitySkeletonRow()),
      );
    } else if (data == null) {
      body = const _EmptyHint('Activity unavailable.');
    } else if (data.recentActivity.isEmpty) {
      body = const _EmptyHint('No recent activity yet.');
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
          Row(
            children: [
              const _CardTitle('Recent activity'),
              const Spacer(),
              if (widget.onNavigate != null)
                _LinkButton(
                  label: 'View all',
                  onTap: () => widget.onNavigate!(1),
                ),
            ],
          ),
          const SizedBox(height: 16),
          body,
        ],
      ),
    );
  }

  VoidCallback? _activityTap(ActivityItem a) {
    final isReport =
        a.kind == ActivityKind.reportNew ||
        a.kind == ActivityKind.reportReviewing ||
        a.kind == ActivityKind.reportResolved ||
        a.kind == ActivityKind.reportRejected;
    return (isReport && widget.onNavigate != null)
        ? () => widget.onNavigate!(1)
        : null;
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
            const _Skeleton(width: 56, height: 26)
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
    final color = _activityColor(item.kind);
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
                child: Icon(_activityIcon(item.kind), size: 16, color: color),
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

  IconData _activityIcon(ActivityKind kind) {
    switch (kind) {
      case ActivityKind.reportNew:
        return Icons.flag_rounded;
      case ActivityKind.reportReviewing:
        return Icons.hourglass_top_rounded;
      case ActivityKind.reportResolved:
        return Icons.check_circle_rounded;
      case ActivityKind.reportRejected:
        return Icons.do_not_disturb_on_rounded;
      case ActivityKind.verifPending:
        return Icons.how_to_reg_rounded;
      case ActivityKind.verifApproved:
        return Icons.verified_user_rounded;
      case ActivityKind.verifRejected:
        return Icons.cancel_rounded;
    }
  }

  Color _activityColor(ActivityKind kind) {
    switch (kind) {
      case ActivityKind.reportNew:
        return AppColors.primaryBlue;
      case ActivityKind.reportReviewing:
        return AppColors.orange;
      case ActivityKind.reportResolved:
        return AppColors.green;
      case ActivityKind.reportRejected:
        return AppColors.red;
      case ActivityKind.verifPending:
        return AppColors.orange;
      case ActivityKind.verifApproved:
        return AppColors.green;
      case ActivityKind.verifRejected:
        return AppColors.red;
    }
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

// ── AI & NLP insights (awaiting pipeline) ────────────────────────────────────
//
// GovPulse's NLP layer classifies feedback by sentiment, urgency, and category
// (see the research paper). Those columns don't exist in Supabase yet, so this
// renders as a clearly-labelled placeholder zone — designed and ready to wire,
// not faked. When the pipeline writes sentiment/urgency, populate the
// AdminDashboardData model and swap the placeholders for the real widgets.
class _NlpInsightsCard extends StatelessWidget {
  const _NlpInsightsCard();

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome_rounded,
                size: 18,
                color: AppColors.primaryBlue,
              ),
              const SizedBox(width: 8),
              const _CardTitle('AI & NLP insights'),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'NLP pipeline',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryBlue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Sentiment, urgency, and forecast from citizen feedback',
            style: TextStyle(fontSize: 12, color: AdminUi.textMuted),
          ),
          const SizedBox(height: 16),
          const _NlpSlot(
            icon: Icons.sentiment_satisfied_alt_rounded,
            label: 'Citizen sentiment',
            hint: 'Positive · neutral · negative split',
          ),
          const SizedBox(height: 10),
          const _NlpSlot(
            icon: Icons.priority_high_rounded,
            label: 'Urgency triage',
            hint: 'High · medium · low classification',
          ),
          const SizedBox(height: 10),
          const _NlpSlot(
            icon: Icons.insights_rounded,
            label: 'Predictive outlook',
            hint: 'Forecasted service-quality trend',
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AdminUi.subtle,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AdminUi.border),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.schedule_rounded,
                  size: 14,
                  color: AdminUi.textMuted,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Awaiting NLP pipeline — these activate once feedback is classified.',
                    style: TextStyle(fontSize: 11, color: AdminUi.textMuted),
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

class _NlpSlot extends StatelessWidget {
  final IconData icon;
  final String label;
  final String hint;
  const _NlpSlot({required this.icon, required this.label, required this.hint});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AdminUi.subtle,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 17, color: AdminUi.textMuted),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AdminUi.textSecondary,
                ),
              ),
              Text(
                hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: AdminUi.textMuted),
              ),
            ],
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
          child: Padding(padding: padding, child: child),
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

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, color: AdminUi.textMuted),
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
        color: AppColors.stroke,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}

class _ActivitySkeletonRow extends StatelessWidget {
  const _ActivitySkeletonRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: AppColors.stroke,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
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
