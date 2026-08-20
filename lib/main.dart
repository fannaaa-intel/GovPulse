import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
// ignore: depend_on_referenced_packages
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
// ignore: depend_on_referenced_packages
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'core/services/push_service.dart';

import 'firebase_options.dart';
import 'core/router/app_router.dart';
import 'features/onboarding/splash_screen.dart';
import 'features/home/shell/citizen_shell_router.dart' show GovPulseWebApp;
import 'core/services/auth_ready.dart' show AuthRestoration;
import 'features/scan/scan_page.dart';
import 'core/widgets/Home/Chat-bubbles/home_chat_bubble.dart';
import 'core/services/chat_service.dart';
import 'features/home/screen/notification_popup.dart' show NotificationService;

/// Global navigator key — used by [AuthService] to push after login.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// True for the one known-benign framework crash we deliberately swallow: the
/// `_zOrderIndex != null` assertion thrown from a [Tooltip]'s hide path.
///
/// The framework's Tooltip (raw_tooltip.dart) doesn't stop its fade controller
/// when its widget is deactivated mid-animation — so on the very common "hover a
/// nav/toolbar tooltip, then click something that rebuilds it away" flow, the
/// controller ticks to `dismissed` a frame later and calls
/// `OverlayPortalController.hide()` on an already-detached portal, tripping the
/// assert (flutter/lib/src/widgets/overlay.dart). It is DEBUG-ONLY: in release
/// the assert is compiled out and `hide()` is a harmless no-op, so suppressing
/// it in debug just matches release behaviour. The match is deliberately narrow
/// — the assertion text AND a tooltip stack frame — so every other error still
/// surfaces normally. Remove once the upstream Tooltip fix lands.
bool _isBenignTooltipZOrderAssertion(FlutterErrorDetails details) {
  if (!details.exceptionAsString().contains('_zOrderIndex')) return false;
  final stack = details.stack?.toString() ?? '';
  return stack.contains('raw_tooltip') ||
      stack.contains('_handleStatusChanged') ||
      stack.contains('Tooltip');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Drop only the benign Tooltip assertion above; forward everything else to
  // Flutter's normal reporting so real errors are never hidden.
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (_isBenignTooltipZOrderAssertion(details)) return;
    (previousOnError ?? FlutterError.presentError)(details);
  };

  // Force Hybrid Composition for Android Google Maps. Without it this device
  // renders blank map tiles (only the marker + "Google" logo draw). Hybrid
  // Composition composites the real map surface, so tiles render. The exit
  // transition is handled separately (the map is snapshotted on close so it
  // fades out with the route instead of popping abruptly).
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    final mapsImpl = GoogleMapsFlutterPlatform.instance;
    if (mapsImpl is GoogleMapsFlutterAndroid) {
      mapsImpl.useAndroidViewSurface = true;
    }
  }

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Must be registered before runApp.
  FirebaseMessaging.onBackgroundMessage(
    firebaseMessagingBackgroundHandler,
  ); // ← PUSH

  await Supabase.initialize(
    url: 'https://vxvflhjbafqwehuxnmeq.supabase.co',
    anonKey: 'sb_publishable_ZBDaQPQdFyC5kOHGbce9Ig_zdtIi6Mo',
  );

  await Hive.initFlutter();

  // Web only: pull the cached role into memory before the first frame, so the
  // guard can classify a returning admin or staff member on its FIRST
  // evaluation rather than holding their location — and painting citizen
  // chrome — while a user_roles query runs.
  //
  // [kIsWeb] is a const, so this block and its await are compiled out on
  // mobile: no SharedPreferences call, no added wait, and main()'s sequence is
  // exactly what it has always been there. Mobile has no use for it either —
  // it routes by role from AuthService.login and from the splash's own lookup.
  //
  // Before begin(), because begin() can resolve a role immediately on a warm
  // session and the cache has to be in memory by then to be consulted.
  if (kIsWeb) {
    await AuthRestoration.instance.primeRoleCache();
  }

  // Start watching for a restored session before the first frame, so the web
  // router's auth guard has something to wait on rather than reading a
  // half-restored auth state and bouncing a signed-in user to /login.
  AuthRestoration.instance.begin();

  // Start the app NOW — splash renders immediately, before any network work.
  runApp(const ProviderScope(child: GovPulseApp()));

  // Everything network-dependent runs after, off the critical path,
  // so it can never block the splash from rendering.
  _initServices();
}

