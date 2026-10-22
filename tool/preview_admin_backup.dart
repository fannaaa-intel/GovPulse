// Preview target: the REAL Admin → Backup & Recovery page and its dialogs.
//
//   flutter build web --release -t tool/preview_admin_backup.dart -o build/preview_admin_backup
//
// No Supabase. `adminBackupProvider` is overridden with a fake notifier that
// returns canned state and canned preview/apply answers, which is the
// sanctioned way to see an admin page here (override the provider, not
// PostgREST).
//
// ?state= picks what to render:
//   list     (default) the populated list + restore history
//   empty    the first-run empty state
//   stale    a backup older than 7 days, so the amber "stale" warning shows
//   failed   a failed backup row above the healthy ones
//   restore  the whole restore flow: mode → dry-run preview → confirm → result
//   details  the backup details sheet
//   warnings the post-create warnings dialog
//   create   the "name this backup" dialog
//
// The restore flow advances on its own as each dialog is dismissed, so one run
// of ?state=restore walks all four steps — that is also the only honest way to
// see them, since each step is built from the previous step's answer.
//
// ?w= forces a logical width so phone widths can be checked: the admin console
// runs on mobile too, and a 1280px screenshot does not prove a 390px layout.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:govpulse/core/services/web_splash.dart';
import 'package:govpulse/features/admin/pages/admin_backup_page.dart';
import 'package:govpulse/features/admin/providers/admin_backup_provider.dart';
import 'package:govpulse/features/admin/theme/admin_ui.dart';
import 'package:govpulse/features/admin/widgets/backup_dialogs.dart';

// ── canned data ──────────────────────────────────────────────────────────────

BackupEntry _entry({
  required String id,
  String? label,
  BackupKind kind = BackupKind.manual,
  int daysAgo = 0,
  int hoursAgo = 3,
  int sizeBytes = 184320,
  int totalRecords = 241,
  String status = 'ready',
  String? error,
}) {
  // Derive the name from the row's own timestamp. A hardcoded name made every
  // row read "2026-10-22-0914" regardless of its date, which would have hidden
  // a wrong-name bug behind a fixture that was wrong in the same way.
  final at = DateTime.now().subtract(Duration(days: daysAgo, hours: hoursAgo));
  String two(int v) => v.toString().padLeft(2, '0');
  final stamp = '${at.year}-${two(at.month)}-${two(at.day)}-'
      '${two(at.hour)}${two(at.minute)}';

  return BackupEntry(
    id: id,
    name: 'govpulse-backup-$stamp',
    label: label,
  kind: kind,
    createdByName: 'Mark Reduca',
    createdAt: at,
    sizeBytes: sizeBytes,
    totalRecords: totalRecords,
    tableCounts: const {
      'reports': 13,
      'suggestions': 19,
      'feedbacks': 13,
      'profiles': 9,
      'user_roles': 8,
      'community_posts': 3,
      'community_post_images': 10,
      'verification_submissions': 4,
      'lgu_facts': 35,
      'admin_activity_log': 19,
      'roles': 3,
    },
    schemaVersion: '20261022000000',
    // Vary by id, so two rows never show the same fingerprint.
    checksum: id.hashCode.toUnsigned(32).toRadixString(16).padLeft(8, '0') * 4,
    status: status,
    error: error,
  );
}

final _ready = <BackupEntry>[
  _entry(id: 'b1', label: 'Before the October cleanup', hoursAgo: 3),
  _entry(
    id: 'b2',
    kind: BackupKind.preRestore,
    daysAgo: 1,
    sizeBytes: 176128,
    totalRecords: 238,
  ),
  _entry(id: 'b3', daysAgo: 4, sizeBytes: 171008, totalRecords: 230),
  // A long label, to catch the overflow a tidy fixture would hide.
  _entry(
    id: 'b4',
    label: 'Weekly safety copy taken before the barangay data migration and '
        'the suggestion re-routing change',
    daysAgo: 6,
    sizeBytes: 169984,
    totalRecords: 228,
  ),
];

final _restores = <RestoreHistoryEntry>[
  RestoreHistoryEntry(
    id: 'r1',
    backupName: 'govpulse-backup-2026-10-21-2210',
    mode: RestoreMode.missingOnly,
    startedByName: 'Mark Reduca',
    startedAt: DateTime.now().subtract(const Duration(hours: 20)),
    status: 'completed',
    safetyBackupName: 'govpulse-backup-2026-10-21-2209',
    error: null,
    result: const {
      'reports': RestoreTableResult(added: 4, unchanged: 9),
      'report_notes': RestoreTableResult(added: 2, unchanged: 1),
    },
  ),
  RestoreHistoryEntry(
    id: 'r2',
    backupName: 'govpulse-backup-2026-10-18-0800',
    mode: RestoreMode.missingAndChanged,
    startedByName: 'Mark Reduca',
    startedAt: DateTime.now().subtract(const Duration(days: 3)),
    status: 'failed',
    safetyBackupName: null,
    error: 'The restore was cancelled because a report referenced a citizen '
        'account that no longer exists.',
    result: const {},
  ),
];

