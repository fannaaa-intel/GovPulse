import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/file_download.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/admin_backup_provider.dart';
import '../theme/admin_ui.dart';
import '../widgets/admin_skeleton.dart';
import '../widgets/admin_snackbar.dart';
import '../widgets/admin_submission_ui.dart';
import '../widgets/backup_dialogs.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Admin → Backup & Recovery (nav slot "Backup & Recovery")
//
//  Save a copy of GovPulse data, and bring records back if they are lost.
//
//  This project is on the Supabase FREE plan: no point-in-time recovery and no
//  daily backups. This page is the ONLY safety net, which is why it leans
//  towards being obvious rather than clever — a status line that says plainly
//  when the last backup was, a preview before anything is written, and an
//  automatic safety copy taken before every restore.
//
//  Responsive: a table on web, cards on a phone, same as the Team page.
// ════════════════════════════════════════════════════════════════════════════

/// Asia/Manila, matching every other date in the console.
String formatManila(DateTime when, {bool withTime = true}) {
  // The app runs in the LGU's own timezone, so the device's local time is
  // already Manila. `toLocal()` in the provider does the conversion; this only
  // decides the shape.
  return DateFormat(withTime ? 'd MMM y, h:mm a' : 'd MMM y').format(when);
}

class AdminBackupPage extends ConsumerWidget {
  const AdminBackupPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminBackupProvider);

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
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _Header(),
                      const SizedBox(height: 18),
                      _StatusCard(async: async),
                      const SizedBox(height: 22),
                      const _SectionTitle('Backups'),
                      _BackupList(async: async),
                      const SizedBox(height: 22),
                      const _SectionTitle('Recent restores'),
                      _RestoreHistory(async: async),
                      const SizedBox(height: 22),
                      const _WhatsIncludedCard(),
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

// ── Header ──────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Text(
          'Backup & Recovery',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AdminUi.textPrimary,
            letterSpacing: -0.3,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'Save a copy of GovPulse data and bring it back if records are lost '
          'or deleted by mistake.',
          style: TextStyle(fontSize: 13.5, color: AdminUi.textSecondary, height: 1.4),
        ),
      ],
    );
  }
}

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
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AdminUi.surface,
      borderRadius: BorderRadius.circular(AdminUi.cardRadius),
      border: Border.all(color: AdminUi.border),
      boxShadow: AdminUi.cardShadow,
    ),
    padding: const EdgeInsets.all(16),
    child: child,
  );
}

// ── Status card: last backup + the Create button ────────────────────────────

class _StatusCard extends ConsumerStatefulWidget {
  final AsyncValue<BackupState> async;
  const _StatusCard({required this.async});

  @override
  ConsumerState<_StatusCard> createState() => _StatusCardState();
}

class _StatusCardState extends ConsumerState<_StatusCard> {
  bool _creating = false;

