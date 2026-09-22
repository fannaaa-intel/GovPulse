// ════════════════════════════════════════════════════════════════════════════
//  Staff — Feedback
//
//  Citizen service ratings for this office, routed by migration
//  20260922000000. READ ONLY, deliberately: staff never author the public reply
//  to a rating of their own office. Letting the subject of a complaint write
//  its own public answer is not a review process. The Municipality replies.
//
//  This page is never reached by an office that cannot receive feedback (see
//  `departmentReceivesFeedback`) — the console omits the nav item entirely
//  rather than open a room that can never fill.
//
//  ANONYMITY: an anonymous rating still counts in every average and still needs
//  reading. Only the NAME is hidden, and it is hidden in the database by
//  `staff_feedbacks_view`, not here.
// ════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/staff_engagement_repository.dart';
import '../providers/staff_engagement_providers.dart';
import '../theme/staff_ui.dart';
import '../widgets/staff_common.dart';

/// Below this the summary tiles stack two-up instead of four across.
const double _kTilesFourFrom = 720;

/// Below this the detail opens as a sheet rather than beside the list.
const double _kTwoPaneFrom = 900;

class StaffFeedbackPage extends ConsumerStatefulWidget {
  final String? highlightId;
  const StaffFeedbackPage({super.key, this.highlightId});

  @override
  ConsumerState<StaffFeedbackPage> createState() => _StaffFeedbackPageState();
}

class _StaffFeedbackPageState extends ConsumerState<StaffFeedbackPage> {
  RatingBand? _band;
  String _query = '';
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.highlightId;
    _revealIfFiltered(widget.highlightId);
  }

  @override
  void didUpdateWidget(covariant StaffFeedbackPage old) {
    super.didUpdateWidget(old);
    if (widget.highlightId != null && widget.highlightId != old.highlightId) {
      setState(() => _selectedId = widget.highlightId);
      _revealIfFiltered(widget.highlightId);
    }
  }

  /// A deep link onto a row the active band filters out silently does nothing.
  void _revealIfFiltered(String? id) {
    if (id == null || _band == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _band = null);
    });
  }

  /// Lets a KPI tile drive the band chips, so a count is a way IN to the rows
  /// it counts.
  void applyBand(RatingBand? b) => setState(() => _band = b);

  List<StaffFeedback> _apply(List<StaffFeedback> all) {
    Iterable<StaffFeedback> out = all;
    if (_band == RatingBand.low) {
      out = out.where((f) => f.overallRating >= 1 && f.overallRating <= 2);
    } else if (_band == RatingBand.high) {
      out = out.where((f) => f.overallRating >= 4);
    }
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      out = out.where((f) =>
          (f.comment ?? '').toLowerCase().contains(q) ||
          f.serviceName.toLowerCase().contains(q) ||
          f.officeLabel.toLowerCase().contains(q));
    }
    return out.toList();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(staffFeedbackProvider);
    final stale = ref.watch(staffFeedbackStaleProvider);

    return StaffPageBody(
      onRefresh: () => ref.read(staffFeedbackProvider.notifier).refresh(),
      maxWidth: 1240,
      // Value first, THEN loading/error — see the note on the Suggestions
      // page. Once rows are on screen a refetch must not replace them with a
      // skeleton, and a failed refetch is reported by the "Showing older data"
      // notice rather than by discarding the page.
      child: async.when(
        skipLoadingOnRefresh: true,
        loading: () => const StaffListPageSkeleton(
          panelHeight: 176,
          twoPaneFrom: _kTwoPaneFrom,
        ),
        error: (e, _) => async.hasValue
            ? _content(async.requireValue, true)
            : StaffErrorState(
                message: 'Feedback could not be loaded.',
                onRetry: () =>
                    ref.read(staffFeedbackProvider.notifier).refresh(),
              ),
        data: (all) => _content(all, stale),
      ),
    );
  }

  Widget _content(List<StaffFeedback> all, bool stale) {
          final items = _apply(all);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (stale)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: _Notice(
                    color: StaffUi.warn,
                    icon: Icons.cloud_off_rounded,
                    title: 'Showing older data',
                    body: 'The last refresh failed. Pull down to try again.',
                  ),
                ),
              const _Header(),
              const SizedBox(height: 14),
              _SummaryTiles(all: all),
              const SizedBox(height: 14),
              _RatingMixPanel(all: all),
              const SizedBox(height: 14),
              _Filters(
                band: _band,
                query: _query,
                onBand: (b) => setState(() => _band = b),
                onQuery: (q) => setState(() => _query = q),
              ),
              const SizedBox(height: 14),
              if (items.isEmpty)
                StaffEmptyState(
                  icon: Icons.reviews_outlined,
                  title: all.isEmpty
                      ? 'No feedback yet'
                      : 'Nothing matches this filter',
                  subtitle: all.isEmpty
                      ? 'Ratings for your office will appear here.'
                      : 'Try a different rating band or clear the search.',
                )
              else
                LayoutBuilder(
                  builder: (context, c) {
                    if (c.maxWidth < _kTwoPaneFrom) {
                      return Column(
                        children: [
                          for (final f in items)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _FeedbackCard(
                                item: f,
                                selected: false,
                                highlighted: f.id == widget.highlightId,
                                onTap: () => _openSheet(f),
                              ),
                            ),
                        ],
                      );
                    }
                    final selected = items.firstWhere(
                      (f) => f.id == _selectedId,
                      orElse: () => items.first,
                    );
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 380,
                          child: Column(
                            children: [
                              for (final f in items)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _FeedbackCard(
                                    item: f,
                                    selected: f.id == selected.id,
                                    highlighted: f.id == widget.highlightId,
                                    onTap: () =>
                                        setState(() => _selectedId = f.id),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _FeedbackDetail(
                            key: ValueKey(selected.id),
                            item: selected,
                          ),
                        ),
                      ],
                    );
                  },
                ),
            ],
          );
  }

  void _openSheet(StaffFeedback f) {
    setState(() => _selectedId = f.id);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.86,
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
                  child: _FeedbackDetail(item: f),
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

class _Header extends StatelessWidget {
  const _Header();
  @override
  Widget build(BuildContext context) => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Feedback',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: StaffUi.textPrimary,
            ),
          ),
          SizedBox(height: 2),
          Text(
            'How citizens rated your office. The Municipality writes the replies.',
            style: TextStyle(fontSize: 13, color: StaffUi.textMuted),
          ),
        ],
      );
}

