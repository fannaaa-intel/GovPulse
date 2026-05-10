import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../network/network_wrapper.dart';
import '../../features/onboarding/splash_screen.dart';
import '../../features/onboarding/intro_screen.dart';
import '../../features/onboarding/otp_loading_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/services/auth_service.dart';
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
import '../../features/home/report/report_issue_screen.dart';
import '../../features/profileVerification/verification_screen.dart';
import '../../features/profileVerification/verification_id_selection_screen.dart';
import '../../features/profileVerification/verification_photo_instruction_screen.dart';
import '../../features/profileVerification/verification_upload_id_screen.dart';
import '../../features/profileVerification/verification_scan_screen.dart';
import '../../features/profileVerification/verification_review_screen.dart';
import '../../features/profileVerification/verification_identity_screen.dart';
import '../../features/profileVerification/verification_face_scan_screen.dart';

/// Required by [MaterialApp.navigatorObservers] for home route tracking.
final RouteObserver<ModalRoute<void>> homeRouteObserver =
    RouteObserver<ModalRoute<void>>();

// ─── Transition helpers ───────────────────────────────────────────────────────

PageRouteBuilder _slide(Widget child) => PageRouteBuilder(
  transitionDuration: const Duration(milliseconds: 400),
  pageBuilder: (_, _, _) => NetworkWrapper(child: child),
  transitionsBuilder: (_, anim, _, child) => SlideTransition(
    position: Tween(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: anim, curve: Curves.easeInOut)),
    child: child,
  ),
);

PageRouteBuilder _slideFade(Widget child) => PageRouteBuilder(
  transitionDuration: const Duration(milliseconds: 400),
  pageBuilder: (_, _, _) => NetworkWrapper(child: child),
  transitionsBuilder: (_, anim, _, child) => SlideTransition(
    position: Tween(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: anim, curve: Curves.easeInOut)),
    child: FadeTransition(
      opacity: Tween<double>(begin: 0, end: 1).animate(anim),
      child: child,
    ),
  ),
);

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

Map<String, WidgetBuilder> get appRoutes => {
  '/splash': (_) => const NetworkWrapper(child: GovPulseSplashScreen()),

  '/guest': (_) => const NetworkWrapper(child: GuestScreen()),

  '/email_verification_success': (context) {
    final email = ModalRoute.of(context)!.settings.arguments as String;
    return NetworkWrapper(child: EmailVerificationSuccess(email: email));
  },

  '/phone_verification_success': (context) {
    final phone = ModalRoute.of(context)!.settings.arguments as String;
    return NetworkWrapper(child: PhoneVerificationSuccess(phone: phone));
  },

  '/reset_password': (context) => NetworkWrapper(
    child: ResetPasswordMethodScreen(
      onEmailTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ResetPasswordEmailScreen(
              onVerify: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ResetPasswordEmailVerifyScreen(
                      email: '',
                      onVerifiedSuccess: () {},
                      onTermsClick: () {},
                      onConditionsClick: () {},
                    ),
                  ),
                );
              },
              onLogin: () => Navigator.pushNamed(context, '/login'),
            ),
          ),
        );
      },
      onPhoneTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ResetPasswordPhoneScreen(
              onVerify: () {},
              onLogin: () => Navigator.pushNamed(context, '/login'),
            ),
          ),
        );
      },
    ),
  ),

  '/signup': (context) => NetworkWrapper(
    child: SignupScreen(
      onSignUpClick: (_, _, _) {},
      onLoginClick: () => Navigator.pushNamed(context, '/login'),
      onGuestClick: () async {
        await FirebaseAuth.instance.signInAnonymously();
        if (!context.mounted) return;
        Navigator.pushNamed(context, '/guest');
      },
      onPhoneClick: () => Navigator.pushNamed(context, '/phone_signup'),
    ),
  ),

  '/phone_signup': (context) => NetworkWrapper(
    child: PhoneSignupScreen(
      onContinueClick: (phone, password) async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OtpLoadingScreen(
              type: 'phone',
              onSendOtp: () async {
                await Future.delayed(const Duration(seconds: 2));
              },
            ),
          ),
        );
        if (!context.mounted) return;
        Navigator.pushNamed(context, '/phone_verify/$phone');
      },
      onBackClick: () => Navigator.pop(context),
      onLoginClick: () => Navigator.pushNamed(context, '/login'),
    ),
  ),

  '/login': (context) => NetworkWrapper(
    child: LoginScreen(
      onLoginClick: (username, password) async {
        final usernameFromDB = await AuthService.login(username, password);
        if (!context.mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) =>
                NetworkWrapper(child: HomePage(username: usernameFromDB)),
          ),
        );
      },
      onSignUpClick: () => Navigator.pushNamed(context, '/signup'),
      onGuestClick: () async {
        await FirebaseAuth.instance.signInAnonymously();
        if (!context.mounted) return;
        Navigator.pushNamed(context, '/guest');
      },
    ),
  ),

  '/verification': (context) {
    final username = ModalRoute.of(context)!.settings.arguments as String;
    return NetworkWrapper(child: VerificationScreen(username: username));
  },

  '/verification_id_selection': (context) {
    final username = ModalRoute.of(context)!.settings.arguments as String;
    return NetworkWrapper(
      child: VerificationIdSelectionScreen(username: username),
    );
  },
};

