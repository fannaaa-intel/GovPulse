import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/deeplink_highlight.dart';
import '../../../core/widgets/report_work_log.dart';
import '../../../core/widgets/report_progress_updates.dart';
import '../../../core/widgets/resolution_media.dart';
import '../../admin/providers/admin_reports_provider.dart'
    show ReportStatus, reportStatusLabel;
// The report detail is the admin console's, rendered with staff content — see
// the header above _ReportDetail.
import '../../admin/widgets/admin_detail_screen.dart';
import '../../admin/widgets/admin_submission_ui.dart';
import '../../admin/widgets/report_detail_kit.dart';
import '../../admin/widgets/report_status_tracker.dart';
import '../data/staff_repository.dart';
import '../providers/staff_providers.dart';
import '../../admin/widgets/admin_responsive_dialog.dart';
import '../theme/staff_ui.dart';
import '../widgets/staff_common.dart';
import '../../../core/widgets/app_dialog.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Reports (department-scoped) + Endorsements (external entity) share the same
//  list + detail UI — only the data provider differs.
// ════════════════════════════════════════════════════════════════════════════

class StaffReportsPage extends ConsumerWidget {
  /// A report id to scroll to and flash once, when arriving from a
  /// notification. Null for a normal open.
  final String? highlightId;
  const StaffReportsPage({super.key, this.highlightId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(staffReportsProvider);
    return _ReportListView(
      async: async,
      highlightId: highlightId,
      department: ref.watch(staffDepartmentProvider),
      onRefresh: () => ref.read(staffReportsProvider.notifier).refresh(),
      onSetStatus: (id, s) =>
          ref.read(staffReportsProvider.notifier).setStatus(id, s),
      onReturnToTriage: (id, reason) =>
          ref.read(staffReportsProvider.notifier).returnToTriage(id, reason),
      emptyIcon: Icons.flag_outlined,
      emptyTitle: 'No reports for your department',
      emptySubtitle:
          'Reports routed to your office will appear here. Anonymous reports are included — the reporter stays hidden.',
    );
  }
}

class StaffEndorsementsPage extends ConsumerWidget {
  /// A report id to scroll to and flash once, when arriving from an
  /// endorsement notification. Null for a normal open.
  final String? highlightId;
  const StaffEndorsementsPage({super.key, this.highlightId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(staffEndorsementsProvider);
    return _ReportListView(
      async: async,
      highlightId: highlightId,
      department: ref.watch(staffDepartmentProvider),
      onRefresh: () => ref.read(staffEndorsementsProvider.notifier).refresh(),
      onSetStatus: (id, s) =>
          ref.read(staffEndorsementsProvider.notifier).setStatus(id, s),
      onReturnToTriage: (id, reason) => ref
          .read(staffEndorsementsProvider.notifier)
          .returnToTriage(id, reason),
      emptyIcon: Icons.assignment_turned_in_outlined,
      emptyTitle: 'No endorsed reports',
      emptySubtitle:
          'When the LGU admin endorses an out-of-scope report to your agency, it lands here.',
      endorsement: true,
    );
  }
}

typedef _SetStatus = Future<void> Function(String id, ReportStatus s);
typedef _ReturnToTriage = Future<void> Function(String id, String reason);

/// Ask why the report is being bounced back to the admin. Returns the reason
/// (possibly empty if they confirm without typing), or null on cancel.
Future<String?> _showReturnDialog(BuildContext context) {
  final ctrl = TextEditingController();
  return showAppDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: StaffUi.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Return to triage',
          style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: StaffUi.textPrimary)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This sends the report back to the admin to re-route. Add a short '
            'reason — it\'s logged for the admin.',
            style: TextStyle(
                fontSize: 12.5, color: StaffUi.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            maxLength: 300,
            style: const TextStyle(fontSize: 14, color: StaffUi.textPrimary),
            decoration: InputDecoration(
              hintText: 'e.g. This belongs to the Sanitation Office',
              hintStyle: const TextStyle(color: StaffUi.textMuted),
              filled: true,
              fillColor: StaffUi.subtle,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: StaffUi.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: StaffUi.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: StaffUi.accent),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel',
              style: TextStyle(color: StaffUi.textMuted)),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
          style: FilledButton.styleFrom(backgroundColor: StaffUi.accent),
          child: const Text('Return'),
        ),
      ],
    ),
  );
}

// ── Queue shape: buckets, filters, sort ──────────────────────────────────────

/// The piles an office's queue divides into.
///
/// Deliberately NOT the admin's buckets. Triage states belong to the admin —
/// a report only reaches an office once it has been accepted — so there is no
/// "Needs triage" and no "Dismissed" here. What an office sorts by is how much
/// of the WORK is done.
enum _Bucket { all, toAssess, working, resolved }

String _bucketLabel(_Bucket b) => switch (b) {
      _Bucket.all => 'All',
      _Bucket.toAssess => 'To assess',
      _Bucket.working => 'In progress',
      _Bucket.resolved => 'Resolved',
    };

bool _inBucket(StaffReport r, _Bucket b) => switch (b) {
      _Bucket.all => true,
      // Pending sits here too: a freshly-routed report the office hasn't
      // acknowledged yet is exactly "to assess".
      _Bucket.toAssess =>
        r.status == ReportStatus.pending || r.status == ReportStatus.underReview,
      _Bucket.working => r.status == ReportStatus.inProgress,
      _Bucket.resolved => r.status == ReportStatus.resolved,
    };

