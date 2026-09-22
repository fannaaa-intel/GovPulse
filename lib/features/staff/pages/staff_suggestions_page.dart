// ════════════════════════════════════════════════════════════════════════════
//  Staff — Suggestions
//
//  Citizen suggestions routed to this office by migration 20260922000000.
//  Staff may DRAFT a reply; it reaches the citizen only after an admin
//  approves it, so every composer here says so plainly. A staff member who
//  believes they have published something the citizen cannot see is the
//  confusion this page is written to prevent.
//
//  RESPONSIVENESS: one column below `_kTwoPaneFrom`, list + detail above it.
//  The detail opens as a full-screen sheet on phones and inline on wide
//  screens — the same shape the reports page uses, so the console does not
//  change idiom between sections.
// ════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/staff_engagement_repository.dart';
import '../providers/staff_engagement_providers.dart';
import '../providers/staff_providers.dart';
import '../theme/staff_ui.dart';
import '../widgets/staff_common.dart';

/// Below this the page is a single column and the detail is a sheet.
const double _kTwoPaneFrom = 900;

/// Below this the filter row scrolls horizontally instead of wrapping — at
/// ~360px a wrapped row of five chips becomes three ragged lines.
const double _kChipScrollBelow = 520;

enum _SuggestionFilter { all, awaiting, pending, published, returned }

String _filterLabel(_SuggestionFilter f) => switch (f) {
      _SuggestionFilter.all => 'All',
      _SuggestionFilter.awaiting => 'Needs reply',
      _SuggestionFilter.pending => 'Awaiting approval',
      _SuggestionFilter.published => 'Published',
      _SuggestionFilter.returned => 'Returned',
    };

class StaffSuggestionsPage extends ConsumerStatefulWidget {
  /// Deep-link target: a suggestion id to open and highlight on arrival.
  final String? highlightId;
  const StaffSuggestionsPage({super.key, this.highlightId});

  @override
  ConsumerState<StaffSuggestionsPage> createState() =>
      _StaffSuggestionsPageState();
}

