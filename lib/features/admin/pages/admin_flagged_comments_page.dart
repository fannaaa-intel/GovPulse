import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/admin_flagged_comments_provider.dart';
import '../theme/admin_ui.dart';
import '../widgets/admin_snackbar.dart';
import '../../../core/widgets/app_dialog.dart';

/// Opens the flagged / held community-comments review queue.
void showFlaggedCommentsReview(BuildContext context) {
  showAppDialog(
    context: context,
    barrierColor: Colors.black54,
    builder: (_) => Dialog(
      backgroundColor: AdminUi.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
        child: const _FlaggedCommentsView(),
      ),
    ),
  );
}

class _FlaggedCommentsView extends ConsumerWidget {
  const _FlaggedCommentsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminFlaggedCommentsProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 8, 12),
          child: Row(
            children: [
              const Icon(Icons.flag_rounded, size: 18, color: AppColors.orange),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Flagged comments',
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
                        Icon(Icons.check_circle_rounded,
                            size: 40, color: AppColors.green),
                        SizedBox(height: 10),
                        Text('Nothing to review',
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
                itemBuilder: (_, i) => _FlaggedCommentCard(item: items[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FlaggedCommentCard extends ConsumerStatefulWidget {
  final FlaggedComment item;
  const _FlaggedCommentCard({required this.item});

  @override
  ConsumerState<_FlaggedCommentCard> createState() =>
      _FlaggedCommentCardState();
}

class _FlaggedCommentCardState extends ConsumerState<_FlaggedCommentCard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      showAdminSnackBar(context, done, type: AdminSnackType.success);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAdminSnackBar(context, 'Failed: $e', type: AdminSnackType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.item;
    final notifier = ref.read(adminFlaggedCommentsProvider.notifier);
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
                  '${c.authorName ?? 'Citizen'} · on "${c.postTitle ?? 'post'}"',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AdminUi.textSecondary,
                  ),
                ),
              ),
              if (c.isPending)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('Held',
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFB45309))),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // Admins see the REAL (unmasked) text to judge it.
          Text(
            c.body,
            style: const TextStyle(
                fontSize: 14, color: AdminUi.textPrimary, height: 1.4),
          ),
          if ((c.flagReason ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(c.flagReason!,
                style: const TextStyle(
                    fontSize: 11.5,
                    fontStyle: FontStyle.italic,
                    color: Color(0xFFB45309))),
          ],
          if (c.createdAt != null) ...[
            const SizedBox(height: 4),
            Text(DateFormat('MMM d, yyyy · h:mm a').format(c.createdAt!),
                style: const TextStyle(fontSize: 11, color: AdminUi.textMuted)),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(() => notifier.deleteComment(c.id),
                          'Comment deleted.'),
                  icon: const Icon(Icons.delete_outline_rounded, size: 16),
                  label: const Text('Delete'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.red,
                    side: const BorderSide(color: AppColors.red),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _busy || !c.isPending
                      ? null
                      : () =>
                          _run(() => notifier.approve(c.id), 'Comment approved.'),
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: Text(c.isPending ? 'Approve' : 'Approved'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