/// Network-dependent service initialization.
/// Runs AFTER runApp so a slow/offline network never blocks first frame.
Future<void> _initServices() async {
  try {
    await PushService.I.init(); // ← PUSH
  } catch (_) {}

  final restored = Supabase.instance.client.auth.currentUser;

  /// The account these services are currently wired to, or null when none.
  ///
  /// The listener below fires on EVERY auth event, and `tokenRefreshed` is an
  /// auth event — so without this the whole block re-ran on every refresh, and
  /// each re-run issues queries (the chat rebind, the push registration, the
  /// notification channel's first load). Those queries go through
  /// supabase-dart's AuthHttpClient, which refreshes the token whenever
  /// `currentSession.isExpired`, which emits another `tokenRefreshed` — a loop
  /// that only ends when GoTrue's refresh limiter returns 429 and gotrue drops
  /// the session, signing the user out seconds after they signed in. See the
  /// matching gate in `AuthRestoration.begin`, which closed the other half of
  /// the same loop.
  ///
  /// None of this work describes a TOKEN; it describes an ACCOUNT. So it runs
  /// once per account and a refresh is correctly a no-op.
  String? wiredUid;

  try {
    if (restored != null) {
      wiredUid = restored.id;
      await ChatService.onUserAuthenticated(restored.id);
      await PushService.I.registerForUser(); // ← PUSH
      NotificationService.startRealtime(); // ← live bell badge
    } else {
      await ChatService.I.init();
    }
  } catch (_) {}

  Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    final user = data.session?.user;
    if (user != null) {
      if (user.id == wiredUid) return; // a token refresh, not a new account
      wiredUid = user.id;
      ChatService.onUserAuthenticated(user.id);
      PushService.I.registerForUser(); // ← PUSH
      NotificationService.startRealtime(); // ← live bell badge
    } else if (data.event == AuthChangeEvent.signedOut) {
      wiredUid = null;
      ChatService.onUserSignedOut();
      NotificationService.stopRealtime();
    }
  });
}

class GovPulseApp extends StatelessWidget {
  const GovPulseApp({super.key});

  /// The route the app was launched with — on web, whatever is in the address
  /// bar at load. Read once, here, because Navigator consumes it.
  static String? get _launchRoute =>
      WidgetsBinding.instance.platformDispatcher.defaultRouteName;

  @override
  Widget build(BuildContext context) {
    // ── Web: go_router owns everything ───────────────────────────────────────
    // One router, one owner of the address bar. The citizen shell is the real
    // destination now, the auth screens and /scan/<token> are real routes, and
    // the legacy table below is reached only imperatively through the
    // legacy_nav shim — so nothing else writes browser history.
    //
    // The splash is deliberately skipped on web: a 3.4s animation before every
    // F5 works directly against the reload-proof URLs this cutover exists to
    // deliver. Mobile keeps it, unchanged, below.
    //
    // The old /scan/ launch-URL branch is gone from this side too — the scan
    // page is a GoRoute now, so it survives a reload instead of only working on
    // a cold start.
    if (kIsWeb) return const GovPulseWebApp();

    // ── Mobile: the legacy Navigator 1.0 app, untouched ──────────────────────
    // ── Public scan deep link ────────────────────────────────────────────────
    // An agency officer's phone opens /#/scan/<token> straight from a printed
    // QR code. That has to bypass the whole startup flow, and specifically it
    // has to bypass the SPLASH: GovPulseSplashScreen unconditionally
    // pushReplacement()s to /login, Home, or a console once its animation
    // finishes (splash_screen.dart _navigateNext), so mounting it here would
    // load the scan page and then throw it away about three seconds later,
    // landing an unauthenticated visitor on a login form.
    //
    // Making the scan page the `home` widget avoids that entirely — the splash
    // is never built, so there is nothing to redirect. Everything else is
    // untouched: the branch is keyed on the /scan/ prefix alone, so the guest
    // flow, the newsfeed, and every normal launch still start at the splash
    // exactly as before.
    final scanToken = scanTokenFrom(_launchRoute);

    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      color: Colors.white, // ← add
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.white, // ← add
      ),
      navigatorObservers: [homeRouteObserver],
      home: scanToken != null
          ? ScanPage(token: scanToken)
          : const GovPulseSplashScreen(),
      routes: appRoutes,
      onGenerateRoute: onGenerateRoute,

      // ── Global chat bubble ───────────────────────────────────────────────
      // Lives in MaterialApp.builder so it renders above the entire Navigator.
      // chatBubbleVisible is a ValueNotifier — HomeChatBubble.showGlobal()
      // sets it to true after the first chat session.
      // The bubble itself hides when offline (via connectivity_plus listener
      // inside _HomeChatBubbleState) and shows the panel centered on screen.
      builder: (context, child) {
        return ValueListenableBuilder<bool>(
          valueListenable: chatBubbleVisible,
          builder: (ctx, visible, _) {
            return Stack(
              children: [
                child!,
                if (visible)
                  // The bubble's panel contains a TextField, which needs an
                  // Overlay ancestor for the cursor, selection handles, and
                  // IME composing region. Without this wrapper the TextField
                  // silently misbehaves — empty-field backspace can restore
                  // previously-cleared text because the IME never gets a
                  // proper reset signal.
                  Overlay(
                    initialEntries: [
                      OverlayEntry(
                        builder: (_) => HomeChatBubble(
                          onDismiss: HomeChatBubble.hideGlobal,
                        ),
                      ),
                    ],
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
