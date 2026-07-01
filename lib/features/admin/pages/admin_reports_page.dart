import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../theme/admin_ui.dart';
import '../providers/admin_reports_provider.dart';
import '../widgets/admin_skeleton.dart';
import '../widgets/admin_snackbar.dart';

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

  Future<void> _changeStatus(AdminReport r, ReportStatus next) async {
    await ref.read(adminReportsProvider.notifier).updateStatus(r.id, next);
    if (!mounted) return;
    showAdminSnackBar(
      context,
      '${r.shortId} → ${reportStatusLabel(next)}',
      type: AdminSnackType.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(adminReportsProvider);
    final filters = ref.read(adminReportsProvider.notifier).filters;

    return RefreshIndicator(
      onRefresh: () => ref.read(adminReportsProvider.notifier).refresh(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeaderLine(async),
                const SizedBox(height: 16),
                _buildToolbar(filters),
                const SizedBox(height: 16),
                _buildResults(async),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderLine(AsyncValue<List<AdminReport>> async) {
    final count = async.valueOrNull?.length;
    final text = count == null
        ? 'Citizen-submitted issue reports'
        : '$count report${count == 1 ? '' : 's'}';
    return Text(
      text,
      style: const TextStyle(fontSize: 13, color: AppColors.hint),
    );
  }

  // ── Toolbar ────────────────────────────────────────────────────────────────
  Widget _buildToolbar(ReportFilters filters) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 280,
          child: TextField(
            controller: _searchCtrl,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search barangay, address, remarks…',
              hintStyle: const TextStyle(fontSize: 13, color: AppColors.hint),
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              suffixIcon: _searchCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16),
                      onPressed: () {
                        _searchCtrl.clear();
                        ref.read(adminReportsProvider.notifier).setQuery('');
                        setState(() {});
                      },
                    ),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AdminUi.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AdminUi.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.primaryBlue),
              ),
            ),
          ),
        ),
        _FilterBox(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<ReportStatus?>(
              value: filters.status,
              isDense: true,
              borderRadius: BorderRadius.circular(10),
              hint: const Text('All status', style: _ddStyle),
              items: <DropdownMenuItem<ReportStatus?>>[
                const DropdownMenuItem(
                  value: null,
                  child: Text('All status', style: _ddStyle),
                ),
                for (final s in ReportStatus.values)
                  DropdownMenuItem(
                    value: s,
                    child: Text(reportStatusLabel(s), style: _ddStyle),
                  ),
              ],
              onChanged: (s) =>
                  ref.read(adminReportsProvider.notifier).setStatus(s),
            ),
          ),
        ),
        _FilterBox(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<ReportSort>(
              value: filters.sort,
              isDense: true,
              borderRadius: BorderRadius.circular(10),
              items: const [
                DropdownMenuItem(
                  value: ReportSort.newest,
                  child: Text('Newest', style: _ddStyle),
                ),
                DropdownMenuItem(
                  value: ReportSort.oldest,
                  child: Text('Oldest', style: _ddStyle),
                ),
              ],
              onChanged: (s) {
                if (s != null) {
                  ref.read(adminReportsProvider.notifier).setSort(s);
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  // ── Results ────────────────────────────────────────────────────────────────
  Widget _buildResults(AsyncValue<List<AdminReport>> async) {
    return _Card(
      padding: EdgeInsets.zero,
      child: async.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(16),
          child: AdminShimmer(
            child: Column(
              children: [
                _RowSkeleton(),
                _RowSkeleton(),
                _RowSkeleton(),
                _RowSkeleton(),
                _RowSkeleton(),
              ],
            ),
          ),
        ),
        error: (e, _) => _ResultsMessage(
          icon: Icons.cloud_off_rounded,
          color: AppColors.red,
          text: 'Couldn\'t load reports.',
          action: TextButton(
            onPressed: () => ref.read(adminReportsProvider.notifier).refresh(),
            child: const Text('Retry'),
          ),
        ),
        data: (reports) {
          if (reports.isEmpty) {
            return const _ResultsMessage(
              icon: Icons.inbox_rounded,
              color: AppColors.hint,
              text: 'No reports match your filters.',
            );
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 720;
              if (wide) {
                return Column(
                  children: [
                    const _TableHeader(),
                    for (final r in reports)
                      _TableRow(report: r, onChange: _changeStatus),
                  ],
                );
              }
              return Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    for (final r in reports)
                      _ReportCard(report: r, onChange: _changeStatus),
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

// ── Status visuals ─────────────────────────────────────────────────────────

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

class _StatusPill extends StatelessWidget {
  final ReportStatus status;
  const _StatusPill(this.status);

  @override
  Widget build(BuildContext context) {
    final c = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        reportStatusLabel(status),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c),
      ),
    );
  }
}

class _StatusMenu extends StatelessWidget {
  final AdminReport report;
  final Future<void> Function(AdminReport, ReportStatus) onChange;
  const _StatusMenu({required this.report, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<ReportStatus>(
      tooltip: 'Change status',
      icon: const Icon(
        Icons.more_horiz_rounded,
        size: 18,
        color: AppColors.hint,
      ),
      onSelected: (s) => onChange(report, s),
      itemBuilder: (context) => [
        for (final s in ReportStatus.values)
          if (s != report.status)
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

// ── Wide table ───────────────────────────────────────────────────────────────

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AdminUi.border)),
      ),
      child: Row(
        children: const [
          _HCell('REF', flex: 2),
          _HCell('CATEGORY', flex: 3),
          _HCell('BARANGAY', flex: 2),
          _HCell('STATUS', flex: 2),
          _HCell('DATE', flex: 2),
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
          color: AppColors.hint,
        ),
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  final AdminReport report;
  final Future<void> Function(AdminReport, ReportStatus) onChange;
  const _TableRow({required this.report, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AdminUi.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              report.shortId,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              report.category,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              (report.barangay == null || report.barangay!.isEmpty)
                  ? '—'
                  : report.barangay!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: AppColors.hint),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _StatusPill(report.status),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _shortDate(report.createdAt),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.hint),
            ),
          ),
          SizedBox(
            width: 40,
            child: _StatusMenu(report: report, onChange: onChange),
          ),
        ],
      ),
    );
  }
}