// ── Summary tiles ───────────────────────────────────────────────────────────

class _SummaryTiles extends ConsumerWidget {
  final List<StaffFeedback> all;
  const _SummaryTiles({required this.all});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avg = ref.watch(staffAverageRatingProvider);
    final low = ref.watch(staffLowRatingsProvider);
    final page = context.findAncestorStateOfType<_StaffFeedbackPageState>();

    return StaffKpiRow(
      fourFrom: _kTilesFourFrom,
      tiles: [
        StaffKpiTile(
          // Null reads as "no ratings yet". A brand-new office must never show
          // 0.0, which looks like the worst possible score rather than no data.
          value: avg == null ? '—' : avg.toStringAsFixed(1),
          label: 'Average rating',
          icon: Icons.star_rounded,
          color: const Color(0xFFF5A623),
        ),
        StaffKpiTile(
          value: '${all.length}',
          label: 'Total ratings',
          icon: Icons.reviews_outlined,
          color: StaffUi.accent,
          onTap: () => page?.applyBand(null),
        ),
        StaffKpiTile(
          value: '$low',
          label: 'Low (1-2 stars) this week',
          icon: Icons.trending_down_rounded,
          color: low > 0 ? StaffUi.danger : StaffUi.textMuted,
          onTap: () => page?.applyBand(RatingBand.low),
        ),
        StaffKpiTile(
          value:
              '${all.where((f) => (f.comment ?? '').trim().isNotEmpty).length}',
          label: 'With comments',
          icon: Icons.chat_bubble_outline_rounded,
          color: StaffUi.accentSoft,
        ),
      ],
    );
  }
}

// ── Rating mix ──────────────────────────────────────────────────────────────

