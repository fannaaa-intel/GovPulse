import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'firebase_options.dart';
import 'core/network/no_internet_screen.dart';

// Screens
import 'features/onboarding/splash_screen.dart';
import 'features/onboarding/intro_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/phone_signup_screen.dart';
import '../../features/verification/screens/phone_verification_screen.dart';
import '../../features/verification/screens/phone_verification_success.dart';
import '../../features/verification/screens/email_verification_success.dart';
import 'features/auth/signup_screen.dart';
import 'features/guest/screen/guest.dart';
import 'features/Resets/reset_password_method_screen.dart';
import 'features/Resets/reset_password_via_phone_screen.dart';
import 'features/Resets/reset_password_email_screen.dart';
import '../../features/verification/screens/reset_password_email_verify_screen.dart';
import 'features/onboarding/otp_loading_screen.dart';
import 'features/home/screen/home_screen.dart';

/// ✅ GLOBAL NAVIGATOR KEY
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// 🌐 INTERNET CHECK
Future<bool> _hasRealInternet() async {
  try {
    final client = HttpClient();
    final request = await client
        .getUrl(Uri.parse('https://clients3.google.com/generate_204'))
        .timeout(const Duration(seconds: 3));

    final response = await request.close();
    return response.statusCode == 204;
  } catch (_) {
    return false;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await Supabase.initialize(
    url: 'https://vxvflhjbafqwehuxnmeq.supabase.co',
    anonKey: 'sb_publishable_ZBDaQPQdFyC5kOHGbce9Ig_zdtIi6Mo',
  );

  runApp(const GovPulseApp());
}

class GovPulseApp extends StatelessWidget {
  const GovPulseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,

      /// ✅ FIX: ALWAYS USE WRAPPER (NO DIRECT NoInternetScreen)
      home: const NetworkWrapper(child: GovPulseSplashScreen()),

      routes: {
        '/splash': (context) =>
            const NetworkWrapper(child: GovPulseSplashScreen()),

        '/guest': (context) => NetworkWrapper(child: const GuestScreen()),

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
                            email: "",
                            onVerifiedSuccess: () {},
                            onTermsClick: () {},
                            onConditionsClick: () {},
                          ),
                        ),
                      );
                    },
                    onLogin: () {
                      Navigator.pushNamed(context, '/login');
                    },
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
                    onLogin: () {
                      Navigator.pushNamed(context, '/login');
                    },
                  ),
                ),
              );
            },
          ),
        ),

        '/signup': (context) => NetworkWrapper(
          child: SignupScreen(
            onSignUpClick: (_, __, ___) {},
            onLoginClick: () {
              Navigator.pushNamed(context, '/login');
            },
            onGuestClick: () async {
              await FirebaseAuth.instance.signInAnonymously();
              Navigator.pushNamed(context, '/guest');
            },
            onPhoneClick: () {
              Navigator.pushNamed(context, '/phone_signup');
            },
          ),
        ),

        '/phone_signup': (context) => NetworkWrapper(
          child: PhoneSignupScreen(
            onContinueClick: (phone, password) async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => OtpLoadingScreen(
                    type: "phone",
                    onSendOtp: () async {
                      await Future.delayed(const Duration(seconds: 2));
                    },
                  ),
                ),
              );

              Navigator.pushNamed(context, '/phone_verify/$phone');
            },
            onBackClick: () => Navigator.pop(context),
            onLoginClick: () {
              Navigator.pushNamed(context, '/login');
            },
          ),
        ),

        '/login': (context) => NetworkWrapper(
          child: LoginScreen(
            onLoginClick: (username, password) async {
              final supabase = Supabase.instance.client;

              final cleanUsername = username.trim();
              final cleanPassword = password.trim();

              if (cleanUsername.isEmpty || cleanPassword.isEmpty) {
                throw "Please enter username and password";
              }

              try {
                final result = await supabase
                    .from('profiles')
                    .select('email, username')
                    .ilike('username', '%$cleanUsername%');

                if (result.isEmpty) {
                  throw "Username not found";
                }

                final userData = result[0];
                final email = userData['email'];
                final usernameFromDB = userData['username'];

                final authResponse = await supabase.auth.signInWithPassword(
                  email: email,
                  password: cleanPassword,
                );

                if (authResponse.user == null) {
                  throw "Invalid password";
                }

                navigatorKey.currentState!.pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => NetworkWrapper(
                      child: HomePage(username: usernameFromDB),
                    ),
                  ),
                );
              } catch (e) {
                throw "Invalid username or password";
              }
            },
            onSignUpClick: () {
              Navigator.pushNamed(context, '/signup');
            },
            onGuestClick: () async {
              await FirebaseAuth.instance.signInAnonymously();
              Navigator.pushNamed(context, '/guest');
            },
          ),
        ),
      },

      onGenerateRoute: (settings) {
        if (settings.name == '/intro') {
          return MaterialPageRoute(
            builder: (_) => NetworkWrapper(
              child: IntroScreen(
                onSignUpClick: () {
                  Navigator.pushNamed(context, '/signup');
                },
                onLoginClick: () {
                  Navigator.pushNamed(context, '/login');
                },
              ),
            ),
          );
        }

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
      },
    );
  }
}

/// 🌐 NETWORK WRAPPER (INSTANT + FIXED)
class NetworkWrapper extends StatefulWidget {
  final Widget child;

  const NetworkWrapper({super.key, required this.child});

  @override
  State<NetworkWrapper> createState() => _NetworkWrapperState();
}

class _NetworkWrapperState extends State<NetworkWrapper> {
  bool? hasInternet;
  late StreamSubscription subscription;

  @override
  void initState() {
    super.initState();
    _checkInternet();

    /// ⚡ INSTANT LISTENER
    subscription = Connectivity().onConnectivityChanged.listen((_) async {
      final result = await _hasRealInternet();

      if (mounted) {
        setState(() {
          hasInternet = result;
        });
      }
    });
  }

  Future<void> _checkInternet() async {
    final result = await _hasRealInternet();
    setState(() {
      hasInternet = result;
    });
  }

  @override
  void dispose() {
    subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (hasInternet == null) {
      return const SizedBox.shrink();
    }

    return Stack(
      children: [
        widget.child,
        NoInternetScreen(
          hasInternet: hasInternet!,
          onContinue: () {
            setState(() {
              hasInternet = true;
            });
          },
        ),
      ],
    );
  }
}
