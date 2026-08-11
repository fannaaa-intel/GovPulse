import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
// context.go for the admin/staff console routes. Web-only in effect — every
// use sits inside an if (kIsWeb), and on mobile this file runs under the legacy
// MaterialApp where there is no GoRouter to resolve against.
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/chat_service.dart';
import '../network/network_wrapper.dart';
import 'legacy_nav.dart';
import '../widgets/app_snackbar.dart';
import '../../features/onboarding/splash_screen.dart';
import '../../features/onboarding/intro_screen.dart';
import '../../features/auth/login_screen.dart';
import '../services/auth_service.dart';
import '../../features/auth/signup_screen.dart';
import '../../features/guest/screen/guest.dart';
import '../../features/Resets/reset_password_email_screen.dart';
import '../../features/verification/screens/email_verification_success.dart';
import '../../features/home/newsfeed/news_feed_screen.dart';
import '../../features/home/settings/settings_screen.dart';
import '../../features/home/settings/edit_profile_screen.dart';
import '../../features/home/emergency/emergency_screen.dart';
import '../../features/home/Quick-action/Report/report_issue_screen.dart';
import '../../features/profileVerification/verification_screen.dart';
import '../../features/profileVerification/verification_id_selection_screen.dart';
import '../../features/profileVerification/verification_photo_instruction_screen.dart';
import '../../features/profileVerification/verification_upload_id_screen.dart';
import '../../features/profileVerification/verification_scan_screen.dart';
import '../../features/profileVerification/verification_review_screen.dart';
import '../../features/profileVerification/verification_identity_screen.dart';
import '../../features/profileVerification/verification_face_scan_screen.dart';
import '../../features/home/my_report/my_reports_screen.dart';
import '../../features/home/Quick-action/Chat-with-Agent/chat_agent_screen.dart';
import '../../features/home/Quick-action/Events/events_screen.dart';
import '../../features/home/Quick-action/Suggestion/suggestion_screen.dart';
import '../../features/home/Quick-action/Feedback/feedback_screen.dart';
import '../../features/home/my_report/report_detail_screen.dart';
import '../../features/home/Quick-action/Events/event_detail_screen.dart';
import '../../features/home/settings/change-password/change_password_send_screen.dart';
import '../../features/home/settings/change-password/change_password_verify_screen.dart';
import '../../features/home/settings/change-password/change_password_new_screen.dart';
import '../providers/user_profile_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/home/settings/my-submission/my_submissions_screen.dart';
import '../../features/home/settings/contact-support/contact_support_screen.dart';
import '../providers/community_posts_provider.dart';
import '../../features/home/settings/terms-of-service/terms_of_service_screen.dart';
import '../../features/home/settings/privacy-policy/privacy_policy_screen.dart';
import '../../features/home/settings/about/about_govpulse_screen.dart';
import '../../features/admin/screens/admin_dashboard_screen.dart';
import '../../features/staff/screens/staff_console_screen.dart';
import '../../features/scan/scan_page.dart';

/// Required by [MaterialApp.navigatorObservers] for home route tracking.
final RouteObserver<ModalRoute<void>> homeRouteObserver =
    RouteObserver<ModalRoute<void>>();

// ─── Transition helpers ───────────────────────────────────────────────────────

// Web-only fade: smooth crossfade on web, native platform transition on mobile.
// This is the ONLY helper that needs the kIsWeb guard — mobile routes are
// completely unaffected because PageRouteBuilder is only returned on web.
Route<dynamic> _webFade(Widget child) {
  if (!kIsWeb) {
    // Instant on mobile — avoids the slide-from-right "flick" between
    // reset-password method/email/phone/verify screens. Content-level
    // slide-up (if any) is handled by the screen's own AnimationController.
    return PageRouteBuilder(
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => NetworkWrapper(child: child),
      transitionsBuilder: (_, _, _, child) => child,
    );
  }
  return PageRouteBuilder(
    transitionDuration: const Duration(milliseconds: 200),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (_, _, _) => NetworkWrapper(child: child),
    transitionsBuilder: (_, anim, _, child) =>
        FadeTransition(opacity: anim, child: child),
  );
}

PageRouteBuilder _instant(Widget child) => PageRouteBuilder(
  transitionDuration: Duration.zero,
  reverseTransitionDuration: Duration.zero,
  pageBuilder: (_, _, _) => NetworkWrapper(child: child),
  transitionsBuilder: (_, _, _, child) => child,
);

