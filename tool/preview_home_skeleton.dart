// Preview target for the MOBILE home skeleton (SkeletonLayout.home).
//
// The skeleton is on screen for the few hundred milliseconds the profile fetch
// takes, behind a login — which is exactly why nobody has looked at it at more
// than one width. This boots it directly at a chosen viewport so its
// proportions can be checked against a real handset and against the widest
// phone the app supports.
//
// Run:
//   flutter run -d web-server --web-port 57900 -t tool/preview_home_skeleton.dart
//
// Query parameters:
//   ?w=360   viewport width to simulate (default 390)
//   &h=800   viewport height (default 844)
import 'package:flutter/material.dart';

import 'package:govpulse/core/widgets/loading/loading_overlay.dart';

void main() {
  final q = Uri.base.queryParameters;
  final w = double.tryParse(q['w'] ?? '') ?? 390;
  final h = double.tryParse(q['h'] ?? '') ?? 844;
  runApp(_PreviewApp(width: w, height: h));
}

class _PreviewApp extends StatelessWidget {
  final double width;
  final double height;
  const _PreviewApp({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFE5E7EB),
        body: Center(
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: Colors.white,
              // A hairline so an element running past the viewport edge is
              // visible rather than merely clipped by the window.
              border: Border.all(color: const Color(0xFFEF4444)),
            ),
            clipBehavior: Clip.hardEdge,
            child: MediaQuery(
              // The skeleton measures itself with uiScaleWidth, which reads
              // MediaQuery.sizeOf — so the override has to be the whole story
              // about how big the screen is.
              data: MediaQueryData(size: Size(width, height)),
              child: LoadingOverlay.bodyOrSkeleton(
                isLoading: true,
                layout: SkeletonLayout.home,
                child: const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