enum _Sort { newest, oldest }

/// Everything the toolbar can narrow the list by. Held in the page rather than
/// the notifier on purpose: the notifier owns a POLLING fetch, and rebuilding
/// it on every keystroke would tear down and re-arm its interval timer (see
/// StaffIdentity's equality note). The office's list is capped at 200 rows, so
/// filtering it here costs nothing.
class _Filters {
  final _Bucket bucket;
  final String query;
  final String? categoryKey;
  final _Sort sort;
  final bool overdueOnly;
  final bool anonymousOnly;

  const _Filters({
    this.bucket = _Bucket.all,
    this.query = '',
    this.categoryKey,
    this.sort = _Sort.newest,
    this.overdueOnly = false,
    this.anonymousOnly = false,
  });

  _Filters copyWith({
    _Bucket? bucket,
    String? query,
    Object? categoryKey = _unset,
    _Sort? sort,
    bool? overdueOnly,
    bool? anonymousOnly,
  }) =>
      _Filters(
        bucket: bucket ?? this.bucket,
        query: query ?? this.query,
        categoryKey: categoryKey == _unset
            ? this.categoryKey
            : categoryKey as String?,
        sort: sort ?? this.sort,
        overdueOnly: overdueOnly ?? this.overdueOnly,
        anonymousOnly: anonymousOnly ?? this.anonymousOnly,
      );

  /// Sentinel so [copyWith] can tell "leave it" from "clear it" for a nullable
  /// field — passing null for categoryKey has to mean "All categories".
  static const Object _unset = Object();

  /// What the Filters SHEET owns. The bucket and the query have their own
  /// visible controls, so counting them here would badge the button for a
  /// filter the user can already see.
  int get sheetCount =>
      (categoryKey != null ? 1 : 0) +
      (sort != _Sort.newest ? 1 : 0) +
      (overdueOnly ? 1 : 0) +
      (anonymousOnly ? 1 : 0);
}

class _ReportListView extends StatefulWidget {
  final AsyncValue<List<StaffReport>> async;
  final String? department;
  final Future<void> Function() onRefresh;
  final _SetStatus onSetStatus;
  final _ReturnToTriage onReturnToTriage;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptySubtitle;
  final bool endorsement;

  /// A report id to scroll to and flash once, when arriving from a
  /// notification. Null for a normal open.
  final String? highlightId;

  const _ReportListView({
    required this.async,
    required this.department,
    required this.onRefresh,
    required this.onSetStatus,
    required this.onReturnToTriage,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptySubtitle,
    this.endorsement = false,
    this.highlightId,
  });

  @override
  State<_ReportListView> createState() => _ReportListViewState();
}

