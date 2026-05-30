import 'package:flutter/foundation.dart' show kIsWeb;

enum HomeNavLayout { top, bottom, drawer }

/// Width at/above which web shows the horizontal top nav.
const double kHomeTopNavMinWidth = 900;

/// Width below which even native mobile falls back to a drawer.
const double kHomeNarrowMobileWidth = 360;

HomeNavLayout resolveHomeNavLayout(double width) {
  if (kIsWeb) {
    return width >= kHomeTopNavMinWidth
        ? HomeNavLayout.top
        : HomeNavLayout.drawer;
  }
  return width < kHomeNarrowMobileWidth
      ? HomeNavLayout.drawer
      : HomeNavLayout.bottom;
}
