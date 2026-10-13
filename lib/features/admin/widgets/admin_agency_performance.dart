// ════════════════════════════════════════════════════════════════════════════
//  Admin — Agency performance panel (Team page)
//
//  One line per external agency: how many reports the LGU endorsed to it, how
//  many it acknowledged and completed, how long that took, and how the
//  reporting citizens rated it. Below: the latest citizen comments.
//
//  Measured from each report's CURRENT endorsement. Re-endorsing a report
//  moves its timing to the new agency (the event log records no agency); its
//  earlier rating stays with the agency it was given to.
// ════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../staff/data/staff_departments.dart';
import '../providers/admin_agency_performance_provider.dart';
import '../theme/admin_ui.dart';
import 'admin_submission_ui.dart' show adminShortDate;

/// Below this panel width the table's seven columns stop fitting; each agency
/// becomes a card instead.
const double kAgencyTableMinWidth = 700;

String _pct(double? v) => v == null ? '—' : '${(v * 100).round()}%';
String _days(double? v) {
  if (v == null) return '—';
  if (v < 1) return '< 1 day';
  final s = v == v.roundToDouble()
      ? v.toStringAsFixed(0)
      : v.toStringAsFixed(1);
  return '$s day${s == '1' ? '' : 's'}';
}

/// "4 · 67%", or just "0" when there is nothing to take a share of.
String _withShare(int n, double? share) =>
    share == null ? '$n' : '$n · ${_pct(share)}';

String agencyStateLabel(String state) => switch (state) {
  'completed' => 'after completion',
  'received' => 'after receipt',
  _ => 'before receipt',
};

class AdminAgencyPerformance extends ConsumerWidget {
  const AdminAgencyPerformance({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminAgencyPerformanceProvider);
    return async.when(
      loading: () => const _Skeleton(),
      error: (e, _) => _ErrorCard(
        onRetry: () => ref.invalidate(adminAgencyPerformanceProvider),
      ),
      data: (d) => AgencyPerformanceView(data: d),
    );
  }
}

/// The panel body, separated from the provider so tests can pump it with data.
class AgencyPerformanceView extends StatelessWidget {
  final AgencyPerformanceData data;
  const AgencyPerformanceView({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Card(
          child: LayoutBuilder(
            builder: (context, c) => c.maxWidth >= kAgencyTableMinWidth
                ? _Table(rows: data.agencies)
                : _CardList(rows: data.agencies),
          ),
        ),
        const SizedBox(height: 10),
        const _HowCounted(),
        const SizedBox(height: 12),
        _Card(child: _Recent(items: data.recent)),
      ],
    );
  }
}

// ── Wide: table ──────────────────────────────────────────────────────────────

// Agency gets the most room: it carries the full name and status line.
const _flex = [5, 3, 3, 3, 3, 3, 3];
const _heads = [
  'Agency',
  'Endorsed',
  'Received',
  'Completed',
  'Avg. to receive',
  'Avg. to complete',
  'Citizen rating',
];

class _Table extends StatelessWidget {
  final List<AgencyPerformance> rows;
  const _Table({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: const BoxDecoration(
            color: AdminUi.subtle,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AdminUi.cardRadius),
            ),
          ),
          child: Row(
            children: [
              for (var i = 0; i < _heads.length; i++)
                Expanded(
                  flex: _flex[i],
                  child: Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Text(
                      _heads[i].toUpperCase(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .5,
                        color: AdminUi.textMuted,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const Divider(height: 1, color: AdminUi.border),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              children: [
                Expanded(
                  flex: _flex[0],
                  child: Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: _AgencyName(rows[i]),
                  ),
                ),
                Expanded(
                  flex: _flex[1],
                  child: _cell('${rows[i].endorsements}'),
                ),
                Expanded(
                  flex: _flex[2],
                  child: _cell(
                    '${rows[i].received}',
                    sub: _pct(rows[i].receivedShare),
                  ),
                ),
                Expanded(
                  flex: _flex[3],
                  child: _cell(
                    '${rows[i].completed}',
                    sub: _pct(rows[i].completedShare),
                  ),
                ),
                Expanded(
                  flex: _flex[4],
                  child: _cell(_days(rows[i].avgDaysToReceive)),
                ),
                Expanded(
                  flex: _flex[5],
                  child: _cell(_days(rows[i].avgDaysToComplete)),
                ),
                Expanded(flex: _flex[6], child: _Rating(rows[i])),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _cell(String main, {String? sub}) => Text.rich(
    TextSpan(
      text: main,
      style: const TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w700,
        color: AdminUi.textPrimary,
      ),
      children: [
        if (sub != null && sub != '—')
          TextSpan(
            text: '  $sub',
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AdminUi.textMuted,
            ),
          ),
      ],
    ),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );
}

class _AgencyName extends StatelessWidget {
  final AgencyPerformance a;
  const _AgencyName(this.a);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          a.agency,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            color: AdminUi.textPrimary,
          ),
        ),
        if (StaffDepartments.externalFullName(a.agency) case final full?)
          Text(
            full,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: AdminUi.textSecondary),
          ),
        if (a.awaiting > 0 || a.withdrawn > 0)
          Text(
            [
              if (a.awaiting > 0) '${a.awaiting} awaiting receipt',
              if (a.withdrawn > 0) '${a.withdrawn} withdrawn',
            ].join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: AdminUi.textMuted),
          ),
      ],
    );
  }
}

class _Rating extends StatelessWidget {
  final AgencyPerformance a;
  const _Rating(this.a);

