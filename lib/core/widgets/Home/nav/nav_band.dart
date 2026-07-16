// lib/core/widgets/Home/nav/nav_band.dart
//
// Which navigation chrome a viewport gets. Shared by `home_screen.dart` and
// `responsive_nav_scaffold.dart` so the two can never drift apart — they used
// to each carry their own copy of this rule.
//
// Kept a dependency-free leaf (foundation + dart:ui only) precisely so both of
// those can import it: responsive_nav_scaffold already imports home_screen, so
// anything the pair shares has to live below them both or it's an import cycle.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:ui' show Size;

/// Which navigation chrome to show for a given viewport.
enum NavBand { phone, drawer, topNav }

/// Width at/above which the horizontal top nav is shown.
const double kNavTopBreakpoint = 900;

/// SHORTEST-SIDE below which a native device is treated as a phone.
///
/// Deliberately measured on the shortest side, not on width. A device's
/// shortest side does not change when you rotate it, so it describes the DEVICE
/// (a ~390–430dp phone vs a ~600dp+ tablet) rather than the current
/// orientation. Testing `width < 600` instead meant a phone turned landscape
/// (~750–930dp wide) stopped matching, silently lost its bottom nav, and got
/// served the tablet drawer layout in a ~390dp-tall viewport.
///
/// 600 is the Android `sw600dp` convention — the same line the platform itself
/// draws between phone and tablet.
const double kNavPhoneShortestSide = 600;

/// Legacy alias for [kNavPhoneShortestSide]. Kept only so the old name still
/// resolves; prefer the shortest-side name, which says what it measures.
@Deprecated('Use kNavPhoneShortestSide — the band is decided on shortest side')
const double kNavMobileBreakpoint = kNavPhoneShortestSide;

/// The nav chrome for [size]:
///
///   • phone  (native, shortest side < 600) → bottom nav, in EITHER orientation
///   • topNav (width >= 900)                → horizontal top nav
///   • drawer (everything else)             → side drawer + slim app bar
///
/// The phone check comes FIRST and short-circuits, which is what keeps a
/// rotated phone on the bottom nav: in landscape it is simultaneously a phone
/// AND wider than the 900 top-nav line, and without the ordering the wider-wins
/// rule would hand it desktop chrome.
///
/// Web is never "phone" — the citizen web app is desktop-first by design and a
/// narrow browser window is a small window, not a handset.
NavBand resolveNavBand(Size size) {
  if (!kIsWeb && size.shortestSide < kNavPhoneShortestSide) {
    return NavBand.phone;
  }
  if (size.width >= kNavTopBreakpoint) return NavBand.topNav;
  return NavBand.drawer;
}
