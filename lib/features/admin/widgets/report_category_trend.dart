// ════════════════════════════════════════════════════════════════════════════
//  Admin dashboard — reports by category over time
//
//  One chart instead of two cards: "Reports over time" (how many) and "Top
//  reported categories" (what kind) used to sit apart, and the category card
//  counted ALL TIME while the trend used the 7/30/90-day range, so the two
//  could disagree. Here every number comes from one range.
//
//  One line per category, each in its own colour, a legend that names every
//  colour with its total, and a tooltip on hover (web) or touch (phone) that
//  gives the count of the line under the pointer for that day or week.
//
//  Colours: the first six slots of the dataviz reference palette, in fixed
//  order, so a category keeps its colour whatever the range. Validated
//  (scripts/validate_palette.js, light, on white): CVD ΔE ≥ 9.1, normal-vision
//  ΔE ≥ 19.6 for every adjacent pair. Three slots sit under 3:1 contrast on
//  white, so a line is never identified by colour alone — the legend and the
//  tooltip both carry the category name.
//
//  7 and 30 days plot one point per day; 90 days plots one per week, because
//  90 daily points × 6 lines is a scribble.
// ════════════════════════════════════════════════════════════════════════════

import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../providers/admin_dashboard_provider.dart' show ReportPoint;
import '../theme/admin_ui.dart';

/// One category line: its key, the label the admin reads, and its colour.
class ReportCategorySeries {
  final String key;
  final String label;

  /// For a narrow legend, where two columns of full names would ellipsize.
  final String shortLabel;
  final Color color;
  const ReportCategorySeries(this.key, this.label, this.shortLabel, this.color);
}

/// Fixed order = fixed colour. Never re-ordered by volume.
const List<ReportCategorySeries> kReportCategorySeries = [
  ReportCategorySeries(
    'road',
    'Road & Infrastructure',
    'Road',
    Color(0xFF2A78D6),
  ),
  ReportCategorySeries('waste', 'Waste & Garbage', 'Waste', Color(0xFFEB6834)),
  ReportCategorySeries(
    'drainage',
    'Drainage & Flooding',
    'Drainage',
    Color(0xFF1BAF7A),
  ),
  ReportCategorySeries(
    'streetlight',
    'Streetlight Outage',
    'Streetlight',
    Color(0xFFEDA100),
  ),
  ReportCategorySeries(
    'environment',
    'Environment & Pollution',
    'Environment',
    Color(0xFFE87BA4),
  ),
  ReportCategorySeries('others', 'Others', 'Others', Color(0xFF008300)),
];

const _kMonths = [
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

String _dayMonth(DateTime d) => '${d.day} ${_kMonths[d.month - 1]}';

/// The bucketed numbers behind the chart. Pure, so it is tested directly.
class CategoryTrend {
  /// First day of each bucket.
  final List<DateTime> bucketStarts;

  /// 1 (daily) or 7 (weekly).
  final int bucketDays;

  /// Category key → count per bucket, for every key in [kReportCategorySeries].
  final Map<String, List<int>> counts;

  /// Category key → total over the whole range.
  final Map<String, int> totals;

  const CategoryTrend({
    required this.bucketStarts,
    required this.bucketDays,
    required this.counts,
    required this.totals,
  });

  int get total => totals.values.fold(0, (a, b) => a + b);
  int get bucketCount => bucketStarts.length;

  int get maxCount =>
      counts.values.expand((c) => c).fold<int>(0, (a, b) => a > b ? a : b);

  /// The range is exactly the last [days] days, today included. Weekly
  /// buckets run back from that same start, so the last week may be shorter
  /// than seven days — the totals still match "the last [days] days".
  static CategoryTrend build(
    List<ReportPoint> points, {
    required int days,
    required DateTime now,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final start = today.subtract(Duration(days: days - 1));
    final bucketDays = days > 30 ? 7 : 1;
    final n = (days / bucketDays).ceil();
    final keys = {for (final s in kReportCategorySeries) s.key};

    final counts = {
      for (final s in kReportCategorySeries) s.key: List<int>.filled(n, 0),
    };
    for (final p in points) {
      final day = DateTime(p.at.year, p.at.month, p.at.day);
      final offset = day.difference(start).inDays;
      if (offset < 0 || offset >= days) continue;
      final key = keys.contains(p.category) ? p.category : 'others';
      counts[key]![offset ~/ bucketDays]++;
    }
    return CategoryTrend(
      bucketStarts: [
        for (var i = 0; i < n; i++) start.add(Duration(days: i * bucketDays)),
      ],
      bucketDays: bucketDays,
      counts: counts,
      totals: {
        for (final e in counts.entries) e.key: e.value.fold(0, (a, b) => a + b),
      },
    );
  }

  /// "3 Oct" for a day; "Week of 22 Sep" for a week.
  String bucketLabel(int i) => bucketDays == 1
      ? _dayMonth(bucketStarts[i])
      : 'Week of ${_dayMonth(bucketStarts[i])}';
}

class ReportCategoryTrend extends StatefulWidget {
  final List<ReportPoint> points;
  final int days;

  /// Injected so tests and previews are deterministic.
  final DateTime? now;

  const ReportCategoryTrend({
    super.key,
    required this.points,
    required this.days,
    this.now,
  });

  @override
  State<ReportCategoryTrend> createState() => _ReportCategoryTrendState();
}

class _ReportCategoryTrendState extends State<ReportCategoryTrend> {
  /// The category the admin tapped in the legend: its line is drawn on top,
  /// thicker, and the others fade. Null shows every line equally.
  String? _focus;

  @override
  Widget build(BuildContext context) {
    final trend = CategoryTrend.build(
      widget.points,
      days: widget.days,
      now: widget.now ?? DateTime.now(),
    );
    // A focused category that has nothing in this range would fade every line
    // for nothing; drop the focus instead.
    final focus = (_focus != null && (trend.totals[_focus] ?? 0) > 0)
        ? _focus
        : null;

    if (trend.total == 0) {
      return _Empty(days: widget.days);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Summary(trend: trend, days: widget.days),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, c) => SizedBox(
            height: c.maxWidth < 420 ? 200 : 230,
            child: _Chart(trend: trend, focus: focus, width: c.maxWidth),
          ),
        ),
        const SizedBox(height: 14),
        _Legend(
          trend: trend,
          focus: focus,
          onTap: (key) => setState(() => _focus = _focus == key ? null : key),
        ),
        const SizedBox(height: 8),
        const Text(
          'Hover or tap a line to see its count. Tap a category to highlight '
          'its line.',
          style: TextStyle(fontSize: 11, height: 1.4, color: AdminUi.textMuted),
        ),
      ],
    );
  }
}

