import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Locally-cached identity of the last signed-in account, so a cold start can
/// pick a destination WITHOUT the network.
///
/// ── Why this exists ────────────────────────────────────────────────────────
/// `supabase_flutter` already persists the session itself, so
/// `auth.currentUser` survives a restart offline. What did NOT survive is
/// everything the splash needs in order to route: the username and the role
/// both came from `profiles` / `user_roles` queries, which hang or throw with
/// no connection. So the splash could know a user was signed in and still be
/// unable to say where to send them.
///
/// This stores those two answers next to the session that proved them. On a
/// cold start the splash reads them synchronously-ish (one SharedPreferences
/// load, no socket) and routes immediately; the real queries still run once the
/// destination is on screen and correct anything stale.
///
/// MOBILE ONLY. Web resolves the same problem through the router guard and
/// [AuthRestoration]'s own role cache; [kIsWeb] is a `const bool`, so every
/// method here folds to a no-op there rather than writing a second, competing
/// copy of the same hints.
///
/// NEVER the source of truth. It decides which SCREEN opens, nothing more.
/// Every query behind that screen is still checked server-side against the
/// user's real `user_roles` row, so a stale 'staff' hint yields an empty staff
/// console, never staff data.
class SessionCache {
  SessionCache._();
  static final SessionCache instance = SessionCache._();

  // Keyed by uid so one account's cached role can never be applied to the
  // next account on a shared device — a mismatch reads as a plain miss.
  static const String _kUidKey = 'session_cache_uid';
  static const String _kUsernameKey = 'session_cache_username';
  static const String _kRoleKey = 'session_cache_role';

  // ── Profile hints ────────────────────────────────────────────────────────
  //
  // The verification status and display identity, cached for the SAME reason
  // as the role: they come from queries (`verification_submissions`,
  // `citizen_details`) that fail offline, and the failure was indistinguishable
  // from a real answer. `userProfileProvider` falls back to
  // `VerifStatus.none` — literally "unverified" — so a verified citizen
  // starting offline was shown an unverified account with no name and no
  // photo, and nothing re-fetched when the network came back.
  //
  // These let that provider seed itself from the last KNOWN-GOOD answer
  // instead of from a default that happens to be a real state.
  //
  // Applies to every role, not just citizens: an admin or staff member has a
  // display name and photo on the same screens, and loses them the same way.
  // ── Staff identity hints ─────────────────────────────────────────────────
  //
  // Same problem, same shape as the profile hints above: a staff member on a
  // weak connection got a generic 'S' avatar and the name 'Staff' instead of
  // their own, because a failed identity fetch falls through to those
  // fallbacks.
  //
  // ── isOnline is DELIBERATELY NOT STORED ──────────────────────────────────
  // The on-duty switch is LIVE state, not identity, and it has a consequence:
  // `findAvailableStaffId` routes a citizen's live-agent request to whoever is
  // marked online. A cached 'true' would let a staff member open the app
  // showing on-duty from a previous session while the server has them off —
  // and a real citizen would be routed to someone who is not there.
  //
  // So it is never written and never restored. A staff member turns it on
  // themselves, which is the only signal that actually means "I am here".
  // There is a test asserting this stays true.
  static const String _kStaffNameKey = 'session_cache_staff_name';
  static const String _kStaffEmailKey = 'session_cache_staff_email';
  static const String _kStaffTitleKey = 'session_cache_staff_title';
  static const String _kStaffDeptKey = 'session_cache_staff_dept';
  static const String _kStaffPhotoKey = 'session_cache_staff_photo';
  static const String _kStaffExternalKey = 'session_cache_staff_external';

  static const String _kVerifKey = 'session_cache_verif';
  static const String _kFullNameKey = 'session_cache_fullname';
  static const String _kPhotoUrlKey = 'session_cache_photo_url';
  static const String _kPhotoPathKey = 'session_cache_photo_path';
  static const String _kBarangayKey = 'session_cache_barangay';
  static const String _kEmailKey = 'session_cache_email';

  /// Sentinel for "this user has no `user_roles` row" — an ordinary citizen.
  /// Stored explicitly so citizens get the offline fast path too, instead of
  /// being indistinguishable from a cache miss.
  static const int _kCitizen = 0;

  String? _uid;
  String? _username;
  int? _roleId;
  bool _loaded = false;

  /// The cached profile for the current uid, or null when none is stored.
  CachedProfile? _profile;

  /// The last known-good staff identity for the current uid, or null.
  CachedStaffIdentity? _staff;

  /// The last known-good staff identity for [uid], or null on a miss.
  ///
  /// Never carries an on-duty state — see the note on the storage keys.
  CachedStaffIdentity? staffFor(String uid) => _uid == uid ? _staff : null;

  /// The last known-good profile for [uid], or null on a miss.
  ///
  /// A miss and "unverified" are deliberately different values here: the whole
  /// bug was that a failed fetch defaulted to a real state. A null return means
  /// "we do not know", which the caller must not paint as an answer.
  CachedProfile? profileFor(String uid) => _uid == uid ? _profile : null;