// ── Narrow card ──────────────────────────────────────────────────────────────

class _ReportCard extends StatelessWidget {
  final AdminReport report;
  final Future<void> Function(AdminReport, ReportStatus) onChange;
  const _ReportCard({required this.report, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AdminUi.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  report.category,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ),
              _StatusPill(report.status),
              _StatusMenu(report: report, onChange: onChange),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              report.shortId,
              if (report.barangay != null && report.barangay!.isNotEmpty)
                report.barangay!,
              _shortDate(report.createdAt),
            ].join('  ·  '),
            style: const TextStyle(fontSize: 12, color: AppColors.hint),
          ),
          if (report.remarks.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              report.remarks,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.black87),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Shared bits ──────────────────────────────────────────────────────────────

const TextStyle _ddStyle = TextStyle(fontSize: 13, color: Colors.black87);

class _FilterBox extends StatelessWidget {
  final Widget child;
  const _FilterBox({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AdminUi.border),
      ),
      child: child,
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _Card({required this.child, this.padding = const EdgeInsets.all(20)});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AdminUi.cardRadius),
        border: Border.all(color: AdminUi.border),
      ),
      child: child,
    );
  }
}

class _ResultsMessage extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  final Widget? action;
  const _ResultsMessage({
    required this.icon,
    required this.color,
    required this.text,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: color),
            const SizedBox(height: 10),
            Text(
              text,
              style: const TextStyle(fontSize: 13, color: AppColors.hint),
            ),
            if (action != null) ...[const SizedBox(height: 8), action!],
          ],
        ),
      ),
    );
  }
}

class _RowSkeleton extends StatelessWidget {
  const _RowSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: const [
          Expanded(flex: 2, child: _Bar(width: 60)),
          Expanded(flex: 3, child: _Bar(width: 120)),
          Expanded(flex: 2, child: _Bar(width: 80)),
          Expanded(flex: 2, child: _Bar(width: 70)),
          Expanded(flex: 2, child: _Bar(width: 70)),
          SizedBox(width: 40),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final double width;
  const _Bar({required this.width});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SkeletonBox(width: width, height: 11),
    );
  }
}

String _shortDate(DateTime? t) {
  if (t == null) return '—';
  const months = [
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
  return '${months[t.month - 1]} ${t.day}, ${t.year}';
}
