import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/admin/providers/admin_session_providers.dart';
import '../../features/admin/widgets/admin_notifications.dart';
import '../../features/staff/providers/staff_providers.dart';
import '../../features/staff/widgets/staff_notifications.dart';
import '../providers/community_posts_provider.dart';
import '../providers/user_profile_provider.dart';
import 'auth_ready.dart';
import 'citizen_guard.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Session teardown — everything that must be dropped when a session ends.
//
//  ── Why this exists ────────────────────────────────────────────────────────
//  There are three sign-out paths — citizen (core/services/citizen_logout.dart),
//  admin (admin_dashboard_screen) and staff (staff_console_screen) — each with
//  its own hand-maintained list, and they had already drifted: the citizen path
//  was missing the notification-center stop the other two had, and ALL THREE
//  invalidated only `userProfileProvider`. Every other session-scoped provider
//  is a plain, non-autoDispose provider in the root ProviderScope, so a staff
//  member's identity, department and cached lists survived sign-out and were
//  still in the container when the next account signed in.
//
//  One list, called by all three, is the only version of this that stays true.
// ════════════════════════════════════════════════════════════════════════════

/// Clears session-scoped state that outlives `auth.signOut()`. **Web only.**
///
/// ── The mobile gate is deliberate, not incidental ──────────────────────────
/// All three call sites are SHARED between platforms: the citizen flow is
/// reached from the web shell (citizen_shell) AND from the legacy mobile
/// Settings screen, and both consoles are mounted by go_router on web and by
/// the mobile login/splash pushes (app_router, splash_screen). So this function
/// runs on mobile too, and everything it does would be NEW behaviour there.
///
/// Bug 2 — session state surviving into the next account — is a web symptom:
/// the web build keeps one long-lived process, one root ProviderScope and one
/// set of singletons across sign-in cycles. [kIsWeb] is a `const bool`, so the
/// early return folds the whole body out of the mobile build and the three call
/// sites keep the exact behaviour they have today.
///
/// Note what this does NOT do. `ChatService.onUserSignedOut()`,
/// `HomeChatBubble.hideGlobal()` and the per-role notification-center stops all
/// stay at the call sites, unmoved — they already run on both platforms and
/// their positions relative to `signOut()` are load-bearing.
///
/// `ref.invalidate(userProfileProvider)` DID stay there originally and has
/// since moved in here, above the web gate. It still runs on both platforms and
/// still lands after `goToLogin`, exactly as before — see the note at the call.
///
/// ── Ordering: AFTER `auth.signOut()`, and AFTER the navigator is done ──────
/// Two constraints, both learned the hard way.
///
/// AFTER `signOut()`: `ref.invalidate` is lazy — a provider with a live
/// listener rebuilds on the next microtask. At sign-out the console is still
/// mounted underneath the confirmation dialog, so invalidating while the
/// session is still valid would let those rebuilds refetch and repopulate the
/// very state being cleared; the teardown would silently undo itself. With the
/// session already gone they resolve empty and stay empty.
///
/// AFTER `Navigator.pop` AND `goToLogin`: invalidating a provider unmounts the
/// route subtrees listening to it, and doing that while the navigator is
/// mid-operation trips its `!_debugLocked` re-entrancy assert. Both navigator
/// calls have to complete first — not just the pop, because `goToLogin` is a
/// navigator operation too (on web `goClearingPageless` pops the pageless stack
/// before `context.go`). Slotting this between them just moves the collision.
///
/// Work that needs a live JWT — `PushService.unregister()`, staff's
/// `setOnline(false)` — stays at the call site, before `signOut()`.
///
/// ── Why a [ProviderContainer] and not a `WidgetRef` ────────────────────────
/// A `WidgetRef` throws once its widget is unmounted, so a teardown holding one
/// can only run while the caller is still on screen. That is exactly backwards:
/// the sign-out paths all have an `if (!context.mounted) return;` guard between
/// the network work and the navigation, and taking it meant skipping the
/// teardown entirely — leaving a signed-out session with every provider still
/// populated, including the citizen's verification sub-state.
///
/// The container is the root scope's and outlives every widget in it, so
/// callers capture it BEFORE their first `await` and invoke this from a
/// `finally`. Teardown then runs on every sign-out path, mounted or not.
///
/// Idempotent, and safe to call with no session.
Future<void> tearDownSession(ProviderContainer container) async {
  // ── Both platforms ──────────────────────────────────────────────────────
  // ABOVE the web gate on purpose, for two independent reasons.
  //
  // It must not become web-only: all three call sites already invalidated this
  // on both platforms, and dropping it on mobile would be a regression.
  //
  // And it must not sit at the call site: it used to be the LAST line of each
  // logout, after the navigation, so anything that threw earlier skipped it —
  // which is how a citizen's verification sub-state (verified/pending/none,
  // from verification_submissions via userProfileProvider) survived a failed
  // sign-out into the next login and showed the previous account's status.
  // Here it runs before anything that can throw.
  container.invalidate(userProfileProvider);

  if (!kIsWeb) return;

  // ── Singletons ──────────────────────────────────────────────────────────
  // Realtime channels first: each holds a subscription keyed to the outgoing
  // uid. Both notification centers are stopped unconditionally, not just the
  // one matching the role signing out — a console user's badge must not survive
  // into a citizen session on the same browser, and the citizen path stopped
  // neither before. Both stop() methods null their channel and zero their
  // badge, so the second call from a role that already stopped its own is a
  // genuine no-op.
  StaffNotifCenter.I.stop();
  AdminNotifCenter.I.stop();

  // No logout path called this before, on either platform. Web only here: the
  // mobile leak is real (CitizenGuard.start() runs from the mobile HomePage)
  // but is a separate, mobile-scoped change.
  CitizenGuard.I.stop();

  // NOT resetForAuthenticatedUser(): that early-returns when the cache is
  // already authenticated and populated, which is every citizen sign-out.
  CommunityPostsProvider.instance.resetForSignOut();

  // The persisted role hint. Uid-keyed, so it was never applied to the wrong
  // account — but a role that outlives its session is a footgun regardless.
  await AuthRestoration.instance.clearRoleCache();

  // ── Providers ───────────────────────────────────────────────────────────
  // The lists live beside their declarations (staff) and in a barrel next to
  // them (admin), so adding a provider puts its list in view.
  for (final provider in staffSessionProviders) {
    container.invalidate(provider);
  }
  for (final provider in adminSessionProviders) {
    container.invalidate(provider);
  }
}
