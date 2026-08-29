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

      expect(find.text('Post'), findsOneWidget);
      expect(
        find.text('An admin reviews this before the citizen can see it.'),
        findsNothing,
        reason: 'the admin IS the reviewer — telling them this is nonsense',
      );
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
