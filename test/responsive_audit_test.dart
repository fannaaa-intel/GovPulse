// Does the MOBILE app survive every phone, both ways up, at every text size?
//
// The bug this file exists to catch is a whole CLASS of bug, not one instance
// of it: nearly every citizen screen sizes itself proportionally off
// `MediaQuery.size.width`, and that is the width of the VIEWPORT. Rotate the
// handset and the viewport gets wider, so every title, gutter, avatar and icon
// measured against it inflates — on a 430x932 phone, by 2.2x. See
// mobile_metrics.dart for the full account and the fix.
//
// Three things are pinned here.
//
//   1. [uiScaleWidth] itself, directly. It is the one rule the whole rollout
//      rests on, so it is tested as a rule rather than only through its
//      consequences.
//
//   2. Every skeleton layout, at every phone size, in both orientations, at
//      three text scales. The skeletons are the honest probe available to a
//      widget test: they are pure StatelessWidgets with no Supabase, no network
//      and no auth, and each is built to mirror the real screen it stands in
//      for — same gutters, same proportional sizing, same structure. If a
//      screen's proportions overflow, its skeleton overflows with it.
//
//   3. The shared chrome — header, back chevron, profile card, both bottom
//      navs — which is what every one of those screens is wearing.
//
// Text scale matters as much as rotation, and is the half that is easy to
// forget: a user with Android's font size at Largest gets textScaleFactor 1.3,
// and a proportional layout that only just fits at 1.0 has nowhere to put it.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:govpulse/core/theme/mobile_metrics.dart';
import 'package:govpulse/features/home/Quick-action/Events/events_screen.dart';
import 'package:govpulse/features/home/Quick-action/Feedback/feedback_screen.dart';
import 'package:govpulse/features/home/Quick-action/Report/report_issue_screen.dart';
import 'package:govpulse/features/home/Quick-action/Suggestion/suggestion_screen.dart';
import 'package:govpulse/features/home/emergency/emergency_screen.dart';
import 'package:govpulse/features/home/my_report/my_reports_screen.dart';
import 'package:govpulse/features/home/newsfeed/news_feed_screen.dart';
import 'package:govpulse/features/home/settings/my-submission/my_submissions_screen.dart';
import 'package:govpulse/features/home/settings/settings_screen.dart';
import 'package:govpulse/core/widgets/Home/home_enums.dart';
import 'package:govpulse/core/widgets/Home/nav/app_bottom_nav.dart';
import 'package:govpulse/core/widgets/Home/nav/home_bottom_nav.dart';
import 'package:govpulse/core/widgets/Home/sections/home_profile_card.dart';
import 'package:govpulse/core/widgets/app_back_chevron.dart';
import 'package:govpulse/core/widgets/app_screen_header.dart';
import 'package:govpulse/core/widgets/loading/loading_overlay.dart';

import '_responsive_matrix.dart';

/// The accessibility text sizes Android and iOS actually hand an app.
/// 1.3 is Android's "Largest"; 1.0 is the default everything is designed at.
const _textScales = <double>[1.0, 1.15, 1.3];

Widget _wrap(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  home: Scaffold(body: child),
);

