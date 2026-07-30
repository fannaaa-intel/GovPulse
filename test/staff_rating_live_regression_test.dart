// REGRESSION GUARD — staff thread must render LIVE ticket state.
//
// Guards the bug fixed in "Staff thread reads live ticket state instead of a
// tap-time snapshot": the citizen's post-chat rating did not reach the staff
// side until the staffer navigated away and back.
//
// THE NARROW CASE IS THE ONE THAT MATTERS. On a wide console the page pushes a
// fresh StaffConversation into the thread on every rebuild, so a by-value
// snapshot still refreshes on the next poll tick and a wide-only test passes
// even against the broken code. On a narrow console the thread is an opaque
// pushed route: it is never rebuilt from above, and it unmounts the page that
// would have rebuilt it. A snapshot taken at tap time is final there. If you
// delete one of the two cases below, delete the wide one.
//
// Non-vacuous: verified 2026-07-30 by stashing the fix and re-running — WIDE
// still passed, NARROW failed on "Citizen rated this chat". Re-prove that way
// after any change to StaffThreadView's conversation resolution.
//
// LIVE: creates its own users/ticket in the real project and deletes them
// again. Skipped unless the service-role key is supplied:
//
//   flutter test test/staff_rating_live_regression_test.dart \
//     --dart-define=SUPABASE_SERVICE_ROLE=<key>
//
// The key is NEVER hardcoded here. It is a full-bypass credential.
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:govpulse/features/staff/pages/staff_conversations_page.dart';
import 'package:govpulse/features/staff/providers/staff_providers.dart';

const _url = 'https://vxvflhjbafqwehuxnmeq.supabase.co';
const _anon = 'sb_publishable_ZBDaQPQdFyC5kOHGbce9Ig_zdtIi6Mo';
const _svcKey = String.fromEnvironment('SUPABASE_SERVICE_ROLE');

const _waiting = 'Waiting for the citizen to rate…';
const _rated = 'Citizen rated this chat';

/// Every fixture row is scoped to this synthetic department, so the staff
/// account under test sees ONLY the fixture ticket. Nothing here depends on,
/// or can be confused by, real production conversations.
late String _dept;
late String _refCode;
late String _staffEmail;
late String _citizenEmail;
late String _staffId;
late String _citizenId;
late String _ticketId;
late String _tileLabel;

late SupabaseClient _svc;
late SupabaseClient _citizenClient;

const _pass = 'Regression!Fixture!20260730';

/// Crockford base32 minus I, L, O, U — the alphabet the reference_code CHECK
/// and the concern_tickets_enforce_anonymity trigger accept (migration
/// 20260722000017). Getting this wrong fails the insert, not the assertion.
String _ref() {
  const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  final r = Random.secure();
  final tail =
      List.generate(6, (_) => alphabet[r.nextInt(alphabet.length)]).join();
  final now = DateTime.now().toUtc();
  final d = '${now.year}${now.month.toString().padLeft(2, '0')}'
      '${now.day.toString().padLeft(2, '0')}';
  return 'LGU-$d-$tail';
}

Future<void> _createFixture() async {
  final stamp = DateTime.now().microsecondsSinceEpoch;
  _dept = 'ZZ Regression Dept $stamp';
  _refCode = _ref();
  _staffEmail = 'regr-staff-$stamp@example.com';
  _citizenEmail = 'regr-citizen-$stamp@example.com';

  final staff = await _svc.auth.admin.createUser(AdminUserAttributes(
      email: _staffEmail, password: _pass, emailConfirm: true));
  final citizen = await _svc.auth.admin.createUser(AdminUserAttributes(
      email: _citizenEmail, password: _pass, emailConfirm: true));
  _staffId = staff.user!.id;
  _citizenId = citizen.user!.id;

  await _svc.from('profiles').insert([
    {'id': _staffId, 'username': 'regr_staff_$stamp', 'email': _staffEmail, 'status': 'active'},
    {'id': _citizenId, 'username': 'regr_citizen_$stamp', 'email': _citizenEmail, 'status': 'active'},
  ]);
  await _svc.from('user_roles').insert([
    {'user_id': _staffId, 'role_id': 2},
    {'user_id': _citizenId, 'role_id': 3},
  ]);
  await _svc.from('admin_profiles').insert({
    'user_id': _staffId,
    'full_name': 'Regression Staff',
    'department': _dept,
  });

  final row = await _svc
      .from('concern_tickets')
      .insert({
        'reference_code': _refCode,
        'user_id': _citizenId,
        'category': 'Roads',
        'department': _dept,
        'details': 'rating staleness regression fixture',
        'status': 'closed',
        'assigned_staff_id': _staffId,
        'is_ghost': false,
        'is_anonymous': false,
        'resolved_at': DateTime.now().toUtc().toIso8601String(),
      })
      .select('id')
      .single();
  _ticketId = row['id'] as String;
  _tileLabel = 'Citizen · $_refCode';

  await _svc.from('ticket_messages').insert({
    'ticket_id': _ticketId,
    'sender_id': _citizenId,
    'sender_type': 'citizen',
    'text': 'hello po',
  });
}

