// Can a signed-in user get past the splash with no internet?
//
// ── The bug these pin ─────────────────────────────────────────────────────
// `supabase_flutter` persists the session itself, so `auth.currentUser`
// already survived a restart offline. What did NOT survive was everything the
// splash needed in order to ROUTE: the username and the role both came from
// `profiles` / `user_roles` queries. With no connection those hang or throw,
// so the splash knew a user was signed in and still could not say where to
// send them — and its connectivity gate ran FIRST anyway, so an offline start
// showed the no-internet screen regardless.
//
// [SessionCache] stores those two answers next to the session that proved
// them, which is what lets the splash decide a destination before it consults
// the network at all.
//
// These test the cache directly rather than driving the splash widget: the
// splash's own path needs a live Supabase client and a real Navigator, while
// every decision worth pinning — is there a hit, for WHICH account, and what
// does a citizen look like versus a miss — lives here.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:govpulse/core/services/session_cache.dart';

const _kUid = 'user-aaa';
const _kOtherUid = 'user-bbb';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // The cache is a singleton, so each test must start from a known state
    // rather than inheriting the previous one's hints.
    await SessionCache.instance.clear();
  });

  test('a primed cache routes a citizen offline, with no query', () async {
    await SessionCache.instance.save(
      uid: _kUid,
      username: 'juan',
      roleId: null, // citizen
    );

    // Simulate the cold start: a fresh process reads the store back.
    await SessionCache.instance.prime();

    expect(SessionCache.instance.hasEntryFor(_kUid), isTrue);
    expect(SessionCache.instance.usernameFor(_kUid), 'juan');
    // Null here means citizen, and `hasEntryFor` is what separates that from
    // a miss — the distinction the `_kCitizen` sentinel exists to preserve.
    expect(SessionCache.instance.roleFor(_kUid), isNull);
  });

  test('a citizen is a HIT, not a miss', () async {
    await SessionCache.instance.save(uid: _kUid, username: 'juan', roleId: null);
    await SessionCache.instance.prime();

    // Both are null-roled; only one is cached. If a citizen read as a miss
    // they would be the one group the offline path never helped.
    expect(SessionCache.instance.hasEntryFor(_kUid), isTrue);
    expect(SessionCache.instance.hasEntryFor(_kOtherUid), isFalse);
  });

  test('staff and admin roles survive the round trip', () async {
    await SessionCache.instance.save(uid: _kUid, username: 'staffer', roleId: 2);
    await SessionCache.instance.prime();
    expect(SessionCache.instance.roleFor(_kUid), 2);

    await SessionCache.instance.save(uid: _kUid, username: 'boss', roleId: 1);
    await SessionCache.instance.prime();
    expect(SessionCache.instance.roleFor(_kUid), 1);
  });

  test('hints are uid-keyed, so one account never routes another', () async {
    await SessionCache.instance.save(uid: _kUid, username: 'boss', roleId: 1);
    await SessionCache.instance.prime();

    // A different account on the same device reads as a plain miss, which
    // sends the splash down the query path instead of opening an admin
    // console for someone who is not an admin.
    expect(SessionCache.instance.hasEntryFor(_kOtherUid), isFalse);
    expect(SessionCache.instance.roleFor(_kOtherUid), isNull);
    expect(SessionCache.instance.usernameFor(_kOtherUid), isNull);
  });

  test('sign-out clears the hints so they never outlive the session', () async {
    await SessionCache.instance.save(uid: _kUid, username: 'juan', roleId: 2);
    await SessionCache.instance.prime();
    expect(SessionCache.instance.hasEntryFor(_kUid), isTrue);

    await SessionCache.instance.clear();
    expect(SessionCache.instance.hasEntryFor(_kUid), isFalse);

    // And the clear is durable — a later cold start must not resurrect them.
    await SessionCache.instance.prime();
    expect(SessionCache.instance.hasEntryFor(_kUid), isFalse);
  });

  // ── The resume gate ─────────────────────────────────────────────────────
  //
  // The splash asks one question before it may skip the no-internet screen:
  // can this cold start route from local state alone? Two inputs, and BOTH
  // matter — a cache hit, and a finished onboarding.
  //
  // The second is easy to forget, which is exactly what happened: the gate
  // checked only the cache while the router still sent an un-onboarded user to
  // /intro. So they skipped the offline screen and landed on a login form with
  // no connection to submit it to. These pin both inputs.
  group('the offline resume gate', () {
    // Mirrors `_canResumeFromCache` in splash_screen.dart. Kept as a local
    // reimplementation because the real one reads `Supabase.instance`, which
    // needs a live client; the LOGIC under test — that both inputs are
    // required — is what this pins.
    Future<bool> canResume({required String uid}) async {
      if (!SessionCache.instance.hasEntryFor(uid)) return false;
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('seenOnboarding') ?? false;
    }

    test('a cached session that finished onboarding resumes', () async {
      SharedPreferences.setMockInitialValues({'seenOnboarding': true});
      await SessionCache.instance.save(
        uid: _kUid,
        username: 'juan',
        roleId: null,
      );
      await SessionCache.instance.prime();

      expect(await canResume(uid: _kUid), isTrue);
    });

    test('a cached session that never finished onboarding does NOT', () async {
      // The desync case. The router will send this user to /intro → /login,
      // which needs the network — so the no-internet screen must NOT be
      // skipped for them, cache hit or not.
      SharedPreferences.setMockInitialValues({});
      await SessionCache.instance.save(
        uid: _kUid,
        username: 'juan',
        roleId: null,
      );
      await SessionCache.instance.prime();

      expect(SessionCache.instance.hasEntryFor(_kUid), isTrue);
      expect(await canResume(uid: _kUid), isFalse);
    });

    test('onboarding alone, with no cached session, does NOT resume', () async {
      SharedPreferences.setMockInitialValues({'seenOnboarding': true});
      await SessionCache.instance.prime();

      expect(await canResume(uid: _kUid), isFalse);
    });
  });

  // ── Profile hints ───────────────────────────────────────────────────────
  //
  // The bug: `verification_submissions` failing offline made
  // `userProfileProvider` error, every consumer fell back to
  // `VerifStatus.none` — a REAL state meaning "unverified" — and a verified
  // citizen was shown an unverified account with no name and no photo.
  //
  // The distinction these pin is the one that fix depends on: a cache MISS
  // must be distinguishable from a stored status, so a failure is never
  // painted as an answer.
  group('the profile hints', () {
    test('a verified profile survives a cold start', () async {
      await SessionCache.instance.saveProfile(
        uid: _kUid,
        profile: const CachedProfile(
          verifStatus: 'approved',
          fullName: 'Juan Dela Cruz',
          facePhotoUrl: 'https://example.test/p.jpg',
          barangay: 'Poblacion',
        ),
      );
      await SessionCache.instance.prime();

      final p = SessionCache.instance.profileFor(_kUid);
      expect(p, isNotNull);
      // The exact regression: this must NOT come back as unverified.
      expect(p!.verifStatus, 'approved');
      expect(p.fullName, 'Juan Dela Cruz');
      expect(p.facePhotoUrl, 'https://example.test/p.jpg');
      expect(p.barangay, 'Poblacion');
    });

    test('pending is preserved as its own state', () async {
      await SessionCache.instance.saveProfile(
        uid: _kUid,
        profile: const CachedProfile(verifStatus: 'pending'),
      );
      await SessionCache.instance.prime();

      // Three states, and the middle one must not collapse into either edge.
      expect(SessionCache.instance.profileFor(_kUid)!.verifStatus, 'pending');
    });

    test('no stored profile reads as UNKNOWN, not as unverified', () async {
      await SessionCache.instance.save(
        uid: _kUid,
        username: 'juan',
        roleId: null,
      );
      await SessionCache.instance.prime();

      // A routing hint exists, but no profile does. Null means "we do not
      // know" — the caller must fall through to the real fetch rather than
      // paint an answer. If this ever returned a default-constructed profile,
      // the original bug would be back.
      expect(SessionCache.instance.hasEntryFor(_kUid), isTrue);
      expect(SessionCache.instance.profileFor(_kUid), isNull);
    });

    test('a profile is never served to a different account', () async {
      await SessionCache.instance.saveProfile(
        uid: _kUid,
        profile: const CachedProfile(
          verifStatus: 'approved',
          fullName: 'Juan Dela Cruz',
        ),
      );
      await SessionCache.instance.prime();

      // Showing one account's name and photo to another is a leak, not a
      // stale hint.
      expect(SessionCache.instance.profileFor(_kOtherUid), isNull);
    });

    test('switching accounts drops the previous profile', () async {
      await SessionCache.instance.saveProfile(
        uid: _kUid,
        profile: const CachedProfile(
          verifStatus: 'approved',
          fullName: 'Juan Dela Cruz',
        ),
      );
      // A different user signs in on the same device.
      await SessionCache.instance.save(
        uid: _kOtherUid,
        username: 'maria',
        roleId: null,
      );

      expect(SessionCache.instance.profileFor(_kOtherUid), isNull);
      expect(SessionCache.instance.profileFor(_kUid), isNull);
    });

    test('sign-out clears the profile too', () async {
      await SessionCache.instance.saveProfile(
        uid: _kUid,
        profile: const CachedProfile(
          verifStatus: 'approved',
          fullName: 'Juan Dela Cruz',
        ),
      );
      await SessionCache.instance.clear();
      await SessionCache.instance.prime();

      expect(SessionCache.instance.profileFor(_kUid), isNull);
    });
  });

  // ── Staff identity hints ────────────────────────────────────────────────
  //
  // Same bug as the profile hints, one screen over: a failed identity fetch
  // falls through to the console's fallbacks, so a staff member on a weak
  // connection saw a generic 'S' avatar and the name 'Staff'.
  //
  // The load-bearing test in this group is the LAST one. The on-duty switch
  // must never be remembered: it decides whether a citizen's live-agent
  // request is routed to this person, so a stale 'online' would send a real
  // citizen to an empty desk.
  group('the staff identity hints', () {
    const identity = CachedStaffIdentity(
      email: 'ana@lgu.test',
      fullName: 'Ana Reyes',
      title: 'Desk Officer',
      department: 'MDRRMO',
      photoUrl: 'https://example.test/ana.jpg',
      isExternal: false,
    );

    test('a staff identity survives a cold start', () async {
      await SessionCache.instance.saveStaffIdentity(
        uid: _kUid,
        identity: identity,
      );
      await SessionCache.instance.prime();

      final saved = SessionCache.instance.staffFor(_kUid);
      expect(saved, isNotNull);
      // The regression: this must not come back as 'Staff' / 'S'.
      expect(saved!.fullName, 'Ana Reyes');
      expect(saved.department, 'MDRRMO');
      expect(saved.title, 'Desk Officer');
      expect(saved.photoUrl, 'https://example.test/ana.jpg');
    });

    test('an identity is never served to a different account', () async {
      await SessionCache.instance.saveStaffIdentity(
        uid: _kUid,
        identity: identity,
      );
      await SessionCache.instance.prime();

      expect(SessionCache.instance.staffFor(_kOtherUid), isNull);
    });

    test('switching accounts drops the previous identity', () async {
      await SessionCache.instance.saveStaffIdentity(
        uid: _kUid,
        identity: identity,
      );
      await SessionCache.instance.save(
        uid: _kOtherUid,
        username: 'other',
        roleId: 2,
      );

      expect(SessionCache.instance.staffFor(_kOtherUid), isNull);
      expect(SessionCache.instance.staffFor(_kUid), isNull);
    });

    test('sign-out clears the identity', () async {
      await SessionCache.instance.saveStaffIdentity(
        uid: _kUid,
        identity: identity,
      );
      await SessionCache.instance.clear();
      await SessionCache.instance.prime();

      expect(SessionCache.instance.staffFor(_kUid), isNull);
    });

    test('the on-duty switch is NEVER stored', () async {
      await SessionCache.instance.saveStaffIdentity(
        uid: _kUid,
        identity: identity,
      );
      final prefs = await SharedPreferences.getInstance();

      // The rule this whole group exists to protect.
      //
      // `findAvailableStaffId` routes a citizen's live-agent request to
      // whoever is marked online. If the switch were remembered, a staff
      // member could open the app showing on-duty from a previous session
      // while actually being away — and a real citizen would be routed to an
      // empty desk. Staff turn it on themselves; that action is the only
      // honest signal that they are present.
      //
      // Asserted against what is actually WRITTEN TO DISK, not against a
      // hand-kept list — a list would happily go stale the moment someone adds
      // a field, which is precisely the day this needs to fail.
      expect(
        prefs.getKeys().where((k) => k.contains('online')),
        isEmpty,
        reason: 'no on-duty state may reach disk — see the note above',
      );
      expect(
        prefs.getKeys().where((k) => k.startsWith('session_cache_staff')).length,
        6,
        reason:
            'six staff fields are cached; if this moved, a field was added — '
            'make sure it is not the on-duty switch, then update this count',
      );
    });
  });

  // ── Cross-contamination between the two hint kinds ──────────────────────
  //
  // Found while enabling the display hints on web. Account switching used to
  // be handled ONLY by [save] — the routing hints — which web never calls,
  // because web routes through the router guard instead. So on web a browser
  // that switched accounts could keep the previous user's staff identity
  // sitting beside the new user's profile.
  //
  // Both writers now drop the other kind when the uid changes.
  group('one account never inherits another', () {
    test('saving a profile drops a previous account staff identity', () async {
      await SessionCache.instance.saveStaffIdentity(
        uid: _kUid,
        identity: const CachedStaffIdentity(
          email: 'ana@lgu.test',
          fullName: 'Ana Reyes',
          title: 'Desk Officer',
          department: 'MDRRMO',
          photoUrl: null,
          isExternal: false,
        ),
      );

      // A DIFFERENT person signs in on the same browser.
      await SessionCache.instance.saveProfile(
        uid: _kOtherUid,
        profile: const CachedProfile(
          verifStatus: 'approved',
          fullName: 'Maria Santos',
        ),
      );

      expect(SessionCache.instance.staffFor(_kOtherUid), isNull);
      expect(SessionCache.instance.staffFor(_kUid), isNull);
      expect(SessionCache.instance.profileFor(_kOtherUid), isNotNull);
    });

    test('saving a staff identity drops a previous account profile', () async {
      await SessionCache.instance.saveProfile(
        uid: _kUid,
        profile: const CachedProfile(
          verifStatus: 'approved',
          fullName: 'Maria Santos',
        ),
      );

      await SessionCache.instance.saveStaffIdentity(
        uid: _kOtherUid,
        identity: const CachedStaffIdentity(
          email: 'ana@lgu.test',
          fullName: 'Ana Reyes',
          title: 'Desk Officer',
          department: 'MDRRMO',
          photoUrl: null,
          isExternal: false,
        ),
      );

      expect(SessionCache.instance.profileFor(_kOtherUid), isNull);
      expect(SessionCache.instance.profileFor(_kUid), isNull);
      expect(SessionCache.instance.staffFor(_kOtherUid), isNotNull);
    });
  });

  test('an empty store primes to a miss rather than throwing', () async {
    SharedPreferences.setMockInitialValues({});
    await SessionCache.instance.prime();

    // First-ever launch: no hints, so the splash falls through to the query
    // path — the behaviour that existed before the cache.
    expect(SessionCache.instance.hasEntryFor(_kUid), isFalse);
  });
}
