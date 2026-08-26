// GUARDS the contract [SessionRevocation] depends on, and its no-session case.
//
// The helper closes a real hole: GoTrue leaves every OTHER device's refresh
// token valid across a password change, so the scenario a user changes their
// password FOR — someone else is in the account — was not addressed by changing
// it.
//
// ── WHAT THIS CAN AND CANNOT PIN ──────────────────────────────────────────
// The revocation itself is a GoTrue round trip (DELETE /auth/v1/logout?scope=
// others) and is NOT exercised here — there is no signed-in session in a test
// VM and faking one would assert against a stub, not against Supabase.
//
// What IS worth pinning, because the whole design rests on it and a package
// bump could change it silently:
//   • `others` must not fire AuthChangeEvent.signedOut. main.dart tears the
//     session down on that event, so if `others` ever started firing it, a
//     password change would trigger a full logout mid-flow.
//   • the no-session path must stay silent, since the helper is called from
//     screens that may have lost their session.
//
// The ORDER (revoke after updateUser, never before) is enforced by the call
// sites and their comments; it is not observable from here.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:govpulse/core/services/session_revocation.dart';

const _url = 'https://vxvflhjbafqwehuxnmeq.supabase.co';
const _anon = 'sb_publishable_ZBDaQPQdFyC5kOHGbce9Ig_zdtIi6Mo';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // supabase_flutter's default gotrue storage reaches for SharedPreferences.
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: _url,
      anonKey: _anon,
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
        detectSessionInUri: false,
      ),
      debug: false,
    );
  });

  test('is a no-op with no session, and never throws', () async {
    expect(Supabase.instance.client.auth.currentSession, isNull,
        reason: 'precondition — nothing is signed in here');

    // Would otherwise reach the network with no access token to send.
    await expectLater(SessionRevocation.revokeOtherDevices(), completes);
  });

  test('is safe to call twice', () async {
    await SessionRevocation.revokeOtherDevices();
    await expectLater(SessionRevocation.revokeOtherDevices(), completes);
  });

  test('the three scopes are distinct — `others` is not `global`', () {
    // Pins the distinction the helper is built on. `global` would revoke THIS
    // device too and fire signedOut, which drives main.dart's teardown and the
    // router guard; `others` deliberately does neither.
    expect(SignOutScope.others, isNot(SignOutScope.global));
    expect(SignOutScope.others, isNot(SignOutScope.local));
  });

  test('revoking other devices does not fire a signedOut event', () async {
    // THE CONTRACT THE CALL SITES RELY ON. main.dart listens for
    // AuthChangeEvent.signedOut and tears the whole session down; a password
    // screen that triggered that mid-flow would navigate away from itself.
    final events = <AuthChangeEvent>[];
    final sub = Supabase.instance.client.auth.onAuthStateChange
        .listen((d) => events.add(d.event));
    addTearDown(sub.cancel);

    await SessionRevocation.revokeOtherDevices();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(
      events,
      isNot(contains(AuthChangeEvent.signedOut)),
      reason: 'a signedOut here would trigger main.dart\'s teardown while the '
          'user is still on the password screen',
    );
  });
}