class _StaffSuggestionsPageState extends ConsumerState<StaffSuggestionsPage> {
  _SuggestionFilter _filter = _SuggestionFilter.all;
  String _query = '';
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.highlightId;
    _revealIfFiltered(widget.highlightId);
  }

  @override
  void didUpdateWidget(covariant StaffSuggestionsPage old) {
    super.didUpdateWidget(old);
    if (widget.highlightId != null && widget.highlightId != old.highlightId) {
      setState(() => _selectedId = widget.highlightId);
      _revealIfFiltered(widget.highlightId);
    }
  }

  /// A deep link onto a row the active filter excludes does nothing at all —
  /// the tap "works", the list does not move, and it reads as a broken link.
  /// Dropping to `all` guarantees the target is in the list before we select
  /// it.
  void _revealIfFiltered(String? id) {
    if (id == null) return;
    if (_filter != _SuggestionFilter.all) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _filter = _SuggestionFilter.all);
      });
    }
  }

  /// Lets the KPI tiles drive the filter chips, so a count is a way IN to the
  /// rows it counts rather than a figure you then have to go find.
  void applyFilter(_SuggestionFilter f) => setState(() => _filter = f);

  List<StaffSuggestion> _apply(List<StaffSuggestion> all) {
    Iterable<StaffSuggestion> out = all;
    out = switch (_filter) {
      _SuggestionFilter.all => out,
      _SuggestionFilter.awaiting => out.where((s) => !s.isAnswered),
      _SuggestionFilter.pending =>
        out.where((s) => s.replyState == ReplyState.pending),
      _SuggestionFilter.published =>
        out.where((s) => s.replyState == ReplyState.approved),
      _SuggestionFilter.returned =>
        out.where((s) => s.replyState == ReplyState.rejected),
    };
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      out = out.where((s) =>
          s.details.toLowerCase().contains(q) ||
          s.categoryLabel.toLowerCase().contains(q) ||
          (s.barangay ?? '').toLowerCase().contains(q));
    }
    return out.toList();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(staffSuggestionsProvider);
    final stale = ref.watch(staffSuggestionsStaleProvider);

    return StaffPageBody(
      onRefresh: () => ref.read(staffSuggestionsProvider.notifier).refresh(),
      maxWidth: 1240,
      // Value first, THEN loading/error.
      //
      // `when` routes on isLoading and hasError AHEAD of the value it is still
      // holding, so a refetch — which is what sending a reply triggers —
      // replaced the whole page with the skeleton for the length of a round
      // trip, and a failed refetch replaced it with an error page. Once rows
      // are on screen they stay on screen; a failed refresh is reported by the
      // stale banner, which exists for exactly that. `skipLoadingOnRefresh`
      // would cover the first case alone, not the error one.
      child: async.when(
        skipLoadingOnRefresh: true,
        loading: () => const StaffListPageSkeleton(
          twoPaneFrom: _kTwoPaneFrom,
        ),
        error: (e, _) => async.hasValue
            ? _content(async.requireValue, true)
            : StaffErrorState(
                message: 'Suggestions could not be loaded.',
                onRetry: () =>
                    ref.read(staffSuggestionsProvider.notifier).refresh(),
              ),
        data: (all) => _content(all, stale),
      ),
    );
  }

  Widget _content(List<StaffSuggestion> all, bool stale) {
          final items = _apply(all);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (stale) const _StaleBanner(),
              _Header(
                total: all.length,
                awaiting: all.where((s) => !s.isAnswered).length,
              ),
              const SizedBox(height: 14),
              // The same KPI row Feedback carries. Two list pages in one
              // console should open the same way.
              _SummaryTiles(all: all),
              const SizedBox(height: 14),
              _Filters(
                active: _filter,
                query: _query,
                onFilter: (f) => setState(() => _filter = f),
                onQuery: (q) => setState(() => _query = q),
              ),
              const SizedBox(height: 14),
              if (items.isEmpty)
                StaffEmptyState(
                  icon: Icons.lightbulb_outline_rounded,
                  title: all.isEmpty
                      ? 'No suggestions yet'
                      : 'Nothing matches this filter',
                  subtitle: all.isEmpty
                      ? 'Citizen ideas routed to your office will appear here.'
                      : 'Try a different filter or clear the search.',
                )
              else
                LayoutBuilder(
                  builder: (context, c) {
                    final twoPane = c.maxWidth >= _kTwoPaneFrom;
                    if (!twoPane) {
                      return Column(
                        children: [
                          for (final s in items)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _SuggestionCard(
                                item: s,
                                selected: false,
                                highlighted: s.id == widget.highlightId,
                                onTap: () => _openSheet(s),
                              ),
                            ),
                        ],
                      );
                    }
                    final selected = items.firstWhere(
                      (s) => s.id == _selectedId,
                      orElse: () => items.first,
                    );
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 380,
                          child: Column(
                            children: [
                              for (final s in items)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _SuggestionCard(
                                    item: s,
                                    selected: s.id == selected.id,
                                    highlighted: s.id == widget.highlightId,
                                    onTap: () =>
                                        setState(() => _selectedId = s.id),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _SuggestionDetail(
                            key: ValueKey(selected.id),
                            item: selected,
                            inSheet: false,
                          ),
                        ),
                      ],
                    );
                  },
                ),
            ],
          );
  }

  void _openSheet(StaffSuggestion s) {
    setState(() => _selectedId = s.id);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.5,
        maxChildSize: 0.96,
        expand: false,
        builder: (_, controller) => Container(
          decoration: const BoxDecoration(
            color: StaffUi.pageBg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: StaffUi.borderStrong,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
                  child: _SuggestionDetail(item: s, inSheet: true),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Header ──────────────────────────────────────────────────────────────────

/// The four counts that drive a staff member's day, each tapping through to
/// the filter that shows those rows.
class _SummaryTiles extends StatelessWidget {
  final List<StaffSuggestion> all;
  const _SummaryTiles({required this.all});

  @override
  Widget build(BuildContext context) {
    final awaiting = all.where((s) => !s.isAnswered).length;
    final pending =
        all.where((s) => s.replyState == ReplyState.pending).length;
    final published =
        all.where((s) => s.replyState == ReplyState.approved).length;
    final returned =
        all.where((s) => s.replyState == ReplyState.rejected).length;

    final page =
        context.findAncestorStateOfType<_StaffSuggestionsPageState>();
    void go(_SuggestionFilter f) => page?.applyFilter(f);

    return StaffKpiRow(
      tiles: [
        StaffKpiTile(
          value: '$awaiting',
          label: 'Need a reply',
          icon: Icons.edit_outlined,
          color: awaiting > 0 ? StaffUi.warn : StaffUi.textMuted,
          onTap: () => go(_SuggestionFilter.awaiting),
        ),
        StaffKpiTile(
          value: '$pending',
          label: 'Awaiting approval',
          icon: Icons.hourglass_top_rounded,
          color: StaffUi.accentSoft,
          onTap: () => go(_SuggestionFilter.pending),
        ),
        StaffKpiTile(
          value: '$published',
          label: 'Published',
          icon: Icons.check_circle_outline_rounded,
          color: StaffUi.online,
          onTap: () => go(_SuggestionFilter.published),
        ),
        StaffKpiTile(
          value: '$returned',
          label: 'Returned to you',
          icon: Icons.undo_rounded,
          color: returned > 0 ? StaffUi.danger : StaffUi.textMuted,
          onTap: () => go(_SuggestionFilter.returned),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final int total;
  final int awaiting;
  const _Header({required this.total, required this.awaiting});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final tight = c.maxWidth < 560;
        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Suggestions',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: StaffUi.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Citizen ideas routed to your office',
              style: const TextStyle(fontSize: 13, color: StaffUi.textMuted),
            ),
          ],
        );
        final stats = Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            StaffPill(
              label: '$total total',
              color: StaffUi.accent,
              icon: Icons.lightbulb_outline_rounded,
            ),
            if (awaiting > 0)
              StaffPill(
                label: '$awaiting need a reply',
                color: StaffUi.warn,
                icon: Icons.schedule_rounded,
              ),
          ],
        );
        if (tight) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [title, const SizedBox(height: 10), stats],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Flexible, not Expanded: the title takes only what it needs and
            // the stats keep their natural width rather than being pushed off.
            Flexible(child: title),
            const SizedBox(width: 12),
            stats,
          ],
        );
      },
    );
  }
}

