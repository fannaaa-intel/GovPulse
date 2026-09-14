// Boots the landing hero and the How-it-works band together, so the trust
// strip under the hero and the wave background behind the steps can both be
// looked at without the router or a Supabase session.
//
// Run:
//     flutter build web --release -t tool/preview_landing_hero_how.dart
//     python -m http.server 57831 --directory build/web
//
// Animations are disabled via MediaQuery so every RevealOnScroll renders its
// final state on the first frame — see reveal_on_scroll.dart.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:govpulse/features/landing/sections/landing_hero.dart';
import 'package:govpulse/features/landing/sections/landing_how_it_works.dart';

void main() => runApp(const _PreviewApp());

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    // The hero's buttons route, so a GoRouter has to exist above them even
    // though nothing here navigates.
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      routerConfig: GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: const Scaffold(
                backgroundColor: Colors.white,
                body: SingleChildScrollView(
                  child: Column(
                    children: [LandingHero(), LandingHowItWorks()],
                  ),
                ),
              ),
            ),
          ),
          GoRoute(path: '/login', builder: (_, _) => const SizedBox()),
          GoRoute(path: '/signup', builder: (_, _) => const SizedBox()),
          GoRoute(path: '/guest', builder: (_, _) => const SizedBox()),
        ],
      ),
    );
  }
}
