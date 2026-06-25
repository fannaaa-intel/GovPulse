import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/inputs/rounded_input_field.dart';
import '../../../core/widgets/responsive_page.dart';
import '../../../core/utils/password_validator.dart';
import '../../../core/widgets/indicators/password_strength_bar.dart';
import '../../../core/network/network_wrapper.dart';

class SetPasswordScreen extends StatefulWidget {
  const SetPasswordScreen({super.key});

  @override
  State<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends State<SetPasswordScreen>
    with TickerProviderStateMixin {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  String password = '';
  String confirmPassword = '';
  bool showPassword = false;
  bool showConfirm = false;
  bool isLoading = false;
  String? errorText;

  bool hasMinLength = false;
  bool hasUpper = false;
  bool hasNumber = false;
  bool hasSpecial = false;

  // ── Content-only slide-up animation (header stays fixed) ─────────────────
  late final AnimationController _slideCtrl;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();

    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));
    _fadeAnim = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 80), () {
        if (mounted) _slideCtrl.forward();
      });
    });
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    _slideCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _onPasswordChanged(String val) {
    setState(() {
      password = val;
      hasMinLength = PasswordValidator.hasMinLength(val);
      hasUpper = PasswordValidator.hasUpper(val);
      hasNumber = PasswordValidator.hasNumber(val);
      hasSpecial = PasswordValidator.hasSpecial(val);
    });
  }

  bool get isPasswordMismatch =>
      confirmPassword.isNotEmpty && password != confirmPassword;

  bool get isPasswordValid =>
      hasMinLength &&
      hasUpper &&
      hasNumber &&
      hasSpecial &&
      password == confirmPassword;

  bool get canSubmit => isPasswordValid && !isLoading;

  int get strengthScore => PasswordValidator.strengthScore(password);

  Color get strengthColor {
    if (strengthScore <= 1) return AppColors.red;
    if (strengthScore <= 3) return AppColors.orange;
    return AppColors.green;
  }

  String get strengthText {
    if (strengthScore <= 1) return 'Weak';
    if (strengthScore <= 3) return 'Medium';
    return 'Strong';
  }

  Future<void> _submit() async {
    if (!canSubmit) return;
    setState(() {
      isLoading = true;
      errorText = null;
    });

    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: password),
      );
      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) Navigator.pop(context, true);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
        errorText = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
        errorText = 'Something went wrong. Please try again.';
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return NetworkWrapper(
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F4F6),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            color: AppColors.primaryBlue,
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            'Set Password',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryBlue,
            ),
          ),
          centerTitle: true,
        ),
        // ── Content slides up, AppBar stays fixed ──────────────────────────
        body: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: ResponsivePageBody(
              maxWidth: 560,
              child: GestureDetector(
                onTap: () => FocusScope.of(context).unfocus(),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Facebook badge ───────────────────────────────────
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE7F0FF),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFBFD4FA)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1877F2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: const Text(
                                'f',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 19,
                                  fontWeight: FontWeight.bold,
                                  height: 1,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'You\'re signed in via Facebook. Setting a password lets you also log in with your email.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.primaryBlue,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 28),

                      // ── New password ─────────────────────────────────────
                      Text(
                        'New password',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.hint,
                        ),
                      ),
                      const SizedBox(height: 8),
                      RoundedInputField(
                        controller: _passwordController,
                        value: password,
                        hintText: 'Password',
                        icon: Icons.lock,
                        obscureText: !showPassword,
                        onChanged: _onPasswordChanged,
                        suffixWidget: GestureDetector(
                          onTap: () =>
                              setState(() => showPassword = !showPassword),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Icon(
                              showPassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 20,
                              color: AppColors.primaryBlue,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // ── Confirm password ─────────────────────────────────
                      RoundedInputField(
                        controller: _confirmController,
                        value: confirmPassword,
                        hintText: 'Confirm Password',
                        icon: Icons.lock,
                        obscureText: !showConfirm,
                        isError: isPasswordMismatch,
                        onChanged: (val) =>
                            setState(() => confirmPassword = val),
                        suffixWidget: GestureDetector(
                          onTap: () =>
                              setState(() => showConfirm = !showConfirm),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Icon(
                              showConfirm
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 20,
                              color: AppColors.primaryBlue,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),

                      // ── Strength bar ─────────────────────────────────────
                      if (password.isNotEmpty) ...[
                        Text(
                          'Strength: $strengthText',
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

                      // ── Requirements ─────────────────────────────────────
                      Row(
                        children: [
                          _req('Atleast 8 characters', hasMinLength),
                          const SizedBox(width: 12),
                          _req('Must have number', hasNumber),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _req('One uppercase letter', hasUpper),
                          const SizedBox(width: 12),
                          _req('One special character', hasSpecial),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // ── Error ────────────────────────────────────────────
                      if (errorText != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            errorText!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      // ── Submit ───────────────────────────────────────────
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: canSubmit
                                ? AppColors.primaryBlue
                                : AppColors.primaryBlue.withValues(alpha: 0.4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: canSubmit ? _submit : null,
                          child: isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Text(
                                  'Set Password',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),

                      const SizedBox(height: 24),
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

  Widget _req(String text, bool met) {
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
}
