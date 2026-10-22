import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Admin → Backup & Recovery
//
//  Every operation goes through the `admin-backup` edge function. Nothing here
//  reads or writes the data tables directly, and that is deliberate:
//
//   • The restore runs as `service_role` inside `admin_apply_restore`, which
//     `authenticated` is not granted EXECUTE on. A client-side restore is not
//     merely discouraged, it is impossible.
//   • A client write would also be WRONG even if it were permitted: the pin
//     triggers (pin_citizen_report_columns and friends) fire for
//     `authenticated` and would null out `ai_classified_at`, `status`,
//     assignment and endorsement on every restored report — so the restored
//     data would be quietly damaged, and the */15 catch-up jobs would re-send
//     it all to Groq.
//   • Audit rows are written server-side, so a restore cannot be performed
//     without being recorded.
//
//  The `backups` and `backup_restores` tables are readable by admins via RLS,
//  but the list still comes from the function so creator names, the restore
//  history and the warnings arrive in one round trip.
// ════════════════════════════════════════════════════════════════════════════

/// How a restore treats rows that already exist.
enum RestoreMode {
  /// Insert rows whose primary key is missing. Nothing existing is touched.
  missingOnly,

  /// Also update existing rows back to their backed-up values.
  missingAndChanged;

  String get wire => this == RestoreMode.missingOnly
      ? 'missing_only'
      : 'missing_and_changed';
}

/// Where a backup came from.
enum BackupKind {
  manual,
  preRestore,
  automatic;

  static BackupKind parse(String? raw) => switch (raw) {
    'pre_restore' => BackupKind.preRestore,
    'automatic' => BackupKind.automatic,
    _ => BackupKind.manual,
  };

  String get label => switch (this) {
    BackupKind.manual => 'Manual',
    BackupKind.preRestore => 'Safety copy',
    BackupKind.automatic => 'Automatic',
  };
}

class BackupEntry {
  final String id;
  final String name;
  final String? label;
  final BackupKind kind;
  final String createdByName;
  final DateTime createdAt;
  final int sizeBytes;
  final int totalRecords;

  /// `{"reports": 13, "profiles": 9, …}` — per-table row counts.
  final Map<String, int> tableCounts;
  final String? schemaVersion;
  final String? checksum;
  final String status; // 'creating' | 'ready' | 'failed'
  final String? error;

  const BackupEntry({
    required this.id,
    required this.name,
    required this.label,
    required this.kind,
    required this.createdByName,
    required this.createdAt,
    required this.sizeBytes,
    required this.totalRecords,
    required this.tableCounts,
    required this.schemaVersion,
    required this.checksum,
    required this.status,
    required this.error,
  });

  bool get isReady => status == 'ready';
  bool get isFailed => status == 'failed';

  /// What the admin sees as the backup's name: their label if they gave one.
  String get displayTitle => (label?.trim().isNotEmpty ?? false) ? label!.trim() : name;

  /// First 12 characters — enough to compare two backups by eye.
  String get shortChecksum =>
      checksum == null ? '—' : checksum!.substring(0, checksum!.length.clamp(0, 12));

  static BackupEntry fromJson(Map<String, dynamic> j) {
    final counts = <String, int>{};
    final raw = j['table_counts'];
    if (raw is Map) {
      for (final e in raw.entries) {
        final v = e.value;
        if (v is num) counts[e.key.toString()] = v.toInt();
      }
    }
    return BackupEntry(
      id: j['id'] as String,
      name: (j['name'] as String?) ?? 'backup',
      label: j['label'] as String?,
      kind: BackupKind.parse(j['kind'] as String?),
      createdByName: (j['created_by_name'] as String?) ?? 'An administrator',
      createdAt:
          DateTime.tryParse(j['created_at']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
      sizeBytes: (j['size_bytes'] as num?)?.toInt() ?? 0,
      totalRecords: (j['total_records'] as num?)?.toInt() ?? 0,
      tableCounts: counts,
      schemaVersion: j['schema_version'] as String?,
      checksum: j['checksum'] as String?,
      status: (j['status'] as String?) ?? 'ready',
      error: j['error'] as String?,
    );
  }
}

class RestoreHistoryEntry {
  final String id;
  final String? backupName;
  final RestoreMode mode;
  final String startedByName;
  final DateTime startedAt;
  final String status; // 'running' | 'completed' | 'failed'
  final String? safetyBackupName;
  final String? error;

