import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/deeplink_highlight.dart';
import '../../../core/widgets/media_source_badge.dart';
import '../../../core/widgets/report_work_log.dart';
import '../../../core/widgets/resolution_media.dart';
import '../../admin/providers/admin_reports_provider.dart'
    show ReportStatus, reportStatusLabel;
import '../data/staff_repository.dart';
import '../providers/staff_providers.dart';
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
  @override
  Widget build(BuildContext context) {
    final async = widget.async;
    final onRefresh = widget.onRefresh;
    final emptyIcon = widget.emptyIcon;
    final emptyTitle = widget.emptyTitle;
    final emptySubtitle = widget.emptySubtitle;

    // Rows exist only once the fetch resolves — flash the deep-link target then.
    if (async.hasValue) flashHighlightOnce(widget.highlightId);

    return StaffPageBody(
      onRefresh: onRefresh,
      child: async.when(
        loading: () => const Padding(
          padding: EdgeInsets.only(top: 80),
          child: Center(
            child: CircularProgressIndicator(color: StaffUi.accent),
          ),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.only(top: 60),
          child: StaffErrorState(
            message: "Couldn't load reports.",
            onRetry: onRefresh,
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Padding(
              padding: const EdgeInsets.only(top: 40),
              child: StaffEmptyState(
                icon: emptyIcon,
                title: emptyTitle,
                subtitle: emptySubtitle,
              ),
            );
          }
          return Column(
            children: [
              for (final r in items)
                Padding(
                  key: highlightKey(r.id),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ReportRow(
                    report: r,
                    onTap: () => _openDetail(context, r),
                    highlighted: isHighlighted(r.id),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  void _openDetail(BuildContext context, StaffReport r) {
    final narrow = MediaQuery.of(context).size.width < 600;
    final sheet = _ReportDetailSheet(
      report: r,
      endorsement: widget.endorsement,
      department: widget.department,
      onSetStatus: widget.onSetStatus,
      onReturnToTriage: widget.onReturnToTriage,
    );
    if (narrow) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => sheet,
      );
    } else {
      showAppDialog(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.45),
        builder: (_) => Center(
          child: Padding(padding: const EdgeInsets.all(24), child: sheet),
        ),
      );
    }
  }
}

class _ReportRow extends StatelessWidget {
  final StaffReport report;
  final VoidCallback onTap;

  /// Set when this row is the deep-link target: it flashes, then fades back.
  /// Drawn as a ring around StaffCard rather than replacing its decoration, so
  /// the card keeps its own surface treatment.
  final bool highlighted;
  const _ReportRow({
    required this.report,
    required this.onTap,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final r = report;
    return highlightRing(
      highlighted: highlighted,
      radius: 14,
      accent: StaffUi.accent,
      child: StaffCard(
        onTap: onTap,
        padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: StaffUi.accentWash,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.report_gmailerrorred_rounded,
                color: StaffUi.accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        r.category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: StaffUi.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('#${r.shortId}',
                        style: const TextStyle(
                            fontSize: 11, color: StaffUi.textMuted)),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  r.remarks.isEmpty ? 'No description' : r.remarks,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: StaffUi.textSecondary),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    StaffStatusPill(r.status),
                    const SizedBox(width: 8),
                    if (r.isOverdue) ...[
                      StaffPill(
                        label: 'Overdue ${r.ageDays}d',
                        color: const Color(0xFFF59E0B),
                        icon: Icons.schedule_rounded,
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (r.isAnonymous) ...[
                      const StaffPill(
                        label: 'Anonymous',
                        color: StaffUi.textMuted,
                        icon: Icons.visibility_off_rounded,
                      ),
                      const SizedBox(width: 8),
                    ],
                    if ((r.barangay ?? '').isNotEmpty) ...[
                      const Icon(Icons.location_on_outlined,
                          size: 13, color: StaffUi.textMuted),
                      const SizedBox(width: 2),
                      Flexible(
                        child: Text(
                          r.barangay!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11.5, color: StaffUi.textMuted),
                        ),
                      ),
                    ],
                    const Spacer(),
                    if (r.mediaCount > 0) ...[
                      const Icon(Icons.photo_library_outlined,
                          size: 13, color: StaffUi.textMuted),
                      const SizedBox(width: 2),
                      Text('${r.mediaCount}',
                          style: const TextStyle(
                              fontSize: 11.5, color: StaffUi.textMuted)),
                      const SizedBox(width: 8),
                    ],
                    Text(staffAgo(r.createdAt),
                        style: const TextStyle(
                            fontSize: 11, color: StaffUi.textMuted)),
                  ],
                ),
              ],
            ),
          ),
          ],
        ),
      ),
    );
  }
}