// ── Headline ────────────────────────────────────────────────────────────────

class _Summary extends StatelessWidget {
  final CategoryTrend trend;
  final int days;
  const _Summary({required this.trend, required this.days});

  @override
  Widget build(BuildContext context) {
    final topCount = trend.totals.values.fold<int>(0, math.max);
    // A tie names every leader: picking one of two equal categories would
    // tell the admin something the numbers do not.
    final leaders = [
      for (final s in kReportCategorySeries)
        if ((trend.totals[s.key] ?? 0) == topCount) s.label,
    ];
    final share = (topCount / trend.total * 100).round();
    final most = leaders.length == 1
        ? 'Most reported: ${leaders.single} ($topCount, $share%)'
        : 'Most reported: ${leaders.join(' and ')} ($topCount each)';
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 10,
      runSpacing: 4,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '${trend.total}',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  color: AdminUi.textPrimary,
                ),
              ),
              TextSpan(
                text: ' report${trend.total == 1 ? '' : 's'} in $days days',
                style: const TextStyle(
                  fontSize: 13,
                  color: AdminUi.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            most,
            style: const TextStyle(fontSize: 12, color: AdminUi.textMuted),
          ),
        ),
      ],
    );
  }
}

// ── Chart ───────────────────────────────────────────────────────────────────

class _Chart extends StatelessWidget {
  final CategoryTrend trend;
  final String? focus;
  final double width;
  const _Chart({required this.trend, required this.focus, required this.width});

