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

  showAppDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const LogoutLoadingOverlay(),
  );

  // Gates the teardown: if signOut() itself failed the session is still live,
  // and invalidating then would let the rebuilds refetch against it and
  // repopulate everything we just cleared.
  var signedOut = false;
  // The spinner is popped on exactly one path, and the catch must not pop a
  // second, unintended route when the failure happened after the dismissal.
  var spinnerDismissed = false;

  try {
    await PushService.I.unregister();
    await Supabase.instance.client.auth.signOut();
    signedOut = true;
    await ChatService.onUserSignedOut();
    HomeChatBubble.hideGlobal();

    if (!context.mounted) return true;
    Navigator.pop(context); // dismiss the spinner
    spinnerDismissed = true;
    goToLogin(context);
    return true;
  } catch (e) {
    if (!context.mounted) return false;
    if (!spinnerDismissed) {
      Navigator.pop(context);
      spinnerDismissed = true;
    }
    showAppSnackBar(context, 'Logout failed: $e', type: AppSnackType.error);
    return false;
  } finally {
    // ALWAYS, on every exit from the try — including the !context.mounted
    // bail-out, which used to skip it and leak the previous account's profile
    // (and with it the verification sub-state) into the next login.
    //
    // In the `finally` rather than inline so it lands after BOTH navigator
    // calls on the happy path: invalidating unmounts the route subtrees
    // listening to those providers, and doing that mid-navigation trips the
    // navigator's !_debugLocked re-entrancy assert.
    if (signedOut) await tearDownSession(container);
  }
}
