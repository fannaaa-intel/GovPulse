// Dev-only harness for the public 404 page.
//
//   flutter build web --release -t tool/preview_not_found.dart
//
// The real page is reached by typing a bad URL, which means going through the
// full router, Supabase, Firebase and a settled AuthRestoration. This mounts
// [NotFoundPage] directly so it can be looked at — and, more to the point, so
// it can be driven through every width without a session.
//
// A GoRouter IS still needed: the page's buttons call `context.go`, and
// `GoRouter.of` throws when there is none above the context. The routes below
// are stubs that only have to exist.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:govpulse/features/landing/not_found_page.dart';

void main() => runApp(_PreviewApp());

class _PreviewApp extends StatelessWidget {
  _PreviewApp();

  final GoRouter _router = GoRouter(
    initialLocation: '/my-reprots',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const _Stub(label: 'landing'),
      ),
      GoRoute(
        path: '/guest',
        builder: (_, _) => const _Stub(label: 'guest feed'),
      ),
      GoRoute(
        path: '/login',
        builder: (_, _) => const _Stub(label: 'login'),
      ),
    ],
    // The page under test. Reached by the initialLocation above, which
    // deliberately matches nothing.
    errorBuilder: (_, state) => NotFoundPage(location: state.uri.toString()),
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'GovPulse — 404',
      routerConfig: _router,
    );
  }
}

/// Where the 404's buttons land, so a click can be seen to have worked.
class _Stub extends StatelessWidget {
  final String label;
  const _Stub({required this.label});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Center(
        child: Text(
          'went to: $label',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
