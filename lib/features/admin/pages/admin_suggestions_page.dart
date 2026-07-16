import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/deeplink_highlight.dart';
import '../../../core/widgets/media_source_badge.dart';
import '../../../core/widgets/ai_detection_badge.dart';
import '../theme/admin_ui.dart';
import '../providers/admin_identity_reveal_provider.dart';
import '../providers/admin_suggestions_provider.dart';
import '../widgets/admin_detail_screen.dart';
import '../widgets/admin_moderation.dart';
import '../widgets/admin_skeleton.dart';
import '../widgets/admin_submission_ui.dart';
import '../widgets/revealable_submitter.dart';
import '../widgets/admin_snackbar.dart';
import '../../../core/widgets/app_dialog.dart';

const List<String> _kSuggestionTemplates = [
  'Thank you for your suggestion — we\'ve noted it.',
  'Great idea. We\'re looking into whether we can put it in place.',
  'Thanks! This isn\'t feasible right now, but we appreciate it.',
];

// ── Category visuals — the same webp illustrations the citizen form uses ──────
String _categoryAsset(String key) {
  switch (key) {
    case 'public_service':
      return 'assets/images/suggestion/courthouse.webp';
    case 'community_program':
      return 'assets/images/suggestion/group.webp';
    case 'health_safety':
      return 'assets/images/suggestion/health.webp';
    case 'infrastructure':
      return 'assets/images/suggestion/building.webp';
    case 'environment':
      return 'assets/images/suggestion/trees.webp';
    case 'others':
    default:
      return 'assets/images/report/menu.webp';
  }
}

IconData _categoryIcon(String key) {
  switch (key) {
    case 'public_service':
      return Icons.account_balance_rounded;
    case 'community_program':
      return Icons.groups_rounded;
    case 'health_safety':
      return Icons.health_and_safety_rounded;
    case 'infrastructure':
      return Icons.apartment_rounded;
    case 'environment':
      return Icons.eco_rounded;
    default:
      return Icons.lightbulb_outline_rounded;
  }
}

Color _categoryColor(String key) {
  switch (key) {
    case 'public_service':
      return const Color(0xFF3B82F6);
    case 'community_program':
      return const Color(0xFF8B5CF6);
    case 'health_safety':
      return const Color(0xFFEF4444);
    case 'infrastructure':
      return const Color(0xFFF59E0B);
    case 'environment':
      return const Color(0xFF22C55E);
    default:
      return const Color(0xFF64748B);
  }
}

Color _statusColor(SuggestionStatus s) =>
    s == SuggestionStatus.responded ? AppColors.green : AppColors.orange;

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

class AdminSuggestionsPage extends ConsumerStatefulWidget {
  /// A suggestion id to scroll to and flash once, when arriving from a
  /// notification. Null for a normal open.
  final String? highlightId;
  const AdminSuggestionsPage({super.key, this.highlightId});

  @override
  ConsumerState<AdminSuggestionsPage> createState() =>
      _AdminSuggestionsPageState();
}

