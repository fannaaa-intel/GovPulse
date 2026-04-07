import 'package:flutter/material.dart';
import '../../core/utils/password_validator.dart';
import '../../core/widgets/inputs/rounded_input_field.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/indicators/password_strength_bar.dart';

class PhoneSignupScreen extends StatefulWidget {
  final Function(String, String) onContinueClick;
  final VoidCallback onBackClick;
  final VoidCallback onLoginClick;

  const PhoneSignupScreen({
    super.key,
    required this.onContinueClick,
    required this.onBackClick,
    required this.onLoginClick,
  });

  @override
  State<PhoneSignupScreen> createState() => _PhoneSignupScreenState();
}

class _PhoneSignupScreenState extends State<PhoneSignupScreen> {
  String phone = "";
  String username = "";
  String password = "";
  String confirmPassword = "";

  bool showPassword = false;
  bool showConfirmPassword = false;

  bool hasMinLength = false;
  bool hasUpper = false;
  bool hasNumber = false;
  bool hasSpecial = false;
  bool get isPasswordMismatch =>
      confirmPassword.isNotEmpty && password != confirmPassword;

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
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: SingleChildScrollView(
            physics: isKeyboardOpen
                ? const ClampingScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  /// LOGO (matched with SignupScreen)
                  Image.asset(
                    "assets/images/applogocrop.png",
                    width: MediaQuery.of(context).size.width * 0.30,
                  ),

                  const SizedBox(height: 6),

                  /// TITLE
                  Text(
                    "Continue with Mobile Number",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryBlue,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 6),

                  Text(
                    "Verify your mobile number to create an account",
                    style: TextStyle(fontSize: 13, color: AppColors.hint),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 14),

                  RoundedInputField(
                    value: phone,
                    hintText: "Phone Number",
                    icon: Icons.phone,
                    prefix: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text(
                        "+63 ",
                        style: TextStyle(
                          color: AppColors.primaryBlue,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    onChanged: (val) {
                      if (val.length <= 10) {
                        setState(() {
                          phone = val;
                        });
                      }
                    },
                  ),

                  const SizedBox(height: 12),

                  /// USERNAME
                  RoundedInputField(
                    value: username,
                    hintText: "Username",
                    icon: Icons.person,
                    onChanged: (val) {
                      setState(() {
                        username = val;
                      });
                    },
                  ),

                  const SizedBox(height: 14),

                  /// PASSWORD
                  RoundedInputField(
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
                      _requirement("At least 8 characters", hasMinLength),
                      const SizedBox(width: 10),
                      _requirement("Must have number", hasNumber),
                    ],
                  ),

                  const SizedBox(height: 6),

                  Row(
                    children: [
                      _requirement("One uppercase letter", hasUpper),
                      const SizedBox(width: 10),
                      _requirement("One special character", hasSpecial),
                    ],
                  ),

                  const SizedBox(height: 18),

                  /// SIGN UP
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isPasswordValid && phone.length == 10
                            ? AppColors.primaryBlue
                            : AppColors.primaryBlue.withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: isPasswordValid && phone.length == 10
                          ? () async {
                              await widget.onContinueClick(phone, password);
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

                  const SizedBox(height: 8),

                  Text(
                    "We will send you a verification code via SMS",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AppColors.hint),
                  ),

                  const SizedBox(height: 16),

                  /// RETURN
                  Row(
                    children: [
                      Expanded(child: Divider(color: AppColors.stroke)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          "Or Return to",
                          style: TextStyle(fontSize: 13, color: AppColors.hint),
                        ),
                      ),
                      Expanded(child: Divider(color: AppColors.stroke)),
                    ],
                  ),

                  const SizedBox(height: 12),

                  SizedBox(
                    width: 220,
                    height: 56,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppColors.stroke),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: widget.onBackClick,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset(
                            "assets/images/out.png",
                            width: 28,
                            height: 28,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            "Sign Up",
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primaryBlue,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  /// LOGIN
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

                  const SizedBox(height: 20),
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
