import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/web/web.dart';
import '../../core/widgets/mobile_form_shell.dart';

class PasswordChangeSuccess extends StatefulWidget {
  const PasswordChangeSuccess({super.key});

  @override
  State<PasswordChangeSuccess> createState() => _PasswordChangeSuccessState();
}

class _PasswordChangeSuccessState extends State<PasswordChangeSuccess>
    with SingleTickerProviderStateMixin {
  late AnimationController _heroController;

  @override
  void initState() {
    super.initState();
    _heroController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _heroController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return _webScaffold(context);
    return _mobileScaffold(context);
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  MOBILE — untouched
  // ══════════════════════════════════════════════════════════════════════════
  Widget _mobileScaffold(BuildContext context) {
    final w = MediaQuery.of(context).size.width;

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
                  "Password Changed",
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryBlue,
                  ),
                ),

                const SizedBox(height: 14),

                const Text(
                  "Your password has been successfully updated.\nYou can now log in with your new password.",
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

  // ══════════════════════════════════════════════════════════════════════════
  //  WEB — glass via WebAuthScaffold + WebAuthCard (kit)
  //  FIX: success icon bg uses AppColors.green tint token, not raw hex
  // ══════════════════════════════════════════════════════════════════════════
  Widget _webScaffold(BuildContext context) {
    return WebAuthScaffold(
      heroController: _heroController,
      headline: "You're all\nset.",
      subtitle:
          "Your password has been updated.\nLog in with your new credentials.",
      card: WebAuthCard(
        children: [
          // ── Logo ──────────────────────────────────────────────────────────
          Center(
            child: Image.asset("assets/images/applogocrop.png", height: 44),
          ),
          const SizedBox(height: 28),

          // ── Success icon — tint derived from AppColors.green, no raw hex ──
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                // green at 8 % opacity — consistent with how kit uses
                // AppColors.green.withValues(alpha: …) elsewhere
                color: AppColors.green.withValues(alpha: 0.08),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.green.withValues(alpha: 0.20),
                  width: 1.5,
                ),
              ),
              child: Icon(
                Icons.check_rounded,
                color: AppColors.green,
                size: 34,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── Title + subtitle via kit styles ───────────────────────────────
          const Text(
            "Password changed",
            textAlign: TextAlign.center,
            style: WebUi.title,
          ),
          const SizedBox(height: 8),
          const Text(
            "Your password has been successfully updated.\nYou can now sign in with your new password.",
            textAlign: TextAlign.center,
            style: WebUi.subtitle,
          ),
          const SizedBox(height: 28),

          // ── CTA — blue-fill, deepen-on-hover (WebPrimaryButton) ───────────
          WebPrimaryButton(
            label: "Continue to sign in",
            onPressed: () => Navigator.of(
              context,
            ).pushNamedAndRemoveUntil('/login', (route) => false),
          ),
        ],
      ),
    );
  }
}
