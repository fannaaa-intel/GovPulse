import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../theme/admin_ui.dart';
import '../providers/admin_dashboard_provider.dart';

class AdminOverviewPage extends ConsumerWidget {
  final int selectedIndex;

  /// Lets the dashboard jump the shell to another section (e.g. Reports = 1).
  /// Wired by the dashboard screen; null elsewhere → tiles simply aren't tappable.
  final void Function(int index)? onNavigate;

  const AdminOverviewPage({
    super.key,
    required this.selectedIndex,
    this.onNavigate,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // No MediaQuery here — this page is embedded inside the sidebar + topbar
    // shell, so all layout decisions are driven by LayoutBuilder against the
    // content area's own constraints.
    final async = ref.watch(adminDashboardProvider);

    return RefreshIndicator(
      onRefresh: () => ref.read(adminDashboardProvider.notifier).refresh(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            // Keep content from stretching edge-to-edge on very wide monitors,
            // which made the page feel sparse.
            constraints: const BoxConstraints(maxWidth: 1400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Welcome back, Admin — here\'s what\'s happening in Aparri today.',
                  style: TextStyle(fontSize: 13, color: AppColors.hint),
                ),
                const SizedBox(height: 20),
                if (async.hasError) ...[
                  _buildErrorBanner(ref),
                  const SizedBox(height: 20),
                ],
                _buildHealthStrip(),
                const SizedBox(height: 20),
                _buildStatsGrid(async),
                const SizedBox(height: 20),
                _buildBottomSection(async),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBanner(WidgetRef ref) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 18, color: AppColors.red),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Couldn\'t load live dashboard data.',
              style: TextStyle(fontSize: 13, color: AppColors.red),
            ),
          ),
          TextButton(
            onPressed: () =>
                ref.read(adminDashboardProvider.notifier).refresh(),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  // ── 1. System health strip ────────────────────────────────────────────────
  // Static placeholder: there is no service-health table / ping endpoint wired
  // yet, so statuses are illustrative.
  Widget _buildHealthStrip() {
    const services = <_ServiceStatus>[
      _ServiceStatus('API', _Health.operational),
      _ServiceStatus('NLP pipeline', _Health.operational),
      _ServiceStatus('Database', _Health.operational),
      _ServiceStatus('Push notifications', _Health.warning),
      _ServiceStatus('Connectivity', _Health.operational),
      _ServiceStatus('Auth service', _Health.operational),
    ];

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel('SYSTEM HEALTH'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: services.map((s) => _buildHealthPill(s)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthPill(_ServiceStatus service) {
    final color = service.health.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(service.health.icon, size: 13, color: color),
          const SizedBox(width: 6),
          Text(
            service.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ── 2. Stat cards grid ─────────────────────────────────────────────────────
  Widget _buildStatsGrid(AsyncValue<AdminDashboardData> async) {
    final data = async.valueOrNull;
    final loading = async.isLoading && data == null;

    final cards = <Widget>[
      // Real: count of citizen reports → tap through to the Reports table.
      _buildStatCard(
        style: const _StatStyle(
          label: 'Total reports',
          icon: Icons.flag_rounded,
          color: AppColors.primaryBlue,
          valueIsAccent: false,
        ),
        loading: loading,
        value: data != null ? '${data.totalReports}' : null,
        sub: data != null ? '+${data.reportsThisWeek} this week' : 'Loading…',
        onTap: onNavigate == null ? null : () => onNavigate!(1),
      ),
      // Placeholder: no NLP/urgency table yet.
      _buildStatCard(
        style: const _StatStyle(
          label: 'AI flagged urgent',
          icon: Icons.error_outline_rounded,
          color: AppColors.red,
          valueIsAccent: true,
        ),
        loading: false,
        value: null,
        sub: 'NLP pipeline pending',
      ),
      // Placeholder: no sentiment table yet.
      _buildStatCard(
        style: const _StatStyle(
          label: 'Avg sentiment',
          icon: Icons.sentiment_satisfied_alt_rounded,
          color: AppColors.green,
          valueIsAccent: true,
        ),
        loading: false,
        value: null,
        sub: 'Sentiment service pending',
      ),
      // Real: count of pending verification submissions.
      _buildStatCard(
        style: const _StatStyle(
          label: 'Pending verification',
          icon: Icons.how_to_reg_rounded,
          color: AppColors.orange,
          valueIsAccent: true,
        ),
        loading: loading,
        value: data != null ? '${data.pendingVerification}' : null,
        sub: 'Awaiting ID review',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 700
            ? 4
            : constraints.maxWidth > 400
            ? 2
            : 1;
        // Derive the aspect ratio from the real column width so every card
        // targets a fixed height instead of growing taller as the screen
        // widens (which made the cards huge on desktop).
        const spacing = 14.0;
        final cardWidth =
            (constraints.maxWidth - spacing * (crossAxisCount - 1)) /
            crossAxisCount;
        final targetHeight = crossAxisCount == 1 ? 104.0 : 150.0;
        final aspect = (cardWidth / targetHeight).clamp(0.8, 6.0);
        return GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: spacing,
          mainAxisSpacing: spacing,
          childAspectRatio: aspect,
          children: cards,
        );
      },
    );
  }

  Widget _buildStatCard({
    required _StatStyle style,
    required bool loading,
    required String? value,
    required String sub,
    VoidCallback? onTap,
  }) {
    // A null value means "not wired / not loaded" → show an em dash in muted
    // colour so it never reads as a real (red/green) figure.
    final hasValue = value != null;
    final valueColor = !hasValue
        ? AppColors.hint
        : style.valueIsAccent
        ? style.color
        : Colors.black87;

    return _Card(
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  style.label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.hint,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: style.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(style.icon, size: 16, color: style.color),
              ),
            ],
          ),
          if (loading)
            const _Skeleton(width: 56, height: 26)
          else
            Text(
              hasValue ? value : '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: valueColor,
              ),
            ),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: AppColors.hint),
          ),
        ],
      ),
    );
  }

  // ── 3. Two-column bottom section ───────────────────────────────────────────
  Widget _buildBottomSection(AsyncValue<AdminDashboardData> async) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 700) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 55, child: _buildActivityFeed(async)),
              const SizedBox(width: 20),
              Expanded(flex: 45, child: _buildAIInsights(async)),
            ],
          );
        }
        return Column(
          children: [
            _buildActivityFeed(async),
            const SizedBox(height: 20),
            _buildAIInsights(async),
          ],
        );
      },
    );
  }

  Widget _buildActivityFeed(AsyncValue<AdminDashboardData> async) {
    final data = async.valueOrNull;
    final loading = async.isLoading && data == null;

    Widget body;
    if (loading) {
      body = Column(
        children: List.generate(4, (_) => const _ActivitySkeletonRow()),
      );
    } else if (data == null) {
      body = const _EmptyHint('Activity unavailable.');
    } else if (data.recentActivity.isEmpty) {
      body = const _EmptyHint('No recent activity yet.');
    } else {
      final items = data.recentActivity;
      body = Column(
        children: [
          for (int i = 0; i < items.length; i++)
            _buildActivityRow(items[i], isLast: i == items.length - 1),
        ],
      );
    }

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recent activity',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          body,
        ],
      ),
    );
  }

  Widget _buildActivityRow(ActivityItem a, {required bool isLast}) {
    final color = _activityColor(a.kind);
    final isReport =
        a.kind == ActivityKind.reportNew ||
        a.kind == ActivityKind.reportReviewing ||
        a.kind == ActivityKind.reportResolved ||
        a.kind == ActivityKind.reportRejected;
    // Report rows jump to the Reports table; verification rows have no detail
    // view to open, so they stay non-interactive.
    final onTap = (isReport && onNavigate != null)
        ? () => onNavigate!(1)
        : null;
    // Transparent Material so the InkWell hover/splash (web) paints above the
    // surrounding card rather than behind it.
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: EdgeInsets.only(
            top: 4,
            bottom: isLast ? 4 : 14,
            left: 4,
            right: 4,
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(_activityIcon(a.kind), size: 16, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      a.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.hint,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _relativeTime(a.timestamp),
                style: const TextStyle(fontSize: 11, color: AppColors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── AI insights panel ──────────────────────────────────────────────────────
  Widget _buildAIInsights(AsyncValue<AdminDashboardData> async) {
    // Sentiment trend + predictive alert are illustrative — no sentiment data
    // source is wired yet. Top categories below ARE real.
    const sentiment = <_SentimentDay>[
      _SentimentDay('Mon', 0.55, AppColors.green),
      _SentimentDay('Tue', 0.70, AppColors.green),
      _SentimentDay('Wed', 0.60, AppColors.green),
      _SentimentDay('Thu', 0.40, AppColors.orange),
      _SentimentDay('Fri', 0.45, AppColors.orange),
      _SentimentDay('Sat', 0.75, AppColors.green),
      _SentimentDay('Today', 0.80, AppColors.green),
    ];

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'AI insights',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          const _SectionLabel('TOP REPORTED CATEGORIES'),
          const SizedBox(height: 12),
          _buildCategories(async),
          const SizedBox(height: 12),
          const _SectionLabel('7-DAY SENTIMENT TREND  ·  SAMPLE'),
          const SizedBox(height: 12),
          _buildSparkline(sentiment),
          const SizedBox(height: 16),
          _buildPredictiveAlert(),
        ],
      ),
    );
  }

  Widget _buildCategories(AsyncValue<AdminDashboardData> async) {
    final data = async.valueOrNull;
    if (async.isLoading && data == null) {
      return Column(
        children: List.generate(3, (_) => const _CategorySkeletonRow()),
      );
    }
    if (data == null) {
      return const _EmptyHint('Categories unavailable.');
    }
    if (data.topCategories.isEmpty) {
      return const _EmptyHint('No reports yet.');
    }
    const palette = <Color>[
      AppColors.red,
      AppColors.orange,
      AppColors.primaryBlue,
    ];
    final cats = data.topCategories;
    return Column(
      children: [
        for (int i = 0; i < cats.length; i++)
          _buildCategoryBar(cats[i], palette[i % palette.length]),
      ],
    );
  }

  Widget _buildCategoryBar(CategoryStat c, Color color) {
    final pct = '${(c.share * 100).round()}%';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              c.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.black87),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Container(
                height: 8,
                color: AppColors.stroke,
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: c.share.clamp(0.0, 1.0),
                  child: Container(color: color),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 36,
            child: Text(
              pct,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.hint,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSparkline(List<_SentimentDay> days) {
    const chartHeight = 70.0;
    return SizedBox(
      height: chartHeight + 18,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final d in days)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      height: (chartHeight * d.value).clamp(4.0, chartHeight),
                      decoration: BoxDecoration(
                        color: d.color.withValues(alpha: 0.85),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      d.label,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.hint,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPredictiveAlert() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.orange.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.trending_up_rounded,
            size: 16,
            color: AppColors.orange,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Predictive alert · sample',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.orange,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Road issues up 40% vs last week — spike likely incoming.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black87.withValues(alpha: 0.7),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Activity kind → visuals ─────────────────────────────────────────────────
  IconData _activityIcon(ActivityKind kind) {
    switch (kind) {
      case ActivityKind.reportNew:
        return Icons.flag_rounded;
      case ActivityKind.reportReviewing:
        return Icons.hourglass_top_rounded;
      case ActivityKind.reportResolved:
        return Icons.check_circle_rounded;
      case ActivityKind.reportRejected:
        return Icons.do_not_disturb_on_rounded;
      case ActivityKind.verifPending:
        return Icons.how_to_reg_rounded;
      case ActivityKind.verifApproved:
        return Icons.verified_user_rounded;
      case ActivityKind.verifRejected:
        return Icons.cancel_rounded;
    }
  }

  Color _activityColor(ActivityKind kind) {
    switch (kind) {
      case ActivityKind.reportNew:
        return AppColors.primaryBlue;
      case ActivityKind.reportReviewing:
        return AppColors.orange;
      case ActivityKind.reportResolved:
        return AppColors.green;
      case ActivityKind.reportRejected:
        return AppColors.red;
      case ActivityKind.verifPending:
        return AppColors.orange;
      case ActivityKind.verifApproved:
        return AppColors.green;
      case ActivityKind.verifRejected:
        return AppColors.red;
    }
  }

  String _relativeTime(DateTime? t) {
    if (t == null) return '';
    final diff = DateTime.now().difference(t);
    if (diff.isNegative) return 'now';
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }
}

// ── Shared presentational helpers ─────────────────────────────────────────────

/// A white rounded card matching the sidebar / topbar stroke + radius.
/// Optionally tappable (Material surface + InkWell) so hover works on web.
class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  const _Card({
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(AdminUi.cardRadius));

    if (onTap == null) {
      return Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: radius,
          border: Border.all(color: AdminUi.border),
        ),
        child: child,
      );
    }

    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: AdminUi.border),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: AppColors.hint,
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, color: AppColors.hint),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  final double? width;
  final double height;
  const _Skeleton({this.width, this.height = 12});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.stroke,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}