  /// The cached username for [uid], or null when nothing is cached for them.
  String? usernameFor(String uid) => _uid == uid ? _username : null;

  /// The cached role for [uid]. Null means citizen OR miss — call
  /// [hasEntryFor] first when the difference matters.
  int? roleFor(String uid) => _uid == uid ? _roleId : null;

  /// Whether anything at all is cached for [uid].
  bool hasEntryFor(String uid) => _loaded && _uid == uid;

  /// Loads the cache into memory. Call once during startup, before the splash
  /// needs to route. Cheap: one SharedPreferences read, no network.
  Future<void> prime() async {
    // Runs on BOTH platforms. The routing hints it loads are consulted only by
    // the mobile splash — web routes through its own guard — but the display
    // hints (profile, staff identity) are read on web too, and they cannot be
    // read if nothing loaded them.
    try {
      final prefs = await SharedPreferences.getInstance();
      _uid = prefs.getString(_kUidKey);
      _username = prefs.getString(_kUsernameKey);
      final stored = prefs.getInt(_kRoleKey);
      _roleId = stored == _kCitizen ? null : stored;

      // Only a STORED verification status makes a profile. Absent that, the
      // profile stays null — "we do not know" — rather than materialising an
      // object whose default status would read as a genuine "unverified".
      final verif = prefs.getString(_kVerifKey);
      _profile = verif == null
          ? null
          : CachedProfile(
              verifStatus: verif,
              fullName: prefs.getString(_kFullNameKey),
              facePhotoUrl: prefs.getString(_kPhotoUrlKey),
              facePhotoPath: prefs.getString(_kPhotoPathKey),
              barangay: prefs.getString(_kBarangayKey),
              email: prefs.getString(_kEmailKey),
              username: _username,
            );

      // Only an EMAIL makes a staff identity: it is the one field the
      // repository always returns, so its absence is an unambiguous miss.
      final staffEmail = prefs.getString(_kStaffEmailKey);
      _staff = staffEmail == null
          ? null
          : CachedStaffIdentity(
              email: staffEmail,
              fullName: prefs.getString(_kStaffNameKey),
              title: prefs.getString(_kStaffTitleKey) ?? '',
              department: prefs.getString(_kStaffDeptKey) ?? '',
              photoUrl: prefs.getString(_kStaffPhotoKey),
              isExternal: prefs.getBool(_kStaffExternalKey) ?? false,
            );

      _loaded = _uid != null;
    } catch (_) {
      // A cache that cannot be read is simply a cache miss: the splash falls
      // back to querying, exactly as it did before this class existed.
      _uid = null;
      _username = null;
      _roleId = null;
      _profile = null;
      _staff = null;
      _loaded = false;
    }
  }