  Future<void> _create() async {
    // Guard the STATE, not just the widget: a double-tap before the first
    // frame repaints would otherwise start two backups, and the second would
    // be refused by the server's job lock with a confusing "busy" message.
    if (_creating) return;

    final label = await showCreateBackupDialog(context);
    if (label == null || !mounted) return; // cancelled

    setState(() => _creating = true);
    try {
      final res = await ref
          .read(adminBackupProvider.notifier)
          .createBackup(label: label.isEmpty ? null : label);
      if (!mounted) return;
      final tables = res.backup.tableCounts.length;
      showAdminSnackBar(
        context,
        'Backup created. ${res.backup.totalRecords} records from $tables tables.',
        type: AdminSnackType.success,
      );
      if (res.warnings.isNotEmpty) {
        await showBackupWarningsDialog(context, res.warnings);
      }
    } on BackupException catch (e) {
      if (mounted) {
        showAdminSnackBar(context, e.message, type: AdminSnackType.error);
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: LayoutBuilder(
        builder: (context, c) {
          final narrow = c.maxWidth < 520;
          final info = widget.async.when(
            loading: () => const _StatusSkeleton(),
            error: (_, _) => const _StatusLine(
              icon: Icons.cloud_off_rounded,
              color: AppColors.red,
              title: "Couldn't load backups.",
              subtitle: 'Check your connection, then try again.',
            ),
            data: (s) => _statusFor(s),
          );

          final button = FilledButton.icon(
            onPressed: _creating ? null : _create,
            icon: _creating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.backup_rounded, size: 18),
            label: Text(_creating ? 'Creating…' : 'Create backup'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AdminUi.controlRadius),
              ),
            ),
          );

          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [info, const SizedBox(height: 14), button],
            );
          }
          return Row(
            children: [
              Expanded(child: info),
              const SizedBox(width: 16),
              button,
            ],
          );
        },
      ),
    );
  }

  Widget _statusFor(BackupState s) {
    final latest = s.latestReady;
    if (latest == null) {
      return const _StatusLine(
        icon: Icons.inventory_2_outlined,
        color: AdminUi.textMuted,
        title: 'No backups yet.',
        subtitle: 'Create your first backup.',
      );
    }
    final stale = s.isStale;
    return _StatusLine(
      icon: stale ? Icons.warning_amber_rounded : Icons.check_circle_rounded,
      color: stale ? AppColors.orange : AppColors.green,
      title: 'Last backup: ${formatManila(latest.createdAt)} '
          'by ${latest.createdByName}',
      subtitle:
          '${latest.totalRecords} records · ${formatBackupSize(latest.sizeBytes)}'
          '${stale ? ' · More than 7 days ago' : ''}',
    );
  }
}

class _StatusLine extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  const _StatusLine({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 20, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AdminUi.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12.5, color: AdminUi.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusSkeleton extends StatelessWidget {
  const _StatusSkeleton();

  @override
  Widget build(BuildContext context) {
    // Wrapped in AdminShimmer because SkeletonBox reads its animation from an
    // inherited clock — unwrapped, the placeholders render as static grey
    // slabs. (AdminShimmer also exists to avoid the ShaderMask bug that made
    // earlier skeletons repaint the card behind them as a solid block.)
    return const AdminShimmer(
      child: Row(
        children: [
          SkeletonBox(width: 36, height: 36, radius: 9),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 260, height: 14),
                SizedBox(height: 6),
                SkeletonBox(width: 160, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── The list ────────────────────────────────────────────────────────────────

class _BackupList extends ConsumerWidget {
  final AsyncValue<BackupState> async;
  const _BackupList({required this.async});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AdminResultsCard(
      child: async.when(
        loading: () => const AdminListSkeleton(),
        // An error must NOT look like an empty list: "no backups yet" when the
        // read simply failed would tell an admin their safety net is empty when
        // it is not.
        error: (_, _) => AdminResultsMessage(
          icon: Icons.cloud_off_rounded,
          color: AppColors.red,
          text: "Couldn't load the list of backups.",
          action: TextButton(
            onPressed: () => ref.read(adminBackupProvider.notifier).refresh(),
            child: const Text('Retry'),
          ),
        ),
        data: (s) {
          if (s.backups.isEmpty) {
            return const AdminResultsMessage(
              icon: Icons.inventory_2_outlined,
              color: AdminUi.textMuted,
              text: 'No backups yet. Create your first backup.',
            );
          }
          return LayoutBuilder(
            builder: (context, c) {
              if (c.maxWidth >= 760) {
                return Column(
                  children: [
                    const _TableHeader(),
                    for (final b in s.backups) _TableRow(backup: b),
                  ],
                );
              }
              return Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [for (final b in s.backups) _BackupCard(backup: b)],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: const BoxDecoration(
      color: AdminUi.subtle,
      border: Border(bottom: BorderSide(color: AdminUi.border)),
    ),
    child: Row(
      children: const [
        _HCell('BACKUP', flex: 4),
        _HCell('TYPE', flex: 2),
        _HCell('RECORDS', flex: 2),
        _HCell('SIZE', flex: 2),
        SizedBox(width: 40),
      ],
    ),
  );
}

class _HCell extends StatelessWidget {
  final String text;
  final int flex;
  const _HCell(this.text, {this.flex = 1});
  @override
  Widget build(BuildContext context) => Expanded(
    flex: flex,
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: AdminUi.textMuted,
      ),
    ),
  );
}

class _KindChip extends StatelessWidget {
  final BackupKind kind;
  const _KindChip(this.kind);

  @override
  Widget build(BuildContext context) {
    final c = switch (kind) {
      BackupKind.manual => AppColors.primaryBlue,
      BackupKind.preRestore => AppColors.orange,
      BackupKind.automatic => AppColors.green,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        kind.label,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: c),
      ),
    );
  }
}

class _TableRow extends ConsumerWidget {
  final BackupEntry backup;
  const _TableRow({required this.backup});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AdminUi.border)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  backup.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AdminUi.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatManila(backup.createdAt)} · ${backup.createdByName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: AdminUi.textMuted),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: backup.isFailed
                  ? const StatusPill(label: 'Failed', color: AppColors.red)
                  : _KindChip(backup.kind),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              backup.isReady ? '${backup.totalRecords}' : '—',
              style: const TextStyle(fontSize: 13, color: AdminUi.textSecondary),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              backup.isReady ? formatBackupSize(backup.sizeBytes) : '—',
              style: const TextStyle(fontSize: 13, color: AdminUi.textSecondary),
            ),
          ),
          _RowMenu(backup: backup),
        ],
      ),
    );
  }
}

