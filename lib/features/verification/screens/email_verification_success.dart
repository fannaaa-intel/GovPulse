import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../../core/router/legacy_nav.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/web/web.dart';
import '../../../core/widgets/mobile_form_shell.dart';
import '../../../core/theme/mobile_metrics.dart';

class EmailVerificationSuccess extends StatefulWidget {
  final String email;

  const EmailVerificationSuccess({super.key, required this.email});

  @override
  State<EmailVerificationSuccess> createState() =>
      _EmailVerificationSuccessState();
}

class _EmailVerificationSuccessState extends State<EmailVerificationSuccess>
    with TickerProviderStateMixin {
  late final AnimationController _bgController;
  late final AnimationController _entranceController;
  late final Animation<double> _entranceFade;
  late final Animation<Offset> _entranceSlide;

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    )..repeat(reverse: true);

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();

    _entranceFade = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOut,
    );

    _entranceSlide =
        Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _entranceController,
            curve: Curves.easeOutCubic,
          ),
        );
  }

  @override
  void dispose() {
    _bgController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  String maskEmail(String email) {
    final parts = email.split('@');
    if (parts.length != 2) return email;
    final name = parts[0];
    final domain = parts[1];
    if (name.length <= 2) return email;
    final visible = name.substring(0, 2);
    final hidden = "*" * (name.length - 2);
    return "$visible$hidden@$domain";
  }

  void _continue() {
    goToLogin(context);
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return _mobileScaffold(context);
    return _webScaffold(context);
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  WEB — glass via WebAuthScaffold + WebAuthCard (kit)
  //  FIX: success icon bg + icon color use AppColors.green tokens, not raw hex
  // ══════════════════════════════════════════════════════════════════════════
  Widget _webScaffold(BuildContext context) {
    final maskedEmail = maskEmail(widget.email);

    return WebAuthScaffold(
      heroController: _bgController,
      headline: "You're all\nset.",
      subtitle:
          "Your account is verified. Sign in to report issues,\ndiscover events, and stay connected with Aparri.",
      card: WebAuthCard(
        children: [
          // ── Logo ──────────────────────────────────────────────────────────
          Center(
            child: Image.asset("assets/images/applogocrop.webp", height: 44),
          ),
          const SizedBox(height: 32),

          // ── Success icon — AppColors.green tokens, no raw hex ─────────────
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                // FIX: was Color(0xFFECFDF5) → AppColors.green at 8% opacity
                color: AppColors.green.withValues(alpha: 0.08),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.green.withValues(alpha: 0.20),
                  width: 1.5,
                ),
              ),
              child: Icon(
                Icons.check_rounded,
                size: 36,
                // FIX: was Color(0xFF10B981) → AppColors.green
                color: AppColors.green,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── Title + subtitle via kit styles ───────────────────────────────
          const Text(
            "Email verified",
            textAlign: TextAlign.center,
            style: WebUi.title,
          ),
          const SizedBox(height: 10),

          Text(
            "Your email $maskedEmail has been\nsuccessfully verified.",
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: WebUi.sub, height: 1.6),
          ),
          const SizedBox(height: 32),

          // ── CTA — blue-fill, deepen-on-hover (WebPrimaryButton) ───────────
          WebPrimaryButton(label: "Continue to sign in", onPressed: _continue),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  MOBILE — untouched
  // ══════════════════════════════════════════════════════════════════════════
  Widget _mobileScaffold(BuildContext context) {
    final w = uiScaleWidth(context);
    final maskedEmail = maskEmail(widget.email);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: MobileFormShell(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 26),
            child: FadeTransition(
              opacity: _entranceFade,
              child: SlideTransition(
                position: _entranceSlide,
                child: Column(
                  children: [
                    const SizedBox(height: 40),

                    Image.asset(
                      "assets/images/applogocrop.webp",
                      width: (w * 0.28).clamp(0.0, 140.0).toDouble(),
                    ),

                    const SizedBox(height: 20),

                    Center(
                      child: Image.asset(
                        "assets/images/success.gif",
                        height: 130,
                      ),
                    ),

                    const SizedBox(height: 20),

                    Text(
                      "Email Verification",
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryBlue,
                      ),
                    ),

                    const SizedBox(height: 14),

                    Text(
                      "Your email $maskedEmail\nhas been successfully verified.",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: AppColors.hint),
                    ),

                    const SizedBox(height: 48),

                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryBlue,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () => goToLogin(context),
                        child: const Text(
                          "Continue",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
