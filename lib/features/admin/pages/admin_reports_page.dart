import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../../../core/theme/app_colors.dart';
import '../theme/admin_ui.dart';
import '../providers/admin_reports_provider.dart';
import '../widgets/admin_detail_screen.dart';
import '../widgets/admin_submission_ui.dart';
import '../widgets/admin_snackbar.dart';

// ── Category visuals — the same webp illustrations the citizen form uses ──────
String _categoryAsset(String key) {
  switch (key) {
    case 'road':
      return 'assets/images/report/roadtwo.webp';
    case 'waste':
      return 'assets/images/report/bin.webp';
    case 'drainage':
      return 'assets/images/report/road.webp';
    case 'streetlight':
      return 'assets/images/report/lamppost.webp';
    case 'environment':
      return 'assets/images/report/leaf.webp';
    case 'others':
    default:
      return 'assets/images/report/menu.webp';
  }
}

IconData _categoryIcon(String key) {
  switch (key) {
    case 'road':
      return Icons.add_road_rounded;
    case 'waste':
      return Icons.delete_outline_rounded;
    case 'drainage':
      return Icons.water_drop_rounded;
    case 'streetlight':
      return Icons.lightbulb_rounded;
    case 'environment':
      return Icons.park_rounded;
    default:
      return Icons.flag_rounded;
  }
}

Color _categoryColor(String key) {
  switch (key) {
    case 'road':
      return const Color(0xFF3B82F6);
    case 'waste':
      return const Color(0xFF84CC16);
    case 'drainage':
      return const Color(0xFF06B6D4);
    case 'streetlight':
      return const Color(0xFFF59E0B);
    case 'environment':
      return const Color(0xFF22C55E);
    default:
      return const Color(0xFF64748B);
  }
}

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

class _CategoryIconBox extends StatelessWidget {
  final String categoryKey;
  final double size;
  const _CategoryIconBox(this.categoryKey, {this.size = 40});