/// A star histogram. An average of 3.0 can be "everyone is lukewarm" or "half
/// love it, half hate it", and those call for opposite responses — the average
/// alone cannot tell them apart.
class _RatingMixPanel extends ConsumerWidget {
  final List<StaffFeedback> all;
  const _RatingMixPanel({required this.all});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mix = ref.watch(staffRatingMixProvider);
    final total = mix.fold<int>(0, (a, b) => a + b);
    if (total == 0) return const SizedBox.shrink();

    return StaffCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Rating mix',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: StaffUi.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          // 5★ first: people read a rating breakdown top-down from best.
          for (var star = 5; star >= 1; star--) ...[
            _MixRow(
              star: star,
              count: mix[star - 1],
              total: total,
            ),
            if (star > 1) const SizedBox(height: 7),
          ],
        ],
      ),
    );
  }
}

class _MixRow extends StatelessWidget {
  final int star;
  final int count;
  final int total;
  const _MixRow({
    required this.star,
    required this.count,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    // Normalised to the TOTAL, not to the largest bucket. Scaling to the
    // biggest bucket renders an even 1-1-1-1-1 split as five full-width bars,
    // which reads as "everything is maxed" and makes the bar length carry no
    // information at all. Against the total, a bar's length always means the
    // same thing as the percentage beside it.
    final frac = total == 0 ? 0.0 : count / total;
    final pct = total == 0 ? 0 : (count * 100 / total).round();
    return Row(
      children: [
        SizedBox(
          width: 34,
          child: Row(
            children: [
              Text(
                '$star',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: StaffUi.textSecondary,
                ),
              ),
              const SizedBox(width: 2),
              const Icon(Icons.star_rounded,
                  size: 12, color: Color(0xFFF5A623)),
            ],
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 9,
              backgroundColor: StaffUi.subtle,
              valueColor: AlwaysStoppedAnimation(
                star >= 4
                    ? StaffUi.online
                    : (star == 3 ? StaffUi.warn : StaffUi.danger),
              ),
            ),
          ),
        ),
        SizedBox(
          width: 56,
          child: Text(
            '$count ($pct%)',
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: StaffUi.textMuted),
          ),
        ),
      ],
    );
  }
}

// ── Filters ─────────────────────────────────────────────────────────────────

class _Filters extends StatelessWidget {
  final RatingBand? band;
  final String query;
  final ValueChanged<RatingBand?> onBand;
  final ValueChanged<String> onQuery;
  const _Filters({
    required this.band,
    required this.query,
    required this.onBand,
    required this.onQuery,
  });

