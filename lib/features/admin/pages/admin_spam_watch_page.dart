import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/admin_spam_watch_provider.dart';
import '../providers/admin_users_provider.dart';
import '../theme/admin_ui.dart';

/// Opens the "Spam watch" report — the noisiest citizens across every channel.
void showSpamWatchReview(BuildContext context) {
  showDialog(
    context: context,
    barrierColor: Colors.black54,
    builder: (_) => Dialog(
      backgroundColor: AdminUi.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 660, maxHeight: 740),
        child: const _SpamWatchView(),
      ),
    ),
  );
}

class _SpamWatchView extends ConsumerWidget {
  const _SpamWatchView();

  static const _windows = [
    (24, '24h'),
    (72, '3 days'),
    (168, '7 days'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminSpamWatchProvider);
    final notifier = ref.read(adminSpamWatchProvider.notifier);
    final window = notifier.windowHours;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 8, 12),
          child: Row(
            children: [
              const Icon(Icons.report_gmailerrorred_rounded,
                  size: 19, color: AppColors.orange),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Spam watch',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AdminUi.textPrimary,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: AdminUi.textMuted),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        // Window selector
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
          child: Row(
            children: [
              const Text('Window:',
                  style: TextStyle(fontSize: 12.5, color: AdminUi.textMuted)),
              const SizedBox(width: 10),
              for (final w in _windows) ...[
                _WindowChip(
                  label: w.$2,
                  selected: window == w.$1,
                  onTap: () => notifier.setWindow(w.$1),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const Divider(height: 1, color: AdminUi.border),
        Flexible(
          child: async.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(28),
              child: Text('Could not load: $e',
                  style: const TextStyle(color: AppColors.red)),
            ),
            data: (items) {
              if (items.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.verified_user_rounded,
                            size: 40, color: AppColors.green),
                        SizedBox(height: 10),
                        Text('No unusual activity in this window',
                            style: TextStyle(
                                fontSize: 14, color: AdminUi.textSecondary)),
                      ],
                    ),
                  ),
                );
              }
              return ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _SpamUserCard(user: items[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _WindowChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _WindowChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primaryBlue : AdminUi.subtle,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : AdminUi.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _SpamUserCard extends ConsumerWidget {
  final SpamWatchUser user;
  const _SpamUserCard({required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: AdminUi.subtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminUi.border),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  user.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AdminUi.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Score ${user.score.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFB45309),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _stat('${user.totalItems}', 'submissions'),
              _stat('${user.duplicateItems}', 'duplicates',
                  danger: user.duplicateItems > 0),
              _stat('${user.flaggedItems}', 'flagged',
                  danger: user.flaggedItems > 0),
              _stat('${user.channels}', 'channels'),
            ],
          ),
          if (user.lastActive != null) ...[
            const SizedBox(height: 8),
            Text(
              'Last active ${DateFormat('MMM d · h:mm a').format(user.lastActive!)}',
              style: const TextStyle(fontSize: 11, color: AdminUi.textMuted),
            ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: () {
                // Seed the Citizen Management search with this person, then
                // close — the admin restricts "News feed" / suspends from the
                // matching row.
                ref.read(manageUserQueryProvider.notifier).state =
                    user.displayName;
                Navigator.pop(context);
              },
              icon: const Icon(Icons.manage_accounts_rounded, size: 16),
              label: const Text('Manage user'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryBlue,
                side: BorderSide(
                    color: AppColors.primaryBlue.withValues(alpha: 0.5)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String value, String label, {bool danger = false}) {
    final color = danger ? const Color(0xFFB45309) : AdminUi.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: danger
            ? AppColors.orange.withValues(alpha: 0.10)
            : AdminUi.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AdminUi.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(fontSize: 11.5, color: AdminUi.textMuted)),
        ],
      ),
    );
  }
}
