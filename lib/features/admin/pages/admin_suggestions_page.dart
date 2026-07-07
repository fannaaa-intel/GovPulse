import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../../../core/theme/app_colors.dart';
import '../theme/admin_ui.dart';
import '../providers/admin_suggestions_provider.dart';
import '../widgets/admin_detail_screen.dart';
import '../widgets/admin_submission_ui.dart';
import '../widgets/admin_snackbar.dart';

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
  const AdminSuggestionsPage({super.key});

  @override
  ConsumerState<AdminSuggestionsPage> createState() =>
      _AdminSuggestionsPageState();
}

class _AdminSuggestionsPageState extends ConsumerState<AdminSuggestionsPage> {
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
        const Text(
          'Suggestions',
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
                      _TableRow(suggestion: s, onOpen: () => onOpen(s)),
                  ],
                );
              }
              return Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    for (final s in items)
                      _Card(suggestion: s, onOpen: () => onOpen(s)),
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
  const _TableRow({required this.suggestion, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final s = suggestion;
    return InkWell(
      onTap: onOpen,
      child: Container(
        decoration: BoxDecoration(
          color: s.isAnonymous ? kAnonColor.withValues(alpha: 0.035) : null,
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
  const _Card({required this.suggestion, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final s = suggestion;
    return SubmissionListCard(
      isAnonymous: s.isAnonymous,
      onTap: onOpen,
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

  @override
  Widget build(BuildContext context) {
    final s = widget.suggestion;
    final size = MediaQuery.of(context).size;
    final narrow = size.width < 640;

    // Rich header — X only in the wide dialog; the narrow page uses the chevron.
    Widget richHeader({required bool showClose}) => Padding(
          padding: EdgeInsets.fromLTRB(20, showClose ? 18 : 12, 12, 12),
          child: Row(
            children: [
              _CategoryIconBox(s.categoryKey, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.category,
                        style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: AdminUi.textPrimary)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(s.shortId,
                            style: const TextStyle(
                                fontSize: 12, color: AdminUi.textMuted)),
                        const SizedBox(width: 8),
                        StatusPill(
                          label: suggestionStatusLabel(_status),
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
            isAnonymous: s.isAnonymous,
            name: s.submitterName,
            photoUrl: s.submitterPhotoUrl,
            role: s.submitterRole,
          ),
          const SizedBox(height: 20),
          _sectionTitle('DETAILS'),
          const SizedBox(height: 8),
          Text(
            s.details.trim().isEmpty ? '—' : s.details,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: AdminUi.textPrimary,
            ),
          ),
          const SizedBox(height: 20),
          _sectionTitle('LOCATION'),
          const SizedBox(height: 8),
          _LocationBlock(suggestion: s),
          const SizedBox(height: 20),
          _sectionTitle('ATTACHMENTS'),
          const SizedBox(height: 10),
          _MediaGallery(future: _mediaFuture),
          const SizedBox(height: 22),
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

    // Narrow → full-screen page.
    if (narrow) {
      return AdminDetailScaffold(
        title: 'Suggestion details',
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

class _LocationBlock extends StatelessWidget {
  final AdminSuggestion suggestion;
  const _LocationBlock({required this.suggestion});

  @override
  Widget build(BuildContext context) {
    final s = suggestion;
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
        (s.barangay == null || s.barangay!.isEmpty) ? null : s.barangay!;
    final address =
        (s.address == null || s.address!.isEmpty) ? null : s.address!;
    if (barangay != null) add(Icons.location_city_rounded, barangay);
    if (address != null) add(Icons.signpost_rounded, address);
    if (s.hasLocation) {
      add(Icons.my_location_rounded,
          '${s.latitude!.toStringAsFixed(6)}, ${s.longitude!.toStringAsFixed(6)}');
    }
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
  final Future<List<SuggestionMedia>> future;
  const _MediaGallery({required this.future});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SuggestionMedia>>(
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
        final media = snap.data ?? const <SuggestionMedia>[];
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
  final SuggestionMedia item;
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
