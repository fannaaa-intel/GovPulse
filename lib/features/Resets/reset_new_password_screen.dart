import 'package:flutter/material.dart';
import '../../core/utils/password_validator.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/inputs/rounded_input_field.dart';
import '../../core/widgets/indicators/password_strength_bar.dart';
import '../../features/Resets/password_successfully_changed.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

class _ResetNewPasswordScreenState extends State<ResetNewPasswordScreen> {
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmController = TextEditingController();

  bool showPassword = false;
  bool showConfirm = false;
  bool isLoading = false;

  String? apiError; // ✅ error state

  bool hasMinLength = false;
  bool hasUpper = false;
  bool hasNumber = false;
  bool hasSpecial = false;

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
  void dispose() {
    passwordController.dispose();
    confirmController.dispose();
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
      apiError = null; // reset error
    });

    try {
      final supabase = Supabase.instance.client;

      await supabase.auth.setSession(widget.refreshToken);

      final res = await supabase.auth.updateUser(
        UserAttributes(password: password),
      );

      if (!mounted) return;

      if (res.user != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const PasswordChangeSuccess()),
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
    final password = passwordController.text;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 26),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 25),

                  Image.asset(
                    "assets/images/applogocrop.png",
                    width: MediaQuery.of(context).size.width * 0.40,
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

                  /// PASSWORD
                  RoundedInputField(
                    controller: passwordController,
                    value: passwordController.text,
                    hintText: "Password",
                    icon: Icons.lock,
                    obscureText: !showPassword,
                    onChanged: (val) {
                      validatePassword(val);
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
                    controller: confirmController,
                    value: confirmController.text,
                    hintText: "Confirm Password",
                    icon: Icons.lock,
                    obscureText: !showConfirm,
                    isError: isPasswordMismatch,
                    onChanged: (val) {
                      setState(() {});
                    },
                    suffixWidget: GestureDetector(
                      onTap: () {
                        setState(() {
                          showConfirm = !showConfirm;
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Image.asset(
                          showConfirm
                              ? "assets/images/eye.png"
                              : "assets/images/closed_eye.png",
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

                  /// 🔴 API ERROR
                  if (apiError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        apiError!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ),

                  /// BUTTON
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
                          ? const CircularProgressIndicator(color: Colors.white)
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
                          style: TextStyle(fontSize: 13, color: Colors.grey),
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
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                      },
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
    );
  }
}
