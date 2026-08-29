// Progress updates — the approval loop's UI contract, and its layout on every
// phone this app ships to.
//
// ⚠ WHAT THESE TESTS DO NOT PROVE. The rule that a citizen never sees an
// unapproved update is enforced by RLS (migration 20260829000001), not by this
// widget: the citizen's SELECT policy binds owns_report to status='approved',
// and the staff INSERT policy hard-codes 'pending_approval'. A widget test runs
// against no database and cannot exercise either. What is pinned here is that
// the UI does not CONTRADICT that contract — no compose affordance for a
// citizen, no approve/return buttons outside the reviewer, and the promise that
// an admin reviews a submission is actually stated to the office making it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/core/widgets/report_progress_updates.dart';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '_responsive_matrix.dart';

// The widget reads `Supabase.instance` in a field initializer, and that ASSERTS
// rather than returning null when the SDK was never initialized — so the tree
// cannot even be constructed without this. Nobody signs in: the client exists
// only so the constructor succeeds, and every request it makes then fails,
// which is the "unavailable" path the widget already handles. Same setup as
// admin_settings_per_admin_test.dart.
const _url = 'https://vxvflhjbafqwehuxnmeq.supabase.co';
const _anon = 'sb_publishable_ZBDaQPQdFyC5kOHGbce9Ig_zdtIi6Mo';

/// Returns [count] approved updates, newest first, so the maxVisible cap and
/// the "View all" sheet can be exercised. Without a client that answers, the
/// widget settles into its empty state and neither is reachable.
class _ListApi extends http.BaseClient {
  final int count;
  _ListApi(this.count);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final rows = [
      for (var i = 0; i < count; i++)
        {
          'id': 'row-$i',
          'body': 'Update number $i.',
          'kind': 'progress',
          'status': 'approved',
          'rejected_reason': null,
          'author_role': 'staff',
          'author_name': 'Engineering Office',
          'created_at': '2026-08-29T12:0$i:00Z',
          'report_update_media': const [],
        },
    ];
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(rows))),
      200,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }
}

/// Re-initialises Supabase with a client that answers the list query.
Future<void> _bootWith(http.BaseClient api) async {
  try {
    await Supabase.instance.dispose();
  } catch (_) {
    // Not initialized yet.
  }
  await Supabase.initialize(
    url: 'https://preview.invalid',
    anonKey: 'test-not-a-real-key',
    httpClient: api,
    authOptions: const FlutterAuthClientOptions(
      localStorage: EmptyLocalStorage(),
      detectSessionInUri: false,
      autoRefreshToken: false,
    ),
    debug: false,
  );
}

