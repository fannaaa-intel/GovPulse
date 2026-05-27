// lib/core/widgets/web/web_responsive.dart
//
// Central responsive helpers for the web auth flow. Import via the barrel
// (web.dart). Use `context.isWide` for the two-panel breakpoint and `fluid(...)`
// for font sizes / spacing that scale smoothly with the viewport instead of
// jumping at a single breakpoint.
//
// WIRING (one line): add to web.dart barrel:
//     export 'web_responsive.dart';

import 'package:flutter/widgets.dart';
import 'web_constants.dart'; // kWebTwoPanelMinWidth

/// Width below which phone-class polish kicks in (iPhone 12 ≈ 390 logical px).
const double kWebPhoneMaxWidth = 480;

extension ResponsiveContext on BuildContext {
  Size get _size => MediaQuery.sizeOf(this);

  double get screenW => _size.width;
  double get screenH => _size.height;

  /// Two-panel hero + form layout (desktop / large landscape).
  bool get isWide => screenW >= kWebTwoPanelMinWidth;

  /// Single centered column (everything below the two-panel breakpoint).
  bool get isCompact => !isWide;

  /// Phone-class width (iPhone 12 etc.) — tighten padding / shrink headings.
  bool get isPhoneWidth => screenW < kWebPhoneMaxWidth;
}

/// Smoothly interpolate a value between [min] (at width [fromW]) and [max]
/// (at width [toW]), clamped outside that range. Perfect for fluid type sizes:
///
///   Text(title, style: TextStyle(fontSize: fluid(context.screenW, min: 22, max: 30)))
///
/// As the inspector window grows from [fromW] → [toW] the value eases from
/// [min] → [max]; outside that window it stays pinned, so it never blows up.
double fluid(
  double width, {
  required double min,
  required double max,
  double fromW = 360,
  double toW = 1200,
}) {
  if (toW <= fromW) return max;
  final t = ((width - fromW) / (toW - fromW)).clamp(0.0, 1.0);
  return min + (max - min) * t;
}
