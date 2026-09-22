import 'package:flutter/material.dart';

class AppColors {
  static const primaryBlue = Color(0xFF0D47A1);
  static const inputBg = Color(0xFFF6F7FB);
  static const stroke = Color(0xFFE3E6EF);
  static const hint = Color(0xFF8A8A8A);

  static const green = Color(0xFF2ECC71);
  static const grey = Color(0xFFB0B0B0);
  static const red = Color(0xFFE74C3C);
  static const orange = Color(0xFFF39C12);
}

/// The one Material colour scheme, shared by the mobile app and the web app.
///
/// ── WHY THIS EXISTS: the purple ────────────────────────────────────────────
/// Material 3 derives every colour role from a seed through a tonal-palette
/// calculation, and the result is NOT the colour you seeded with. Seeding from
/// the brand blue #0D47A1 produces `primary` = **#475D92**, a desaturated
/// blue-violet. Worse, the web app passed a `ThemeData` carrying no scheme at
/// all, so the browser fell back to Flutter's stock **#6750A4** — a strong
/// purple.
///
/// A bare `TextButton` takes its label colour from `colorScheme.primary`. Of
/// the 127 TextButtons in this app only 28 set a colour of their own, so ~99
/// of them drew purple labels: every "Cancel" beside a destructive action,
/// most dialog dismissals, most inline links.
///
/// So `primary` is PINNED to the literal brand blue rather than left to the
/// tonal maths, and `onPrimary` is pinned with it — the two are a contrast
/// pair, and moving one without the other is how a filled button ends up with
/// a label that cannot be read against its own background.
///
/// The surfaces are pinned to plain white/greys for the same reason they
/// always were: a seeded scheme tints every surface with the primary, which is
/// what once made the account menus and dropdowns look faintly pink. The
/// hand-built pages (AdminUi, CitizenUi) assume plain white.
///
/// Both apps read THIS, so web and mobile cannot drift apart again.
final ColorScheme govPulseColorScheme = () {
  final base = ColorScheme.fromSeed(seedColor: AppColors.primaryBlue);
  return base.copyWith(
    primary: AppColors.primaryBlue,
    onPrimary: Colors.white,
    surface: Colors.white,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Colors.white,
    surfaceContainer: Colors.white,
    surfaceContainerHigh: Colors.white,
    surfaceContainerHighest: const Color(0xFFF4F6FA),
    surfaceTint: Colors.transparent, // no elevation tint over white
  );
}();
