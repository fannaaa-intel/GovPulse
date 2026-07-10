import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../theme/admin_ui.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Spam / troll moderation UI — shared across reports, feedback, suggestions.
//
//  Dismissing is a SOFT action: it hides the row from the admin lists and
//  excludes it from all analytics + the AI forecast, but keeps it for audit and
//  lets an admin restore it. Anonymous submissions can't be moderated at the
//  user level, so this operates purely on the content.
// ════════════════════════════════════════════════════════════════════════════

/// Preset dismissal reasons offered in [showAdminDismissDialog].
const List<String> kDismissReasons = [
  'Spam',
  'Abusive or inappropriate',
  'Test / nonsense',
  'Duplicate',
];

/// Ask the admin why they're dismissing this item. Returns the chosen reason,
/// or null if they cancel. [itemLabel] is e.g. 'report' / 'feedback'.
Future<String?> showAdminDismissDialog(
  BuildContext context, {
  required String itemLabel,
}) {
  return showDialog<String>(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) => _DismissReasonDialog(itemLabel: itemLabel),
  );
}

class _DismissReasonDialog extends StatefulWidget {
  final String itemLabel;
  const _DismissReasonDialog({required this.itemLabel});

  @override
  State<_DismissReasonDialog> createState() => _DismissReasonDialogState();
}

class _DismissReasonDialogState extends State<_DismissReasonDialog> {
  String _reason = kDismissReasons.first;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AdminUi.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        'Dismiss this ${widget.itemLabel}?',
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: AdminUi.textPrimary,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'It will be hidden from the list and excluded from analytics and '
            'the AI forecast. You can restore it later.',
            style: TextStyle(fontSize: 13, color: AdminUi.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 14),
          const Text(
            'REASON',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: AdminUi.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in kDismissReasons)
                _ReasonChip(
                  label: r,
                  selected: _reason == r,
                  onTap: () => setState(() => _reason = r),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: () => Navigator.pop(context, _reason),
          icon: const Icon(Icons.block_rounded, size: 18),
          label: const Text('Dismiss'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.red,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}

class _ReasonChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ReasonChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.red.withValues(alpha: 0.10) : AdminUi.subtle,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? AppColors.red : AdminUi.border,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: selected ? AppColors.red : AdminUi.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// A moderation strip for a detail screen: when the item is dismissed it shows
/// an amber banner + Restore; otherwise a subtle "Dismiss as spam" action.
class AdminModerationBar extends StatelessWidget {
  final bool isDismissed;
  final String? reason;
  final bool busy;
  final VoidCallback onDismiss;
  final VoidCallback onRestore;

  const AdminModerationBar({
    super.key,
    required this.isDismissed,
    required this.reason,
    required this.busy,
    required this.onDismiss,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    if (isDismissed) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.orange.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.orange.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            const Icon(Icons.visibility_off_rounded, size: 18, color: AppColors.orange),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Dismissed — hidden from lists & analytics',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFB45309),
                    ),
                  ),
                  if ((reason ?? '').isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      'Reason: $reason',
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFFB45309)),
                    ),
                  ],
                ],
              ),
            ),
            TextButton.icon(
              onPressed: busy ? null : onRestore,
              icon: const Icon(Icons.restore_rounded, size: 16),
              label: const Text('Restore'),
              style: TextButton.styleFrom(foregroundColor: AppColors.primaryBlue),
            ),
          ],
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: busy ? null : onDismiss,
        icon: const Icon(Icons.block_rounded, size: 16),
        label: const Text('Dismiss as spam'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.red,
          side: BorderSide(color: AppColors.red.withValues(alpha: 0.6)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
      ),
    );
  }
}
