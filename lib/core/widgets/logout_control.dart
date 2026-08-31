import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Logout, drawn one way
//
//  Seven surfaces offered this action and no two agreed. Three spellings were
//  live at once — "Log out", "Logout", "Sign Out" — which is three different
//  actions as far as a reader is concerned. Some had a divider separating them
//  from the ordinary settings above; some sat flush against "Change password"
//  as though it were the same kind of thing.
//
//  ── WHY IT IS TINTED RATHER THAN JUST RED TEXT ────────────────────────────
//  Red text alone is the weakest emphasis available and it was already being
//  used: the problem was never that logout lacked colour, it was that it read
//  as one more row in a list. A tinted ground with a hairline gives the row an
//  EDGE, so the eye finds it as a distinct thing without it having to shout.
//
//  It is deliberately NOT a filled red button. Logout sits beside Edit profile
//  and Change password — controls people open often — and a solid red block is
//  the visual language this app reserves for genuinely destructive, one-way
//  actions (Delete account, Reject report). Logging out is reversible: you log
//  back in. Making it the loudest thing on the page invites the mis-tap it
//  should be preventing.
// ════════════════════════════════════════════════════════════════════════════

/// The one label. Sentence case, two words: it is a verb phrase, and "Logout"
/// is the noun.
const String kLogoutLabel = 'Log out';

/// The tinted ground behind a logout control.
const Color kLogoutTint = Color(0xFFFEF2F2);

/// Its hairline.
const Color kLogoutBorder = Color(0xFFFECACA);

/// A full-width logout row, for a settings page or the foot of a drawer.
///
/// [compact] drops the label for a collapsed rail, keeping the icon centred.
class LogoutTile extends StatelessWidget {
  final VoidCallback onLogout;

  /// Icon only — for a collapsed sidebar.
  final bool compact;

  /// Rounded corners. Off inside a card that already clips its own.
  final bool rounded;

  const LogoutTile({
    super.key,
    required this.onLogout,
    this.compact = false,
    this.rounded = true,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(rounded ? 12 : 0);

    // `button: true` only — NOT a label. The row already contains the words
    // "Log out" as a Text, and a label here is MERGED with it rather than
    // replacing it, so a screen reader announced "Log out, Log out". In the
    // compact form the label is supplied by the caller's Tooltip instead.
    return Semantics(
      button: true,
      child: Material(
        color: kLogoutTint,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onLogout,
          // A visible press state matters more here than elsewhere: this is
          // the one control whose result is the screen disappearing, so the
          // tap wants acknowledging before the app goes.
          splashColor: AppColors.red.withValues(alpha: 0.12),
          highlightColor: AppColors.red.withValues(alpha: 0.06),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 0 : 16,
              vertical: 14,
            ),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: kLogoutBorder),
            ),
            child: Row(
              mainAxisAlignment: compact
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                const Icon(
                  Icons.logout_rounded,
                  size: 20,
                  color: AppColors.red,
                ),
                if (!compact) ...[
                  const SizedBox(width: 12),
                  // No trailing chevron. A chevron promises a NEXT screen —
                  // it is what "Change password" and "Edit profile" carry,
                  // because those open something. Logout opens nothing: it
                  // acts and the session ends. Borrowing the affordance made
                  // the one row that behaves differently look like the rest.
                  const Text(
                    kLogoutLabel,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.red,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The logout entry inside a popup or dropdown menu.
///
/// A menu row cannot carry its own border — the menu draws the surface — so
/// the tint does the work alone, and the caller puts a divider above it. The
/// icon sits in a tinted disc, which is what the citizen dropdown already did
/// and the admin and staff ones did not.
class LogoutMenuRow extends StatelessWidget {
  const LogoutMenuRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: kLogoutTint,
            shape: BoxShape.circle,
            border: Border.all(color: kLogoutBorder),
          ),
          child: const Icon(
            Icons.logout_rounded,
            size: 16,
            color: AppColors.red,
          ),
        ),
        const SizedBox(width: 11),
        const Text(
          kLogoutLabel,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.red,
          ),
        ),
      ],
    );
  }
}