  /// Per-table outcome: added / updated / unchanged / skipped.
  final Map<String, RestoreTableResult> result;

  const RestoreHistoryEntry({
    required this.id,
    required this.backupName,
    required this.mode,
    required this.startedByName,
    required this.startedAt,
    required this.status,
    required this.safetyBackupName,
    required this.error,
    required this.result,
  });

  bool get succeeded => status == 'completed';

  int get totalAdded => result.values.fold(0, (s, r) => s + r.added);
  int get totalUpdated => result.values.fold(0, (s, r) => s + r.updated);

  static RestoreHistoryEntry fromJson(Map<String, dynamic> j) => RestoreHistoryEntry(
    id: j['id'] as String,
    backupName: j['backup_name'] as String?,
    mode: j['mode'] == 'missing_and_changed'
        ? RestoreMode.missingAndChanged
        : RestoreMode.missingOnly,
    startedByName: (j['started_by_name'] as String?) ?? 'An administrator',
    startedAt:
        DateTime.tryParse(j['started_at']?.toString() ?? '')?.toLocal() ??
        DateTime.now(),
    status: (j['status'] as String?) ?? 'completed',
    safetyBackupName: j['safety_backup_name'] as String?,
    error: j['error'] as String?,
    result: RestoreTableResult.parseMap(j['result']),
  );
}

/// One table's outcome in a preview or a finished restore.
class RestoreTableResult {
  final int added;
  final int updated;
  final int unchanged;
  final int skippedMissingUser;
  final int skippedTooOld;

  const RestoreTableResult({
    this.added = 0,
    this.updated = 0,
    this.unchanged = 0,
    this.skippedMissingUser = 0,
    this.skippedTooOld = 0,
  });

  int get skipped => skippedMissingUser + skippedTooOld;

  /// True when this table would not change at all — used to keep the preview
  /// focused on what actually differs.
  bool get isNoChange => added == 0 && updated == 0;

  static RestoreTableResult fromJson(Map<String, dynamic> j) => RestoreTableResult(
    added: (j['added'] as num?)?.toInt() ?? 0,
    updated: (j['updated'] as num?)?.toInt() ?? 0,
    unchanged: (j['unchanged'] as num?)?.toInt() ?? 0,
    skippedMissingUser: (j['skipped_missing_user'] as num?)?.toInt() ?? 0,
    skippedTooOld: (j['skipped_too_old'] as num?)?.toInt() ?? 0,
  );

  static Map<String, RestoreTableResult> parseMap(dynamic raw) {
    final out = <String, RestoreTableResult>{};
    if (raw is Map) {
      for (final e in raw.entries) {
        if (e.value is Map) {
          out[e.key.toString()] =
              fromJson(Map<String, dynamic>.from(e.value as Map));
        }
      }
    }
    return out;
  }
}

/// A dry run's answer: what a restore would do, and what to warn about.
class RestorePreview {
  final Map<String, RestoreTableResult> tables;
  final List<String> warnings;

  const RestorePreview({required this.tables, required this.warnings});

  int get totalAdded => tables.values.fold(0, (s, r) => s + r.added);
  int get totalUpdated => tables.values.fold(0, (s, r) => s + r.updated);
  int get totalUnchanged => tables.values.fold(0, (s, r) => s + r.unchanged);
  int get totalSkipped => tables.values.fold(0, (s, r) => s + r.skipped);

  /// Nothing to do — the live data already matches this backup.
  bool get isNoOp => totalAdded == 0 && totalUpdated == 0;

  /// Only the tables that would change, most-affected first.
  List<(String, RestoreTableResult)> get changedTables {
    final rows = tables.entries
        .where((e) => !e.value.isNoChange)
        .map((e) => (e.key, e.value))
        .toList();
    rows.sort((a, b) =>
        (b.$2.added + b.$2.updated).compareTo(a.$2.added + a.$2.updated));
    return rows;
  }
}

/// What a finished restore did.
class RestoreOutcome {
  final Map<String, RestoreTableResult> tables;
  final List<String> warnings;
  final String? safetyBackupName;

