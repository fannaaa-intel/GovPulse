import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/admin_reports_provider.dart';
import '../theme/admin_ui.dart';
import 'admin_submission_ui.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Report status tracker
//
//  The stepper + stage card + timeline that drive the "Update Report Status"
//  pane of the admin report detail.
//
//  The stages mirror the REAL lifecycle a report moves through in this product —
//  admin triage hands the report to an office (`assigned_to_department`), then
//  that office drives `reports.status` under_review → in_progress → resolved.
//  There is deliberately no stage the data can never reach: every circle here
//  can actually light up.
// ════════════════════════════════════════════════════════════════════════════

/// Where a single stage sits relative to the report's current position.
enum ReportStageState {
  /// Passed — the report has moved beyond this stage.
  done,

  /// The stage the report is sitting in right now.
  current,

  /// Not reached yet.
  upcoming,

  /// The lifecycle stopped before this stage (report rejected).
  blocked,
}

class ReportStage {
  /// 1-based position, shown inside the circle.
  final int step;
  final String title;
  final String description;
  final ReportStageState state;

  /// Extra lines revealed when the timeline row is expanded (e.g. who accepted
  /// it and when). Empty when there is nothing on record yet.
  final List<({String label, String value})> facts;

  const ReportStage({
    required this.step,
    required this.title,
    required this.description,
    required this.state,
    this.facts = const [],
  });

  bool get isDone => state == ReportStageState.done;
  bool get isCurrent => state == ReportStageState.current;
}

/// How far the report has travelled, as a count of COMPLETED stages (0–4).
int _completedStages(bool accepted, ReportStatus status) {
  switch (status) {
    case ReportStatus.resolved:
      return 4;
    case ReportStatus.inProgress:
      return 2;
    case ReportStatus.underReview:
      return 1;
    case ReportStatus.rejected:
    case ReportStatus.pending:
      // A rejected report keeps whatever ground it had covered; a pending one
      // has only cleared triage if an office already owns it.
      return accepted ? 1 : 0;
  }
}

/// Builds the four lifecycle stages for [r], with each one's state resolved
/// against [status] (passed separately so the dialog can reflect an optimistic
/// change before the list refetches).
List<ReportStage> buildReportStages(
  AdminReport r,
  ReportStatus status, {
  String? acceptedByName,
}) => buildReportStagesFrom(
  status: status,
  accepted: r.isAssigned || r.isEndorsed,
  isEndorsed: r.isEndorsed,
  owner: r.isEndorsed ? r.endorsedToDepartment : r.assignedToDepartment,
  acceptedAt: r.isEndorsed ? r.endorsedAt : r.assignedAt,
  acceptedByName: acceptedByName,
);

/// The same four stages from plain values rather than an [AdminReport] — the
/// staff console renders this tracker from its own [StaffReport], which carries
/// only the facts an office is allowed to see.
///
/// [accepted] is "triage has passed this on": an office owns it, by assignment
/// or by endorsement.
List<ReportStage> buildReportStagesFrom({
  required ReportStatus status,
  required bool accepted,
  bool isEndorsed = false,
  String? owner,
  DateTime? acceptedAt,
  String? acceptedByName,
}) {
  final completed = _completedStages(accepted, status);
  final rejected = status == ReportStatus.rejected;

  ReportStageState stateFor(int step) {
    if (step <= completed) return ReportStageState.done;
    if (rejected) return ReportStageState.blocked;
    if (step == completed + 1) return ReportStageState.current;
    return ReportStageState.upcoming;
  }

  return [
    ReportStage(
      step: 1,
      title: 'Report Accepted',
      description: 'The report has been reviewed and accepted.',
      state: stateFor(1),
      facts: [
        if (acceptedAt != null)
          (label: 'Accepted on', value: adminLongDateTime(acceptedAt)),
        if (acceptedByName != null)
          (label: 'Accepted by', value: acceptedByName),
        if (owner != null)
          (
            label: isEndorsed ? 'Endorsed to' : 'Assigned department',
            value: owner,
          ),
      ],
    ),
    ReportStage(
      step: 2,
      title: 'For Assessment',
      description:
          'The reported issue is now being assessed by the assigned department.',
      state: stateFor(2),
      facts: [if (owner != null) (label: 'Handled by', value: owner)],
    ),
    ReportStage(
      step: 3,
      title: 'In Progress',
      description: 'Work is now in progress to address the reported issue.',
      state: stateFor(3),
      facts: [if (owner != null) (label: 'Carried out by', value: owner)],
    ),
    ReportStage(
      step: 4,
      title: 'Resolved',
      description:
          'The issue has been resolved and the report is officially closed.',
      state: stateFor(4),
    ),
  ];
}

