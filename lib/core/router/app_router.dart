import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/chat_service.dart';
import '../network/network_wrapper.dart';
import '../../features/onboarding/splash_screen.dart';
import '../../features/onboarding/intro_screen.dart';
import '../../features/onboarding/otp_loading_screen.dart';
import '../../features/auth/login_screen.dart';
import '../services/auth_service.dart';
import '../../features/auth/phone_signup_screen.dart';
import '../../features/auth/signup_screen.dart';
import '../../features/guest/screen/guest.dart';
import '../../features/Resets/reset_password_method_screen.dart';
import '../../features/Resets/reset_password_via_phone_screen.dart';
import '../../features/Resets/reset_password_email_screen.dart';
import '../../features/verification/screens/reset_password_email_verify_screen.dart';
import '../../features/verification/screens/phone_verification_screen.dart';
import '../../features/verification/screens/phone_verification_success.dart';
import '../../features/verification/screens/email_verification_success.dart';
import '../../features/home/screen/home_screen.dart';
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
import '../../features/home/my_report/report_detail_screen.dart';
import '../../features/home/Quick-action/Events/event_detail_screen.dart';
import '../../features/home/settings/change-password/change_password_send_screen.dart';
import '../../features/home/settings/change-password/change_password_verify_screen.dart';
import '../../features/home/settings/change-password/change_password_new_screen.dart';
import '../providers/user_profile_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Required by [MaterialApp.navigatorObservers] for home route tracking.
final RouteObserver<ModalRoute<void>> homeRouteObserver =
    RouteObserver<ModalRoute<void>>();

// ─── Transition helpers ───────────────────────────────────────────────────────