class _ReportDetailSheet extends StatefulWidget {
  final StaffReport report;
  final bool endorsement;
  final String? department;
  final _SetStatus onSetStatus;
  final _ReturnToTriage onReturnToTriage;
  const _ReportDetailSheet({
    required this.report,
    required this.endorsement,
    required this.department,
    required this.onSetStatus,
    required this.onReturnToTriage,
  });

  @override
  State<_ReportDetailSheet> createState() => _ReportDetailSheetState();
}

class _ReportDetailSheetState extends State<_ReportDetailSheet> {
  late ReportStatus _status = widget.report.status;
  bool _busy = false;

  // Staff own the WORKING states only. Triage states (pending / rejected) belong
  // to the admin — a report only reaches staff once accepted (under_review+).
  static const _flow = [
    ReportStatus.underReview,
    ReportStatus.inProgress,
    ReportStatus.resolved,
  ];

  Future<void> _apply(ReportStatus s) async {
    if (s == _status || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.onSetStatus(widget.report.id, s);
      if (mounted) {
        setState(() {
          _status = s;
          _busy = false;
        });
        showAppSnackBar(context, 'Status set to ${reportStatusLabel(s)}.',
            type: AppSnackType.success);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showAppSnackBar(context, '$e', type: AppSnackType.error);
      }
    }
  }

