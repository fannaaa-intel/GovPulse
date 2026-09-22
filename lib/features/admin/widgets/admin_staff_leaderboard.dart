// ════════════════════════════════════════════════════════════════════════════
//  Admin — staff performance leaderboard
//
//  A ranked comparison across LGU staff, filterable by office, metric and
//  department. Admin-only by design: staff see their own scorecard on their own
//  dashboard, never a scoreboard of their colleagues.
//
//  The metrics are actions each person took. Citizen OFFICE ratings are not
//  ranked against anyone — `feedbacks` has no staff id and rates a counter
//  visit, not a person. See staff_performance_view for the full reasoning.
// ════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../staff/data/staff_departments.dart';
import '../../staff/widgets/staff_performance_panels.dart';
import '../providers/admin_staff_replies_provider.dart';
import '../theme/admin_ui.dart';

class AdminStaffLeaderboard extends ConsumerStatefulWidget {
  const AdminStaffLeaderboard({super.key});

  @override
  ConsumerState<AdminStaffLeaderboard> createState() =>
      _AdminStaffLeaderboardState();
}

class _AdminStaffLeaderboardState extends ConsumerState<AdminStaffLeaderboard> {
  LeaderboardMetric _metric = LeaderboardMetric.reportsResolved;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(adminScorecardsProvider);
    final dept = ref.watch(adminScorecardDeptProvider);
    final cards = ref.watch(adminFilteredScorecardsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DeptFilter(
          active: dept,
          onPick: (d) =>
              ref.read(adminScorecardDeptProvider.notifier).state = d,
        ),
        const SizedBox(height: 12),
        async.when(
          loading: () => const _LeaderboardSkeleton(),
          error: (e, _) => Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AdminUi.surface,
              borderRadius: BorderRadius.circular(AdminUi.cardRadius),
              border: Border.all(color: AdminUi.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.cloud_off_rounded,
                    size: 18, color: AppColors.red),
                const SizedBox(width: 9),
                const Expanded(
                  child: Text(
                    "Performance data couldn't be loaded.",
                    style: TextStyle(fontSize: 13, color: AdminUi.textSecondary),
                  ),
                ),
                TextButton(
                  onPressed: () => ref.invalidate(adminScorecardsProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
          data: (_) => StaffLeaderboardPanel(
            cards: cards,
            metric: _metric,
            onMetric: (m) => setState(() => _metric = m),
            title: dept ?? 'All offices',
          ),
        ),
        const SizedBox(height: 10),
        const _RatingsNote(),
      ],
    );
  }
}

/// Office filter. Only the four INTERNAL offices appear: external agencies hold
/// no inbox and are excluded from the performance view itself.
class _DeptFilter extends StatelessWidget {
  final String? active;
  final ValueChanged<String?> onPick;
  const _DeptFilter({required this.active, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final options = <(String?, String)>[
      (null, 'All offices'),
      for (final d in StaffDepartments.internal) (d.name, d.name),
    ];
    // Horizontal scroll rather than a Wrap: five office names wrap into three
    // ragged lines on a phone, and the chips lose their row alignment.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (value, label) in options)
            Padding(
              padding: const EdgeInsets.only(right: 7),
              child: Material(
                color: value == active ? AppColors.primaryBlue : AdminUi.surface,
                borderRadius: BorderRadius.circular(AdminUi.controlRadius),
                child: InkWell(
                  onTap: () => onPick(value),
                  borderRadius: BorderRadius.circular(AdminUi.controlRadius),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 11, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius:
                          BorderRadius.circular(AdminUi.controlRadius),
                      border: Border.all(
                        color: value == active
                            ? AppColors.primaryBlue
                            : AdminUi.border,
                      ),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: value == active
                            ? Colors.white
                            : AdminUi.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// States plainly why citizen star ratings are not in the ranking, so nobody
/// adds them later assuming it was an oversight.
class _RatingsNote extends StatelessWidget {
  const _RatingsNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AdminUi.subtle,
        borderRadius: BorderRadius.circular(AdminUi.controlRadius),
        border: Border.all(color: AdminUi.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 15, color: AdminUi.textMuted),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'The citizen satisfaction score on the Dashboard is NOT part of '
              'this ranking. Those stars rate the office for a counter visit, '
              'not a person, so nobody can be ranked on them.',
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

class _LeaderboardSkeleton extends StatelessWidget {
  const _LeaderboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminUi.surface,
        borderRadius: BorderRadius.circular(AdminUi.cardRadius),
        border: Border.all(color: AdminUi.border),
        boxShadow: AdminUi.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 160,
            height: 16,
            decoration: BoxDecoration(
              color: const Color(0xFFE7EBF1),
              borderRadius: BorderRadius.circular(5),
            ),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < 4; i++) ...[
            Container(
              height: 14,
              decoration: BoxDecoration(
                color: const Color(0xFFE7EBF1),
                borderRadius: BorderRadius.circular(5),
              ),
            ),
            if (i < 3) const SizedBox(height: 11),
          ],
        ],
      ),
    );
  }
}
