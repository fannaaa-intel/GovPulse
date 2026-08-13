import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'app_back_chevron.dart';

/// The app's pinned screen header: a white bar carrying [AppBackChevron] and a
/// blue title, with a soft shadow separating it from the page beneath.
///
/// ── TRANSCRIBED FROM SETTINGS, LIKE THE CHEVRON IT CONTAINS ────────────────
/// Every value comes from the Settings sub-screens, where this exact block is
/// currently copy-pasted across About, Privacy Policy, Terms of Service,
/// Contact Support, Edit Profile, My Submissions and the Change Password
/// steps. Terms of Service even carries the comment "Header — identical to
/// ContactSupportScreen for consistency", which is the intent this widget makes
/// structural instead of a note someone has to honour by hand.
///
/// It replaces a Material [AppBar] at its call sites rather than wrapping one:
/// an AppBar brings its own title typography, its own leading slot and the
/// platform back arrow, none of which match the Settings look. Sits at the top
/// of a Column, ABOVE whatever animates in — the header is pinned in Settings
/// and does not slide with the body.
///
/// Change the look HERE, not at a call site.
class AppScreenHeader extends StatelessWidget {
  final String title;

  /// Defaults to a back navigation, which is what every call site wants.
  final VoidCallback? onBack;

  /// Layout width to scale against. Defaults to the clamped screen width — the
  /// expression every Settings screen already uses.
  final double? width;

  const AppScreenHeader({
    super.key,
    required this.title,
    this.onBack,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final w = width ?? MediaQuery.of(context).size.width.clamp(0.0, 480.0);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(w * 0.04, w * 0.04, w * 0.04, w * 0.035),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          AppBackChevron(width: w, onTap: onBack),
          SizedBox(width: w * 0.035),
          // Expanded so a longer title ellipsises instead of overflowing the
          // Row. "Profile Verification" is wider than most Settings titles and
          // is the first call site that could reach the edge on a small phone.
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: w * 0.052,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryBlue,
                letterSpacing: -0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