/// Pumps [build] across every phone, both orientations, every text scale, and
/// returns one line per combination that overflowed.
Future<List<String>> _sweep(
  WidgetTester tester,
  Widget Function() build, {
  Widget Function(Widget)? shell,
}) async {
  final failures = <String>[];
  for (final device in kAllPhones) {
    for (final scale in _textScales) {
      final errors = await pumpAt(
        tester,
        device,
        () => (shell ?? _wrap)(build()),
        textScale: scale,
      );
      // Every error, not just the first: a screen with two bad Rows would
      // otherwise report one, get fixed, and immediately fail again on the
      // other. Duplicates are squeezed out because the same RenderFlex reports
      // once on layout and again on paint.
      for (final e in errors.toSet()) {
        failures.add('$device @ ${scale}x — $e');
      }
    }
  }

  // Dispose the last tree. `pumpAt` clears the PREVIOUS one on its way in, so
  // without this the final screen is still mounted when the test ends and its
  // animation controllers and debounce timers are still running — which the
  // binding reports as "A Timer is still pending", drowning the layout result
  // this file is actually here to report.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));

  return failures;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Several citizen screens read `Supabase.instance` on the way UP — in build,
  // not in a callback — and assert if it was never initialised. So the client
  // has to exist before any of them can be pumped at all. Nothing signs in and
  // nothing here is allowed to reach the network: the session is empty, so the
  // screens settle into their signed-out/empty states, which is the state
  // whose CHROME this file is measuring. Mirrors the bootstrap in
  // notification_popup_live_test.dart.
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});

    // cached_network_image -> flutter_cache_manager -> path_provider has no
    // implementation in a test VM. Unrelated to what is under test.
    final tmp = Directory.systemTemp.createTempSync('govpulse_resp').path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tmp,
        );

    await Supabase.initialize(
      url: 'https://vxvflhjbafqwehuxnmeq.supabase.co',
      anonKey: 'sb_publishable_ZBDaQPQdFyC5kOHGbce9Ig_zdtIi6Mo',
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
        detectSessionInUri: false,
      ),
      debug: false,
    );
  });

  // ── 1. The rule itself ────────────────────────────────────────────────────
  group('uiScaleWidth', () {
    test('a device measures the same in both orientations', () {
      for (final d in kPortrait) {
        expect(
          uiScaleWidthOf(d.rotated.size),
          uiScaleWidthOf(d.size),
          reason: '${d.name} must not change scale when rotated',
        );
      }
    });

    test('portrait phones are unaffected — the fix is a no-op there', () {
      // Every phone's shortest side IS its portrait width, and all of them are
      // under the 480 cap. So the rollout changed nothing about what a phone
      // held upright renders, which is what made it safe to apply everywhere.
      for (final d in kPortrait) {
        expect(uiScaleWidthOf(d.size), d.size.width);
      }
    });

    test('a tablet is capped rather than given phone proportions at 768dp', () {
      expect(uiScaleWidthOf(kTablet.size), kUiScaleMaxWidth);
      expect(uiScaleWidthOf(kTablet.rotated.size), kUiScaleMaxWidth);
    });
  });

  // ── 2. Every skeleton, every phone, both ways up, three text sizes ────────
  //
  // One test per layout rather than per (layout x device x scale) so a failure
  // names the screen and lists every size that broke, instead of scattering
  // near-identical red lines across the whole report.
  for (final layout in SkeletonLayout.values) {
    if (layout == SkeletonLayout.none) continue;

    testWidgets('${layout.name} skeleton fits every phone', (tester) async {
      final failures = await _sweep(
        tester,
        () => LoadingOverlay.bodyOrSkeleton(
          isLoading: true,
          layout: layout,
          child: const SizedBox.shrink(),
        ),
      );
      expect(failures, isEmpty, reason: '\n${failures.join('\n')}');
    });
  }

  // ── 3. The shared chrome every screen wears ──────────────────────────────
  final chrome = <String, Widget Function()>{
    'AppScreenHeader': () => const AppScreenHeader(title: 'Terms of Service'),
    'AppScreenHeader (long title)': () =>
        const AppScreenHeader(title: 'Aparri Citizenship Verification Review'),
    'AppBackChevron': () => const AppBackChevron(),
    'HomeProfileCard (verified)': () => HomeProfileCard(
      username: 'juandelacruz',
      verifStatus: VerifStatus.verified,
      fullName: 'Juan Miguel Dela Cruz',
      facePhotoUrl: null,
      profileLoading: false,
      notificationCount: 12,
      onNotificationTap: () {},
      onVerifyTap: () {},
    ),
    'HomeProfileCard (unverified)': () => HomeProfileCard(
      username: 'juandelacruz',
      verifStatus: VerifStatus.none,
      fullName: 'Juan Miguel Dela Cruz',
      facePhotoUrl: null,
      profileLoading: false,
      notificationCount: 0,
      onNotificationTap: () {},
      onVerifyTap: () {},
    ),
  };

  chrome.forEach((name, build) {
    testWidgets('$name fits every phone', (tester) async {
      final failures = await _sweep(tester, build);
      expect(failures, isEmpty, reason: '\n${failures.join('\n')}');
    });
  });

  // The navs hang off `bottomNavigationBar`, not `body`, so they get their own
  // shell — pumped into a body they would be measured against the wrong slot.
  Widget navShell(Widget nav) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(body: const SizedBox.expand(), bottomNavigationBar: nav),
  );

  final navs = <String, Widget Function()>{
    'HomeBottomNav': () => HomeBottomNav(currentIndex: 0, onTap: (_) {}),
    'AppBottomNav': () => const AppBottomNav(
      currentIndex: 1,
      username: 'juandelacruz',
      isVerified: true,
    ),
  };

  navs.forEach((name, build) {
    testWidgets('$name fits every phone', (tester) async {
      final failures = await _sweep(tester, build, shell: navShell);
      expect(failures, isEmpty, reason: '\n${failures.join('\n')}');
    });
  });

  // ── 4. The real screens ──────────────────────────────────────────────────
  //
  // Supabase is not initialised under test, so every fetch these make fails
  // immediately and each screen settles into its empty or error state. That is
  // a limit worth stating plainly — a populated list is not covered here — but
  // it does not weaken what IS covered, because the thing under test is the
  // CHROME: the header, the hero panel, the gutters, the nav and the type
  // scale, all of which are laid out before any row arrives and are exactly
  // what the viewport-width bug deformed.
  Widget appShell(Widget screen) => ProviderScope(
    child: MaterialApp(debugShowCheckedModeBanner: false, home: screen),
  );

  final screens = <String, Widget Function()>{
    'EmergencyScreen': () =>
        const EmergencyScreen(username: 'juandelacruz', isVerified: true),
    'SettingScreen': () => const SettingScreen(username: 'juandelacruz'),
    'MyReportsScreen': () => const MyReportsScreen(username: 'juandelacruz'),
    // Added late: this screen was never in the sweep, and both overflows found
    // on it — the tab strip and the LGU-response block — would have been caught
    // years earlier if it had been. Its POPULATED form is swept separately in
    // submission_lists_content_matrix_test, since the empty state this file
    // renders cannot reach the tab badges.
    'MySubmissionsScreen': () =>
        const MySubmissionsScreen(username: 'juandelacruz'),
    // Guest mode, and not to test the guest feed: it is the one way to pump
    // this screen at all. Signed in, it calls `subscribeRealtime()` on
    // CommunityPostsProvider — a SINGLETON that deliberately outlives the
    // screen — so the websocket's heartbeat timers survive every dispose the
    // screen could possibly do, and the binding fails the test for a pending
    // timer before it ever reports a layout. `setGuestMode(true)` skips the
    // subscription. The feed body, its chrome and its gutters are identical;
    // what guest mode drops is post ACTIONS, not layout.
    'NewsFeedScreen': () => const NewsFeedScreen(
      username: 'juandelacruz',
      isVerified: true,
      isGuest: true,
    ),
    'EventsScreen': () => EventsScreen(
      username: 'juandelacruz',
      isVerified: true,
      onClose: () {},
    ),
    'ReportIssueScreen': () =>
        const ReportIssueScreen(username: 'juandelacruz'),
    'SuggestionScreen': () => const SuggestionScreen(username: 'juandelacruz'),
    'FeedbackScreen': () => const FeedbackScreen(username: 'juandelacruz'),
  };

  screens.forEach((name, build) {
    testWidgets('$name fits every phone', (tester) async {
      final failures = await _sweep(tester, build, shell: appShell);
      expect(failures, isEmpty, reason: '\n${failures.join('\n')}');
    });
  });
}
