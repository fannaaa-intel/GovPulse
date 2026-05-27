// lib/core/widgets/mobile_form_shell.dart
//
// Shared shell for native (mobile) form/auth screens. It does two things every
// mobile screen needs for cross-device reliability:
//
//   1. ALWAYS SCROLLS — content can never overflow on short or small phones
//      (no more "RenderFlex overflowed" yellow/black stripes). This replaces
//      the buggy `isKeyboardOpen ? Clamping : NeverScrollable` pattern.
//
//   2. CAPS + CENTERS on large screens — on tablets, foldables, and desktop-
//      sized windows the content sits in a centered column up to [maxWidth]
//      instead of stretching the fields edge-to-edge. Phones narrower than
//      [maxWidth] are completely unaffected — full width, pixel-identical to
//      before.
//
// Usage: wrap whatever you used to put inside the SingleChildScrollView.
// The child keeps its own Padding, so existing layouts drop in unchanged:
//
//   body: SafeArea(
//     child: MobileFormShell(
//       child: Padding(
//         padding: const EdgeInsets.symmetric(horizontal: 26),
//         child: Column(children: [...]),
//       ),
//     ),
//   ),

import 'package:flutter/material.dart';

class MobileFormShell extends StatelessWidget {
  final Widget child;

  /// Above this width the content stops stretching and centers. 480 ≈ a large
  /// phone, so anything phone-sized renders exactly as it did before.
  final double maxWidth;

  const MobileFormShell({super.key, required this.child, this.maxWidth = 480});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    );
  }
}
