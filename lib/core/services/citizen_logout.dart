import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/user_profile_provider.dart';
import '../router/legacy_nav.dart';
import '../widgets/Home/Chat-bubbles/home_chat_bubble.dart';
import '../widgets/app_dialog.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/logout_confirm_dialog.dart';
import 'chat_service.dart';
import 'push_service.dart';

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
/// [ref] is used only to invalidate [userProfileProvider] so the next signed-in
/// user does not inherit this one's cached profile.
///
/// No-ops (returns false) if the user cancels the confirmation.
Future<bool> performCitizenLogout(
  BuildContext context,
  WidgetRef ref, {
  String? confirmMessage,
}) async {
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

  try {
    await PushService.I.unregister();
    await Supabase.instance.client.auth.signOut();
    await ChatService.onUserSignedOut();
    HomeChatBubble.hideGlobal();

    if (!context.mounted) return true;
    Navigator.pop(context); // dismiss the spinner
    goToLogin(context);
    ref.invalidate(userProfileProvider);
    return true;
  } catch (e) {
    if (!context.mounted) return false;
    Navigator.pop(context);
    showAppSnackBar(context, 'Logout failed: $e', type: AppSnackType.error);
    return false;
  }
}
