import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'firebase_options.dart';
import 'core/router/app_router.dart';
import 'features/onboarding/splash_screen.dart';
import 'core/widgets/Home/Chat-bubbles/home_chat_bubble.dart';
import 'features/auth/services/chat_service.dart';

/// Global navigator key — used by [AuthService] to push after login.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await Supabase.initialize(
    url: 'https://vxvflhjbafqwehuxnmeq.supabase.co',
    anonKey: 'sb_publishable_ZBDaQPQdFyC5kOHGbce9Ig_zdtIi6Mo',
  );

  // ── Chat cache (Hive) ─────────────────────────────────────────────────────
  // Hive stores the LGU chat conversation locally so it survives app restarts.
  // ChatService.I.init() loads cached messages and, if there are none,
  // kicks off the bot greeting + category prompt.
  // On logout, call ChatService.I.clearOnLogout() to wipe the box.
  await Hive.initFlutter();
  await ChatService.I.init();

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
