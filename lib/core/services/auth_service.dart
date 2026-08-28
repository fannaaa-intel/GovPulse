import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'session_cache.dart';

class AuthService {
  static final _client = Supabase.instance.client;

  // ── Signup checks ───────────────────────────────────────────────────────
  // These run BEFORE any session exists, so they go through Edge Functions
  // deployed with verify_jwt = false. Each returns only {'exists': bool} —
  // never any row data. The `profiles` table itself is not readable by the
  // anon key.
  //
  // These used to call the `email_exists` / `username_exists` RPCs directly
  // with the anon key. The RPCs are unmetered — PostgREST applies no rate
  // limiting — so the enumeration oracle they expose was bounded only by
  // network throughput. Routing through the Edge Functions puts every probe
  // behind that layer's checkRateLimit. There is deliberately NO fallback to
  // the RPCs: a fallback would keep the unmetered path alive and defeat the
  // revoke that follows.
  //
  // The Edge Functions are themselves thin wrappers over the same two RPCs
  // (called server-side), so the matching semantics are unchanged and remain
  // defined in exactly one place — `lower(col) = lower(trim(input))`.
  //
  // The value sent is the TRIMMED input, matching what _submitSignup actually
  // stores (signup_screen.dart:354-355). That is not a reimplementation of the
  // match — it is sending the same string the form will submit, so the answer
  // describes the value that will really be written.

