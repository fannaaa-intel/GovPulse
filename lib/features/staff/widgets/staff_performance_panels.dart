// ════════════════════════════════════════════════════════════════════════════
//  Performance panels — shared by the staff dashboard and the admin console
//
//  WHAT THESE SHOW, AND WHAT THEY REFUSE TO SHOW
//
//  A scorecard is built only from actions the person took: reports they
//  completed, chat conversations citizens rated THEM for, suggestion replies
//  an admin published, and how often a draft came back.
//
//  Citizen OFFICE ratings are not in anyone's score. `feedbacks` carries no
//  staff id — the citizen is rating a counter visit, often one no console user
//  touched. The office's stars appear as DEPARTMENT context, never attached to
//  a name. See staff_performance_view for the full reasoning.
//
//  Staff see their own card. The ranked comparison is an admin surface.
// ════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../data/staff_engagement_repository.dart';
import '../theme/staff_ui.dart';
import '../widgets/staff_common.dart';

/// Below this a caller should pass `compact: true` to ScorecardPanel, so its
/// metric tiles go two-up instead of four across.
const double kMetricsCompactBelow = 640;

// ── One person's scorecard ──────────────────────────────────────────────────

class ScorecardPanel extends StatelessWidget {
  final StaffScorecard card;

  /// Two metric tiles per row instead of four. Decided by the CALLER, which
  /// already knows its width — this card cannot measure itself with a
  /// LayoutBuilder without becoming unmeasurable to its own parent.
  final bool compact;

  /// Department average, shown as context beside the card. Never folded into
  /// the score — see the header note.
  final double? departmentRating;
  final bool departmentReceivesRatings;

  const ScorecardPanel({
    super.key,
    required this.card,
    this.compact = false,
    this.departmentRating,
    this.departmentReceivesRatings = true,
  });

  @override
  Widget build(BuildContext context) {
    final metrics = <Widget>[
      _Metric(
        value: '${card.reportsResolved}',
        label: 'Reports completed',
        icon: Icons.task_alt_rounded,
        color: StaffUi.online,
      ),
      _Metric(
        value: card.chatRating == null
            ? '—'
            : card.chatRating!.toStringAsFixed(1),
        label: card.chatRatingCount == 0
            ? 'Chat rating'
            : 'Chat rating (${card.chatRatingCount})',
        icon: Icons.forum_rounded,
        color: const Color(0xFFF5A623),
      ),
      _Metric(
        value: '${card.repliesApproved}',
        label: 'Replies published',
        icon: Icons.mark_email_read_outlined,
        color: StaffUi.accent,
      ),
      _Metric(
        value: card.medianResponseHours == null
            ? '—'
            : _hours(card.medianResponseHours!),
        label: 'Typical reply time',
        icon: Icons.schedule_rounded,
        color: StaffUi.accentSoft,
      ),
    ];

    return StaffCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights_rounded,
                  size: 17, color: StaffUi.accent),
              const SizedBox(width: 7),
              const Expanded(
                child: Text(
                  'Your performance',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: StaffUi.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Flex rows, NOT a LayoutBuilder.
          //
          // A LayoutBuilder cannot report an intrinsic height, so any ancestor
          // that asks for one — an IntrinsicHeight equalising this card against
          // the chart beside it — throws during layout and the whole dashboard
          // fails to render. Expanded children inside plain Rows give the same
          // even split and stay measurable.
          //
          // The breakpoint moves to the caller: `compact` is decided by the
          // parent, which already knows its width.
          _MetricGrid(metrics: metrics, compact: compact),
          if (card.rejectionRate != null && card.repliesTotal > 0) ...[
            const SizedBox(height: 12),
            _ReturnRate(card: card),
          ],
          if (departmentReceivesRatings) ...[
            const SizedBox(height: 12),
            _DepartmentContext(rating: departmentRating),
          ],
        ],
      ),
    );
  }
}

String _hours(double h) {
  if (h < 1) return '${(h * 60).round()}m';
  if (h < 48) return '${h.toStringAsFixed(h < 10 ? 1 : 0)}h';
  return '${(h / 24).round()}d';
}

class _Metric extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;
  const _Metric({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: StaffUi.subtle,
        borderRadius: BorderRadius.circular(StaffUi.controlRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 5),
              // Flexible + ellipsis: "1.2k" or a long duration must shrink
              // rather than push the row past the tile.
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: StaffUi.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: StaffUi.textMuted),
          ),
        ],
      ),
    );
  }
}

