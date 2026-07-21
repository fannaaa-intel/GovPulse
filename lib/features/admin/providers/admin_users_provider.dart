import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_activity_provider.dart';
import 'admin_profile_provider.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Admin → Users management data layer
//
//  Backs the "Users" admin nav slot: lists every account (role, deactivation,
//  active restriction/suspension) and exposes the admin actions —
//    • create staff (via the `create-staff` Edge Function; needs service role)
//    • deactivate / reactivate (soft, reversible)
//    • restrict / lift-restriction (feature-level)
//    • suspend / lift-suspension (account-level)
//    • broadcast / targeted notification
//  Restriction/suspension actions AUTO-INSERT a detailed citizen notification
//  (and a "lifted" notice), matching the enforcement contract in
//  supabase/legacy/user_management.sql.
// ════════════════════════════════════════════════════════════════════════════

/// Restrictable features — the exact keys stored in
/// `user_restrictions.restricted_features`, shared by the admin toggles, the
/// citizen-side feature gates, and the DB triggers. Order = display order.
const Map<String, String> kRestrictableFeatures = {
  'newsfeed': 'News feed',
  'reports': 'Reporting',
  'feedback': 'Feedback',
  'suggestions': 'Suggestions',
  'ai_chat': 'AI assistant',
};

String restrictionFeatureLabel(String key) => kRestrictableFeatures[key] ?? key;

enum AppUserRole { admin, staff, citizen }

AppUserRole _roleFromId(int? id) => switch (id) {
  1 => AppUserRole.admin,
  2 => AppUserRole.staff,
  _ => AppUserRole.citizen,
};

String appUserRoleLabel(AppUserRole r) => switch (r) {
  AppUserRole.admin => 'Admin',
  AppUserRole.staff => 'Staff',
  AppUserRole.citizen => 'Citizen',
};

/// Citizen identity-verification standing, derived from the latest
/// `verification_submissions.status`. A rejected submission is distinct from
/// never-having-submitted ("unverified") so the two get their own summary tiles.
enum CitizenVerif { unverified, pending, verified, rejected }

String citizenVerifLabel(CitizenVerif v) => switch (v) {
  CitizenVerif.verified => 'Verified',
  CitizenVerif.pending => 'Pending',
  CitizenVerif.unverified => 'Unverified',
  CitizenVerif.rejected => 'Rejected',
};

CitizenVerif _verifFromStatus(String? s) => switch (s) {
  'approved' => CitizenVerif.verified,
  'pending' => CitizenVerif.pending,
  'rejected' => CitizenVerif.rejected,
  _ => CitizenVerif.unverified,
};

// ── Model ──────────────────────────────────────────────────────────────────

class ManagedUser {
  final String id; // auth uid
  final String? username;
  final String? email;
  final String? firstName;
  final String? lastName;
  final String? photoUrl;
  final String? barangay;
  final AppUserRole role;
  final CitizenVerif verif;

  /// `admin_profiles.department` — the office a staff member speaks for. Only
  /// staff carry one; admins speak for the LGU itself and leave this null.
  final String? department;

  /// When the account was created (`profiles.created_at`). Drives the "Joined"
  /// column and the newest/oldest sort.
  final DateTime? joinedAt;

  final bool isDeactivated;

  /// Active restriction (lifted_at is null and not expired), if any.
  final List<String> restrictedFeatures;
  final String? restrictionReason;
  final DateTime? restrictionExpires;

  /// Active suspension (lifted_at is null and not expired), if any.
  final bool isSuspended;
  final String? suspensionReason;
  final DateTime? suspensionExpires;

  const ManagedUser({
    required this.id,
    required this.username,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.photoUrl,
    required this.barangay,
    required this.role,
    required this.verif,
    required this.department,
    required this.joinedAt,
    required this.isDeactivated,
    required this.restrictedFeatures,
    required this.restrictionReason,
    required this.restrictionExpires,
    required this.isSuspended,
    required this.suspensionReason,
    required this.suspensionExpires,
  });

