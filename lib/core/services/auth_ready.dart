import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
// Backs the WEB-only role cache below. Every use is behind `kIsWeb`, so mobile
// neither reads nor writes it and never pays for the plugin call.
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Waits until Supabase has finished restoring a persisted session, or until
/// [timeout], whichever comes first.
///
/// Why this exists: on a COLD load — a browser refresh straight onto a detail
/// URL — the widget tree builds and starts fetching immediately, but session
/// restoration from local storage is asynchronous and may not have landed yet.
/// A query that runs in that window is unauthenticated, so RLS quietly returns
/// no rows and the caller concludes "not found" for a report the user does in
/// fact own. That failure is especially nasty because it looks like correct
/// behaviour rather than a race.
///
/// In-session navigation never waits: [currentSession] is already non-null, so
/// this returns on the first check and costs nothing. That keeps the fast path —
/// and the mobile app, which always has a session by the time it navigates —
/// exactly as it was.
///
/// Bounded and non-throwing on purpose. A genuinely signed-out visitor has no
/// session to wait for, so after [timeout] the caller proceeds unauthenticated
/// and gets a legitimate "not found" rather than hanging on a spinner forever.
Future<void> awaitAuthReady({
  Duration timeout = const Duration(seconds: 3),
}) async {
  final auth = Supabase.instance.client.auth;
  if (auth.currentSession != null) return;

  final deadline = DateTime.now().add(timeout);
  while (auth.currentSession == null && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

/// The router-facing half of [awaitAuthReady]: a [Listenable] that fires once
/// session restoration has settled, and again on every sign-in / sign-out.
///
/// go_router's redirect is synchronous, so it cannot await the restoration race
/// that [awaitAuthReady] exists to absorb. Without something like this the
/// redirect would read `currentSession == null` on a cold load — a browser
/// refresh straight onto a deep link — and bounce a signed-in user to /login,
/// losing the URL they were actually on. That is the single worst failure mode
/// of an auth guard, because it looks exactly like being logged out.
///
/// So the guard treats "no session AND not settled yet" as UNKNOWN rather than
/// as signed-out, and holds the requested location. [settled] flipping notifies
/// go_router (via `refreshListenable`), the redirect re-runs, and only THEN is a
/// genuinely signed-out visitor sent to /login — with their location intact up
/// to that point.
class AuthRestoration extends ChangeNotifier {
  AuthRestoration._();

  static final AuthRestoration instance = AuthRestoration._();

  bool _settled = false;

  /// True once we know whether there is a session — either because one was
  /// restored, or because [awaitAuthReady] timed out waiting for one.
  ///
  /// On WEB "we know" means both auth systems have reported: a guest is a
  /// Firebase anonymous user with no Supabase session, so settling on Supabase
  /// alone would let the guard classify a guest mid-restore as signed out and
  /// bounce them off their own URL. On MOBILE there is no Firebase input and
  /// this means exactly what it always has — Supabase, or the timeout.
  bool get settled => _settled;

  /// Whether Supabase's restoration has reported in.
  bool _supabaseKnown = false;

  /// Whether Firebase's restoration has reported in.
  ///
  /// Starts true off web. [kIsWeb] is a `const bool`, so on mobile this folds
  /// to `true` at compile time and never gates [_settled] — which is what keeps
  /// mobile's settle timing identical to before this input existed.
  bool _firebaseKnown = !kIsWeb;

  /// The signed-in account's `user_roles.role_id` — 1 admin, 2 staff, null for
  /// a citizen, an unverified account, or nobody.
  int? _roleId;

  /// The uid that [_roleId] describes, or null when signed out.
  ///
  /// WEB ONLY — written only inside the `kIsWeb` block in [begin].
  ///
  /// Exists to tell an ACCOUNT CHANGE apart from a token refresh. The listener
  /// re-arms the role hold whenever this changes, and Supabase emits
  /// `tokenRefreshed` on a live session roughly hourly — so re-arming on every
  /// event instead would drop a console user onto the startup spinner for a
  /// round-trip in the middle of their work. Only a change of identity can
  /// invalidate a role.
  String? _roleUid;

  /// Whether the role lookup has reported in.
  ///
  /// Starts true off web for the same reason — and by the same mechanism — as
  /// [_firebaseKnown]: [kIsWeb] is a `const bool`, so on mobile this folds to
  /// `true` at compile time. Mobile therefore never waits on a role and never
  /// runs the fetch below. It has no need of either: mobile routes by role from
  /// [AuthService.login]'s return value and from the splash's own lookup,
  /// neither of which consults this class.
  bool _roleKnown = !kIsWeb;

  // ── Role cache ────────────────────────────────────────────────────────────
  //
  // WEB ONLY. A hint that lets the guard classify a returning visitor on its
  // FIRST evaluation instead of holding their location while a query runs.
  //
  // The window this closes is real but narrow: between the session becoming
  // known and the role landing, the guard holds — and holding means the
  // requested location builds. An admin cold-loading a citizen URL therefore
  // painted citizen chrome for the length of one query before being bounced.
  //
  // NEVER the source of truth. [_refreshRole] issues the real query on every
  // invocation, cache hit included, and overwrites whatever this supplied. A
  // role that changed between sessions is wrong for exactly as long as that
  // query takes, then corrects itself. And it only ever decides CHROME: every
  // console query is checked server-side against the user's actual user_roles
  // row, so a stale 'admin' hint yields an empty admin frame, never admin data.
  static const String _kRoleCacheUidKey = 'role_cache_uid';
  static const String _kRoleCacheRoleKey = 'role_cache_role';

  /// Sentinel for "this user has no role row" — a citizen. Stored explicitly so
  /// citizens get the fast path too, rather than being indistinguishable from a
  /// cache miss.
  static const int _kRoleCacheCitizen = 0;

  String? _cachedRoleUid;
  int? _cachedRoleId;

  /// Reads the cached role into memory. Call ONCE, before `runApp`, on web.
  ///
  /// Deliberately not keyed here: session restoration is asynchronous — the
  /// premise this whole class exists for — so there is no user id to key on
  /// yet. This loads the store; [_refreshRole] does the keyed lookup at the
  /// moment the session, and with it the id, becomes known. That instant is the
  /// start of the window being closed, so applying it there is what matters.
  Future<void> primeRoleCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _cachedRoleUid = prefs.getString(_kRoleCacheUidKey);
      final stored = prefs.getInt(_kRoleCacheRoleKey);
      _cachedRoleId = stored == _kRoleCacheCitizen ? null : stored;
    } catch (_) {
      // A cache that cannot be read is simply a cache miss.
      _cachedRoleUid = null;
      _cachedRoleId = null;
    }
  }

  Future<void> _writeRoleCache(String uid, int? role) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kRoleCacheUidKey, uid);
      await prefs.setInt(_kRoleCacheRoleKey, role ?? _kRoleCacheCitizen);
    } catch (_) {
      // Best effort: failing to persist the hint costs a held frame next time,
      // nothing more.
    }
  }

  /// Drops the persisted role hint, in memory and on disk.
  ///
  /// WEB ONLY by its single caller — the sign-out teardown in
  /// `core/services/session_teardown.dart`, which returns before this on
  /// mobile. Mobile never writes these keys either (every access in this class
  /// is `kIsWeb`-guarded), so there is nothing there to remove.
  ///
  /// Called so a role never outlives the session that proved it. The cost is
  /// one held frame on the next cold load after an explicit sign-out: the hint
  /// is rewritten by the first [_refreshRole] once the next account signs in.
  Future<void> clearRoleCache() async {
    _cachedRoleUid = null;
    _cachedRoleId = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kRoleCacheUidKey);
      await prefs.remove(_kRoleCacheRoleKey);
    } catch (_) {
      // A hint that cannot be removed is stale, not dangerous: it is uid-keyed,
      // so it can only ever be applied to the account it was written for.
    }
  }

  /// Only meaningful once [roleKnown]. Null means citizen.
  int? get roleId => _roleId;

  /// Whether [roleId] can be trusted yet. The web guard holds the requested
  /// location until this is true rather than guessing a role.
  bool get roleKnown => _roleKnown;

  // ── Auth-flow hold ──────────────────────────────────────────────────────
  //
  // Set while a screen is DELIBERATELY driving auth state as part of its own
  // flow, so the web guard leaves the location alone until it is finished.
  //
  // The case this exists for: the forgot-password reset screen must call
  // setSession() before it can do anything, because both the 30-day cooldown
  // read and updateUser() need an authenticated identity. That sign-in fires
  // onAuthStateChange -> notifyListeners() -> _authRedirect, SYNCHRONOUSLY,
  // long before the screen's own await has resumed. The screen sits on /login,
  // and _citizenRedirect sweeps a signed-in citizen off /login to /home — so
  // the user was thrown onto the home page mid-reset and never saw the result,
  // success or failure. On a cooldown block that looked like "I typed a new
  // password and it just logged me in", with the password silently unchanged.
  //
  // Only the guard reads this. It is NOT a security control: it holds the
  // requested location, exactly like the [settled] and [roleKnown] holds, and
  // every route still enforces its own access rules. Callers MUST release it in
  // a finally block — see reset_new_password_screen.updatePassword.
  bool _authFlowActive = false;

  /// True while a screen owns the auth transition; the web guard holds.
  bool get authFlowActive => _authFlowActive;

  /// Take the hold. Deliberately does NOT notify: the point is to avoid a guard
  /// re-run, not to cause one.
  void beginAuthFlow() {
    _authFlowActive = true;
  }

  /// Release the hold and re-run the guard so the user lands wherever their
  /// now-final auth state says they belong.
  void endAuthFlow() {
    if (!_authFlowActive) return;
    _authFlowActive = false;
    notifyListeners();
  }

  bool _started = false;

  /// Starts the one-shot restoration watch and subscribes to auth changes.
  /// Safe to call more than once.
  void begin() {
    if (_started) return;
    _started = true;

    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      // A sign-in or sign-out is itself proof that auth state is known, and
      // both change where the user belongs — so settle and re-run the guard.
      //
      // notifyListeners() fires on EVERY event, not just the first: that is
      // what re-runs the guard on sign-out, so it must not be short-circuited
      // once settled. Only the settle condition is gated.
      _supabaseKnown = true;
      if (_firebaseKnown) _settled = true;

      // Web only — folds out entirely on mobile, which never reads the role.
      //
      // RE-ARM THE ROLE HOLD BEFORE NOTIFYING, because notifyListeners() below
      // re-runs the guard SYNCHRONOUSLY while [_refreshRole] is async and has
      // not started. Without this the guard decides on the role left over from
      // the previous state — and after a signed-out boot that leftover is
      // (_roleKnown: true, _roleId: null), which the guard reads as a confident
      // "citizen" and uses to route an admin to /home for one round-trip before
      // correcting itself. The `!roleKnown` hold in _authRedirect was always
      // meant to cover this window; it never engaged because _roleKnown is
      // sticky-true once anything has resolved it.
      //
      // Gated on the uid rather than fired on every event: see [_roleUid].
      var identityChanged = false;
      if (kIsWeb) {
        final uid = data.session?.user.id;
        if (uid != _roleUid) {
          identityChanged = true;
          _roleUid = uid;
          _roleId = null;
          _roleKnown = false;
        }
      }

      notifyListeners();

      // Web only — folds out entirely on mobile, which never reads the role.
      //
      // This one listener covers BOTH triggers: a fresh sign-in, and a cold
      // load, because Supabase emits a restoration event for a persisted
      // session too. Signing out arrives here as well, which is what clears a
      // stale role before the next account signs in.
      //
      // ── Why this is gated on the identity, not fired on every event ───────
      // It used to run unconditionally, and that closed a FEEDBACK LOOP that
      // ended in the user being signed out a few seconds after logging in.
      //
      //   tokenRefreshed  →  this listener  →  _refreshRole()'s user_roles
      //   query  →  supabase-dart's AuthHttpClient calls _getAccessToken(),
      //   which refreshes the token whenever `currentSession.isExpired`  →
      //   tokenRefreshed  →  …
      //
      // Each turn costs one round trip, so the pair ran roughly every 150ms
      // until GoTrue's refresh limiter answered 429. A 429 is not a retryable
      // fetch error, so gotrue drops the session and emits signedOut — and the
      // guard, seeing no session, sends a user who had just signed in straight
      // back to /login.
      //
      // `isExpired` is the loop's ignition and it is true whenever the DEVICE
      // CLOCK runs ahead of the token's `exp` (see the clock check in
      // AuthService.login), but a clock nobody controls must not be able to
      // spend a session. Only a change of identity can invalidate a role — the
      // same rule the hold above already follows — so a token refresh no longer
      // issues a query, and the loop has no second turn.
      if (kIsWeb && identityChanged) _refreshRole();
    });

    // Web only, and the whole block is compiled out elsewhere because [kIsWeb]
    // is a const. Guests authenticate with Firebase anonymous auth and never
    // get a Supabase session, so without this the guard has no signal at all
    // when someone becomes — or stops being — a guest.
    //
    // Deliberately not on mobile: nothing there reads [settled], and the rule
    // is that a shared file may not register work on the Navigator 1.0 path.
    if (kIsWeb) {
      FirebaseAuth.instance.authStateChanges().listen((_) {
        _firebaseKnown = true;
        if (_supabaseKnown) _settled = true;
        notifyListeners();
      });
    }

    // A SHORTER wait than the data-fetch default on purpose. This one is paid
    // by a signed-out visitor as time on the startup spinner before /login
    // appears — a restore that has not landed within a second was never going
    // to — whereas the 3s default is paid only by a query that would otherwise
    // return a wrong "not found". Different costs, different budgets.
    //
    // A session that is already restored settles instantly and waits for
    // nothing, which is the reload-onto-a-deep-link case that matters most.
    awaitAuthReady(timeout: const Duration(seconds: 1)).then((_) async {
      // Belt and braces, web only. The listener above is the normal path to a
      // role, but it depends on Supabase emitting an event for the restored
      // session. If one never arrives while a session nonetheless exists, the
      // guard would hold that user's location forever waiting on a lookup
      // nothing had started. Conditioned on a session actually being present,
      // so a signed-out visitor never fires a pointless query.
      if (kIsWeb &&
          !_roleKnown &&
          Supabase.instance.client.auth.currentSession != null) {
        _refreshRole();
      }

      if (_settled) return;

      // This floor polls SUPABASE only, and a guest has no Supabase session to
      // wait for — so for them the second above always expires in full and this
      // used to settle with Firebase still unreported. The guard would then read
      // a mid-restore guest as signed out and bounce them off the very URL the
      // guest flow exists to make reloadable.
      //
      // Off web [_firebaseKnown] is a compile-time true, so this returns on its
      // first check and mobile settles at exactly the 1s mark it always has.
      await _awaitFirebaseKnown(timeout: const Duration(seconds: 2));

      // The event paths may have settled us while we waited.
      if (_settled) return;
      _settled = true;
      notifyListeners();
    });
  }

  /// Loads the signed-in account's role, or clears it when signed out.
  ///
  /// WEB ONLY: every call site sits inside an `if (kIsWeb)`, so this never runs
  /// on mobile and mobile never issues the query.
  ///
  /// Signing out resolves immediately — there is nothing to look up, and the
  /// answer is known the moment we see no user. That matters as much as the
  /// sign-in case: without it a stale [roleId] would outlive its session and
  /// the guard would route the next visitor by the last one's role.
  ///
  /// FAILS AS CITIZEN. A lookup that errors must not strand someone on the
  /// startup spinner, and the citizen shell is the surface with the least
  /// authority — so an error resolves to "citizen, known" rather than leaving
  /// the guard holding. The consoles are one sign-in away from being reachable
  /// again.
  Future<void> _refreshRole() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      _roleId = null;
      _roleKnown = true;
      notifyListeners();
      return;
    }

    // Synchronous fast path. An in-memory hit for THIS user classifies them
    // now, so the guard's very next evaluation routes them correctly instead of
    // holding their location while the query below runs — which is the whole
    // point: holding is what let citizen chrome paint for an admin.
    //
    // Keyed on the id, so a previous account's role on a shared browser is
    // never applied to a new one; a mismatch simply falls through to the hold.
    // Guarded on !_roleKnown so a later refresh never regresses a known role
    // back to a cached one.
    if (!_roleKnown && _cachedRoleUid == user.id) {
      _roleId = _cachedRoleId;
      _roleKnown = true;
      notifyListeners();
    }

    // ── The lookup, with ONE retry ───────────────────────────────────────
    //
    // `null` carries two different meanings here and they must not be
    // conflated: "this user has no user_roles row, so they are a citizen", and
    // "the query did not come back". This used to answer both with
    // `_roleId = null`, which meant a single network blip classified an admin
    // or a staff member as a citizen, swept them off their own console to
    // /home, AND persisted that wrong answer to the role cache — so the next
    // cold load started from "citizen" too, until a later refresh corrected it.
    //
    // It fails in the SAFE direction (a console user is downgraded, never a
    // citizen upgraded) and every console query is re-checked server-side, so
    // this was never a data-exposure bug — but being randomly and stickily
    // ejected from your own console is its own kind of broken.
    int? fetched;
    var lookupOk = false;
    for (var attempt = 0; attempt < 2 && !lookupOk; attempt++) {
      if (attempt > 0) {
        await Future.delayed(const Duration(milliseconds: 250));
      }
      try {
        final row = await Supabase.instance.client
            .from('user_roles')
            .select('role_id')
            .eq('user_id', user.id)
            .maybeSingle();
        fetched = row?['role_id'] as int?;
        lookupOk = true;
      } catch (_) {
        // Retry once, then fall through to the fail-safe below.
      }
    }

    if (lookupOk) {
      _roleId = fetched;
      _roleKnown = true;

      // Refresh the hint for next time. Fire-and-forget: nothing waits on it,
      // and a failed write costs one held frame on the next cold load.
      //
      // ONLY on a real answer. Caching a failure is what made the misclassify
      // stick across reloads.
      _writeRoleCache(user.id, _roleId);
    } else {
      // Fall back to the best answer we already hold for THIS user — the
      // synchronous cache hit above, when it fired — rather than forcing null
      // and demoting them. Keyed on the id so a previous account's role on a
      // shared browser is never applied to a new one.
      _roleId = (_cachedRoleUid == user.id) ? _cachedRoleId : null;
      _roleKnown = true;
      // Deliberately NOT written to the cache: nothing was learned.
    }

    notifyListeners();
  }

  /// Adopt a role that an authoritative lookup has ALREADY resolved, so the
  /// guard does not re-ask for something the caller is holding.
  ///
  /// WEB ONLY, like everything else that touches the role — mobile never reads
  /// it, and [kIsWeb] is a const so this folds to a no-op there.
  ///
  /// ── Why this exists ────────────────────────────────────────────────────────
  /// [AuthService.login] already runs `user_roles.select('role_id')` and returns
  /// the answer. Without this, signing in threw that answer away: the auth-state
  /// listener re-armed `_roleKnown = false`, the console route rendered the
  /// startup spinner, and [_refreshRole] issued the SAME query a second time —
  /// so every console login paid a redundant round-trip as a visible spinner
  /// flash between the login form and the dashboard.
  ///
  /// ── Only a POSITIVE role is adopted, and that is the whole safety rule ─────
  /// `null` from a lookup is ambiguous — a real citizen, an unverified account,
  /// or (before the caller's own error handling) a query that did not land.
  /// Adopting a null would set `_roleKnown = true` on a maybe-wrong answer, and
  /// because a known role is never re-derived that wrong answer would STICK —
  /// which is precisely the demotion bug the retry-and-fall-back logic in
  /// [_refreshRole] exists to prevent. So callers may only hand over 1 or 2, and
  /// anything else is ignored here rather than trusted. A citizen simply follows
  /// the normal path; they never reach a console builder anyway.
  ///
  /// [_roleUid] is set alongside, so the sign-in event that follows sees an
  /// unchanged identity and does not re-arm the hold this call just satisfied.
  void adoptRole({required String userId, required int? roleId}) {
    if (!kIsWeb) return;
    if (roleId != 1 && roleId != 2) return;

    _roleUid = userId;
    _roleId = roleId;
    _roleKnown = true;

    // Same hint [_refreshRole] writes on a real answer, so the next cold load
    // classifies this user synchronously instead of holding.
    _writeRoleCache(userId, roleId);

    notifyListeners();
  }

  /// Waits for Firebase's first auth event, or [timeout] — whichever first.
  ///
  /// Bounded because the alternative is a visitor stuck on the startup spinner
  /// forever if Firebase never initialises. In the normal case this costs
  /// nothing: Firebase reports within tens of milliseconds, emitting `null` for
  /// a visitor with no user just as readily as a user for one who has, so the
  /// timeout is reached only when Firebase is genuinely dead.
  ///
  /// 2s on top of the 1s floor puts the pathological worst case at 3s, matching
  /// [awaitAuthReady]'s own default budget for a wait that must not hang.
  ///
  /// Polls rather than listening, mirroring [awaitAuthReady] a few lines up: one
  /// bounded-wait idiom in this file is easier to reason about than two, and the
  /// 50ms granularity is irrelevant against a 1s floor.
  Future<void> _awaitFirebaseKnown({required Duration timeout}) async {
    if (_firebaseKnown) return;

    final deadline = DateTime.now().add(timeout);
    while (!_firebaseKnown && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
}