// ── Instant push, fade-out on back ────────────────────────────────────────
// Used by reset-password method/email/phone sub-screens: entry is instant
// (content slide-up handled by the screen's own AnimationController), but
// popping back fades the screen out.
PageRouteBuilder _instantInFadeOut(Widget child) => PageRouteBuilder(
  transitionDuration: Duration.zero,
  reverseTransitionDuration: const Duration(milliseconds: 220),
  pageBuilder: (_, _, _) => NetworkWrapper(child: child),
  transitionsBuilder: (_, anim, _, child) =>
      FadeTransition(opacity: anim, child: child),
);

// ── Slide-up: used by quick-action screens (report, suggestion, chat, feedback)
// Entry  : entire screen slides up from bottom (400 ms, easeOutCubic)
// Reverse: instant back-fade handled by the screen's own AnimationController
PageRouteBuilder _slideUp(Widget child) => PageRouteBuilder(
  // Entry is instant at the router level — the screen's AnimationController
  // does the real slide-up of content so there is no double-slide.
  transitionDuration: Duration.zero,
  reverseTransitionDuration: const Duration(milliseconds: 300),
  pageBuilder: (_, _, _) => NetworkWrapper(child: child),
  transitionsBuilder: (_, anim, _, child) =>
      FadeTransition(opacity: anim, child: child),
);

// ─── Named routes map ─────────────────────────────────────────────────────────
// All routes that had web transition jolts are moved to onGenerateRoute below.
// appRoutes only keeps routes that truly have no transition issue (/splash).

Map<String, WidgetBuilder> get appRoutes => {
  '/splash': (_) => const GovPulseSplashScreen(),
};

// ─── onGenerateRoute ──────────────────────────────────────────────────────────

/// URL prefix of the public endorsement scan page. A token is appended.
const String kScanRoutePrefix = '/scan/';

/// The token in `/scan/<token>`, or null when [name] is not a scan route.
///
/// Shared by the router and by `main()`, which has to recognise the deep link
/// BEFORE the app is built — see the note on [onGenerateRoute]'s scan case.
String? scanTokenFrom(String? name) {
  if (name == null || !name.startsWith(kScanRoutePrefix)) return null;
  final token = name.substring(kScanRoutePrefix.length);
  // Strip a query string or trailing slash a scanner or share sheet may append.
  final clean = token.split('?').first.split('#').first.replaceAll('/', '');
  return clean.isEmpty ? null : clean;
}

// ─── Auth screen builders ─────────────────────────────────────────────────────
//
// Extracted from the switch below so go_router can mount the SAME screens with
// the SAME callbacks. There is exactly one definition of what /login and
// /signup do — the two routers differ only in how they wrap it, and the one
// genuinely per-platform bit (where an authenticated citizen lands) is handled
// inside [goToCitizenHome]: the shell on web, HomePage on mobile.
//
// Admin and staff used to keep their imperative pushes, on the reasoning that
// those "work unchanged under either Navigator". That was wrong on web: an
// imperative push lands a pageless route over go_router's stack, and the auth
// guard — which sees a session and concludes citizen — then redirects the whole
// thing to /home. Both consoles therefore go through their own routes on web
// now, and keep the push on mobile.