/// How often the Municipality sent a draft back. The quality signal — volume
/// alone rewards fast and careless.
class _ReturnRate extends StatelessWidget {
  final StaffScorecard card;
  const _ReturnRate({required this.card});

  @override
  Widget build(BuildContext context) {
    final rate = card.rejectionRate!;
    final pct = (rate * 100).round();
    final good = rate <= 0.2;
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: (good ? StaffUi.online : StaffUi.warn).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(StaffUi.controlRadius),
      ),
      child: Row(
        children: [
          Icon(
            good ? Icons.verified_outlined : Icons.undo_rounded,
            size: 15,
            color: good ? StaffUi.online : StaffUi.warn,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$pct% of your replies came back for changes '
              '(${card.repliesRejected} of ${card.repliesTotal})',
              style: const TextStyle(
                fontSize: 12,
                height: 1.35,
                color: StaffUi.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The office's citizen rating, stated plainly as the OFFICE's number so it is
/// never read as the individual's score.
class _DepartmentContext extends StatelessWidget {
  final double? rating;
  const _DepartmentContext({required this.rating});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: StaffUi.accentWash,
        borderRadius: BorderRadius.circular(StaffUi.controlRadius),
      ),
      child: Row(
        children: [
          const Icon(Icons.apartment_rounded, size: 15, color: StaffUi.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              rating == null
                  ? "Your office has no citizen ratings yet."
                  : "Your office's citizen rating is "
                      '${rating!.toStringAsFixed(1)} out of 5. '
                      'This reflects the office, not any one person.',
              style: const TextStyle(
                fontSize: 12,
                height: 1.35,
                color: StaffUi.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Rating trend ────────────────────────────────────────────────────────────

/// Weekly average rating. One line, because the only question a trend answers
/// well is "are we getting better or worse".
class RatingTrendPanel extends StatelessWidget {
  final List<RatingPoint> points;
  const RatingTrendPanel({super.key, required this.points});

  @override
  Widget build(BuildContext context) {
    final rated = points.where((p) => p.count > 0).toList();
    return StaffCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.show_chart_rounded,
                  size: 17, color: StaffUi.accent),
              const SizedBox(width: 7),
              const Expanded(
                child: Text(
                  'Rating trend',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: StaffUi.textPrimary,
                  ),
                ),
              ),
              Text(
                'Last ${points.length} weeks',
                style: const TextStyle(fontSize: 11, color: StaffUi.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 2),
          // Says what the line IS. Without it the chart is an unlabelled line
          // against an unlabelled axis: nothing states that the numbers are
          // stars, that the scale is 1-5, or that each point is a week.
          const Text(
            'Average stars citizens gave your office each week, out of 5.',
            style: TextStyle(fontSize: 11.5, color: StaffUi.textMuted),
          ),
          if (rated.length >= 2) ...[
            const SizedBox(height: 10),
            _TrendHeadline(rated: rated),
          ],
          const SizedBox(height: 12),
          if (rated.length < 2)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'Not enough ratings yet to show a trend.',
                  style: TextStyle(fontSize: 12.5, color: StaffUi.textMuted),
                ),
              ),
            )
          else ...[
            SizedBox(
              height: 130,
              child: CustomPaint(
                size: Size.infinite,
                painter: _TrendPainter(points),
              ),
            ),
            const SizedBox(height: 6),
            // The x-axis had no labels at all, so nothing said the line ran
            // left-to-right through time. Two anchors are enough and stay
            // readable at any width; a label per week would collide.
            Padding(
              padding: const EdgeInsets.only(left: 22),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${points.length} weeks ago',
                    style: const TextStyle(
                        fontSize: 10, color: StaffUi.textMuted),
                  ),
                  const Text(
                    'This week',
                    style:
                        TextStyle(fontSize: 10, color: StaffUi.textMuted),
                  ),
                ],
              ),
            ),
            if (points.any((p) => p.count == 0)) ...[
              const SizedBox(height: 8),
              // A break in the line is otherwise unexplained — it looks like a
              // rendering fault rather than a week nobody rated.
              Row(
                children: [
                  Container(
                    width: 14,
                    height: 2,
                    color: StaffUi.border,
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'A gap means no ratings were received that week.',
                      style:
                          TextStyle(fontSize: 10.5, color: StaffUi.textMuted),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// The number the chart is about, stated in words, plus which way it moved.
///
/// A line alone makes the reader estimate the current value off an axis and
/// guess the direction from the slope. This says both outright, so the chart
/// becomes supporting evidence rather than the only source.
class _TrendHeadline extends StatelessWidget {
  final List<RatingPoint> rated;
  const _TrendHeadline({required this.rated});

  @override
  Widget build(BuildContext context) {
    final latest = rated.last.average;
    final previous = rated[rated.length - 2].average;
    final delta = latest - previous;
    // A tenth of a star is noise on a handful of ratings, not a trend.
    final flat = delta.abs() < 0.1;
    final up = delta > 0;
    final color = flat
        ? StaffUi.textMuted
        : (up ? StaffUi.online : StaffUi.danger);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          latest.toStringAsFixed(1),
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: StaffUi.textPrimary,
          ),
        ),
        const SizedBox(width: 3),
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
            '/ 5',
            style: TextStyle(fontSize: 12, color: StaffUi.textMuted),
          ),
        ),
        const SizedBox(width: 10),
        Icon(
          flat
              ? Icons.remove_rounded
              : (up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded),
          size: 14,
          color: color,
        ),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            flat
                ? 'about the same as last week'
                : '${delta.abs().toStringAsFixed(1)} '
                    '${up ? 'higher' : 'lower'} than last week',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  final List<RatingPoint> points;
  _TrendPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    // The y-axis is pinned to the rating scale 1..5 rather than fitted to the
    // data. An auto-fitted axis makes a wobble between 4.1 and 4.3 look like a
    // collapse, which is exactly the misreading a performance chart must not
    // invite.
    const minY = 1.0, maxY = 5.0;
    const leftPad = 22.0, bottomPad = 16.0;
    final w = size.width - leftPad;
    final h = size.height - bottomPad;
    if (w <= 0 || h <= 0) return;

    final grid = Paint()
      ..color = StaffUi.border
      ..strokeWidth = 1;
    final text = TextPainter(textDirection: TextDirection.ltr);

    for (var v = 1; v <= 5; v++) {
      final y = h - ((v - minY) / (maxY - minY)) * h;
      canvas.drawLine(Offset(leftPad, y), Offset(size.width, y), grid);
      text
        ..text = TextSpan(
          text: '$v',
          style: const TextStyle(fontSize: 9, color: StaffUi.textMuted),
        )
        ..layout();
      text.paint(canvas, Offset(leftPad - text.width - 5, y - text.height / 2));
    }

    // A week with no ratings is a GAP, not a zero. Plotting it as zero would
    // invent a catastrophic week that never happened.
    final path = Path();
    var started = false;
    final dots = <Offset>[];
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      if (p.count == 0) {
        started = false;
        continue;
      }
      final x = leftPad + (points.length == 1
          ? w / 2
          : (i / (points.length - 1)) * w);
      final y = h - ((p.average.clamp(minY, maxY) - minY) / (maxY - minY)) * h;
      final o = Offset(x, y);
      dots.add(o);
      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = StaffUi.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    for (final o in dots) {
      canvas.drawCircle(o, 3.2, Paint()..color = StaffUi.accent);
      canvas.drawCircle(o, 1.6, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) => old.points != points;
}

// ── Ranked leaderboard (admin only) ─────────────────────────────────────────

/// Horizontal bars, ranked. Horizontal because staff names are long and a
/// vertical bar chart would either clip them or turn them sideways.
class StaffLeaderboardPanel extends StatelessWidget {
  final List<StaffScorecard> cards;
  final LeaderboardMetric metric;
  final ValueChanged<LeaderboardMetric>? onMetric;
  final String title;

  const StaffLeaderboardPanel({
    super.key,
    required this.cards,
    required this.metric,
    this.onMetric,
    this.title = 'Staff performance',
  });

  @override
  Widget build(BuildContext context) {
    final ranked = [...cards]
      ..sort((a, b) => _value(b).compareTo(_value(a)));
    final maxV = ranked.isEmpty
        ? 0.0
        : ranked.map(_value).reduce((a, b) => a > b ? a : b);

    return StaffCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, c) {
              final head = Row(
                children: [
                  const Icon(Icons.leaderboard_rounded,
                      size: 17, color: StaffUi.accent),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: StaffUi.textPrimary,
                      ),
                    ),
                  ),
                ],
              );
              if (onMetric == null) return head;
              final picker = _MetricPicker(active: metric, onPick: onMetric!);
              // The picker holds four chips whose width grows with the text
              // scale, so a width threshold alone is not enough: at 640px and
              // 1.3x the four chips are wider than the half-row they are given
              // and the Row overflows regardless of how the slack is split.
              // Stacking below 700 keeps the picker at its natural width at
              // every scale this app supports.
              if (c.maxWidth < 700) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [head, const SizedBox(height: 10), picker],
                );
              }
              return Row(
                children: [
                  Expanded(child: head),
                  const SizedBox(width: 10),
                  // Flexible, not a bare child: above 700px the picker still
                  // must be allowed to shrink into its own horizontal scroll
                  // rather than force the Row wider than the card.
                  Flexible(child: picker),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          // What the chosen metric actually counts, and which direction is
          // good. A chip reading "Speed" over a bar reading "1" is a name, a
          // length and a number with no unit between them.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline_rounded,
                  size: 13, color: StaffUi.textMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  leaderboardMetricHelp(metric),
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: StaffUi.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (ranked.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'No staff activity to rank yet.',
                  style: TextStyle(fontSize: 12.5, color: StaffUi.textMuted),
                ),
              ),
            )
          else ...[
            // One person is not a ranking. Saying so stops a single full-width
            // bar reading as "top of the league" when there is nobody to be
            // top of.
            if (ranked.length == 1) ...[
              const Text(
                'Only one staff member has activity to show, so there is '
                'nothing to compare yet.',
                style: TextStyle(fontSize: 11.5, color: StaffUi.textMuted),
              ),
              const SizedBox(height: 10),
            ],
            for (var i = 0; i < ranked.length; i++) ...[
              _Bar(
                rank: i + 1,
                card: ranked[i],
                value: _value(ranked[i]),
                display: _display(ranked[i]),
                unit: leaderboardMetricUnit(metric, _value(ranked[i])),
                maxValue: maxV,
                showRank: ranked.length > 1,
              ),
              if (i < ranked.length - 1) const SizedBox(height: 9),
            ],
          ],
        ],
      ),
    );
  }

  double _value(StaffScorecard c) => switch (metric) {
        LeaderboardMetric.reportsResolved => c.reportsResolved.toDouble(),
        LeaderboardMetric.repliesPublished => c.repliesApproved.toDouble(),
        LeaderboardMetric.chatRating => c.chatRating ?? 0,
        // Faster is better, so the bar is inverted: a short reply time must
        // produce a LONG bar or the chart ranks the slowest staff highest.
        LeaderboardMetric.responseTime =>
          c.medianResponseHours == null ? 0 : 1 / (c.medianResponseHours! + 1),
      };

  String _display(StaffScorecard c) => switch (metric) {
        LeaderboardMetric.reportsResolved => '${c.reportsResolved}',
        LeaderboardMetric.repliesPublished => '${c.repliesApproved}',
        LeaderboardMetric.chatRating =>
          c.chatRating == null ? '—' : c.chatRating!.toStringAsFixed(1),
        LeaderboardMetric.responseTime => c.medianResponseHours == null
            ? '—'
            : _hours(c.medianResponseHours!),
      };
}