// ── Filters ─────────────────────────────────────────────────────────────────

class _Filters extends StatelessWidget {
  final _SuggestionFilter active;
  final String query;
  final ValueChanged<_SuggestionFilter> onFilter;
  final ValueChanged<String> onQuery;
  const _Filters({
    required this.active,
    required this.query,
    required this.onFilter,
    required this.onQuery,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final chips = [
          for (final f in _SuggestionFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _Chip(
                label: _filterLabel(f),
                selected: f == active,
                onTap: () => onFilter(f),
              ),
            ),
        ];
        final search = _SearchField(value: query, onChanged: onQuery);

        // Narrow: chips scroll on their own line, search sits below at full
        // width. Wrapping five chips at 360px produces three ragged lines.
        if (c.maxWidth < _kChipScrollBelow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: chips),
              ),
              const SizedBox(height: 10),
              search,
            ],
          );
        }
        return Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: chips),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(width: 240, child: search),
          ],
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? StaffUi.accent : StaffUi.surface,
      borderRadius: BorderRadius.circular(StaffUi.controlRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(StaffUi.controlRadius),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(StaffUi.controlRadius),
            border: Border.all(
              color: selected ? StaffUi.accent : StaffUi.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : StaffUi.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _SearchField({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: value,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Search suggestions',
        hintStyle: const TextStyle(fontSize: 13, color: StaffUi.textMuted),
        prefixIcon: const Icon(Icons.search_rounded, size: 18),
        prefixIconConstraints:
            const BoxConstraints(minWidth: 36, minHeight: 36),
        filled: true,
        fillColor: StaffUi.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(StaffUi.controlRadius),
          borderSide: const BorderSide(color: StaffUi.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(StaffUi.controlRadius),
          borderSide: const BorderSide(color: StaffUi.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(StaffUi.controlRadius),
          borderSide: const BorderSide(color: StaffUi.accent, width: 1.5),
        ),
      ),
    );
  }
}

// ── List card ───────────────────────────────────────────────────────────────

class _SuggestionCard extends StatelessWidget {
  final StaffSuggestion item;
  final bool selected;
  final bool highlighted;
  final VoidCallback onTap;
  const _SuggestionCard({
    required this.item,
    required this.selected,
    required this.highlighted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(StaffUi.cardRadius),
        border: Border.all(
          color: selected
              ? StaffUi.accent
              : (highlighted ? StaffUi.warn : Colors.transparent),
          width: selected || highlighted ? 2 : 0,
        ),
      ),
      child: StaffCard(
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Flexible + ellipsis: a long "Others" label written by the
                // citizen must shrink rather than overflow the row.
                Flexible(
                  child: Text(
                    item.categoryLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: StaffUi.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _ReplyPill(item: item),
              ],
            ),
            const SizedBox(height: 6),
            // The body always occupies TWO lines, whether the text fills them
            // or not. maxLines caps the tall case but does nothing for the
            // short one, so a one-line suggestion made a card ~17px shorter
            // than its neighbour and the column came out ragged.
            SizedBox(
              height: 12.5 * 1.35 * 2,
              width: double.infinity,
              child: Text(
                item.details,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: StaffUi.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (item.wasAiRouted)
                  const StaffPill(
                    label: 'Routed by AI',
                    color: StaffUi.accentSoft,
                    icon: Icons.auto_awesome_rounded,
                  ),
                if ((item.barangay ?? '').isNotEmpty)
                  StaffPill(
                    label: item.barangay!,
                    color: StaffUi.textMuted,
                    icon: Icons.place_outlined,
                  ),
                Text(
                  _ago(item.createdAt),
                  style: const TextStyle(
                    fontSize: 11,
                    color: StaffUi.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReplyPill extends StatelessWidget {
  final StaffSuggestion item;
  const _ReplyPill({required this.item});

  @override
  Widget build(BuildContext context) => switch (item.replyState) {
        ReplyState.pending => const StaffPill(
            label: 'Awaiting approval',
            color: StaffUi.warn,
            icon: Icons.hourglass_top_rounded,
          ),
        ReplyState.approved => const StaffPill(
            label: 'Published',
            color: StaffUi.online,
            icon: Icons.check_circle_outline_rounded,
          ),
        ReplyState.rejected => const StaffPill(
            label: 'Returned',
            color: StaffUi.danger,
            icon: Icons.undo_rounded,
          ),
        ReplyState.none => item.isAnswered
            ? const StaffPill(
                label: 'Answered',
                color: StaffUi.online,
                icon: Icons.check_circle_outline_rounded,
              )
            : const StaffPill(
                label: 'Needs reply',
                color: StaffUi.accent,
                icon: Icons.edit_outlined,
              ),
      };
}

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  return '${t.day}/${t.month}/${t.year}';
}

// ── Detail + composer ───────────────────────────────────────────────────────

class _SuggestionDetail extends ConsumerStatefulWidget {
  final StaffSuggestion item;
  final bool inSheet;
  const _SuggestionDetail({
    super.key,
    required this.item,
    required this.inSheet,
  });

  @override
  ConsumerState<_SuggestionDetail> createState() => _SuggestionDetailState();
}

class _SuggestionDetailState extends ConsumerState<_SuggestionDetail> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.item.replyBody ?? '');

  /// Guards the write itself, not just the button's appearance. A flag that
  /// only reaches the widget tree still allows a second tap in the same frame
  /// before the rebuild lands.
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy) return;
    final body = _ctrl.text.trim();
    // Name the field. A bare `return` here reads as a dead button.
    if (body.isEmpty) {
      setState(() => _error = 'Write your reply before sending it for approval.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final n = ref.read(staffSuggestionsProvider.notifier);
      if (widget.item.canEdit(
          ref.read(staffIdentityProvider).valueOrNull?.userId)) {
        await n.reviseReply(widget.item.replyId!, body);
      } else {
        await n.submitReply(widget.item.id, body);
      }
      if (!mounted) return;
      if (widget.inSheet) Navigator.of(context).maybePop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sent to the Municipality for approval.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error =
          'Your reply could not be sent. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.item;
    final myId = ref.watch(staffIdentityProvider).valueOrNull?.userId;
    final canEdit = s.canEdit(myId);
    // Pending or published closes the composer: two staff answering the same
    // item, or one re-answering an answered one, is the failure this prevents.
    final composerOpen = !s.isAnswered || canEdit;

    // ONE card, with internal dividers between its parts.
    //
    // This was three or four separate StaffCards stacked with 12px gaps, so a
    // single suggestion read as a pile of unrelated floating boxes rather than
    // as one record. The status notice and the composer belong TO this
    // suggestion; separating them with a gap implied they were peers of it.
    return StaffCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      s.categoryLabel,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: StaffUi.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _ReplyPill(item: s),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  StaffPill(
                    label: s.isAnonymous ? 'Anonymous' : 'Citizen',
                    color: StaffUi.textMuted,
                    icon: s.isAnonymous
                        ? Icons.visibility_off_outlined
                        : Icons.person_outline_rounded,
                  ),
                  if ((s.barangay ?? '').isNotEmpty)
                    StaffPill(
                      label: s.barangay!,
                      color: StaffUi.textMuted,
                      icon: Icons.place_outlined,
                    ),
                  StaffPill(
                    label: _ago(s.createdAt),
                    color: StaffUi.textMuted,
                    icon: Icons.schedule_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                s.details,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: StaffUi.textPrimary,
                ),
              ),
              if (s.wasAiRouted) ...[
                const SizedBox(height: 14),
                _AiRoutedNote(item: s),
              ],
            ],
          ),
        ),
        if (s.replyState == ReplyState.rejected &&
            (s.replyRejectedReason ?? '').trim().isNotEmpty) ...[
          const _CardDivider(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: _Notice(
              color: StaffUi.danger,
              icon: Icons.undo_rounded,
              title: 'Returned for changes',
              body: s.replyRejectedReason!.trim(),
            ),
          ),
        ],
        if (s.replyState == ReplyState.pending) ...[
          const _CardDivider(),
          const Padding(
            padding: EdgeInsets.all(16),
            child: _Notice(
              color: StaffUi.warn,
              icon: Icons.hourglass_top_rounded,
              title: 'Waiting for the Municipality',
              body: 'Your reply has been sent for approval. The citizen will '
                  'not see it — and will not be notified — until it is '
                  'approved.',
            ),
          ),
        ],
        if (s.replyState == ReplyState.approved ||
            (s.adminResponse ?? '').trim().isNotEmpty) ...[
          const _CardDivider(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: _Notice(
              color: StaffUi.online,
              icon: Icons.check_circle_outline_rounded,
              title: 'Published to the citizen',
              body: (s.replyBody ?? s.adminResponse ?? '').trim(),
            ),
          ),
        ],
        if (composerOpen) ...[
          const _CardDivider(),
          _composer(canEdit),
        ],
      ],
      ),
    );
  }

  Widget _composer(bool canEdit) {
    // No StaffCard of its own: it is a SECTION of the detail card now, so it
    // carries only padding. A card inside a card draws two borders.
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.edit_outlined, size: 16, color: StaffUi.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  canEdit ? 'Revise your reply' : 'Write a reply',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: StaffUi.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'The Municipality reviews every reply before the citizen sees it.',
            style: TextStyle(fontSize: 12, color: StaffUi.textMuted),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _ctrl,
            maxLines: 5,
            minLines: 3,
            enabled: !_busy,
            textInputAction: TextInputAction.newline,
            style: const TextStyle(fontSize: 13.5, height: 1.45),
            decoration: InputDecoration(
              hintText: 'Answer the citizen in plain language…',
              hintStyle: const TextStyle(fontSize: 13, color: StaffUi.textMuted),
              filled: true,
              fillColor: StaffUi.subtle,
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(StaffUi.controlRadius),
                borderSide: const BorderSide(color: StaffUi.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(StaffUi.controlRadius),
                borderSide: const BorderSide(color: StaffUi.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(StaffUi.controlRadius),
                borderSide: const BorderSide(color: StaffUi.accent, width: 1.5),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline_rounded,
                    size: 15, color: StaffUi.danger),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: StaffUi.danger,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            height: 42,
            child: FilledButton.icon(
              onPressed: _busy ? null : _send,
              style: FilledButton.styleFrom(
                backgroundColor: StaffUi.accent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(StaffUi.controlRadius),
                ),
              ),
              icon: _busy
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_rounded, size: 16),
              label: Text(_busy ? 'Sending…' : 'Send for approval'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Explains why an item the citizen filed as "Others" is sitting in this
/// office. An unexplained move looks like a routing bug.
class _AiRoutedNote extends StatelessWidget {
  final StaffSuggestion item;
  const _AiRoutedNote({required this.item});

  @override
  Widget build(BuildContext context) {
    final reason = (item.aiCategoryReason ?? '').trim();
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: StaffUi.accentWash,
        borderRadius: BorderRadius.circular(StaffUi.controlRadius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.auto_awesome_rounded,
              size: 15, color: StaffUi.accentSoft),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Routed to your office automatically',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: StaffUi.accent,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  reason.isEmpty
                      ? 'The citizen chose "Others", so this was classified '
                          'from what they wrote.'
                      : reason,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: StaffUi.textSecondary,
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

class _Notice extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final String body;
  const _Notice({
    required this.color,
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(StaffUi.cardRadius),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    body,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: StaffUi.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StaleBanner extends StatelessWidget {
  const _StaleBanner();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _Notice(
          color: StaffUi.warn,
          icon: Icons.cloud_off_rounded,
          title: 'Showing older data',
          body: 'The last refresh failed. Pull down to try again.',
        ),
      );
}

/// A hairline between two sections of the detail card. Full-bleed, so it reads
/// as a division of one panel rather than a gap between two.
class _CardDivider extends StatelessWidget {
  const _CardDivider();
  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, thickness: 1, color: StaffUi.border);
}
