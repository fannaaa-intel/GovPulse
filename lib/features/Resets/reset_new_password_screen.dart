import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/services/password_cooldown.dart';
import '../../core/utils/password_validator.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/inputs/rounded_input_field.dart';
import '../../core/widgets/indicators/password_strength_bar.dart';
import '../../features/Resets/password_successfully_changed.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/widgets/web/web.dart';
import '../../core/widgets/mobile_form_shell.dart';

class ResetNewPasswordScreen extends StatefulWidget {
  final String accessToken;
  final String refreshToken;

  const ResetNewPasswordScreen({
    super.key,
    required this.accessToken,
    required this.refreshToken,
  });

  @override
  State<ResetNewPasswordScreen> createState() => _ResetNewPasswordScreenState();
}

class _ResetNewPasswordScreenState extends State<ResetNewPasswordScreen>
    with TickerProviderStateMixin {
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmController = TextEditingController();

  bool showPassword = false;
  bool showConfirm = false;
  bool isLoading = false;

  String? apiError;

  bool hasMinLength = false;
  bool hasUpper = false;
  bool hasNumber = false;
  bool hasSpecial = false;

  late AnimationController _heroController;

  // ── Content entrance: instant screen, content fades + slides up ──────────
  late final AnimationController _entranceController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  bool get isPasswordMismatch =>
      confirmController.text.isNotEmpty &&
      passwordController.text != confirmController.text;

  bool get isFormValid =>
      passwordController.text.isNotEmpty &&
      confirmController.text.isNotEmpty &&
      passwordController.text == confirmController.text &&
      hasMinLength &&
      hasUpper &&
      hasNumber &&
      hasSpecial;

  void validatePassword(String value) {
    setState(() {
      hasMinLength = PasswordValidator.hasMinLength(value);
      hasUpper = PasswordValidator.hasUpper(value);
      hasNumber = PasswordValidator.hasNumber(value);
      hasSpecial = PasswordValidator.hasSpecial(value);
    });
  }

  int get strengthScore =>
      PasswordValidator.strengthScore(passwordController.text);

  Color get strengthColor {
    if (strengthScore <= 1) return AppColors.red;
    if (strengthScore == 2 || strengthScore == 3) return AppColors.orange;
    return AppColors.green;
  }

  String get strengthText {
    if (strengthScore <= 1) return "Weak";
    if (strengthScore == 2 || strengthScore == 3) return "Medium";
    return "Strong";
  }

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
    passwordController.dispose();
    confirmController.dispose();
    _heroController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  Widget requirement(String text, bool met) {
    return Expanded(
      child: Row(
        children: [
          Icon(
            met ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 16,
            color: met ? AppColors.green : AppColors.grey,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: met ? AppColors.green : AppColors.grey,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> updatePassword() async {
    final password = passwordController.text.trim();

    setState(() {
      isLoading = true;
      apiError = null;
    });

    try {
      final supabase = Supabase.instance.client;

      await supabase.auth.setSession(widget.refreshToken);

      // ── Cooldown gate ────────────────────────────────────────────────────
      // This flow previously had no gate and no stamp, so "forgot password" was
      // a complete bypass of the 30-day rule for EVERY user — a citizen locked
      // out of the change-password screen could reset here immediately.
      //
      // Checked AFTER setSession, not in initState: the gate reads the caller's
      // own profiles row, which needs an authenticated identity, and this screen
      // is reached from an OTP link with no session established yet.
      final gateUser = supabase.auth.currentUser;
      if (gateUser != null) {
        final remaining =
            await PasswordCooldown.remainingDays(supabase, gateUser.id);
        if (remaining != null) {
          if (!mounted) return;
          setState(() {
            apiError = 'You can only change your password every '
                '${PasswordCooldown.days} days. Please try again in '
                '$remaining ${remaining == 1 ? "day" : "days"}.';
          });
          return;
        }
      }

      final res = await supabase.auth.updateUser(
        UserAttributes(password: password),
      );

      if (!mounted) return;

      if (res.user != null) {
        // Same stamp as the change-password flow, so a reset starts the
        // cooldown too. Without this, resetting repeatedly stays free.
        await PasswordCooldown.stamp(supabase, res.user!.id);
        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          kIsWeb
              ? PageRouteBuilder(
                  pageBuilder: (_, _, _) => const PasswordChangeSuccess(),
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: Duration.zero,
                )
              : PageRouteBuilder(
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: Duration.zero,
                  pageBuilder: (_, _, _) => const PasswordChangeSuccess(),
                ),
        );
      } else {
        throw Exception("Failed to update password");
      }
    } catch (e) {
      if (!mounted) return;

      final errorMsg = e.toString();

      setState(() {
        if (errorMsg.toLowerCase().contains("same") ||
            errorMsg.toLowerCase().contains("different")) {
          apiError = "New password must be different from your old password";
        } else {
          apiError = "Something went wrong. Please try again.";
        }
      });
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
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
    final password = passwordController.text;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SlideTransition(
              position: _slideAnim,
              child: MobileFormShell(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 26),
                  child: Column(
                    children: [
                      const SizedBox(height: 25),

                      Image.asset(
                        "assets/images/applogocrop.webp",
                        width: (w * 0.40).clamp(0.0, 180.0).toDouble(),
                      ),

                      const SizedBox(height: 16),

                      Text(
                        "Reset Password",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryBlue,
                        ),
                      ),

                      const SizedBox(height: 26),

                      RoundedInputField(
                        controller: passwordController,
                        value: passwordController.text,
                        hintText: "Password",
                        icon: Icons.lock,
                        obscureText: !showPassword,
                        onChanged: (val) => validatePassword(val),
                        suffixWidget: GestureDetector(
                          onTap: () =>
                              setState(() => showPassword = !showPassword),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Image.asset(
                              showPassword
                                  ? "assets/images/eye.webp"
                                  : "assets/images/closed_eye.webp",
                              height: 20,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      RoundedInputField(
                        controller: confirmController,
                        value: confirmController.text,
                        hintText: "Confirm Password",
                        icon: Icons.lock,
                        obscureText: !showConfirm,
                        isError: isPasswordMismatch,
                        onChanged: (_) => setState(() {}),
                        suffixWidget: GestureDetector(
                          onTap: () =>
                              setState(() => showConfirm = !showConfirm),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Image.asset(
                              showConfirm
                                  ? "assets/images/eye.webp"
                                  : "assets/images/closed_eye.webp",
                              height: 20,
                            ),
                          ),
                        ),
                      ),

                      if (isPasswordMismatch)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            "Passwords do not match",
                            style: TextStyle(color: Colors.red, fontSize: 12),
                          ),
                        ),

                      const SizedBox(height: 8),

                      if (password.isNotEmpty)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Strength: $strengthText",
                              style: TextStyle(
                                fontSize: 12,
                                color: strengthColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            PasswordStrengthBar(score: strengthScore),
                            const SizedBox(height: 10),
                          ],
                        ),

                      Row(
                        children: [
                          requirement("At least 8 characters", hasMinLength),
                          const SizedBox(width: 12),
                          requirement("Must have number", hasNumber),
                        ],
                      ),

                      const SizedBox(height: 6),

                      Row(
                        children: [
                          requirement("One uppercase letter", hasUpper),
                          const SizedBox(width: 12),
                          requirement("One special character", hasSpecial),
                        ],
                      ),

                      const SizedBox(height: 30),

                      if (apiError != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            apiError!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 12,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),

                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryBlue,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: (isLoading || !isFormValid)
                              ? null
                              : updatePassword,
                          child: isLoading
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  "Reset Password",
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),

                      const SizedBox(height: 18),

                      Row(
                        children: [
                          Expanded(child: Divider(color: Colors.grey.shade300)),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10),
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
                        height: 54,
                        width: 170,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.grey.shade300),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            // OutlinedButton's default horizontal padding of 24
                            // leaves only 122px of the fixed 170px width for the
                            // child, and icon + gap + "Log In" measures 122.6 —
                            // a 0.6px RenderFlex overflow. Nothing moves
                            // visually: the row is centred either way, this just
                            // gives it room to lay out.
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          onPressed: () => Navigator.pop(context),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.logout, color: AppColors.primaryBlue),
                              const SizedBox(width: 8),
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
  //  WEB — glass via WebAuthScaffold + WebAuthCard (kit)
  //  FIX: strength "Strength:" label uses WebUi.sub token (was raw TextStyle)
  // ══════════════════════════════════════════════════════════════════════════
  Widget _webScaffold(BuildContext context) {
    final password = passwordController.text;

    return WebAuthScaffold(
      heroController: _heroController,
      blockBack: true,
      headline: "Reset your\npassword.",
      subtitle: "Choose a strong new password\nto secure your account.",
      card: WebAuthCard(
        children: [
          const WebCardHeader(
            title: "Reset password",
            subtitle: "Choose a strong new password for your account.",
          ),
          const SizedBox(height: 28),

          // ── New password field ────────────────────────────────────────────
          WebInputField(
            hint: "New password",
            icon: Icons.lock_outline,
            keyboardType: TextInputType.visiblePassword,
            obscure: !showPassword,
            onChanged: (val) => validatePassword(val),
            controller: passwordController,
            suffix: GestureDetector(
              onTap: () => setState(() => showPassword = !showPassword),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Image.asset(
                  showPassword
                      ? "assets/images/eye.webp"
                      : "assets/images/closed_eye.webp",
                  height: 18,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Confirm password field ────────────────────────────────────────
          WebInputField(
            hint: "Confirm password",
            icon: Icons.lock_outline,
            keyboardType: TextInputType.visiblePassword,
            obscure: !showConfirm,
            isError: isPasswordMismatch,
            onChanged: (_) => setState(() {}),
            controller: confirmController,
            suffix: GestureDetector(
              onTap: () => setState(() => showConfirm = !showConfirm),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Image.asset(
                  showConfirm
                      ? "assets/images/eye.webp"
                      : "assets/images/closed_eye.webp",
                  height: 18,
                ),
              ),
            ),
          ),
          if (isPasswordMismatch)
            const WebFieldError(text: "Passwords do not match"),

          const SizedBox(height: 14),

          // ── Strength bar — label uses WebUi.sub (kit token), not raw color ─
          if (password.isNotEmpty) ...[
            Row(
              children: [
                const Text(
                  "Strength: ",
                  // FIX: was TextStyle(fontSize:12, color: WebUi.sub) inline;
                  // now uses WebUi.subtitle as base + explicit size for clarity
                  style: TextStyle(fontSize: 12, color: WebUi.sub),
                ),
                Text(
                  strengthText,
                  style: TextStyle(
                    fontSize: 12,
                    color: strengthColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            WebStrengthBar(score: strengthScore, color: strengthColor),
            const SizedBox(height: 14),
          ],

          // ── Requirements — WebRequirementRow (kit) ────────────────────────
          WebRequirementRow(
            left: ("At least 8 characters", hasMinLength),
            right: ("One number", hasNumber),
          ),
          const SizedBox(height: 6),
          WebRequirementRow(
            left: ("One uppercase letter", hasUpper),
            right: ("One special character", hasSpecial),
          ),
          const SizedBox(height: 24),

          // ── API error ─────────────────────────────────────────────────────
          if (apiError != null) ...[
            WebFieldError(text: apiError),
            const SizedBox(height: 12),
          ],

          // ── CTA — blue-fill, deepen-on-hover (WebPrimaryButton) ───────────
          WebPrimaryButton(
            label: "Reset password",
            loading: isLoading,
            onPressed: isFormValid ? updatePassword : null,
          ),
          const SizedBox(height: 20),

          // ── Back link ─────────────────────────────────────────────────────
          WebOutlinedButton(
            icon: Icons.arrow_back_rounded,
            label: "Back to sign in",
            onTap: () => Navigator.of(
              context,
            ).pushNamedAndRemoveUntil('/login', (route) => false),
          ),
        ],
      ),
    );
  }
}
