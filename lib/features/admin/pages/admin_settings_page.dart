import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/admin_activity_provider.dart';
import '../providers/admin_settings_provider.dart';
import '../theme/admin_ui.dart';
import '../widgets/admin_skeleton.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Admin → Settings page (nav slot "Settings")
//
//  System/app-level configuration (account actions live in the topbar chip):
//   • Notifications  — mute which topics count toward the bell badge
//   • Data refresh   — how often the dashboard auto-refreshes (device-local)
//   • Activity log   — recent admin actions (from admin_activity_log)
//   • About          — version + support contact
//   • Log out        — mirrors the topbar/sidebar logout
//
//  Responsive: a centred single column that fills phone width, with padding and
//  control layouts that reflow on small screens (web narrow + app).
// ════════════════════════════════════════════════════════════════════════════

const String _kAppVersion = '1.0.0';
const String _kSupportEmail = 'support@govpulse.ph';

/// Notification topic groups shown as mute toggles. `topics` are the raw values
/// stored in `notifications.topic` (see AdminNotifCenter.kAllAdminTopics).
class _TopicGroup {
  final String label;
  final IconData icon;
  final Color color;
  final List<String> topics;
  const _TopicGroup(this.label, this.icon, this.color, this.topics);
}

const List<_TopicGroup> _kTopicGroups = [
  _TopicGroup('Reports', Icons.report_gmailerrorred_rounded,
      Color(0xFFF59E0B), ['report']),
  _TopicGroup('Verifications', Icons.verified_user_outlined,
      Color(0xFF6366F1), ['verification']),
  _TopicGroup('Feedback', Icons.reviews_outlined, Color(0xFF14B8A6),
      ['feedback']),
  _TopicGroup('Suggestions', Icons.lightbulb_outline_rounded,
      Color(0xFF22C55E), ['suggestion']),
  _TopicGroup('Comments', Icons.mode_comment_outlined, Color(0xFF2563EB),
      ['comment']),
  _TopicGroup('Hearts', Icons.favorite_rounded, Color(0xFFEC4899),
      ['post_heart', 'comment_heart']),
];

class AdminSettingsPage extends ConsumerWidget {
  /// Mirrors the topbar logout flow — the dashboard shell passes its own.
  final VoidCallback onLogout;
  const AdminSettingsPage({super.key, required this.onLogout});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      color: AdminUi.pageBg,
      child: LayoutBuilder(
        builder: (context, c) {
          final narrow = c.maxWidth < 600;
          final pad = narrow ? 14.0 : 24.0;
          return ListView(
            padding: EdgeInsets.fromLTRB(pad, pad, pad, pad + 40),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _SectionTitle('Notifications'),
                      const _NotificationsCard(),
                      const SizedBox(height: 22),
                      const _SectionTitle('Data refresh'),
                      const _RefreshCard(),
                      const SizedBox(height: 22),
                      const _SectionTitle('Activity log'),
                      const _ActivityCard(),
                      const SizedBox(height: 22),
                      const _SectionTitle('About'),
                      const _AboutCard(),
                      const SizedBox(height: 24),
                      _LogoutButton(onLogout: onLogout),
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

// ── Shared chrome ────────────────────────────────────────────────────────────
class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
        color: AdminUi.textSecondary,
      ),
    ),
  );
}

class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const _Card({
    required this.child,
    this.padding = const EdgeInsets.all(6),
  });
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AdminUi.surface,
      borderRadius: BorderRadius.circular(AdminUi.cardRadius),
      border: Border.all(color: AdminUi.border),
      boxShadow: AdminUi.cardShadow,
    ),
    padding: padding,
    child: child,
  );
}

// ── Notifications ────────────────────────────────────────────────────────────
class _NotificationsCard extends ConsumerWidget {
  const _NotificationsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = ref.watch(
      adminSettingsProvider.select((s) => s.mutedTopics),
    );
    final notifier = ref.read(adminSettingsProvider.notifier);

    return _Card(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Choose which topics alert you. Muted topics stop counting '
                'toward the bell badge — you can still open their tab to browse.',
                style: TextStyle(fontSize: 12.5, color: AdminUi.textMuted),
              ),
            ),
          ),
          for (int i = 0; i < _kTopicGroups.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, color: AdminUi.subtle, indent: 52),
            _TopicRow(
              group: _kTopicGroups[i],
              enabled: _kTopicGroups[i].topics.every((t) => !muted.contains(t)),
              onChanged: (on) {
                for (final t in _kTopicGroups[i].topics) {
                  notifier.setTopicMuted(t, !on);
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _TopicRow extends StatelessWidget {
  final _TopicGroup group;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  const _TopicRow({
    required this.group,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: group.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(group.icon, size: 18, color: group.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              group.label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AdminUi.textPrimary,
              ),
            ),
          ),
          Switch(
            value: enabled,
            onChanged: onChanged,
            activeColor: AppColors.primaryBlue,
          ),
        ],
      ),
    );
  }
}

// ── Data refresh interval ────────────────────────────────────────────────────
class _RefreshCard extends ConsumerWidget {
  const _RefreshCard();

