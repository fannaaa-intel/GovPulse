import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/web/web.dart';
import '../../core/widgets/mobile_form_shell.dart';

class ResetPasswordMethodScreen extends StatefulWidget {
  final VoidCallback onEmailTap;
  final VoidCallback onPhoneTap;

  const ResetPasswordMethodScreen({
    super.key,
    required this.onEmailTap,
    required this.onPhoneTap,
  });

  @override
  State<ResetPasswordMethodScreen> createState() =>
      _ResetPasswordMethodScreenState();
}

class _ResetPasswordMethodScreenState extends State<ResetPasswordMethodScreen>
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
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: MobileFormShell(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                const SizedBox(height: 20),

                Image.asset(
                  "assets/images/applogocrop.png",
                  width: (w * 0.46).clamp(0.0, 200.0).toDouble(),
                ),

                const SizedBox(height: 20),

                Text(
                  "Reset Your Password",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryBlue,
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  "Choose how you want to receive a\nverification code.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                ),

                const SizedBox(height: 40),

                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: widget.onEmailTap,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(
                          "assets/images/email.png",
                          width: 22,
                          height: 22,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          "Email Address",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: widget.onPhoneTap,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(
                          "assets/images/phone.png",
                          width: 22,
                          height: 22,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          "Phone Number",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 36),

                Row(
                  children: [
                    Expanded(child: Divider(color: Colors.grey.shade300)),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        "Or Return to",
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                    ),
                    Expanded(child: Divider(color: Colors.grey.shade300)),
                  ],
                ),

                const SizedBox(height: 18),

                SizedBox(
                  height: 54,
                  width: 170,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.grey.shade300),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(
                          "assets/images/out.png",
                          width: 20,
                          height: 20,
                          color: AppColors.primaryBlue,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          "Log In",
                          style: TextStyle(
                            color: AppColors.primaryBlue,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 25),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  WEB — glass via WebAuthScaffold + WebAuthCard (kit)
  // ══════════════════════════════════════════════════════════════════════════
  Widget _webScaffold(BuildContext context) {
    return WebAuthScaffold(
      heroController: _heroController,
      headline: "Reset your\npassword.",
      subtitle: "Choose how you want to verify\nyour identity and get back in.",
      card: WebAuthCard(
        children: [
          const WebCardHeader(
            title: "Reset your password",
            subtitle:
                "Choose how you'd like to receive your verification code.",
          ),
          const SizedBox(height: 28),

          // ── Method cards — outline → blue on hover (kit rule 2) ──────────
          _MethodCard(
            icon: Icons.email_outlined,
            label: "Email address",
            description: "Receive a code at your registered email",
            onTap: widget.onEmailTap,
          ),
          const SizedBox(height: 12),
          _MethodCard(
            icon: Icons.phone_outlined,
            label: "Phone number",
            description: "Receive a code via SMS to your phone",
            onTap: widget.onPhoneTap,
          ),
          const SizedBox(height: 24),

          WebOutlinedButton(
            icon: Icons.arrow_back_rounded,
            label: "Back to sign in",
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Method option card
//  RULE 2 FIX: rest state uses WebUi kit tokens exclusively.
//              hover state: border → AppColors.primaryBlue (40 % alpha),
//              icon + label → AppColors.primaryBlue. No raw hex.
// ─────────────────────────────────────────────────────────────────────────────
class _MethodCard extends StatefulWidget {
  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onTap;

  const _MethodCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
  });

  @override
  State<_MethodCard> createState() => _MethodCardState();
}

class _MethodCardState extends State<_MethodCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            color: WebUi.pageBg, // no fill, ever
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hovered
                  ? AppColors
                        .primaryBlue // solid blue on hover
                  : WebUi.outlineRest, // visible gray at rest
              width: _hovered ? 1.5 : 1.2,
            ),
          ),
          child: Row(
            children: [
              // Icon container — rest: white bg + outlineRest border.
              //                  hover: primaryBlue tint bg + blue border.
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _hovered
                        ? AppColors.primaryBlue.withValues(alpha: 0.18)
                        : WebUi.outlineRest,
                  ),
                ),
                child: Icon(
                  widget.icon,
                  size: 20,
                  // Rest: WebUi.sub. Hover: primaryBlue. (no raw hex)
                  color: _hovered ? AppColors.primaryBlue : WebUi.sub,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        // Rest: WebUi.ink. Hover: primaryBlue.
                        color: _hovered ? AppColors.primaryBlue : WebUi.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.description,
                      // Description always uses WebUi.faint — subdued, kit token.
                      style: const TextStyle(
                        fontSize: 12,
                        color: WebUi.faint,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                // Rest: faint divider tone. Hover: primaryBlue.
                color: _hovered ? AppColors.primaryBlue : WebUi.divider,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