class _BackupCard extends StatelessWidget {
  final BackupEntry backup;
  const _BackupCard({required this.backup});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AdminUi.surface,
        borderRadius: BorderRadius.circular(AdminUi.controlRadius),
        border: Border.all(color: AdminUi.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  backup.displayTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AdminUi.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _RowMenu(backup: backup),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (backup.isFailed)
                const StatusPill(label: 'Failed', color: AppColors.red)
              else
                _KindChip(backup.kind),
              if (backup.isReady)
                Text(
                  '${backup.totalRecords} records · ${formatBackupSize(backup.sizeBytes)}',
                  style: const TextStyle(fontSize: 12, color: AdminUi.textSecondary),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${formatManila(backup.createdAt)} · ${backup.createdByName}',
            style: const TextStyle(fontSize: 11.5, color: AdminUi.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Details / Download / Restore / Delete.
class _RowMenu extends ConsumerWidget {
  final BackupEntry backup;
  const _RowMenu({required this.backup});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'Actions',
      icon: const Icon(Icons.more_vert_rounded, size: 20, color: AdminUi.textMuted),
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AdminUi.controlRadius),
        side: const BorderSide(color: AdminUi.border),
      ),
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'details', child: Text('Details')),
        if (backup.isReady) ...[
          const PopupMenuItem(value: 'download', child: Text('Download')),
          const PopupMenuItem(value: 'restore', child: Text('Restore from this')),
        ],
        const PopupMenuItem(
          value: 'delete',
          child: Text('Delete', style: TextStyle(color: AppColors.red)),
        ),
      ],
      onSelected: (v) => switch (v) {
        'details' => showBackupDetailsSheet(context, backup),
        'download' => _download(context, ref),
        'restore' => showRestoreFlow(context, ref, backup),
        'delete' => _delete(context, ref),
        _ => null,
      },
    );
  }

  /// Two steps on purpose.
  ///
  /// Fetching the signed URL is asynchronous, and Safari withdraws permission
  /// to navigate away as soon as the gesture's stack unwinds — so an `await`
  /// followed by a download in the same tap is blocked on iOS (the lesson from
  /// the emergency dialer). The first tap gets the link, the second tap uses
  /// it, and that second tap is a fresh gesture the browser honours.
  Future<void> _download(BuildContext context, WidgetRef ref) async {
    showAdminSnackBar(context, 'Preparing the download…');
    try {
      final link = await ref.read(adminBackupProvider.notifier).downloadUrl(backup.id);
      if (!context.mounted) return;
      await showDownloadReadyDialog(
        context,
        filename: link.filename,
        onDownload: () {
          // Synchronous inside the button's own tap.
          if (kIsWeb) {
            downloadFromBrowser(link.url, link.filename);
          } else {
            launchUrl(Uri.parse(link.url), mode: LaunchMode.externalApplication);
          }
        },
      );
    } on BackupException catch (e) {
      if (context.mounted) {
        showAdminSnackBar(context, e.message, type: AdminSnackType.error);
      }
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDeleteBackupDialog(context, backup);
    if (!ok || !context.mounted) return;
    try {
      await ref.read(adminBackupProvider.notifier).deleteBackup(backup.id);
      if (context.mounted) {
        showAdminSnackBar(
          context,
          'Backup deleted.',
          type: AdminSnackType.success,
        );
      }
    } on BackupException catch (e) {
      if (context.mounted) {
        showAdminSnackBar(context, e.message, type: AdminSnackType.error);
      }
    }
  }
}

