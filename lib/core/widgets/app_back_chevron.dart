import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/mobile_metrics.dart';

/// The app's back chevron: a rounded-square chip with a light fill, a hairline
/// border and a blue `arrow_back_ios_rounded`.
///
/// ── THIS IS A TRANSCRIPTION, NOT A NEW DESIGN ──────────────────────────────
/// Every number here is lifted from the Settings screens, which have used the
/// same block — About, Privacy Policy, Terms, Contact Support, Edit Profile,
/// My Submissions and the three Change Password steps — long enough that it is
/// what "back" looks like in this app. It exists because the Profile
/// Verification wizard had drifted into FOUR different answers to the same
/// question: a bare Material AppBar arrow, a blue-tinted 38px circle, a plain
/// white IconButton, and several steps with no affordance at all.
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
          color: onDark
              ? Colors.black.withValues(alpha: 0.35)
              : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(w * 0.025),
          border: Border.all(
            color: onDark
                ? Colors.white.withValues(alpha: 0.45)
                : AppColors.stroke,
          ),
        ),
        child: Icon(
          Icons.arrow_back_ios_rounded,
          size: w * 0.04,
          color: onDark ? Colors.white : AppColors.primaryBlue,
        ),
      ),
    );
  }
}