class _ReportListViewState extends State<_ReportListView>
    with DeepLinkHighlightMixin {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  _Filters _filters = const _Filters();

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _set(_Filters next) => setState(() => _filters = next);

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => _set(_filters.copyWith(query: value)),
    );
  }

  List<StaffReport> get _all => widget.async.valueOrNull ?? const [];

  /// The categories this office actually receives. Offered as the category
  /// filter instead of the full citizen list, because an office only ever
  /// handles a few of them — Engineering sees roads, drainage and streetlights
  /// and would never use the other three.
  List<({String key, String label})> get _categories {
    final seen = <String, String>{};
    for (final r in _all) {
      seen.putIfAbsent(r.categoryKey, () => r.category);
    }
    return [for (final e in seen.entries) (key: e.key, label: e.value)]
      ..sort((a, b) => a.label.compareTo(b.label));
  }

  List<StaffReport> _apply(List<StaffReport> items) {
    final f = _filters;
    final q = f.query.trim().toLowerCase();
    final out = [
      for (final r in items)
        if (_inBucket(r, f.bucket) &&
            (f.categoryKey == null || r.categoryKey == f.categoryKey) &&
            (!f.overdueOnly || r.isOverdue) &&
            (!f.anonymousOnly || r.isAnonymous) &&
            (q.isEmpty ||
                r.remarks.toLowerCase().contains(q) ||
                (r.barangay ?? '').toLowerCase().contains(q) ||
                (r.address ?? '').toLowerCase().contains(q) ||
                r.category.toLowerCase().contains(q) ||
                r.shortId.toLowerCase().contains(q)))
          r,
    ];
    out.sort((a, b) {
      final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
      final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
      return f.sort == _Sort.newest ? bt.compareTo(at) : at.compareTo(bt);
    });
    return out;
  }

  void _openFilters() {
    openAdminFilterSheet(
      context,
      title: widget.endorsement ? 'Filter endorsements' : 'Filter reports',
      onReset: () => _set(
        _filters.copyWith(
          categoryKey: null,
          sort: _Sort.newest,
          overdueOnly: false,
          anonymousOnly: false,
        ),
      ),
      content: StatefulBuilder(
        builder: (context, setSheet) {
          // The sheet edits the page's filters directly; setSheet only repaints
          // the sheet's own chips so the selection reads back immediately.
          void update(_Filters next) {
            _set(next);
            setSheet(() {});
          }

          final cats = _categories;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (cats.length > 1) ...[
                FilterChoiceRow<String>(
                  label: 'Category',
                  value: _filters.categoryKey,
                  options: [
                    (value: null, text: 'All'),
                    for (final c in cats) (value: c.key, text: c.label),
                  ],
                  onSelected: (v) =>
                      update(_filters.copyWith(categoryKey: v)),
                ),
                const SizedBox(height: 18),
              ],
              FilterChoiceRow<_Sort>(
                label: 'Sort',
                value: _filters.sort,
                options: const [
                  (value: _Sort.newest, text: 'Newest'),
                  (value: _Sort.oldest, text: 'Oldest'),
                ],
                onSelected: (v) {
                  if (v != null) update(_filters.copyWith(sort: v));
                },
              ),
              const SizedBox(height: 18),
              FilterSwitchRow(
                icon: Icons.schedule_rounded,
                label: 'Overdue only',
                subtitle: 'Open more than 7 days since it reached your office',
                value: _filters.overdueOnly,
                onChanged: (v) => update(_filters.copyWith(overdueOnly: v)),
              ),
              const SizedBox(height: 12),
              FilterSwitchRow(
                icon: Icons.visibility_off_rounded,
                label: 'Anonymous only',
                subtitle: 'Show only reports with a withheld identity',
                value: _filters.anonymousOnly,
                onChanged: (v) => update(_filters.copyWith(anonymousOnly: v)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = widget.async;

    // Rows exist only once the fetch resolves — flash the deep-link target then.
    if (async.hasValue) flashHighlightOnce(widget.highlightId);

    return StaffPageBody(
      onRefresh: widget.onRefresh,
      maxWidth: 1400,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(items: _all, loaded: async.hasValue),
          const SizedBox(height: 14),
          // Buckets first: they answer "which pile am I looking at", which the
          // search and the filters then narrow.
          AdminPillTabs(
            labels: [for (final b in _Bucket.values) _bucketLabel(b)],
            counts: async.hasValue
                ? [
                    for (final b in _Bucket.values)
                      _all.where((r) => _inBucket(r, b)).length,
                  ]
                : null,
            selected: _Bucket.values.indexOf(_filters.bucket),
            onSelect: (i) =>
                _set(_filters.copyWith(bucket: _Bucket.values[i])),
            fadeColor: StaffUi.pageBg,
          ),
          const SizedBox(height: 12),
          _Toolbar(
            searchCtrl: _searchCtrl,
            activeCount: _filters.sheetCount,
            onSearch: _onSearchChanged,
            onClearSearch: () {
              _searchCtrl.clear();
              _set(_filters.copyWith(query: ''));
            },
            onOpenFilters: _openFilters,
          ),
          _ActiveChips(
            filters: _filters,
            categories: _categories,
            onChange: _set,
          ),
          const SizedBox(height: 14),
          _Results(
            async: async,
            filtered: _apply(_all),
            filtering: _filters.sheetCount > 0 ||
                _filters.query.trim().isNotEmpty ||
                _filters.bucket != _Bucket.all,
            onClearFilters: () {
              _searchCtrl.clear();
              _set(const _Filters());
            },
            onRetry: widget.onRefresh,
            onOpen: (r) => _openDetail(context, r),
            keyFor: highlightKey,
            isHighlighted: isHighlighted,
            emptyIcon: widget.emptyIcon,
            emptyTitle: widget.emptyTitle,
            emptySubtitle: widget.emptySubtitle,
          ),
        ],
      ),
    );
  }

  void _openDetail(BuildContext context, StaffReport r) {
    // Same presentation as the admin console's report detail: a full-screen
    // slide-up page on a phone, a centred dialog card on the web.
    showAdminDetail(
      context,
      builder: (_) => _ReportDetail(
        report: r,
        endorsement: widget.endorsement,
        department: widget.department,
        onSetStatus: widget.onSetStatus,
        onReturnToTriage: widget.onReturnToTriage,
      ),
    );
  }
}

// ── Header ───────────────────────────────────────────────────────────────────

/// "N reports · N anonymous", plus an overdue count when there is one.
///
/// Overdue is the office's own KPI — it counts reports IT has been sitting on
/// (the clock starts when the report was routed here, not when it was filed),
/// so it belongs at the top of the office's queue rather than in a filter.
class _Header extends StatelessWidget {
  final List<StaffReport> items;
  final bool loaded;
  const _Header({required this.items, required this.loaded});

  @override
  Widget build(BuildContext context) {
    if (!loaded) {
      return const Text(
        'Reports routed to your office',
        style: TextStyle(fontSize: 13, color: StaffUi.textMuted),
      );
    }
    final total = items.length;
    final anon = items.where((r) => r.isAnonymous).length;
    final overdue = items.where((r) => r.isOverdue).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '$total report${total == 1 ? '' : 's'}',
              style: const TextStyle(fontSize: 13, color: StaffUi.textMuted),
            ),
            if (anon > 0) ...[
              const Text('  ·  ', style: TextStyle(color: StaffUi.textMuted)),
              const Icon(
                Icons.visibility_off_rounded,
                size: 13,
                color: kAnonColor,
              ),
              const SizedBox(width: 3),
              Text(
                '$anon anonymous',
                style: const TextStyle(fontSize: 13, color: kAnonColor),
              ),
            ],
          ],
        ),
        if (overdue > 0) ...[
          const SizedBox(height: 10),
          _HeaderStat(
            icon: Icons.schedule_rounded,
            label: '$overdue overdue',
            color: StaffUi.warn,
          ),
        ],
      ],
    );
  }
}

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

// ── Toolbar ──────────────────────────────────────────────────────────────────

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