enum LeaderboardMetric {
  reportsResolved,
  repliesPublished,
  chatRating,
  responseTime,
}

/// The chip label. Kept to one or two words so four chips fit a phone row —
/// the sentence that explains each one lives in [leaderboardMetricHelp],
/// directly under the header, because a bare noun like "Speed" does not say
/// what is being counted or which direction is good.
String leaderboardMetricLabel(LeaderboardMetric m) => switch (m) {
      LeaderboardMetric.reportsResolved => 'Reports',
      LeaderboardMetric.repliesPublished => 'Replies',
      LeaderboardMetric.chatRating => 'Chat rating',
      LeaderboardMetric.responseTime => 'Speed',
    };

/// One plain sentence naming WHAT is counted and WHICH WAY is better.
///
/// Without this the page shows a name, a bar and a number with no unit: "1"
/// could be one report, one percent or rank one. Every sentence therefore
/// states the unit, and the two metrics where bigger is NOT simply better say
/// so outright.
String leaderboardMetricHelp(LeaderboardMetric m) => switch (m) {
      LeaderboardMetric.reportsResolved =>
        'Reports this person completed and an admin approved. Higher is better.',
      LeaderboardMetric.repliesPublished =>
        'Suggestion replies they wrote that were approved and sent to the '
            'citizen. Higher is better.',
      LeaderboardMetric.chatRating =>
        'Average stars citizens gave them after a chat, out of 5. Higher is '
            'better.',
      LeaderboardMetric.responseTime =>
        'How quickly they answer a suggestion, measured as the usual time from '
            'the citizen asking. FASTER is better, so a longer bar means a '
            'shorter wait.',
    };

