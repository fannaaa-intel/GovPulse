// Boots the Features section immediately followed by How it Works, so the SEAM
// between them can be looked at.
//
// ── Why a preview of a join, not of a section ──────────────────────────────
// The features ring sizes itself from a solve constant rather than from what it
// paints, and the difference showed up as a band of empty white between the
// last labels and the next section's eyebrow. Neither section looks wrong on
// its own — landing_features and landing_how_it_works both preview fine — so
// the defect is only visible where they meet.
//
// Run:
//     flutter build web --release -t tool/preview_landing_seam.dart
//     python -m http.server 57830 --directory build/web
import 'package:flutter/material.dart';

import 'package:govpulse/features/landing/sections/landing_features.dart';
import 'package:govpulse/features/landing/sections/landing_how_it_works.dart';

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
              body: SingleChildScrollView(
                child: Column(
                  children: [LandingFeatures(), LandingHowItWorks()],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