  static String _shortLabel(int s) => switch (s) {
    0 => 'Off',
    15 => '15s',
    30 => '30s',
    60 => '1 min',
    300 => '5 min',
    _ => '${s}s',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(
      adminSettingsProvider.select((s) => s.pollSeconds),
    );
    final notifier = ref.read(adminSettingsProvider.notifier);

    return _Card(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'The dashboard silently refetches the visible tab this often. '
            '“Off” disables auto-refresh — ${pollIntervalLabel(current).toLowerCase()}.',
            style: const TextStyle(fontSize: 12.5, color: AdminUi.textMuted),
          ),
          const SizedBox(height: 12),
          // Wraps to multiple rows on narrow web / phone.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in kPollIntervalChoices)
                _ChoiceChip(
                  label: _shortLabel(s),
                  selected: s == current,
                  onTap: () => notifier.setPollSeconds(s),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primaryBlue
              : AdminUi.subtle,
          borderRadius: BorderRadius.circular(AdminUi.controlRadius),
          border: Border.all(
            color: selected ? AppColors.primaryBlue : AdminUi.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AdminUi.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ── Activity log ─────────────────────────────────────────────────────────────
IconData _activityIcon(String action) => switch (action) {
  'staff_created' => Icons.person_add_alt_1_rounded,
  'user_suspended' => Icons.pause_circle_outline_rounded,
  'suspension_lifted' => Icons.play_circle_outline_rounded,
  'user_restricted' => Icons.block_rounded,
  'restriction_lifted' => Icons.lock_open_rounded,
  'user_deactivated' => Icons.person_off_rounded,
  'user_reactivated' => Icons.person_outline_rounded,
  'broadcast_sent' => Icons.campaign_rounded,
  _ => Icons.history_rounded,
};

Color _activityColor(String action) => switch (action) {
  'user_suspended' || 'user_restricted' || 'user_deactivated' =>
    AppColors.red,
  'suspension_lifted' || 'restriction_lifted' || 'user_reactivated' =>
    AppColors.green,
  'staff_created' || 'broadcast_sent' => AppColors.primaryBlue,
  _ => AdminUi.textMuted,
};

class _ActivityCard extends ConsumerWidget {
  const _ActivityCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminActivityProvider);

    return _Card(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Recent admin actions',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AdminUi.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () =>
                      ref.read(adminActivityProvider.notifier).refresh(),
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  color: AdminUi.textMuted,
                  tooltip: 'Refresh',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AdminUi.subtle),
          async.when(
            loading: () => const _ActivitySkeleton(),
            error: (_, _) => const _ActivityEmpty(
              message:
                  'Activity log unavailable. Run admin_activity_log.sql to '
                  'enable it.',
            ),
            data: (items) {
              if (items.isEmpty) {
                return const _ActivityEmpty(
                  message: 'No admin actions recorded yet.',
                );
              }
              // Cap the inline list; the page itself is the scroll surface.
              final shown = items.take(15).toList();
              return Column(
                children: [
                  for (int i = 0; i < shown.length; i++) ...[
                    if (i > 0)
                      const Divider(
                        height: 1,
                        color: AdminUi.subtle,
                        indent: 52,
                      ),
                    _ActivityRow(shown[i]),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final AdminActivity a;
  const _ActivityRow(this.a);

  @override
  Widget build(BuildContext context) {
    final color = _activityColor(a.action);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(_activityIcon(a.action), size: 16, color: color),
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
                    fontWeight: FontWeight.w600,
                    color: AdminUi.textPrimary,
                  ),
                ),
                if ((a.detail ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    a.detail!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AdminUi.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 3),
                Text(
                  [
                    if ((a.actorName ?? '').isNotEmpty) a.actorName!,
                    a.timeAgo,
                  ].join(' · '),
                  style: const TextStyle(fontSize: 11, color: AdminUi.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityEmpty extends StatelessWidget {
  final String message;
  const _ActivityEmpty({required this.message});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
    child: Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12.5, color: AdminUi.textMuted),
      ),
    ),
  );
}

class _ActivitySkeleton extends StatelessWidget {
  const _ActivitySkeleton();
  @override
  Widget build(BuildContext context) => const AdminShimmer(
    child: Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          _ActivitySkeletonRow(),
          _ActivitySkeletonRow(),
          _ActivitySkeletonRow(),
        ],
      ),
    ),
  );
}

class _ActivitySkeletonRow extends StatelessWidget {
  const _ActivitySkeletonRow();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SkeletonBox(width: 30, height: 30, radius: 9),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 180, height: 12),
              SizedBox(height: 7),
              SkeletonBox(width: 90, height: 10),
            ],
          ),
        ),
      ],
    ),
  );
}

// ── About ────────────────────────────────────────────────────────────────────
class _AboutCard extends StatelessWidget {
  const _AboutCard();

  Future<void> _contactSupport() async {
    final uri = Uri(
      scheme: 'mailto',
      path: _kSupportEmail,
      query: 'subject=GovPulse Admin support',
    );
    await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      padding: const EdgeInsets.all(6),
      child: Column(
        children: [
          const _AboutRow(
            icon: Icons.info_outline_rounded,
            label: 'Version',
            trailing: Text(
              'GovPulse Admin $_kAppVersion',
              style: TextStyle(fontSize: 13, color: AdminUi.textMuted),
            ),
          ),
          const Divider(height: 1, color: AdminUi.subtle, indent: 52),
          _AboutRow(
            icon: Icons.mail_outline_rounded,
            label: 'Contact support',
            onTap: _contactSupport,
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: AdminUi.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget trailing;
  final VoidCallback? onTap;
  const _AboutRow({
    required this.icon,
    required this.label,
    required this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AdminUi.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AdminUi.textPrimary,
                  ),
                ),
              ),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}

// ── Logout ───────────────────────────────────────────────────────────────────
class _LogoutButton extends StatelessWidget {
  final VoidCallback onLogout;
  const _LogoutButton({required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: OutlinedButton.icon(
        onPressed: onLogout,
        icon: const Icon(Icons.logout_rounded, size: 20),
        label: const Text('Log out'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.red,
          side: BorderSide(color: AppColors.red.withValues(alpha: 0.5)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}
