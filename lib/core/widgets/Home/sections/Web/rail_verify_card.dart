import 'package:flutter/material.dart';

import '../../../../theme/citizen_ui.dart';
import '../../home_enums.dart';
import 'web_promo_card_style.dart';

/// The left rail's verification slot — the citizen web shell's single verify
/// affordance.
///
/// CITIZEN WEB ONLY. Mounted at the bottom of `_leftRail`, which is private to
/// `_CitizenShellState` and built only by the web router; the mobile app never
/// reaches this. Nothing in this file is imported by a mobile code path, so the
/// mobile verification screens (`features/profileVerification/`) are untouched
/// by anything here.
///
/// Three states, keyed on [VerifStatus]. All three are rendered by ONE build
/// method off a [_VerifSkin] record, which is the whole point: the card cannot
/// drift in size between states, because there is only one set of paddings,
/// type sizes, artwork box and divider in the layout — and those come from
/// [WebPromoCardStyle], shared with [HomeAppDownloadCard], so it cannot drift
/// from its sibling in the right sidebar either. What varies is data — colour,
/// artwork, and copy — plus the single `if` that adds the button:
///
///   none      red skin    + "Verify Your Account" button
///   pending   amber skin, NO button — the wizard refuses a second pending
///             submission, so a button here would be dead. Matches the product
///             stance the rail has always taken.
///   verified  green skin, no button — nothing left to act on
///
/// The profile-still-loading case is NOT one of these: see [maybe].
class RailVerifyCard extends StatelessWidget {
  final VerifStatus status;

  /// Runs the shell's `_startVerification`. Only ever invoked for
  /// [VerifStatus.none] — the other two states render no control at all.
  final VoidCallback onVerify;

  const RailVerifyCard({
    super.key,
    required this.status,
    required this.onVerify,
  });

  /// The card, or nothing at all while the profile is still loading.
  ///
  /// [VerifStatus] falls back to `none` when there is no profile yet, so keying
  /// the card on status alone would flash the red "unverified" card at a
  /// VERIFIED citizen for the length of every cold load. Rendering nothing
  /// until [profileLoaded] is the same guard the rail's profile card uses for
  /// its status line.
  static Widget maybe({
    required bool profileLoaded,
    required VerifStatus status,
    required VoidCallback onVerify,
  }) {
    if (!profileLoaded) return const SizedBox.shrink();
    return RailVerifyCard(status: status, onVerify: onVerify);
  }

  // ── Layout ─────────────────────────────────────────────────────────────────

