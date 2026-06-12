import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/inputs/rounded_input_field.dart';
import '../../core/widgets/web/web.dart';
import '../../core/widgets/mobile_form_shell.dart';

class ResetPasswordPhoneScreen extends StatefulWidget {
  final VoidCallback onVerify;
  final VoidCallback onLogin;

  const ResetPasswordPhoneScreen({
    super.key,
    required this.onVerify,
    required this.onLogin,
  });

  @override
  State<ResetPasswordPhoneScreen> createState() =>
      _ResetPasswordPhoneScreenState();
}

class _ResetPasswordPhoneScreenState extends State<ResetPasswordPhoneScreen>
    with TickerProviderStateMixin {
  String phone = "";

  late AnimationController _heroController;

  // ── Content entrance: instant screen, content fades + slides up ──────────
  late final AnimationController _entranceController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _heroController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);

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

    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) _entranceController.forward();
    });
  }

  @override
  void dispose() {
    _heroController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return _webScaffold(context);
    return _mobileScaffold(context);
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  MOBILE — MobileFormShell + logo clamp applied
  // ══════════════════════════════════════════════════════════════════════════
  Widget _mobileScaffold(BuildContext context) {
    final w = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SlideTransition(
              position: _slideAnim,
              child: MobileFormShell(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 26),
                  child: Column(
                    children: [
                      const SizedBox(height: 30),

                      Image.asset(
                        "assets/images/applogocrop.webp",
                        width: (w * 0.32).clamp(0.0, 160.0).toDouble(),
                      ),

                      const SizedBox(height: 14),

                      Text(
                        "Reset Password",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryBlue,
                        ),
                      ),

                      const SizedBox(height: 6),

                      Text(
                        "Enter your Phone Number to receive a\nverification code.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),

                      const SizedBox(height: 22),

                      RoundedInputField(
                        value: phone,
                        hintText: "Phone number",
                        icon: Icons.phone,
                        prefix: Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Text(
                            "+63",
                            style: TextStyle(
                              color: AppColors.primaryBlue,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        onChanged: (val) {
                          if (val.length <= 10) {
                            setState(() => phone = val);
                          }
                        },
                      ),

                      const SizedBox(height: 18),

                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryBlue,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: phone.length == 10
                              ? widget.onVerify
                              : null,
                          child: const Text(
                            "Verify Code",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),

                      Text(
                        "We will send you a verification code via SMS",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),

                      const SizedBox(height: 26),

                      Row(
                        children: [
                          Expanded(child: Divider(color: Colors.grey.shade300)),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              "Or Return to",
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                          Expanded(child: Divider(color: Colors.grey.shade300)),
                        ],
                      ),

                      const SizedBox(height: 16),

                      SizedBox(
                        height: 56,
                        width: 170,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.grey.shade300),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: widget.onLogin,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Image.asset(
                                "assets/images/out.webp",
                                width: 20,
                                height: 20,
                                color: AppColors.primaryBlue,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                "Log In",
                                style: TextStyle(
                                  color: AppColors.primaryBlue,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),
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

  // ══════════════════════════════════════════════════════════════════════════
  //  WEB — already on kit, unchanged
  // ══════════════════════════════════════════════════════════════════════════
  Widget _webScaffold(BuildContext context) {
    return WebAuthScaffold(
      heroController: _heroController,
      headline: "Reset your\npassword.",
      subtitle: "Enter your phone number and we'll\nsend a code via SMS.",
      card: WebAuthCard(
        children: [
          const WebCardHeader(
            title: "Reset password",
            subtitle: "Enter your phone number to receive a verification code.",
          ),
          const SizedBox(height: 28),
          _WebPhoneField(
            onChanged: (val) {
              if (val.length <= 10) setState(() => phone = val);
            },
          ),
          const SizedBox(height: 20),
          WebPrimaryButton(
            label: "Send verification code",
            onPressed: phone.length == 10 ? widget.onVerify : null,
          ),
          const SizedBox(height: 10),
          const WebCaption("We'll send a 6-digit code via SMS."),
          const SizedBox(height: 24),
          WebOutlinedButton(
            icon: Icons.arrow_back_rounded,
            label: "Back to sign in",
            onTap: widget.onLogin,
          ),
        ],
      ),
    );
  }
}

// ── Phone field with +63 prefix ──────────────────────────────────────────────
class _WebPhoneField extends StatefulWidget {
  final ValueChanged<String> onChanged;
  const _WebPhoneField({required this.onChanged});

  @override
  State<_WebPhoneField> createState() => _WebPhoneFieldState();
}

class _WebPhoneFieldState extends State<_WebPhoneField> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: 56,
      decoration: BoxDecoration(
        color: _focused ? Colors.white : const Color(0xFFF8F9FC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _focused ? AppColors.primaryBlue : const Color(0xFFE3E6EF),
          width: _focused ? 1.5 : 1.0,
        ),
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: AppColors.primaryBlue.withValues(alpha: 0.07),
                  blurRadius: 0,
                  spreadRadius: 3,
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          Icon(
            Icons.phone_outlined,
            size: 17,
            color: _focused ? AppColors.primaryBlue : AppColors.hint,
          ),
          const SizedBox(width: 10),
          Container(
            height: 20,
            width: 1,
            color: const Color(0xFFE3E6EF),
            margin: const EdgeInsets.symmetric(horizontal: 8),
          ),
          Text(
            "+63",
            style: TextStyle(
              color: AppColors.primaryBlue,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Focus(
              onFocusChange: (f) => setState(() => _focused = f),
              child: TextField(
                keyboardType: TextInputType.phone,
                maxLength: 10,
                buildCounter:
                    (
                      _, {
                      required currentLength,
                      required isFocused,
                      maxLength,
                    }) => null,
                onChanged: widget.onChanged,
                cursorColor: AppColors.primaryBlue,
                cursorWidth: 1.4,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF111827),
                  fontWeight: FontWeight.w500,
                ),
                decoration: InputDecoration(
                  hintText: "9XX XXX XXXX",
                  hintStyle: TextStyle(color: AppColors.hint, fontSize: 14),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
        ],
      ),
    );
  }
}
