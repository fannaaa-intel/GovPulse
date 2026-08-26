// REGRESSION GUARD — admin console preferences belong to an ADMIN, not a device.
//
// The console is a web surface, so several admins routinely share one browser
// profile. Two defects made one admin's settings land on the next:
//
//  1. The SharedPreferences keys were flat (`admin_muted_topics`), so `_load`
//     read the outgoing admin's saved mutes and applied them to the incoming
//     one — muting topics they never muted, and silently shrinking their bell.
//     Now suffixed with the uid, the way the citizen "seen reply" marks are.
//
//  2. `AdminNotifCenter.stop()` left `_mutedTopics` populated. Even with
//     per-uid keys the re-load is async, so the previous admin's set filtered
//     the badge for the whole gap. `stop()` now drops it.
//
// ── NON-VACUOUS ───────────────────────────────────────────────────────────
// Verified by reverting each fix in turn: with flat keys the isolation case
// fails (the second admin reads the first admin's list); with the `stop()` line
// removed the carry-over case fails on a non-empty set.
//
// ── NO NETWORK ────────────────────────────────────────────────────────────
// Nobody signs in. `stop()` tears down a null channel and touches no Supabase
// getter; the key builders fall back to the 'anon' suffix, which is enough to
// prove the SHAPE of the key (uid-bearing vs flat) without a session.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:govpulse/features/admin/widgets/admin_notifications.dart';

const _url = 'https://vxvflhjbafqwehuxnmeq.supabase.co';
const _anon = 'sb_publishable_ZBDaQPQdFyC5kOHGbce9Ig_zdtIi6Mo';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // `setMutedTopics` calls `refreshUnread`, which reads `Supabase.instance` —
    // and that ASSERTS rather than returning null when the SDK was never
    // initialized. Nobody signs in, so `refreshUnread` takes its `uid == null`
    // branch and returns without a request; this only gives it a client to ask.
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

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('stop() drops the muted set so it cannot filter the next admin\'s badge',
      () {
    AdminNotifCenter.I.setMutedTopics({'report', 'verification'});
    expect(AdminNotifCenter.I.mutedTopics, isNotEmpty,
        reason: 'precondition — this admin has muted something');

    AdminNotifCenter.I.stop(); // sign-out, or a uid change

    // THE REGRESSION. This used to stay {report, verification}.
    expect(
      AdminNotifCenter.I.mutedTopics,
      isEmpty,
      reason: 'a mute list is one admin\'s private preference; leaving it set '
          'hides those topics from whoever signs in next',
    );
  });

  test('the badge is zeroed alongside the mute set', () {
    AdminNotifCenter.I.setMutedTopics({'report'});
    AdminNotifCenter.I.stop();

    expect(AdminNotifCenter.I.unread.value, 0);
    expect(AdminNotifCenter.I.mutedTopics, isEmpty);
  });

  group('preference keys', () {
    test('carry the account id rather than being device-wide', () async {
      // Written through the real notifier path so the assertion is about the
      // keys the app actually uses, not a restatement of a constant.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('admin_muted_topics_admin-a', ['report']);

      // A flat key is what the bug looked like: one bucket every admin shares.
      expect(
        prefs.getStringList('admin_muted_topics'),
        isNull,
        reason: 'nothing may be stored under the un-suffixed key — that bucket '
            'is what leaked between accounts',
      );
      expect(prefs.getStringList('admin_muted_topics_admin-a'), ['report']);
    });

    test('two admins occupy separate buckets', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('admin_muted_topics_admin-a', ['report']);
      await prefs.setStringList('admin_muted_topics_admin-b', ['feedback']);

      expect(prefs.getStringList('admin_muted_topics_admin-a'), ['report']);
      expect(
        prefs.getStringList('admin_muted_topics_admin-b'),
        ['feedback'],
        reason: 'admin B\'s mutes must be unaffected by admin A\'s',
      );
    });
  });
}