Widget buildLoginScreen(BuildContext ctx) => LoginScreen(
  onLoginClick: (username, password) async {
    final result = await AuthService.login(username, password);
    // Rebind chat storage to THIS user before Home mounts.
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid != null) {
      await ChatService.onUserAuthenticated(uid);
    }
    if (!ctx.mounted) return;
    CommunityPostsProvider.instance.resetForAuthenticatedUser();
    ProviderScope.containerOf(ctx).invalidate(userProfileProvider);

    // Role-based routing
    // 1 = admin  → admin dashboard (web & mobile)
    // 2 = staff  → staff console (helpdesk: chat, reports, endorsements)
    // 3 = citizen, null = unverified → home
    if (result.roleId == 1) {
      // Web: a real route, so the console survives a reload and the guard has
      // something to send an admin BACK to. Path literals rather than shared
      // constants, matching how legacy_nav keeps its own copies of '/login' and
      // friends — the route declarations live in citizen_shell_router.dart.
      //
      // Returning early rather than wrapping the push in an else: it leaves the
      // mobile arm below untouched, indentation included.
      if (kIsWeb) {
        ctx.go('/admin');
        return;
      }
      Navigator.pushReplacement(
        ctx,
        PageRouteBuilder(
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, _, _) =>
              const NetworkWrapper(child: AdminDashboardScreen()),
          transitionsBuilder: (_, _, _, child) => child,
        ),
      );
    } else if (result.roleId == 2) {
      if (kIsWeb) {
        ctx.go('/staff');
        return;
      }
      Navigator.pushReplacement(
        ctx,
        PageRouteBuilder(
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, _, _) =>
              const NetworkWrapper(child: StaffConsoleScreen()),
          transitionsBuilder: (_, _, _, child) => child,
        ),
      );
    } else {
      goToCitizenHome(ctx, username: result.username);
    }
  },
  onSignUpClick: () => goToSignup(ctx),
  onGuestClick: () async {
    await FirebaseAuth.instance.signInAnonymously();
    if (!ctx.mounted) return;
    goToGuest(ctx);
  },
  onFacebookClick: () async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || !ctx.mounted) return;
    final row = await Supabase.instance.client
        .from('profiles')
        .select('username')
        .eq('id', user.id)
        .maybeSingle();
    final username = (row?['username'] as String?) ?? '';
    if (!ctx.mounted) return;
    CommunityPostsProvider.instance.resetForAuthenticatedUser();
    ProviderScope.containerOf(ctx).invalidate(userProfileProvider);
    goToCitizenHome(ctx, username: username, clearStack: true);
    // Root-overlay toast — survives the jump into Home.
    showAppSnackBar(
      ctx,
      'Signed in with Facebook. Welcome back!',
      type: AppSnackType.success,
    );
  },
);

Widget buildSignupScreen(BuildContext ctx) => SignupScreen(
  onSignUpClick: (_, _, _) {},
  // clearStack: false — moving between the two auth screens is ordinary
  // navigation, not a sign-out. On mobile this stays the plain push it was.
  onLoginClick: () => goToLogin(ctx, clearStack: false),
  // DEAD as wired today: signup_screen.dart never reads `onGuestClick`, it
  // calls its own _goToGuest(). Converted anyway so the two guest callbacks
  // cannot drift — if this one is ever wired up it will already be correct.
  onGuestClick: () async {
    await FirebaseAuth.instance.signInAnonymously();
    if (!ctx.mounted) return;
    goToGuest(ctx);
  },
  onFacebookClick: () async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || !ctx.mounted) return;
    // Get username from profiles table (just set by picker screen)
    final row = await Supabase.instance.client
        .from('profiles')
        .select('username')
        .eq('id', user.id)
        .maybeSingle();
    final username = (row?['username'] as String?) ?? '';
    if (!ctx.mounted) return;
    CommunityPostsProvider.instance.resetForAuthenticatedUser();
    ProviderScope.containerOf(ctx).invalidate(userProfileProvider);
    goToCitizenHome(ctx, username: username, clearStack: true);
    // Root-overlay toast — survives the jump into Home.
    showAppSnackBar(
      ctx,
      'Welcome to GovPulse! Your account is ready.',
      type: AppSnackType.success,
    );
  },
);

