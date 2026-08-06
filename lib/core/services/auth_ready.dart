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