  @override
  Widget build(BuildContext context) {
    final c = _categoryColor(categoryKey);
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.16),
      decoration: BoxDecoration(
        color: AdminUi.subtle,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Image.asset(
        _categoryAsset(categoryKey),
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) =>
            Icon(_categoryIcon(categoryKey), size: size * 0.5, color: c),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Page
// ═════════════════════════════════════════════════════════════════════════════

class AdminReportsPage extends ConsumerStatefulWidget {
  const AdminReportsPage({super.key});

  @override
  ConsumerState<AdminReportsPage> createState() => _AdminReportsPageState();
}

class _AdminReportsPageState extends ConsumerState<AdminReportsPage> {
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

  Future<void> _changeStatus(AdminReport r, ReportStatus next) async {
    await ref.read(adminReportsProvider.notifier).updateStatus(r.id, next);
    if (!mounted) return;
    showAdminSnackBar(context, '${r.shortId} → ${reportStatusLabel(next)}',
        type: AdminSnackType.success);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(adminReportsProvider);
    final notifier = ref.read(adminReportsProvider.notifier);
    final filters = notifier.filters;
    final pad = MediaQuery.of(context).size.width < 600 ? 16.0 : 24.0;

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
                  onOpen: _openDetail,
                  onChange: _changeStatus,
                  onRetry: () =>
                      ref.read(adminReportsProvider.notifier).refresh(),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Reports',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: AdminUi.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Text('$total report${total == 1 ? '' : 's'}',
                style: const TextStyle(fontSize: 13, color: AdminUi.textMuted)),
            const Text('  ·  ', style: TextStyle(color: AdminUi.textMuted)),
            Icon(Icons.visibility_off_rounded,
                size: 13, color: highAnon ? AppColors.orange : kAnonColor),
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
      ],
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

// ── Active chips ──────────────────────────────────────────────────────────────

class _ActiveChips extends StatelessWidget {
  final ReportFilters filters;
  final AdminReportsNotifier notifier;
  const _ActiveChips({required this.filters, required this.notifier});

  @override
  Widget build(BuildContext context) {
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
  final void Function(AdminReport) onOpen;
  final Future<void> Function(AdminReport, ReportStatus) onChange;
  final VoidCallback onRetry;
  const _Results({
    required this.async,
    required this.onOpen,
    required this.onChange,
    required this.onRetry,
  });

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
            return const AdminResultsMessage(
              icon: Icons.inbox_rounded,
              color: AdminUi.textMuted,
              text: 'No reports match your filters.',
            );
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 720) {
                return Column(
                  children: [
                    const _TableHeader(),
                    for (final r in items)
                      _TableRow(
                        report: r,
                        onOpen: () => onOpen(r),
                        onChange: onChange,
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
                        report: r,
                        onOpen: () => onOpen(r),
                        onChange: onChange,
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

// ── Status menu ───────────────────────────────────────────────────────────────

class _StatusMenu extends StatelessWidget {
  final ReportStatus current;
  final ValueChanged<ReportStatus> onChange;
  const _StatusMenu({required this.current, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<ReportStatus>(
      tooltip: 'Change status',
      icon: const Icon(Icons.more_horiz_rounded, size: 18, color: AdminUi.textMuted),
      onSelected: onChange,
      itemBuilder: (context) => [
        for (final s in ReportStatus.values)
          if (s != current)
            PopupMenuItem(
              value: s,
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _statusColor(s),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('Mark ${reportStatusLabel(s)}'),
                ],
              ),
            ),
      ],
    );
  }
}

// ── Wide table ──────────────────────────────────────────────────────────────────

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
          _HCell('CATEGORY', flex: 4),
          _HCell('SUBMITTER', flex: 3),
          _HCell('BARANGAY', flex: 2),
          _HCell('STATUS', flex: 2),
          _HCell('DATE', flex: 2),
          SizedBox(width: 30),
          SizedBox(width: 40),
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
  final Future<void> Function(AdminReport, ReportStatus) onChange;
  const _TableRow({
    required this.report,
    required this.onOpen,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final r = report;
    return InkWell(
      onTap: onOpen,
      child: Container(
        decoration: BoxDecoration(
          color: r.isAnonymous ? kAnonColor.withValues(alpha: 0.035) : null,
          border: const Border(bottom: BorderSide(color: AdminUi.border)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  _CategoryIconBox(r.categoryKey, size: 30),
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
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: SubmitterInline(
                isAnonymous: r.isAnonymous,
                name: r.submitterName,
                role: r.submitterRole,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                (r.barangay == null || r.barangay!.isEmpty) ? '—' : r.barangay!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: AdminUi.textMuted),
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: StatusPill(
                  label: reportStatusLabel(r.status),
                  color: _statusColor(r.status),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                adminShortDate(r.createdAt),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AdminUi.textMuted),
              ),
            ),
            SizedBox(width: 30, child: _MediaCount(r.mediaCount)),
            SizedBox(
              width: 40,
              child: _StatusMenu(
                current: r.status,
                onChange: (next) => onChange(r, next),
              ),
            ),
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
        Text('$count',
            style: const TextStyle(fontSize: 11, color: AdminUi.textMuted)),
      ],
    );
  }
}

// ── Narrow card ────────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final AdminReport report;
  final VoidCallback onOpen;
  final Future<void> Function(AdminReport, ReportStatus) onChange;
  const _Card({
    required this.report,
    required this.onOpen,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final r = report;
    return SubmissionListCard(
      isAnonymous: r.isAnonymous,
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _CategoryIconBox(r.categoryKey, size: 38),
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
              _StatusMenu(
                current: r.status,
                onChange: (next) => onChange(r, next),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SubmitterInline(
            isAnonymous: r.isAnonymous,
            name: r.submitterName,
            role: r.submitterRole,
          ),
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
  late Future<List<ReportMedia>> _mediaFuture;

  @override
  void initState() {
    super.initState();
    _status = widget.report.status;
    _mediaFuture =
        ref.read(adminReportsProvider.notifier).fetchMedia(widget.report.id);
  }

  Future<void> _changeStatus(ReportStatus next) async {
    if (next == _status) return;
    await ref
        .read(adminReportsProvider.notifier)
        .updateStatus(widget.report.id, next);
    if (!mounted) return;
    setState(() => _status = next);
    showAdminSnackBar(context, 'Status → ${reportStatusLabel(next)}',
        type: AdminSnackType.success);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    final size = MediaQuery.of(context).size;
    final narrow = size.width < 640;

    // Rich header — the category icon + title + id + status. The X only shows
    // in the wide dialog; the narrow full-screen page uses the chevron header.
    Widget richHeader({required bool showClose}) => Padding(
          padding: EdgeInsets.fromLTRB(20, showClose ? 18 : 12, 12, 12),
          child: Row(
            children: [
              _CategoryIconBox(r.categoryKey, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.category,
                        style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: AdminUi.textPrimary)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(r.shortId,
                            style: const TextStyle(
                                fontSize: 12, color: AdminUi.textMuted)),
                        const SizedBox(width: 8),
                        StatusPill(
                          label: reportStatusLabel(_status),
                          color: _statusColor(_status),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (showClose)
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                  color: AdminUi.textMuted,
                ),
            ],
          ),
        );

    final scrollContent = SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SubmitterBlock(
            isAnonymous: r.isAnonymous,
            name: r.submitterName,
            photoUrl: r.submitterPhotoUrl,
            role: r.submitterRole,
          ),
          const SizedBox(height: 20),
          _sectionTitle('REPORT DETAILS'),
          const SizedBox(height: 8),
          Text(
            r.remarks.trim().isEmpty ? '—' : r.remarks,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: AdminUi.textPrimary,
            ),
          ),
          const SizedBox(height: 20),
          _sectionTitle('LOCATION'),
          const SizedBox(height: 8),
          _LocationBlock(report: r),
          const SizedBox(height: 20),
          _sectionTitle('ATTACHMENTS'),
          const SizedBox(height: 10),
          _MediaGallery(future: _mediaFuture),
        ],
      ),
    );

    final footer = _StatusFooter(current: _status, onChange: _changeStatus);

    // Narrow → full-screen page: chevron header, rich header, content, footer.
    if (narrow) {
      return AdminDetailScaffold(
        title: 'Report details',
        child: Column(
          children: [
            richHeader(showClose: false),
            const Divider(height: 1, color: AdminUi.border),
            Expanded(child: scrollContent),
            const Divider(height: 1, color: AdminUi.border),
            footer,
          ],
        ),
      );
    }

    // Wide → centered dialog card.
    return Dialog(
      backgroundColor: AdminUi.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            richHeader(showClose: true),
            const Divider(height: 1, color: AdminUi.border),
            Flexible(child: scrollContent),
            const Divider(height: 1, color: AdminUi.border),
            footer,
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: AdminUi.textMuted,
        ),
      );
}

class _StatusFooter extends StatelessWidget {
  final ReportStatus current;
  final ValueChanged<ReportStatus> onChange;
  const _StatusFooter({required this.current, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      color: AdminUi.subtle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flag_rounded, size: 14, color: AdminUi.textMuted),
              const SizedBox(width: 6),
              const Text(
                'SET STATUS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: AdminUi.textMuted,
                ),
              ),
              const SizedBox(width: 8),
              StatusPill(
                label: reportStatusLabel(current),
                color: _statusColor(current),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in ReportStatus.values)
                _StatusChoice(
                  label: reportStatusLabel(s),
                  color: _statusColor(s),
                  selected: s == current,
                  onTap: () => onChange(s),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusChoice extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _StatusChoice({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.14) : AdminUi.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? color : AdminUi.border,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // A colour dot keeps every status distinguishable even when it's
              // not the selected one, so the row no longer reads as a flat wall
              // of grey chips.
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: selected ? color : AdminUi.textSecondary,
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 5),
                Icon(Icons.check_rounded, size: 14, color: color),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LocationBlock extends StatelessWidget {
  final AdminReport report;
  const _LocationBlock({required this.report});

  @override
  Widget build(BuildContext context) {
    final r = report;
    final rows = <Widget>[];
    void add(IconData icon, String value) {
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: AppColors.primaryBlue),
            const SizedBox(width: 8),
            Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 13, color: AdminUi.textPrimary)),
            ),
          ],
        ),
      ));
    }