// ── Stepper ──────────────────────────────────────────────────────────────────

/// The numbered circles + connector rail across the top of the status pane.
///
/// Lays out as evenly-spaced columns that share the leftover width between the
/// connectors. When the viewport can't seat every column at a legible size the
/// whole rail scrolls horizontally rather than crushing the labels.
class ReportStepperRail extends StatelessWidget {
  final List<ReportStage> stages;
  const ReportStepperRail({super.key, required this.stages});

  static const double _circle = 34;
  static const double _minCol = 58;
  static const double _maxCol = 104;

  /// Shortest a connector may be drawn before the rail scrolls instead. The
  /// line has to stay long enough to read as a link between two circles, and to
  /// hold the labels apart.
  static const double _minConnector = 16;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final n = stages.length;
        // Reserve the connectors' length BEFORE sizing the columns. They are
        // part of the rail, not leftovers: sizing columns against the full
        // width lets them eat every pixel, which collapses the connectors to
        // nothing and leaves the four labels running together as one line of
        // text. Only shows up where a column lands under its max (i.e. phones).
        final forColumns = c.maxWidth - (n - 1) * _minConnector;
        final natural = forColumns / n;
        final scrolls = natural < _minCol;
        final colW = scrolls ? _minCol : natural.clamp(_minCol, _maxCol);

        final rail = Row(
          mainAxisSize: scrolls ? MainAxisSize.min : MainAxisSize.max,
          // Top-aligned, NOT centred: a step column is much taller than a
          // connector (circle + label vs. a 2px line), so centring would float
          // the connectors down to the labels instead of joining the circles.
          // With start alignment the connector's own top padding is what puts
          // it exactly on the circles' centre line.
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < n; i++) ...[
              if (i > 0)
                scrolls
                    ? _Connector.fixed(passed: stages[i - 1].isDone)
                    : Expanded(child: _Connector(passed: stages[i - 1].isDone)),
              SizedBox(
                width: colW,
                child: _StepColumn(stage: stages[i], diameter: _circle),
              ),
            ],
          ],
        );

        if (!scrolls) return rail;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: rail,
        );
      },
    );
  }
}

/// Marks each connector line, so a test can assert they sit on the circles'
/// centre line rather than drifting off it.
const Key kReportStepperConnector = Key('report-stepper-connector');

class _Connector extends StatelessWidget {
  final bool passed;
  final double? width;
  const _Connector({required this.passed}) : width = null;
  const _Connector.fixed({required this.passed}) : width = 22;

  @override
  Widget build(BuildContext context) {
    final line = Container(
      key: kReportStepperConnector,
      height: 2,
      width: width,
      color: passed ? AppColors.primaryBlue : AdminUi.border,
    );
    // Drop the line onto the circles' centre line. Relies on the rail being
    // top-aligned (see ReportStepperRail) — under centre alignment this padding
    // would be absorbed and the line would sit level with the labels.
    return Padding(
      padding: const EdgeInsets.only(
        top: ReportStepperRail._circle / 2 - 1,
        left: 2,
        right: 2,
      ),
      child: line,
    );
  }
}

class _StepColumn extends StatelessWidget {
  final ReportStage stage;
  final double diameter;
  const _StepColumn({required this.stage, required this.diameter});

  @override
  Widget build(BuildContext context) {
    final done = stage.isDone;
    final current = stage.isCurrent;
    final active = done || current;
    final blocked = stage.state == ReportStageState.blocked;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: diameter,
          height: diameter,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? AppColors.primaryBlue : AdminUi.surface,
            shape: BoxShape.circle,
            border: Border.all(
              color: active ? AppColors.primaryBlue : AdminUi.border,
              width: 1.5,
            ),
          ),
          child: done
              ? const Icon(Icons.check_rounded, size: 17, color: Colors.white)
              : Text(
                  '${stage.step}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: current
                        ? Colors.white
                        : (blocked ? AdminUi.border : AdminUi.textMuted),
                  ),
                ),
        ),
        const SizedBox(height: 7),
        Padding(
          // Keeps a gutter between neighbouring labels even at the narrowest
          // column, where two long titles would otherwise sit edge to edge.
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            stage.title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              height: 1.25,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active
                  ? AppColors.primaryBlue
                  : (blocked ? AdminUi.border : AdminUi.textMuted),
            ),
          ),
        ),
      ],
    );
  }
}