Future<void> _destroyFixture() async {
  try {
    await _svc.from('ticket_messages').delete().eq('ticket_id', _ticketId);
    await _svc.from('concern_tickets').delete().eq('id', _ticketId);
    await _svc.from('notifications').delete().inFilter('user_id', [_staffId, _citizenId]);
    await _svc.from('admin_profiles').delete().eq('user_id', _staffId);
    await _svc.from('user_roles').delete().inFilter('user_id', [_staffId, _citizenId]);
    await _svc.from('profiles').delete().inFilter('id', [_staffId, _citizenId]);
    await _svc.auth.admin.deleteUser(_staffId);
    await _svc.auth.admin.deleteUser(_citizenId);
  } catch (e) {
    // Never mask a real assertion failure behind a teardown error, but do say
    // so — a leaked fixture user is worth knowing about.
    debugPrint('FIXTURE TEARDOWN FAILED (manual cleanup needed): $e');
  }
}

Future<void> _resetRating() => _svc.from('concern_tickets').update(
    {'rating': null, 'rating_comment': null, 'rated_at': null}).eq('id', _ticketId);

Future<void> _settle(WidgetTester tester,
    {int rounds = 14, Duration step = const Duration(milliseconds: 400)}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(step));
    await tester.pump();
  }
}

void main() {
  // LIVE binding: the default one runs under FakeAsync, so a request started by
  // a widget never completes and every provider stays in AsyncLoading forever.
  LiveTestWidgetsFlutterBinding();
  HttpOverrides.global = null;

  final missingKey = _svcKey.isEmpty;

  setUpAll(() async {
    if (missingKey) return;
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});

    // cached_network_image -> flutter_cache_manager -> path_provider has no
    // implementation in a test VM. Unrelated to what is under test.
    final tmp = Directory.systemTemp.createTempSync('govpulse_regr').path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp,
    );

    await Supabase.initialize(
      url: _url,
      anonKey: _anon,
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
        detectSessionInUri: false,
      ),
      debug: false,
    );
    _svc = SupabaseClient(_url, _svcKey);
    await _createFixture();

    _citizenClient = SupabaseClient(_url, _anon);
    await _citizenClient.auth
        .signInWithPassword(email: _citizenEmail, password: _pass);
    await Supabase.instance.client.auth
        .signInWithPassword(email: _staffEmail, password: _pass);
  });

  tearDownAll(() async {
    if (missingKey) return;
    await _destroyFixture();
  });

  Future<void> runLayout(WidgetTester tester, Size size, String label) async {
    HttpOverrides.global = null;
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);

    await tester.runAsync(_resetRating);

    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: Scaffold(body: StaffConversationsPage())),
    ));
    await _settle(tester);

    expect(find.text(_tileLabel), findsWidgets,
        reason: '[$label] fixture ticket must be in the staff inbox');

    // Captured BEFORE the tap: on narrow the pushed opaque route unmounts
    // StaffConversationsPage, so it cannot be located afterwards.
    final container = ProviderScope.containerOf(
        tester.element(find.byType(StaffConversationsPage)));

    await tester.tap(find.text(_tileLabel).first);
    await _settle(tester);

    expect(find.text(_waiting), findsOneWidget,
        reason: '[$label] thread open, citizen has not rated yet');
    expect(find.text(_rated), findsNothing);

    await tester.runAsync(() => _citizenClient.rpc('rate_ticket', params: {
          'p_ticket_id': _ticketId,
          'p_rating': 4,
          'p_comment': 'regression fixture',
        }));

    await tester.pump();
    expect(find.text(_rated), findsNothing,
        reason: '[$label] nothing has refreshed yet');

    // ONE poll tick — the exact method StaffIntervalPoll's 30s timer calls.
    // NO navigation: the thread is never popped, reopened, or rebuilt from
    // above. This is the whole assertion.
    await tester.runAsync(
        () => container.read(staffConversationsProvider.notifier).poll());
    await _settle(tester, rounds: 8);

    expect(find.text(_rated), findsOneWidget,
        reason: '[$label] rating must render WITHOUT navigation — the thread '
            'must resolve ticket state from staffConversationsProvider by id, '
            'not from the by-value seed captured when the tile was tapped');
    expect(find.text(_waiting), findsNothing);
    debugPrint('[$label] PASS — rating rendered with no navigation');

    await tester.pumpWidget(const SizedBox());
    await _settle(tester, rounds: 3);
  }

  testWidgets(
    'NARROW (<900, pushed route): rating appears without navigation',
    (tester) => runLayout(tester, const Size(500, 900), 'NARROW 500x900'),
    timeout: const Timeout(Duration(minutes: 4)),
    skip: missingKey,
  );

  testWidgets(
    'WIDE (>=900, two-pane): rating appears without navigation',
    (tester) => runLayout(tester, const Size(1400, 900), 'WIDE 1400x900'),
    timeout: const Timeout(Duration(minutes: 4)),
    skip: missingKey,
  );
}