    final barangay =
        (r.barangay == null || r.barangay!.isEmpty) ? null : r.barangay!;
    final address =
        (r.address == null || r.address!.isEmpty) ? null : r.address!;
    if (barangay != null) add(Icons.location_city_rounded, barangay);
    if (address != null) add(Icons.signpost_rounded, address);
    if (rows.isEmpty) {
      return const Text('No location provided.',
          style: TextStyle(fontSize: 13, color: AdminUi.textMuted));
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AdminUi.subtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminUi.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows),
    );
  }
}

// ── Media gallery + viewers ────────────────────────────────────────────────────

class _MediaGallery extends StatelessWidget {
  final Future<List<ReportMedia>> future;
  const _MediaGallery({required this.future});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ReportMedia>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 90,
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final media = snap.data ?? const <ReportMedia>[];
        if (media.isEmpty) {
          return const Text('No attachments.',
              style: TextStyle(fontSize: 13, color: AdminUi.textMuted));
        }
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [for (final m in media) _MediaThumb(item: m)],
        );
      },
    );
  }
}

class _MediaThumb extends StatelessWidget {
  final ReportMedia item;
  const _MediaThumb({required this.item});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (item.isVideo) {
          showDialog(
            context: context,
            barrierColor: Colors.black87,
            builder: (_) => _NetworkVideoDialog(url: item.url),
          );
        } else {
          showDialog(
            context: context,
            barrierColor: Colors.black87,
            builder: (_) => _FullscreenImageDialog(url: item.url),
          );
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 92,
          height: 92,
          color: AdminUi.subtle,
          child: item.isVideo
              ? Stack(
                  fit: StackFit.expand,
                  children: const [
                    ColoredBox(color: Color(0xFF1F2937)),
                    Center(
                      child: Icon(Icons.play_circle_fill_rounded,
                          color: Colors.white70, size: 34),
                    ),
                    Positioned(
                      left: 5,
                      bottom: 5,
                      child: Icon(Icons.videocam_rounded,
                          size: 14, color: Colors.white70),
                    ),
                  ],
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      item.url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(
                          Icons.broken_image_rounded,
                          color: AdminUi.textMuted,
                          size: 22),
                    ),
                    Positioned(
                      right: 5,
                      bottom: 5,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(Icons.zoom_in_rounded,
                            size: 13, color: Colors.white),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _FullscreenImageDialog extends StatelessWidget {
  final String url;
  const _FullscreenImageDialog({required this.url});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              child: Image.network(url, fit: BoxFit.contain),
            ),
          ),
          Positioned(
            top: 40,
            right: 16,
            child: _CloseButton(onTap: () => Navigator.pop(context)),
          ),
        ],
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CloseButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.close_rounded, color: Colors.white),
      ),
    );
  }
}

