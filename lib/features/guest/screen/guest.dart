import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/web/web.dart';
import '../../../core/widgets/mobile_form_shell.dart';

class GuestScreen extends StatefulWidget {
  const GuestScreen({super.key});

  @override
  State<GuestScreen> createState() => _GuestScreenState();
}

class _GuestScreenState extends State<GuestScreen>
    with TickerProviderStateMixin {
  // ── Entrance + background animations ─────────────────────────────────────
  // The screen itself pops in instantly (caller uses zero-duration PageRouteBuilder).
  // The content slides up and fades in on its own timeline.
  late final AnimationController _entranceController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;
  late final AnimationController _bgController;

  @override
  void initState() {
    super.initState();

    // Content entrance: 500 ms slide-up + fade
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOut,
    );
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _entranceController,
            curve: Curves.easeOutCubic,
          ),
        );

    // Background blob animation (web hero panel)
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat(reverse: true);

    // Tiny delay lets the route settle before animating — avoids 1-frame stutter
    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) _entranceController.forward();
    });
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _bgController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return kIsWeb ? _webScaffold(context) : _mobileScaffold(context);
  }

  // ── Web layout ────────────────────────────────────────────────────────────
  Widget _webScaffold(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final bool wide = width >= kWebTwoPanelMinWidth;
    final double hPad = wide ? 48 : (width < 600 ? 24 : 40);

    final Widget card = WebGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const WebCardHeader(
            title: "Continue as Guest",
            subtitle: "Explore GovPulse without creating an account.",
          ),
          const SizedBox(height: 32),
          _webFeatureCard(),
          const SizedBox(height: 28),
          WebPrimaryButton(label: "Continue as Guest", onPressed: () {}),
          const SizedBox(height: 12),
          _webCreateAccountButton(context),
          const SizedBox(height: 8),
          const WebCaption(
            "You can create an account any time to unlock full access.",
          ),
        ],
      ),
    );

    // The card area wraps the card in the entrance animation so content
    // slides up and fades regardless of whether we're in wide or compact mode.
    final Widget cardArea = Center(
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 44),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SlideTransition(position: _slideAnim, child: card),
          ),
        ),
      ),
    );

    if (wide) {
      return Scaffold(
        backgroundColor: kHeroBgBottom,
        body: Row(
          children: [
            Expanded(
              flex: 56,
              child: WebHeroPanel(
                bgController: _bgController,
                headline: "Explore your\ncommunity\nfreely.",
                subtitle:
                    "Browse reports, discover local events, and\nsee what's happening around Aparri — no\naccount needed.",
              ),
            ),
            Expanded(flex: 44, child: WebGlassSurface(child: cardArea)),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFEFF3FB),
      body: WebGlassSurface(child: SafeArea(child: cardArea)),
    );
  }

  Widget _webFeatureCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WebUi.divider),
        color: const Color(0xFFF6F7FB),
      ),
      child: const Column(
        children: [
          _FeatureItem(
            icon: Icons.visibility_outlined,
            text: "View community reports and updates",
          ),
          SizedBox(height: 12),
          _FeatureItem(
            icon: Icons.map_outlined,
            text: "Explore reported issues around Aparri",
          ),
          SizedBox(height: 12),
          _FeatureItem(
            icon: Icons.lock_outline,
            text: "Reporting issues requires an account",
          ),
        ],
      ),
    );
  }

  Widget _webCreateAccountButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: WebUi.buttonHeight,
      child: OutlinedButton(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.all(Colors.transparent),
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          side: WidgetStateProperty.resolveWith((states) {
            final active =
                states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.pressed);
            return BorderSide(
              color: active ? AppColors.primaryBlue : const Color(0xFFCBD2DE),
              width: active ? 1.4 : 1.2,
            );
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            final active =
                states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.pressed);
            return active ? AppColors.primaryBlue : const Color(0xFF374151);
          }),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(WebUi.buttonRadius),
            ),
          ),
          elevation: WidgetStateProperty.all(0),
        ),
        onPressed: () => Navigator.pushNamed(context, '/signup'),
        child: const Text(
          "Create Account",
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
        ),
      ),
    );
  }

  // ── Mobile layout ─────────────────────────────────────────────────────────
  Widget _mobileScaffold(BuildContext context) {
    final w = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.white,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          // Wrap the entire scrollable body in the entrance animation
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SlideTransition(
              position: _slideAnim,
              child: MobileFormShell(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 26,
                    vertical: 20,
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 24),

                      // LOGO
                      Image.asset(
                        "assets/images/applogocrop.webp",
                        width: (w * 0.55).clamp(0.0, 200.0).toDouble(),
                      ),

                      const SizedBox(height: 30),

                      // TITLE
                      const Text(
                        "Continue as Guest",
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryBlue,
                        ),
                      ),

                      const SizedBox(height: 10),

                      const Text(
                        "Explore GovPulse without creating an account.",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: AppColors.hint),
                      ),

                      const SizedBox(height: 30),

                      // INFO CARD
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.stroke),
                          color: const Color(0xFFF6F7FB),
                        ),
                        child: const Column(
                          children: [
                            _FeatureItem(
                              icon: Icons.visibility_outlined,
                              text: "View community reports and updates",
                            ),
                            SizedBox(height: 12),
                            _FeatureItem(
                              icon: Icons.map_outlined,
                              text: "Explore reported issues around Aparri",
                            ),
                            SizedBox(height: 12),
                            _FeatureItem(
                              icon: Icons.lock_outline,
                              text: "Reporting issues requires an account",
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 40),

                      // CONTINUE BUTTON
                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryBlue,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                          ),
                          onPressed: () {},
                          child: const Text(
                            "Continue as Guest",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // CREATE ACCOUNT BUTTON
                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(
                              color: AppColors.primaryBlue,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: () =>
                              Navigator.pushNamed(context, '/signup'),
                          child: const Text(
                            "Create Account",
                            style: TextStyle(
                              color: AppColors.primaryBlue,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Shared feature row ────────────────────────────────────────────────────────

class _FeatureItem extends StatelessWidget {
  final IconData icon;
  final String text;

  const _FeatureItem({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primaryBlue, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14, color: AppColors.hint),
          ),
        ),
      ],
    );
  }
}
