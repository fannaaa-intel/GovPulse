import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'firebase_options.dart';
import 'core/router/app_router.dart';
import 'features/onboarding/splash_screen.dart';

/// Global navigator key — used by [AuthService] to push after login.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

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
      navigatorObservers: [homeRouteObserver],
      home: const GovPulseSplashScreen(),
      routes: appRoutes,
      onGenerateRoute: onGenerateRoute,
    );
  }
}
