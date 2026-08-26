// REGRESSION GUARD — an OPEN notification sheet is a live view, not a snapshot.
//
// Guards the bug fixed alongside migration 20260813000000: the popup copied
// NotificationService.notifications once in initState and never looked again, so
// a notification arriving (or being deleted from another device) did not appear
// in a sheet that was already open. The badge behind it was already live; the
// list was not.
//
// ── WHY THIS IS NOT A TRIVIAL TEST ────────────────────────────────────────
// The list is an [AnimatedList], which keeps its OWN item count. Reconciling by
// replacing the backing list desyncs the two and the itemBuilder then indexes
// past the end. The fix pairs every backing-list mutation with an
// insertItem/removeItem, and THAT is what these cases pin: the count the
// AnimatedList believes in has to match what is on screen after each change.
//
// ── NO NETWORK ────────────────────────────────────────────────────────────
// Supabase is initialized so NotificationService's `_uid` getter has a client
// to read, but nobody signs in — and load() returns early on a null uid without
// touching the list. So the static list stays exactly as each case seeds it and
// nothing here reaches the database. That is why this runs in CI unconditionally
// while staff_rating_live_regression_test needs a service-role key.
//
// Non-vacuous: verified 2026-08-13 by making _syncFromService return early —
// ALL FOUR cases failed. Re-prove that way after any change to the
// reconciliation, and do not accept a case that still passes with the listener
// stubbed. The read-state case earns its place only because it reads the
// rendered font weight; an earlier version asserted the row was "still there",
// which a do-nothing reconciler satisfies trivially — it passed the stub and
// was rewritten.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:govpulse/features/home/screen/notification_popup.dart';

const _url = 'https://vxvflhjbafqwehuxnmeq.supabase.co';
const _anon = 'sb_publishable_ZBDaQPQdFyC5kOHGbce9Ig_zdtIi6Mo';

AppNotification _n(String id, String title) => AppNotification(
      id: id,
      icon: Icons.info_outline,
      title: title,
      subtitle: 'body of $title',
      time: DateTime(2026, 8, 13, 9),
      color: Colors.blue,
    );

Future<void> _pumpSheet(WidgetTester tester) async {
  // A phone viewport — the sheet sizes itself off MediaQuery and the default
  // 800x600 test surface is not a shape it is built for.
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      // The test font draws EVERY glyph as a full em square, so a real
      // 13-character heading measures ~230px here against ~120 on a device and
      // the sheet header overflows on a viewport where it fits perfectly in the
      // app. Scaled down so text occupies device-like width.
      //
      // ⚠ THIS MAKES THE FILE BLIND TO LAYOUT. Nothing here may be read as
      // evidence about overflow — that is what the *_status_card / hero tests
      // are for, and they set their own scale deliberately. These cases pin
      // AnimatedList bookkeeping and nothing else.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(0.5)),
        child: child!,
      ),
      home: const Scaffold(body: NotificationPopup(width: 390)),
    ),
  );
  // initState's load() resolves on the next microtask (null uid → early
  // return), then the AnimatedList mounts with its initialItemCount.
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});

    // cached_network_image -> flutter_cache_manager -> path_provider has no
    // implementation in a test VM. Unrelated to what is under test.
    final tmp = Directory.systemTemp.createTempSync('govpulse_notif').path;
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
  });

  setUp(() {
    NotificationService.notifications = [];
    NotificationService.revision.value = 0;
  });

  testWidgets('a notification arriving lands in an already-open sheet',
      (tester) async {
    NotificationService.notifications = [_n('a', 'First'), _n('b', 'Second')];
    await _pumpSheet(tester);

    expect(find.text('First'), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);
    expect(find.text('Third'), findsNothing);

    // What the realtime callback does: refresh the list, then bump revision.
    // Newest-first, matching load()'s `order(created_at, ascending: false)`.
    NotificationService.notifications = [
      _n('c', 'Third'),
      _n('a', 'First'),
      _n('b', 'Second'),
    ];
    NotificationService.revision.value++;
    await tester.pumpAndSettle();

    expect(find.text('Third'), findsOneWidget,
        reason: 'an arrival must reach a sheet that is already open');
    expect(find.text('First'), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);
  });

  testWidgets('a notification deleted elsewhere leaves the open sheet',
      (tester) async {
    NotificationService.notifications = [
      _n('a', 'First'),
      _n('b', 'Second'),
      _n('c', 'Third'),
    ];
    await _pumpSheet(tester);
    expect(find.text('Second'), findsOneWidget);

    // Deleted on another device: the row is gone from the service and the only
    // signal is the revision bump.
    NotificationService.notifications = [_n('a', 'First'), _n('c', 'Third')];
    NotificationService.revision.value++;
    await tester.pumpAndSettle();

    expect(find.text('Second'), findsNothing,
        reason: 'a row removed elsewhere must collapse out of the open sheet');
    expect(find.text('First'), findsOneWidget);
    expect(find.text('Third'), findsOneWidget);
  });

  testWidgets('the AnimatedList count survives a remove-then-add sequence',
      (tester) async {
    // THE DESYNC CASE. If the backing list were swapped without pairing each
    // change with removeItem/insertItem, the AnimatedList would keep its old
    // count and the itemBuilder would index past the end of a shorter list —
    // which throws during the pump below rather than failing an expect.
    NotificationService.notifications = [
      _n('a', 'First'),
      _n('b', 'Second'),
      _n('c', 'Third'),
    ];
    await _pumpSheet(tester);

    NotificationService.notifications = [_n('b', 'Second')];
    NotificationService.revision.value++;
    await tester.pumpAndSettle();

    expect(find.text('First'), findsNothing);
    expect(find.text('Third'), findsNothing);
    expect(find.text('Second'), findsOneWidget);

    NotificationService.notifications = [
      _n('d', 'Fourth'),
      _n('b', 'Second'),
      _n('e', 'Fifth'),
    ];
    NotificationService.revision.value++;
    await tester.pumpAndSettle();

    expect(find.text('Fourth'), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);
    expect(find.text('Fifth'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a read-state change restyles the row in place', (tester) async {
    NotificationService.notifications = [_n('a', 'First')];
    await _pumpSheet(tester);

    // The row's own styling is the discriminator. Asserting only that the row
    // is STILL THERE would pass against a do-nothing reconciler — the row never
    // goes anywhere — so this reads the weight the card actually rendered:
    // w700 while unread, lighter once read.
    //
    // The read weight is w600, not w500: a read card no longer fades its
    // background, so the title carries the read/unread distinction on its own
    // and has to stay legible while still being visibly lighter than unread.
    FontWeight? weight() => tester.widget<Text>(find.text('First')).style?.fontWeight;
    expect(weight(), FontWeight.w700);

    // markRead replaces the object with copyWith(read: true) under the same id.
    // The row must stay put — same key, no insert/remove — and simply restyle.
    NotificationService.notifications = [
      NotificationService.notifications.first.copyWith(read: true),
    ];
    NotificationService.revision.value++;
    await tester.pumpAndSettle();

    expect(find.text('First'), findsOneWidget,
        reason: 'a read row stays in the list, it is not removed');
    expect(weight(), FontWeight.w600,
        reason: 'the card must pick up the new read state in place');
    expect(tester.takeException(), isNull);
  });
}
