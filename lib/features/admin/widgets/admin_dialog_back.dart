import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Back control for admin dialogs / full-screen forms — a rounded chevron
/// button placed at the LEFT of the header title. Web/desktop dialogs use a
/// top-right X close instead (see the New event form), so this is only used for
/// the full-screen header.
///
/// ── THIS IS A TRANSCRIPTION, NOT A NEW DESIGN ──────────────────────────────
/// Every number and colour here comes from [AppBackChevron], the citizen app's
/// back control. The console used to draw its own: a heavier `AdminUi.border`
/// hairline around a `chevron_left_rounded` at 24px, which read as a chunkier
/// control than the identical-purpose button one tap away in the citizen app.
/// Same product, same gesture — so it is now the same chip.
///
/// The admin console is a fixed-width desktop surface rather than a
/// proportionally-scaled phone layout, so the sizes are [AppBackChevron]'s
/// evaluated at its own reference width instead of re-derived per screen. That
/// keeps a dialog header from resizing its back button as the window moves.
///
/// Change the look in [AppBackChevron], then mirror it here.
class AdminDialogBack extends StatelessWidget {
  final VoidCallback onTap;
  const AdminDialogBack({super.key, required this.onTap});

  /// Chip edge. [AppBackChevron] uses `width * 0.09`; at the 420px reference
  /// this file targets that is ~38, the size the console already used.
  static const double size = 38;

  /// Corner radius — `width * 0.025` at the same reference.
  static const double radius = 10.5;

  @override
  Widget build(BuildContext context) {
    return Material(
      // The citizen chip's flat grey, not AdminUi.subtle's blue-tinted one.
      color: const Color(0xFFF3F4F6),
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            // AppColors.stroke (#E3E6EF), a genuine hairline — AdminUi.border
            // (#CBD3DF) is nearly three shades darker and is what made this
            // read heavy next to the citizen control.
            border: Border.all(color: AppColors.stroke),
          ),
          child: const Icon(
            Icons.arrow_back_ios_rounded,
            size: 17,
            color: AppColors.primaryBlue,
          ),
        ),
      ),
    );
  }
}
