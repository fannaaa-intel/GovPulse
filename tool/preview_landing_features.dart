// Boots ONLY the landing page's Features section, so its ring composition can
// be looked at without the rest of the page, a Supabase session, or the router.
//
// ── Why a preview target at all ────────────────────────────────────────────
// The features ring is a Stack of absolutely-positioned labels around two
// overlapping device shots. Every number in it — slot alignments, the phone
// offsets, the ring height — is a geometry judgement that a test can assert but
// only a screenshot can EVALUATE. `flutter analyze` and the widget tests pass
// happily on a ring whose labels sit on top of the phones.
//
// Run:
//     flutter build web --release -t tool/preview_landing_features.dart
//     python -m http.server 57830 --directory build/web
//
// Animations are disabled via MediaQuery, which makes every RevealOnScroll
// render its FINAL state on the first frame — see reveal_on_scroll.dart. Without
// that a headless screenshot catches the section mid-fade and everything reads
// as too faint to judge.
import 'package:flutter/material.dart';

import 'package:govpulse/features/landing/sections/landing_features.dart';

void main() => runApp(const _PreviewApp());

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Builder(
        builder: (context) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: const Scaffold(
              backgroundColor: Colors.white,
              body: SingleChildScrollView(child: LandingFeatures()),
            ),
          );
        },
      ),
    );
  }
}