/// The unit that follows the number on each bar, so "1" reads as "1 report".
String leaderboardMetricUnit(LeaderboardMetric m, double value) =>
    switch (m) {
      LeaderboardMetric.reportsResolved => value == 1 ? 'report' : 'reports',
      LeaderboardMetric.repliesPublished => value == 1 ? 'reply' : 'replies',
      LeaderboardMetric.chatRating => 'out of 5',
      LeaderboardMetric.responseTime => 'typical wait',
    };

class _MetricPicker extends StatelessWidget {
  final LeaderboardMetric active;
  final ValueChanged<LeaderboardMetric> onPick;
  const _MetricPicker({required this.active, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final m in LeaderboardMetric.values)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Material(
                color: m == active ? StaffUi.accent : StaffUi.subtle,
                borderRadius: BorderRadius.circular(7),
                child: InkWell(
                  onTap: () => onPick(m),
                  borderRadius: BorderRadius.circular(7),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 6),
                    child: Text(
                      leaderboardMetricLabel(m),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: m == active
                            ? Colors.white
                            : StaffUi.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final int rank;
  final StaffScorecard card;
  final double value;
  final String display;

  /// What the number counts ("reports", "out of 5", "typical wait"), shown
  /// under it so a bare "1" is never left to be guessed at.
  final String unit;
  final double maxValue;

  /// Hidden when there is only one row: a "1" beside the only person reads as
  /// a rank they earned rather than the only entry there is.
  final bool showRank;

  const _Bar({
    required this.rank,
    required this.card,
    required this.value,
    required this.display,
    required this.unit,
    required this.maxValue,
    this.showRank = true,
  });

  @override
  Widget build(BuildContext context) {
    final frac = maxValue <= 0 ? 0.0 : (value / maxValue).clamp(0.0, 1.0);
    return Row(
      children: [
        if (showRank)
          SizedBox(
            width: 20,
            child: Text(
              '$rank',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: rank <= 3 ? StaffUi.accent : StaffUi.textMuted,
              ),
            ),
          ),
        // A fixed name column keeps every bar starting at the same x — ragged
        // bar origins make two lengths impossible to compare by eye.
        SizedBox(
          width: 104,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                card.fullName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: StaffUi.textPrimary,
                ),
              ),
              Text(
                card.department,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: StaffUi.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 12,
              backgroundColor: StaffUi.subtle,
              valueColor: AlwaysStoppedAnimation(
                rank == 1 ? StaffUi.accent : StaffUi.accentSoft,
              ),
            ),
          ),
        ),
        // Wider than the number needs, because the unit sits beneath it. Both
        // lines are right-aligned so the column reads as one block.
        SizedBox(
          width: 74,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                display,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: StaffUi.textPrimary,
                ),
              ),
              Text(
                unit,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 9.5,
                  height: 1.2,
                  color: StaffUi.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}


/// The four metric tiles, as flex rows.
///
/// Deliberately not a Wrap sized by a LayoutBuilder: this card sits beside the
/// rating chart in an IntrinsicHeight row, and a LayoutBuilder in the subtree
/// makes the whole row unmeasurable and throws at layout time.
class _MetricGrid extends StatelessWidget {
  final List<Widget> metrics;
  final bool compact;
  const _MetricGrid({required this.metrics, required this.compact});

  @override
  Widget build(BuildContext context) {
    const gap = 10.0;
    final perRow = compact ? 2 : 4;
    final rows = <Widget>[];
    for (var i = 0; i < metrics.length; i += perRow) {
      final slice = metrics.skip(i).take(perRow).toList();
      rows.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var j = 0; j < perRow; j++) ...[
              // A short final row keeps its columns the same width as a full
              // one by padding with empty flex slots, so the tiles line up
              // vertically down the card.
              Expanded(
                child: j < slice.length ? slice[j] : const SizedBox.shrink(),
              ),
              if (j < perRow - 1) const SizedBox(width: gap),
            ],
          ],
        ),
      ));
      if (i + perRow < metrics.length) rows.add(const SizedBox(height: gap));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: rows,
    );
  }
}