// ── Restore history ─────────────────────────────────────────────────────────

class _RestoreHistory extends StatelessWidget {
  final AsyncValue<BackupState> async;
  const _RestoreHistory({required this.async});

  @override
  Widget build(BuildContext context) {
    return AdminResultsCard(
      child: async.when(
        loading: () => const AdminListSkeleton(),
        error: (_, _) => const AdminResultsMessage(
          icon: Icons.cloud_off_rounded,
          color: AppColors.red,
          text: "Couldn't load the restore history.",
        ),
        data: (s) {
          if (s.restores.isEmpty) {
            return const AdminResultsMessage(
              icon: Icons.history_rounded,
              color: AdminUi.textMuted,
              text: 'Nothing has been restored yet.',
            );
          }
          return Column(
            children: [for (final r in s.restores) _RestoreRow(entry: r)],
          );
        },
      ),
    );
  }
}

class _RestoreRow extends StatelessWidget {
  final RestoreHistoryEntry entry;
  const _RestoreRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final ok = entry.succeeded;
    final running = entry.status == 'running';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AdminUi.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            running
                ? Icons.hourglass_top_rounded
                : ok
                    ? Icons.check_circle_rounded
                    : Icons.error_outline_rounded,
            size: 18,
            color: running
                ? AppColors.orange
                : ok
                    ? AppColors.green
                    : AppColors.red,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  running
                      ? 'Restoring ${entry.backupName ?? 'a backup'}…'
                      : ok
                          ? 'Restored from ${entry.backupName ?? 'a backup'}'
                          : 'Restore failed',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AdminUi.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  ok
                      ? '${entry.totalAdded} brought back, ${entry.totalUpdated} updated'
                      : entry.error ?? '',
                  style: const TextStyle(fontSize: 12, color: AdminUi.textSecondary),
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatManila(entry.startedAt)} · ${entry.startedByName}'
                  '${entry.safetyBackupName != null ? ' · safety copy: ${entry.safetyBackupName}' : ''}',
                  style: const TextStyle(fontSize: 11.5, color: AdminUi.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── What's included ─────────────────────────────────────────────────────────

class _WhatsIncludedCard extends StatelessWidget {
  const _WhatsIncludedCard();

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'What a backup contains',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AdminUi.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          const _Bullet(
            icon: Icons.check_rounded,
            color: AppColors.green,
            text: 'Reports, suggestions, feedback, events, verifications, '
                'community posts and comments, accounts and their roles, '
                'and the admin activity log.',
          ),
          const _Bullet(
            icon: Icons.close_rounded,
            color: AppColors.red,
            text: 'Photos and videos are NOT included — only the records that '
                'refer to them. Files stay in storage and are never deleted by '
                'a restore.',
          ),
          const _Bullet(
            icon: Icons.close_rounded,
            color: AppColors.red,
            text: 'Notifications are not included, because restoring them would '
                'send push messages to people again.',
          ),
          const _Bullet(
            icon: Icons.close_rounded,
            color: AppColors.red,
            text: 'Login accounts themselves are not re-created. If an account '
                'was deleted, its records are skipped and listed.',
          ),
          const _Bullet(
            icon: Icons.lock_rounded,
            color: AppColors.primaryBlue,
            text: 'Every backup file is encrypted and kept private. A download '
                'link lasts 60 seconds.',
          ),
          const _Bullet(
            icon: Icons.shield_rounded,
            color: AppColors.primaryBlue,
            text: 'A restore only adds back what is missing. It never deletes '
                'anything, and a safety copy is saved first.',
          ),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _Bullet({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 15, color: color),
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