class _ActivitySkeletonRow extends StatelessWidget {
  const _ActivitySkeletonRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: AppColors.stroke,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                _Skeleton(width: 140, height: 11),
                SizedBox(height: 6),
                _Skeleton(width: 90, height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategorySkeletonRow extends StatelessWidget {
  const _CategorySkeletonRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(width: 96, child: _Skeleton(width: 70, height: 11)),
          SizedBox(width: 8),
          Expanded(child: _Skeleton(height: 8)),
        ],
      ),
    );
  }
}

enum _Health { operational, warning, down }

extension _HealthVisuals on _Health {
  Color get color {
    switch (this) {
      case _Health.operational:
        return AppColors.green;
      case _Health.warning:
        return AppColors.orange;
      case _Health.down:
        return AppColors.red;
    }
  }

  IconData get icon {
    switch (this) {
      case _Health.operational:
        return Icons.check_circle_rounded;
      case _Health.warning:
        return Icons.warning_amber_rounded;
      case _Health.down:
        return Icons.error_rounded;
    }
  }
}

class _ServiceStatus {
  final String label;
  final _Health health;
  const _ServiceStatus(this.label, this.health);
}

class _StatStyle {
  final String label;
  final IconData icon;
  final Color color;
  final bool valueIsAccent;
  const _StatStyle({
    required this.label,
    required this.icon,
    required this.color,
    required this.valueIsAccent,
  });
}

class _SentimentDay {
  final String label;
  final double value; // 0..1
  final Color color;
  const _SentimentDay(this.label, this.value, this.color);
}
