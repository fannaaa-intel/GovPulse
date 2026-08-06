import 'package:flutter/foundation.dart';
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
  bool get settled => _settled;

  bool _started = false;

  /// Starts the one-shot restoration watch and subscribes to auth changes.
  /// Safe to call more than once.
  void begin() {
    if (_started) return;
    _started = true;

    Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      // A sign-in or sign-out is itself proof that auth state is known, and
      // both change where the user belongs — so settle and re-run the guard.
      _settled = true;
      notifyListeners();
    });

    // A SHORTER wait than the data-fetch default on purpose. This one is paid
    // by a signed-out visitor as time on the startup spinner before /login
    // appears — a restore that has not landed within a second was never going
    // to — whereas the 3s default is paid only by a query that would otherwise
    // return a wrong "not found". Different costs, different budgets.
    //
    // A session that is already restored settles instantly and waits for
    // nothing, which is the reload-onto-a-deep-link case that matters most.
    awaitAuthReady(timeout: const Duration(seconds: 1)).then((_) {
      if (_settled) return;
      _settled = true;
      notifyListeners();
    });
  }
}