/// Names the stage a report is sitting in, in the stepper's own vocabulary.
///
/// Stage 1 gets a special case: "Report Accepted" is the name of the step, but
/// while a report is still WAITING on that step, printing its name would claim
/// the opposite of the truth.
String reportStageSummary(List<ReportStage> stages) {
  if (stages.any((s) => s.state == ReportStageState.blocked)) return 'Rejected';
  final current = stages.where((s) => s.isCurrent);
  if (current.isEmpty) return stages.last.title; // every stage done
  final at = current.first;
  return at.step == 1 ? 'Awaiting triage' : at.title;
}

/// Where a report has got to, as words, for a list row.
///
/// Deliberately text only. This started as a row of dots with the name beside
/// it, but once the stage is named the dots add nothing an admin can read at a
/// glance — four near-identical circles needed the label to be legible at all.
class ReportProgressLabel extends StatelessWidget {
  final List<ReportStage> stages;
  const ReportProgressLabel({super.key, required this.stages});

  @override
  Widget build(BuildContext context) {
    final rejected = stages.any((s) => s.state == ReportStageState.blocked);
    final started = stages.any((s) => s.isDone);
    return Text(
      reportStageSummary(stages),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        // Nothing started yet reads muted, so a queue of untouched reports
        // doesn't shout as loudly as the ones actually moving.
        color: rejected
            ? AppColors.red
            : (started ? AdminUi.textSecondary : AdminUi.textMuted),
      ),
    );
  }
}

// ── Stage card ───────────────────────────────────────────────────────────────

/// The illustrated "where this report stands" card under the stepper: a state
/// chip, a headline, and a strip of the facts behind the current stage.
class ReportStageCard extends StatelessWidget {
  final String chip;
  final String headline;
  final String blurb;
  final Color accent;
  final List<({String label, String value})> facts;
  const ReportStageCard({
    super.key,
    required this.chip,
    required this.headline,
    required this.blurb,
    required this.accent,
    this.facts = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AdminUi.cardRadius),
        border: Border.all(color: accent.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                chip,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, c) {
              final copy = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    headline,
                    style: const TextStyle(
                      fontSize: 18,
                      height: 1.25,
                      fontWeight: FontWeight.w800,
                      color: AdminUi.textPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    blurb,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: AdminUi.textSecondary,
                    ),
                  ),
                ],
              );

              // Below ~380px the illustration would squeeze the headline into a
              // ragged column, so it drops out and the copy takes the full row.
              if (c.maxWidth < 380) return copy;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: copy),
                  const SizedBox(width: 12),
                  Image.asset(
                    'assets/images/report/clipboard.webp',
                    width: (c.maxWidth * 0.22).clamp(72.0, 116.0),
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ],
              );
            },
          ),
          if (facts.isNotEmpty) ...[
            const SizedBox(height: 14),
            _FactStrip(facts: facts, accent: accent),
          ],
        ],
      ),
    );
  }
}

/// The white inset strip of label/value pairs at the foot of the stage card.
/// Lays the facts side by side when there's room and stacks them when there
/// isn't, so a long department name never gets clipped.
class _FactStrip extends StatelessWidget {
  final List<({String label, String value})> facts;
  final Color accent;
  const _FactStrip({required this.facts, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AdminUi.surface,
        borderRadius: BorderRadius.circular(AdminUi.controlRadius),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          // Each fact needs ~150px to seat a date or a department name on two
          // lines; under that the row becomes a stack.
          final side = c.maxWidth >= facts.length * 150;
          if (side) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < facts.length; i++) ...[
                  if (i > 0) const SizedBox(width: 14),
                  Expanded(child: _fact(facts[i])),
                ],
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < facts.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                _fact(facts[i]),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _fact(({String label, String value}) f) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          f.label,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
            color: AdminUi.textMuted,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          f.value,
          style: const TextStyle(
            fontSize: 12,
            height: 1.35,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryBlue,
          ),
        ),
      ],
    );
  }
}