/// The widget talks to Supabase in initState. There is no client in a widget
/// test, so the load throws and the widget settles into its "unavailable"
/// branch — which renders SizedBox.shrink and would make every assertion below
/// vacuous. So the tree is pumped and inspected for what it offers BEFORE that
/// future resolves, which is also the frame a real user sees first.
Widget _host(ReportUpdatesMode mode) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ReportProgressUpdates(
            reportId: '3f2a1b6c-8d4e-4f7a-9b1c-2e5d6a7b8c9d',
            mode: mode,
            authorName: 'Engineering Office',
          ),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Supabase.initialize builds a SharedPreferences-backed auth store even
    // with EmptyLocalStorage, and the plugin channel does not exist under the
    // test binding — so without the mock this throws MissingPluginException
    // before any test runs.
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

  group('the composer is offered to exactly the roles that may post', () {
    testWidgets('a citizen is given no way to write anything', (tester) async {
      await tester.pumpWidget(_host(ReportUpdatesMode.citizen));
      await tester.pump();

      expect(find.byType(TextField), findsNothing,
          reason: 'the citizen reads updates, never writes them');
      expect(find.text('Add photos'), findsNothing);
      expect(find.text('Approve'), findsNothing);
    });

    testWidgets('an office gets a composer that says it will be reviewed',
        (tester) async {
      await tester.pumpWidget(_host(ReportUpdatesMode.author));
      await tester.pump();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Submit for approval'), findsOneWidget,
          reason: 'the button must not imply the update goes live');
      expect(
        find.text('An admin reviews this before the citizen can see it.'),
        findsOneWidget,
        reason: 'the office must be told the update is not yet public',
      );
    });

    testWidgets('an admin posts directly, with no approval promise',
        (tester) async {
      await tester.pumpWidget(_host(ReportUpdatesMode.reviewer));
      await tester.pump();

      expect(find.text('Post update'), findsOneWidget);
      expect(
        find.text('An admin reviews this before the citizen can see it.'),
        findsNothing,
        reason: 'the admin IS the reviewer — telling them this is nonsense',
      );
    });
  });

  // The citizen screen frames every section as a blue heading OUTSIDE the
  // content, so this widget drops its own card and title there — and takes the
  // heading as a parameter, because it hides itself entirely when there is
  // nothing approved and a parent-emitted label would be stranded above
  // nothing.
  group('chrome', () {
    testWidgets('draws its own title and card by default', (tester) async {
      await tester.pumpWidget(_host(ReportUpdatesMode.author));
      await tester.pump();

      expect(find.text('Progress updates'), findsOneWidget);
    });

    testWidgets('drops both when chrome is off, and renders a passed heading',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ReportProgressUpdates(
                reportId: '3f2a1b6c-8d4e-4f7a-9b1c-2e5d6a7b8c9d',
                mode: ReportUpdatesMode.author,
                chrome: false,
                heading: Text('Passed-in heading'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Progress updates'), findsNothing,
          reason: 'the self-title must not double up with the parent one');
      expect(find.text('Passed-in heading'), findsOneWidget);
    });
  });

  // The citizen screen caps the inline list at two and moves the rest into a
  // sheet, because that screen already carries a tracker, a details card,
  // attachments and a completion gallery — an unbounded history turned it into
  // a page nobody reaches the bottom of.
  group('maxVisible', () {
    Widget capped(int cap) => MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ReportProgressUpdates(
                reportId: '3f2a1b6c-8d4e-4f7a-9b1c-2e5d6a7b8c9d',
                mode: ReportUpdatesMode.citizen,
                chrome: false,
                maxVisible: cap,
              ),
            ),
          ),
        );

    testWidgets('shows only the cap, and says how many are hidden',
        (tester) async {
      await _bootWith(_ListApi(5));
      await tester.pumpWidget(capped(2));
      await tester.pumpAndSettle();

      expect(find.text('Update number 0.'), findsOneWidget);
      expect(find.text('Update number 1.'), findsOneWidget);
      expect(find.text('Update number 2.'), findsNothing,
          reason: 'the third is past the cap');
      expect(find.text('View all 5 updates'), findsOneWidget);
    });

    testWidgets('no View all when nothing is hidden', (tester) async {
      await _bootWith(_ListApi(2));
      await tester.pumpWidget(capped(2));
      await tester.pumpAndSettle();

      expect(find.text('Update number 1.'), findsOneWidget);
      expect(find.textContaining('View all'), findsNothing,
          reason: 'a cap that hid nothing must not offer to reveal it');
    });

    testWidgets('the sheet carries every update', (tester) async {
      await _bootWith(_ListApi(5));
      await tester.pumpWidget(capped(2));
      await tester.pumpAndSettle();

      await tester.tap(find.text('View all 5 updates'));
      await tester.pumpAndSettle();

      expect(find.text('Progress updates (5)'), findsOneWidget);
      // The one the inline list withheld.
      expect(find.text('Update number 4.'), findsOneWidget);
    });
  });

  // The sheet serves a 320px phone, a tablet and a desktop browser from one
  // widget, and the three want different things: edge to edge on a phone,
  // width-capped and floating on a wide screen. These pin the two properties
  // that a screenshot at one size cannot.
  group('the sheet is responsive', () {
    Future<void> openAt(WidgetTester tester, Size size) async {
      await _bootWith(_ListApi(4));
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ReportProgressUpdates(
                reportId: '3f2a1b6c-8d4e-4f7a-9b1c-2e5d6a7b8c9d',
                mode: ReportUpdatesMode.citizen,
                chrome: false,
                maxVisible: 2,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('View all 4 updates'));
      await tester.pumpAndSettle();
    }

    testWidgets('fills the width on a phone', (tester) async {
      await openAt(tester, const Size(360, 720));

      final box = tester.getSize(
        find.ancestor(
          of: find.text('Progress updates (4)'),
          matching: find.byType(ConstrainedBox),
        ).first,
      );
      expect(box.width, 360,
          reason: 'a phone sheet runs edge to edge');
    });

    // showModalBottomSheet ALWAYS anchors to the bottom edge, whatever the
    // viewport — which put a drag-handled phone sheet across the foot of a
    // desktop browser. A wide screen gets a centred Dialog instead.
    testWidgets('is a bottom sheet on a phone', (tester) async {
      await openAt(tester, const Size(360, 720));
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('is a centred dialog on a wide screen', (tester) async {
      await openAt(tester, const Size(1400, 900));
      expect(find.byType(Dialog), findsOneWidget,
          reason: 'a bottom sheet on a 1400px window is a stranded phone '
              'gesture');
    });

    testWidgets('caps its width on a wide screen', (tester) async {
      await openAt(tester, const Size(1400, 900));

      final box = tester.getSize(
        find.ancestor(
          of: find.text('Progress updates (4)'),
          matching: find.byType(ConstrainedBox),
        ).first,
      );
      expect(box.width, lessThanOrEqualTo(620),
          reason: 'body text running 1400px wide is unreadable');
    });
  });

  testWidgets('an empty body cannot be submitted', (tester) async {
    await tester.pumpWidget(_host(ReportUpdatesMode.author));
    await tester.pump();

    // Tapping Submit with nothing typed must not throw and must not clear the
    // staged state — _submit returns early. The assertion that matters is that
    // the composer is still standing afterwards.
    await tester.tap(find.text('Submit for approval'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(TextField), findsOneWidget);
  });

  // The composer holds a text field, two buttons and a chip on one axis, and
  // the tile holds a name, up to three badges and a timestamp on another. Both
  // are Wrap, not Row, precisely because they overflow otherwise — this is what
  // proves that stayed true.
  group('lays out on every phone', () {
    for (final mode in ReportUpdatesMode.values) {
      for (final device in kAllPhones) {
        testWidgets('${mode.name} at $device', (tester) async {
          final overflows = await pumpAt(tester, device, () => _host(mode));
          expect(overflows, isEmpty, reason: overflows.join('\n'));
        });
      }
    }
  });

  // Android's largest font setting, on the smallest phone — where a Row that
  // looked fine at 1.0x gives way.
  testWidgets('survives a large text scale on a small phone', (tester) async {
    final overflows = await pumpAt(
      tester,
      kSmallPhone,
      () => _host(ReportUpdatesMode.author),
      textScale: 1.6,
    );
    expect(overflows, isEmpty, reason: overflows.join('\n'));
  });
}
