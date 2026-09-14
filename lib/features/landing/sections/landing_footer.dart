import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../landing_page.dart' show LandingBand;
import '../landing_theme.dart';
import '../widgets/brand_mark.dart';

/// The navy footer: the mark, three link columns, and contact details.
///
/// ── Which links are real ───────────────────────────────────────────────────
/// Every entry here either scrolls to a section on this page or goes to a route
/// that exists. The design's footer also lists "Help Center", "Data Protection"
/// and "Accessibility"; those have no destination in the product today, so
/// rather than render dead text that looks clickable, Support carries the three
/// that ARE real — Privacy Policy, Terms of Service, and Contact Support, all of
/// which are already screens in the app.
///
/// A footer link that does nothing is the cheapest possible way to make a
/// government site look abandoned, and it is worth more to ship three working
/// links than six decorative ones.
class LandingFooter extends StatelessWidget {
  final VoidCallback onFeatures;
  final VoidCallback onHowItWorks;
  final VoidCallback onFaq;

  const LandingFooter({
    super.key,
    required this.onFeatures,
    required this.onHowItWorks,
    required this.onFaq,
  });

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < LandingUi.mobileBreak;

    final about = _FooterAbout(narrow: narrow);
    final quickLinks = _FooterColumn(
      heading: 'Quick Links',
      items: <_FooterItem>[
        _FooterItem('Features', onFeatures),
        _FooterItem('How it Works', onHowItWorks),
        _FooterItem('FAQ', onFaq),
      ],
      narrow: narrow,
    );
    final support = _FooterColumn(
      heading: 'Support',
      items: <_FooterItem>[
        // These three are routes on the legacy table, reachable without a
        // session, and each is a real screen in the app.
        _FooterItem('Privacy Policy', () => context.go('/privacy_policy')),
        _FooterItem('Terms of Service', () => context.go('/terms_of_service')),
        _FooterItem('About GovPulse', () => context.go('/about')),
      ],
      narrow: narrow,
    );
    const contact = _FooterContact();

    return Container(
      color: LandingUi.footerBg,
      child: LandingBand(
        padding: EdgeInsets.symmetric(
          vertical: narrow ? 44 : 56,
          horizontal: LandingUi.gutter,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (narrow)
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  about,
                  const SizedBox(height: 34),
                  quickLinks,
                  const SizedBox(height: 28),
                  support,
                  const SizedBox(height: 28),
                  contact,
                ],
              )
            else
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 4, child: about),
                    const SizedBox(width: 32),
                    Expanded(flex: 2, child: quickLinks),
                    const SizedBox(width: 24),
                    Expanded(flex: 2, child: support),
                    const SizedBox(width: 24),
                    const Expanded(flex: 3, child: contact),
                  ],
                ),
              ),
            SizedBox(height: narrow ? 32 : 40),
            const Divider(color: Color(0x33FFFFFF), height: 1),
            const SizedBox(height: 20),
            Align(
              alignment: narrow ? Alignment.center : Alignment.centerLeft,
              child: Text(
                '© ${DateTime.now().year} Municipality of Aparri, Cagayan. '
                'All rights reserved.',
                textAlign: narrow ? TextAlign.center : TextAlign.start,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: Color(0xFF8FA3BF),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FooterAbout extends StatelessWidget {
  final bool narrow;
  const _FooterAbout({required this.narrow});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: narrow
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const BrandMark(onDark: true),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Text(
            'Empowering communities by connecting citizens and their local '
            'government for a better, safer, and more responsive tomorrow.',
            textAlign: narrow ? TextAlign.center : TextAlign.start,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.65,
              color: LandingUi.footerText,
            ),
          ),
        ),
      ],
    );
  }
}

class _FooterColumn extends StatelessWidget {
  final String heading;
  final List<_FooterItem> items;
  final bool narrow;

  const _FooterColumn({
    required this.heading,
    required this.items,
    required this.narrow,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: narrow
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          heading,
          style: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            color: LandingUi.footerHeading,
          ),
        ),
        const SizedBox(height: 14),
        for (final item in items)
          _FooterLink(label: item.label, onTap: item.onTap, narrow: narrow),
      ],
    );
  }
}