  /// Persists the hints for [uid]. Fire-and-forget — a failed write costs one
  /// online-only cold start, nothing more.
  Future<void> save({
    required String uid,
    required String username,
    required int? roleId,
  }) async {
    if (kIsWeb) return;
    // A different account than the one cached invalidates the stored profile:
    // it described the PREVIOUS user, and showing their name or photo to the
    // next one would be a leak, not a stale hint.
    if (_uid != uid) {
      _profile = null;
      _staff = null;
    }
    _uid = uid;
    _username = username;
    _roleId = roleId;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kUidKey, uid);
      await prefs.setString(_kUsernameKey, username);
      await prefs.setInt(_kRoleKey, roleId ?? _kCitizen);
    } catch (_) {
      // Best effort — see the doc comment above.
    }
  }

  /// Persists the last known-good profile for [uid].
  ///
  /// Call ONLY with a real fetched answer. Writing a default here would
  /// re-create the exact bug this cache exists to fix: a failure that looks
  /// like a fact, and then persists across restarts.
  Future<void> saveProfile({
    required String uid,
    required CachedProfile profile,
  }) async {
    // Drop anything held for a DIFFERENT account before adopting this one.
    // On mobile [save] does this at login, but web never calls [save] — its
    // routing goes through the router guard — so without this a browser that
    // switched accounts could keep the previous user's staff identity beside
    // the new user's profile. Showing one person's name or photo to another
    // is a leak, not a stale hint.
    if (_uid != uid) _staff = null;
    _uid = uid;
    _profile = profile;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kUidKey, uid);
      await prefs.setString(_kVerifKey, profile.verifStatus);
      await _put(prefs, _kFullNameKey, profile.fullName);
      await _put(prefs, _kPhotoUrlKey, profile.facePhotoUrl);
      await _put(prefs, _kPhotoPathKey, profile.facePhotoPath);
      await _put(prefs, _kBarangayKey, profile.barangay);
      await _put(prefs, _kEmailKey, profile.email);
      if (profile.username != null) {
        await prefs.setString(_kUsernameKey, profile.username!);
      }
    } catch (_) {
      // Best effort — a missed write costs one online-only start.
    }
  }

  /// Persists the last known-good staff identity for [uid].
  ///
  /// Takes the fields individually rather than a `StaffIdentity` so this file
  /// stays free of feature imports — and so the on-duty flag is not even in
  /// scope to be saved by accident.
  Future<void> saveStaffIdentity({
    required String uid,
    required CachedStaffIdentity identity,
  }) async {
    // Same reason as [saveProfile]: never let one account's data sit beside
    // another's.
    if (_uid != uid) _profile = null;
    _uid = uid;
    _staff = identity;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kUidKey, uid);
      await _put(prefs, _kStaffNameKey, identity.fullName);
      await _put(prefs, _kStaffEmailKey, identity.email);
      await _put(prefs, _kStaffTitleKey, identity.title);
      await _put(prefs, _kStaffDeptKey, identity.department);
      await _put(prefs, _kStaffPhotoKey, identity.photoUrl);
      await prefs.setBool(_kStaffExternalKey, identity.isExternal);
    } catch (_) {
      // Best effort — a missed write costs one online-only start.
    }
  }

  /// setString with a null meaning "remove", so a field that has become null
  /// (a photo the user deleted) does not linger from a previous write.
  Future<void> _put(SharedPreferences prefs, String key, String? value) async {
    if (value == null || value.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, value);
    }
  }

  /// Drops the hints, in memory and on disk, so they never outlive the session
  /// that proved them. Called from the sign-out teardown.
  Future<void> clear() async {
    // Both platforms — web stores display hints too, and a sign-out must not
    // leave a name or photo behind for the next person at the same browser.
    
    _uid = null;
    _username = null;
    _roleId = null;
    _profile = null;
    _staff = null;
    _loaded = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kUidKey);
      await prefs.remove(_kUsernameKey);
      await prefs.remove(_kRoleKey);
      await prefs.remove(_kVerifKey);
      await prefs.remove(_kFullNameKey);
      await prefs.remove(_kPhotoUrlKey);
      await prefs.remove(_kPhotoPathKey);
      await prefs.remove(_kBarangayKey);
      await prefs.remove(_kEmailKey);
      await prefs.remove(_kStaffNameKey);
      await prefs.remove(_kStaffEmailKey);
      await prefs.remove(_kStaffTitleKey);
      await prefs.remove(_kStaffDeptKey);
      await prefs.remove(_kStaffPhotoKey);
      await prefs.remove(_kStaffExternalKey);
    } catch (_) {
      // A hint that cannot be removed is stale, not dangerous: it is uid-keyed,
      // so it can only ever be applied to the account it was written for.
    }
  }

  /// Refreshes the hints from the server for the CURRENT user, in the
  /// background, once a destination is already on screen.
  ///
  /// Returns the freshly-read `is_deactivated` flag, or null when the lookup
  /// did not complete. The splash uses that to eject an account that was
  /// deactivated while it was offline.
  Future<bool?> refreshInBackground() async {
    // Mobile only, unlike the rest: this serves the splash's cached-resume
    // path — re-checking a deactivation that the offline route could not see.
    // Web has no such path; its guard re-resolves on every load.
    if (kIsWeb) return null;
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return null;

    String? username;
    bool? deactivated;
    int? roleId;
    var ok = false;

    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('username, is_deactivated')
          .eq('id', user.id)
          .maybeSingle();
      username = (row?['username'] as String?) ?? '';
      deactivated = (row?['is_deactivated'] as bool?) ?? false;

      final roleRow = await Supabase.instance.client
          .from('user_roles')
          .select('role_id')
          .eq('user_id', user.id)
          .maybeSingle();
      roleId = roleRow?['role_id'] as int?;
      ok = true;
    } catch (_) {
      // Still offline, or the request failed. Nothing was learned, so nothing
      // is written — caching a failure is what would make a wrong answer stick
      // across restarts.
    }

    if (ok && deactivated == false) {
      await save(uid: user.id, username: username ?? '', roleId: roleId);
    }
    return deactivated;
  }
}

/// The last known-good profile for the signed-in account.
///
/// [verifStatus] is stored as the RAW server string ('approved', 'pending',
/// 'none') rather than the `VerifStatus` enum, so this file stays free of UI
/// imports and the mapping lives in exactly one place — the provider that
/// already owns it. It also means a status the app does not yet understand
/// round-trips intact instead of being flattened on write.
class CachedProfile {
  final String verifStatus;
  final String? fullName;
  final String? facePhotoUrl;
  final String? facePhotoPath;
  final String? barangay;
  final String? email;
  final String? username;

  const CachedProfile({
    required this.verifStatus,
    this.fullName,
    this.facePhotoUrl,
    this.facePhotoPath,
    this.barangay,
    this.email,
    this.username,
  });
}

/// The last known-good staff identity, minus anything live.
///
/// There is deliberately NO `isOnline` field. The on-duty switch decides
/// whether a citizen's live-agent request is routed to this person, so a
/// remembered value could send a real citizen to an empty desk. Staff turn it
/// on themselves each session; that action is the only thing that honestly
/// means "I am here".
///
/// Do not add it. A test asserts this class has no such field.
class CachedStaffIdentity {
  final String email;
  final String? fullName;
  final String title;
  final String department;
  final String? photoUrl;
  final bool isExternal;

  const CachedStaffIdentity({
    required this.email,
    required this.fullName,
    required this.title,
    required this.department,
    required this.photoUrl,
    required this.isExternal,
  });
}