class _ActiveChips extends StatelessWidget {
  final _Filters filters;
  final List<({String key, String label})> categories;
  final ValueChanged<_Filters> onChange;
  const _ActiveChips({
    required this.filters,
    required this.categories,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    // No bucket chip: the pill above already shows which pile is on screen.
    final chips = <Widget>[
      if (filters.categoryKey != null)
        ActiveChip(
          label: categories
              .firstWhere(
                (c) => c.key == filters.categoryKey,
                orElse: () => (key: '', label: 'Category'),
              )
              .label,
          onRemove: () => onChange(filters.copyWith(categoryKey: null)),
        ),
      if (filters.sort != _Sort.newest)
        ActiveChip(
          label: 'Oldest first',
          onRemove: () => onChange(filters.copyWith(sort: _Sort.newest)),
        ),
      if (filters.overdueOnly)
        ActiveChip(
          label: 'Overdue only',
          onRemove: () => onChange(filters.copyWith(overdueOnly: false)),
        ),
      if (filters.anonymousOnly)
        ActiveChip(
          label: 'Anonymous only',
          emphasize: true,
          onRemove: () => onChange(filters.copyWith(anonymousOnly: false)),
        ),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(spacing: 8, runSpacing: 8, children: chips),
    );
  }
}

// ── Results ──────────────────────────────────────────────────────────────────

class _Results extends StatelessWidget {
  final AsyncValue<List<StaffReport>> async;
  final List<StaffReport> filtered;

  /// True when something is narrowing the list, so an empty result can say
  /// "nothing MATCHES" (with a way out) rather than "you have nothing".
  final bool filtering;
  final VoidCallback onClearFilters;
  final Future<void> Function() onRetry;
  final void Function(StaffReport) onOpen;
  final GlobalKey Function(String id) keyFor;
  final bool Function(String id) isHighlighted;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptySubtitle;

  const _Results({
    required this.async,
    required this.filtered,
    required this.filtering,
    required this.onClearFilters,
    required this.onRetry,
    required this.onOpen,
    required this.keyFor,
    required this.isHighlighted,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptySubtitle,
  });

  @override
  Widget build(BuildContext context) {
    return AdminResultsCard(
      child: async.when(
        loading: () => const _ReportListSkeleton(),
        error: (e, _) => AdminResultsMessage(
          icon: Icons.cloud_off_rounded,
          color: StaffUi.danger,
          text: "Couldn't load reports.",
          action: TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(foregroundColor: StaffUi.accent),
            child: const Text('Retry'),
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: StaffEmptyState(
                icon: emptyIcon,
                title: emptyTitle,
                subtitle: emptySubtitle,
              ),
            );
          }
          if (filtered.isEmpty) {
            return AdminResultsMessage(
              icon: Icons.filter_alt_off_rounded,
              color: StaffUi.textMuted,
              text: 'No reports match this view.',
              action: TextButton(
                onPressed: onClearFilters,
                style: TextButton.styleFrom(foregroundColor: StaffUi.accent),
                child: const Text('Clear filters'),
              ),
            );
          }
          return LayoutBuilder(
            builder: (context, c) {
              if (c.maxWidth >= kReportTableFrom) {
                return Column(
                  children: [
                    const _TableHeader(),
                    for (final r in filtered)
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
                    for (final r in filtered)
                      _ReportCard(
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

// ── Wide table ───────────────────────────────────────────────────────────────

/// Column widths for the wide table, in one place — the header and the rows are
/// separate widgets that must lay out identically.
///
/// No SUBMITTER column, unlike the admin's table: there is no name to put in
/// it. REPORTER carries the one fact an office is allowed to know — whether the
/// reporter chose to stay anonymous.
abstract final class _Col {
  static const int category = 4;
  static const int reporter = 2;
  static const int barangay = 2;
  static const int progress = 2;

  /// Wider than its neighbours on purpose: this cell seats a status pill AND an
  /// overdue chip beside it, on ONE line.
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
        color: StaffUi.subtle,
        border: Border(bottom: BorderSide(color: StaffUi.border)),
      ),
      child: const Row(
        children: [
          _HCell('CATEGORY', flex: _Col.category),
          _HCell('REPORTER', flex: _Col.reporter),
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
          color: StaffUi.textMuted,
        ),
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  final StaffReport report;
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
                accent: StaffUi.accent,
                divider: const BorderSide(color: StaffUi.border),
              )
            : BoxDecoration(
                color: r.isAnonymous
                    ? kAnonColor.withValues(alpha: 0.035)
                    : null,
                border: const Border(bottom: BorderSide(color: StaffUi.border)),
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
                            color: StaffUi.textPrimary,
                          ),
                        ),
                        Text(
                          r.shortId,
                          style: const TextStyle(
                            fontSize: 11,
                            color: StaffUi.textMuted,
                          ),
                        ),
                        if (r.remarks.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              r.remarks.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: StaffUi.textSecondary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(flex: _Col.reporter, child: _ReporterCell(r.isAnonymous)),
            Expanded(
              flex: _Col.barangay,
              child: Text(
                (r.barangay == null || r.barangay!.isEmpty) ? '—' : r.barangay!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: StaffUi.textMuted),
              ),
            ),
            Expanded(
              flex: _Col.progress,
              child: ReportProgressLabel(stages: _stagesOf(r)),
            ),
            Expanded(flex: _Col.status, child: _StatusCell(r)),
            Expanded(
              flex: _Col.date,
              child: Text(
                adminShortDate(r.createdAt),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: StaffUi.textMuted),
              ),
            ),
            SizedBox(width: _Col.media, child: _MediaCount(r.mediaCount)),
          ],
        ),
      ),
    );
  }
}

/// Where the report has got to, in the tracker's own vocabulary — the same
/// stages the detail's stepper draws, so the list and the detail never disagree.
List<ReportStage> _stagesOf(StaffReport r) => buildReportStagesFrom(
      status: r.status,
      accepted: true,
      isEndorsed: r.endorsedToDepartment != null,
      owner: r.endorsedToDepartment ?? r.assignedToDepartment,
      acceptedAt: r.assignedAt,
    );

/// The REPORTER column: whether the citizen chose to stay anonymous, which is
/// the only thing about them an office is allowed to know.
///
/// The pill is a fixed ~98px in a FLEXED cell, so it goes in the shrinkable
/// wrapper — a cell a few pixels narrower reports overflow otherwise.
class _ReporterCell extends StatelessWidget {
  final bool isAnonymous;
  const _ReporterCell(this.isAnonymous);