  const RestoreOutcome({
    required this.tables,
    required this.warnings,
    required this.safetyBackupName,
  });

  int get totalAdded => tables.values.fold(0, (s, r) => s + r.added);
  int get totalUpdated => tables.values.fold(0, (s, r) => s + r.updated);
  int get totalSkipped => tables.values.fold(0, (s, r) => s + r.skipped);

  List<(String, RestoreTableResult)> get changedTables {
    final rows = tables.entries
        .where((e) => !e.value.isNoChange)
        .map((e) => (e.key, e.value))
        .toList();
    rows.sort((a, b) =>
        (b.$2.added + b.$2.updated).compareTo(a.$2.added + a.$2.updated));
    return rows;
  }
}

/// A backup plus the recent restore history — one fetch, one card to render.
class BackupState {
  final List<BackupEntry> backups;
  final List<RestoreHistoryEntry> restores;

  const BackupState({required this.backups, required this.restores});

  BackupEntry? get latestReady =>
      backups.where((b) => b.isReady).firstOrNull;

  /// True when there is no successful backup from the last 7 days — the
  /// amber-warning condition on the status card.
  bool get isStale {
    final latest = latestReady;
    if (latest == null) return true;
    return DateTime.now().difference(latest.createdAt) > const Duration(days: 7);
  }
}

/// Raised with a message already written for an admin to read.
class BackupException implements Exception {
  final String message;
  final String code;
  const BackupException(this.message, {this.code = 'error'});

  /// True when the admin typed the wrong password — the dialog keeps the field
  /// open for another try rather than closing.
  bool get isBadPassword => code == 'bad_password';
  bool get isLockedOut => code == 'locked';

  @override
  String toString() => message;
}

class AdminBackupNotifier extends AsyncNotifier<BackupState> {
  SupabaseClient get _db => Supabase.instance.client;