  static Future<bool> checkEmailExists(String email) async {
    if (email.trim().isEmpty) return false;
    try {
      final response = await _client.functions.invoke(
        'check-email-exists',
        body: {'email': email.trim()},
      );
      final data = response.data;
      return data is Map && data['exists'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> checkUsernameExists(String username) async {
    if (username.trim().isEmpty) return false;
    try {
      final response = await _client.functions.invoke(
        'check-username-exists',
        body: {'username': username.trim()},
      );
      final data = response.data;
      return data is Map && data['exists'] == true;
    } catch (_) {
      return false;
    }
  }

  // ── Login ─────────────────────────────────────────────────────────────────
  static Future<({String username, int? roleId})> login(
    String username,
    String password,
  ) async {
    final cleanUsername = username.trim();
    // DO NOT REMOVE THIS .trim() (audit F-12).
    //
    // It is not ideal — it silently strips leading/trailing whitespace and so
    // slightly shrinks the password space. But signup trims too
    // (signup_screen.dart, _submitSignup), so any account created through the
    // app has a TRIMMED password stored in GoTrue. Dropping the trim here would
    // send the untrimmed string and lock out every existing user whose password
    // has surrounding whitespace. Changing this safely means changing signup and
    // login together AND migrating existing credentials — which cannot be done,
    // because the stored bcrypt hashes are one-way. Treat it as permanent.
    final cleanPassword = password.trim();

    if (cleanUsername.isEmpty || cleanPassword.isEmpty) {
      throw 'Please enter your username and password.';
    }

    // Steps 1+2 — resolve the account AND verify the password SERVER-SIDE via
    // the `username-login` Edge Function. The email is resolved inside the
    // function and never returned to the client: the old two-step path called
    // lookup_login_email, which handed the account's email to the anon key —
    // a username→email oracle with no login. That RPC's anon EXECUTE is revoked
    // in 10b phase 3, so there is deliberately NO client fallback to it here; a
    // fallback would keep the oracle alive. On success the function returns only
    // a session. Unknown-username and wrong-password are indistinguishable (both
    // 401) by design, so their copy below MUST stay identical.
    final FunctionResponse response;
    try {
      response = await _client.functions.invoke(
        'username-login',
        body: {'username': cleanUsername, 'password': cleanPassword},
      );
    } on FunctionException catch (e) {
      // functions_client throws FunctionException on non-2xx; the status field
      // is `status` (int), not `statusCode`.
      switch (e.status) {
        case 401:
          // MUST be the same string as a wrong password — never "user not
          // found" — or this re-opens the enumeration the Edge Function closes.
          throw 'Incorrect password. Please try again.';
        case 403:
          throw 'This account has been deactivated. Please contact the LGU to restore access.';
        case 429:
          throw 'Too many login attempts. Please try again in a few minutes.';
        default: // 400, 500, or any other non-2xx
          throw 'Something went wrong. Please try again later.';
      }
    } catch (_) {
      // Could not reach the function at all (network/transport).
      throw 'Unable to connect. Please check your internet connection and try again.';
    }

    // Establish the session from the returned refresh token. It is single-use
    // and rotates on exchange, so a failure here is not a credentials problem —
    // the user must sign in again. Show a retryable message, not "login failed".
    final data = response.data;
    final refreshToken =
        (data is Map ? data['refresh_token'] as String? : null) ?? '';
    final String userId;
    try {
      final authResponse = await _client.auth.setSession(refreshToken);
      final user = authResponse.user ?? _client.auth.currentUser;
      if (user == null) throw 'no session';
      userId = user.id;
    } catch (_) {
      throw 'Something went wrong. Please try again later.';
    }

    // ── Device-clock gate ────────────────────────────────────────────────────
    //
    // A session minted a fraction of a second ago cannot really have expired,
    // so `isExpired` here can only mean this DEVICE'S CLOCK is running ahead of
    // the token's `exp` — gotrue derives the expiry from the JWT and compares it
    // against `DateTime.now()`, with a 30s margin.
    //
    // That is not a cosmetic problem, it is unusable: supabase-dart refreshes
    // the token before ANY request whose session reads as expired, so every
    // query mints a new token that also reads as expired, and the app spends
    // roughly one refresh per query until GoTrue's limiter answers 429. A 429 is
    // not a retryable fetch error, so gotrue drops the session and emits
    // signedOut — the web guard then bounces the user to /login seconds after
    // they signed in, with nothing on screen to explain why.
    //
    // The loop's amplifiers are gone (see AuthRestoration.begin and main's
    // _initServices), but the underlying condition still makes the session
    // unusable, and only the user can fix it. So say so plainly, with the
    // measured error, and refuse the sign-in rather than handing back a session
    // that will die on its own.
    //
    // `expiresAt` is the JWT's `exp` and `expiresIn` the lifetime GoTrue issued
    // it with, so their difference is the moment the SERVER issued the token —
    // and the gap to local now is the skew itself, not an estimate.
    final fresh = _client.auth.currentSession;
    if (fresh != null && fresh.isExpired) {
      final expiresAt = fresh.expiresAt;
      final expiresIn = fresh.expiresIn;
      String offBy = '';
      if (expiresAt != null && expiresIn != null) {
        final issuedAt = DateTime.fromMillisecondsSinceEpoch(
          (expiresAt - expiresIn) * 1000,
        );
        final skew = DateTime.now().difference(issuedAt);
        if (skew.inMinutes.abs() >= 1) {
          offBy = skew.isNegative
              ? ' It is about ${-skew.inMinutes} minutes behind.'
              : ' It is about ${skew.inMinutes} minutes ahead.';
        }
      }
      await _client.auth.signOut();
      throw "Your device's date and time are wrong, so your sign-in expires "
          "immediately.$offBy Turn on automatic date and time, then try again.";
    }

    // Step 3 — deactivation is gated SERVER-SIDE and is not re-checked here.
    //
    // Removed 2026-08-23 (audit F-13). This used to re-read
    // profiles.is_deactivated and treat a read error as "not deactivated".
    // It was dead code and weaker than the real gate:
    //   * username-login already answers 403 for a deactivated account and
    //     revokes the session it minted, so a deactivated user never reaches
    //     this line with a session at all — the 403 is handled above.
    //   * that gate FAILS CLOSED (an unreadable flag returns 500 and revokes);
    //     this copy failed OPEN, so keeping it around implied a protection it
    //     did not provide.
    // It also cost an extra round-trip on every single successful login.
    // Do not reinstate a client-side copy: the server decides.

    // Step 4 — fetch role_id (null = unverified citizen)
    final roleData = await _client
        .from('user_roles')
        .select('role_id')
        .eq('user_id', userId)
        .maybeSingle();

    final roleId = roleData?['role_id'] as int?;

    // Seed the mobile splash's offline routing hints while both answers are in
    // hand. Doing it here rather than only on the next splash query means the
    // fast path works from the FIRST cold start after signing in, instead of
    // needing one more online launch to warm itself.
    //
    // Fire-and-forget, and a no-op on web: nothing about login should wait on
    // a SharedPreferences write.
    unawaited(
      SessionCache.instance.save(
        uid: userId,
        username: cleanUsername,
        roleId: roleId,
      ),
    );

    // The Edge Function returns only a session, not the account's canonical
    // username, so echo the (trimmed) input. Previously this was the DB's
    // stored casing; usernames match case-insensitively, so this only affects
    // display casing on the Home greeting.
    return (username: cleanUsername, roleId: roleId);
  }
}