/// Deliberately varied: tables that only add, only update, only skip, and one
/// that does nothing — so every row style in the preview table is exercised.
const _previewTables = <String, RestoreTableResult>{
  'reports': RestoreTableResult(added: 4, updated: 2, unchanged: 7),
  'report_notes': RestoreTableResult(added: 3, unchanged: 1),
  'suggestions': RestoreTableResult(added: 1, updated: 1, unchanged: 17),
  'community_posts': RestoreTableResult(added: 1, unchanged: 2),
  'citizen_details': RestoreTableResult(unchanged: 4, skippedMissingUser: 1),
  'admin_activity_log': RestoreTableResult(added: 5, skippedTooOld: 3),
  'profiles': RestoreTableResult(unchanged: 9),
};

const _warnings = <String>[
  '1 record was skipped because the user account no longer exists.',
  '3 activity-log entries were older than 90 days and were skipped.',
  '2 restored events are dated before yesterday and will be removed by the '
      'nightly cleanup.',
  'Some restored records point at photos that are no longer in storage, so '
      'their images will appear broken.',
];

// ── a notifier that never touches the network ────────────────────────────────

class _FakeNotifier extends AdminBackupNotifier {
  _FakeNotifier(this._state);
  final BackupState _state;

  @override
  Future<BackupState> build() async => _state;

  @override
  Future<RestorePreview> preview(String id, RestoreMode mode) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return const RestorePreview(tables: _previewTables, warnings: _warnings);
  }

  @override
  Future<RestoreOutcome> apply({
    required String id,
    required RestoreMode mode,
    required String password,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return const RestoreOutcome(
      tables: _previewTables,
      warnings: _warnings,
      safetyBackupName: 'govpulse-backup-2026-10-22-0930',
    );
  }
}

// ── harness ──────────────────────────────────────────────────────────────────

String _q(String key, String fallback) {
  final v = Uri.base.queryParameters[key];
  return (v == null || v.isEmpty) ? fallback : v;
}

void main() {
  final state = _q('state', 'list');

  final BackupState data = switch (state) {
    'empty' => const BackupState(backups: [], restores: []),
    'stale' => BackupState(
      backups: [_entry(id: 'b9', daysAgo: 23)],
      restores: const [],
    ),
    'failed' => BackupState(
      backups: [
        _entry(
          id: 'bf',
          status: 'failed',
          error: 'The backup stopped because the database was busy. Try again.',
          totalRecords: 0,
          sizeBytes: 0,
        ),
        ..._ready,
      ],
      restores: _restores,
    ),
    _ => BackupState(backups: _ready, restores: _restores),
  };

  runApp(
    ProviderScope(
      overrides: [adminBackupProvider.overrideWith(() => _FakeNotifier(data))],
      child: _Preview(state: state),
    ),
  );
  WidgetsBinding.instance.endOfFrame.then((_) => removeWebSplash());
}

class _Preview extends StatelessWidget {
  const _Preview({required this.state});
  final String state;

  @override
  Widget build(BuildContext context) {
    final forced = double.tryParse(_q('w', ''));

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Consumer(
        builder: (context, ref, _) {
          final page = _Opener(state: state, child: const AdminBackupPage());
          return Scaffold(
            backgroundColor: forced == null ? AdminUi.pageBg : Colors.black12,
            body: SafeArea(
              child: forced == null
                  ? page
                  // A forced width renders the page in a box of exactly that
                  // logical width, so one browser window shows a phone layout.
                  : Center(
                      child: SizedBox(
                        width: forced,
                        child: ColoredBox(color: AdminUi.pageBg, child: page),
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }
}

/// Opens whichever dialog `?state=` asked for, once the page has a frame.
class _Opener extends ConsumerStatefulWidget {
  const _Opener({required this.state, required this.child});
  final String state;
  final Widget child;

  @override
  ConsumerState<_Opener> createState() => _OpenerState();
}

class _OpenerState extends ConsumerState<_Opener> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    if (!mounted) return;
    final backup = _ready.first;

    switch (widget.state) {
      case 'restore':
        await showRestoreFlow(context, ref, backup);
      case 'details':
        await showBackupDetailsSheet(context, backup);
      case 'warnings':
        await showBackupWarningsDialog(context, _warnings);
      case 'create':
        await showCreateBackupDialog(context);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