  Future<void> _returnToTriage() async {
    final reason = await _showReturnDialog(context);
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.onReturnToTriage(widget.report.id, reason);
      if (!mounted) return;
      setState(() => _busy = false);
      Navigator.pop(context);
      showAppSnackBar(context, 'Returned to the admin for re-routing.',
          type: AppSnackType.success);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showAppSnackBar(context, '$e', type: AppSnackType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    final narrow = MediaQuery.of(context).size.width < 600;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (narrow)
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: StaffUi.borderStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.category,
                        style: const TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                          color: StaffUi.textPrimary,
                        )),
                    const SizedBox(height: 2),
                    Text('#${r.shortId} · ${staffAgo(r.createdAt)}',
                        style: const TextStyle(
                            fontSize: 12, color: StaffUi.textMuted)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: StaffUi.textMuted),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: StaffUi.border),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (widget.endorsement && r.endorsedToDepartment != null)
                      StaffPill(
                        label: 'Endorsed to ${r.endorsedToDepartment}',
                        color: StaffUi.accent,
                        icon: Icons.forward_to_inbox_rounded,
                      ),
                    if (r.isAnonymous)
                      const StaffPill(
                        label: 'Anonymous reporter',
                        color: StaffUi.textMuted,
                        icon: Icons.visibility_off_rounded,
                      ),
                  ],
                ),
                if (widget.endorsement && r.endorsedToDepartment != null ||
                    r.isAnonymous)
                  const SizedBox(height: 12),
                const _Label('Description'),
                const SizedBox(height: 4),
                Text(r.remarks.isEmpty ? 'No description provided.' : r.remarks,
                    style: const TextStyle(
                        fontSize: 13.5, color: StaffUi.textSecondary, height: 1.4)),
                const SizedBox(height: 14),
                if ((r.address ?? r.barangay) != null) ...[
                  const _Label('Location'),
                  const SizedBox(height: 4),
                  Text(
                    [r.address, r.barangay]
                        .where((e) => (e ?? '').isNotEmpty)
                        .join(', '),
                    style: const TextStyle(
                        fontSize: 13.5, color: StaffUi.textSecondary),
                  ),
                  const SizedBox(height: 14),
                ],
                if (r.mediaCount > 0) ...[
                  const _Label('Attachments'),
                  const SizedBox(height: 6),
                  _MediaStrip(reportId: r.id),
                  const SizedBox(height: 14),
                ],
                const _Label('Update status'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in _flow)
                      ChoiceChip(
                        label: Text(reportStatusLabel(s)),
                        selected: _status == s,
                        onSelected: _busy ? null : (_) => _apply(s),
                        labelStyle: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: _status == s
                              ? Colors.white
                              : StaffUi.textSecondary,
                        ),
                        selectedColor: staffReportStatusColor(s),
                        backgroundColor: StaffUi.subtle,
                        side: BorderSide(
                          color: _status == s
                              ? staffReportStatusColor(s)
                              : StaffUi.border,
                        ),
                        showCheckmark: false,
                      ),
                  ],
                ),
                if (_status == ReportStatus.resolved) ...[
                  const SizedBox(height: 16),
                  ResolutionMediaSection(reportId: r.id, canEdit: true),
                ],
                const SizedBox(height: 16),
                const _Label('Work log'),
                const SizedBox(height: 6),
                const Text(
                  'Log progress or reply to the admin. The citizen never sees this.',
                  style: TextStyle(fontSize: 12, color: StaffUi.textMuted, height: 1.4),
                ),
                const SizedBox(height: 8),
                ReportWorkLog(
                  reportId: r.id,
                  authorRole: 'staff',
                  authorName: widget.department ?? 'Staff',
                ),
                const SizedBox(height: 16),
                const Divider(height: 1, color: StaffUi.border),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _busy ? null : _returnToTriage,
                    icon: const Icon(Icons.reply_rounded, size: 17),
                    label: const Text('Not my department — return to triage'),
                    style: TextButton.styleFrom(
                      foregroundColor: StaffUi.textMuted,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );

    return Material(
      color: StaffUi.surface,
      borderRadius: narrow
          ? const BorderRadius.vertical(top: Radius.circular(22))
          : BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: narrow
          ? SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.9,
                ),
                child: content,
              ),
            )
          : ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
              child: content,
            ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: StaffUi.textMuted,
        ),
      );
}

class _MediaStrip extends ConsumerWidget {
  final String reportId;
  const _MediaStrip({required this.reportId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(staffRepoProvider);
    return FutureBuilder<List<StaffReportMedia>>(
      future: repo.fetchReportMedia(reportId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 90,
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child:
                    CircularProgressIndicator(strokeWidth: 2, color: StaffUi.accent),
              ),
            ),
          );
        }
        final media = snap.data ?? const [];
        if (media.isEmpty) {
          return const Text('No attachments could be loaded.',
              style: TextStyle(fontSize: 12.5, color: StaffUi.textMuted));
        }
        return SizedBox(
          height: 90,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: media.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final m = media[i];
              return ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 120,
                  height: 90,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      m.isVideo
                          ? Container(
                              color: StaffUi.subtle,
                              child: const Icon(
                                  Icons.play_circle_outline_rounded,
                                  color: StaffUi.accent,
                                  size: 30),
                            )
                          : Image.network(
                              m.url,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                color: StaffUi.subtle,
                                child: const Icon(Icons.broken_image_outlined,
                                    color: StaffUi.textMuted),
                              ),
                            ),
                      Positioned(
                        top: 5,
                        left: 5,
                        child: MediaSourceBadge(verified: m.isGpsVerified),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