  @override
  Widget build(BuildContext context) {
    if (!isAnonymous) {
      return const Text(
        'Citizen',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 13, color: StaffUi.textMuted),
      );
    }
    return const ShrinkableAnonPill();
  }
}

/// The STATUS column of one row: the status pill plus the overdue flag, on ONE
/// line. A [Wrap] here made the column ragged — a wide status ("In progress")
/// pushed the chip onto a second line while "Pending" kept its on the first, so
/// rows in the same table stood at different heights. The chip gives up its
/// label as the column narrows instead; the colour, icon and tooltip carry it.
class _StatusCell extends StatelessWidget {
  final StaffReport report;
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
            Flexible(
              child: StatusPill(
                label: reportStatusLabel(r.status),
                color: staffReportStatusColor(r.status),
              ),
            ),
            if (r.isOverdue) ...[
              const SizedBox(width: 6),
              DetailOverdueChip(r.ageDays, density: density),
            ],
          ],
        );
      },
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
        const Icon(Icons.image_outlined, size: 15, color: StaffUi.textMuted),
        const SizedBox(width: 2),
        Text(
          '$count',
          style: const TextStyle(fontSize: 11, color: StaffUi.textMuted),
        ),
      ],
    );
  }
}

// ── Narrow card ──────────────────────────────────────────────────────────────

class _ReportCard extends StatelessWidget {
  final StaffReport report;
  final VoidCallback onOpen;
  final bool highlighted;
  const _ReportCard({
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
                    color: StaffUi.textPrimary,
                  ),
                ),
              ),
              StatusPill(
                label: reportStatusLabel(r.status),
                color: staffReportStatusColor(r.status),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ReportProgressLabel(stages: _stagesOf(r)),
          if (r.isAnonymous || r.isOverdue) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (r.isAnonymous) const AnonPill(),
                if (r.isOverdue) DetailOverdueChip(r.ageDays),
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
                color: StaffUi.textSecondary,
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
            style: const TextStyle(fontSize: 11.5, color: StaffUi.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Placeholder rows shown while the list loads — shaped like the real rows so
/// the layout doesn't shift when the fetch lands.
class _ReportListSkeleton extends StatelessWidget {
  const _ReportListSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: StaffShimmer(
        child: Column(
          children: [
            _SkeletonRow(),
            _SkeletonRow(),
            _SkeletonRow(),
            _SkeletonRow(),
            _SkeletonRow(),
          ],
        ),
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StaffSkeletonBox(width: 30, height: 30, radius: 8),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StaffSkeletonBox(width: 140, height: 12),
                SizedBox(height: 8),
                StaffSkeletonBox(width: 90, height: 10),
              ],
            ),
          ),
          SizedBox(
            width: 70,
            child: StaffSkeletonBox(width: 70, height: 20, radius: 20),
          ),
        ],
      ),
    );
  }
}
// ═════════════════════════════════════════════════════════════════════════════
//  Report detail
//
//  The SAME two-pane detail the admin console uses (see report_detail_kit.dart)
//  — "Update Report Status" beside "Report Details", one pane at a time once
//  the viewport is too narrow to seat both. What differs is the CONTENT, and
//  deliberately so:
//
//    • the office can MOVE the report through the working states, which the
//      admin's read-only pane cannot — that control sits under the stage card;
//    • there is no reporter identity here, ever. The staff view carries no
//      name, anonymous or not, so "Reported By" says what is known and no more;
//    • the only triage action an office has is handing the report back.
// ═════════════════════════════════════════════════════════════════════════════

class _ReportDetail extends ConsumerStatefulWidget {
  final StaffReport report;
  final bool endorsement;
  final String? department;
  final _SetStatus onSetStatus;
  final _ReturnToTriage onReturnToTriage;
  const _ReportDetail({
    required this.report,
    required this.endorsement,
    required this.department,
    required this.onSetStatus,
    required this.onReturnToTriage,
  });

  @override
  ConsumerState<_ReportDetail> createState() => _ReportDetailState();
}

class _ReportDetailState extends ConsumerState<_ReportDetail> {
  late ReportStatus _status = widget.report.status;
  bool _busy = false;

  /// The status whose chip was pressed and is now being written.
  ///
  /// [_busy] disables every chip while the write is in flight; this says which
  /// one the officer chose, so the spinner appears where they clicked rather
  /// than the whole row simply going dead.
  ReportStatus? _applying;

