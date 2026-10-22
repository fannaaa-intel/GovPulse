import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_dialog.dart';
import '../pages/admin_backup_page.dart' show formatManila;
import '../providers/admin_backup_provider.dart';
import '../theme/admin_ui.dart';
import 'admin_responsive_dialog.dart';
import 'admin_snackbar.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Backup & Recovery dialogs
//
//  Create · Details · Download · Delete · the 3-step Restore flow.
//
//  All of them use AdminResponsiveDialog, so each is a centred modal on the web
//  console and a full-screen sheet on a phone — the admin console runs on
//  mobile too, and a fixed-width modal there strands its buttons off-screen.
//
//  The restore flow is deliberately slow to get through: mode → preview →
//  typed confirmation + password. It rewrites production data on a project with
//  no point-in-time recovery, so every step is a chance to notice something is
//  wrong before anything is written.
// ════════════════════════════════════════════════════════════════════════════

/// Returns the label the admin typed (possibly empty), or null if cancelled.
Future<String?> showCreateBackupDialog(BuildContext context) {
  final controller = TextEditingController();
  return showAppDialog<String>(
    context: context,
    builder: (ctx) => AdminResponsiveDialog(
      title: 'Create a backup',
      subtitle: 'Saves a copy of the current GovPulse records.',
      maxWidth: 520,
      leading: const Icon(Icons.backup_rounded, color: AppColors.primaryBlue),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          // Empty is fine — the backup is named after its date either way.
          onPressed: () => Navigator.of(ctx).pop(controller.text),
          style: FilledButton.styleFrom(backgroundColor: AppColors.primaryBlue),
          child: const Text('Create backup'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Give it a name you will recognise later (optional).',
            style: TextStyle(fontSize: 13, color: AdminUi.textSecondary),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            autofocus: true,
            maxLength: 80,
            decoration: InputDecoration(
              hintText: 'For example: Before clearing old reports',
              counterText: '',
              filled: true,
              fillColor: AdminUi.subtle,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AdminUi.controlRadius),
                borderSide: const BorderSide(color: AdminUi.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AdminUi.controlRadius),
                borderSide: const BorderSide(color: AdminUi.border),
              ),
            ),
            onSubmitted: (v) => Navigator.of(ctx).pop(v),
          ),
          const SizedBox(height: 12),
          const _InfoNote(
            'Photos and videos are not included, and notifications are left '
            'out so that restoring never sends messages to people again.',
          ),
        ],
      ),
    ),
  );
}

/// Coverage and schema warnings worth reading, but not worth blocking on.
Future<void> showBackupWarningsDialog(
  BuildContext context,
  List<String> warnings,
) {
  return showAppDialog<void>(
    context: context,
    builder: (ctx) => AdminResponsiveDialog(
      title: 'Backup created, with notes',
      maxWidth: 560,
      leading: const Icon(Icons.warning_amber_rounded, color: AppColors.orange),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          style: FilledButton.styleFrom(backgroundColor: AppColors.primaryBlue),
          child: const Text('Got it'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final w in warnings) _WarningRow(w)],
      ),
    ),
  );
}

// ── Details ─────────────────────────────────────────────────────────────────

Future<void> showBackupDetailsSheet(BuildContext context, BackupEntry backup) {
  final tables = backup.tableCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  return showAppDialog<void>(
    context: context,
    builder: (ctx) => AdminResponsiveDialog(
      title: backup.displayTitle,
      subtitle: '${formatManila(backup.createdAt)} · ${backup.createdByName}',
      maxWidth: 620,
      leading: const Icon(Icons.inventory_2_outlined, color: AppColors.primaryBlue),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          style: FilledButton.styleFrom(backgroundColor: AppColors.primaryBlue),
          child: const Text('Close'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Fact('Records', '${backup.totalRecords}'),
              _Fact('Size', formatBackupSize(backup.sizeBytes)),
              _Fact('Type', backup.kind.label),
              _Fact('File name', backup.name),
              _Fact('Database version', backup.schemaVersion ?? '—'),
              // Shown so two backups can be told apart by eye, and so a
              // download can be checked against what the server recorded.
              _Fact('Checksum', backup.shortChecksum),
            ],
          ),
          if (backup.error != null) ...[
            const SizedBox(height: 14),
            _WarningRow(backup.error!),
          ],
          const SizedBox(height: 18),
          const Text(
            'RECORDS IN THIS BACKUP',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: AdminUi.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          if (tables.isEmpty)
            const Text(
              'No record counts were saved for this backup.',
              style: TextStyle(fontSize: 13, color: AdminUi.textSecondary),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: AdminUi.subtle,
                borderRadius: BorderRadius.circular(AdminUi.controlRadius),
                border: Border.all(color: AdminUi.border),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Column(
                children: [
                  for (final e in tables)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              friendlyTableName(e.key),
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: AdminUi.textSecondary,
                              ),
                            ),
                          ),
                          Text(
                            '${e.value}',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AdminUi.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          const _InfoNote(
            'Not included: photos and videos, notifications, and login '
            'accounts themselves. A restore only adds back missing records — '
            'it never deletes anything.',
          ),
        ],
      ),
    ),
  );
}

