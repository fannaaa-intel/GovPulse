import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../theme/admin_ui.dart';
import '../providers/admin_feedback_provider.dart';
import '../providers/admin_identity_reveal_provider.dart';
import '../widgets/admin_detail_screen.dart';
import '../widgets/admin_moderation.dart';
import '../widgets/admin_submission_ui.dart';
import '../widgets/revealable_submitter.dart';
import '../widgets/admin_snackbar.dart';

const List<String> _kFeedbackTemplates = [
  'Thank you for your feedback.',
  'We\'re sorry about your experience — we\'re looking into it.',
  'Thanks for letting us know. We\'ll use this to improve.',
];

// ── Office visuals — mirror the citizen feedback form ────────────────────────
const Map<String, IconData> _officeIcons = {
  'health': Icons.local_hospital_rounded,
  'mayor': Icons.account_balance_rounded,
  'mpdo': Icons.map_rounded,
  'civil': Icons.assignment_rounded,
  'cert': Icons.task_alt_rounded,
};
const Map<String, Color> _officeColors = {
  'health': Color(0xFFEF4444),
  'mayor': Color(0xFF3B82F6),
  'mpdo': Color(0xFF10B981),
  'civil': Color(0xFFF59E0B),
  'cert': Color(0xFF8B5CF6),
};
IconData _officeIcon(String id) => _officeIcons[id] ?? Icons.business_rounded;
Color _officeColor(String id) => _officeColors[id] ?? AppColors.primaryBlue;

const Color _kStarAmber = Color(0xFFF59E0B);

Color _statusColor(FeedbackStatus s) =>
    s == FeedbackStatus.responded ? AppColors.green : AppColors.orange;

class _OfficeIconBox extends StatelessWidget {
  final String officeId;
  final double size;
  const _OfficeIconBox(this.officeId, {this.size = 30});

  @override
  Widget build(BuildContext context) {
    final c = _officeColor(officeId);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Icon(_officeIcon(officeId), size: size * 0.55, color: c),
    );
  }
}

/// A row of 5 stars; 1-2★ tints red/orange so poor experiences jump out.
class _StarRow extends StatelessWidget {
  final int rating;
  final double size;
  const _StarRow({required this.rating, this.size = 15});

