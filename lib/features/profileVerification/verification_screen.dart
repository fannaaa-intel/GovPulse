import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../core/router/legacy_nav.dart';
import '../../core/widgets/Home/Account/account_web_kit.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_screen_header.dart';
import '../../core/widgets/mobile_form_shell.dart';
import '../../core/theme/citizen_ui.dart';

class VerificationScreen extends StatefulWidget {
  final String username;

  const VerificationScreen({super.key, required this.username});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen>
    with SingleTickerProviderStateMixin {
  double _scale = 1.0;
  late final AnimationController _entryCtrl;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));
    _fadeAnim = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) _entryCtrl.forward();
      });
    });
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    super.dispose();
  }

  /// FEATURE CARD
  Widget _featureCard({
    required String icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CitizenUi.sharedStroke),
      ),
      // mainAxisSize.min + Flexible text: the grid gives each card a fixed
      // height from its aspect ratio, and on a narrow phone the icon plus two
      // two-line labels are taller than that. The labels give first, rather
      // than the column overflowing its cell.
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 35,
            width: 35,
            child: Image.asset(icon, fit: BoxFit.contain),
          ),
          const SizedBox(height: 6),
          Flexible(
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1F2937),
              ),
            ),
          ),
          const SizedBox(height: 3),
          Flexible(
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10.5, color: Color(0xFF6B7280)),
            ),
          ),
        ],
      ),
    );
  }

  /// MAIN CONTENT
  Widget _buildContent() {
    return Column(
      children: [
        const SizedBox(height: 16),

        /// ❌ LOGO REMOVED

        /// ILLUSTRATION
        Center(
          child: Image.asset(
            "assets/images/verification/getverified.webp",
            height: 150,
            fit: BoxFit.contain,
          ),
        ),

        const SizedBox(height: 24),

        /// 🔻 BOTTOM CARD
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: CitizenUi.sharedStroke),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                /// TITLE
                const Text(
                  "Why Need to be Fully Verified?",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: Color.fromARGB(255, 0, 106, 255),
                  ),
                ),

                const SizedBox(height: 14),

                /// GRID
                //
                // The aspect ratio has to loosen as the screen narrows: the
                // cards keep their content height (icon + two labels) while the
                // cell width shrinks, so a fixed 1.3 leaves them 40px short on
                // a 320px phone.
                Builder(
                  builder: (context) {
                    final double w = MediaQuery.of(context).size.width;
                    final double ratio = w < 340
                        ? 0.95
                        : (w < 380 ? 1.08 : 1.3);
                    return GridView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 12,
                        childAspectRatio: ratio,
                      ),
                      children: [
                        _featureCard(
                          icon: "assets/images/verification/access.webp",
                          title: "Access Full Services",
                          subtitle: "Unlock all LGU features",
                        ),
                        _featureCard(
                          icon: "assets/images/verification/checksec.webp",
                          title: "Secure & Trusted",
                          subtitle: "Safe and protected account",
                        ),
                        _featureCard(
                          icon: "assets/images/verification/faster.webp",
                          title: "Faster Transaction",
                          subtitle: "Quick processing of request",
                        ),
                        _featureCard(
                          icon: "assets/images/verification/verified.webp",
                          title: "Verified Access",
                          subtitle: "Be recognized as a verified citizen",
                        ),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 12),

                /// ✨ PROFESSIONAL INFO BOX
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: CitizenUi.sharedStroke),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      /// HEADER
                      //
                      // Expanded, like the items below it: without it the
                      // label cannot wrap and pushes the row 41px past the
                      // card on a 320px phone.
                      Row(
                        children: const [
                          Icon(
                            Icons.info_outline,
                            size: 16,
                            color: Color(0xFF6B7280),
                          ),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              "Important Information",
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF374151),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      /// ITEM 1
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Icon(
                            Icons.badge_outlined,
                            size: 14,
                            color: Color(0xFF6B7280),
                          ),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              "Only valid government-issued IDs are accepted for verification.",
                              style: TextStyle(
                                fontSize: 10.5,
                                color: Color(0xFF6B7280),
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      /// ITEM 2
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Icon(
                            Icons.location_on_outlined,
                            size: 14,
                            color: Color(0xFF6B7280),
                          ),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              "Verification is currently available for Aparri residents only.",
                              style: TextStyle(
                                fontSize: 10.5,
                                color: Color(0xFF6B7280),
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      /// ITEM 3
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Icon(
                            Icons.person_outline,
                            size: 14,
                            color: Color(0xFF6B7280),
                          ),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              "Non-residents may continue using the app with limited access.",
                              style: TextStyle(
                                fontSize: 10.5,
                                color: Color(0xFF6B7280),
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                /// BUTTON
                GestureDetector(
                  onTapDown: (_) => setState(() => _scale = 0.96),
                  onTapUp: (_) => setState(() => _scale = 1.0),
                  onTapCancel: () => setState(() => _scale = 1.0),
                  onTap: () {
                    pushLegacy(
                      context,
                      '/verification_id_selection',
                      arguments: widget.username,
                    );
                  },
                  child: AnimatedScale(
                    scale: _scale,
                    duration: const Duration(milliseconds: 120),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: AppColors.green,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        "Verify Now",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================================================
  //  WEB
  //
  //  -- This screen owns the whole window ------------------------------------
  //  The wizard is reached by `pushLegacy` from the SHELL's own context, and
  //  Navigator.of() is nearest-first: the shell's context sits ABOVE the branch
  //  navigators, above the centre-column MediaQuery override and above
  //  CitizenShellScope, so the nearest Navigator looking up from it is
  //  go_router's ROOT one. The gate dialog agrees - showAppDialog defaults to
  //  `useRootNavigator: true`, so `Navigator.of(ctx)` inside it is root too.
  //
  //  So unlike every account page, this is NOT a pane: there is no rail beside
  //  it, no top nav above it, and the MediaQuery it sees is the real viewport.
  //  It gets the kit's page frame because it is a citizen web page, not because
  //  it is inside the shell.
  //
  //  -- Why AppScreenHeader goes ---------------------------------------------
  //  It is a FULL-BLEED white bar. On a phone that is the screen, so its title
  //  and the content below it share an edge. In a browser the bar spans the
  //  window while the content is centred, so on a wide monitor the page's name
  //  sat about a thousand pixels from the card it named. [AccountPageTitle] is
  //  the same header idea - chevron, then the page's name - drawn INSIDE the
  //  measure, so the title, the section labels and the cards share one left
  //  edge. That is rule 1, and there is a test that fails when it drifts.
  //
  //  -- The chevron is not optional here -------------------------------------
  //  `pushLegacy` writes no URL, and there is no shell underneath to fall back
  //  to, so browser Back does not close this page - it leaves the app. Without
  //  a chevron this is a room with no door.
  //
  //  -- No stepper on this screen --------------------------------------------
  //  This is the "why", not a step: nothing has been asked for yet and nothing
  //  can be filled in wrong. A progress bar reading "step 1 of n" before the
  //  flow starts makes the intro look like work.
  // ==========================================================================

  Widget _buildWebScaffold() {
    return Scaffold(
      // Matches the ColorFilter the illustration is modulated with, so the gif's
      // white plate keeps disappearing into the page rather than sitting on a
      // visible square.
      backgroundColor: CitizenUi.pageBg,
      body: SafeArea(
        child: AccountPageBody(
          builder: (context, stack) => FadeTransition(
            opacity: _fadeAnim,
            child: SlideTransition(
              position: _slideAnim,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AccountPageTitle(
                    title: 'Profile Verification',
                    subtitle:
                        'Confirm your identity to unlock the full range of '
                        'LGU services.',
                    onBack: () => Navigator.pop(context),
                    backLabel: 'Back to Settings',
                  ),

                  Center(
                    child: Image.asset(
                      'assets/images/verification/getverified.webp',
                      // The phone draws this at 150 inside a 480 column. The
                      // web measure is 880, so it keeps roughly the same share
                      // of the page instead of shrinking into the middle of it.
                      height: stack ? 150 : 180,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: kAccountSectionGap),

                  const AccountSectionLabel('Why verify your profile'),
                  AccountCard(child: _webFeatureGrid(stack)),
                  const SizedBox(height: kAccountSectionGap),

                  const AccountSectionLabel('Before you start'),
                  const AccountCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _WebInfoRow(
                          icon: Icons.badge_outlined,
                          text:
                              'Only valid government-issued IDs are accepted '
                              'for verification.',
                        ),
                        SizedBox(height: 12),
                        _WebInfoRow(
                          icon: Icons.location_on_outlined,
                          text:
                              'Verification is currently available for Aparri '
                              'residents only.',
                        ),
                        SizedBox(height: 12),
                        _WebInfoRow(
                          icon: Icons.person_outline,
                          text:
                              'Non-residents may continue using the app with '
                              'limited access.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: kAccountSectionGap),

                  _webStartButton(stack),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Four benefits, one row when there is room and two-by-two when there is not.
  ///
  /// [IntrinsicHeight] rather than the phone's `childAspectRatio: 1.3`. A fixed
  /// ratio inside an 880 column makes each cell over 400px tall to hold two
  /// short lines of text; worse, it is a hand-computed shape, so at 125% browser
  /// font size - the 0.6-scale case the kit tests pin - the text outgrows the
  /// box it was measured for. Letting the tallest card set the height cannot
  /// overflow at any text scale.
  Widget _webFeatureGrid(bool stack) {
    const cards = <(String, String, String)>[
      (
        'assets/images/verification/access.webp',
        'Access Full Services',
        'Unlock all LGU features',
      ),
      (
        'assets/images/verification/checksec.webp',
        'Secure & Trusted',
        'Safe and protected account',
      ),
      (
        'assets/images/verification/faster.webp',
        'Faster Transaction',
        'Quick processing of request',
      ),
      (
        'assets/images/verification/verified.webp',
        'Verified Access',
        'Be recognized as a verified citizen',
      ),
    ];

    Widget row(List<(String, String, String)> group) => IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < group.length; i++) ...[
            if (i > 0) const SizedBox(width: kAccountGap),
            Expanded(
              child: _WebFeatureCard(
                icon: group[i].$1,
                title: group[i].$2,
                subtitle: group[i].$3,
              ),
            ),
          ],
        ],
      ),
    );

    if (!stack) return row(cards);
    return Column(
      children: [
        row(cards.sublist(0, 2)),
        const SizedBox(height: kAccountGap),
        row(cards.sublist(2)),
      ],
    );
  }

  /// The CTA keeps the phone's green.
  ///
  /// [accountPrimaryButtonStyle] is reused for every other property - padding,
  /// radius, type - so this sits at exactly the weight of the primary button on
  /// Edit Profile or Change Password, and only the fill differs. The green is
  /// [CitizenUi.accentGreen], an existing token, not a new colour; it is the
  /// app's own colour for THIS action, and the rule is that the app's design
  /// wins where a screen is the same object in both products.
  Widget _webStartButton(bool stack) {
    final button = ElevatedButton(
      onPressed: () => pushLegacy(
        context,
        '/verification_id_selection',
        arguments: widget.username,
      ),
      style: accountPrimaryButtonStyle().copyWith(
        backgroundColor: const WidgetStatePropertyAll(CitizenUi.accentGreen),
      ),
      child: const Text('Verify Now'),
    );

    // Same rule as [AccountActions]: right-aligned when there is room to its
    // right, full width when there is not.
    return stack
        ? SizedBox(width: double.infinity, child: button)
        : Row(mainAxisAlignment: MainAxisAlignment.end, children: [button]);
  }

  /// BUILD
  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return _buildWebScaffold();
    // No AppBar. It carried the PLATFORM back arrow and its own 16px w500
    // title on a grey bar — three ways of differing from every Settings screen
    // this is reached from. AppScreenHeader is the Settings header itself: a
    // white bar with a shadow, the chevron chip, and a w700 blue title.
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFFF3F4F6),
      body: SafeArea(
        child: Column(
          children: [
            // Pinned, like Settings — the header does not slide with the body.
            const AppScreenHeader(title: 'Profile Verification'),
            Expanded(
              child: FadeTransition(
                opacity: _fadeAnim,
                child: SlideTransition(
                  position: _slideAnim,
                  child: MobileFormShell(child: _buildContent()),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==============================================================================
//  Web-only leaves. Nothing below is reachable from the mobile app.
// ==============================================================================

/// One benefit tile.
///
/// The phone draws these at 12.5/10.5 because four of them share a 480 column.
/// On web they share 880, so they are set at the kit's own body sizes - the
/// phone's caption scale inside a desktop card reads as a screenshot of the app
/// rather than as the page you are on.
class _WebFeatureCard extends StatelessWidget {
  final String icon;
  final String title;
  final String subtitle;

  const _WebFeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: CitizenUi.subtle,
        borderRadius: BorderRadius.circular(CitizenUi.controlRadius),
        border: Border.all(color: CitizenUi.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          SizedBox(
            height: 36,
            width: 36,
            child: Image.asset(icon, fit: BoxFit.contain),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: CitizenUi.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              height: 1.35,
              color: CitizenUi.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// One line of the "Before you start" card.
class _WebInfoRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _WebInfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: CitizenUi.textFaint),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.45,
              color: CitizenUi.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