class _NetworkVideoDialog extends StatefulWidget {
  final String url;
  const _NetworkVideoDialog({required this.url});

  @override
  State<_NetworkVideoDialog> createState() => _NetworkVideoDialogState();
}

class _NetworkVideoDialogState extends State<_NetworkVideoDialog> {
  late VideoPlayerController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _controller.play();
    }).catchError((Object e) {
      debugPrint('Video init error: $e');
      return null;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        children: [
          Center(
            child: _ready
                ? AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: VideoPlayer(_controller),
                  )
                : const CircularProgressIndicator(color: Colors.white),
          ),
          if (_ready)
            Center(
              child: GestureDetector(
                onTap: () => setState(() {
                  _controller.value.isPlaying
                      ? _controller.pause()
                      : _controller.play();
                }),
                child: Container(
                  color: Colors.transparent,
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
            ),
          if (_ready)
            Positioned(
              bottom: 60,
              left: 16,
              right: 16,
              child: VideoProgressIndicator(
                _controller,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: Colors.white,
                  bufferedColor: Colors.white38,
                  backgroundColor: Colors.white24,
                ),
              ),
            ),
          Positioned(
            top: 40,
            right: 16,
            child: _CloseButton(onTap: () => Navigator.pop(context)),
          ),
        ],
      ),
    );
  }
}
