import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/deeplink_highlight.dart';
import '../../../core/widgets/media_source_badge.dart';
import '../../../core/widgets/ai_detection_badge.dart';
import '../theme/admin_ui.dart';
import '../providers/admin_feedback_provider.dart';
import '../providers/admin_identity_reveal_provider.dart';
import '../widgets/admin_detail_screen.dart';
import '../widgets/admin_moderation.dart';
import '../widgets/admin_skeleton.dart';
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
  /// A feedback id to scroll to and flash once, when arriving from an insight
  /// row or a notification. Null for a normal open.
  final String? highlightId;
  const AdminFeedbackPage({super.key, this.highlightId});

  @override
  ConsumerState<AdminFeedbackPage> createState() => _AdminFeedbackPageState();
}

class _AdminFeedbackPageState extends ConsumerState<AdminFeedbackPage>
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

    // Rows exist only once the fetch resolves — flash the deep-link target then.
    if (async.hasValue) flashHighlightOnce(widget.highlightId);

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

  /// Deep-link plumbing: the page owns the highlight state (via
  /// [DeepLinkHighlightMixin]) and hands down a key + a flag per row, so the
  /// flashed row can be scrolled to and tinted.
  final GlobalKey Function(String id) keyFor;
  final bool Function(String id) isHighlighted;
  const _Results({
    required this.async,
    required this.onOpen,
    required this.onRetry,
    required this.keyFor,
    required this.isHighlighted,
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
                      _TableRow(
                        key: keyFor(f.id),
                        feedback: f,
                        onOpen: () => onOpen(f),
                        highlighted: isHighlighted(f.id),
                      ),
                  ],
                );
              }
              return Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    for (final f in items)
                      _Card(
                        key: keyFor(f.id),
                        feedback: f,
                        onOpen: () => onOpen(f),
                        highlighted: isHighlighted(f.id),
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

  /// Set when this row is the deep-link target: it flashes, then fades back.
  final bool highlighted;
  const _TableRow({
    super.key,
    required this.feedback,
    required this.onOpen,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final f = feedback;
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
                color:
                    f.isAnonymous ? kAnonColor.withValues(alpha: 0.035) : null,
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
  final bool highlighted;
  const _Card({
    super.key,
    required this.feedback,
    required this.onOpen,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final f = feedback;
    return SubmissionListCard(
      isAnonymous: f.isAnonymous,
      onTap: onOpen,
      highlighted: highlighted,
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

  /// Which PANE is showing when the layout is too narrow to seat both side by
  /// side: 0 = Feedback Details, 1 = Feedback Status. Details leads — you read
  /// what the citizen rated and wrote before you reply to it.
  int _paneTab = 0;

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

  /// Left pane — where this feedback stands, and the reply that closes it out.
  ///
  /// Deliberately NOT the report's stepper: feedback has no workflow to walk
  /// through. It's either waiting on the LGU or it's been answered, so the
  /// status card plus the reply composer say everything the four-step rail
  /// would, without inventing stages that don't exist.
  Widget _statusPane() {
    final f = widget.feedback;
    final replied = _status == FeedbackStatus.responded;
    final accent = _statusColor(_status);

    return _Pane(
      title: 'Feedback Status',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusCard(
            chip: feedbackStatusLabel(_status),
            headline: replied
                ? 'You\'ve replied to this feedback.'
                : 'This feedback is awaiting a reply.',
            blurb: replied
                ? 'The citizen has been notified of your response. The internal '
                      'note below stays private to the console.'
                : 'It\'s still on the review desk. Send a reply and the citizen '
                      'is notified — or keep a private note for the team.',
            accent: accent,
            facts: [
              (label: 'Submitted on', value: adminLongDateTime(f.createdAt)),
              if (replied && _respondedAt != null)
                (label: 'Replied on', value: adminLongDateTime(_respondedAt))
              else
                (label: 'Office', value: f.officeLabel),
            ],
          ),
          const SizedBox(height: 18),
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
  }

  /// Right pane — what was rated, and by whom. Mirrors the report details pane;
  /// there's no action block because feedback's only actions are the reply
  /// (left pane) and dismissal (the moderation bar up top).
  Widget _detailsPane() {
    final f = widget.feedback;
    final aspects = <MapEntry<String, int>>[
      if (f.aspectStaff != null) MapEntry('Staff attitude', f.aspectStaff!),
      if (f.aspectWait != null) MapEntry('Wait time', f.aspectWait!),
      if (f.aspectClarity != null) MapEntry('Process clarity', f.aspectClarity!),
      if (f.aspectFacility != null) MapEntry('Facility', f.aspectFacility!),
    ];
    final photos = f.photoUrls;

    return _Pane(
      title: 'Feedback Details',
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
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HeroThumb(
                url: photos.isEmpty ? null : photos.first,
                officeId: f.officeId,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _KvRow(
                      label: 'Status',
                      trailing: StatusPill(
                        label: feedbackStatusLabel(_status),
                        color: _statusColor(_status),
                      ),
                    ),
                    _KvRow(label: 'ID', value: '#FBK-${f.shortId}'),
                    _KvRow(
                      label: 'Date Submitted',
                      value: adminShortDate(f.createdAt),
                    ),
                    _KvRow(
                      label: 'Time Submitted',
                      value: adminClockTime(f.createdAt),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(height: 1, color: AdminUi.border),
          const SizedBox(height: 18),
          _IconSection(
            icon: _officeIcon(f.officeId),
            title: 'Office',
            child: Text(
              f.officeLabel,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AdminUi.textSecondary,
              ),
            ),
          ),
          _IconSection(
            icon: Icons.room_service_rounded,
            title: 'Service',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  f.serviceName.isEmpty ? '—' : f.serviceName,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: AdminUi.textSecondary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Visited · ${adminShortDate(f.visitDate)}',
                  style: const TextStyle(fontSize: 12, color: AdminUi.textMuted),
                ),
              ],
            ),
          ),
          _IconSection(
            icon: Icons.star_rounded,
            title: 'Overall Rating',
            child: Row(
              children: [
                _StarRow(rating: f.overallRating, size: 18),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    feedbackRatingLabel(f.overallRating),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AdminUi.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (aspects.isNotEmpty)
            _IconSection(
              icon: Icons.tune_rounded,
              title: 'Aspect Ratings',
              child: _AspectGrid(aspects: aspects),
            ),
          _IconSection(
            icon: Icons.person_rounded,
            title: 'Submitted By',
            child: RevealableSubmitter(
              source: RevealSource.feedback,
              submissionId: f.id,
              isAnonymous: f.isAnonymous,
              name: f.submitterName,
              photoUrl: f.submitterPhotoUrl,
              role: null,
            ),
          ),
          _IconSection(
            icon: Icons.description_rounded,
            title: 'Comment',
            child: Text(
              f.comment ?? 'No comment provided.',
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color:
                    f.comment == null ? AdminUi.textMuted : AdminUi.textSecondary,
              ),
            ),
          ),
          _IconSection(
            icon: Icons.attach_file_rounded,
            title: 'Photos',
            isLast: true,
            child: _PhotoGallery(
              urls: f.photoUrls,
              sources: f.photoSources,
              aiScores: f.photoAiScores,
              aiStatuses: f.photoAiStatus,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.of(context).size.width < kAdminDetailNarrowBelow;

    // One pane at a time on a phone, or in a dialog too narrow for two columns.
    // Stacking both would make a small screen scroll the length of the pair.
    Widget paneTabs() => AdminSegmentedTabs(
      labels: const ['Feedback Details', 'Feedback Status'],
      selected: _paneTab,
      onSelect: (i) => setState(() => _paneTab = i),
    );

    Widget activePane() => SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: _paneTab == 0 ? _detailsPane() : _statusPane(),
    );

    if (narrow) {
      return AdminDetailScaffold(
        title: 'Feedback details',
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
      // Tight vertical inset: the panes are long, and every pixel given back
      // here is a pixel the admin doesn't have to scroll.
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120, maxHeight: 900),
        child: LayoutBuilder(
          builder: (context, c) {
            if (c.maxWidth < _kTwoPaneFrom) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                    child: Row(
                      children: [
                        Expanded(child: paneTabs()),
                        const SizedBox(width: 10),
                        const _PaneCloseButton(),
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
                const Positioned(top: 22, right: 22, child: _PaneCloseButton()),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Width at which the detail splits into two columns. Matches the reports and
/// suggestions consoles so all three break at the same point.
const double _kTwoPaneFrom = 900;

/// Test hook for the status card that heads the detail's left pane — the piece
/// with the width-dependent illustration and fact strip.
Widget feedbackStatusCardForTesting({
  required String chip,
  required String headline,
  required String blurb,
  required Color accent,
  List<({String label, String value})> facts = const [],
}) => _StatusCard(
  chip: chip,
  headline: headline,
  blurb: blurb,
  accent: accent,
  facts: facts,
);

// ── Detail building blocks ───────────────────────────────────────────────────

/// A titled white card — one of the two panes of the feedback detail.
class _Pane extends StatelessWidget {
  final String title;
  final Widget child;
  const _Pane({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AdminUi.surface,
        borderRadius: BorderRadius.circular(AdminUi.cardRadius),
        border: Border.all(color: AdminUi.border),
        boxShadow: AdminUi.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AdminUi.textPrimary,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

/// The status headline card at the top of the left pane — the feedback's
/// equivalent of the report's stage card, illustrated with the feedback mark.
class _StatusCard extends StatelessWidget {
  final String chip;
  final String headline;
  final String blurb;
  final Color accent;
  final List<({String label, String value})> facts;
  const _StatusCard({
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
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
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
                children: [
                  Expanded(child: copy),
                  const SizedBox(width: 12),
                  Image.asset(
                    'assets/images/feedback.webp',
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

/// The white inset strip of label/value pairs at the foot of the status card.
/// Side by side when there's room, stacked when there isn't, so a long office
/// name or timestamp never gets clipped.
class _FactStrip extends StatelessWidget {
  final List<({String label, String value})> facts;
  final Color accent;
  const _FactStrip({required this.facts, required this.accent});

  @override
  Widget build(BuildContext context) {
    Widget fact(({String label, String value}) f) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          f.label,
          style: const TextStyle(fontSize: 11, color: AdminUi.textMuted),
        ),
        const SizedBox(height: 3),
        Text(
          f.value,
          style: const TextStyle(
            fontSize: 12.5,
            height: 1.35,
            fontWeight: FontWeight.w700,
            color: AdminUi.textPrimary,
          ),
        ),
      ],
    );

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
          // Each fact needs ~150px to seat a date on two lines; under that the
          // row becomes a stack.
          if (c.maxWidth >= facts.length * 150) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < facts.length; i++) ...[
                  if (i > 0) const SizedBox(width: 14),
                  Expanded(child: fact(facts[i])),
                ],
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < facts.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                fact(facts[i]),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Square preview of the feedback's first photo, beside the id/date block.
/// Falls back to the office mark when there's no photo to show.
class _HeroThumb extends StatelessWidget {
  final String? url;
  final String officeId;
  const _HeroThumb({required this.url, required this.officeId});

  @override
  Widget build(BuildContext context) {
    final u = url;
    Widget inner;
    if (u == null) {
      inner = _OfficeIconBox(officeId, size: 88);
    } else {
      inner = GestureDetector(
        onTap: () => showDialog(
          context: context,
          barrierColor: Colors.black87,
          builder: (_) => _FullscreenImageDialog(url: u),
        ),
        // Shimmers in its own box while it loads, and stays cached after.
        child: SkeletonNetworkImage(
          url: u,
          errorChild: _OfficeIconBox(officeId, size: 88),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 88,
        height: 88,
        color: AdminUi.subtle,
        child: inner,
      ),
    );
  }
}

/// "Label: value" line in the details pane's id block. Pass [value] for plain
/// text or [trailing] for a widget (the status pill).
class _KvRow extends StatelessWidget {
  final String label;
  final String? value;
  final Widget? trailing;
  const _KvRow({required this.label, this.value, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AdminUi.textPrimary,
            ),
          ),
          Expanded(
            child:
                trailing ??
                Text(
                  value ?? '—',
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: AdminUi.textSecondary,
                  ),
                ),
          ),
        ],
      ),
    );
  }
}

/// An icon + heading with its content indented beneath — the repeating unit of
/// the details pane (Office, Service, Rating, Comment, Photos).
class _IconSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;
  final bool isLast;
  const _IconSection({
    required this.icon,
    required this.title,
    required this.child,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: AppColors.primaryBlue),
              const SizedBox(width: 7),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AdminUi.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(padding: const EdgeInsets.only(left: 22), child: child),
        ],
      ),
    );
  }
}

/// The dialog's way out, styled to sit on a pane's top-right corner.
class _PaneCloseButton extends StatelessWidget {
  const _PaneCloseButton();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AdminUi.subtle,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.pop(context),
        child: Tooltip(
          message: 'Close',
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              border: Border.fromBorderSide(BorderSide(color: AdminUi.border)),
            ),
            child: const Icon(
              Icons.close_rounded,
              size: 18,
              color: AdminUi.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
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

  /// Per-photo provenance, aligned index-for-index with [urls].
  final List<String> sources;

  /// Per-photo AI-detection results, aligned index-for-index with [urls].
  final List<double?> aiScores;
  final List<String?> aiStatuses;
  const _PhotoGallery({
    required this.urls,
    this.sources = const [],
    this.aiScores = const [],
    this.aiStatuses = const [],
  });

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) {
      return const Text('No photos attached.',
          style: TextStyle(fontSize: 13, color: AdminUi.textMuted));
    }
    // Tiles size to the pane rather than a hardcoded 92, so the grid ends flush
    // on a narrow details column and stays tappable on a phone.
    return LayoutBuilder(
      builder: (context, c) {
        final tile = attachmentTileSize(c.maxWidth);
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var i = 0; i < urls.length; i++)
              _PhotoThumb(
                url: urls[i],
                size: tile,
                verified: i < sources.length && sources[i] == 'camera',
                aiScore: i < aiScores.length ? aiScores[i] : null,
                aiStatus: i < aiStatuses.length ? aiStatuses[i] : null,
              ),
          ],
        );
      },
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  final String url;
  final bool verified;
  final double? aiScore;
  final String? aiStatus;

  /// Side of the square tile. The gallery sizes this to the pane it's in — see
  /// [attachmentTileSize].
  final double size;
  const _PhotoThumb({
    required this.url,
    this.size = 92,
    this.verified = false,
    this.aiScore,
    this.aiStatus,
  });

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
          width: size,
          height: size,
          color: AdminUi.subtle,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Shimmers while it loads and keeps a disk cache, so reopening
              // this feedback doesn't re-download its photos.
              SkeletonNetworkImage(
                url: url,
                fit: BoxFit.cover,
                errorChild: const ColoredBox(
                  color: AdminUi.subtle,
                  child: Icon(Icons.broken_image_rounded,
                      color: AdminUi.textMuted, size: 22),
                ),
              ),
              Positioned(
                top: 5,
                left: 5,
                child: MediaSourceBadge(verified: verified),
              ),
              // AI-generated-image flag (top-right, opposite the source badge).
              // Compact on the small 92px thumb to avoid collision.
              Positioned(
                top: 5,
                right: 5,
                child: AiDetectionBadge(
                  score: aiScore,
                  status: aiStatus,
                  compact: true,
                ),
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
              // Cached: the thumb already warmed this URL, so opening the
              // viewer shows the photo instead of re-fetching it.
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.contain,
                placeholder: (_, _) =>
                    const CircularProgressIndicator(color: Colors.white),
                errorWidget: (_, _, _) => const Icon(
                  Icons.broken_image_rounded,
                  color: Colors.white54,
                  size: 40,
                ),
              ),
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