class _FooterLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool narrow;

  const _FooterLink({
    required this.label,
    required this.onTap,
    required this.narrow,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: narrow ? Alignment.center : Alignment.centerLeft,
      // A TextButton rather than a GestureDetector: focusable, keyboard
      // operable, and announced as a button.
      //
      // ── The tap target is 44px, not the text's own height ────────────────
      // This used to set `minimumSize: Size.zero` with
      // `tapTargetSize: shrinkWrap`, which are the two properties that let a
      // Material button shrink to its label. Measured, that made every footer
      // link 34px tall — under the 44px that both WCAG 2.5.5 and the Apple HIG
      // ask for, on the links most likely to be tapped with a thumb.
      //
      // The links still LOOK the same: 7px of vertical padding keeps them
      // visually tight in their column, and the extra height comes from the
      // minimumSize, which pads the target without moving the text. Only the
      // hit area grew.
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: LandingUi.footerText,
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
          minimumSize: const Size(0, 44),
          alignment: narrow ? Alignment.center : Alignment.centerLeft,
        ),
        child: Text(label, style: const TextStyle(fontSize: 13.5, height: 1.5)),
      ),
    );
  }
}

class _FooterContact extends StatelessWidget {
  const _FooterContact();

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < LandingUi.mobileBreak;

    return Column(
      crossAxisAlignment: narrow
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Contact Us',
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            color: LandingUi.footerHeading,
          ),
        ),
        const SizedBox(height: 14),
        // ── The phone and email are ACTIONABLE ──────────────────────────────
        // These were plain Text. On a civic support page that is a real gap:
        // the two details a citizen comes to the footer FOR are the ones they
        // then have to select and copy by hand, and on a phone — where most of
        // this traffic is — selecting text out of a footer is fiddly enough
        // that people give up.
        //
        // `uri` is null for the address, which has nothing to launch: a map
        // link would need a place ID this page does not have, and guessing one
        // from a street string is how you send someone to the wrong town.
        for (final row in <({IconData icon, String text, Uri? uri})>[
          (
            icon: Icons.location_on_outlined,
            text:
                'GovPulse Support Center, LGU Aparri,\n'
                'Cagayan, 3515, Philippines',
            uri: null,
          ),
          (
            icon: Icons.phone_outlined,
            text: '+63 977 632 7786',
            // Spaces stripped: a tel: with spaces in it is not dialled by
            // every handset.
            uri: Uri.parse('tel:+639776327786'),
          ),
          (
            icon: Icons.mail_outline_rounded,
            text: 'supportgovpulse@gmail.com',
            uri: Uri.parse('mailto:supportgovpulse@gmail.com'),
          ),
        ]) ...[
          _ContactRow(
            icon: row.icon,
            text: row.text,
            uri: row.uri,
            narrow: narrow,
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

/// One contact detail. Tappable when it has somewhere to go.
class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String text;

  /// `tel:` or `mailto:`, or null for a detail with nothing to launch.
  final Uri? uri;
  final bool narrow;

  const _ContactRow({
    required this.icon,
    required this.text,
    required this.uri,
    required this.narrow,
  });

  @override
  Widget build(BuildContext context) {
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: LandingUi.footerText),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            text,
            textAlign: narrow ? TextAlign.center : TextAlign.start,
            style: TextStyle(
              fontSize: 13,
              height: 1.6,
              color: LandingUi.footerText,
              // Underlined only when it is a link, so the two that DO something
              // are distinguishable from the address that does not. Colour
              // alone would not be: these all sit on navy at the same weight.
              decoration: uri == null ? null : TextDecoration.underline,
              decorationColor: const Color(0x66C7D4E6),
            ),
          ),
        ),
      ],
    );

    if (uri == null) return row;

    return Semantics(
      link: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          // ── No await before the launch ──────────────────────────────────
          // Safari grants a page permission to leave for an external scheme
          // only while it is still inside the user gesture that asked. An
          // `await canLaunchUrl(...)` first hands control back to the event
          // loop, and by the time the launch runs the permission is gone —
          // Safari drops it silently, while Chrome allows the same sequence,
          // so it looks fine on Android and does nothing on an iPhone.
          //
          // This is the same bug already documented in emergency_screen.dart;
          // the check bought nothing anyway, since canLaunchUrl on web only
          // tests the scheme against a hard-coded list that tel and mailto are
          // both in.
          onTap: () => launchUrl(uri!),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            // Pads the hit area past 44px without moving the text off the
            // column's alignment. 12, not the 10 that looked right: the single
            // -line rows measured 41px with 10, three short of the minimum.
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            child: row,
          ),
        ),
      ),
    );
  }
}

class _FooterItem {
  final String label;
  final VoidCallback onTap;
  const _FooterItem(this.label, this.onTap);
}