  @override
  Widget build(BuildContext context) {
    final Color c = rating <= 1
        ? AppColors.red
        : rating == 2
            ? AppColors.orange
            : _kStarAmber;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            i <= rating ? Icons.star_rounded : Icons.star_outline_rounded,
            size: size,
            color: i <= rating ? c : AdminUi.border,
          ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Page
// ═════════════════════════════════════════════════════════════════════════════

class AdminFeedbackPage extends ConsumerStatefulWidget {
  const AdminFeedbackPage({super.key});

  @override
  ConsumerState<AdminFeedbackPage> createState() => _AdminFeedbackPageState();
}

class _AdminFeedbackPageState extends ConsumerState<AdminFeedbackPage> {
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
      ref.read(adminFeedbackProvider.notifier).setQuery(value);
    });
  }

  int _activeFilterCount(FeedbackFilters f) {
    var n = 0;
    if (f.officeId != null) n++;
    if (f.ratingBand != null) n++;
    if (f.status != null) n++;
    if (f.sort != FeedbackSort.newest) n++;
    if (f.anonymousOnly) n++;
    if (f.showDismissed) n++;
    return n;
  }

  void _openFilters() {
    final notifier = ref.read(adminFeedbackProvider.notifier);
    openAdminFilterSheet(
      context,
      title: 'Filter feedback',
      onReset: () {
        notifier.setOffice(null);
        notifier.setRatingBand(null);
        notifier.setStatus(null);
        notifier.setSort(FeedbackSort.newest);
        if (notifier.filters.anonymousOnly) notifier.toggleAnonymousOnly();
        notifier.setShowDismissed(false);
      },
      content: Consumer(
        builder: (context, ref, _) {
          ref.watch(adminFeedbackProvider);
          final f = ref.read(adminFeedbackProvider.notifier).filters;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FilterChoiceRow<String>(
                label: 'Office',
                value: f.officeId,
                options: [
                  (value: null, text: 'All'),
                  for (final o in kFeedbackOffices)
                    (value: o.id, text: o.label),
                ],
                onSelected: (v) => notifier.setOffice(v),
              ),
              const SizedBox(height: 18),
              FilterChoiceRow<RatingBand>(
                label: 'Rating',
                value: f.ratingBand,
                options: const [
                  (value: null, text: 'All'),
                  (value: RatingBand.low, text: 'Low (1-2★)'),
                  (value: RatingBand.high, text: 'High (4-5★)'),
                ],
                onSelected: (v) => notifier.setRatingBand(v),
              ),
              const SizedBox(height: 18),
              FilterChoiceRow<FeedbackStatus>(
                label: 'Status',
                value: f.status,
                options: [
                  (value: null, text: 'All'),
                  for (final s in FeedbackStatus.values)
                    (value: s, text: feedbackStatusLabel(s)),
                ],
                onSelected: (v) => notifier.setStatus(v),
              ),
              const SizedBox(height: 18),
              FilterChoiceRow<FeedbackSort>(
                label: 'Sort',
                value: f.sort,
                options: const [
                  (value: FeedbackSort.newest, text: 'Newest'),
                  (value: FeedbackSort.oldest, text: 'Oldest'),
                ],
                onSelected: (v) {
                  if (v != null) notifier.setSort(v);
                },
              ),
              const SizedBox(height: 18),
              FilterSwitchRow(
                icon: Icons.visibility_off_rounded,
                label: 'Anonymous only',
                subtitle: 'Show only feedback with a withheld identity',
                value: f.anonymousOnly,
                onChanged: (_) => notifier.toggleAnonymousOnly(),
              ),
              const SizedBox(height: 18),
              FilterSwitchRow(
                icon: Icons.block_rounded,
                label: 'Show dismissed',
                subtitle: 'Review spam hidden from the list, analytics & AI',
                value: f.showDismissed,
                onChanged: (v) => notifier.setShowDismissed(v),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openDetail(AdminFeedback f) async {
    await showAdminDetail(
      context,
      builder: (_) => _FeedbackDetailDialog(feedback: f),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(adminFeedbackProvider);
    final notifier = ref.read(adminFeedbackProvider.notifier);
    final filters = notifier.filters;
    final pad = MediaQuery.of(context).size.width < 600 ? 16.0 : 24.0;

    return RefreshIndicator(
      onRefresh: () => ref.read(adminFeedbackProvider.notifier).refresh(),
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
                  onRetry: () =>
                      ref.read(adminFeedbackProvider.notifier).refresh(),
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
  final AsyncValue<List<AdminFeedback>> async;
  final AdminFeedbackNotifier notifier;
  const _Header({required this.async, required this.notifier});

  @override
  Widget build(BuildContext context) {
    if (async.valueOrNull == null) {
      return const Text(
        'Citizen service-satisfaction feedback',
        style: TextStyle(fontSize: 13, color: AdminUi.textMuted),
      );
    }
    final total = notifier.totalCount;
    final avg = notifier.averageRating;
    final low = notifier.lowRatingCount;
    final highLow = total > 0 && low / total > 0.15;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The top bar already shows "Feedback", so no in-content page title.
        Row(
          children: [
            Text('$total feedback',
                style: const TextStyle(fontSize: 13, color: AdminUi.textMuted)),
            const Text('  ·  ', style: TextStyle(color: AdminUi.textMuted)),
            Text(
              total == 0 ? 'no ratings' : 'avg ${avg.toStringAsFixed(1)}★',
              style: const TextStyle(fontSize: 13, color: AdminUi.textMuted),
            ),
            const Text('  ·  ', style: TextStyle(color: AdminUi.textMuted)),
            Text(
              '$low low-rated',
              style: TextStyle(
                fontSize: 13,
                color: highLow ? AppColors.red : AdminUi.textMuted,
                fontWeight: highLow ? FontWeight.w700 : FontWeight.w400,
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
                hint: 'Search comment, service…',
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
  final FeedbackFilters filters;
  final AdminFeedbackNotifier notifier;
  const _ActiveChips({required this.filters, required this.notifier});

  @override
  Widget build(BuildContext context) {
    String? officeLabel;
    if (filters.officeId != null) {
      officeLabel = kFeedbackOffices
          .firstWhere((o) => o.id == filters.officeId,
              orElse: () => const FeedbackOffice('', 'Office'))
          .label;
    }
    final chips = <Widget>[
      if (officeLabel != null)
        ActiveChip(label: officeLabel, onRemove: () => notifier.setOffice(null)),
      if (filters.ratingBand != null)
        ActiveChip(
          label: filters.ratingBand == RatingBand.low
              ? 'Low (1-2★)'
              : 'High (4-5★)',
          onRemove: () => notifier.setRatingBand(null),
        ),
      if (filters.status != null)
        ActiveChip(
          label: feedbackStatusLabel(filters.status!),
          onRemove: () => notifier.setStatus(null),
        ),
      if (filters.sort != FeedbackSort.newest)
        ActiveChip(
          label: 'Oldest first',
          onRemove: () => notifier.setSort(FeedbackSort.newest),
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
  final AsyncValue<List<AdminFeedback>> async;
  final void Function(AdminFeedback) onOpen;
  final VoidCallback onRetry;
  const _Results({
    required this.async,
    required this.onOpen,
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
          text: 'Couldn\'t load feedback.',
          action: TextButton(onPressed: onRetry, child: const Text('Retry')),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const AdminResultsMessage(
              icon: Icons.inbox_rounded,
              color: AdminUi.textMuted,
              text: 'No feedback matches your filters.',
            );
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 720) {
                return Column(
                  children: [
                    const _TableHeader(),
                    for (final f in items)
                      _TableRow(feedback: f, onOpen: () => onOpen(f)),
                  ],
                );
              }
              return Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    for (final f in items)
                      _Card(feedback: f, onOpen: () => onOpen(f)),
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
          _HCell('OFFICE / SERVICE', flex: 4),
          _HCell('RATING', flex: 2),
          _HCell('SUBMITTER', flex: 3),
          _HCell('STATUS', flex: 2),
          _HCell('DATE', flex: 2),
          SizedBox(width: 34),
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
  final AdminFeedback feedback;
  final VoidCallback onOpen;
  const _TableRow({required this.feedback, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final f = feedback;
    return InkWell(
      onTap: onOpen,
      child: Container(
        decoration: BoxDecoration(
          color: f.isAnonymous ? kAnonColor.withValues(alpha: 0.035) : null,
          border: const Border(bottom: BorderSide(color: AdminUi.border)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  _OfficeIconBox(f.officeId),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          f.officeLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AdminUi.textPrimary,
                          ),
                        ),
                        Text(
                          f.serviceName.isEmpty ? f.shortId : f.serviceName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
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
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _StarRow(rating: f.overallRating),
              ),
            ),
            Expanded(
              flex: 3,
              child: SubmitterInline(
                isAnonymous: f.isAnonymous,
                name: f.submitterName,
                role: null,
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: StatusPill(
                  label: feedbackStatusLabel(f.status),
                  color: _statusColor(f.status),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                adminShortDate(f.createdAt),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AdminUi.textMuted),
              ),
            ),
            SizedBox(width: 34, child: _PhotoCount(f.photoCount)),
          ],
        ),
      ),
    );
  }
}

class _PhotoCount extends StatelessWidget {
  final int count;
  const _PhotoCount(this.count);

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox(width: 34);
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
  final AdminFeedback feedback;
  final VoidCallback onOpen;
  const _Card({required this.feedback, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final f = feedback;
    return SubmissionListCard(
      isAnonymous: f.isAnonymous,
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _OfficeIconBox(f.officeId, size: 38),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  f.officeLabel,
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
                label: feedbackStatusLabel(f.status),
                color: _statusColor(f.status),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _StarRow(rating: f.overallRating, size: 16),
              const SizedBox(width: 10),
              Expanded(
                child: SubmitterInline(
                  isAnonymous: f.isAnonymous,
                  name: f.submitterName,
                  role: null,
                ),
              ),
            ],
          ),
          if (f.serviceName.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              f.serviceName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AdminUi.textSecondary,
              ),
            ),
          ],
          if (f.comment != null) ...[
            const SizedBox(height: 4),
            Text(
              f.comment!,
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
              f.shortId,
              adminShortDate(f.createdAt),
              if (f.photoCount > 0)
                '${f.photoCount} photo${f.photoCount == 1 ? '' : 's'}',
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

class _FeedbackDetailDialog extends ConsumerStatefulWidget {
  final AdminFeedback feedback;
  const _FeedbackDetailDialog({required this.feedback});

  @override
  ConsumerState<_FeedbackDetailDialog> createState() =>
      _FeedbackDetailDialogState();
}

class _FeedbackDetailDialogState extends ConsumerState<_FeedbackDetailDialog> {
  late final TextEditingController _noteCtrl;
  late FeedbackStatus _status;
  DateTime? _respondedAt;
  String? _response;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final f = widget.feedback;
    _noteCtrl = TextEditingController(text: f.adminNote ?? '');
    _status = f.status;
    _response = f.adminResponse;
    _respondedAt = f.status == FeedbackStatus.responded ? f.reviewedAt : null;
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _respond(String message) async {
    try {
      await ref
          .read(adminFeedbackProvider.notifier)
          .respond(widget.feedback.id, message);
      if (!mounted) return;
      setState(() {
        _status = FeedbackStatus.responded;
        _respondedAt = DateTime.now();
        _response = message;
      });
      showAdminSnackBar(context, 'Response sent to the citizen.',
          type: AdminSnackType.success);
    } catch (e) {
      if (mounted) {
        showAdminSnackBar(context, e.toString(), type: AdminSnackType.error);
      }
      rethrow;
    }
  }

  Future<void> _saveNote() async {
    try {
      await ref
          .read(adminFeedbackProvider.notifier)
          .saveAdminNote(widget.feedback.id, _noteCtrl.text);
      if (!mounted) return;
      showAdminSnackBar(context, 'Note saved.', type: AdminSnackType.success);
    } catch (_) {
      if (mounted) {
        showAdminSnackBar(context, 'Couldn\'t save the note.',
            type: AdminSnackType.error);
      }
    }
  }

  Future<void> _dismiss() async {
    final reason = await showAdminDismissDialog(context, itemLabel: 'feedback');
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(adminFeedbackProvider.notifier).dismiss(widget.feedback.id, reason);
      if (!mounted) return;
      Navigator.pop(context);
      showAdminSnackBar(context, 'Feedback dismissed — excluded from analytics & AI.',
          type: AdminSnackType.success);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAdminSnackBar(context, 'Could not dismiss: $e', type: AdminSnackType.error);
    }
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    try {
      await ref.read(adminFeedbackProvider.notifier).restore(widget.feedback.id);
      if (!mounted) return;
      Navigator.pop(context);
      showAdminSnackBar(context, 'Feedback restored.', type: AdminSnackType.success);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAdminSnackBar(context, 'Could not restore: $e', type: AdminSnackType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.feedback;
    final size = MediaQuery.of(context).size;
    final narrow = size.width < 640;
    final c = _officeColor(f.officeId);

    final aspects = <MapEntry<String, int>>[
      if (f.aspectStaff != null) MapEntry('Staff attitude', f.aspectStaff!),
      if (f.aspectWait != null) MapEntry('Wait time', f.aspectWait!),
      if (f.aspectClarity != null) MapEntry('Process clarity', f.aspectClarity!),
      if (f.aspectFacility != null) MapEntry('Facility', f.aspectFacility!),
    ];

    // Rich header — X only in the wide dialog; the narrow page uses the chevron.
    Widget richHeader({required bool showClose}) => Padding(
          padding: EdgeInsets.fromLTRB(20, showClose ? 18 : 12, 12, 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_officeIcon(f.officeId), size: 22, color: c),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(f.officeLabel,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AdminUi.textPrimary)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(f.shortId,
                            style: const TextStyle(
                                fontSize: 12, color: AdminUi.textMuted)),
                        const SizedBox(width: 8),
                        StatusPill(
                          label: feedbackStatusLabel(_status),
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
          AdminModerationBar(
            isDismissed: f.isDismissed,
            reason: f.dismissedReason,
            busy: _busy,
            onDismiss: _dismiss,
            onRestore: _restore,
          ),
          const SizedBox(height: 16),
          RevealableSubmitter(
            source: RevealSource.feedback,
            submissionId: f.id,
            isAnonymous: f.isAnonymous,
            name: f.submitterName,
            photoUrl: f.submitterPhotoUrl,
            role: null,
          ),
          const SizedBox(height: 20),
          _sectionTitle('SERVICE'),
          const SizedBox(height: 8),
          Text(f.serviceName.isEmpty ? '—' : f.serviceName,
              style: const TextStyle(
                  fontSize: 13.5, height: 1.4, color: AdminUi.textPrimary)),
          const SizedBox(height: 6),
          Text('Visited · ${adminShortDate(f.visitDate)}',
              style: const TextStyle(fontSize: 12, color: AdminUi.textMuted)),
          const SizedBox(height: 20),
          _sectionTitle('OVERALL RATING'),
          const SizedBox(height: 8),
          Row(
            children: [
              _StarRow(rating: f.overallRating, size: 20),
              const SizedBox(width: 10),
              Text(feedbackRatingLabel(f.overallRating),
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AdminUi.textSecondary)),
            ],
          ),
          if (aspects.isNotEmpty) ...[
            const SizedBox(height: 20),
            _sectionTitle('ASPECT RATINGS'),
            const SizedBox(height: 10),
            _AspectGrid(aspects: aspects),
          ],
          const SizedBox(height: 20),
          _sectionTitle('COMMENT'),
          const SizedBox(height: 8),
          Text(
            f.comment ?? 'No comment provided.',
            style: TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color:
                  f.comment == null ? AdminUi.textMuted : AdminUi.textPrimary,
            ),
          ),
          const SizedBox(height: 20),
          _sectionTitle('PHOTOS'),
          const SizedBox(height: 10),
          _PhotoGallery(urls: f.photoUrls),
          const SizedBox(height: 22),
          RespondPanel(
            isAnonymous: f.isAnonymous,
            respondedAt: _respondedAt,
            existingResponse: _response,
            templates: _kFeedbackTemplates,
            noteController: _noteCtrl,
            onSendResponse: _respond,
            onSaveNote: _saveNote,
          ),
        ],
      ),
    );

    // Narrow → full-screen page.
    if (narrow) {
      return AdminDetailScaffold(
        title: 'Feedback details',
        child: Column(
          children: [
            richHeader(showClose: false),
            const Divider(height: 1, color: AdminUi.border),
            Expanded(child: scrollContent),
          ],
        ),
      );
    }

    // Wide → centered dialog card.
    return Dialog(
      backgroundColor: AdminUi.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            richHeader(showClose: true),
            const Divider(height: 1, color: AdminUi.border),
            Flexible(child: scrollContent),
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

class _AspectGrid extends StatelessWidget {
  final List<MapEntry<String, int>> aspects;
  const _AspectGrid({required this.aspects});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AdminUi.subtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminUi.border),
      ),
      padding: const EdgeInsets.all(4),
      child: LayoutBuilder(
        builder: (context, c) {
          final twoCol = c.maxWidth >= 440;
          final itemWidth = twoCol ? c.maxWidth / 2 : c.maxWidth;
          return Wrap(
            children: [
              for (final a in aspects)
                SizedBox(
                  width: itemWidth,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(a.key,
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  color: AdminUi.textSecondary)),
                        ),
                        _StarRow(rating: a.value, size: 14),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _PhotoGallery extends StatelessWidget {
  final List<String> urls;
  const _PhotoGallery({required this.urls});

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) {
      return const Text('No photos attached.',
          style: TextStyle(fontSize: 13, color: AdminUi.textMuted));
    }
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [for (final u in urls) _PhotoThumb(url: u)],
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  final String url;
  const _PhotoThumb({required this.url});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showDialog(
        context: context,
        barrierColor: Colors.black87,
        builder: (_) => _FullscreenImageDialog(url: url),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 92,
          height: 92,
          color: AdminUi.subtle,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                url,
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
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
