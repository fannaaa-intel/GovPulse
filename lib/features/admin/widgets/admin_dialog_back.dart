import 'package:flutter/material.dart';

import '../theme/admin_ui.dart';

/// Back control for admin dialogs / full-screen forms — a chevron button placed
/// at the LEFT of the header title. Web/desktop dialogs use a top-right X close
/// instead (see the New event form), so this is only used for the full-screen
/// header.
///
/// ── THIS IS A TRANSCRIPTION, NOT A NEW DESIGN ──────────────────────────────
/// Every number here comes from `QaRailHeader`'s back control in
/// quick_action_split_panel.dart — the chip on the citizen "Report an Issue"
/// fullscreen panel. That is the button an admin sees one tap away in the same
/// product, so the console draws the same one rather than a near-miss.
///
/// It is deliberately NOT [AppBackChevron], the Settings-screen chevron, even
/// though the two look related. That one is a filled grey chip with a BLUE
/// glyph, sized proportionally off the phone's layout width; this is an
/// outlined transparent chip with a neutral glyph at a fixed 32px. The console
/// is a fixed-width desktop surface, so a proportional size would make a dialog
/// header resize its own back button as the window moves — and the outlined
/// form is what the reference actually shows.
///
/// Change the look in `QaRailHeader`, then mirror it here.
class AdminDialogBack extends StatelessWidget {
  final VoidCallback onTap;
  const AdminDialogBack({super.key, required this.onTap});

  /// Chip edge and corner, straight from the reference.
  static const double size = 32;
  static const double radius = 10;

  @override
  Widget build(BuildContext context) {
    return Material(
      // Transparent, not a fill: the reference chip is an outline. A filled
      // chip is the Settings chevron, which is a different control.
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Tooltip(
          message: 'Back',
          child: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              // AdminUi.border is #CBD3DF — the same value CitizenUi.border
              // carries, so the console's own token is the right one to name
              // here rather than importing the citizen theme.
              border: const Border.fromBorderSide(
                BorderSide(color: AdminUi.border),
              ),
            ),
            child: const Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 18,
              // Neutral, not blue: the glyph is chrome, and the reference keeps
              // the accent for things that are actually actionable content.
              // Spelled out rather than AdminUi.textSecondary (#4B5563) — the
              // reference is CitizenUi.textSecondary, one step darker, and a
              // near-miss is exactly what this rewrite is correcting.
              color: Color(0xFF374151),
            ),
          ),
        ),
      ),
    );
  }
}