// ── Download ────────────────────────────────────────────────────────────────

/// The second half of the two-tap download.
///
/// The signed URL has already been fetched (that was the first tap). This
/// dialog exists so the navigation that actually saves the file happens inside
/// a FRESH user gesture: Safari withdraws permission to navigate away once the
/// original gesture's stack unwinds, so an `await` followed by a download in
/// the same tap is silently blocked on iOS and iPadOS.
Future<void> showDownloadReadyDialog(
  BuildContext context, {
  required String filename,
  required VoidCallback onDownload,
}) {
  return showAppDialog<void>(
    context: context,
    builder: (ctx) => AdminResponsiveDialog(
      title: 'Your backup is ready',
      subtitle: filename,
      maxWidth: 520,
      leading: const Icon(Icons.download_rounded, color: AppColors.primaryBlue),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: () {
            // Synchronous: no await between this tap and the navigation.
            onDownload();
            Navigator.of(ctx).pop();
          },
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('Download file'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.primaryBlue),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          _InfoNote(
            'The link lasts 60 seconds, so download it now. If it expires, '
            'just choose Download again.',
          ),
          SizedBox(height: 10),
          _WarningRow(
            'This file contains residents’ personal information. It is '
            'encrypted, but keep it somewhere safe and do not email it.',
          ),
        ],
      ),
    ),
  );
}

// ── Delete ──────────────────────────────────────────────────────────────────

Future<bool> showDeleteBackupDialog(
  BuildContext context,
  BackupEntry backup,
) async {
  final ok = await showAppDialog<bool>(
    context: context,
    builder: (ctx) => AdminResponsiveDialog(
      title: 'Delete this backup?',
      subtitle: backup.displayTitle,
      maxWidth: 520,
      leading: const Icon(Icons.delete_outline_rounded, color: AppColors.red),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Keep it'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: FilledButton.styleFrom(backgroundColor: AppColors.red),
          child: const Text('Delete backup'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'The backup file will be removed for good. '
            '${backup.totalRecords} saved records will no longer be '
            'recoverable from this copy.',
            style: const TextStyle(
              fontSize: 13.5,
              color: AdminUi.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          const _WarningRow('This cannot be undone.'),
        ],
      ),
    ),
  );
  return ok ?? false;
}

// ── Restore: the 3-step flow ────────────────────────────────────────────────

/// Mode → Preview → Confirm, then a result screen.
///
/// Each step is its own dialog rather than one dialog with an index, so a step
/// that needs a different size or set of buttons simply is a different dialog,
/// and backing out of one lands on the previous one instead of unwinding the
/// whole flow.
Future<void> showRestoreFlow(
  BuildContext context,
  WidgetRef ref,
  BackupEntry backup,
) async {
  // Step 1 — what should it do?
  final mode = await _askMode(context, backup);
  if (mode == null || !context.mounted) return;

  // Step 2 — a dry run, so nobody confirms blind.
  RestorePreview preview;
  try {
    preview = await _withBlockingSpinner(
      context,
      'Checking what would change…',
      () => ref.read(adminBackupProvider.notifier).preview(backup.id, mode),
    );
  } on BackupException catch (e) {
    if (context.mounted) {
      showAdminSnackBar(context, e.message, type: AdminSnackType.error);
    }
    return;
  }
  if (!context.mounted) return;

  final goOn = await _showPreview(context, backup, mode, preview);
  if (goOn != true || !context.mounted) return;

  // Step 3 — typed confirmation plus the admin's password.
  final outcome = await _confirmAndRun(context, ref, backup, mode);
  if (outcome == null || !context.mounted) return;

  await _showResult(context, outcome);
}

