import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/deeplink_highlight.dart';
import '../../../core/widgets/report_work_log.dart';
import '../../../core/widgets/resolution_media.dart';
import '../../staff/data/staff_departments.dart';
import '../theme/admin_ui.dart';
import '../providers/admin_reports_provider.dart';
import '../utils/report_pdf.dart';
import '../widgets/accept_assign_dialog.dart';
import '../widgets/admin_detail_screen.dart';
import '../widgets/endorse_entity_dialog.dart';
import '../widgets/endorsement_success_dialog.dart';
import '../widgets/admin_moderation.dart';
import '../providers/admin_identity_reveal_provider.dart';
import '../widgets/admin_submission_ui.dart';
import '../widgets/report_detail_kit.dart';
import '../widgets/report_status_tracker.dart';
import '../widgets/revealable_submitter.dart';
import '../widgets/admin_snackbar.dart';
import '../../../core/widgets/app_dialog.dart';

// The category visuals, the detail panes, the attachment grid and its viewers
// all live in report_detail_kit.dart — the staff console shows the same report
// from the office's side and renders it with the same pieces.

Color _statusColor(ReportStatus s) {
  switch (s) {
    case ReportStatus.pending:
      return AppColors.orange;
    case ReportStatus.underReview:
    case ReportStatus.inProgress:
      return AppColors.primaryBlue;
    case ReportStatus.resolved:
      return AppColors.green;
    case ReportStatus.rejected:
      return AppColors.red;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Page
// ═════════════════════════════════════════════════════════════════════════════

class AdminReportsPage extends ConsumerStatefulWidget {
  /// A report id to scroll to and flash once, when arriving from an insight row
  /// or a notification. Null for a normal open.
  final String? highlightId;
  const AdminReportsPage({super.key, this.highlightId});

  @override
  ConsumerState<AdminReportsPage> createState() => _AdminReportsPageState();
}

class _AdminReportsPageState extends ConsumerState<AdminReportsPage>
    with DeepLinkHighlightMixin {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(adminReportsProvider.notifier).setQuery(value);
    });
  }

  /// Only counts what the sheet still owns — the buckets moved out to the tabs,
  /// where they're visible without opening anything.
  int _activeFilterCount(ReportFilters f) {
    var n = 0;
    if (f.status != null) n++;
    if (f.sort != ReportSort.newest) n++;
    if (f.anonymousOnly) n++;
    return n;
  }

  void _openFilters() {
    final notifier = ref.read(adminReportsProvider.notifier);
    openAdminFilterSheet(
      context,
      title: 'Filter reports',
      onReset: () {
        notifier.setStatus(null);
        notifier.setSort(ReportSort.newest);
        if (notifier.filters.anonymousOnly) notifier.toggleAnonymousOnly();
      },
      content: Consumer(
        builder: (context, ref, _) {
          ref.watch(adminReportsProvider);
          final f = ref.read(adminReportsProvider.notifier).filters;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FilterChoiceRow<ReportStatus>(
                label: 'Status',
                value: f.status,
                options: [
                  (value: null, text: 'All'),
                  for (final s in ReportStatus.values)
                    (value: s, text: reportStatusLabel(s)),
                ],
                onSelected: (v) => notifier.setStatus(v),
              ),
              const SizedBox(height: 18),
              FilterChoiceRow<ReportSort>(
                label: 'Sort',
                value: f.sort,
                options: const [
                  (value: ReportSort.newest, text: 'Newest'),
                  (value: ReportSort.oldest, text: 'Oldest'),
                ],
                onSelected: (v) {
                  if (v != null) notifier.setSort(v);
                },
              ),
              const SizedBox(height: 18),
              FilterSwitchRow(
                icon: Icons.visibility_off_rounded,
                label: 'Anonymous only',
                subtitle: 'Show only reports with a withheld identity',
                value: f.anonymousOnly,
                onChanged: (_) => notifier.toggleAnonymousOnly(),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openDetail(AdminReport r) async {
    await showAdminDetail(
      context,
      builder: (_) => _ReportDetailDialog(report: r),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(adminReportsProvider);
    final notifier = ref.read(adminReportsProvider.notifier);
    final filters = notifier.filters;
    final pad = MediaQuery.of(context).size.width < 600 ? 16.0 : 24.0;

    // Rows exist only once the fetch resolves — flash the deep-link target then.
    if (async.hasValue) flashHighlightOnce(widget.highlightId);

    return RefreshIndicator(
      onRefresh: () => ref.read(adminReportsProvider.notifier).refresh(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(pad, pad, pad, pad + 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Header(async: async, notifier: notifier),
                const SizedBox(height: 14),
                // Buckets first: they answer "which pile am I looking at",
                // which the search and filters then narrow.
                _BucketTabs(
                  async: async,
                  current: filters.bucket,
                  notifier: notifier,
                ),
                const SizedBox(height: 12),
                _Toolbar(
                  searchCtrl: _searchCtrl,
                  activeCount: _activeFilterCount(filters),
                  onSearch: _onSearchChanged,
                  onClearSearch: () {
                    _searchCtrl.clear();
                    notifier.setQuery('');
                    setState(() {});
                  },
                  onOpenFilters: _openFilters,
                ),
                _ActiveChips(filters: filters, notifier: notifier),
                const SizedBox(height: 14),
                _Results(
                  async: async,
                  bucket: filters.bucket,
                  onOpen: _openDetail,
                  onRetry: () =>
                      ref.read(adminReportsProvider.notifier).refresh(),
                  keyFor: highlightKey,
                  isHighlighted: isHighlighted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final AsyncValue<List<AdminReport>> async;
  final AdminReportsNotifier notifier;
  const _Header({required this.async, required this.notifier});

  @override
  Widget build(BuildContext context) {
    if (async.valueOrNull == null) {
      return const Text(
        'Citizen-submitted issue reports',
        style: TextStyle(fontSize: 13, color: AdminUi.textMuted),
      );
    }
    final total = notifier.totalCount;
    final anon = notifier.anonymousCount;
    final highAnon = total > 0 && anon / total > 0.30;
    // Needs-triage has its own tab (with a count) — no header pill for it.
    // Overdue cuts across the buckets, so it stays here.
    final overdue = notifier.overdueCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The top bar already shows "Reports", so no in-content page title.
        Row(
          children: [
            Text(
              '$total report${total == 1 ? '' : 's'}',
              style: const TextStyle(fontSize: 13, color: AdminUi.textMuted),
            ),
            const Text('  ·  ', style: TextStyle(color: AdminUi.textMuted)),
            Icon(
              Icons.visibility_off_rounded,
              size: 13,
              color: highAnon ? AppColors.orange : kAnonColor,
            ),
            const SizedBox(width: 3),
            Text(
              '$anon anonymous',
              style: TextStyle(
                fontSize: 13,
                color: highAnon ? AppColors.orange : kAnonColor,
                fontWeight: highAnon ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
        if (overdue > 0) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HeaderStat(
                icon: Icons.schedule_rounded,
                label: '$overdue overdue',
                color: AppColors.orange,
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Small tappable stat pill under the reports header (needs-triage / overdue).
class _HeaderStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _HeaderStat({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Toolbar ─────────────────────────────────────────────────────────────────

class _Toolbar extends StatelessWidget {
  final TextEditingController searchCtrl;
  final int activeCount;
  final ValueChanged<String> onSearch;
  final VoidCallback onClearSearch;
  final VoidCallback onOpenFilters;
  const _Toolbar({
    required this.searchCtrl,
    required this.activeCount,
    required this.onSearch,
    required this.onClearSearch,
    required this.onOpenFilters,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final searchWidth = c.maxWidth < 480 ? c.maxWidth - 128 : 320.0;
        return Row(
          children: [
            SizedBox(
              width: searchWidth.clamp(140.0, 360.0),
              child: AdminSearchField(
                controller: searchCtrl,
                hint: 'Search barangay, address, remarks…',
                onChanged: onSearch,
                onClear: onClearSearch,
              ),
            ),
            const SizedBox(width: 10),
            FilterButton(activeCount: activeCount, onTap: onOpenFilters),
          ],
        );
      },
    );
  }
}

// ── Bucket tabs ──────────────────────────────────────────────────────────────

/// The queue's primary navigation: one tab per pile, each carrying its count.
/// These replaced three switches buried in the Filters sheet — an admin should
/// be able to see how much is waiting on them without opening anything.
class _BucketTabs extends StatelessWidget {
  final AsyncValue<List<AdminReport>> async;
  final ReportBucket current;
  final AdminReportsNotifier notifier;
  const _BucketTabs({
    required this.async,
    required this.current,
    required this.notifier,
  });

  static const _order = ReportBucket.values;

  @override
  Widget build(BuildContext context) {
    // Counts are meaningless until the fetch lands; show the tabs bare rather
    // than a row of confident zeros that then change.
    final loaded = async.hasValue;
    // A pill rail, not underline tabs: the buckets are this queue's primary
    // navigation and deserve a control that stands apart from the Filters
    // button beside it. The active pile fills solid blue; chips size to their
    // labels and scroll (with edge fades + auto-scroll) when they run out of
    // room, so nothing stretches on a desktop or hides on a phone.
    return AdminPillTabs(
      labels: [for (final b in _order) reportBucketLabel(b)],
      counts: loaded ? [for (final b in _order) notifier.bucketCount(b)] : null,
      selected: _order.indexOf(current),
      onSelect: (i) => notifier.setBucket(_order[i]),
    );
  }
}

// ── Active chips ──────────────────────────────────────────────────────────────

class _ActiveChips extends StatelessWidget {
  final ReportFilters filters;
  final AdminReportsNotifier notifier;
  const _ActiveChips({required this.filters, required this.notifier});

  @override
  Widget build(BuildContext context) {
    // No bucket chip: the tab above already shows which pile is on screen, and
    // a chip that removes it would just be a second, quieter way to press All.
    final chips = <Widget>[
      if (filters.status != null)
        ActiveChip(
          label: reportStatusLabel(filters.status!),
          onRemove: () => notifier.setStatus(null),
        ),
      if (filters.sort != ReportSort.newest)
        ActiveChip(
          label: 'Oldest first',
          onRemove: () => notifier.setSort(ReportSort.newest),
        ),
      if (filters.anonymousOnly)
        ActiveChip(
          label: 'Anonymous only',
          emphasize: true,
          onRemove: () => notifier.toggleAnonymousOnly(),
        ),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(spacing: 8, runSpacing: 8, children: chips),
    );
  }
}

// ── Results ───────────────────────────────────────────────────────────────────

class _Results extends StatelessWidget {
  final AsyncValue<List<AdminReport>> async;
  final ReportBucket bucket;
  final void Function(AdminReport) onOpen;
  final VoidCallback onRetry;

  /// Deep-link plumbing: the page owns the highlight state (via
  /// [DeepLinkHighlightMixin]) and hands down a key + flag per row.
  final GlobalKey Function(String id) keyFor;
  final bool Function(String id) isHighlighted;
  const _Results({
    required this.async,
    required this.bucket,
    required this.onOpen,
    required this.onRetry,
    required this.keyFor,
    required this.isHighlighted,
  });

  /// An empty bucket usually isn't a problem — it's the goal. Say which, so a
  /// cleared triage desk doesn't read like a broken filter.
  ({IconData icon, Color color, String text}) get _emptyState {
    switch (bucket) {
      case ReportBucket.needsTriage:
        return (
          icon: Icons.task_alt_rounded,
          color: AppColors.green,
          text: 'Triage desk is clear — nothing waiting on you.',
        );
      case ReportBucket.working:
        return (
          icon: Icons.engineering_rounded,
          color: AdminUi.textMuted,
          text: 'No reports are being worked right now.',
        );
      case ReportBucket.resolved:
        return (
          icon: Icons.verified_rounded,
          color: AdminUi.textMuted,
          text: 'Nothing has been resolved yet.',
        );
      case ReportBucket.endorsed:
        return (
          icon: Icons.forward_to_inbox_rounded,
          color: AdminUi.textMuted,
          text: 'No reports have been endorsed to an external entity.',
        );
      case ReportBucket.dismissed:
        return (
          icon: Icons.block_rounded,
          color: AdminUi.textMuted,
          text: 'No reports have been dismissed as spam.',
        );
      case ReportBucket.all:
        return (
          icon: Icons.inbox_rounded,
          color: AdminUi.textMuted,
          text: 'No reports match your filters.',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminResultsCard(
      child: async.when(
        loading: () => const AdminListSkeleton(),
        error: (e, _) => AdminResultsMessage(
          icon: Icons.cloud_off_rounded,
          color: AppColors.red,
          text: 'Couldn\'t load reports.',
          action: TextButton(onPressed: onRetry, child: const Text('Retry')),
        ),
        data: (items) {
          if (items.isEmpty) {
            final e = _emptyState;
            return AdminResultsMessage(
              icon: e.icon,
              color: e.color,
              text: e.text,
            );
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= kReportTableFrom) {
                return Column(
                  children: [
                    const _TableHeader(),
                    for (final r in items)
                      _TableRow(
                        key: keyFor(r.id),
                        report: r,
                        onOpen: () => onOpen(r),
                        highlighted: isHighlighted(r.id),
                      ),
                  ],
                );
              }
              return Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    for (final r in items)
                      _Card(
                        key: keyFor(r.id),
                        report: r,
                        onOpen: () => onOpen(r),
                        highlighted: isHighlighted(r.id),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ── Wide table ──────────────────────────────────────────────────────────────────

/// Column widths for the wide table, in one place.
///
/// The header and the rows are separate widgets that must lay out identically —
/// keeping two copies of these numbers in sync by hand is exactly how PROGRESS
/// once ended up flex 3 in the header and flex 2 in the rows, dragging every
/// column to its right out of alignment with its own heading.
abstract final class _Col {
  static const int category = 4;
  static const int submitter = 3;
  static const int barangay = 2;
  static const int progress = 2;

  /// Wider than its neighbours on purpose: this cell seats a status pill AND
  /// up to two flag chips beside it, and it has to do that on ONE line.
  static const int status = 3;
  static const int date = 2;

  /// Fixed, not flexed: just an icon and a count.
  static const double media = 30;
}

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: AdminUi.subtle,
        border: Border(bottom: BorderSide(color: AdminUi.border)),
      ),
      child: Row(
        children: const [
          _HCell('CATEGORY', flex: _Col.category),
          _HCell('SUBMITTER', flex: _Col.submitter),
          _HCell('BARANGAY', flex: _Col.barangay),
          _HCell('PROGRESS', flex: _Col.progress),
          _HCell('STATUS', flex: _Col.status),
          _HCell('DATE', flex: _Col.date),
          SizedBox(width: _Col.media),
        ],
      ),
    );
  }
}

class _HCell extends StatelessWidget {
  final String text;
  final int flex;
  const _HCell(this.text, {this.flex = 1});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: AdminUi.textMuted,
        ),
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  final AdminReport report;
  final VoidCallback onOpen;

  /// Set when this row is the deep-link target: it flashes, then fades back.
  final bool highlighted;
  const _TableRow({
    super.key,
    required this.report,
    required this.onOpen,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final r = report;
    return InkWell(
      onTap: onOpen,
      child: AnimatedContainer(
        duration: kHighlightFade,
        decoration: highlighted
            ? highlightRowDecoration(
                accent: AppColors.primaryBlue,
                divider: const BorderSide(color: AdminUi.border),
              )
            : BoxDecoration(
                color: r.isAnonymous
                    ? kAnonColor.withValues(alpha: 0.035)
                    : null,
                border: const Border(bottom: BorderSide(color: AdminUi.border)),
              ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              flex: _Col.category,
              child: Row(
                children: [
                  ReportCategoryIconBox(r.categoryKey, size: 30),
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
                            fontWeight: FontWeight.w600,
                            color: AdminUi.textPrimary,
                          ),
                        ),
                        Text(
                          r.shortId,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AdminUi.textMuted,
                          ),
                        ),
                        if (r.isEndorsed) ...[
                          const SizedBox(height: 4),
                          _EndorsedBadge(r.endorsedToDepartment!),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: _Col.submitter,
              child: SubmitterInline(
                isAnonymous: r.isAnonymous,
                name: r.submitterName,
                role: r.submitterRole,
              ),
            ),
            Expanded(
              flex: _Col.barangay,
              child: Text(
                (r.barangay == null || r.barangay!.isEmpty) ? '—' : r.barangay!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: AdminUi.textMuted),
              ),
            ),
            Expanded(
              flex: _Col.progress,
              child: ReportProgressLabel(
                stages: buildReportStages(r, r.status),
              ),
            ),
            Expanded(flex: _Col.status, child: _StatusCell(r)),
            Expanded(
              flex: _Col.date,
              child: Text(
                adminShortDate(r.createdAt),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AdminUi.textMuted),
              ),
            ),
            SizedBox(width: _Col.media, child: _MediaCount(r.mediaCount)),
          ],
        ),
      ),
    );
  }
}

/// The STATUS column of one table row: the status pill, plus the overdue and
/// corroboration flags when they apply.
///
/// Lays out on ONE line, always. This was a [Wrap], which is what made the
/// column ragged: a wide status ("In progress") pushed the overdue chip onto a
/// second line while its neighbours ("Pending") kept theirs on the first, so
/// rows in the same table stood at different heights and the pills stopped
/// lining up — the one thing a column of pills exists to do.
///
/// Instead the secondary chips give up their labels as the column narrows
/// (see [ChipDensity]) and the pill itself flexes last. The meaning survives
/// in the colour, the icon, and the tooltip.
class _StatusCell extends StatelessWidget {
  final AdminReport report;
  const _StatusCell(this.report);

  @override
  Widget build(BuildContext context) {
    final r = report;
    return LayoutBuilder(
      builder: (context, c) {
        // Measured against the widest pill this column has to seat ("Under
        // review", ~85px) plus the 6px gap: the full chip needs ~100 more, the
        // number-only form ~52, the glyph alone ~26.
        final density = c.maxWidth >= 195
            ? ChipDensity.full
            : (c.maxWidth >= 145 ? ChipDensity.compact : ChipDensity.icon);
        return Row(
          children: [
            // Flexible, so an extreme squeeze ellipsizes the label rather than
            // overflowing the cell.
            Flexible(
              child: StatusPill(
                label: reportStatusLabel(r.status),
                color: _statusColor(r.status),
              ),
            ),
            if (r.isOverdue) ...[
              const SizedBox(width: 6),
              DetailOverdueChip(r.ageDays, density: density),
            ],
            if (r.isCorroborated) ...[
              const SizedBox(width: 6),
              _ConfirmedChip(r.reporterCount, density: density),
            ],
          ],
        );
      },
    );
  }
}

/// Small pill flagging that a report has been endorsed out to an external
/// entity — so an admin scanning the list instantly sees it's no longer theirs.
class _EndorsedBadge extends StatelessWidget {
  final String entity;
  const _EndorsedBadge(this.entity);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: AppColors.primaryBlue.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.forward_to_inbox_rounded,
            size: 11,
            color: AppColors.primaryBlue,
          ),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              'Endorsed · $entity',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryBlue,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Reject a report with a free-text reason the CITIZEN will see. Distinct from
/// [showAdminDismissDialog] (spam soft-hide) — this is a legitimate closure with
/// a citizen-facing explanation and a notification. Returns the note, or null.
Future<String?> showRejectReportDialog(BuildContext context) {
  return showAppDialog<String>(
    context: context,
    barrierColor: Colors.black54,
    builder: (_) => const _RejectReasonDialog(),
  );
}

/// A canned rejection reason. The blurb is what an ADMIN reads while choosing;
/// [title] is what gets sent to the citizen, so it has to stand on its own in
/// "Your road report was reviewed and closed. <title>".
class _RejectPreset {
  final String title;
  final String blurb;
  final String asset;
  const _RejectPreset(this.title, this.blurb, this.asset);
}

const List<_RejectPreset> _kRejectPresets = [
  _RejectPreset(
    'Duplicate of an existing report',
    'This report has already been submitted.',
    'assets/images/report/copy (1).webp',
  ),
  _RejectPreset(
    'Not enough information to act',
    'There isn\'t enough detail to take action.',
    'assets/images/report/information (3).webp',
  ),
  _RejectPreset(
    'Not actionable by the LGU',
    'This issue is outside the scope of our jurisdiction.',
    'assets/images/report/map (1).webp',
  ),
  _RejectPreset(
    'Could not be verified',
    'The information provided could not be verified.',
    'assets/images/report/shield (1).webp',
  ),
];

class _RejectReasonDialog extends StatefulWidget {
  const _RejectReasonDialog();

  @override
  State<_RejectReasonDialog> createState() => _RejectReasonDialogState();
}

class _RejectReasonDialogState extends State<_RejectReasonDialog> {
  final _ctrl = TextEditingController();
  int? _selected;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// The citizen must always be told SOMETHING, so a preset or free text is
  /// required — "(optional)" on the cards means you may type instead of picking
  /// one, not that a report can be closed with no explanation at all.
  bool get _canSubmit => _selected != null || _ctrl.text.trim().isNotEmpty;

  /// Free text wins when both are given: the admin went out of their way.
  String get _reason {
    final typed = _ctrl.text.trim();
    if (typed.isNotEmpty) return typed;
    return _kRejectPresets[_selected!].title;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AdminUi.surface,
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        // Wide enough to seat four reason cards; the Dialog itself keeps this
        // inside the viewport (and above the keyboard) on a phone.
        constraints: const BoxConstraints(maxWidth: 840, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(),
            const Divider(height: 1, color: AdminUi.border),
            // Only the middle scrolls, so the actions stay reachable and the
            // heading stays put while picking a reason.
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _FieldLabel('Select a reason (optional)'),
                    const SizedBox(height: 10),
                    _presetGrid(),
                    const SizedBox(height: 18),
                    const _FieldLabel('Or provide another reason'),
                    const SizedBox(height: 10),
                    _reasonField(),
                    const SizedBox(height: 8),
                    _fieldFooter(),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: AdminUi.border),
            _actions(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 54,
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.red.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Image.asset(
              'assets/images/report/exclamation (1).webp',
              width: 28,
              height: 28,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Reject this report?',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AdminUi.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 5),
                // The consequence, spelled out: this closes the report AND
                // notifies a real person, and there's no undo from here.
                Text.rich(
                  const TextSpan(
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: AdminUi.textSecondary,
                    ),
                    children: [
                      TextSpan(
                        text:
                            'The report will be closed and the citizen will '
                            'be notified. This action ',
                      ),
                      TextSpan(
                        text: 'cannot be undone',
                        style: TextStyle(
                          color: AppColors.red,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextSpan(text: '.'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
            color: AdminUi.textMuted,
            tooltip: 'Cancel',
          ),
        ],
      ),
    );
  }

  /// Reason cards. Four across on a desktop, two on a tablet, and one per row
  /// on a phone — where they flip to a horizontal layout, since a full-width
  /// card with a centred icon over centred text just wastes height.
  Widget _presetGrid() {
    return LayoutBuilder(
      builder: (context, c) {
        final columns = c.maxWidth >= 640
            ? 4
            : c.maxWidth >= 380
            ? 2
            : 1;
        const gap = 12.0;

        final rows = <Widget>[];
        for (var i = 0; i < _kRejectPresets.length; i += columns) {
          if (rows.isNotEmpty) rows.add(const SizedBox(height: gap));

          final end = (i + columns).clamp(0, _kRejectPresets.length);
          final rowItems = <Widget>[];
          for (var j = i; j < end; j++) {
            if (j > i) rowItems.add(const SizedBox(width: gap));
            rowItems.add(
              Expanded(
                child: _PresetCard(
                  preset: _kRejectPresets[j],
                  selected: _selected == j,
                  horizontal: columns == 1,
                  // Tapping the chosen one again clears it — otherwise there'd
                  // be no way back to "no preset, my own words".
                  onTap: () =>
                      setState(() => _selected = _selected == j ? null : j),
                ),
              ),
            );
          }

          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: rowItems,
              ),
            ),
          );
        }

        return Column(children: rows);
      },
    );
  }

  Widget _reasonField() {
    return TextField(
      controller: _ctrl,
      maxLines: 3,
      minLines: 3,
      maxLength: 300,
      onChanged: (_) => setState(() {}),
      style: const TextStyle(fontSize: 14, color: AdminUi.textPrimary),
      decoration: InputDecoration(
        hintText: 'Enter reason the citizen will see…',
        hintStyle: const TextStyle(color: AdminUi.textMuted),
        counterText: '', // shown in the footer instead
        filled: true,
        fillColor: AdminUi.surface,
        contentPadding: const EdgeInsets.all(14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AdminUi.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AdminUi.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: AppColors.primaryBlue,
            width: 1.6,
          ),
        ),
      ),
    );
  }

  Widget _fieldFooter() {
    final note = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.info_outline_rounded,
          size: 14,
          color: AdminUi.textMuted,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            'The citizen will see this reason in their notification.',
            style: const TextStyle(fontSize: 12, color: AdminUi.textMuted),
          ),
        ),
      ],
    );
    final counter = Text(
      '${_ctrl.text.characters.length}/300',
      style: const TextStyle(fontSize: 12, color: AdminUi.textMuted),
    );

    return LayoutBuilder(
      builder: (context, c) {
        // Side by side while both fit; the counter drops under the note rather
        // than squeezing it into an ellipsis on a phone.
        if (c.maxWidth < 380) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [note, const SizedBox(height: 6), counter],
          );
        }
        return Row(
          children: [
            Expanded(child: note),
            const SizedBox(width: 10),
            counter,
          ],
        );
      },
    );
  }

  Widget _actions() {
    final cancel = OutlinedButton(
      onPressed: () => Navigator.pop(context),
      style: OutlinedButton.styleFrom(
        foregroundColor: AdminUi.textSecondary,
        side: const BorderSide(color: AdminUi.border),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AdminUi.controlRadius),
        ),
      ),
      child: const Text(
        'Cancel',
        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
      ),
    );

    final reject = FilledButton.icon(
      onPressed: _canSubmit ? () => Navigator.pop(context, _reason) : null,
      icon: const Icon(Icons.send_rounded, size: 17),
      label: const Text(
        'Reject & notify citizen',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.red,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AdminUi.controlRadius),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      child: LayoutBuilder(
        builder: (context, c) {
          // Stacked full-width on a phone, where the two side by side would
          // ellipse "Reject & notify citizen" down to nothing.
          if (c.maxWidth < 420) {
            return Column(
              children: [
                SizedBox(width: double.infinity, child: reject),
                const SizedBox(height: 10),
                SizedBox(width: double.infinity, child: cancel),
              ],
            );
          }
          return Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [cancel, const SizedBox(width: 10), reject],
          );
        },
      ),
    );
  }
}

/// Small bold label above a field in the reject dialog.
class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AdminUi.textPrimary,
      ),
    );
  }
}

/// One selectable rejection reason.
class _PresetCard extends StatelessWidget {
  final _RejectPreset preset;
  final bool selected;

  /// Icon beside the text instead of above it — for the one-per-row phone
  /// layout, where a centred column would run tall and mostly empty.
  final bool horizontal;
  final VoidCallback onTap;
  const _PresetCard({
    required this.preset,
    required this.selected,
    required this.horizontal,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final title = Text(
      preset.title,
      textAlign: horizontal ? TextAlign.start : TextAlign.center,
      style: const TextStyle(
        fontSize: 13,
        height: 1.3,
        fontWeight: FontWeight.w700,
        color: AdminUi.textPrimary,
      ),
    );
    final blurb = Text(
      preset.blurb,
      textAlign: horizontal ? TextAlign.start : TextAlign.center,
      style: const TextStyle(
        fontSize: 11.5,
        height: 1.35,
        color: AdminUi.textMuted,
      ),
    );

    return Material(
      color: selected
          ? AppColors.primaryBlue.withValues(alpha: 0.04)
          : AdminUi.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Container(
              width: double.infinity,
              height: double.infinity,
              padding: EdgeInsets.fromLTRB(14, 14, horizontal ? 34 : 14, 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? AppColors.primaryBlue : AdminUi.border,
                  width: selected ? 1.6 : 1,
                ),
              ),
              child: horizontal
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _icon(),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [title, const SizedBox(height: 4), blurb],
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _icon(),
                        const SizedBox(height: 10),
                        title,
                        const SizedBox(height: 6),
                        blurb,
                      ],
                    ),
            ),
            if (selected)
              const Positioned(
                top: 8,
                right: 8,
                child: Icon(
                  Icons.check_circle_rounded,
                  size: 19,
                  color: AppColors.primaryBlue,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _icon() => SizedBox(
    width: 42,
    height: 42,
    child: Image.asset(preset.asset, fit: BoxFit.contain),
  );
}

/// "N reports" — this issue was independently reported by more than one citizen.
///
/// Deliberately blue, not orange: corroboration is a PRIORITY signal, not a
/// problem. Five people reporting one pothole means it's a bad pothole, and this
/// chip is what makes that visible next to AI urgency.
class _ConfirmedChip extends StatelessWidget {
  final int reporterCount;
  final ChipDensity density;
  const _ConfirmedChip(this.reporterCount, {this.density = ChipDensity.full});

  @override
  Widget build(BuildContext context) {
    final label = switch (density) {
      ChipDensity.full => '$reporterCount reports',
      ChipDensity.compact => '$reporterCount',
      ChipDensity.icon => null,
    };
    return Tooltip(
      message: '$reporterCount citizens reported this issue',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: label == null ? 4 : 7,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: AppColors.primaryBlue.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: AppColors.primaryBlue.withValues(alpha: 0.30),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.groups_rounded,
              size: 11,
              color: AppColors.primaryBlue,
            ),
            if (label != null) ...[
              const SizedBox(width: 3),
              Text(
                label,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryBlue,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MediaCount extends StatelessWidget {
  final int count;
  const _MediaCount(this.count);

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox(width: 30);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.image_outlined, size: 15, color: AdminUi.textMuted),
        const SizedBox(width: 2),
        Text(
          '$count',
          style: const TextStyle(fontSize: 11, color: AdminUi.textMuted),
        ),
      ],
    );
  }
}

// ── Narrow card ────────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final AdminReport report;
  final VoidCallback onOpen;
  final bool highlighted;
  const _Card({
    super.key,
    required this.report,
    required this.onOpen,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final r = report;
    return SubmissionListCard(
      isAnonymous: r.isAnonymous,
      onTap: onOpen,
      highlighted: highlighted,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ReportCategoryIconBox(r.categoryKey, size: 38),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  r.category,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AdminUi.textPrimary,
                  ),
                ),
              ),
              StatusPill(
                label: reportStatusLabel(r.status),
                color: _statusColor(r.status),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SubmitterInline(
            isAnonymous: r.isAnonymous,
            name: r.submitterName,
            role: r.submitterRole,
          ),
          const SizedBox(height: 8),
          ReportProgressLabel(stages: buildReportStages(r, r.status)),
          if (r.isEndorsed || r.isOverdue || r.isCorroborated) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (r.isEndorsed) _EndorsedBadge(r.endorsedToDepartment!),
                if (r.isOverdue) DetailOverdueChip(r.ageDays),
                if (r.isCorroborated) _ConfirmedChip(r.reporterCount),
              ],
            ),
          ],
          if (r.remarks.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              r.remarks,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: AdminUi.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            [
              r.shortId,
              if (r.barangay != null && r.barangay!.isNotEmpty) r.barangay!,
              adminShortDate(r.createdAt),
              if (r.mediaCount > 0)
                '${r.mediaCount} file${r.mediaCount == 1 ? '' : 's'}',
            ].join('  ·  '),
            style: const TextStyle(fontSize: 11.5, color: AdminUi.textMuted),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Detail dialog
// ═════════════════════════════════════════════════════════════════════════════

class _ReportDetailDialog extends ConsumerStatefulWidget {
  final AdminReport report;
  const _ReportDetailDialog({required this.report});

  @override
  ConsumerState<_ReportDetailDialog> createState() =>
      _ReportDetailDialogState();
}

class _ReportDetailDialogState extends ConsumerState<_ReportDetailDialog> {
  late ReportStatus _status;

  /// The report's attachments, mapped into the kit's neutral item so the hero
  /// thumb and the gallery are the same widgets the staff console uses.
  late Future<List<DetailMediaItem>> _mediaFuture;

  /// Open reports that might be the same issue. Loaded once alongside the media
  /// so the pane doesn't refetch on every rebuild.
  late Future<List<DuplicateCandidate>> _dupFuture;

  bool _busy = false;

  /// Which tab of the status pane is showing: 0 = Timeline, 1 = Report History.
  int _trackerTab = 0;

  /// Which PANE is showing, when the layout is too narrow to seat both side by
  /// side: 0 = Report Details, 1 = Update Report Status. Stacking the two into
  /// one column made a phone scroll through both; the tabs keep each to about a
  /// screen, the same trick the dashboard uses.
  int _paneTab = 0;

  /// The report as it stands NOW.
  ///
  /// The dialog opens on a snapshot from the list, but it also STAYS OPEN across
  /// the actions taken here — reject, reopen, restore — each of which rewrites
  /// the row. Rendering from the snapshot would leave the panes describing the
  /// report as it was before the tap (no rejection reason, still assigned), so
  /// every render path reads through this instead. Falls back to the snapshot
  /// only if the row has left the store entirely.
  AdminReport get report =>
      ref.read(adminReportsProvider.notifier).byId(widget.report.id) ??
      widget.report;

  @override
  void initState() {
    super.initState();
    _status = widget.report.status;
    _mediaFuture = ref
        .read(adminReportsProvider.notifier)
        .fetchMedia(widget.report.id)
        .then(
          (media) => [
            for (final m in media)
              DetailMediaItem(
                url: m.url,
                isVideo: m.isVideo,
                isGpsVerified: m.isGpsVerified,
                aiScore: m.aiScore,
                aiStatus: m.aiStatus,
              ),
          ],
        );
    // Only worth asking on the triage desk: that's where a duplicate should be
    // caught, before an office starts work on a twin of a job it already has.
    _dupFuture = widget.report.needsTriage && !widget.report.isDismissed
        ? ref
              .read(adminReportsProvider.notifier)
              .fetchDuplicateCandidates(widget.report.id)
        : Future.value(const []);
  }

  /// Links this report to [c] as a confirmation of the same issue. Asks first —
  /// a merge takes a report off the queue, so it should never be one stray tap.
  Future<void> _merge(DuplicateCandidate c) async {
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Same issue?',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        content: Text(
          'RPT-${widget.report.shortId} will be linked to RPT-${c.shortRef} as a '
          'confirmation and will leave the queue. The citizen keeps their report '
          'and is told it matched an existing one — nothing is deleted, and you '
          'can undo this from their report.',
          style: const TextStyle(
            fontSize: 13,
            height: 1.5,
            color: AdminUi.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Link as duplicate'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(adminReportsProvider.notifier)
          .merge(widget.report.id, c.id);
      if (!mounted) return;
      Navigator.pop(context);
      showAdminSnackBar(
        context,
        'Linked to RPT-${c.shortRef} — the citizen was notified.',
        type: AdminSnackType.success,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAdminSnackBar(
        context,
        'Could not link: $e',
        type: AdminSnackType.error,
      );
    }
  }

  Future<void> _dismiss() async {
    final reason = await showAdminDismissDialog(context, itemLabel: 'report');
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(adminReportsProvider.notifier)
          .dismiss(widget.report.id, reason);
      if (!mounted) return;
      Navigator.pop(context);
      showAdminSnackBar(
        context,
        'Report dismissed — hidden from analytics.',
        type: AdminSnackType.success,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAdminSnackBar(
        context,
        'Could not dismiss: $e',
        type: AdminSnackType.error,
      );
    }
  }

  /// Undo a dismissal. Like [_reopen], this brings the report back rather than
  /// finishing with it, so the dialog stays open and re-renders as the ordinary
  /// report — the dismissed banner gone, its actions returned.
  Future<void> _restore() async {
    setState(() => _busy = true);
    try {
      await ref.read(adminReportsProvider.notifier).restore(widget.report.id);
      if (!mounted) return;
      setState(() => _busy = false);
      showAdminSnackBar(
        context,
        'Report restored.',
        type: AdminSnackType.success,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAdminSnackBar(
        context,
        'Could not restore: $e',
        type: AdminSnackType.error,
      );
    }
  }

  /// Endorses this report to an external entity (out-of-LGU-scope). The report
  /// then lands in that entity's staff-console inbox, and the server mints the
  /// token + PIN that back the printed endorsement letter.
  Future<void> _endorse() async {
    final picked = await showEndorseEntityDialog(
      context,
      currentEndorsement: widget.report.endorsedToDepartment,
    );
    if (picked == null || !mounted) return;

    setState(() => _busy = true);
    try {
      if (picked.isClear) {
        await ref
            .read(adminReportsProvider.notifier)
            .clearEndorsement(widget.report.id);
        if (!mounted) return;
        setState(() => _busy = false);
        showAdminSnackBar(
          context,
          'Endorsement cleared.',
          type: AdminSnackType.success,
        );
        return;
      }

      final credentials = await ref
          .read(adminReportsProvider.notifier)
          .endorse(widget.report.id, picked.agency, picked.reason);
      if (!mounted) return;
      setState(() => _busy = false);

      // Straight into the success dialog rather than a toast. The PIN it
      // carries exists nowhere else — the server kept only a hash — so this
      // must not be something the admin can miss while looking elsewhere.
      await showEndorsementSuccessDialog(
        context,
        report: widget.report,
        credentials: credentials,
        reason: picked.reason,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAdminSnackBar(
        context,
        'Could not endorse: $e',
        type: AdminSnackType.error,
      );
    }
  }

  /// Triage ACCEPT → route the report to an internal LGU office. Defaults to the
  /// office the category maps to; the admin can override it if mis-categorized.
  Future<void> _accept() async {
    final r = widget.report;
    final picked = await showAcceptAssignDialog(
      context,
      recommendedOffice: StaffDepartments.forReportCategory(r.categoryKey),
    );
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(adminReportsProvider.notifier).accept(r.id, picked);
      if (!mounted) return;
      // No re-render on the way out — same reasoning as [_reject].
      Navigator.pop(context);
      showAdminSnackBar(
        context,
        'Accepted — routed to $picked.',
        type: AdminSnackType.success,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAdminSnackBar(
        context,
        'Could not accept: $e',
        type: AdminSnackType.error,
      );
    }
  }

  /// REJECT → close the report with a citizen-facing reason. The citizen is
  /// notified by a DB trigger. If staff/external were already working it, an
  /// admin work-log note is posted too so they're pinged the work was closed.
  Future<void> _reject() async {
    final r = widget.report;
    final note = await showRejectReportDialog(context);
    if (note == null || !mounted) return;
    setState(() => _busy = true);
    try {
      // The provider also drops a work-log note (pinging the office) when the
      // report was already being worked, so [r] is passed for that check.
      await ref.read(adminReportsProvider.notifier).reject(r.id, note);
      if (!mounted) return;
      // Deliberately NOT re-rendering into the rejected state on the way out.
      // Repainting the stepper red and swapping the buttons to "Reopen" one
      // frame before the pop means the card that fades away is not the card you
      // were looking at — it reads as a glitch rather than an exit. Dismissing
      // simply pops, which is why it already feels smooth; rejecting now does
      // the same. The rejected state IS rendered — for anyone who opens the
      // report again.
      Navigator.pop(context);
      showAdminSnackBar(
        context,
        'Report rejected — citizen notified.',
        type: AdminSnackType.success,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAdminSnackBar(
        context,
        'Could not reject: $e',
        type: AdminSnackType.error,
      );
    }
  }

  /// Reopen a mistakenly-rejected report — back to the triage desk.
  ///
  /// Stays open, unlike reject / dismiss: reopening isn't finishing with the
  /// report, it's putting it back on the desk. The panes re-render as the
  /// triage view — Accept / Reject, no rejection reason — which is exactly what
  /// you'd see if you closed this and opened the report again.
  Future<void> _reopen() async {
    setState(() => _busy = true);
    try {
      await ref.read(adminReportsProvider.notifier).reopen(widget.report.id);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = ReportStatus.pending;
        // Back on the triage desk is the one place duplicates matter, and the
        // lookup was skipped on open because the report was rejected then.
        _dupFuture = ref
            .read(adminReportsProvider.notifier)
            .fetchDuplicateCandidates(widget.report.id);
      });
      showAdminSnackBar(
        context,
        'Report reopened for triage.',
        type: AdminSnackType.success,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAdminSnackBar(
        context,
        'Could not reopen: $e',
        type: AdminSnackType.error,
      );
    }
  }

  /// "Download Report" → the full printed dossier for this one report.
  ///
  /// Was a one-row CSV, which was the wrong artefact: a spreadsheet answers
  /// "how do these hundreds of reports compare", and nobody downloads ONE
  /// report to ask that. They download it to attach it to something — an
  /// endorsement, a reply, a case file — where a single row answers nothing the
  /// reader will ask.
  ///
  /// The attachments and work log are fetched here rather than in the exporter
  /// so the button can show its spinner while they load. Media is already
  /// cached by the pane, so this is usually just the notes.
  Future<void> _download() async {
    final r = report;
    setState(() => _busy = true);
    try {
      final notifier = ref.read(adminReportsProvider.notifier);
      final media = await notifier.fetchMedia(r.id);
      final notes = await notifier.fetchNotes(r.id);
      await exportReportPdf(report: r, media: media, notes: notes);
      if (!mounted) return;
      setState(() => _busy = false);
      showAdminSnackBar(
        context,
        'Report downloaded.',
        type: AdminSnackType.success,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAdminSnackBar(
        context,
        'Could not download: $e',
        type: AdminSnackType.error,
      );
    }
  }

  /// The facts behind the acceptance, shown in the stage card's inset strip and
  /// in the timeline's first step: when it was accepted, by whom, and to where.
  List<({String label, String value})> _acceptanceFacts() {
    final r = report;
    if (r.isEndorsed) {
      return [
        (label: 'Endorsed on', value: adminLongDateTime(r.endorsedAt)),
        (label: 'Endorsed to', value: r.endorsedToDepartment!),
      ];
    }
    if (r.isAssigned) {
      return [
        (label: 'Accepted on', value: adminLongDateTime(r.assignedAt)),
        (label: 'Accepted by', value: r.assignedByName ?? '—'),
        (label: 'Assigned department', value: r.assignedToDepartment!),
      ];
    }
    return [
      (label: 'Reported on', value: adminLongDateTime(r.createdAt)),
      (
        label: 'Suggested department',
        value: StaffDepartments.forReportCategory(r.categoryKey),
      ),
    ];
  }

  /// Copy + colour for the illustrated stage card — the "where does this report
  /// stand right now" answer, derived from the same lifecycle the stepper uses.
  ({String chip, String headline, String blurb, Color accent}) _stageCopy() {
    final r = report;
    final owner = r.isEndorsed
        ? r.endorsedToDepartment
        : r.assignedToDepartment;

    if (_status == ReportStatus.rejected) {
      return (
        chip: 'Rejected',
        headline: 'This report was rejected.',
        blurb: (r.rejectionNote != null && r.rejectionNote!.isNotEmpty)
            ? r.rejectionNote!
            : 'The report was closed and the citizen was notified.',
        accent: AppColors.red,
      );
    }
    if (_status == ReportStatus.resolved) {
      return (
        chip: 'Completed',
        headline: 'This report has been resolved.',
        blurb: owner == null
            ? 'The reported issue has been addressed and the report is closed.'
            : 'The issue was addressed by $owner. Proof of completion is filed '
                  'under Report History.',
        accent: AppColors.green,
      );
    }
    if (_status == ReportStatus.inProgress) {
      return (
        chip: 'Ongoing',
        headline: 'Work is underway.',
        blurb: owner == null
            ? 'The assigned department is carrying out the work.'
            : '$owner is carrying out the work. Their progress notes are under '
                  'Report History.',
        accent: AppColors.primaryBlue,
      );
    }
    if (r.needsTriage) {
      return (
        chip: 'Not Started',
        headline: 'This report hasn\'t started yet.',
        blurb:
            'The report is still on the triage desk. Accept it to route it '
            'to a department, or reject it with a reason the citizen will see.',
        accent: AppColors.orange,
      );
    }
    // Accepted (or endorsed) and waiting on the owning office to assess it.
    return (
      chip: 'Not Started',
      headline: 'This report hasn\'t started yet.',
      blurb:
          'The report has been accepted and is now waiting to be assessed '
          'by the assigned department.',
      accent: AppColors.primaryBlue,
    );
  }

  // ── Panes ─────────────────────────────────────────────────────────────────

  /// Left pane — the stepper, the stage card, and the Timeline / Report History
  /// tabs. Read-only: status is driven by triage and the owning office, never by
  /// an admin nudging raw states here.
  Widget _statusPane() {
    final r = report;
    final stages = buildReportStages(
      r,
      _status,
      acceptedByName: r.assignedByName,
    );
    final copy = _stageCopy();

    return DetailPane(
      title: 'Update Report Status',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          ReportStepperRail(stages: stages),
          const SizedBox(height: 20),
          ReportStageCard(
            chip: copy.chip,
            headline: copy.headline,
            blurb: copy.blurb,
            accent: copy.accent,
            facts: _acceptanceFacts(),
          ),
          const SizedBox(height: 18),
          AdminUnderlineTabs(
            labels: const ['Timeline', 'Report History'],
            selected: _trackerTab,
            onSelect: (i) => setState(() => _trackerTab = i),
          ),
          const SizedBox(height: 16),
          if (_trackerTab == 0) ...[
            const Text(
              'Timeline Progress',
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: AdminUi.textPrimary,
              ),
            ),
            const SizedBox(height: 14),
            ReportTimelineProgress(stages: stages),
          ] else
            _historyTab(),
        ],
      ),
    );
  }

  /// "Report History" tab — the internal work log between the admin and the
  /// owning office, plus the completion photos once it's resolved. Both are
  /// empty until a department owns the report, so say so rather than showing a
  /// composer that has nobody to talk to.
  Widget _historyTab() {
    final r = report;
    if (!r.isAssigned && !r.isEndorsed) {
      return const DetailEmptyNote(
        icon: Icons.history_rounded,
        text:
            'No history yet. Once this report is accepted and routed to a '
            'department, their progress notes and completion photos appear here.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReportWorkLog(
          reportId: r.id,
          authorRole: 'admin',
          authorName: 'LGU Admin',
        ),
        if (_status == ReportStatus.resolved) ...[
          const SizedBox(height: 20),
          ResolutionMediaSection(reportId: r.id, canEdit: true),
        ],
      ],
    );
  }

  /// Right pane — what was reported, and the actions available on it.
  /// "This may already be reported" strip — triage desk only.
  ///
  /// A suggestion, never an action: it proposes, the admin disposes. Renders
  /// nothing while loading, when there's no candidate, or when
  /// report_duplicates.sql hasn't been applied — so it can never make the pane
  /// jump on open or break a detail view.
  Widget _duplicateSuggestion() {
    return FutureBuilder<List<DuplicateCandidate>>(
      future: _dupFuture,
      builder: (context, snap) {
        final list = snap.data ?? const <DuplicateCandidate>[];
        if (list.isEmpty) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.orange.withValues(alpha: 0.06),
            border: Border.all(color: AppColors.orange.withValues(alpha: 0.35)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.copy_all_rounded,
                    size: 15,
                    color: AppColors.orange,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    list.length == 1
                        ? 'This may already be reported'
                        : 'This may match ${list.length} existing reports',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: AdminUi.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Same category, filed nearby, still open. Linking keeps one '
                'ticket and counts the rest as confirmations.',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.45,
                  color: AdminUi.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              for (final c in list) _duplicateCandidateRow(c),
            ],
          ),
        );
      },
    );
  }

  Widget _duplicateCandidateRow(DuplicateCandidate c) {
    final meta = [
      c.distanceLabel,
      adminShortDate(c.createdAt),
      reportStatusLabel(c.status),
      if (c.reporterCount > 1) '${c.reporterCount} reports',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'RPT-${c.shortRef} — ${c.remarks.trim().isEmpty ? 'No description' : c.remarks}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AdminUi.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  meta,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AdminUi.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _busy ? null : () => _merge(c),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.orange,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Link',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  /// The other citizens who reported this same issue. Their reports are real
  /// rows — this is the only place they're reachable, since a confirmation has
  /// no queue row of its own — so unlinking one lives here too.
  Widget _confirmationsBlock(AdminReport r) {
    final linked = ref
        .read(adminReportsProvider.notifier)
        .confirmationsOf(r.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${r.reporterCount} citizens reported this issue — '
          '${r.confirmCount} confirmed the original.',
          style: const TextStyle(
            fontSize: 13,
            height: 1.5,
            color: AdminUi.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        for (final d in linked)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'RPT-${d.shortId} · ${adminShortDate(d.createdAt)}'
                    '${d.remarks.trim().isEmpty ? '' : ' · ${d.remarks.trim()}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AdminUi.textSecondary,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _unmerge(d),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.red,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Unlink',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Splits a confirmation back out into its own ticket — the escape hatch for a
  /// wrong merge, which is what lets the merge itself be a low-stakes decision.
  Future<void> _unmerge(AdminReport d) async {
    setState(() => _busy = true);
    try {
      await ref.read(adminReportsProvider.notifier).unmerge(d.id);
      if (!mounted) return;
      Navigator.pop(context);
      showAdminSnackBar(
        context,
        'RPT-${d.shortId} is a separate report again — find it under Needs triage.',
        type: AdminSnackType.success,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAdminSnackBar(
        context,
        'Could not unlink: $e',
        type: AdminSnackType.error,
      );
    }
  }

  Widget _detailsPane() {
    final r = report;
    return DetailPane(
      title: 'Report Details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminModerationBar(
            isDismissed: r.isDismissed,
            reason: r.dismissedReason,
            busy: _busy,
            onDismiss: _dismiss,
            onRestore: _restore,
          ),
          _duplicateSuggestion(),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DetailHeroThumb(future: _mediaFuture, categoryKey: r.categoryKey),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DetailKvRow(
                      label: 'Status',
                      trailing: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          StatusPill(
                            label: reportStatusLabel(_status),
                            color: _statusColor(_status),
                          ),
                          if (r.isOverdue) DetailOverdueChip(r.ageDays),
                          if (r.isCorroborated) _ConfirmedChip(r.reporterCount),
                        ],
                      ),
                    ),
                    DetailKvRow(label: 'ID', value: '#RPT-${r.shortId}'),
                    DetailKvRow(
                      label: 'Date Reported',
                      value: adminShortDate(r.createdAt),
                    ),
                    DetailKvRow(
                      label: 'Time Reported',
                      value: adminClockTime(r.createdAt),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(height: 1, color: AdminUi.border),
          const SizedBox(height: 18),
          DetailIconSection(
            icon: reportCategoryIcon(r.categoryKey),
            title: 'Category',
            child: Text(
              r.category,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AdminUi.textSecondary,
              ),
            ),
          ),
          DetailIconSection(
            icon: Icons.location_on_rounded,
            title: 'Location',
            child: DetailLocationBlock(barangay: r.barangay, address: r.address),
          ),
          DetailIconSection(
            icon: Icons.person_rounded,
            title: 'Reported By',
            child: RevealableSubmitter(
              source: RevealSource.report,
              submissionId: r.id,
              isAnonymous: r.isAnonymous,
              name: r.submitterName,
              photoUrl: r.submitterPhotoUrl,
              role: r.submitterRole,
              subject: 'reporter',
            ),
          ),
          DetailIconSection(
            icon: Icons.description_rounded,
            title: 'Details',
            child: Text(
              r.remarks.trim().isEmpty ? '—' : r.remarks,
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: AdminUi.textSecondary,
              ),
            ),
          ),
          DetailIconSection(
            icon: Icons.attach_file_rounded,
            title: 'Attachments',
            isLast: !r.isCorroborated,
            child: DetailMediaGallery(
              future: _mediaFuture,
              placeholderCount: r.mediaCount,
            ),
          ),
          if (r.isCorroborated)
            DetailIconSection(
              icon: Icons.groups_rounded,
              title: 'Confirmations',
              isLast: true,
              child: _confirmationsBlock(r),
            ),
          const SizedBox(height: 18),
          const Divider(height: 1, color: AdminUi.border),
          const SizedBox(height: 16),
          _actionSection(),
        ],
      ),
    );
  }

  /// The action block at the foot of the details pane. Which buttons appear is
  /// driven by where the report actually is: only a report still on the triage
  /// desk can be accepted, only a rejected one can be reopened, and so on.
  Widget _actionSection() {
    final r = report;
    final rejected = _status == ReportStatus.rejected;
    final resolved = _status == ReportStatus.resolved;

    final buttons = <Widget>[];

    if (!r.isDismissed) {
      if (r.needsTriage) {
        buttons.add(
          DetailActionRow(
            children: [
              DetailActionButton(
                label: 'Accept Report',
                icon: Icons.check_circle_rounded,
                color: AppColors.green,
                onTap: _busy ? null : _accept,
              ),
              DetailActionButton(
                label: 'Reject Report',
                icon: Icons.cancel_rounded,
                color: AppColors.red,
                onTap: _busy ? null : _reject,
              ),
            ],
          ),
        );
        buttons.add(
          DetailActionButton(
            label: 'Endorse to external entity',
            icon: Icons.forward_to_inbox_rounded,
            color: AppColors.primaryBlue,
            outlined: true,
            onTap: _busy ? null : _endorse,
          ),
        );
      } else if (rejected) {
        buttons.add(
          DetailActionButton(
            label: 'Reopen Report',
            icon: Icons.restart_alt_rounded,
            color: AppColors.primaryBlue,
            outlined: true,
            onTap: _busy ? null : _reopen,
          ),
        );
      } else if (!resolved) {
        // Being worked by an office or an external entity — the admin oversees:
        // they can pull it back (reject) or re-route an endorsement.
        buttons.add(
          DetailActionRow(
            children: [
              if (r.isEndorsed)
                DetailActionButton(
                  label: 'Change endorsement',
                  icon: Icons.swap_horiz_rounded,
                  color: AppColors.primaryBlue,
                  outlined: true,
                  onTap: _busy ? null : _endorse,
                ),
              DetailActionButton(
                label: 'Reject Report',
                icon: Icons.cancel_rounded,
                color: AppColors.red,
                onTap: _busy ? null : _reject,
              ),
            ],
          ),
        );
      }
    }

    buttons.add(
      DetailActionButton(
        label: 'Download Report',
        icon: Icons.download_rounded,
        color: AppColors.primaryBlue,
        onTap: _busy ? null : _download,
      ),
    );

    return DetailActionSection(buttons: buttons);
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.of(context).size.width < kAdminDetailNarrowBelow;

    // One pane at a time, for the phone and for a dialog too narrow to seat two
    // columns. Stacking both made a small screen scroll the length of the two
    // put together; the tabs keep each to roughly a screen. Details leads —
    // it's what was reported, and it carries the Accept / Reject buttons.
    Widget paneTabs() => AdminSegmentedTabs(
      labels: const ['Report Details', 'Update Report Status'],
      selected: _paneTab,
      onSelect: (i) => setState(() => _paneTab = i),
    );

    Widget activePane() => SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: _paneTab == 0 ? _detailsPane() : _statusPane(),
    );

    if (narrow) {
      return AdminDetailScaffold(
        title: 'Report details',
        child: Container(
          color: AdminUi.pageBg,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                child: paneTabs(),
              ),
              Expanded(child: activePane()),
            ],
          ),
        ),
      );
    }

    return Dialog(
      backgroundColor: AdminUi.pageBg,
      // Vertical inset is deliberately tight: the panes are long, and every
      // pixel given back here is a pixel the admin doesn't have to scroll.
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      // The two-pane layout fills this height so both cards match; the cap
      // stops that from stretching them into mostly-empty space on a tall
      // monitor. On a short viewport the screen binds first.
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120, maxHeight: 900),
        child: LayoutBuilder(
          builder: (context, c) {
            // Two columns only once the details pane can still hold a readable
            // ~330px next to the tracker; below that the dialog falls back to
            // the one-pane-at-a-time tabs.
            //
            // Stacking the two panes into one scroll was tried here instead and
            // REVERTED: it turned a narrow window into a scroll the length of
            // both panes with no way to skip past one, which is worse than a
            // switcher that keeps each to about a screen. Don't retry it.
            if (c.maxWidth < kReportDetailTwoPaneFrom) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                    child: Row(
                      children: [
                        Expanded(child: paneTabs()),
                        const SizedBox(width: 10),
                        const DetailPaneCloseButton(),
                      ],
                    ),
                  ),
                  Flexible(child: activePane()),
                ],
              );
            }
            return Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: AdminTwoPaneRow(
                    main: _statusPane(),
                    side: _detailsPane(),
                  ),
                ),
                // Floats over the details pane's title row (left-aligned, so
                // the corner is free). Pinned rather than scrolled with the
                // pane — the way out stays put however far down you are.
                const Positioned(
                  top: 22,
                  right: 22,
                  child: DetailPaneCloseButton(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Detail building blocks ───────────────────────────────────────────────────

// ── Media gallery + viewers ────────────────────────────────────────────────────
