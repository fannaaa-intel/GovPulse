import 'package:flutter/material.dart';

import '../theme/mobile_metrics.dart';

/// The one back-chevron palette, shared by the citizen chip below, the admin
/// console's AdminDialogBack and the staff thread header.
///
/// Named here rather than pulled from AppColors/AdminUi/StaffUi because the
/// point is that all three portals use the SAME two values — three theme
/// lookups that happen to agree today is exactly how they drift apart.
const Color kBackChevronBorder = Color(0xFFCBD3DF);
const Color kBackChevronGlyph = Color(0xFF374151);

/// Title colour for a screen header carrying [AppBackChevron]. Near-black, not
/// the brand blue: with the chevron receding, a blue title made the header read
/// as two competing accents.
const Color kScreenTitleColor = Color(0xFF1F2937);

/// The app's back chevron: an outlined rounded square with a neutral
/// `arrow_back_ios_new_rounded`.
///
/// ── ONE CHEVRON, THREE PORTALS ─────────────────────────────────────────────
/// Citizen, admin and staff all show the same control for the same gesture, so
/// they draw the same chip. The reference is the fullscreen "Report an Issue"
/// panel: an OUTLINE, not a filled chip, with a neutral glyph rather than an
/// accent one. Back is chrome — it is the same affordance on every screen and
/// never the thing you came to the screen to press — so it recedes and lets the
/// title lead. The filled grey chip with a blue glyph that preceded this read
/// as a primary action sitting in the corner of every page.
///
/// It exists because the app had drifted into many answers to one question: a
/// bare Material AppBar arrow, a blue-tinted circle, a plain white IconButton,
/// filled chips at 38 and 40px, and several screens with no affordance at all.
///
/// The admin console mirrors this in AdminDialogBack (fixed sizes rather than
/// proportional ones — see that file); staff mirrors it in its thread header.
///
/// Change the look HERE, not at a call site. A call site that needs something
/// different is the drift this widget was written to end — the whole reason
/// there were four of these is that each screen styled its own.
///
/// ── Sizing ─────────────────────────────────────────────────────────────────
/// Proportional to the layout width, like the Settings header it comes from,
/// and clamped at 480 so it stops growing on a tablet. Pass [width] where the
/// caller already computes one, so the chip matches the header it sits in
/// rather than re-deriving a slightly different number.
class AppBackChevron extends StatelessWidget {
  /// Layout width the chip scales against. Defaults to the clamped screen
  /// width — the same expression the Settings screens use.
  final double? width;

  /// Defaults to `Navigator.pop`, which is what every current call site wants.
  final VoidCallback? onTap;

  /// Set on a dark backdrop (a full-bleed camera preview) so the chip keeps its
  /// shape and proportions while inverting its colours. The light fill has
  /// nothing to sit against there, and a light-on-light border disappears.
  final bool onDark;

  const AppBackChevron({
    super.key,
    this.width,
    this.onTap,
    this.onDark = false,
  });

  @override
  Widget build(BuildContext context) {
    final w = width ?? uiScaleWidth(context);
    final size = w * 0.09;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap ?? () => Navigator.of(context).maybePop(),
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          // Transparent on light: the chip is an outline. On a dark backdrop it
          // still needs a scrim, or the glyph floats on the camera preview.
          color: onDark ? Colors.black.withValues(alpha: 0.35) : null,
          borderRadius: BorderRadius.circular(w * 0.025),
          border: Border.all(
            color: onDark
                ? Colors.white.withValues(alpha: 0.45)
                : kBackChevronBorder,
          ),
        ),
        child: Icon(
          Icons.arrow_back_ios_new_rounded,
          size: w * 0.046,
          color: onDark ? Colors.white : kBackChevronGlyph,
        ),
      ),
    );
  }
}