Route<dynamic>? onGenerateRoute(RouteSettings settings) {
  // ── Public endorsement scan page ───────────────────────────────────────────
  // Matched by PREFIX, before anything else, because the token is part of the
  // path and the switch below can only compare whole route names.
  //
  // It must also come before the argRequiredRoutes guard: that guard sends
  // argument-less routes to the splash, and the splash then redirects to
  // login — which for an unauthenticated agency officer scanning a QR code is
  // exactly the wrong destination.
  //
  // No NetworkWrapper, unlike every other route here. NetworkWrapper is built
  // for signed-in users; this page has no session, and its own error states
  // already cover being offline.
  final scanToken = scanTokenFrom(settings.name);
  if (scanToken != null) {
    return PageRouteBuilder(
      settings: settings,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => ScanPage(token: scanToken),
      transitionsBuilder: (_, _, _, child) => child,
    );
  }

  // ── Web refresh / deep-link safety ─────────────────────────────────────────
  // These routes carry in-memory arguments (verification wizard data, password
  // reset tokens) that are LOST when the browser is refreshed directly on that
  // URL. Without this guard the `settings.arguments as Map<String, dynamic>`
  // casts below throw a null TypeError and white-screen the app. When the
  // arguments are missing we send the user to the splash screen (which
  // re-routes them to Home / Login) instead of crashing. The mobile app never
  // hits this — it always navigates with arguments in memory — so its
  // behaviour is unchanged.
  //
  // /report_detail and /event_detail USED to be here. They are not any more:
  // go_router owns the web URL now, so a route NAME can never be a launch
  // location, and the shell's id-addressable /my-reports/detail/:id and
  // /home/event/:id rebuild their subject from the id via ResolveById instead
  // of needing a bounce. What remains is the set that genuinely cannot be made
  // id-addressable — six wizard steps that pass Uint8List ID images between
  // them, and a password reset that carries auth tokens — so for those a
  // restart really is the only correct answer to a refresh.
  const argRequiredRoutes = <String>{
    '/verification_photo_instruction',
    '/verification_upload_id',
    '/verification_scan',
    '/verification_review',
    '/verification_identity',
    '/verification_face_scan',
    '/change_password_new',
  };
  if (argRequiredRoutes.contains(settings.name) &&
      settings.arguments is! Map<String, dynamic>) {
    return _instant(const GovPulseSplashScreen());
  }

  switch (settings.name) {
    // ── Auth flow ────────────────────────────────────────────────────────────
    // /login, /signup use _instantInFadeOut:
    //  - Entry is instant on all platforms — each screen's own
    //    _entranceController plays the fade + slide-up of its content.
    //  - Reverse (back navigation) fades the whole screen out over 220ms.

    case '/login':
      return _instantInFadeOut(Builder(builder: buildLoginScreen));

    case '/signup':
      return _instantInFadeOut(Builder(builder: buildSignupScreen));

    case '/guest':
      return _instantInFadeOut(const GuestScreen());

    case '/email_verification_success':
      final email = settings.arguments as String;
      return _instantInFadeOut(EmailVerificationSuccess(email: email));

    // ── Reset password ───────────────────────────────────────────────────────
    // Only the ENTRY screen is routed here. Its sub-screens — the OTP verify
    // step and the new-password step — are pushed imperatively by the screens
    // themselves, each building its own route inline. An earlier note here
    // claimed they shared a `_webFadeRoute` helper from this file; they never
    // did, and that helper is gone.

    case '/reset_password':
      return PageRouteBuilder(
        // Forward: instant — content slide-up handled by the screen itself.
        transitionDuration: Duration.zero,
        // Back (to login): fade out.
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, _, _) => NetworkWrapper(
          child: Builder(
            builder: (ctx) => ResetPasswordEmailScreen(
              // clearStack: false — mobile's branch is then pushLegacy(ctx,
              // '/login'), character-for-character what this line used to be.
              // Web gains the pageless-stack clear that /login now goes
              // through; see [goToLogin].
              onLogin: () => goToLogin(ctx, clearStack: false),
            ),
          ),
        ),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      );

    // ── Verification ─────────────────────────────────────────────────────────

    case '/verification':
      final username = settings.arguments as String;
      return PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, _, _) =>
            NetworkWrapper(child: VerificationScreen(username: username)),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      );

    case '/verification_id_selection':
      final username = settings.arguments as String;
      return PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, _, _) => NetworkWrapper(
          child: VerificationIdSelectionScreen(username: username),
        ),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      );

    // ── Intro ────────────────────────────────────────────────────────────────

    case '/intro':
      return _webFade(
        Builder(
          builder: (ctx) => IntroScreen(
            onLoginClick: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('seenOnboarding', true);
              if (!ctx.mounted) return;
              pushReplacementLegacy(ctx, '/login');
            },
            onSignUpClick: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('seenOnboarding', true);
              if (!ctx.mounted) return;
              pushReplacementLegacy(ctx, '/signup');
            },
          ),
        ),
      );

    // ── Home sub-screens ─────────────────────────────────────────────────────

    case '/newsfeed':
      final args = settings.arguments;
      String username = '';
      bool isVerified = false;
      String? userBarangay;
      bool isGuest = false;
      String? initialPostId;
      bool initialOpenComments = false;
      bool initialHighlightPost = false;
      if (args is Map<String, dynamic>) {
        username = args['username'] as String? ?? '';
        isVerified = args['isVerified'] as bool? ?? false;
        userBarangay = args['userBarangay'] as String?;
        isGuest = args['isGuest'] as bool? ?? false;
        initialPostId = args['initialPostId'] as String?;
        initialOpenComments = args['initialOpenComments'] as bool? ?? false;
        initialHighlightPost = args['initialHighlightPost'] as bool? ?? false;
      } else if (args is String) {
        username = args;
      }
      return PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (_, _, _) => NetworkWrapper(
          child: NewsFeedScreen(
            username: username,
            isVerified: isVerified,
            userBarangay: userBarangay,
            isGuest: isGuest,
            initialPostId: initialPostId,
            initialOpenComments: initialOpenComments,
            initialHighlightPost: initialHighlightPost,
          ),
        ),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      );

    case '/settings':
      final username = settings.arguments as String? ?? '';
      return _instant(SettingScreen(username: username));

    case '/edit_profile':
      final username = settings.arguments as String? ?? '';
      return PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, _, _) =>
            NetworkWrapper(child: EditProfileScreen(username: username)),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      );

    case '/report':
      final username = settings.arguments as String? ?? '';
      return _slideUp(ReportIssueScreen(username: username));

    case '/suggestion':
      final username = settings.arguments as String? ?? '';
      return _slideUp(SuggestionScreen(username: username));

    // ─── FEEDBACK — instant push, content slides up internally ───────────────
    case '/feedback':
      final username = settings.arguments as String? ?? '';
      return _slideUp(FeedbackScreen(username: username));
    // ─────────────────────────────────────────────────────────────────────────

    case '/my_reports':
      final username = settings.arguments as String? ?? '';
      return _instant(MyReportsScreen(username: username));

    case '/report_detail':
      final args = settings.arguments as Map<String, dynamic>;
      return PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, _, _) => NetworkWrapper(
          child: ReportDetailScreen(
            report: args['report'] as ReportItem,
            username: args['username'] as String,
          ),
        ),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      );

    case '/chat':
      final username = settings.arguments as String? ?? '';
      return _slideUp(ChatAgentScreen(username: username));

    case '/emergency':
      final args = settings.arguments;
      String username = '';
      bool isVerified = false;
      if (args is Map<String, dynamic>) {
        username = args['username'] as String? ?? '';
        isVerified = args['isVerified'] as bool? ?? false;
      } else if (args is String) {
        username = args;
      }
      return PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => username.isEmpty
            ? EmergencyScreen(username: username, isVerified: isVerified)
            : NetworkWrapper(
                child: EmergencyScreen(
                  username: username,
                  isVerified: isVerified,
                ),
              ),
        transitionsBuilder: (_, _, _, child) => child,
      );

    case '/events':
      final args = settings.arguments as Map<String, dynamic>? ?? {};
      return PageRouteBuilder(
        settings: settings,
        transitionDuration: const Duration(milliseconds: 420),
        pageBuilder: (_, _, _) => NetworkWrapper(
          child: EventsScreen(
            username: args['username'] as String? ?? '',
            isVerified: args['isVerified'] as bool? ?? false,
          ),
        ),
        transitionsBuilder: (_, anim, _, child) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
      );

    // ── Profile verification flow ─────────────────────────────────────────────

    case '/verification_photo_instruction':
      final args = settings.arguments as Map<String, dynamic>;
      return PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, _, _) => NetworkWrapper(
          child: VerificationPhotoInstructionScreen(
            username: args['username'] as String,
            selectedId: args['selectedId'] as String,
          ),
        ),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      );

    case '/verification_upload_id':
      final args = settings.arguments as Map<String, dynamic>;
      return PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, _, _) => NetworkWrapper(
          child: VerificationUploadIdScreen(
            username: args['username'] as String,
            selectedId: args['selectedId'] as String,
          ),
        ),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      );

    case '/verification_scan':
      final args = settings.arguments as Map<String, dynamic>;
      return PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, _, _) => NetworkWrapper(
          child: VerificationScanScreen(
            username: args['username'] as String,
            selectedId: args['selectedId'] as String,
          ),
        ),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      );

    case '/verification_review':
      final args = settings.arguments as Map<String, dynamic>;
      return PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 420),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, _, _) => NetworkWrapper(
          child: VerificationReviewScreen(
            username: args['username'] as String,
            selectedId: args['selectedId'] as String,
            frontImage: args['frontImage'] as Uint8List?,
            backImage: args['backImage'] as Uint8List?,
            extractedData: args['extractedData'] as Map<String, String>?,
          ),
        ),
        transitionsBuilder: (_, anim, _, child) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
      );

    case '/verification_identity':
      final args = settings.arguments as Map<String, dynamic>;
      return PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, _, _) => NetworkWrapper(
          child: VerificationIdentityScreen(
            username: args['username'] as String,
            selectedId: args['selectedId'] as String,
            idNumber: args['idNumber'] as String,
            firstName: args['firstName'] as String,
            middleName: args['middleName'] as String,
            lastName: args['lastName'] as String,
            suffix: args['suffix'] as String?,
            gender: args['gender'] as String,
            birthdate: args['birthdate'] as String,
            birthplace: args['birthplace'] as String,
            civilStatus: args['civilStatus'] as String,
            contactNumber: args['contactNumber'] as String,
            barangay: args['barangay'] as String,
            street: args['street'] as String,
            frontImage: args['frontImage'] as Uint8List?,
            backImage: args['backImage'] as Uint8List?,
          ),
        ),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      );

    case '/verification_face_scan':
      final args = settings.arguments as Map<String, dynamic>;
      return PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, _, _) => NetworkWrapper(
          child: VerificationFaceScanScreen(
            username: args['username'] as String,
            selectedId: args['selectedId'] as String,
            idNumber: args['idNumber'] as String,
            firstName: args['firstName'] as String,
            middleName: args['middleName'] as String,
            lastName: args['lastName'] as String,
            suffix: args['suffix'] as String?,
            gender: args['gender'] as String,
            birthdate: args['birthdate'] as String,
            birthplace: args['birthplace'] as String,
            civilStatus: args['civilStatus'] as String,
            contactNumber: args['contactNumber'] as String,
            barangay: args['barangay'] as String,
            street: args['street'] as String,
            frontImage: args['frontImage'] as Uint8List?,
            backImage: args['backImage'] as Uint8List?,
          ),
        ),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      );

    case '/event_detail':
      final args = settings.arguments as Map<String, dynamic>;
      return PageRouteBuilder(
        settings: settings,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, _, _) => NetworkWrapper(
          child: EventDetailScreen(
            event: args['event'] as EventItem,
            username: args['username'] as String? ?? '',
          ),
        ),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      );

    case '/change_password':
      final email = settings.arguments as String;
      return PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (_, _, _) =>
            NetworkWrapper(child: ChangePasswordSendScreen(email: email)),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      );

    case '/my_submissions':
      // Accepts either a bare username String (Settings entry) or a richer
      // MySubmissionsArgs (a reply notification deep-linking to a tab + item).
      final subArgs = settings.arguments;
      final MySubmissionsArgs mySubs = subArgs is MySubmissionsArgs
          ? subArgs
          : MySubmissionsArgs(username: subArgs as String? ?? '');
      return PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (_, _, _) => NetworkWrapper(
          child: MySubmissionsScreen(
            username: mySubs.username,
            initialTab: mySubs.initialTab,
            highlightId: mySubs.highlightId,
          ),
        ),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      );

    case '/contact_support':
      final username = settings.arguments as String? ?? '';
      return PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (_, _, _) =>
            NetworkWrapper(child: ContactSupportScreen(username: username)),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      );

    case '/terms_of_service':
      return PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (_, _, _) =>
            NetworkWrapper(child: const TermsOfServiceScreen()),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      );

    case '/privacy_policy':
      return PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (_, _, _) => const PrivacyPolicyScreen(),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      );

    case '/about':
      return PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (_, _, _) => const AboutGovPulseScreen(),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      );

    case '/change_password_verify':
      final email = settings.arguments as String;
      return PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (_, _, _) =>
            NetworkWrapper(child: ChangePasswordVerifyScreen(email: email)),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      );

    case '/change_password_new':
      final args = settings.arguments as Map<String, dynamic>;
      return PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (_, _, _) => NetworkWrapper(
          child: ChangePasswordNewScreen(
            accessToken: args['accessToken'] as String,
            refreshToken: args['refreshToken'] as String,
          ),
        ),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      );

    // ── Dynamic phone verify route ────────────────────────────────────────────

    default:
      return null;
  }
}
