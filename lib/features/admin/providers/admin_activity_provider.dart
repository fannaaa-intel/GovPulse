import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Admin activity log — read side
//
//  Backs Settings → Activity log. Rows are written by AdminUsersNotifier._log()
//  after each management action, into public.admin_activity_log (see
//  supabase/legacy/admin_activity_log.sql). This provider only reads the recent tail.
// ════════════════════════════════════════════════════════════════════════════

class AdminActivity {
  final String id;
  final String action; // machine key, e.g. 'user_suspended'
  final String? actorName;
  final String? targetLabel;
  final String? detail;
  final DateTime createdAt;

  const AdminActivity({
    required this.id,
    required this.action,
    required this.actorName,
    required this.targetLabel,
    required this.detail,
    required this.createdAt,
  });

  factory AdminActivity.fromRow(Map<String, dynamic> r) => AdminActivity(
    id: r['id'] as String,
    action: (r['action'] as String?) ?? 'unknown',
    actorName: r['actor_name'] as String?,
    targetLabel: r['target_label'] as String?,
    detail: r['detail'] as String?,
    createdAt:
        DateTime.tryParse((r['created_at'] as String?) ?? '')?.toLocal() ??
        DateTime.now(),
  );

  /// Human-readable summary of what happened, e.g. "Suspended Juan Dela Cruz".
  String get title {
    final verb = switch (action) {
      'staff_created' => 'Created staff account',
      'user_suspended' => 'Suspended',
      'suspension_lifted' => 'Lifted suspension for',
      'user_restricted' => 'Restricted',
      'restriction_lifted' => 'Lifted restriction for',
      'user_deactivated' => 'Deactivated',
      'user_reactivated' => 'Reactivated',
      'broadcast_sent' => 'Broadcast to citizens',
      'identity_revealed' => 'Revealed anonymous identity —',
      _ => action.replaceAll('_', ' '),
    };
    final target = targetLabel;
    if (target == null || target.isEmpty) return verb;
    return '$verb $target';
  }

  String get timeAgo {
    final d = DateTime.now().difference(createdAt);
    if (d.inSeconds < 60) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} hr ago';
    if (d.inDays < 7) return '${d.inDays} d ago';
    return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
  }

  /// Exact date + time, e.g. "Jul 8, 2026 · 11:07 AM" — shown in the full
  /// "View all" history where precise timestamps matter.
  String get exactTime => DateFormat('MMM d, y · h:mm a').format(createdAt);

  /// Calendar day, e.g. "Jul 8, 2026" — used to group the history list.
  String get dayLabel => DateFormat('MMM d, y').format(createdAt);

  /// Clock time only, e.g. "11:07 AM". The history groups by day already, so
  /// repeating the date on every row inside a day is noise.
  String get timeOnly => DateFormat('h:mm a').format(createdAt);
}

class AdminActivityNotifier extends AsyncNotifier<List<AdminActivity>> {
  SupabaseClient get _db => Supabase.instance.client;

  @override
  Future<List<AdminActivity>> build() => _fetch();

  Future<List<AdminActivity>> _fetch() async {
    final rows = await _db
        .from('admin_activity_log')
        .select('id, action, actor_name, target_label, detail, created_at')
        .order('created_at', ascending: false)
        .limit(100);
    return (rows as List)
        .map((r) => AdminActivity.fromRow(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  Future<void> silentRefresh() async {
    final next = await AsyncValue.guard(_fetch);
    if (next.hasValue) state = next;
  }

  /// Reads the log for the "View all" history screen, optionally bounded by a
  /// created_at range. Independent of [state] — the screen owns its own list so
  /// it can apply date filters without disturbing the Settings card.
  Future<List<AdminActivity>> fetchHistory({
    DateTime? from,
    DateTime? to,
    int limit = 1000,
  }) async {
    var query = _db
        .from('admin_activity_log')
        .select('id, action, actor_name, target_label, detail, created_at');
    if (from != null) {
      query = query.gte('created_at', from.toUtc().toIso8601String());
    }
    if (to != null) {
      query = query.lt('created_at', to.toUtc().toIso8601String());
    }
    final rows = await query.order('created_at', ascending: false).limit(limit);
    return (rows as List)
        .map((r) => AdminActivity.fromRow(r as Map<String, dynamic>))
        .toList();
  }
}

final adminActivityProvider =
    AsyncNotifierProvider<AdminActivityNotifier, List<AdminActivity>>(
      AdminActivityNotifier.new,
    );