// Web-only fade: smooth crossfade on web, native platform transition on mobile.
// This is the ONLY helper that needs the kIsWeb guard — mobile routes are
// completely unaffected because PageRouteBuilder is only returned on web.
Route<dynamic> _webFade(Widget child) {
  if (!kIsWeb) {
    return MaterialPageRoute(builder: (_) => NetworkWrapper(child: child));
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

// Web-only fade for inline Navigator.push calls (reset password sub-screens).
// Returns a MaterialPageRoute on mobile so those flows are untouched.
Route<dynamic> _webFadeRoute(Widget child) => _webFade(child);

PageRouteBuilder _slideUp(Widget child) => PageRouteBuilder(
  transitionDuration: const Duration(milliseconds: 400),
  pageBuilder: (_, _, _) => NetworkWrapper(child: child),
  transitionsBuilder: (_, anim, _, child) => SlideTransition(
    position: Tween(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
    child: child,
  ),
);

// ─── Named routes map ─────────────────────────────────────────────────────────
// All routes that had web transition jolts are moved to onGenerateRoute below.
// appRoutes only keeps routes that truly have no transition issue (/splash).

Map<String, WidgetBuilder> get appRoutes => {
  '/splash': (_) => const GovPulseSplashScreen(),
};

// ─── onGenerateRoute ──────────────────────────────────────────────────────────

Route<dynamic>? onGenerateRoute(RouteSettings settings) {
  switch (settings.name) {
    // ── Auth flow — _webFade on web, native transition on mobile ─────────────

    case '/login':
      return _webFade(
        Builder(
          builder: (ctx) => LoginScreen(
            onLoginClick: (username, password) async {
              final usernameFromDB = await AuthService.login(
                username,
                password,
              );
              // Rebind chat storage to THIS user before Home mounts.
              final uid = Supabase.instance.client.auth.currentUser?.id;
              if (uid != null) {
                await ChatService.onUserAuthenticated(uid);
              }
              if (!ctx.mounted) return;

              // ── ADD THIS LINE ─────────────────────────────────────
              ProviderScope.containerOf(ctx).invalidate(userProfileProvider);
              // ──────────────────────────────────────────────────────

              Navigator.pushReplacement(
                ctx,
                PageRouteBuilder(
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: Duration.zero,
                  pageBuilder: (_, _, _) =>
                      NetworkWrapper(child: HomePage(username: usernameFromDB)),
                  transitionsBuilder: (_, _, _, child) => child,
                ),
              );
            },
            onSignUpClick: () => Navigator.pushNamed(ctx, '/signup'),
            onGuestClick: () async {
              await FirebaseAuth.instance.signInAnonymously();
              if (!ctx.mounted) return;
              Navigator.pushNamed(ctx, '/guest');
            },
          ),
        ),
      );

    case '/signup':
      return _webFade(
        Builder(
          builder: (ctx) => SignupScreen(
            onSignUpClick: (_, _, _) {},
            onLoginClick: () => Navigator.pushNamed(ctx, '/login'),
            onGuestClick: () async {
              await FirebaseAuth.instance.signInAnonymously();
              if (!ctx.mounted) return;
              Navigator.pushNamed(ctx, '/guest');
            },
            onPhoneClick: () => Navigator.pushNamed(ctx, '/phone_signup'),
          ),
        ),
      );

    case '/phone_signup':
      return _webFade(
        Builder(
          builder: (ctx) => PhoneSignupScreen(
            onContinueClick: (phone, password) async {
              await Navigator.push(
                ctx,
                _webFadeRoute(
                  OtpLoadingScreen(
                    type: 'phone',
                    onSendOtp: () async {
                      await Future.delayed(const Duration(seconds: 2));
                    },
                  ),
                ),
              );
              if (!ctx.mounted) return;
              Navigator.pushNamed(ctx, '/phone_verify/$phone');
            },
            onBackClick: () => Navigator.pop(ctx),
            onLoginClick: () => Navigator.pushNamed(ctx, '/login'),
          ),
        ),
      );

    case '/guest':
      return _webFade(const GuestScreen());

    case '/email_verification_success':
      final email = settings.arguments as String;
      return _webFade(EmailVerificationSuccess(email: email));

    case '/phone_verification_success':
      final phone = settings.arguments as String;
      return _webFade(PhoneVerificationSuccess(phone: phone));

    // ── Reset password — sub-screens also use _webFadeRoute inline ───────────

    case '/reset_password':
      return _webFade(
        Builder(
          builder: (ctx) => ResetPasswordMethodScreen(
            onEmailTap: () {
              Navigator.push(
                ctx,
                _webFadeRoute(
                  Builder(
                    builder: (ctx2) => ResetPasswordEmailScreen(
                      onVerify: () {
                        Navigator.push(
                          ctx2,
                          _webFadeRoute(
                            ResetPasswordEmailVerifyScreen(
                              email: '',
                              onVerifiedSuccess: () {},
                              onTermsClick: () {},
                              onConditionsClick: () {},
                            ),
                          ),
                        );
                      },
                      onLogin: () => Navigator.pushNamed(ctx2, '/login'),
                    ),
                  ),
                ),
              );
            },
            onPhoneTap: () {
              Navigator.push(
                ctx,
                _webFadeRoute(
                  Builder(
                    builder: (ctx2) => ResetPasswordPhoneScreen(
                      onVerify: () {},
                      onLogin: () => Navigator.pushNamed(ctx2, '/login'),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
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
            onLoginClick: () => Navigator.pushReplacementNamed(ctx, '/login'),
            onSignUpClick: () => Navigator.pushReplacementNamed(ctx, '/signup'),
          ),
        ),
      );

    // ── Home sub-screens — keep their original slide/slideUp transitions ─────

    case '/newsfeed':
      final args = settings.arguments;
      String username = '';
      bool isVerified = false;
      if (args is Map<String, dynamic>) {
        username = args['username'] as String? ?? '';
        isVerified = args['isVerified'] as bool? ?? false;
      } else if (args is String) {
        username = args;
      }
      return _instant(
        NewsFeedScreen(username: username, isVerified: isVerified),
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
          // ← updated
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
        transitionDuration: const Duration(milliseconds: 420), // ← updated
        reverseTransitionDuration: const Duration(milliseconds: 300),
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
        transitionsBuilder: (_, anim, _, child) => SlideTransition(
          // ← updated
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
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
        transitionDuration: Duration.zero, // instant in
        reverseTransitionDuration: const Duration(
          milliseconds: 300,
        ), // fade out
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
      if (settings.name != null &&
          settings.name!.startsWith('/phone_verify/')) {
        final phone = settings.name!.split('/').last;
        return _webFade(
          PhoneVerificationScreen(
            phone: phone,
            onTermsClick: () {},
            onConditionsClick: () {},
          ),
        );
      }
      return null;
  }
}