Future<RestoreMode?> _askMode(BuildContext context, BackupEntry backup) {
  return showAppDialog<RestoreMode>(
    context: context,
    builder: (ctx) {
      var alsoUndo = false;
      return StatefulBuilder(
        builder: (ctx, setState) => AdminResponsiveDialog(
          title: 'Restore from this backup',
          subtitle: '${backup.displayTitle} · ${formatManila(backup.createdAt)}',
          maxWidth: 600,
          leading: const Icon(Icons.restore_rounded, color: AppColors.primaryBlue),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(
                alsoUndo ? RestoreMode.missingAndChanged : RestoreMode.missingOnly,
              ),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primaryBlue),
              child: const Text('Next: see what changes'),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The default, and always on: this is what "restore" means here.
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(AdminUi.controlRadius),
                  border: Border.all(
                    color: AppColors.primaryBlue.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Icon(Icons.check_circle_rounded,
                        size: 18, color: AppColors.primaryBlue),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Bring back missing records',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AdminUi.textPrimary,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Adds back anything that was deleted. Records that '
                            'are still here are left exactly as they are.',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: AdminUi.textSecondary,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // The optional extra, off by default, because it overwrites work
              // done since the backup.
              InkWell(
                onTap: () => setState(() => alsoUndo = !alsoUndo),
                borderRadius: BorderRadius.circular(AdminUi.controlRadius),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AdminUi.subtle,
                    borderRadius: BorderRadius.circular(AdminUi.controlRadius),
                    border: Border.all(color: AdminUi.border),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: Checkbox(
                          value: alsoUndo,
                          onChanged: (v) => setState(() => alsoUndo = v ?? false),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'Also undo changes to existing records',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AdminUi.textPrimary,
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Puts records that have been edited since the '
                              'backup back to how they were. Any work done on '
                              'them since then will be lost.',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: AdminUi.textSecondary,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const _InfoNote(
                'A safety copy of the current data is always saved first, so '
                'this can be undone.',
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<bool?> _showPreview(
  BuildContext context,
  BackupEntry backup,
  RestoreMode mode,
  RestorePreview preview,
) {
  final changed = preview.changedTables;

  return showAppDialog<bool>(
    context: context,
    builder: (ctx) => AdminResponsiveDialog(
      title: 'What this restore will do',
      subtitle: '${backup.displayTitle} · nothing has been changed yet',
      maxWidth: 680,
      leading: const Icon(Icons.fact_check_outlined, color: AppColors.primaryBlue),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 8),
        if (!preview.isNoOp)
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primaryBlue),
            child: const Text('Next: confirm'),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (preview.isNoOp)
            // The useful "nothing to do" answer. Without it an admin cannot
            // tell a working restore from a broken one.
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AdminUi.controlRadius),
                border: Border.all(color: AppColors.green.withValues(alpha: 0.35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Icon(Icons.check_circle_rounded, size: 18, color: AppColors.green),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Nothing to restore. Current data already matches this '
                      'backup.',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AdminUi.textPrimary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _Fact('Will be brought back', '${preview.totalAdded}'),
                if (mode == RestoreMode.missingAndChanged)
                  _Fact('Will be put back', '${preview.totalUpdated}'),
                _Fact('Already correct', '${preview.totalUnchanged}'),
                if (preview.totalSkipped > 0)
                  _Fact('Skipped', '${preview.totalSkipped}'),
              ],
            ),
            const SizedBox(height: 18),
            const Text(
              'WHAT CHANGES',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: AdminUi.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: AdminUi.subtle,
                borderRadius: BorderRadius.circular(AdminUi.controlRadius),
                border: Border.all(color: AdminUi.border),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Column(
                children: [
                  for (final (name, r) in changed)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              friendlyTableName(name),
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: AdminUi.textSecondary,
                              ),
                            ),
                          ),
                          if (r.added > 0)
                            _MiniTag('+${r.added} back', AppColors.green),
                          if (r.updated > 0) ...[
                            const SizedBox(width: 6),
                            _MiniTag('${r.updated} put back', AppColors.orange),
                          ],
                          if (r.skipped > 0) ...[
                            const SizedBox(width: 6),
                            _MiniTag('${r.skipped} skipped', AdminUi.textMuted),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (preview.warnings.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Text(
              'PLEASE NOTE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: AdminUi.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            for (final w in preview.warnings) _WarningRow(w),
          ],
        ],
      ),
    ),
  );
}

/// Step 3: type RESTORE and enter the password. Runs the restore on confirm.
Future<RestoreOutcome?> _confirmAndRun(
  BuildContext context,
  WidgetRef ref,
  BackupEntry backup,
  RestoreMode mode,
) {
  return showAppDialog<RestoreOutcome>(
    context: context,
    // Not dismissible: a stray tap on the barrier mid-restore would look like
    // the restore was cancelled when it is still running.
    barrierDismissible: false,
    builder: (ctx) {
      final confirmCtl = TextEditingController();
      final passwordCtl = TextEditingController();
      var busy = false;
      var errorText = '';
      return StatefulBuilder(
        builder: (ctx, setState) {
          final ready = confirmCtl.text.trim().toUpperCase() == 'RESTORE' &&
              passwordCtl.text.isNotEmpty;

          Future<void> run() async {
            if (busy || !ready) return;
            setState(() {
              busy = true;
              errorText = '';
            });
            try {
              final outcome = await ref.read(adminBackupProvider.notifier).apply(
                    id: backup.id,
                    mode: mode,
                    password: passwordCtl.text,
                  );
              if (ctx.mounted) Navigator.of(ctx).pop(outcome);
            } on BackupException catch (e) {
              if (!ctx.mounted) return;
              // A wrong password keeps the dialog open so the admin can retry
              // without walking the whole flow again.
              setState(() {
                busy = false;
                errorText = e.message;
              });
              if (e.isBadPassword) passwordCtl.clear();
            }
          }

          return AdminResponsiveDialog(
            title: 'Confirm the restore',
            subtitle: backup.displayTitle,
            maxWidth: 560,
            leading: const Icon(Icons.shield_outlined, color: AppColors.orange),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: (ready && !busy) ? run : null,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                ),
                child: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Restore now'),
              ),
            ],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: AppColors.green.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AdminUi.controlRadius),
                    border:
                        Border.all(color: AppColors.green.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Icon(Icons.save_rounded, size: 17, color: AppColors.green),
                      SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          'A safety copy of the current data will be saved '
                          'first, so you can undo this.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AdminUi.textSecondary,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Type RESTORE to confirm',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AdminUi.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: confirmCtl,
                  enabled: !busy,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [LengthLimitingTextInputFormatter(10)],
                  onChanged: (_) => setState(() {}),
                  decoration: _fieldDecoration('RESTORE'),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Your account password',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AdminUi.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: passwordCtl,
                  enabled: !busy,
                  obscureText: true,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => run(),
                  decoration: _fieldDecoration('Password'),
                ),
                if (errorText.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _WarningRow(errorText),
                ],
                if (busy) ...[
                  const SizedBox(height: 14),
                  const Text(
                    'Saving a safety copy, then restoring. This can take a '
                    'moment — please do not close this window.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AdminUi.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      );
    },
  );
}

Future<void> _showResult(BuildContext context, RestoreOutcome outcome) {
  return showAppDialog<void>(
    context: context,
    builder: (ctx) => AdminResponsiveDialog(
      title: 'Restore complete',
      subtitle: '${outcome.totalAdded} brought back · '
          '${outcome.totalUpdated} put back',
      maxWidth: 640,
      leading: const Icon(Icons.check_circle_rounded, color: AppColors.green),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          style: FilledButton.styleFrom(backgroundColor: AppColors.primaryBlue),
          child: const Text('Done'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (outcome.safetyBackupName != null)
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: AdminUi.subtle,
                borderRadius: BorderRadius.circular(AdminUi.controlRadius),
                border: Border.all(color: AdminUi.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.save_rounded, size: 17, color: AppColors.green),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'A safety copy of the data from before this restore was '
                      'saved as "${outcome.safetyBackupName}". Restore from '
                      'that if you need to undo this.',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AdminUi.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          if (outcome.changedTables.isEmpty)
            const Text(
              'Nothing needed to change.',
              style: TextStyle(fontSize: 13, color: AdminUi.textSecondary),
            )
          else ...[
            const Text(
              'WHAT CHANGED',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: AdminUi.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: AdminUi.subtle,
                borderRadius: BorderRadius.circular(AdminUi.controlRadius),
                border: Border.all(color: AdminUi.border),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Column(
                children: [
                  for (final (name, r) in outcome.changedTables)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              friendlyTableName(name),
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: AdminUi.textSecondary,
                              ),
                            ),
                          ),
                          if (r.added > 0)
                            _MiniTag('+${r.added} back', AppColors.green),
                          if (r.updated > 0) ...[
                            const SizedBox(width: 6),
                            _MiniTag('${r.updated} put back', AppColors.orange),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (outcome.warnings.isNotEmpty) ...[
            const SizedBox(height: 16),
            for (final w in outcome.warnings) _WarningRow(w),
          ],
        ],
      ),
    ),
  );
}

// ── Shared pieces ───────────────────────────────────────────────────────────

InputDecoration _fieldDecoration(String hint) => InputDecoration(
  hintText: hint,
  isDense: true,
  filled: true,
  fillColor: AdminUi.subtle,
  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AdminUi.controlRadius),
    borderSide: const BorderSide(color: AdminUi.border),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AdminUi.controlRadius),
    borderSide: const BorderSide(color: AdminUi.border),
  ),
);

/// Runs [task] behind a dialog that cannot be dismissed, so a slow preview
/// cannot be mistaken for a frozen console.
Future<T> _withBlockingSpinner<T>(
  BuildContext context,
  String message,
  Future<T> Function() task,
) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  showAppDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        decoration: BoxDecoration(
          color: AdminUi.surface,
          borderRadius: BorderRadius.circular(AdminUi.cardRadius),
          boxShadow: AdminUi.cardShadow,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 14),
            Text(
              message,
              style: const TextStyle(fontSize: 13.5, color: AdminUi.textPrimary),
            ),
          ],
        ),
      ),
    ),
  );
  try {
    return await task();
  } finally {
    // Pop the spinner whether the task succeeded or threw, so a failure never
    // leaves the console behind an undismissable overlay.
    if (navigator.canPop()) navigator.pop();
  }
}