  @override
  Widget build(BuildContext context) {
    final chips = [
      _Chip(label: 'All', selected: band == null, onTap: () => onBand(null)),
      const SizedBox(width: 8),
      _Chip(
        label: 'Low 1-2 stars',
        selected: band == RatingBand.low,
        onTap: () => onBand(RatingBand.low),
      ),
      const SizedBox(width: 8),
      _Chip(
        label: 'High 4-5 stars',
        selected: band == RatingBand.high,
        onTap: () => onBand(RatingBand.high),
      ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final search = _SearchField(value: query, onChanged: onQuery);
        if (c.maxWidth < 520) {
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
            border:
                Border.all(color: selected ? StaffUi.accent : StaffUi.border),
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
        hintText: 'Search feedback',
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

// ── Cards ───────────────────────────────────────────────────────────────────

class _FeedbackCard extends StatelessWidget {
  final StaffFeedback item;
  final bool selected;
  final bool highlighted;
  final VoidCallback onTap;
  const _FeedbackCard({
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
                StaffStarRow(item.overallRating),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    feedbackRatingLabel(item.overallRating),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: StaffUi.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              item.serviceName.isEmpty ? item.officeLabel : item.serviceName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: StaffUi.textPrimary,
              ),
            ),
            // The comment slot is ALWAYS two lines tall, even when the citizen
            // left no comment. Rendering it conditionally made a rating with a
            // comment ~40px taller than one without, so a mixed list came out
            // ragged. A rating with no comment says so rather than showing a
            // blank gap.
            const SizedBox(height: 5),
            SizedBox(
              height: 12.5 * 1.35 * 2,
              width: double.infinity,
              child: Text(
                (item.comment ?? '').trim().isEmpty
                    ? 'No comment left.'
                    : item.comment!.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  fontStyle: (item.comment ?? '').trim().isEmpty
                      ? FontStyle.italic
                      : FontStyle.normal,
                  color: (item.comment ?? '').trim().isEmpty
                      ? StaffUi.textMuted
                      : StaffUi.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 9),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                StaffPill(
                  label: item.displayName,
                  color: StaffUi.textMuted,
                  icon: item.isAnonymous
                      ? Icons.visibility_off_outlined
                      : Icons.person_outline_rounded,
                ),
                Text(
                  _ago(item.createdAt),
                  style:
                      const TextStyle(fontSize: 11, color: StaffUi.textMuted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  return '${t.day}/${t.month}/${t.year}';
}

// ── Detail ──────────────────────────────────────────────────────────────────

class _FeedbackDetail extends StatelessWidget {
  final StaffFeedback item;
  const _FeedbackDetail({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final aspects = <(String, int?)>[
      ('Staff', item.aspectStaff),
      ('Waiting time', item.aspectWait),
      ('Clarity', item.aspectClarity),
      ('Facility', item.aspectFacility),
    ].where((a) => a.$2 != null && a.$2! > 0).toList();

    // ONE card with internal dividers, matching the Suggestions detail. This
    // was three floating cards stacked with gaps, so a single rating read as
    // three unrelated boxes rather than one record.
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
                  StaffStarRow(item.overallRating, size: 18),
                  const SizedBox(width: 9),
                  Flexible(
                    child: Text(
                      feedbackRatingLabel(item.overallRating),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: StaffUi.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                item.serviceName.isEmpty ? item.officeLabel : item.serviceName,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: StaffUi.textPrimary,
                ),
              ),
              if (item.serviceName.isNotEmpty &&
                  item.officeLabel.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  item.officeLabel,
                  style:
                      const TextStyle(fontSize: 12.5, color: StaffUi.textMuted),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  StaffPill(
                    label: item.displayName,
                    color: StaffUi.textMuted,
                    icon: item.isAnonymous
                        ? Icons.visibility_off_outlined
                        : Icons.person_outline_rounded,
                  ),
                  if (item.visitDate != null)
                    StaffPill(
                      label: 'Visited '
                          '${item.visitDate!.day}/${item.visitDate!.month}/'
                          '${item.visitDate!.year}',
                      color: StaffUi.textMuted,
                      icon: Icons.event_outlined,
                    ),
                  StaffPill(
                    label: _ago(item.createdAt),
                    color: StaffUi.textMuted,
                    icon: Icons.schedule_rounded,
                  ),
                ],
              ),
              if ((item.comment ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: StaffUi.subtle,
                    borderRadius: BorderRadius.circular(StaffUi.controlRadius),
                  ),
                  child: Text(
                    item.comment!.trim(),
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.5,
                      color: StaffUi.textPrimary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (aspects.isNotEmpty) ...[
          const _CardDivider(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Breakdown',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: StaffUi.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                for (var i = 0; i < aspects.length; i++) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          aspects[i].$1,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: StaffUi.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      StaffStarRow(aspects[i].$2!, size: 13),
                    ],
                  ),
                  if (i < aspects.length - 1) const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ],
        const _CardDivider(),
        Padding(
          padding: const EdgeInsets.all(16),
          child: (item.adminResponse ?? '').trim().isNotEmpty
              ? _Notice(
                  color: StaffUi.online,
                  icon: Icons.check_circle_outline_rounded,
                  title: 'The Municipality replied',
                  body: item.adminResponse!.trim(),
                )
              : const _Notice(
                  color: StaffUi.accent,
                  icon: Icons.info_outline_rounded,
                  title: 'Replies come from the Municipality',
                  body: 'Feedback about your office is answered centrally, so '
                      'this page is read-only. Raise anything urgent with the '
                      'Municipality directly.',
                ),
        ),
      ],
      ),
    );
  }
}

/// A hairline between two sections of the detail card.
class _CardDivider extends StatelessWidget {
  const _CardDivider();
  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, thickness: 1, color: StaffUi.border);
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