  /// The "Return to triage" action is the one running.
  bool _returning = false;

  /// The report is finished with — completed, or refused by the admin.
  ///
  /// The single definition of "closed" for this pane, so the status control,
  /// the citizen-facing composer and the internal thread cannot drift apart
  /// about whether there is still work to do. Staff never see dismissed rows,
  /// so those are not part of this test (unlike the admin console's).
  bool get _isClosed =>
      _status == ReportStatus.resolved || _status == ReportStatus.rejected;

  /// Which tab of the status pane is showing: 0 = Timeline, 1 = Work log.
  int _trackerTab = 0;

  /// Which PANE is showing, when the layout is too narrow to seat both side by
  /// side: 0 = Report Details, 1 = Update Report Status.
  int _paneTab = 0;

  /// Fetched ONCE, here. Built inside build() (as the old sheet's media strip
  /// did) it re-ran on every rebuild, so each status tap re-signed the media
  /// URLs and flashed the attachments back to their skeleton.
  late final Future<List<DetailMediaItem>> _mediaFuture = ref
      .read(staffRepoProvider)
      .fetchReportMedia(widget.report.id)
      .then(
        (media) => [
          for (final m in media)
            DetailMediaItem(
              url: m.url,
              isVideo: m.isVideo,
              isGpsVerified: m.isGpsVerified,
            ),
        ],
      );

  // Staff own the WORKING states only. Triage states (pending / rejected)
  // belong to the admin — a report only reaches staff once accepted.
  static const _flow = [
    ReportStatus.underReview,
    ReportStatus.inProgress,
    ReportStatus.resolved,
  ];

  /// The office that owns this report — the agency it was endorsed to, or the
  /// department it was assigned to.
  String? get _owner => widget.endorsement
      ? (widget.report.endorsedToDepartment ?? widget.department)
      : (widget.report.assignedToDepartment ?? widget.department);

