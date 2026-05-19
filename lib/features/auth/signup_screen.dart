import 'package:flutter/material.dart';
import '../../core/widgets/inputs/rounded_input_field.dart';
import '../../core/widgets/buttons/social_button.dart';
import '../../core/utils/password_validator.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/indicators/password_strength_bar.dart';
import '../../features/verification/screens/email_verification_screen.dart';
import '../../features/onboarding/otp_loading_screen.dart';
import 'services/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class SignupScreen extends StatefulWidget {
  final Function(String, String, String) onSignUpClick;
  final VoidCallback onLoginClick;
  final VoidCallback onGuestClick;
  final VoidCallback onPhoneClick;

  const SignupScreen({
    super.key,
    required this.onSignUpClick,
    required this.onLoginClick,
    required this.onGuestClick,
    required this.onPhoneClick,
  });

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  String email = "";
  String username = "";
  String password = "";
  String confirmPassword = "";

  bool showPassword = false;
  bool showConfirmPassword = false;
  bool emailLocked = false;

  Timer? _emailDebounce;
  Timer? _usernameDebounce;

  String? emailErrorText;
  String? usernameErrorText;

  bool isCheckingEmail = false;
  bool isCheckingUsername = false;

  bool get isPasswordMismatch =>
      confirmPassword.isNotEmpty && password != confirmPassword;

  final TextEditingController emailController = TextEditingController();
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();

  final FocusNode passwordFocusNode = FocusNode();

  bool hasMinLength = false;
  bool hasUpper = false;
  bool hasNumber = false;
  bool hasSpecial = false;

  @override
  void dispose() {
    emailController.dispose();
    usernameController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    passwordFocusNode.dispose();
    super.dispose();
  }

  void validatePassword(String value) {
    hasMinLength = PasswordValidator.hasMinLength(value);
    hasUpper = PasswordValidator.hasUpper(value);
    hasNumber = PasswordValidator.hasNumber(value);
    hasSpecial = PasswordValidator.hasSpecial(value);
  }

  bool get isPasswordValid =>
      hasMinLength &&
      hasUpper &&
      hasNumber &&
      hasSpecial &&
      password == confirmPassword;

  int get strengthScore => PasswordValidator.strengthScore(password);

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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(), // ✅ ALWAYS SCROLLABLE
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 18),

                  Image.asset(
                    "assets/images/applogocrop.png",
                    width: MediaQuery.of(context).size.width * 0.30,
                  ),

                  const SizedBox(height: 10),

                  Column(
                    children: [
                      Text(
                        "Sign Up for GovPulse",
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryBlue,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Stay Updated and report community\nissues in Aparri",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: AppColors.hint),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  /// 🔥 EMAIL
                  RoundedInputField(
                    controller: emailController,
                    enabled: !emailLocked,
                    value: email,
                    hintText: "Email Address",
                    icon: Icons.email,
                    isError: emailErrorText != null,
                    suffixWidget: isCheckingEmail
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                    onChanged: (val) {
                      setState(() {
                        email = val;
                        emailErrorText = null;
                      });

                      if (_emailDebounce?.isActive ?? false) {
                        _emailDebounce!.cancel();
                      }

                      _emailDebounce = Timer(
                        const Duration(milliseconds: 600),
                        () async {
                          final exists = await AuthService.checkEmailExists(
                            email,
                          );

                          if (!mounted) return;

                          setState(() {
                            isCheckingEmail = false;
                            emailErrorText = exists
                                ? "Email is already used"
                                : null;
                          });
                        },
                      );
                    },
                  ),

                  if (emailErrorText != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          emailErrorText!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),

                  const SizedBox(height: 12),

                  /// 🔥 USERNAME
                  RoundedInputField(
                    controller: usernameController,
                    value: username,
                    hintText: "Username",
                    icon: Icons.person,
                    isError: usernameErrorText != null,
                    suffixWidget: isCheckingUsername
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                    onChanged: (val) {
                      setState(() {
                        username = val;
                        usernameErrorText = null;
                      });

                      if (_usernameDebounce?.isActive ?? false) {
                        _usernameDebounce!.cancel();
                      }

                      _usernameDebounce = Timer(
                        const Duration(milliseconds: 600),
                        () async {
                          if (username.isEmpty) return;

                          setState(() => isCheckingUsername = true);

                          final exists = await AuthService.checkUsernameExists(
                            username,
                          );

                          if (!mounted) return;

                          // 🔥 VERY IMPORTANT (prevents stale result bug)
                          if (username != usernameController.text) return;

                          setState(() {
                            isCheckingUsername = false;
                            usernameErrorText = exists
                                ? "Username is already taken"
                                : null;
                          });
                        },
                      );
                    },
                  ),

                  if (usernameErrorText != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          usernameErrorText!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),

                  const SizedBox(height: 14),

                  /// PASSWORD
                  RoundedInputField(
                    controller: passwordController,
                    focusNode: passwordFocusNode,
                    value: password,
                    hintText: "Password",
                    icon: Icons.lock,
                    obscureText: !showPassword,
                    onChanged: (val) {
                      setState(() {
                        password = val;
                        validatePassword(val);
                      });
                    },
                    suffixWidget: GestureDetector(
                      onTap: () {
                        setState(() {
                          showPassword = !showPassword;
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Image.asset(
                          showPassword
                              ? "assets/images/eye.png"
                              : "assets/images/closed_eye.png",
                          height: 20,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  /// CONFIRM PASSWORD
                  RoundedInputField(
                    controller: confirmPasswordController,
                    value: confirmPassword,
                    hintText: "Confirm Password",
                    icon: Icons.lock,
                    obscureText: !showConfirmPassword,
                    isError: isPasswordMismatch,
                    onChanged: (val) {
                      setState(() {
                        confirmPassword = val;
                      });
                    },
                    suffixWidget: GestureDetector(
                      onTap: () {
                        setState(() {
                          showConfirmPassword = !showConfirmPassword;
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Image.asset(
                          showConfirmPassword
                              ? "assets/images/eye.png"
                              : "assets/images/closed_eye.png",
                          height: 20,
                        ),
                      ),
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
                      _requirement("Atleast 8 characters", hasMinLength),
                      const SizedBox(width: 12),
                      _requirement("Must have number", hasNumber),
                    ],
                  ),

                  const SizedBox(height: 6),

                  Row(
                    children: [
                      _requirement("One uppercase letter", hasUpper),
                      const SizedBox(width: 12),
                      _requirement("One special Character", hasSpecial),
                    ],
                  ),

                  const SizedBox(height: 16),

                  /// 🔥 BUTTON UPDATED CONDITION
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            (isPasswordValid &&
                                emailErrorText == null &&
                                usernameErrorText == null)
                            ? AppColors.primaryBlue
                            : AppColors.primaryBlue.withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed:
                          (isPasswordValid &&
                              emailErrorText == null &&
                              usernameErrorText == null)
                          ? () async {
                              final email = emailController.text.trim();
                              final username = usernameController.text.trim();
                              final password = passwordController.text.trim();

                              try {
                                final success = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => OtpLoadingScreen(
                                      type: "email",
                                      onSendOtp: () async {
                                        final supabase =
                                            Supabase.instance.client;

                                        final canSend = await supabase.rpc(
                                          'can_send_otp',
                                          params: {
                                            'p_identifier': email,
                                            'p_purpose': 'signup',
                                          },
                                        );
                                        if (canSend['allowed'] != true) {
                                          throw Exception(
                                            canSend['message'] as String,
                                          );
                                        }

                                        final response = await http.post(
                                          Uri.parse(
                                            "https://vxvflhjbafqwehuxnmeq.supabase.co/functions/v1/send-email-otp",
                                          ),
                                          headers: {/* unchanged */},
                                          body: jsonEncode({"email": email}),
                                        );

                                        final data = jsonDecode(response.body);

                                        if (response.statusCode != 200 ||
                                            data["success"] != true) {
                                          throw Exception(
                                            data["message"] ??
                                                "Failed to send OTP",
                                          );
                                        }
                                      },
                                    ),
                                  ),
                                );
                                if (!context.mounted) return;
                                if (success != null &&
                                    success["success"] == true) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => VerificationScreen(
                                        email: email,
                                        username: username,
                                        password: password,
                                        onVerifiedSuccess: () {
                                          Navigator.pushReplacementNamed(
                                            context,
                                            '/email_verification_success',
                                            arguments: email,
                                          );
                                        },
                                        onTermsClick: () {},
                                        onConditionsClick: () {},
                                      ),
                                    ),
                                  );
                                }
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(e.toString())),
                                );
                              }
                            }
                          : null,
                      child: const Text(
                        "Sign Up",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  Row(
                    children: [
                      Expanded(child: Divider(color: AppColors.stroke)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          "Or Continue with",
                          style: TextStyle(fontSize: 13, color: AppColors.hint),
                        ),
                      ),
                      Expanded(child: Divider(color: AppColors.stroke)),
                    ],
                  ),

                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: SocialButton(
                          iconPath: "assets/images/guest.png",
                          label: "As Guest",
                          onTap: widget.onGuestClick,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: SocialButton(
                          icon: Icons.phone,
                          isIconData: true,
                          label: "With Phone",
                          onTap: widget.onPhoneClick,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Already have an account? ",
                        style: TextStyle(fontSize: 13, color: AppColors.hint),
                      ),
                      GestureDetector(
                        onTap: widget.onLoginClick,
                        child: Text(
                          "Log In",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryBlue,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _requirement(String text, bool met) {
    return Expanded(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Row(
          key: ValueKey(met),
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
      ),
    );
  }
}
