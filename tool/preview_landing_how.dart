// Boots ONLY the landing page's How it Works section, so its three step rows
// can be looked at across widths without the rest of the page.
//
// Same reason as tool/preview_landing_features.dart: the section is art beside
// copy at a ratio that changes with the viewport, and `flutter analyze` plus the
// widget tests pass happily on a row whose art has collapsed or whose copy has
// been squeezed to two words a line. Only a screenshot shows that.
//
// Run:
//     flutter build web --release -t tool/preview_landing_how.dart
//     python -m http.server 57830 --directory build/web
import 'package:flutter/material.dart';

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
              body: SingleChildScrollView(child: LandingHowItWorks()),
            ),
          );
        },
      ),
    );
  }
}
