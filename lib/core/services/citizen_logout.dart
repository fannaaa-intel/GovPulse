import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../router/legacy_nav.dart';
import '../widgets/Home/Chat-bubbles/home_chat_bubble.dart';
import '../widgets/app_dialog.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/logout_confirm_dialog.dart';
import 'chat_service.dart';
import 'push_service.dart';
import 'session_teardown.dart';

/// Signs the citizen out: confirm, unregister push, sign out of Supabase, wipe
/// the local chat cache, hide the floating bubble, then return to /login.
///
/// Lives here rather than inside a screen's State because three different places
/// need to start it — the Settings page, the nav chrome's logout action, and the
/// web shell — and only one of them has the State in its subtree. Settings used
/// to expose it by reaching back up the element tree with
/// `findAncestorStateOfType`, which worked but coupled the nav chrome to the
/// private State class of whatever happened to be mounted below it.
///
/// Session-scoped state — the user profile included — is cleared by
/// [tearDownSession], which takes the root [ProviderContainer] read from
/// [context] rather than a `WidgetRef`: a ref throws once its widget unmounts,
/// and the teardown has to survive exactly that. Callers used to pass their
/// `ref` here for the one `invalidate` this function did itself; that moved into
/// the teardown, so the parameter is gone.
///
/// No-ops (returns false) if the user cancels the confirmation.
Future<bool> performCitizenLogout(
  BuildContext context, {
  String? confirmMessage,
}) async {
  // Captured BEFORE the first await, while the context is certainly mounted.
  // The container belongs to the root scope and outlives this widget, so the
  // teardown in the `finally` below runs even when we bail on !context.mounted.
  final container = ProviderScope.containerOf(context, listen: false);

  // `message` carries a non-null default in the dialog, so pass it only when
  // a caller actually overrode it rather than restating the default here.
  final Future<bool> ask = confirmMessage == null
      ? showLogoutConfirmDialog(context)
      : showLogoutConfirmDialog(context, message: confirmMessage);
  final confirmed = await ask;
  if (!confirmed || !context.mounted) return false;

  // HELD, not popped blind. `signOut()` below drops the web auth guard onto its
  // signed-out branch, and the page swap that follows removes this spinner along
  // with the page it sits on — after which a `Navigator.pop` aimed at the
  // spinner lands on /login instead. See [AppDialogHandle].
  final spinner = showAppDialogWithHandle(
    context: context,
    barrierDismissible: false,
    builder: (_) => const LogoutLoadingOverlay(),
  );

  // Gates the teardown: if signOut() itself failed the session is still live,
  // and invalidating then would let the rebuilds refetch against it and
  // repopulate everything we just cleared.
  var signedOut = false;

  try {
    await PushService.I.unregister();
    await Supabase.instance.client.auth.signOut();
    signedOut = true;
    // Everything past this point is CLEANUP. The user is already signed out; a
    // chat cache that fails to clear is not a logout failure and must not divert
    // into the catch below, by now the guard's sign-out redirect has begun
    // moving off this location.
    try {
      await ChatService.onUserSignedOut();
    } catch (_) {}
    HomeChatBubble.hideGlobal();

    // Before the `context.mounted` gate, not after: the handle holds a route and
    // a navigator rather than a context, so it works whether or not the caller
    // survived — and a bail-out here used to strand the spinner on screen.
    spinner.dismiss();

    // ── WEB: the guard navigates, and nothing else may ─────────────────────
    // Signing out drops [_authRedirect] onto its signed-out branch, and
    // `_signedOutRedirect` returns /login from every citizen location — so the
    // guard is already taking the user there. Issuing a second, imperative
    // navigation on top of it is what produced the double-flash: the two land
    // in an order that depends on how long `signOut()` took, so a warm second
    // logout swapped them and the imperative one arrived after the page had
    // already changed underneath it. Same reasoning, same shape, as the
    // suspended-citizen sign-out in citizen_guard_modals.dart.
    //
    // The guard also subsumes what [goToLogin] was doing beyond navigating:
    // pageless routes above the outgoing page are removed with it, so there is
    // no stack left to clear by hand.
    if (kIsWeb) return true;

    // MOBILE is unchanged: no guard is watching, so this is the only thing that
    // moves the user.
    if (!context.mounted) return true;
    goToLogin(context);
    return true;
  } catch (e) {
    spinner.dismiss();
    if (!context.mounted) return false;
    showAppSnackBar(context, 'Logout failed: $e', type: AppSnackType.error);
    return false;
  } finally {
    // ALWAYS, on every exit from the try — including the !context.mounted
    // bail-out, which used to skip it and leak the previous account's profile
    // (and with it the verification sub-state) into the next login.
    //
    // In the `finally` rather than inline so it lands after the dismissal and
    // after mobile's [goToLogin]: invalidating unmounts the route subtrees
    // listening to those providers, and doing that mid-navigation trips the
    // navigator's !_debugLocked re-entrancy assert. On web there is no longer a
    // navigator call here at all — the guard's redirect runs on its own frame,
    // and this runs between frames — so the two can no longer overlap.
    if (signedOut) await tearDownSession(container);
  }
}
