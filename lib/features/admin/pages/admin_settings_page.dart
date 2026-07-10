import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/admin_activity_provider.dart';
import '../providers/admin_flagged_comments_provider.dart';
import '../providers/admin_moderation_config_provider.dart';
import '../providers/admin_settings_provider.dart';
import '../providers/admin_spam_watch_provider.dart';
import '../theme/admin_ui.dart';
import '../widgets/admin_skeleton.dart';
import '../widgets/admin_snackbar.dart';
import 'admin_activity_log_page.dart';
import 'admin_flagged_comments_page.dart';
import 'admin_spam_watch_page.dart';

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
                      const _SectionTitle('Content moderation'),
                      const _ModerationCard(),
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

// ── Content moderation ───────────────────────────────────────────────────────
class _ModerationCard extends ConsumerStatefulWidget {
  const _ModerationCard();
  @override
  ConsumerState<_ModerationCard> createState() => _ModerationCardState();
}

class _ModerationCardState extends ConsumerState<_ModerationCard> {
  final _termCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _termCtrl.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      showAdminSnackBar(context, done, type: AdminSnackType.success);
    } catch (e) {
      if (!mounted) return;
      showAdminSnackBar(context, 'Failed: $e', type: AdminSnackType.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addTerm() async {
    final input = _termCtrl.text.trim();
    if (input.isEmpty) return;
    // Snapshot the current list so we can tell a genuinely new word from one
    // that normalized to an already-banned root (e.g. "8080" → "bobo").
    final before =
        ref.read(adminModerationConfigProvider).valueOrNull?.terms ??
            const <String>[];
    setState(() => _busy = true);
    try {
      final root =
          await ref.read(adminModerationConfigProvider.notifier).addTerm(input);
      if (!mounted) return;
      final existed = root.isNotEmpty && before.contains(root);
      // Show the canonical root when it differs from what was typed, so it's
      // clear why "8080" lands as "bobo".
      final savedAs =
          root.isNotEmpty && root != input.toLowerCase() ? ' as “$root”' : '';
      showAdminSnackBar(
        context,
        existed ? '“$root” is already in the list.' : 'Word added$savedAs.',
        type: existed ? AdminSnackType.info : AdminSnackType.success,
      );
      _termCtrl.clear();
    } catch (e) {
      if (!mounted) return;
      showAdminSnackBar(context, 'Failed: $e', type: AdminSnackType.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final flaggedCount =
        ref.watch(adminFlaggedCommentsProvider).valueOrNull?.length ?? 0;
    final spamCount =
        ref.watch(adminSpamWatchProvider).valueOrNull?.length ?? 0;
    final config = ref.watch(adminModerationConfigProvider).valueOrNull;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Text(
              'Review flagged content, watch for spammers, and tune what gets '
              'caught — all applied live.',
              style: TextStyle(fontSize: 12.5, color: AdminUi.textMuted),
            ),
          ),
          // Review queues
          _ModRow(
            icon: Icons.flag_rounded,
            title: 'Flagged comments',
            subtitle: 'Held for profanity or spam — approve or delete',
            count: flaggedCount,
            onTap: () => showFlaggedCommentsReview(context),
          ),
          const Divider(height: 1, color: AdminUi.subtle, indent: 52),
          _ModRow(
            icon: Icons.report_gmailerrorred_rounded,
            title: 'Spam watch',
            subtitle: 'Citizens flooding across posts, reports, chat…',
            count: spamCount,
            onTap: () => showSpamWatchReview(context),
          ),
          const Divider(height: 1, color: AdminUi.border),
          const SizedBox(height: 6),

          if (config == null || !config.available)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Run the moderation SQL (profanity_moderation.sql, '
                'spam_detection.sql, moderation_admin.sql) to edit the banned '
                'words and thresholds here.',
                style: TextStyle(fontSize: 12, color: AdminUi.textMuted),
              ),
            )
          else ...[
            _subLabel('Banned words'),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                'Added words are flagged server-side. Type any form '
                '(e.g. "G4go") — it saves the canonical root.',
                style: TextStyle(fontSize: 11.5, color: AdminUi.textMuted),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in config.terms)
                    _TermChip(
                      term: t,
                      busy: _busy,
                      onRemove: () => _run(
                        () => ref
                            .read(adminModerationConfigProvider.notifier)
                            .removeTerm(t),
                        'Word removed.',
                      ),
                    ),
                  if (config.terms.isEmpty)
                    const Text('No custom words yet.',
                        style: TextStyle(
                            fontSize: 12, color: AdminUi.textMuted)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _termCtrl,
                      enabled: !_busy,
                      onSubmitted: (_) => _addTerm(),
                      textInputAction: TextInputAction.done,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Add a word…',
                        hintStyle: const TextStyle(
                            fontSize: 13, color: AdminUi.textMuted),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 11),
                        filled: true,
                        fillColor: AdminUi.subtle,
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AdminUi.controlRadius),
                          borderSide:
                              const BorderSide(color: AdminUi.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AdminUi.controlRadius),
                          borderSide:
                              const BorderSide(color: AdminUi.border),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _busy ? null : _addTerm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 13),
                    ),
                    child: const Text('Add'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1, color: AdminUi.subtle),
            const SizedBox(height: 6),
            _subLabel('Thresholds'),
            for (final s in config.settings)
              _SettingRow(
                setting: s,
                busy: _busy,
                onChanged: (v) => _run(
                  () => ref
                      .read(adminModerationConfigProvider.notifier)
                      .setSetting(s.key, v),
                  'Saved.',
                ),
              ),
          ],
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _subLabel(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: AdminUi.textMuted,
          ),
        ),
      );
}