  @override
  Widget build(BuildContext context) {
    if (a.ratings == 0 || a.avgStars == null) {
      return const Text(
        'No ratings yet',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12.5, color: AdminUi.textMuted),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.star_rounded, size: 16, color: Color(0xFFF59E0B)),
        const SizedBox(width: 3),
        Text(
          a.avgStars!.toStringAsFixed(1),
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            color: AdminUi.textPrimary,
          ),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            '(${a.ratings})',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, color: AdminUi.textMuted),
          ),
        ),
      ],
    );
  }
}

// ── Narrow: one card per agency ──────────────────────────────────────────────

class _CardList extends StatelessWidget {
  final List<AgencyPerformance> rows;
  const _CardList({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const Divider(height: 1, color: AdminUi.border),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: _AgencyName(rows[i])),
                    const SizedBox(width: 8),
                    // Capped, not Flexible: a loose Flexible split the slack
                    // with the name and left the rating floating mid-row.
                    // The cap gives its count a bounded width to ellipsize in.
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 130),
                      child: _Rating(rows[i]),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _StatGrid(
                  children: [
                    _Stat('Endorsed', '${rows[i].endorsements}'),
                    _Stat(
                      'Received',
                      _withShare(rows[i].received, rows[i].receivedShare),
                    ),
                    _Stat(
                      'Completed',
                      _withShare(rows[i].completed, rows[i].completedShare),
                    ),
                    _Stat('Avg. to receive', _days(rows[i].avgDaysToReceive)),
                    _Stat('Avg. to complete', _days(rows[i].avgDaysToComplete)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Equal-width columns, so the five stats line up as 3 + 2 instead of a
/// ragged wrap that leaves one item alone on a line.
class _StatGrid extends StatelessWidget {
  final List<Widget> children;
  const _StatGrid({required this.children});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      const gap = 12.0;
      final cols = c.maxWidth >= 300 ? 3 : 2;
      final cell = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: 10,
        children: [
          for (final child in children) SizedBox(width: cell, child: child),
        ],
      );
    },
  );
}

/// States how the numbers are counted, so nobody reads a re-endorsed report
/// as having vanished from the agency it was first sent to.
class _HowCounted extends StatelessWidget {
  const _HowCounted();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AdminUi.subtle,
        borderRadius: BorderRadius.circular(AdminUi.controlRadius),
        border: Border.all(color: AdminUi.border),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 15, color: AdminUi.textMuted),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Times are measured from the day the LGU endorsed the report. '
              'A re-endorsed report counts toward the agency it is with now; '
              'citizen ratings stay with the agency they rated.',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: AdminUi.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat(this.label, this.value);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11, color: AdminUi.textMuted),
      ),
      const SizedBox(height: 2),
      Text(
        value,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AdminUi.textPrimary,
        ),
      ),
    ],
  );
}

// ── Recent citizen comments ──────────────────────────────────────────────────

class _Recent extends StatelessWidget {
  final List<AgencyComment> items;
  const _Recent({required this.items});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Latest citizen ratings',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AdminUi.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Given by the citizen who filed each report. Agencies do not see '
            'these, and citizens are not named here.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.4,
              color: AdminUi.textMuted,
            ),
          ),
          const SizedBox(height: 10),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No citizen has rated an agency yet.',
                style: TextStyle(fontSize: 13, color: AdminUi.textSecondary),
              ),
            )
          else
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const Divider(height: 17, color: AdminUi.border),
              _CommentRow(items[i]),
            ],
        ],
      ),
    );
  }
}

class _CommentRow extends StatelessWidget {
  final AgencyComment c;
  const _CommentRow(this.c);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A Wrap, not a Row: an agency name that does not fit pushes the
        // stars and date to the next line instead of off the card. The badge
        // itself is capped at the line width and ellipsizes.
        LayoutBuilder(
          builder: (context, box) => Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: box.maxWidth),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    c.agency,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryBlue,
                    ),
                  ),
                ),
              ),
              Semantics(
                label: '${c.stars} out of 5 stars',
                child: ExcludeSemantics(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var s = 1; s <= 5; s++)
                        Icon(
                          s <= c.stars
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          size: 14,
                          color: s <= c.stars
                              ? const Color(0xFFF59E0B)
                              : AdminUi.borderStrong,
                        ),
                    ],
                  ),
                ),
              ),
              Text(
                [
                  'rated ${agencyStateLabel(c.state)}',
                  if (c.at != null) adminShortDate(c.at!),
                ].join(' · '),
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AdminUi.textMuted,
                ),
              ),
            ],
          ),
        ),
        if ((c.comment ?? '').isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            c.comment!,
            style: const TextStyle(
              fontSize: 13,
              height: 1.45,
              color: AdminUi.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

// ── Chrome ───────────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AdminUi.surface,
      borderRadius: BorderRadius.circular(AdminUi.cardRadius),
      border: Border.all(color: AdminUi.border),
      boxShadow: AdminUi.cardShadow,
    ),
    child: child,
  );
}

class _ErrorCard extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorCard({required this.onRetry});

  @override
  Widget build(BuildContext context) => _Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 18, color: AppColors.red),
          const SizedBox(width: 9),
          const Expanded(
            child: Text(
              "Agency performance couldn't be loaded.",
              style: TextStyle(fontSize: 13, color: AdminUi.textSecondary),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) => _Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          for (var i = 0; i < 5; i++) ...[
            Container(
              height: 14,
              decoration: BoxDecoration(
                color: const Color(0xFFE7EBF1),
                borderRadius: BorderRadius.circular(5),
              ),
            ),
            if (i < 4) const SizedBox(height: 12),
          ],
        ],
      ),
    ),
  );
}