// ── Timeline ─────────────────────────────────────────────────────────────────

/// The expandable stage list under the tabs: a numbered rail down the left with
/// one collapsible row per stage.
class ReportTimelineProgress extends StatefulWidget {
  final List<ReportStage> stages;
  const ReportTimelineProgress({super.key, required this.stages});

  @override
  State<ReportTimelineProgress> createState() => _ReportTimelineProgressState();
}

class _ReportTimelineProgressState extends State<ReportTimelineProgress> {
  /// Steps the admin has opened. The stage the report is sitting in starts open
  /// — that's the one they came here to read.
  late final Set<int> _open = {
    for (final s in widget.stages)
      if (s.isCurrent) s.step,
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < widget.stages.length; i++)
          _TimelineRow(
            stage: widget.stages[i],
            isLast: i == widget.stages.length - 1,
            expanded: _open.contains(widget.stages[i].step),
            onToggle: () => setState(() {
              final step = widget.stages[i].step;
              _open.contains(step) ? _open.remove(step) : _open.add(step);
            }),
          ),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final ReportStage stage;
  final bool isLast;
  final bool expanded;
  final VoidCallback onToggle;
  const _TimelineRow({
    required this.stage,
    required this.isLast,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final active = stage.isDone || stage.isCurrent;
    final blocked = stage.state == ReportStageState.blocked;
    final dim = blocked ? AdminUi.border : AdminUi.textMuted;

    return Stack(
      children: [
        // The thread down to the next stage, painted BEHIND the row and pinned
        // top-to-bottom. It used to be an Expanded inside an IntrinsicHeight,
        // which is what made the row overflow: collapsing a stage dropped the
        // intrinsic height to the closed size immediately, while the detail's
        // open/shut animation still occupied the old one. Positioning the line
        // instead lets the row's height be driven purely by its content.
        if (!isLast)
          Positioned(
            top: 22,
            bottom: 0,
            left: 12,
            child: Container(
              width: 2,
              color: stage.isDone ? AppColors.primaryBlue : AdminUi.border,
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The numbered marker. mainAxisSize.min keeps the rail column the
            // height of the dot, so the Stack above sizes to the content.
            SizedBox(
              width: 26,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: active ? AppColors.primaryBlue : AdminUi.surface,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: active ? AppColors.primaryBlue : AdminUi.border,
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      '${stage.step}',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: active ? Colors.white : dim,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: onToggle,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 10, right: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    stage.title,
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: active
                                          ? AdminUi.textPrimary
                                          : AdminUi.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    stage.description,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      height: 1.4,
                                      color: AdminUi.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            AnimatedRotation(
                              turns: expanded ? 0.5 : 0,
                              duration: const Duration(milliseconds: 180),
                              child: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 20,
                                color: AdminUi.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // A collapsed row builds nothing — the detail is out of the
                    // tree, not just hidden, so a closed stage costs nothing and
                    // can't be read by screen readers or found by tests.
                    AnimatedSize(
                      alignment: Alignment.topCenter,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      child: expanded
                          ? _detail()
                          : const SizedBox(width: double.infinity),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _detail() {
    final status = switch (stage.state) {
      ReportStageState.done => 'Completed',
      ReportStageState.current => 'In progress',
      ReportStageState.upcoming => 'Not started yet',
      ReportStageState.blocked => 'Not reached — the report was rejected',
    };
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12, right: 2),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AdminUi.subtle,
        borderRadius: BorderRadius.circular(AdminUi.controlRadius),
        border: Border.all(color: AdminUi.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                switch (stage.state) {
                  ReportStageState.done => Icons.check_circle_rounded,
                  ReportStageState.current => Icons.timelapse_rounded,
                  ReportStageState.upcoming => Icons.schedule_rounded,
                  ReportStageState.blocked => Icons.block_rounded,
                },
                size: 14,
                color: switch (stage.state) {
                  ReportStageState.done => AppColors.green,
                  ReportStageState.current => AppColors.primaryBlue,
                  ReportStageState.upcoming => AdminUi.textMuted,
                  ReportStageState.blocked => AppColors.red,
                },
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  status,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AdminUi.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          for (final f in stage.facts) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 116,
                  child: Text(
                    f.label,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AdminUi.textMuted,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    f.value,
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: AdminUi.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