// ─── onGenerateRoute ──────────────────────────────────────────────────────────

Route<dynamic>? onGenerateRoute(RouteSettings settings) {
  switch (settings.name) {
    case '/intro':
      return _slide(IntroScreen(onSignUpClick: () {}, onLoginClick: () {}));

    case '/newsfeed':
      final username = settings.arguments as String? ?? '';
      return _slide(NewsFeedScreen(username: username));

    case '/settings':
      final username = settings.arguments as String? ?? '';
      return _slide(SettingScreen(username: username));

    case '/edit_profile':
      final username = settings.arguments as String? ?? '';
      return _slide(EditProfileScreen(username: username));

    case '/emergency':
      final username = settings.arguments as String? ?? '';
      return _slide(EmergencyScreen(username: username));

    case '/report':
      final username = settings.arguments as String? ?? '';
      return _slideUp(ReportIssueScreen(username: username));

    case '/verification_photo_instruction':
      final args = settings.arguments as Map<String, dynamic>;
      return _slide(
        VerificationPhotoInstructionScreen(
          username: args['username'] as String,
          selectedId: args['selectedId'] as String,
        ),
      );

    case '/verification_upload_id':
      final args = settings.arguments as Map<String, dynamic>;
      return _slideFade(
        VerificationUploadIdScreen(
          username: args['username'] as String,
          selectedId: args['selectedId'] as String,
        ),
      );

    case '/verification_scan':
      final args = settings.arguments as Map<String, dynamic>;
      return _slideFade(
        VerificationScanScreen(
          username: args['username'] as String,
          selectedId: args['selectedId'] as String,
        ),
      );

    case '/verification_review':
      final args = settings.arguments as Map<String, dynamic>;
      return _slide(
        VerificationReviewScreen(
          username: args['username'] as String,
          selectedId: args['selectedId'] as String,
          frontImage: args['frontImage'] as Uint8List?,
          backImage: args['backImage'] as Uint8List?,
        ),
      );

    case '/verification_identity':
      final args = settings.arguments as Map<String, dynamic>;
      return _slideFade(
        VerificationIdentityScreen(
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
      );

    case '/verification_face_scan':
      final args = settings.arguments as Map<String, dynamic>;
      return _slideFade(
        VerificationFaceScanScreen(
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
      );

    default:
      if (settings.name != null &&
          settings.name!.startsWith('/phone_verify/')) {
        final phone = settings.name!.split('/').last;
        return MaterialPageRoute(
          builder: (_) => NetworkWrapper(
            child: PhoneVerificationScreen(
              phone: phone,
              onTermsClick: () {},
              onConditionsClick: () {},
            ),
          ),
        );
      }
      return null;
  }
}
