import 'dart:async' show unawaited;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Ensures a visitor about to use the guest experience holds a Firebase
/// anonymous user.
///
/// ── Why this exists ────────────────────────────────────────────────────────
/// A guest is not a Supabase session — they are a Firebase anonymous user with
/// no Supabase session at all. The web auth guard is being taught to classify
/// three states (signed-out / guest / citizen) rather than two, and "guest"
/// can only be recognised if the anonymous user actually exists by the time the
/// guard runs. Today it does not for every entry: only the login screen's guest
/// button mints one, so a visitor arriving from sign-up, or by pasting
/// `/#/guest`, reaches the guest screen indistinguishable from a stranger.
///
/// Called from [GuestScreen.initState], which every route into guest mode
/// passes through — the login and sign-up buttons, and the `/guest` GoRoute.
/// That is why this is one call and not four.
///
/// ── Web only, deliberately ─────────────────────────────────────────────────
/// [kIsWeb] is a `const bool`, so off web the body below is eliminated at
/// compile time: no Firebase call, no user minted, no auth-state event. Mobile
/// keeps exactly the behaviour it has today, where the login button mints an
/// anonymous user and the sign-up button does not. The asymmetry is untouched
/// because mobile has no guard to satisfy — the three-state classification
/// lives on the web router, which the Navigator 1.0 app never builds.
///
/// ── Idempotent, and it never clobbers a real user ──────────────────────────
/// Returns early if ANY Firebase user is present. That covers the cheap case
/// (an anonymous user from an earlier tap — `signInAnonymously` would return it
/// anyway, but without a round trip) and the dangerous one: Firebase signs the
/// current user OUT when `signInAnonymously` is called while a non-anonymous
/// user is signed in. Minting on mount would otherwise evict a real account
/// just because someone opened `/#/guest`.
/// The mint currently in flight, so concurrent callers share one round trip.
///
/// [GuestScreen.initState] starts a mint the moment the screen mounts, and
/// [goToGuestFeed] awaits one just before the guard runs. Without this the
/// second call would see `currentUser == null` — the first has not landed yet —
/// and fire a SECOND `signInAnonymously`, which mints a second anonymous
/// account and makes the round trip the button waits on longer than it needs to
/// be. Sharing the future means the button waits on the mint already running.
///
/// Cleared when it completes so a later call (a visitor who signed out, say)
/// starts a fresh one rather than reusing a stale result.
Future<void>? _inFlight;

/// Whether a guest anonymous user exists RIGHT NOW.
///
/// The guard's question, asked without starting anything. [goToGuestFeed] uses
/// it to skip the await entirely in the common case — a visitor who sat on the
/// guest screen for more than a moment already has one, and making them wait on
/// a resolved future would add a frame for nothing.
bool get hasGuestAnonSession =>
    kIsWeb && FirebaseAuth.instance.currentUser != null;

Future<void> ensureGuestAnonSession() {
  if (!kIsWeb) return Future<void>.value();
  if (FirebaseAuth.instance.currentUser != null) return Future<void>.value();

  // Somebody else is already minting — wait on theirs rather than starting a
  // second one. See [_inFlight].
  final running = _inFlight;
  if (running != null) return running;

  final future = () async {
    try {
      await FirebaseAuth.instance.signInAnonymously();
    } catch (_) {
      // Non-fatal. The guest screen renders and browses fine without it; the
      // only cost is that the guard reads this visitor as signed-out — which
      // is why [goToGuestFeed] awaits this before navigating, so a failure
      // shows up as "stayed put" rather than as a bounce to /login.
    }
  }();

  _inFlight = future;
  // Detached on purpose: this clears the slot without making callers wait on
  // the cleanup, and `future` already swallows its own errors.
  unawaited(future.whenComplete(() {
    if (identical(_inFlight, future)) _inFlight = null;
  }));
  return future;
}