class _ModRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final int count;
  final VoidCallback onTap;
  const _ModRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: count > 0
                      ? AppColors.orange.withValues(alpha: 0.12)
                      : AdminUi.subtle,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon,
                    size: 17,
                    color: count > 0 ? AppColors.orange : AdminUi.textMuted),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: AdminUi.textPrimary)),
                    const SizedBox(height: 1),
                    Text(subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11.5, color: AdminUi.textMuted)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (count > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('$count',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFB45309))),
                ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded,
                  size: 18, color: AdminUi.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _TermChip extends StatelessWidget {
  final String term;
  final bool busy;
  final VoidCallback onRemove;
  const _TermChip(
      {required this.term, required this.busy, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(term,
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF991B1B))),
          const SizedBox(width: 4),
          InkWell(
            onTap: busy ? null : onRemove,
            borderRadius: BorderRadius.circular(20),
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(Icons.close_rounded, size: 14, color: AppColors.red),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final ModSetting setting;
  final bool busy;
  final ValueChanged<num> onChanged;
  const _SettingRow(
      {required this.setting, required this.busy, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final v = setting.value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              setting.description ?? setting.key,
              style: const TextStyle(
                  fontSize: 12.5, color: AdminUi.textSecondary, height: 1.3),
            ),
          ),
          const SizedBox(width: 10),
          _Stepper(
            value: v,
            busy: busy,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  final num value;
  final bool busy;
  final ValueChanged<num> onChanged;
  const _Stepper(
      {required this.value, required this.busy, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, VoidCallback? onTap) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            child: Icon(icon, size: 16, color: AdminUi.textSecondary),
          ),
        );
    return Container(
      decoration: BoxDecoration(
        color: AdminUi.subtle,
        borderRadius: BorderRadius.circular(AdminUi.controlRadius),
        border: Border.all(color: AdminUi.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn(Icons.remove_rounded,
              busy || value <= 0 ? null : () => onChanged(value - 1)),
          Container(
            constraints: const BoxConstraints(minWidth: 30),
            alignment: Alignment.center,
            child: Text(
              value % 1 == 0 ? '${value.toInt()}' : '$value',
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AdminUi.textPrimary),
            ),
          ),
          btn(Icons.add_rounded, busy ? null : () => onChanged(value + 1)),
        ],
      ),
    );
  }
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
          // Equal-width chips in justified rows so they never wrap into a
          // left-ragged single trailing chip. All fit on one row when there's
          // room; on phones they lay out 3-per-row, centred so the last row
          // (2 chips) stays symmetric.
          LayoutBuilder(
            builder: (context, c) {
              const gap = 8.0;
              final count = kPollIntervalChoices.length;
              final perRow = c.maxWidth >= 440 ? count : 3;
              final chipW = (c.maxWidth - gap * (perRow - 1)) / perRow;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                alignment: WrapAlignment.center,
                children: [
                  for (final s in kPollIntervalChoices)
                    SizedBox(
                      width: chipW,
                      child: _ChoiceChip(
                        label: _shortLabel(s),
                        selected: s == current,
                        onTap: () => notifier.setPollSeconds(s),
                      ),
                    ),
                ],
              );
            },
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        alignment: Alignment.center,
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
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
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
  'identity_revealed' => Icons.visibility_rounded,
  _ => Icons.history_rounded,
};

Color _activityColor(String action) => switch (action) {
  'user_suspended' || 'user_restricted' || 'user_deactivated' ||
        'identity_revealed' =>
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
              // The full, date-filterable history lives behind "View all".
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
                  const Divider(height: 1, color: AdminUi.subtle),
                  _ViewAllButton(more: items.length > shown.length),
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

/// Full-width footer that opens the complete, date-filterable history.
class _ViewAllButton extends StatelessWidget {
  /// True when there are more actions than the inline list shows — surfaces a
  /// gentle hint that "View all" reveals additional history.
  final bool more;
  const _ViewAllButton({required this.more});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => showAdminActivityLog(context),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                more ? 'View all activity' : 'View all & filter by date',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryBlue,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.arrow_forward_rounded,
                size: 16,
                color: AppColors.primaryBlue,
              ),
            ],
          ),
        ),
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