class _AdminSuggestionsPageState extends ConsumerState<AdminSuggestionsPage>
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
      ref.read(adminSuggestionsProvider.notifier).setQuery(value);
    });
  }

  int _activeFilterCount(SuggestionFilters f) {
    var n = 0;
    if (f.status != null) n++;
    if (f.sort != SuggestionSort.newest) n++;
    if (f.anonymousOnly) n++;
    if (f.showDismissed) n++;
    return n;
  }

  void _openFilters() {
    final notifier = ref.read(adminSuggestionsProvider.notifier);
    openAdminFilterSheet(
      context,
      title: 'Filter suggestions',
      onReset: () {
        notifier.setStatus(null);
        notifier.setSort(SuggestionSort.newest);
        if (notifier.filters.anonymousOnly) notifier.toggleAnonymousOnly();
        notifier.setShowDismissed(false);
      },
      content: Consumer(
        builder: (context, ref, _) {
          ref.watch(adminSuggestionsProvider);
          final f = ref.read(adminSuggestionsProvider.notifier).filters;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FilterChoiceRow<SuggestionStatus>(
                label: 'Status',
                value: f.status,
                options: [
                  (value: null, text: 'All'),
                  for (final s in SuggestionStatus.values)
                    (value: s, text: suggestionStatusLabel(s)),
                ],
                onSelected: (v) => notifier.setStatus(v),
              ),
              const SizedBox(height: 18),
              FilterChoiceRow<SuggestionSort>(
                label: 'Sort',
                value: f.sort,
                options: const [
                  (value: SuggestionSort.newest, text: 'Newest'),
                  (value: SuggestionSort.oldest, text: 'Oldest'),
                ],
                onSelected: (v) {
                  if (v != null) notifier.setSort(v);
                },
              ),
              const SizedBox(height: 18),
              FilterSwitchRow(
                icon: Icons.visibility_off_rounded,
                label: 'Anonymous only',
                subtitle: 'Show only submissions with a withheld identity',
                value: f.anonymousOnly,
                onChanged: (_) => notifier.toggleAnonymousOnly(),
              ),
              const SizedBox(height: 18),
              FilterSwitchRow(
                icon: Icons.block_rounded,
                label: 'Show dismissed',
                subtitle: 'Review spam hidden from the list & analytics',
                value: f.showDismissed,
                onChanged: (v) => notifier.setShowDismissed(v),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openDetail(AdminSuggestion s) async {
    await showAdminDetail(
      context,
      builder: (_) => _SuggestionDetailDialog(suggestion: s),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(adminSuggestionsProvider);
    final notifier = ref.read(adminSuggestionsProvider.notifier);
    final filters = notifier.filters;
    final pad = MediaQuery.of(context).size.width < 600 ? 16.0 : 24.0;

    // Rows exist only once the fetch resolves — flash the deep-link target then.
    if (async.hasValue) flashHighlightOnce(widget.highlightId);

    return RefreshIndicator(
      onRefresh: () => ref.read(adminSuggestionsProvider.notifier).refresh(),
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
                  keyFor: highlightKey,
                  isHighlighted: isHighlighted,
                  onRetry: () =>
                      ref.read(adminSuggestionsProvider.notifier).refresh(),
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
  final AsyncValue<List<AdminSuggestion>> async;
  final AdminSuggestionsNotifier notifier;
  const _Header({required this.async, required this.notifier});

  @override
  Widget build(BuildContext context) {
    if (async.valueOrNull == null) {
      return const Text(
        'Citizen-submitted community suggestions',
        style: TextStyle(fontSize: 13, color: AdminUi.textMuted),
      );
    }
    final total = notifier.totalCount;
    final anon = notifier.anonymousCount;
    final highAnon = total > 0 && anon / total > 0.30;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The top bar already shows "Suggestions", so no in-content page title.
        Row(
          children: [
            Text('$total suggestion${total == 1 ? '' : 's'}',
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

// ── Toolbar ───────────────────────────────────────────────────────────────────

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
                hint: 'Search suggestions…',
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

// ── Active filter chips ────────────────────────────────────────────────────────

class _ActiveChips extends StatelessWidget {
  final SuggestionFilters filters;
  final AdminSuggestionsNotifier notifier;
  const _ActiveChips({required this.filters, required this.notifier});

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      if (filters.status != null)
        ActiveChip(
          label: suggestionStatusLabel(filters.status!),
          onRemove: () => notifier.setStatus(null),
        ),
      if (filters.sort != SuggestionSort.newest)
        ActiveChip(
          label: 'Oldest first',
          onRemove: () => notifier.setSort(SuggestionSort.newest),
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

// ── Results ────────────────────────────────────────────────────────────────────

class _Results extends StatelessWidget {
  final AsyncValue<List<AdminSuggestion>> async;
  final void Function(AdminSuggestion) onOpen;
  final VoidCallback onRetry;

  /// Deep-link plumbing: the page owns the highlight state (via
  /// [DeepLinkHighlightMixin]) and hands down a key + flag per row.
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
          text: 'Couldn\'t load suggestions.',
          action: TextButton(onPressed: onRetry, child: const Text('Retry')),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const AdminResultsMessage(
              icon: Icons.inbox_rounded,
              color: AdminUi.textMuted,
              text: 'No suggestions match your filters.',
            );
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 720) {
                return Column(
                  children: [
                    const _TableHeader(),
                    for (final s in items)
                      _TableRow(
                        key: keyFor(s.id),
                        suggestion: s,
                        onOpen: () => onOpen(s),
                        highlighted: isHighlighted(s.id),
                      ),
                  ],
                );
              }
              return Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    for (final s in items)
                      _Card(
                        key: keyFor(s.id),
                        suggestion: s,
                        onOpen: () => onOpen(s),
                        highlighted: isHighlighted(s.id),
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
          _HCell('CATEGORY', flex: 4),
          _HCell('SUBMITTER', flex: 3),
          _HCell('BARANGAY', flex: 2),
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
  final AdminSuggestion suggestion;
  final VoidCallback onOpen;

  /// Set when this row is the deep-link target: it flashes, then fades back.
  final bool highlighted;
  const _TableRow({
    super.key,
    required this.suggestion,
    required this.onOpen,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final s = suggestion;
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
                    s.isAnonymous ? kAnonColor.withValues(alpha: 0.035) : null,
                border: const Border(bottom: BorderSide(color: AdminUi.border)),
              ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  _CategoryIconBox(s.categoryKey, size: 30),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.category,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AdminUi.textPrimary,
                          ),
                        ),
                        Text(s.shortId,
                            style: const TextStyle(
                                fontSize: 11, color: AdminUi.textMuted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: SubmitterInline(
                isAnonymous: s.isAnonymous,
                name: s.submitterName,
                role: s.submitterRole,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                (s.barangay == null || s.barangay!.isEmpty) ? '—' : s.barangay!,
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
                  label: suggestionStatusLabel(s.status),
                  color: _statusColor(s.status),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                adminShortDate(s.createdAt),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AdminUi.textMuted),
              ),
            ),
            SizedBox(
              width: 34,
              child: _MediaCount(s.mediaCount),
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
  final AdminSuggestion suggestion;
  final VoidCallback onOpen;
  final bool highlighted;
  const _Card({
    super.key,
    required this.suggestion,
    required this.onOpen,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final s = suggestion;
    return SubmissionListCard(
      isAnonymous: s.isAnonymous,
      onTap: onOpen,
      highlighted: highlighted,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _CategoryIconBox(s.categoryKey, size: 38),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  s.category,
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
                label: suggestionStatusLabel(s.status),
                color: _statusColor(s.status),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SubmitterInline(
            isAnonymous: s.isAnonymous,
            name: s.submitterName,
            role: s.submitterRole,
          ),
          if (s.details.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              s.details,
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
              s.shortId,
              if (s.barangay != null && s.barangay!.isNotEmpty) s.barangay!,
              adminShortDate(s.createdAt),
              if (s.mediaCount > 0)
                '${s.mediaCount} file${s.mediaCount == 1 ? '' : 's'}',
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

class _SuggestionDetailDialog extends ConsumerStatefulWidget {
  final AdminSuggestion suggestion;
  const _SuggestionDetailDialog({required this.suggestion});

  @override
  ConsumerState<_SuggestionDetailDialog> createState() =>
      _SuggestionDetailDialogState();
}

class _SuggestionDetailDialogState
    extends ConsumerState<_SuggestionDetailDialog> {
  late final TextEditingController _noteCtrl;
  late SuggestionStatus _status;
  DateTime? _respondedAt;
  String? _response;
  late Future<List<SuggestionMedia>> _mediaFuture;
  bool _busy = false;

  /// Which PANE is showing when the layout is too narrow to seat both side by
  /// side: 0 = Suggestion Details, 1 = Suggestion Status. Details leads — it's
  /// what the citizen actually wrote, and you read it before you reply to it.
  int _paneTab = 0;

  /// The suggestion as it stands NOW. The dialog opens on a snapshot from the
  /// list but stays open across a restore, which rewrites the row — so the
  /// render paths read through this rather than keep describing the suggestion
  /// as it was before the tap. Falls back to the snapshot only if the row has
  /// left the store entirely.
  AdminSuggestion get suggestion =>
      ref.read(adminSuggestionsProvider.notifier).byId(widget.suggestion.id) ??
      widget.suggestion;

  @override
  void initState() {
    super.initState();
    final s = widget.suggestion;
    _noteCtrl = TextEditingController(text: s.adminNote ?? '');
    _status = s.status;
    _response = s.adminResponse;
    _respondedAt =
        s.status == SuggestionStatus.responded ? s.reviewedAt : null;
    _mediaFuture =
        ref.read(adminSuggestionsProvider.notifier).fetchMedia(s.id);
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _respond(String message) async {
    try {
      await ref
          .read(adminSuggestionsProvider.notifier)
          .respond(widget.suggestion.id, message);
      if (!mounted) return;
      setState(() {
        _status = SuggestionStatus.responded;
        _respondedAt = DateTime.now();
        _response = message;
      });
      showAdminSnackBar(context, 'Response sent to the citizen.',
          type: AdminSnackType.success);
    } catch (e) {
      if (mounted) {
        showAdminSnackBar(context, e.toString(), type: AdminSnackType.error);
      }
      rethrow; // let RespondPanel keep the text
    }
  }

  Future<void> _saveNote() async {
    try {
      await ref
          .read(adminSuggestionsProvider.notifier)
          .saveAdminNote(widget.suggestion.id, _noteCtrl.text);
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
    final reason = await showAdminDismissDialog(context, itemLabel: 'suggestion');
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(adminSuggestionsProvider.notifier)
          .dismiss(widget.suggestion.id, reason);
      if (!mounted) return;
      Navigator.pop(context);
      showAdminSnackBar(context, 'Suggestion dismissed — hidden from analytics.',
          type: AdminSnackType.success);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAdminSnackBar(context, 'Could not dismiss: $e', type: AdminSnackType.error);
    }
  }

  /// Undo a dismissal. Unlike dismissing, this brings the suggestion back
  /// rather than finishing with it, so the dialog stays open and re-renders as
  /// the ordinary suggestion — the dismissed banner gone.
  Future<void> _restore() async {
    setState(() => _busy = true);
    try {
      await ref.read(adminSuggestionsProvider.notifier).restore(widget.suggestion.id);
      if (!mounted) return;
      setState(() => _busy = false);
      showAdminSnackBar(context, 'Suggestion restored.', type: AdminSnackType.success);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAdminSnackBar(context, 'Could not restore: $e', type: AdminSnackType.error);
    }
  }

  /// Left pane — where this suggestion stands, and the reply that moves it.
  ///
  /// Deliberately NOT the report's stepper: a suggestion has no multi-stage
  /// workflow to walk through. It is either waiting on the LGU or it has been
  /// answered, so the stage card plus the reply composer say everything the
  /// four-step rail would, without inventing stages that don't exist.
  Widget _statusPane() {
    final s = suggestion;
    final replied = _status == SuggestionStatus.responded;
    final accent = _statusColor(_status);

    return _Pane(
      title: 'Suggestion Status',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusCard(
            chip: suggestionStatusLabel(_status),
            headline: replied
                ? 'You\'ve replied to this suggestion.'
                : 'This suggestion is awaiting a reply.',
            blurb: replied
                ? 'The citizen has been notified of your response. The internal '
                      'note below stays private to the console.'
                : 'It\'s still on the review desk. Send a reply and the citizen '
                      'is notified — or keep a private note for the team.',
            accent: accent,
            facts: [
              (label: 'Submitted on', value: adminLongDateTime(s.createdAt)),
              if (replied && _respondedAt != null)
                (label: 'Replied on', value: adminLongDateTime(_respondedAt))
              else
                (label: 'Category', value: s.category),
            ],
          ),
          const SizedBox(height: 18),
          RespondPanel(
            isAnonymous: s.isAnonymous,
            respondedAt: _respondedAt,
            existingResponse: _response,
            templates: _kSuggestionTemplates,
            noteController: _noteCtrl,
            onSendResponse: _respond,
            onSaveNote: _saveNote,
          ),
        ],
      ),
    );
  }

  /// Right pane — what was suggested, and by whom. Mirrors the report details
  /// pane; there's no action block because a suggestion's only actions are the
  /// reply (left pane) and dismissal (the moderation bar up top).
  Widget _detailsPane() {
    final s = suggestion;
    return _Pane(
      title: 'Suggestion Details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminModerationBar(
            isDismissed: s.isDismissed,
            reason: s.dismissedReason,
            busy: _busy,
            onDismiss: _dismiss,
            onRestore: _restore,
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HeroThumb(future: _mediaFuture, categoryKey: s.categoryKey),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _KvRow(
                      label: 'Status',
                      trailing: StatusPill(
                        label: suggestionStatusLabel(_status),
                        color: _statusColor(_status),
                      ),
                    ),
                    _KvRow(label: 'ID', value: '#SUG-${s.shortId}'),
                    _KvRow(
                      label: 'Date Submitted',
                      value: adminShortDate(s.createdAt),
                    ),
                    _KvRow(
                      label: 'Time Submitted',
                      value: adminClockTime(s.createdAt),
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
            icon: _categoryIcon(s.categoryKey),
            title: 'Category',
            child: Text(
              s.category,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AdminUi.textSecondary,
              ),
            ),
          ),
          _IconSection(
            icon: Icons.location_on_rounded,
            title: 'Location',
            child: _LocationBlock(suggestion: s),
          ),
          _IconSection(
            icon: Icons.person_rounded,
            title: 'Suggested By',
            child: RevealableSubmitter(
              source: RevealSource.suggestion,
              submissionId: s.id,
              isAnonymous: s.isAnonymous,
              name: s.submitterName,
              photoUrl: s.submitterPhotoUrl,
              role: s.submitterRole,
              subject: 'suggester',
            ),
          ),
          _IconSection(
            icon: Icons.description_rounded,
            title: 'Details',
            child: Text(
              s.details.trim().isEmpty ? '—' : s.details,
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: AdminUi.textSecondary,
              ),
            ),
          ),
          _IconSection(
            icon: Icons.attach_file_rounded,
            title: 'Attachments',
            isLast: true,
            child: _MediaGallery(
              future: _mediaFuture,
              placeholderCount: s.mediaCount,
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
      labels: const ['Suggestion Details', 'Suggestion Status'],
      selected: _paneTab,
      onSelect: (i) => setState(() => _paneTab = i),
    );

    Widget activePane() => SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: _paneTab == 0 ? _detailsPane() : _statusPane(),
    );

    if (narrow) {
      return AdminDetailScaffold(
        title: 'Suggestion details',
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

/// Width at which the detail splits into two columns. Matches the reports
/// console so both consoles break at the same point.
const double _kTwoPaneFrom = 900;

/// Test hook for the status card that heads the detail's left pane — the piece
/// with the width-dependent illustration and fact strip.
Widget suggestionStatusCardForTesting({
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

/// A titled white card — one of the two panes of the suggestion detail.
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

/// The status headline card at the top of the left pane — the suggestion's
/// equivalent of the report's stage card, illustrated with the suggestion mark.
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
                    'assets/images/suggestion/suggestion.webp',
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
/// Side by side when there's room, stacked when there isn't, so a long
/// timestamp never gets clipped.
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

/// Square preview of the suggestion's first photo, beside the id/date block.
/// Falls back to the category illustration when there's no image to show.
class _HeroThumb extends StatelessWidget {
  final Future<List<SuggestionMedia>> future;
  final String categoryKey;
  const _HeroThumb({required this.future, required this.categoryKey});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SuggestionMedia>>(
      future: future,
      builder: (context, snap) {
        final media = snap.data ?? const <SuggestionMedia>[];
        final photos = media.where((m) => !m.isVideo);
        final url = photos.isEmpty ? null : photos.first.url;
        final videos = media.where((m) => m.isVideo).toList();

        Widget inner;
        if (snap.connectionState != ConnectionState.done) {
          // Shimmer, not a spinner: the box is already the image's final size,
          // so the placeholder reads as the image arriving rather than as a
          // control sitting in a hole.
          inner = const AdminShimmer(
            child: ColoredBox(color: kSkeletonBase, child: SizedBox.expand()),
          );
        } else if (url == null && videos.isNotEmpty) {
          // Video-only: there IS media here, so the category illustration would
          // read as "nothing attached". Show a play tile that opens the clip.
          inner = GestureDetector(
            onTap: () => showAppDialog(
              context: context,
              barrierColor: Colors.black87,
              builder: (_) => _NetworkVideoDialog(url: videos.first.url),
            ),
            child: const Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: Color(0xFF1F2937)),
                Center(
                  child: Icon(
                    Icons.play_circle_fill_rounded,
                    color: Colors.white70,
                    size: 32,
                  ),
                ),
              ],
            ),
          );
        } else if (url == null) {
          inner = _CategoryIconBox(categoryKey, size: 88);
        } else {
          inner = GestureDetector(
            onTap: () => showAppDialog(
              context: context,
              barrierColor: Colors.black87,
              builder: (_) => _FullscreenImageDialog(url: url),
            ),
            child: SkeletonNetworkImage(
              url: url,
              errorChild: _CategoryIconBox(categoryKey, size: 88),
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
      },
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
/// the details pane (Category, Location, Suggested By, Details, Attachments).
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

/// The suggested location as one line — "Brgy. Maura, Zone 1" — with the raw
/// coordinates beneath when the citizen pinned one. Sits under the Location
/// heading in the details pane, which already supplies the pin icon, so this
/// stays plain text rather than a box of its own.
class _LocationBlock extends StatelessWidget {
  final AdminSuggestion suggestion;
  const _LocationBlock({required this.suggestion});

  @override
  Widget build(BuildContext context) {
    final s = suggestion;
    final parts = [
      if (s.barangay != null && s.barangay!.isNotEmpty) s.barangay!,
      if (s.address != null && s.address!.isNotEmpty) s.address!,
    ];
    if (parts.isEmpty && !s.hasLocation) {
      return const Text(
        'No location provided.',
        style: TextStyle(fontSize: 13, color: AdminUi.textMuted),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (parts.isNotEmpty)
          Text(
            parts.join(', '),
            style: const TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AdminUi.textSecondary,
            ),
          ),
        if (s.hasLocation) ...[
          if (parts.isNotEmpty) const SizedBox(height: 4),
          Text(
            '${s.latitude!.toStringAsFixed(6)}, ${s.longitude!.toStringAsFixed(6)}',
            style: const TextStyle(
              fontSize: 12,
              height: 1.4,
              color: AdminUi.textMuted,
            ),
          ),
        ],
      ],
    );
  }
}

// ── Media gallery + viewers ────────────────────────────────────────────────────

class _MediaGallery extends StatelessWidget {
  final Future<List<SuggestionMedia>> future;

  /// How many thumbs to shape the skeleton with. The list row already knows the
  /// media count, so the placeholder grid matches the real one and the pane
  /// doesn't reflow when the signed URLs land.
  final int placeholderCount;
  const _MediaGallery({required this.future, this.placeholderCount = 0});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SuggestionMedia>>(
      future: future,
      builder: (context, snap) {
        final media = snap.data ?? const <SuggestionMedia>[];
        final loading = snap.connectionState != ConnectionState.done;
        if (loading && placeholderCount == 0) return const SizedBox.shrink();
        if (!loading && media.isEmpty) {
          return const Text('No attachments.',
              style: TextStyle(fontSize: 13, color: AdminUi.textMuted));
        }
        // Tiles size to the pane rather than a hardcoded 92, so the grid ends
        // flush on a narrow details column and stays tappable on a phone. The
        // skeleton uses the same maths, so nothing reflows when the URLs land.
        return LayoutBuilder(
          builder: (context, c) {
            final tile = attachmentTileSize(c.maxWidth);
            if (loading) {
              // One shimmer over the whole group, so the sweep crosses the grid
              // as a single band rather than each tile animating on its own.
              return AdminShimmer(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (var i = 0; i < placeholderCount; i++)
                      SkeletonBox(width: tile, height: tile, radius: 10),
                  ],
                ),
              );
            }
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final m in media) _MediaThumb(item: m, size: tile),
              ],
            );
          },
        );
      },
    );
  }
}

class _MediaThumb extends StatelessWidget {
  final SuggestionMedia item;

  /// Side of the square tile. The gallery sizes this to the pane it's in — see
  /// [attachmentTileSize].
  final double size;
  const _MediaThumb({required this.item, this.size = 92});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (item.isVideo) {
          showAppDialog(
            context: context,
            barrierColor: Colors.black87,
            builder: (_) => _NetworkVideoDialog(url: item.url),
          );
        } else {
          showAppDialog(
            context: context,
            barrierColor: Colors.black87,
            builder: (_) => _FullscreenImageDialog(url: item.url),
          );
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: size,
          height: size,
          color: AdminUi.subtle,
          child: item.isVideo
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: Color(0xFF1F2937)),
                    const Center(
                      child: Icon(Icons.play_circle_fill_rounded,
                          color: Colors.white70, size: 34),
                    ),
                    const Positioned(
                      left: 5,
                      bottom: 5,
                      child: Icon(Icons.videocam_rounded,
                          size: 14, color: Colors.white70),
                    ),
                    Positioned(
                      top: 5,
                      left: 5,
                      child: MediaSourceBadge(verified: item.isGpsVerified),
                    ),
                    // AI-generated-image flag (top-right, opposite the source
                    // badge). Compact on the small thumb to avoid collision.
                    Positioned(
                      top: 5,
                      right: 5,
                      child: AiDetectionBadge(
                        score: item.aiScore,
                        status: item.aiStatus,
                        compact: true,
                      ),
                    ),
                  ],
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    // Shimmers while it loads and keeps a disk cache, so a
                    // reopened suggestion doesn't re-download its photos.
                    SkeletonNetworkImage(
                      url: item.url,
                      fit: BoxFit.cover,
                      errorChild: const ColoredBox(
                        color: AdminUi.subtle,
                        child: Icon(Icons.broken_image_rounded,
                            color: AdminUi.textMuted, size: 22),
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
                    Positioned(
                      top: 5,
                      left: 5,
                      child: MediaSourceBadge(verified: item.isGpsVerified),
                    ),
                    // AI-generated-image flag (top-right, opposite the source
                    // badge). Compact on the small thumb to avoid collision.
                    Positioned(
                      top: 5,
                      right: 5,
                      child: AiDetectionBadge(
                        score: item.aiScore,
                        status: item.aiStatus,
                        compact: true,
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
