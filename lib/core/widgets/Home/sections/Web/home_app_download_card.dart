import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../theme/citizen_ui.dart';
import '../../../app_snackbar.dart';
import 'web_promo_card_style.dart';

/// Where "Download App" sends the citizen.
///
/// TODO(govpulse): deliberately null. There is no Play Store listing, App Store
/// listing, or APK URL anywhere in this repository, so there is nothing honest
/// to point at yet — and a guessed link is worse than none. Fill this in when
/// the listing is live; the card needs no other change.
const String? kGovPulseAppDownloadUrl = null;

/// The card's illustration. 512x512 WebP with alpha, so it sits straight on the
/// card's wash — see [WebPromoCardStyle.art].
const String _kArt = 'assets/images/stay-connected.webp';

/// Right-rail promo for the GovPulse mobile app.
///
/// CITIZEN WEB ONLY — mounted by the shell's right sidebar. The mobile app
/// obviously never shows this, and nothing here is reachable from a mobile code
/// path.
///
/// The mockup is a landscape card: headline and body on the left beside the
/// phone illustration, then a hairline rule, then the green button. The sidebar
/// hands it 312px (`_kRightSidebarWidth` less the sidebar's own padding), which
/// is too narrow to run the illustration down the card's full height the way
/// the mockup does — so the illustration keeps its place beside the copy, and
/// the rule and button span the full width beneath it. That is the same fold
/// [RailVerifyCard] makes at 288, and both read their geometry from
/// [WebPromoCardStyle], so the two cards cannot drift apart.
class HomeAppDownloadCard extends StatelessWidget {
  const HomeAppDownloadCard({super.key});

  Future<void> _download(BuildContext context) async {
    final url = kGovPulseAppDownloadUrl;

    // No listing yet. Say so plainly rather than shipping a button that looks
    // live and does nothing.
    if (url == null || url.isEmpty) {
      showAppSnackBar(
        context,
        'The GovPulse mobile app is coming soon.',
        type: AppSnackType.info,
      );
      return;
    }

    final uri = Uri.parse(url);
    if (!await canLaunchUrl(uri)) {
      if (!context.mounted) return;
      showAppSnackBar(
        context,
        "Couldn't open the download page.",
        type: AppSnackType.error,
      );
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    // Widths are read off the CARD, never the window: the sidebar is one fixed
    // width today, but this is the same widget the [LayoutBuilder] contract in
    // [WebPromoCardStyle] is written against, and reading the window here would
    // make the card wrong the moment the sidebar is resized or reused.
    return LayoutBuilder(
      builder: (context, constraints) {
        final double w = constraints.maxWidth;
        final double pad = WebPromoCardStyle.padFor(w);
        final double art = WebPromoCardStyle.artFor(w);

        return Container(
          padding: EdgeInsets.all(pad),
          // Washed from the brand green token rather than a new literal — the
          // mockup's promo card is green where the rest of the rail is blue.
          decoration: WebPromoCardStyle.decoration(CitizenUi.accentGreen),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            // The sidebar scrolls, so this is normally handed an unbounded
            // height and the default would be fine — but a max-size Column
            // under a BOUNDED height stretches the card and strands the button
            // at the top of it.
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // The line break is authored, not incidental: the
                        // mockup breaks the headline after "connected", and at
                        // this width natural wrapping would put "on" on the
                        // first line and orphan "the go!" on the second.
                        const Text(
                          'Stay connected\non the go!',
                          style: WebPromoCardStyle.headline,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Access GovPulse easily from your mobile device.',
                          style: WebPromoCardStyle.body,
                        ),
                      ],
                    ),
                  ),
                  if (art > 0) ...[
                    const SizedBox(width: WebPromoCardStyle.artGap),
                    WebPromoCardStyle.art(_kArt, art),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              WebPromoCardStyle.rule(CitizenUi.accentGreen),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _download(context),
                  icon: const Icon(Icons.download_rounded, size: 17),
                  label: const Text('Download App'),
                  style: WebPromoCardStyle.button(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
