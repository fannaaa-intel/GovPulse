// Dev-only harness that boots the REAL public landing page.
//
//   flutter build web --release -t tool/preview_landing_full.dart
//
// The live page is reachable at '/' in the app, but only through the full
// router, which needs Supabase, Firebase and a settled AuthRestoration before
// it will paint anything. This mounts [LandingPage] directly so the page can be
// looked at — which is the point: a 404 has to be designed against what the
// landing page ACTUALLY renders, not against a reading of its token file.
//
// LandingPage is self-chroming (its own nav, hero, sections and footer) and
// takes no arguments, so nothing else is needed here.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:govpulse/features/landing/landing_page.dart';

void main() => runApp(const ProviderScope(child: _PreviewApp()));

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'GovPulse — landing',
      home: LandingPage(),
    );
  }
}
