// lib/core/theme/mobile_metrics.dart
//
// The width that proportional sizing on the MOBILE app is measured against.
//
// ── The problem this exists to solve ──────────────────────────────────────
// Almost every citizen screen sizes itself proportionally — `width * 0.045`
// for a title, `width * 0.04` for a gutter, `width * 0.065` for a nav icon.
// That is a sound idea (a 320dp handset and a 430dp handset should not get the
// same 16px gutter) and it is not going away. What it got wrong is *which*
// width it measured.
//
// `MediaQuery.size.width` is the width of the VIEWPORT, and a viewport changes
// when you rotate the device. A 430x932 handset turned sideways is 932dp wide,
// so every one of those factors more than doubles: the bottom nav went from
// 56dp tall to 124dp — 29% of the 430dp-tall landscape screen — with 61px
// icons and 26pt labels, and the same inflation ran through every title,
// avatar and gutter on the screen. Rotating a phone must not resize its type.
//
// [uiScaleWidth] measures the SHORTEST SIDE instead. A device's shortest side
// is a property of the DEVICE, not of how it is being held, so a handset gets
// the same type in both orientations — which is what "responsive" means here.
// It is the same reasoning, and the same 600dp convention's sibling, that
// `resolveNavBand` already uses to decide the nav chrome (see nav_band.dart),
// and the same rule `image_grid.dart` had already reached for on its own.
//
// The upper clamp is unchanged at 480: most screens already wrote
// `.clamp(0.0, 480.0)` by hand, and it is what stops a tablet from rendering
// phone proportions at 768dp. The lower bound stays 0 rather than becoming a
// floor, so anything narrower than a modern handset renders exactly what it
// renders today.
//
// ── Why web is branched out ───────────────────────────────────────────────
// Several of these widgets — the screen header, the back chevron, the loading
// skeletons, the comments sheet — are ONE widget drawn by the app and by the
// citizen web shell alike. Swapping the rule underneath them would have
// retuned the browser layout as a side effect of fixing the handset, so the
// web arm keeps the literal behaviour it has today. `kIsWeb` is a
// compile-time constant, so the branch folds away at build time; this is the
// same split, for the same reason, that `CitizenUi.sharedBorder` makes.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';

/// Widest value proportional mobile sizing is allowed to be measured against.
///
/// Above this a screen is a tablet, and phone proportions stop being the right
/// answer — a 768dp-wide gutter of `width * 0.04` is 31dp of dead margin.
const double kUiScaleMaxWidth = 480;

/// The width [size]'s proportional sizing should be measured against.
///
/// Native: the shortest side, clamped — stable across rotation.
/// Web: the viewport width, clamped — unchanged from what it renders today.
double uiScaleWidthOf(Size size) =>
    (kIsWeb ? size.width : size.shortestSide).clamp(0.0, kUiScaleMaxWidth);

/// [uiScaleWidthOf] for the nearest MediaQuery.
///
/// Depends on size alone, so a rebuild is scheduled only when the viewport
/// actually resizes — not on every keyboard inset or padding change.
double uiScaleWidth(BuildContext context) =>
    uiScaleWidthOf(MediaQuery.sizeOf(context));

/// True when the viewport is a handset held sideways: short enough that
/// vertical room is the scarce resource, wide enough to spend width instead.
///
/// Screens use this to trade a tall stack for a side-by-side arrangement, or
/// to drop a decorative hero that would otherwise leave no room for the form
/// underneath it. Tablets are excluded — they are short in neither direction.
bool isCompactLandscape(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return !kIsWeb &&
      size.width > size.height &&
      size.shortestSide < 600 &&
      size.height < 500;
}