  bool get isOfficial => role == AppUserRole.admin || role == AppUserRole.staff;
  bool get isRestricted => restrictedFeatures.isNotEmpty;

  String get displayName {
    final n = '${firstName ?? ''} ${lastName ?? ''}'.trim();
    if (n.isNotEmpty) return n;
    return (username?.trim().isNotEmpty ?? false)
        ? username!.trim()
        : (email ?? 'User');
  }

  /// How this account is labelled in the Team roster.
  ///
  /// A staff account acts as its OFFICE, not as the person holding the login —
  /// the same rule `officialDisplayName` enforces everywhere the public can see
  /// (see core/identity/official_display_name.dart). "Rheinz" told an admin
  /// nothing about which office a ticket would land in; "Sanitation Office"
  /// does. Falls back to the person's name when no department is on file, so a
  /// half-provisioned row never renders blank.
  String get teamLabel {
    final dept = department?.trim() ?? '';
    if (role == AppUserRole.staff && dept.isNotEmpty) return dept;
    return displayName;
  }

  String get initials {
    final n = displayName;
    final parts = n
        .split(RegExp(r'[\s@._-]+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'U';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts[1].substring(0, 1))
        .toUpperCase();
  }
}

// ── Notifier ───────────────────────────────────────────────────────────────
//
//  The provider holds the FULL, unfiltered account list. Each page (Citizen
//  Management, Team) filters/sorts locally, so the two pages never fight over a
//  shared filter — and the command palette can search across everyone.

class AdminUsersNotifier extends AsyncNotifier<List<ManagedUser>> {
  SupabaseClient get _db => Supabase.instance.client;
  String? get _adminId => _db.auth.currentUser?.id;

  List<ManagedUser> _all = const [];

  Iterable<ManagedUser> get _citizens =>
      _all.where((u) => u.role == AppUserRole.citizen);
  int get citizenCount => _citizens.length;
  int get staffCount => _all.where((u) => u.role == AppUserRole.staff).length;
  int get adminCount => _all.where((u) => u.role == AppUserRole.admin).length;

  int get verifiedCount =>
      _citizens.where((u) => u.verif == CitizenVerif.verified).length;
  int get pendingVerifCount =>
      _citizens.where((u) => u.verif == CitizenVerif.pending).length;
  int get unverifiedCount =>
      _citizens.where((u) => u.verif == CitizenVerif.unverified).length;
  int get rejectedVerifCount =>
      _citizens.where((u) => u.verif == CitizenVerif.rejected).length;
  int get restrictedCount => _citizens.where((u) => u.isRestricted).length;
  int get suspendedCount => _citizens.where((u) => u.isSuspended).length;

  /// Distinct barangays across citizens, alphabetically — feeds the barangay
  /// filter dropdown on the Citizen Management page.
  List<String> get barangays {
    final set = <String>{
      for (final u in _citizens)
        if ((u.barangay ?? '').trim().isNotEmpty) u.barangay!.trim(),
    };
    final list = set.toList()..sort();
    return list;
  }

  @override
  Future<List<ManagedUser>> build() async {
    _all = await _fetchAll();
    return _all;
  }

  void _publish() => state = AsyncData(_all);

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      _all = await _fetchAll();
      return _all;
    });
  }

  Future<void> _reload() async {
    final next = await AsyncValue.guard(_fetchAll);
    if (next.hasValue) {
      _all = next.value!;
      _publish();
    }
  }

  Future<void> silentRefresh() => _reload();

  // ── Fetch + resolve ─────────────────────────────────────────────────────

  Future<List<ManagedUser>> _fetchAll() async {
    final profiles = await _db
        .from('profiles')
        .select('id, username, email, is_deactivated, created_at')
        .limit(1000);
    final rows = List<Map<String, dynamic>>.from(profiles);
    if (rows.isEmpty) return const [];

    final ids = [for (final r in rows) r['id'] as String];

    // Resolve identity, role and enforcement state in parallel.
    final results = await Future.wait([
      _db
          .from('user_roles')
          .select('user_id, role_id')
          .inFilter('user_id', ids),
      _db
          .from('public_user_profiles')
          .select('user_id, first_name, last_name, profile_photo_path')
          .inFilter('user_id', ids),
      _db
          .from('citizen_details')
          .select('user_id, barangay')
          .inFilter('user_id', ids),
      _db
          .from('user_restrictions')
          .select('user_id, restricted_features, reason, expires_at')
          .inFilter('user_id', ids)
          .isFilter('lifted_at', null),
      _db
          .from('user_suspensions')
          .select('user_id, reason, expires_at')
          .inFilter('user_id', ids)
          .isFilter('lifted_at', null),
      _db
          .from('verification_submissions')
          .select('user_id, status, created_at')
          .inFilter('user_id', ids)
          .order('created_at', ascending: false),
      // Officials (admins + staff) keep their name + avatar in admin_profiles
      // (bucket: admin-avatars), NOT in public_user_profiles. Without this the
      // Team list falls back to username and a blank silhouette.
      _db
          .from('admin_profiles')
          .select('user_id, full_name, organization, photo_url, department')
          .inFilter('user_id', ids),
    ]);

    final roles = <String, int>{
      for (final r in List<Map<String, dynamic>>.from(results[0]))
        r['user_id'] as String: (r['role_id'] as int?) ?? 0,
    };
    final names = <String, Map<String, dynamic>>{
      for (final r in List<Map<String, dynamic>>.from(results[1]))
        r['user_id'] as String: r,
    };
    final barangays = <String, String?>{
      for (final r in List<Map<String, dynamic>>.from(results[2]))
        r['user_id'] as String: r['barangay'] as String?,
    };
    final now = DateTime.now();
    final restrictions = <String, Map<String, dynamic>>{};
    for (final r in List<Map<String, dynamic>>.from(results[3])) {
      final exp = _parseTs(r['expires_at']);
      if (exp != null && exp.isBefore(now)) continue; // expired → not active
      restrictions[r['user_id'] as String] = r;
    }
    final suspensions = <String, Map<String, dynamic>>{};
    for (final r in List<Map<String, dynamic>>.from(results[4])) {
      final exp = _parseTs(r['expires_at']);
      if (exp != null && exp.isBefore(now)) continue;
      suspensions[r['user_id'] as String] = r;
    }
    // Rows are newest-first, so the first status seen per user is the latest.
    final verifs = <String, String>{};
    for (final r in List<Map<String, dynamic>>.from(results[5])) {
      verifs.putIfAbsent(
        r['user_id'] as String,
        () => r['status'] as String? ?? '',
      );
    }
    // Official identity (admins + staff), keyed by user_id.
    final officials = <String, Map<String, dynamic>>{
      for (final r in List<Map<String, dynamic>>.from(results[6]))
        r['user_id'] as String: r,
    };

    return rows.map((p) {
      final id = p['id'] as String;
      final nameRow = names[id];
      final official = officials[id];

      // Officials store name + avatar in admin_profiles (photo_url is already a
      // full public URL); citizens use public_user_profiles + the profile-photos
      // bucket. Resolve name/photo from whichever applies.
      String? firstName = nameRow?['first_name'] as String?;
      String? lastName = nameRow?['last_name'] as String?;
      String? photoUrl;
      // Officials show their admin_profiles name; a staff member has a full_name,
      // while an admin may only carry the organization ("LGU Aparri") — fall back
      // to that so the row never degrades to a bare username.
      final officialName = (official?['full_name'] as String?)?.trim();
      final officialOrg = (official?['organization'] as String?)?.trim();
      final resolvedOfficial = (officialName != null && officialName.isNotEmpty)
          ? officialName
          : (officialOrg != null && officialOrg.isNotEmpty
                ? officialOrg
                : null);
      if (resolvedOfficial != null) {
        firstName =
            resolvedOfficial; // single field → displayName uses it as-is
        lastName = null;
      }
      final officialPhoto = (official?['photo_url'] as String?)?.trim();
      if (officialPhoto != null && officialPhoto.isNotEmpty) {
        photoUrl = officialPhoto;
      } else {
        final photoPath = nameRow?['profile_photo_path'] as String?;
        if (photoPath != null && photoPath.isNotEmpty) {
          photoUrl = _db.storage.from('profile-photos').getPublicUrl(photoPath);
        }
      }
      final restr = restrictions[id];
      final susp = suspensions[id];
      return ManagedUser(
        id: id,
        username: p['username'] as String?,
        email: p['email'] as String?,
        firstName: firstName,
        lastName: lastName,
        photoUrl: photoUrl,
        barangay: barangays[id],
        role: _roleFromId(roles[id]),
        verif: _verifFromStatus(verifs[id]),
        department: (official?['department'] as String?)?.trim(),
        joinedAt: _parseTs(p['created_at']),
        isDeactivated: (p['is_deactivated'] as bool?) ?? false,
        restrictedFeatures: restr == null
            ? const []
            : List<String>.from(
                (restr['restricted_features'] as List?) ?? const [],
              ),
        restrictionReason: restr?['reason'] as String?,
        restrictionExpires: _parseTs(restr?['expires_at']),
        isSuspended: susp != null,
        suspensionReason: susp?['reason'] as String?,
        suspensionExpires: _parseTs(susp?['expires_at']),
      );
    }).toList();
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  /// Create a staff account via the admin-only Edge Function. Throws its
  /// message on failure.
  Future<void> createStaff({
    required String email,
    required String password,
    required String username,
    required String fullName,
    required String department,
    bool isExternal = false,
  }) async {
    final res = await _db.functions.invoke(
      'create-staff',
      body: {
        'email': email,
        'password': password,
        'username': username,
        'fullName': fullName,
        'department': department,
        'isExternal': isExternal,
      },
    );
    final data = res.data;
    final ok = data is Map && data['success'] == true;
    if (!ok) {
      final msg = data is Map ? data['message'] as String? : null;
      throw msg ?? 'Could not create staff account.';
    }
    await _log(
      'staff_created',
      targetType: 'staff',
      targetLabel: fullName.trim().isNotEmpty ? fullName.trim() : email.trim(),
    );
    await _reload();
  }

  /// Soft-deactivate or reactivate an account (blocks login while off). When
  /// deactivating, optionally notify the user with the [reason] and end date.
  Future<void> setDeactivated(
    ManagedUser user,
    bool deactivated, {
    String? reason,
    DateTime? expiresAt,
    bool notify = true,
  }) async {
    await _db
        .from('profiles')
        .update({
          'is_deactivated': deactivated,
          'deactivated_at': deactivated
              ? DateTime.now().toUtc().toIso8601String()
              : null,
          'deactivated_by': deactivated ? _adminId : null,
        })
        .eq('id', user.id);

    if (notify) {
      if (deactivated) {
        await _notify(
          user.id,
          'Your account has been deactivated',
          '${reason != null && reason.trim().isNotEmpty ? '${reason.trim()}. ' : ''}'
              '${expiresAt != null ? 'In effect ${_untilText(expiresAt)}. ' : ''}'
              'Contact the LGU to restore access.',
          color: 0xFFEF4444,
        );
      } else {
        await _notify(
          user.id,
          'Your account has been reactivated',
          'You can sign in and use GovPulse again.',
          color: 0xFF22C55E,
        );
      }
    }
    await _log(
      deactivated ? 'user_deactivated' : 'user_reactivated',
      targetType: 'user',
      targetLabel: user.displayName,
      detail: reason,
    );
    await _reload();
  }

  /// Restrict [features] for a citizen, with an optional [reason]/[expiresAt],
  /// and (when [notify]) notify them with the specifics.
  Future<void> restrict(
    ManagedUser user, {
    required List<String> features,
    String? reason,
    DateTime? expiresAt,
    bool notify = true,
  }) async {
    // Lift any prior active restriction first, so there's one active row.
    await _db
        .from('user_restrictions')
        .update({
          'lifted_at': DateTime.now().toUtc().toIso8601String(),
          'lifted_by': _adminId,
        })
        .eq('user_id', user.id)
        .isFilter('lifted_at', null);

    await _db.from('user_restrictions').insert({
      'user_id': user.id,
      'restricted_features': features,
      'reason': reason,
      'restricted_by': _adminId,
      'expires_at': expiresAt?.toUtc().toIso8601String(),
    });

    if (notify) {
      final labels = features.map(restrictionFeatureLabel).join(', ');
      await _notify(
        user.id,
        'Your account has been restricted',
        'Access limited to: $labels. '
            '${reason != null && reason.trim().isNotEmpty ? 'Reason: ${reason.trim()}. ' : ''}'
            'In effect ${_untilText(expiresAt)}.',
        color: 0xFFEF4444,
      );
    }
    await _log(
      'user_restricted',
      targetType: 'user',
      targetLabel: user.displayName,
      detail: features.map(restrictionFeatureLabel).join(', '),
    );
    await _reload();
  }

  Future<void> liftRestriction(ManagedUser user) async {
    await _db
        .from('user_restrictions')
        .update({
          'lifted_at': DateTime.now().toUtc().toIso8601String(),
          'lifted_by': _adminId,
        })
        .eq('user_id', user.id)
        .isFilter('lifted_at', null);

    final labels = user.restrictedFeatures
        .map(restrictionFeatureLabel)
        .join(', ');
    await _notify(
      user.id,
      'Restriction lifted',
      labels.isEmpty
          ? 'Your account restrictions have been removed.'
          : 'Your access to $labels has been restored.',
      color: 0xFF22C55E,
    );
    await _log(
      'restriction_lifted',
      targetType: 'user',
      targetLabel: user.displayName,
    );
    await _reload();
  }

  Future<void> suspend(
    ManagedUser user, {
    String? reason,
    DateTime? expiresAt,
    bool notify = true,
  }) async {
    await _db
        .from('user_suspensions')
        .update({
          'lifted_at': DateTime.now().toUtc().toIso8601String(),
          'lifted_by': _adminId,
        })
        .eq('user_id', user.id)
        .isFilter('lifted_at', null);

    await _db.from('user_suspensions').insert({
      'user_id': user.id,
      'reason': reason,
      'suspended_by': _adminId,
      'expires_at': expiresAt?.toUtc().toIso8601String(),
    });

    if (notify) {
      await _notify(
        user.id,
        'Your account has been suspended',
        '${reason != null && reason.trim().isNotEmpty ? '${reason.trim()}. ' : ''}'
            'In effect ${_untilText(expiresAt)}. You have been signed out.',
        color: 0xFFEF4444,
      );
    }
    await _log(
      'user_suspended',
      targetType: 'user',
      targetLabel: user.displayName,
      detail: reason,
    );
    await _reload();
  }

  Future<void> liftSuspension(ManagedUser user) async {
    await _db
        .from('user_suspensions')
        .update({
          'lifted_at': DateTime.now().toUtc().toIso8601String(),
          'lifted_by': _adminId,
        })
        .eq('user_id', user.id)
        .isFilter('lifted_at', null);

    await _notify(
      user.id,
      'Suspension lifted',
      'Your account has been reactivated. You can sign in again.',
      color: 0xFF22C55E,
    );
    await _log(
      'suspension_lifted',
      targetType: 'user',
      targetLabel: user.displayName,
    );
    await _reload();
  }

  /// Broadcast one message to every citizen (server-side fan-out).
  /// Returns how many recipients it reached.
  Future<int> broadcast({
    required String title,
    required String subtitle,
  }) async {
    // p_color is passed explicitly (it's the function's own default blue) so the
    // RPC binds unambiguously to broadcast_notification(text, text, bigint).
    //
    // This was load-bearing until 2026-07-16: a stale 6-arg overload made the
    // call ambiguous (PostgREST PGRST203), and fix_broadcast_overload.sql had
    // failed to remove it — it dropped the wrong signature, and `IF EXISTS`
    // can't tell "already gone" from "never matched", so it reported success and
    // did nothing. The overload is now genuinely dropped, leaving this argument
    // as belt-and-braces rather than the thing holding the call together.
    final res = await _db.rpc(
      'broadcast_notification',
      params: {
        'p_title': title,
        'p_subtitle': subtitle,
        'p_color': 4283980779, // 0xFF2563EB
      },
    );
    final count = res is int ? res : int.tryParse('$res') ?? 0;
    await _log(
      'broadcast_sent',
      targetType: 'broadcast',
      targetLabel: title,
      detail: 'Reached $count citizen${count == 1 ? '' : 's'}',
    );
    return count;
  }

  /// Send a one-off notification to a single user.
  Future<void> sendToUser(
    ManagedUser user, {
    required String title,
    required String subtitle,
  }) async {
    await _notify(user.id, title, subtitle);
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  /// Append one row to the admin activity log, attributed to the current admin.
  /// Best-effort: a logging failure must never block the action it records, so
  /// this swallows errors. Refreshes the activity provider so Settings updates.
  Future<void> _log(
    String action, {
    String? targetType,
    String? targetLabel,
    String? detail,
  }) async {
    try {
      await _db.from('admin_activity_log').insert({
        'actor_id': _adminId,
        'actor_name': ref.read(adminProfileProvider).valueOrNull?.displayName,
        'action': action,
        'target_type': targetType,
        'target_label': targetLabel,
        'detail': detail,
      });
      ref.read(adminActivityProvider.notifier).silentRefresh();
    } catch (_) {
      // Activity logging is non-critical; ignore (e.g. table not yet created).
    }
  }

  Future<void> _notify(
    String userId,
    String title,
    String subtitle, {
    int color = 0xFF2563EB,
  }) async {
    // Carry the acting admin as the notification's actor so the citizen's bell
    // renders the admin's profile photo instead of a generic icon — matching
    // the suggestion / feedback responses.
    final actorPhotoUrl = await _fetchAdminPhotoUrl();
    await _db.from('notifications').insert({
      'user_id': userId,
      'title': title,
      'subtitle': subtitle,
      'type': 'general',
      'color_value': color,
      'icon_code': 0,
      'is_approved': true,
      'sent_by': _adminId,
      'actor_id': _adminId,
      'actor_photo_url': actorPhotoUrl,
    });
  }

  /// The acting admin's avatar URL from `admin_profiles.photo_url`, used to
  /// personalise citizen notifications. Best-effort — a missing profile or read
  /// error just falls back to null (generic icon).
  Future<String?> _fetchAdminPhotoUrl() async {
    final id = _adminId;
    if (id == null) return null;
    try {
      final row = await _db
          .from('admin_profiles')
          .select('photo_url')
          .eq('user_id', id)
          .maybeSingle();
      final url = (row?['photo_url'] as String?)?.trim();
      return (url != null && url.isNotEmpty) ? url : null;
    } catch (_) {
      return null;
    }
  }

  static String _untilText(DateTime? expires) {
    if (expires == null) return 'until further notice';
    final d = expires.toLocal();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return 'until ${d.day} ${months[d.month - 1]} ${d.year}';
  }

  static DateTime? _parseTs(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v.toLocal();
    if (v is String) return DateTime.tryParse(v)?.toLocal();
    return null;
  }
}

final adminUsersProvider =
    AsyncNotifierProvider<AdminUsersNotifier, List<ManagedUser>>(
      AdminUsersNotifier.new,
    );

/// A one-shot search seed for the Citizen Management page. The Spam-watch review
/// sets this (e.g. "Manage user") and the page consumes it to pre-fill its
/// search box, then clears it back to ''.
final manageUserQueryProvider = StateProvider<String>((_) => '');