class _Fact extends StatelessWidget {
  final String label;
  final String value;
  const _Fact(this.label, this.value);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: AdminUi.subtle,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AdminUi.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: AdminUi.textMuted,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AdminUi.textPrimary,
          ),
        ),
      ],
    ),
  );
}

class _MiniTag extends StatelessWidget {
  final String text;
  final Color color;
  const _MiniTag(this.text, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color),
    ),
  );
}

class _InfoNote extends StatelessWidget {
  final String text;
  const _InfoNote(this.text);

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Padding(
        padding: EdgeInsets.only(top: 1),
        child: Icon(Icons.info_outline_rounded, size: 15, color: AdminUi.textMuted),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            color: AdminUi.textMuted,
            height: 1.45,
          ),
        ),
      ),
    ],
  );
}

class _WarningRow extends StatelessWidget {
  final String text;
  const _WarningRow(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(Icons.warning_amber_rounded, size: 15, color: AppColors.orange),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12.5,
              color: AdminUi.textSecondary,
              height: 1.45,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Table names an admin can read.
///
/// The preview and the details sheet both list tables, and `community_post_images`
/// means nothing to the person deciding whether to restore. Anything not named
/// here falls back to a de-underscored version rather than being hidden, so a
/// table added later still appears.
String friendlyTableName(String table) => switch (table) {
  'reports' => 'Reports',
  'report_media' => 'Report photos and videos',
  'report_notes' => 'Internal notes on reports',
  'report_updates' => 'Progress updates',
  'report_update_media' => 'Photos on progress updates',
  'report_resolution_media' => 'Completion photos',
  'report_endorsements' => 'Endorsements to agencies',
  'report_endorsement_events' => 'Endorsement history',
  'agency_feedback' => 'Ratings of agencies',
  'suggestions' => 'Suggestions',
  'suggestion_media' => 'Suggestion photos',
  'suggestion_replies' => 'Replies to suggestions',
  'feedbacks' => 'Service feedback',
  'events' => 'Events',
  'verification_submissions' => 'ID verifications',
  'community_posts' => 'Community posts',
  'community_post_images' => 'Images on posts',
  'community_post_likes' => 'Post likes',
  'community_comments' => 'Comments',
  'community_comment_likes' => 'Comment likes',
  'profiles' => 'Accounts',
  'user_roles' => 'Account roles',
  'citizen_details' => 'Citizen profiles',
  'admin_details' => 'Admin records',
  'staff_details' => 'Staff records',
  'admin_profiles' => 'Staff and admin profiles',
  'user_restrictions' => 'Feature restrictions',
  'user_suspensions' => 'Suspensions',
  'notification_preferences' => 'Notification settings',
  'admin_activity_log' => 'Admin activity log',
  'roles' => 'Role definitions',
  'lgu_facts' => 'Chatbot facts',
  'moderation_terms' => 'Banned words',
  'moderation_allow_terms' => 'Allowed words',
  'moderation_settings' => 'Moderation settings',
  'concern_tickets' => 'Old support tickets',
  'ticket_messages' => 'Old ticket messages',
  'ticket_attachments' => 'Old ticket attachments',
  _ => table.replaceAll('_', ' '),
};
