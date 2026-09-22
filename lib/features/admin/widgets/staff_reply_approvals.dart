// ════════════════════════════════════════════════════════════════════════════
//  Admin — staff reply approval queue
//
//  Staff answer the suggestions routed to their office, but nothing reaches the
//  citizen until it is approved here. This panel is the gate.
//
//  It is ordered by how long the CITIZEN has been waiting, not by when the
//  draft was written: an office that answers late should not be rewarded with a
//  fresh place at the front of the queue.
//
//  Rejecting REQUIRES a reason. A draft returned with no explanation gives the
//  author nothing to act on and comes straight back — the reason is what makes
//  the loop terminate.
// ════════════════════════════════════════════════════════════════════════════

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_dialog.dart';
import '../providers/admin_staff_replies_provider.dart';
import '../theme/admin_ui.dart';

/// Below this the action buttons stack instead of sharing a row.
const double _kActionsRowFrom = 420;

class StaffReplyApprovalsPanel extends ConsumerWidget {
  const StaffReplyApprovalsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminStaffRepliesProvider);
    final items = async.valueOrNull ?? const <PendingStaffReply>[];

    // The panel disappears when there is nothing to approve rather than showing
    // an empty box on every visit — this is a queue, not a permanent section.
    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AdminUi.surface,
        borderRadius: BorderRadius.circular(AdminUi.cardRadius),
        border: Border.all(color: const Color(0xFFF39C12).withValues(alpha: 0.5)),
        boxShadow: AdminUi.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            color: const Color(0xFFF39C12).withValues(alpha: 0.09),
            child: Row(
              children: [
                const Icon(Icons.rate_review_rounded,
                    size: 17, color: Color(0xFFB8770A)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    items.length == 1
                        ? '1 staff reply waiting for approval'
                        : '${items.length} staff replies waiting for approval',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF8A5A05),
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, thickness: 1, color: AdminUi.border),
            _ReplyRow(item: items[i]),
          ],
        ],
      ),
    );
  }
}

class _ReplyRow extends ConsumerStatefulWidget {
  final PendingStaffReply item;
  const _ReplyRow({required this.item});

  @override
  ConsumerState<_ReplyRow> createState() => _ReplyRowState();
}

class _ReplyRowState extends ConsumerState<_ReplyRow> {
  /// Guards the write, not just the button's look. A flag that only reaches the
  /// widget tree still permits a second tap in the same frame, which here would
  /// mean approving twice.
  bool _busy = false;

  Future<void> _approve() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(adminStaffRepliesProvider.notifier)
          .approve(widget.item.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reply published. The citizen has been notified.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The reply could not be published. Please try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    if (_busy) return;
    final reason = await _askReason(context);
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(adminStaffRepliesProvider.notifier)
          .reject(widget.item.id, reason);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sent back to the office with your note.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The reply could not be returned. Please try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Avatar(url: it.authorPhotoUrl, name: it.authorName),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      it.authorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: AdminUi.textPrimary,
                      ),
                    ),
                    Text(
                      '${it.department} · ${it.categoryLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AdminUi.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _WaitBadge(waiting: it.citizenWaiting),
            ],
          ),
          const SizedBox(height: 11),
          // The citizen's words first: a reply cannot be judged without the
          // thing it answers.
          _Quote(
            label: 'The citizen wrote',
            body: it.suggestionDetails,
            color: AdminUi.textMuted,
          ),
          const SizedBox(height: 9),
          _Quote(
            label: 'The office replied',
            body: it.body,
            color: AppColors.primaryBlue,
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, c) {
              final approve = FilledButton.icon(
                onPressed: _busy ? null : _approve,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AdminUi.controlRadius),
                  ),
                ),
                icon: _busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check_rounded, size: 16),
                label: const Text('Approve & publish'),
              );
              final reject = OutlinedButton.icon(
                onPressed: _busy ? null : _reject,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFDC2626),
                  side: const BorderSide(color: Color(0xFFE5A3A3)),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AdminUi.controlRadius),
                  ),
                ),
                icon: const Icon(Icons.undo_rounded, size: 16),
                label: const Text('Send back'),
              );
              if (c.maxWidth < _kActionsRowFrom) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: 40, child: approve),
                    const SizedBox(height: 8),
                    SizedBox(height: 40, child: reject),
                  ],
                );
              }
              return Row(
                children: [
                  SizedBox(height: 40, child: approve),
                  const SizedBox(width: 9),
                  SizedBox(height: 40, child: reject),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Quote extends StatelessWidget {
  final String label;
  final String body;
  final Color color;
  const _Quote({
    required this.label,
    required this.body,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AdminUi.subtle,
        borderRadius: BorderRadius.circular(AdminUi.controlRadius),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
              color: color,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            body,
            // A long suggestion must not push the approve button below the
            // fold — a control the admin cannot see is one they cannot press.
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: AdminUi.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _WaitBadge extends StatelessWidget {
  final Duration waiting;
  const _WaitBadge({required this.waiting});

  @override
  Widget build(BuildContext context) {
    final days = waiting.inDays;
    final late = days >= 3;
    final label = days >= 1
        ? '${days}d waiting'
        : '${waiting.inHours}h waiting';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (late ? const Color(0xFFDC2626) : AdminUi.textMuted)
            .withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: late ? const Color(0xFFDC2626) : AdminUi.textSecondary,
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? url;
  final String name;
  const _Avatar({required this.url, required this.name});

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final fallback = Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Color(0xFFEAF1FB),
        shape: BoxShape.circle,
      ),
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: AppColors.primaryBlue,
        ),
      ),
    );
    if (url == null || url!.isEmpty) return fallback;
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url!,
        width: 34,
        height: 34,
        fit: BoxFit.cover,
        placeholder: (_, _) => fallback,
        errorWidget: (_, _, _) => fallback,
      ),
    );
  }
}

/// Asks for the reason. Returns null when cancelled, and never returns an empty
/// string — the send-back is refused until a reason is typed, and the refusal
/// names the field rather than silently doing nothing.
Future<String?> _askReason(BuildContext context) {
  final ctrl = TextEditingController();
  // `error` lives OUTSIDE the builder. Declared inside, every rebuild would
  // reset it to null and the message would never render — the button would
  // look dead, which is the exact failure this message exists to prevent.
  String? error;
  return showAppDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        return AlertDialog(
          backgroundColor: AdminUi.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AdminUi.cardRadius),
          ),
          title: const Text(
            'Send back for changes',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tell the office what to change. They see this note.',
                  style: TextStyle(fontSize: 13, color: AdminUi.textMuted),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  maxLines: 4,
                  autofocus: true,
                  style: const TextStyle(fontSize: 13.5),
                  onChanged: (_) {
                    if (error != null) setLocal(() => error = null);
                  },
                  decoration: InputDecoration(
                    hintText: 'e.g. Please answer the drainage question too.',
                    hintStyle: const TextStyle(
                        fontSize: 13, color: AdminUi.textMuted),
                    errorText: error,
                    filled: true,
                    fillColor: AdminUi.subtle,
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AdminUi.controlRadius),
                      borderSide: const BorderSide(color: AdminUi.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AdminUi.controlRadius),
                      borderSide: const BorderSide(color: AdminUi.border),
                    ),
                  ),
                ),
              ],
            ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
              ),
              onPressed: () {
                final v = ctrl.text.trim();
                // Name the field. A bare return here reads as a dead button.
                if (v.isEmpty) {
                  setLocal(() => error = 'Please say what needs changing.');
                  return;
                }
                Navigator.of(ctx).pop(v);
              },
              child: const Text('Send back'),
            ),
          ],
        );
      },
    ),
  );
}
