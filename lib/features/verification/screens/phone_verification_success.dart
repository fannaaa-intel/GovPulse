import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/web/web.dart';
import '../../../core/widgets/mobile_form_shell.dart';

class PhoneVerificationSuccess extends StatefulWidget {
  final String phone;

  const PhoneVerificationSuccess({super.key, required this.phone});

  @override
  State<PhoneVerificationSuccess> createState() =>
      _PhoneVerificationSuccessState();
}

class _PhoneVerificationSuccessState extends State<PhoneVerificationSuccess>
    with TickerProviderStateMixin {
  late final AnimationController _bgController;

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _bgController.dispose();
    super.dispose();
  }

  String maskPhone(String phone) {
    if (phone.length < 6) return phone;
    final start = phone.substring(0, 3);
    final end = phone.substring(phone.length - 2);
    final hidden = "*" * (phone.length - 5);
    return "$start$hidden$end";
  }

  void _continue() {
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
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
    final maskedPhone = maskPhone(widget.phone);

    return WebAuthScaffold(
      heroController: _bgController,
      headline: "You're all\nset.",
      subtitle:
          "Your number is verified. Sign in to report issues,\ndiscover events, and stay connected with Aparri.",
      card: WebAuthCard(
        children: [
          // ── Logo ──────────────────────────────────────────────────────────
          Center(
            child: Image.asset("assets/images/applogocrop.png", height: 44),
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
            "Phone verified",
            textAlign: TextAlign.center,
            style: WebUi.title,
          ),
          const SizedBox(height: 10),

          Text(
            "Your phone number $maskedPhone has\nbeen successfully verified.",
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
    final w = MediaQuery.of(context).size.width;
    final maskedPhone = maskPhone(widget.phone);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: MobileFormShell(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 26),
            child: Column(
              children: [
                const SizedBox(height: 40),

                Image.asset(
                  "assets/images/applogocrop.png",
                  width: (w * 0.28).clamp(0.0, 140.0).toDouble(),
                ),

                const SizedBox(height: 20),

                Center(
                  child: Image.asset("assets/images/success.gif", height: 130),
                ),

                const SizedBox(height: 20),

                Text(
                  "Phone Verification",
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryBlue,
                  ),
                ),

                const SizedBox(height: 14),

                Text(
                  "Your phone number $maskedPhone\nhas been successfully verified.",
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
                    onPressed: () => Navigator.of(
                      context,
                    ).pushNamedAndRemoveUntil('/login', (route) => false),
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
    );
  }
}