  @override
  Widget build(BuildContext context) {
    final n = trend.bucketCount;
    final maxVal = trend.maxCount;
    final maxY = maxVal <= 4 ? 4.0 : (maxVal * 1.2).ceilToDouble();
    final yInterval = math.max(1.0, (maxY / 4).ceilToDouble());
    // Roughly one date label per 70px, never more than six.
    final labels = (width / 70).floor().clamp(2, 6);
    final xInterval = math.max(1.0, ((n - 1) / (labels - 1)).ceilToDouble());
    final dots = n <= 14;

    // Lines that have anything to show, in fixed order — the focused one last,
    // so it draws on top of the others.
    final drawn = [
      for (final s in kReportCategorySeries)
        if ((trend.totals[s.key] ?? 0) > 0 && s.key != focus) s,
      for (final s in kReportCategorySeries)
        if (s.key == focus) s,
    ];

    LineChartBarData bar(ReportCategorySeries s) {
      final dim = focus != null && s.key != focus;
      final color = dim ? s.color.withValues(alpha: 0.18) : s.color;
      return LineChartBarData(
        spots: [
          for (var i = 0; i < n; i++)
            FlSpot(i.toDouble(), trend.counts[s.key]![i].toDouble()),
        ],
        // Straight segments: a curve between two days draws values nobody
        // reported (humps above a day with one report, dips below zero).
        isCurved: false,
        color: color,
        barWidth: s.key == focus ? 3 : 2,
        isStrokeCapRound: true,
        isStrokeJoinRound: true,
        dotData: FlDotData(
          show: dots,
          getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
            radius: 3,
            color: color,
            // A 2px surface ring so crossing lines' dots stay separable.
            strokeWidth: 1.5,
            strokeColor: AdminUi.surface,
          ),
        ),
      );
    }

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: math.max(1, n - 1).toDouble(),
        minY: 0,
        maxY: maxY,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: yInterval,
          getDrawingHorizontalLine: (v) =>
              const FlLine(color: Color(0xFFE6EAF0), strokeWidth: 1),
        ),
        borderData: FlBorderData(
          show: true,
          border: const Border(bottom: BorderSide(color: AdminUi.border)),
        ),
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
                    textAlign: TextAlign.right,
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
                if (i < 0 || i >= n || value != i.toDouble()) {
                  return const SizedBox.shrink();
                }
                return SideTitleWidget(
                  meta: meta,
                  space: 6,
                  fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                  child: Text(
                    _dayMonth(trend.bucketStarts[i]),
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
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          // The line under the pointer, not every line at that date: the
          // distance counts both axes, and the pointer only has to come
          // within 16px of a point — a 2px line is not a target anyone hits.
          distanceCalculator: (touch, spot) => (touch - spot).distance,
          touchSpotThreshold: 16,
          getTouchedSpotIndicator: (barData, indexes) => [
            for (final _ in indexes)
              TouchedSpotIndicatorData(
                const FlLine(color: AdminUi.borderStrong, strokeWidth: 1),
                FlDotData(
                  getDotPainter: (spot, _, bar, _) => FlDotCirclePainter(
                    radius: 5,
                    color: bar.color ?? AdminUi.textPrimary,
                    strokeWidth: 2,
                    strokeColor: AdminUi.surface,
                  ),
                ),
              ),
          ],
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AdminUi.surface,
            tooltipBorder: const BorderSide(color: AdminUi.border),
            tooltipBorderRadius: BorderRadius.circular(8),
            tooltipPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
            // Wide enough for the longest category name on one line.
            maxContentWidth: 220,
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItems: (spots) => [
              for (final sp in spots) _tooltipItem(drawn[sp.barIndex], sp),
            ],
          ),
        ),
        lineBarsData: [for (final s in drawn) bar(s)],
      ),
    );
  }

  /// Value first (the reader already knows which line they pointed at and
  /// wants the number), then the category with a short stroke of its colour
  /// as the key, then the date. Text stays in text colours.
  LineTooltipItem _tooltipItem(ReportCategorySeries s, LineBarSpot sp) {
    final count = sp.y.round();
    return LineTooltipItem(
      '$count report${count == 1 ? '' : 's'}\n',
      const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        color: AdminUi.textPrimary,
        height: 1.5,
      ),
      textAlign: TextAlign.left,
      children: [
        TextSpan(
          text: '━ ',
          style: TextStyle(
            color: s.color,
            fontWeight: FontWeight.w900,
            fontSize: 12,
          ),
        ),
        TextSpan(
          text: '${s.label}\n',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AdminUi.textSecondary,
          ),
        ),
        TextSpan(
          text: trend.bucketLabel(sp.x.round()),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: AdminUi.textMuted,
          ),
        ),
      ],
    );
  }
}

// ── Legend ──────────────────────────────────────────────────────────────────

class _Legend extends StatelessWidget {
  final CategoryTrend trend;
  final String? focus;
  final ValueChanged<String> onTap;
  const _Legend({
    required this.trend,
    required this.focus,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        // Narrow: an even grid of short names (three rows of two) instead of
        // six full names stacked one per line.
        final narrow = c.maxWidth < 480;
        final cols = c.maxWidth < 240 ? 1 : 2;
        final cell = (c.maxWidth - 6 * (cols - 1)) / cols;
        return Wrap(
          spacing: 6,
          runSpacing: narrow ? 2 : 6,
          children: [
            for (final s in kReportCategorySeries)
              SizedBox(
                width: narrow ? cell : null,
                child: _LegendItem(
                  series: s,
                  short: narrow,
                  total: trend.totals[s.key] ?? 0,
                  focused: focus == s.key,
                  faded: focus != null && focus != s.key,
                  onTap: () => onTap(s.key),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _LegendItem extends StatelessWidget {
  final ReportCategorySeries series;
  final bool short;
  final int total;
  final bool focused;
  final bool faded;
  final VoidCallback onTap;
  const _LegendItem({
    required this.series,
    this.short = false,
    required this.total,
    required this.focused,
    required this.faded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final empty = total == 0;
    return Semantics(
      button: !empty,
      selected: focused,
      label:
          '${series.label}, $total report${total == 1 ? '' : 's'}'
          '${empty ? '' : '. Tap to highlight its line.'}',
      excludeSemantics: true,
      child: Opacity(
        opacity: faded || empty ? 0.45 : 1,
        child: Material(
          color: focused ? AdminUi.subtle : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: empty ? null : onTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              constraints: const BoxConstraints(minHeight: 36),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: focused ? AdminUi.borderStrong : Colors.transparent,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // A line key for a line chart, not a box.
                  Container(
                    width: 16,
                    height: 3,
                    decoration: BoxDecoration(
                      color: series.color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      short ? series.shortLabel : series.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: focused ? FontWeight.w700 : FontWeight.w500,
                        color: AdminUi.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$total',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: AdminUi.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final int days;
  const _Empty({required this.days});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.show_chart_rounded,
              size: 28,
              color: AdminUi.textMuted,
            ),
            const SizedBox(height: 8),
            Text(
              'No reports in the last $days days.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AdminUi.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