  /// The mockup is a landscape card: status pill on top, then headline and body
  /// beside the artwork, then a rule, a footnote and (unverified only) the
  /// button. The rail is a fixed 288 — `kCitizenRailWidth`, and the drawer
  /// below 1024 is the same 288 — which is far too narrow to hang the artwork
  /// down the full height of the card the way the mockup does.
  ///
  /// So the artwork keeps its position beside the headline block, and the pill,
  /// rule, footnote and button span the full width above and below it. Reading
  /// order is the mockup's, unchanged; only the artwork's column stops short.
  ///
  /// Widths are read off the CARD, never the window: [LayoutBuilder] here means
  /// the same widget is correct in the inline rail, in the drawer, and in the
  /// clamped drawer a browser window narrower than 288 produces — Flutter caps
  /// a [Drawer] at the screen width, which is the one case where this card is
  /// handed less than it asks for.
  @override
  Widget build(BuildContext context) {
    final skin = _skinFor(status);

    return LayoutBuilder(
      builder: (context, constraints) {
        final double w = constraints.maxWidth;
        final double pad = WebPromoCardStyle.padFor(w);
        // 0 means "drop the artwork" — see [WebPromoCardStyle.artFor].
        final double art = WebPromoCardStyle.artFor(w);

        return Container(
          padding: EdgeInsets.all(pad),
          decoration: WebPromoCardStyle.decoration(skin.tint),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            // The rail scrolls, so the card is normally handed an unbounded
            // height and this is moot — but the drawer hands it a BOUNDED one,
            // and a max-size Column there stretches the card down the whole
            // drawer with the footnote stranded at the top.
            mainAxisSize: MainAxisSize.min,
            children: [
              _pill(skin),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _headline(skin),
                        const SizedBox(height: 8),
                        Text(skin.body, style: WebPromoCardStyle.body),
                      ],
                    ),
                  ),
                  if (art > 0) ...[
                    const SizedBox(width: WebPromoCardStyle.artGap),
                    WebPromoCardStyle.art(skin.art, art),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              WebPromoCardStyle.rule(skin.tint),
              const SizedBox(height: 14),
              _footnote(skin),
              // The ONLY state-dependent branch in the layout. Pending and
              // verified have nothing to act on, so they end at the footnote.
              if (status == VerifStatus.none) ...[
                const SizedBox(height: 14),
                _verifyButton(),
              ],
            ],
          ),
        );
      },
    );
  }

  // ── Pieces ─────────────────────────────────────────────────────────────────

  /// Status pill: a filled dot carrying a white glyph, then the label in caps.
  /// Sized by its content, so it is the same height in all three states and
  /// only its width follows the label.
  Widget _pill(_VerifSkin skin) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 5, 11, 5),
      decoration: BoxDecoration(
        color: skin.tint.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 19,
            height: 19,
            decoration: BoxDecoration(color: skin.tint, shape: BoxShape.circle),
            child: Icon(skin.pillIcon, size: 12, color: Colors.white),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              skin.pillLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: .5,
                color: skin.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// `Your account is <state>.` — the state word carries the colour.
  ///
  /// It is painted in [_VerifSkin.ink], not [_VerifSkin.tint]: the tints are
  /// chosen to wash well at 10% alpha, and at full strength on that wash the
  /// green in particular falls to roughly 2:1 against the card. The inks clear
  /// 3:1 at this weight and size.
  Widget _headline(_VerifSkin skin) {
    return Text.rich(
      TextSpan(
        text: skin.headLead,
        children: [
          TextSpan(
            text: skin.headAccent,
            style: TextStyle(color: skin.ink),
          ),
        ],
      ),
      style: WebPromoCardStyle.headline,
    );
  }

  /// The reassurance line under the rule. Full width and centred in every
  /// state, so the block keeps one shape whether the copy is four words or a
  /// wrapped sentence.
  Widget _footnote(_VerifSkin skin) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: skin.tint.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(CitizenUi.controlRadius),
      ),
      child: Text(
        skin.footnote,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, height: 1.45, color: skin.ink),
      ),
    );
  }

  /// Green even on the red card — see [WebPromoCardStyle.button], which is the
  /// same button the download card's "Download App" uses.
  Widget _verifyButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onVerify,
        icon: const Icon(Icons.how_to_reg_rounded, size: 17),
        label: const Text('Verify Your Account'),
        style: WebPromoCardStyle.button(),
      ),
    );
  }

  // ── State data ─────────────────────────────────────────────────────────────

  static _VerifSkin _skinFor(VerifStatus status) {
    return switch (status) {
      VerifStatus.verified => const _VerifSkin(
        tint: CitizenUi.accentGreen,
        ink: CitizenUi.success,
        art: 'assets/images/verification/verifies-status.webp',
        pillIcon: Icons.check_rounded,
        pillLabel: 'VERIFIED',
        headLead: 'Your account is ',
        headAccent: 'verified!',
        body: 'You have full access to all LGU Aparri services.',
        footnote: 'Thank you for verifying your account.',
      ),
      VerifStatus.pending => const _VerifSkin(
        tint: CitizenUi.warn,
        ink: CitizenUi.pending,
        art: 'assets/images/verification/Pending.webp',
        pillIcon: Icons.access_time_rounded,
        pillLabel: 'PENDING REVIEW',
        headLead: 'Your account is ',
        headAccent: 'pending review.',
        body:
            "We're reviewing your information. You'll be notified once it's "
            'approved.',
        footnote: 'Thank you for your patience.',
      ),
      VerifStatus.none => const _VerifSkin(
        tint: CitizenUi.danger,
        ink: _dangerInk,
        art: 'assets/images/verification/Unverified.webp',
        pillIcon: Icons.priority_high_rounded,
        pillLabel: 'UNVERIFIED ACCOUNT',
        headLead: 'Your account is ',
        headAccent: 'unverified.',
        body: 'Please verify your account to access all LGU Aparri services.',
        footnote:
            'Some features may be limited until your account is verified.',
      ),
    };
  }
}

/// Readable red on a red wash. [CitizenUi] has darkened companions for the
/// green and amber tints (`success`, `pending`) but none for `danger`, so this
/// reuses the same 0xFFB91C1C the report status chips already use for red text.
const Color _dangerInk = Color(0xFFB91C1C);

/// Everything that differs between the three states. Deliberately data, not
/// three widget builders: a builder per state is how the old card ended up with
/// a different footprint for verified than for unverified.
@immutable
class _VerifSkin {
  /// Drives the wash, the border, the rule and the pill dot — never text.
  final Color tint;

  /// The darkened companion to [tint], used for every piece of coloured TEXT.
  final Color ink;

  final String art;
  final IconData pillIcon;
  final String pillLabel;

  /// Headline, split so the state word can take [ink].
  final String headLead;
  final String headAccent;

  final String body;
  final String footnote;

  const _VerifSkin({
    required this.tint,
    required this.ink,
    required this.art,
    required this.pillIcon,
    required this.pillLabel,
    required this.headLead,
    required this.headAccent,
    required this.body,
    required this.footnote,
  });
}