  Future<void> _apply(ReportStatus s) async {
    if (s == _status || _busy) return;
    setState(() {
      _busy = true;
      _applying = s;
    });
    try {
      await widget.onSetStatus(widget.report.id, s);
      if (mounted) {
        setState(() {
          _status = s;
          _busy = false;
          _applying = null;
        });
        showAppSnackBar(context, 'Status set to ${reportStatusLabel(s)}.',
            type: AppSnackType.success);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _applying = null;
        });
        showAppSnackBar(context, '$e', type: AppSnackType.error);
      }
    }
  }

  Future<void> _returnToTriage() async {
    final reason = await _showReturnDialog(context);
    // Re-check _busy as well as mounted: the dialog was open for as long as the
    // officer took to type a reason, and a status chip may have claimed the
    // pane in the meantime.
    if (reason == null || !mounted || _busy) return;
    setState(() {
      _busy = true;
      _returning = true;
    });
    try {
      await widget.onReturnToTriage(widget.report.id, reason);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _returning = false;
      });
      Navigator.pop(context);
      showAppSnackBar(context, 'Returned to the admin for re-routing.',
          type: AppSnackType.success);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _returning = false;
        });
        showAppSnackBar(context, '$e', type: AppSnackType.error);
      }
    }
  }

  /// The facts behind the routing, shown in the stage card's inset strip: when
  /// the report reached this office, and which office owns it.
  List<({String label, String value})> _routingFacts() {
    final r = widget.report;
    return [
      (
        label: widget.endorsement ? 'Endorsed on' : 'Routed on',
        value: adminLongDateTime(r.assignedAt ?? r.createdAt),
      ),
      if (_owner != null)
        (
          label: widget.endorsement ? 'Endorsed to' : 'Assigned department',
          value: _owner!,
        ),
    ];
  }

  /// Copy + colour for the illustrated stage card — "where does this report
  /// stand right now", read from the office's side of the work.
  ({String chip, String headline, String blurb, Color accent}) _stageCopy() {
    switch (_status) {
      case ReportStatus.rejected:
        return (
          chip: 'Rejected',
          headline: 'This report was closed.',
          blurb: 'The LGU admin rejected the report, so no further work is '
              'expected from your office.',
          accent: StaffUi.danger,
        );
      case ReportStatus.resolved:
        return (
          chip: 'Completed',
          headline: 'This report has been resolved.',
          blurb: 'Your office marked the work complete. Attach proof of '
              'completion under Work log so the admin can close it out.',
          accent: StaffUi.online,
        );
      case ReportStatus.inProgress:
        return (
          chip: 'Ongoing',
          headline: 'Work is underway.',
          blurb: 'Your office is carrying out the work. Log progress under '
              'Work log — the admin reads it, the citizen never does.',
          accent: StaffUi.accentSoft,
        );
      case ReportStatus.underReview:
        return (
          chip: 'For assessment',
          headline: 'This report is being assessed.',
          blurb: 'Your office is assessing the issue. Move it to In progress '
              'once the work actually starts.',
          accent: StaffUi.accentSoft,
        );
      case ReportStatus.pending:
        return (
          chip: 'Not Started',
          headline: 'This report hasn\'t started yet.',
          blurb: 'It was routed to your office and is waiting to be assessed. '
              'If it isn\'t yours, hand it back to triage.',
          accent: StaffUi.warn,
        );
    }
  }

  // ── Panes ─────────────────────────────────────────────────────────────────

  /// Left pane — the stepper, the stage card, the status control that is the
  /// office's one write on the lifecycle, and the Timeline / Work log tabs.
  Widget _statusPane() {
    final r = widget.report;
    final stages = buildReportStagesFrom(
      status: _status,
      // A report only reaches an office once the admin has passed triage.
      accepted: true,
      isEndorsed: widget.endorsement,
      owner: _owner,
      acceptedAt: r.assignedAt,
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
            facts: _routingFacts(),
          ),
          const SizedBox(height: 18),
          _StatusControl(
            flow: _flow,
            current: _status,
            busy: _busy,
            applying: _applying,
            locked: _isClosed,
            onPick: _apply,
          ),
          const SizedBox(height: 18),
          AdminUnderlineTabs(
            labels: const ['Timeline', 'Work log'],
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
                color: StaffUi.textPrimary,
              ),
            ),
            const SizedBox(height: 14),
            ReportTimelineProgress(stages: stages),
          ] else
            _workLogTab(),
        ],
      ),
    );
  }

  /// "Work log" tab — the internal thread between this office and the admin,
  /// plus the completion photos once the work is done.
  Widget _workLogTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The citizen-facing half first: what this office writes here reaches
        // the reporter once an admin approves it.
        //
        // NOTE the tab used to open with "Log progress or reply to the admin.
        // The citizen never sees this." — true of the work log, and flatly
        // wrong about the panel that now sits under it. Each half carries its
        // own caption instead, because the whole risk on this screen is an
        // officer mistaking one box for the other.
        // Locked once the report is closed. An office was previously offered
        // a "tell the Municipality what has happened" box on work it had
        // finished weeks earlier — an invitation to file progress against a
        // closed report, which is either a mistake about to happen or a note
        // nobody will read. The history stays; only the composer goes.
        ReportProgressUpdates(
          reportId: widget.report.id,
          mode: ReportUpdatesMode.author,
          authorName: widget.department ?? 'Staff',
          locked: _isClosed,
        ),
        const SizedBox(height: 22),
        const Text(
          'INTERNAL NOTES',
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.7,
            color: StaffUi.textMuted,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Between this office and the admin only. The citizen never sees '
          'these.',
          style: TextStyle(
            fontSize: 12.5,
            height: 1.45,
            color: StaffUi.textMuted,
          ),
        ),
        const SizedBox(height: 10),
        // Locked here but NOT on the admin side — see ReportWorkLog.locked.
        // Oversight continues after closure; this office's work does not.
        ReportWorkLog(
          reportId: widget.report.id,
          authorRole: 'staff',
          authorName: widget.department ?? 'Staff',
          locked: _isClosed,
        ),
        if (_status == ReportStatus.resolved) ...[
          const SizedBox(height: 20),
          ResolutionMediaSection(reportId: widget.report.id, canEdit: true),
        ],
      ],
    );
  }

  /// Right pane — what was reported, and the one action an office has on it.
  Widget _detailsPane() {
    final r = widget.report;
    return DetailPane(
      title: 'Report Details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.endorsement && r.endorsedToDepartment != null) ...[
            StaffPill(
              label: 'Endorsed to ${r.endorsedToDepartment}',
              color: StaffUi.accent,
              icon: Icons.forward_to_inbox_rounded,
            ),
            const SizedBox(height: 14),
          ],
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
                            color: staffReportStatusColor(_status),
                          ),
                          if (r.isOverdue) DetailOverdueChip(r.ageDays),
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
          const Divider(height: 1, color: StaffUi.border),
          const SizedBox(height: 18),
          DetailIconSection(
            icon: reportCategoryIcon(r.categoryKey),
            title: 'Category',
            child: Text(
              r.category,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: StaffUi.textSecondary,
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
            child: _ReporterBlock(isAnonymous: r.isAnonymous),
          ),
          DetailIconSection(
            icon: Icons.description_rounded,
            title: 'Details',
            child: Text(
              r.remarks.trim().isEmpty ? '—' : r.remarks,
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: StaffUi.textSecondary,
              ),
            ),
          ),
          DetailIconSection(
            icon: Icons.attach_file_rounded,
            title: 'Attachments',
            isLast: true,
            child: DetailMediaGallery(
              future: _mediaFuture,
              placeholderCount: r.mediaCount,
            ),
          ),
          // "Not my department" is a triage objection, and it stops making
          // sense the moment the work is finished: an office cannot both have
          // completed a report and disown it. Offered on a closed report it
          // would bounce completed work back to the admin's desk and drag the
          // citizen's status backwards. The whole action block goes with it —
          // an empty bordered section under a divider is worse than no section.
          if (!_isClosed) ...[
            const SizedBox(height: 18),
            const Divider(height: 1, color: StaffUi.border),
            const SizedBox(height: 16),
            DetailActionSection(
              buttons: [
                DetailActionButton(
                  label: 'Not my department — return to triage',
                  icon: Icons.reply_rounded,
                  color: StaffUi.accent,
                  outlined: true,
                  busy: _returning,
                  onTap: _busy ? null : _returnToTriage,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.of(context).size.width < kAdminDetailNarrowBelow;

    // One pane at a time, for the phone and for a dialog too narrow to seat two
    // columns. Details leads — it's what was reported.
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
          color: StaffUi.pageBg,
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

    // Full screen on a phone, modal above 640 — the same rule the admin
    // console's report dialogs follow. This is staff's counterpart to the
    // admin report detail, and the two are opened from the same kind of list
    // for the same kind of work, so they take the same shape.
    final full = adminDialogIsFullscreen(context);

    return Dialog(
      backgroundColor: StaffUi.pageBg,
      // Vertical inset is deliberately tight: the panes are long, and every
      // pixel given back here is a pixel nobody has to scroll. On a phone it
      // goes to zero — the detail IS the screen there.
      insetPadding: full
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      clipBehavior: Clip.antiAlias,
      shape: full
          ? const RoundedRectangleBorder()
          : RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: full
            ? BoxConstraints(
                minWidth: MediaQuery.sizeOf(context).width,
                minHeight: MediaQuery.sizeOf(context).height,
              )
            : const BoxConstraints(maxWidth: 1120, maxHeight: 900),
        child: LayoutBuilder(
          builder: (context, c) {
            // Two columns only once the details pane can still hold a readable
            // column beside the tracker; below that, one pane at a time.
            //
            // Stacking the two panes into one scroll was tried here instead and
            // REVERTED: it turned a narrow window into a scroll the length of
            // both panes with no way to skip past one. Don't retry it.
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
                // Pinned rather than scrolled with the pane — the way out stays
                // put however far down you are.
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

/// The office's one write on the lifecycle: which working state the report is
/// in. The admin's equivalent pane is read-only, so this has no counterpart
/// there — it sits under the stage card, where the pane's title promises it.
class _StatusControl extends StatelessWidget {
  final List<ReportStatus> flow;
  final ReportStatus current;
  final bool busy;

  /// The chip whose write is in flight, if any - it carries the spinner.
  final ReportStatus? applying;

  /// The report is finished with, so there are no moves left to offer.
  final bool locked;
  final ValueChanged<ReportStatus> onPick;
  const _StatusControl({
    required this.flow,
    required this.current,
    required this.busy,
    required this.locked,
    required this.onPick,
    this.applying,
  });

  @override
  Widget build(BuildContext context) {
    // ── A closed report offers no moves ────────────────────────────────────
    //
    // This used to render the full chip row whatever the status, so a RESOLVED
    // report still showed live "Under review" and "In progress" chips. One tap
    // reopened finished work and — because every status change notifies the
    // reporter — told the resident their completed report had gone backwards.
    //
    // An office has no standing to reopen its own closed work: that is the
    // admin's call, and the admin console has its own Reopen action. So this
    // becomes a statement of fact rather than a control.
    if (locked) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: const Color(0xFFF6F8FB),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: StaffUi.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              current == ReportStatus.resolved
                  ? Icons.task_alt_rounded
                  : Icons.do_not_disturb_on_outlined,
              size: 19,
              color: staffReportStatusColor(current),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    current == ReportStatus.resolved
                        ? 'This report is completed.'
                        : 'This report is closed.',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: StaffUi.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'No further action is needed from this office. Contact '
                    'the Municipality if it has to be reopened.',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.4,
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Move this report',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: StaffUi.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'The citizen sees this change on their own report.',
          style: TextStyle(fontSize: 11.5, color: StaffUi.textMuted),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in flow)
              _StatusChip(
                label: reportStatusLabel(s),
                color: staffReportStatusColor(s),
                selected: current == s,
                busy: applying == s,
                onTap: busy || current == s ? null : () => onPick(s),
              ),
          ],
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;

  /// This chip's status is the one being written.
  ///
  /// The chip takes its SELECTED colours while busy even though the write has
  /// not landed - the officer pressed it, and showing it inert until the server
  /// answers reads as a press that missed.
  final bool busy;
  final VoidCallback? onTap;
  const _StatusChip({
    required this.label,
    required this.color,
    required this.selected,
    this.busy = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(StaffUi.controlRadius),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: (selected || busy) ? color : StaffUi.subtle,
            borderRadius: BorderRadius.circular(StaffUi.controlRadius),
            border:
                Border.all(color: (selected || busy) ? color : StaffUi.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy) ...[
                const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 5),
              ] else if (selected) ...[
                const Icon(Icons.check_rounded, size: 15, color: Colors.white),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color:
                      (selected || busy) ? Colors.white : StaffUi.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Reported By", from the office's side.
///
/// There is no name to show here for ANY report: `staff_reports_view` nulls the
/// reporter for anonymous rows in the database, and the staff console never
/// fetches a profile for the rest. So this states what is actually known rather
/// than borrowing the admin's identity block, which would imply a name is being
/// withheld from the screen when there isn't one to withhold.
class _ReporterBlock extends StatelessWidget {
  final bool isAnonymous;
  const _ReporterBlock({required this.isAnonymous});

  @override
  Widget build(BuildContext context) {
    final color = isAnonymous ? kAnonColor : StaffUi.textMuted;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isAnonymous ? kAnonColor.withValues(alpha: 0.07) : StaffUi.subtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color:
              isAnonymous ? kAnonColor.withValues(alpha: 0.30) : StaffUi.border,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Icon(
              isAnonymous ? Icons.visibility_off_rounded : Icons.person_rounded,
              size: 21,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAnonymous ? 'Anonymous reporter' : 'Citizen',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isAnonymous ? kAnonColor : StaffUi.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isAnonymous
                      ? 'Identity withheld and never retrieved'
                      : 'Reporter details stay with the LGU admin',
                  style: const TextStyle(
                    fontSize: 11.5,
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