  @override
  Future<BackupState> build() => _fetch();

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_fetch);
  }

  /// Re-fetch without flashing a skeleton — after a create or a delete, the
  /// list is already on screen and should simply update in place.
  ///
  /// Swallows failures on purpose: the refresh is cosmetic, the action it
  /// follows has already succeeded or thrown on its own, and replacing a good
  /// list with an error card because a follow-up fetch blipped would misreport
  /// what happened.
  Future<void> silentRefresh() async {
    try {
      state = AsyncValue.data(await _fetch());
    } catch (_) {
      // Keep the last good list on screen.
    }
  }

  Future<BackupState> _fetch() async {
    final res = await _invoke('list');
    final backups = (res['backups'] as List? ?? [])
        .whereType<Map>()
        .map((m) => BackupEntry.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    final restores = (res['restores'] as List? ?? [])
        .whereType<Map>()
        .map((m) => RestoreHistoryEntry.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    return BackupState(backups: backups, restores: restores);
  }

  /// Create a backup. Returns the new entry plus any coverage warnings.
  Future<({BackupEntry backup, List<String> warnings})> createBackup({
    String? label,
  }) async {
    final res = await _invoke('create', {
      if (label != null && label.trim().isNotEmpty) 'label': label.trim(),
    });
    final entry = BackupEntry.fromJson(
      Map<String, dynamic>.from(res['backup'] as Map),
    );
    await silentRefresh();
    return (
      backup: entry,
      warnings: (res['warnings'] as List? ?? []).map((w) => w.toString()).toList(),
    );
  }

  /// A signed URL valid for 60 seconds, plus the filename to save as.
  ///
  /// Short-lived on purpose: the link is a bearer token for a file containing
  /// citizen personal data. The caller must open it promptly — see the download
  /// handling in the page, which keeps the open inside the user's own tap so
  /// Safari does not treat it as a pop-up.
  Future<({String url, String filename})> downloadUrl(String id) async {
    final res = await _invoke('download', {'id': id});
    return (
      url: res['url'] as String,
      filename: (res['filename'] as String?) ?? 'govpulse-backup.gpbak',
    );
  }

  Future<void> deleteBackup(String id) async {
    await _invoke('delete', {'id': id});
    await silentRefresh();
  }

  /// Dry run: what a restore WOULD do. Writes nothing.
  Future<RestorePreview> preview(String id, RestoreMode mode) async {
    final res = await _invoke('restore_preview', {'id': id, 'mode': mode.wire});
    return RestorePreview(
      tables: RestoreTableResult.parseMap(res['preview']),
      warnings: (res['warnings'] as List? ?? []).map((w) => w.toString()).toList(),
    );
  }

  /// Perform the restore. Takes a safety copy first, server-side.
  Future<RestoreOutcome> apply({
    required String id,
    required RestoreMode mode,
    required String password,
  }) async {
    final res = await _invoke('restore_apply', {
      'id': id,
      'mode': mode.wire,
      // The server requires this exact word; the dialog will not enable its
      // button without it, and the server checks again rather than trusting us.
      'confirm': 'RESTORE',
      'password': password,
    });
    await silentRefresh();
    final safety = res['safety_backup'];
    return RestoreOutcome(
      tables: RestoreTableResult.parseMap(res['result']),
      warnings: (res['warnings'] as List? ?? []).map((w) => w.toString()).toList(),
      safetyBackupName:
          safety is Map ? safety['name'] as String? : null,
    );
  }

  /// Call the edge function and unwrap its envelope.
  ///
  /// The function answers `{success: false, code, message}` with a non-2xx
  /// status for every refusal, and those messages are already written for an
  /// admin to read — so they are passed through rather than replaced with
  /// something vaguer. Only a genuinely unexpected failure gets a generic line.
  Future<Map<String, dynamic>> _invoke(
    String action, [
    Map<String, dynamic> extra = const {},
  ]) async {
    try {
      final res = await _db.functions.invoke(
        'admin-backup',
        body: {
          'action': action,
          // Carried so the audit row names the admin, matching how
          // reveal-identity records its actor.
          'actorName': _db.auth.currentUser?.userMetadata?['full_name'],
          ...extra,
        },
      );
      final data = res.data;
      if (data is Map && data['success'] == true) {
        return Map<String, dynamic>.from(data);
      }
      throw BackupException(
        _messageFrom(data) ?? 'Something went wrong. Please try again.',
        code: (data is Map ? data['code'] as String? : null) ?? 'error',
      );
    } on FunctionException catch (e) {
      // Non-2xx: the body still carries the function's own message.
      final details = e.details;
      throw BackupException(
        _messageFrom(details) ?? _statusMessage(e.status),
        code: (details is Map ? details['code'] as String? : null) ?? 'error',
      );
    } on BackupException {
      rethrow;
    } catch (_) {
      throw const BackupException(
        'Could not reach the server. Check your connection and try again.',
        code: 'network',
      );
    }
  }

  String? _messageFrom(dynamic body) {
    if (body is Map) {
      final m = body['message'];
      if (m is String && m.trim().isNotEmpty) return m;
    }
    return null;
  }

  String _statusMessage(int? status) => switch (status) {
    401 || 403 => 'You do not have permission to do this.',
    // Deliberately vaguer than the server's own 409 text. Only the function
    // knows WHICH conflict happened — another job holding the claim, or a
    // restore already running from this backup — and it always sends a message
    // saying so. This line is the fallback for a 409 whose body did not parse,
    // so it must not assert a cause it cannot know.
    409 => 'That conflicts with something else happening right now. Please try again in a minute.',
    429 => 'Too many attempts. Please wait a few minutes.',
    503 => 'The server is busy. Please try again in a moment.',
    504 => 'That took too long and was stopped. Nothing was changed.',
    _ => 'Something went wrong. Please try again.',
  };
}

final adminBackupProvider =
    AsyncNotifierProvider<AdminBackupNotifier, BackupState>(
  AdminBackupNotifier.new,
);

/// Human-readable byte size. Backups here are tens of kilobytes, so KB/MB is
/// as far as this needs to go.
String formatBackupSize(int bytes) {
  if (bytes <= 0) return '—';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
