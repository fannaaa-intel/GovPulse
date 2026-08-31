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
import 'core/theme/app_colors.dart';

import 'firebase_options.dart';
import 'core/router/app_router.dart';
import 'features/onboarding/splash_screen.dart';
import 'features/home/shell/citizen_shell_router.dart' show GovPulseWebApp;
import 'core/services/auth_ready.dart' show AuthRestoration;
import 'core/network/timeout_http_client.dart';
import 'core/services/session_cache.dart';
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
    // Without this every query inherits Dart's default: a connection timeout,
    // but no ceiling on how long an ESTABLISHED connection may stay silent. On
    // a weak-but-live network the socket connects — so the reachability probe
    // reports "online" — and the request then never answers, which is what
    // left login, the citizen home and both consoles on a spinner or skeleton
    // that never resolved. See [TimeoutHttpClient].
    httpClient: TimeoutHttpClient(),
  );

  await Hive.initFlutter();

  // Drops the pre-fix unscoped chat boxes, which could hold one account's
  // messages where the next account (or a signed-out visitor) would read them.
  // Before any bind, so it can never delete a box the live session is using.
  await ChatService.purgeLegacyUnscopedBoxes();

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

  // Both platforms, for two different reasons.
  //
  // MOBILE: pulls the cached username + role into memory before the first
  // frame, so the splash can pick a destination for a restored session WITHOUT
  // the network. Without it the splash had to query for both, which meant an
  // offline start could not route a user who was still signed in.
  //
  // WEB: routing is the router guard's job and this cache stays out of it —
  // but the DISPLAY hints (verification status, name, photo, staff identity)
  // are read on web too, and a failed fetch there falls back to the same wrong
  // defaults it did on mobile: 'unverified' for a citizen, 'Staff' for a staff
  // member. They cannot be read if nothing loaded them.
  await SessionCache.instance.prime();

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

/// The app's one theme.
///
/// [MaterialScrollBehavior] that scrolls exactly as the default does but paints
/// no scrollbar, applied app-wide from [MaterialApp.scrollBehavior].
///
/// Only [buildScrollbar] is overridden: wheel, trackpad, drag and keyboard
/// scrolling are untouched, and so are the physics and the overscroll
/// indicator. The bar goes, the scrolling stays.
///
/// This supersedes the two local copies that existed first — `_NoDrawerScrollbar`
/// in home_nav_drawer.dart and the `ScrollConfiguration` in
/// quick_action_split_panel.dart. Both are now redundant rather than wrong;
/// they are left in place because each is scoped and harmless, and deleting a
/// working guard to prove a point is how a regression gets in.
class _NoScrollbars extends MaterialScrollBehavior {
  const _NoScrollbars();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}

/// Until this existed, `MaterialApp` was handed a bare `ThemeData()`, which in
/// Material 3 builds a colour scheme seeded from Flutter's DEFAULT purple — not
/// from our blue. Every widget that takes its background from a scheme role
/// rather than an explicit colour therefore rendered lavender: `surface` came
/// out #FEF7FF and `surfaceContainer` #F3EDF7. That is why the account menu
/// (admin and staff), the row overflow menus and the dropdowns all looked
/// faintly pink against otherwise white pages.
///
/// Seeding from [AppColors.primaryBlue] fixes the hue, but a seeded scheme is
/// still *tinted* — M3 deliberately blends the primary into every surface. The
/// surfaces are therefore pinned to plain white/greys afterwards, which is what
/// the hand-built pages (AdminUi, CitizenUi) already assume. Doing it here, once,
/// keeps every popup consistent without touching ~700 widget call sites.
final ThemeData _appTheme = () {
  final base = ColorScheme.fromSeed(seedColor: AppColors.primaryBlue);
  final scheme = base.copyWith(
    surface: Colors.white,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Colors.white,
    surfaceContainer: Colors.white,
    surfaceContainerHigh: Colors.white,
    surfaceContainerHighest: const Color(0xFFF4F6FA),
    surfaceTint: Colors.transparent, // no elevation tint over white
  );

  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.white,
    canvasColor: Colors.white,
    // M3 elevation overlays re-introduce the tint even on a white surface;
    // these three are the widgets the tint was actually visible on.
    popupMenuTheme: const PopupMenuThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
    ),
    drawerTheme: const DrawerThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: const CardThemeData(surfaceTintColor: Colors.transparent),
    appBarTheme: const AppBarTheme(surfaceTintColor: Colors.transparent),
  );
}();

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
      theme: _appTheme,
      // ── No painted scrollbars, anywhere ──────────────────────────────────
      //
      // On desktop web Material hangs a scrollbar on every scroll view, and
      // this app is made of scroll views INSIDE cards: a report detail, a
      // staff pane, the scan page's letter. A track running down the inside
      // edge of a card reads as a seam in the card rather than as a control,
      // and on the report detail it sat directly on the rounded corner.
      //
      // Two places had already solved this locally — the citizen quick-action
      // panel and the nav drawer — each with its own copy of the same trick.
      // Setting it here retires both patterns as the app-wide default rather
      // than leaving every new scrolling surface to rediscover it.
      //
      // Only the PAINTED BAR goes. buildScrollbar is the sole override, so
      // wheel, trackpad, drag, keyboard and scrollbar-drag-free scrolling all
      // behave exactly as before — see _NoScrollbars.
      scrollBehavior: const _NoScrollbars(),
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
