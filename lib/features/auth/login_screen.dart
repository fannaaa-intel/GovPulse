import 'package:flutter/material.dart';

import '../../core/widgets/inputs/rounded_input_field.dart';
import '../../core/widgets/buttons/social_button.dart';
import '../../core/theme/app_colors.dart';

class LoginScreen extends StatefulWidget {
  final Future<void> Function(String, String) onLoginClick;
  final VoidCallback onSignUpClick;

  final VoidCallback? onGuestClick;
  final VoidCallback? onPhoneClick;

  const LoginScreen({
    super.key,
    required this.onLoginClick,
    required this.onSignUpClick,
    this.onGuestClick,
    this.onPhoneClick,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String username = "";
  String password = "";
  bool showPassword = false;

  String? errorMessage;
  bool isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Column(
                    children: [
                      Image.asset(
                        "assets/images/applogocrop.png",
                        width: MediaQuery.of(context).size.width * 0.55,
                      ),
                      const SizedBox(height: 32),
                      Text(
                        "Welcome Back",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryBlue,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        "Please enter your details to access the services",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: AppColors.hint),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  Column(
                    children: [
                      RoundedInputField(
                        value: username,
                        hintText: "Username",
                        icon: Icons.person,
                        onChanged: (val) {
                          username = val;
                        },
                      ),

                      const SizedBox(height: 20),

                      RoundedInputField(
                        value: password,
                        hintText: "Password",
                        icon: Icons.lock,
                        obscureText: !showPassword,
                        onChanged: (val) {
                          password = val;
                        },
                        suffixWidget: GestureDetector(
                          onTap: () {
                            setState(() {
                              showPassword = !showPassword;
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Image.asset(
                              showPassword
                                  ? "assets/images/eye.png"
                                  : "assets/images/closed_eye.png",
                              width: 22,
                              height: 22,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: () {
                            Navigator.pushNamed(context, '/reset_password');
                          },
                          child: Text(
                            "Forgot Password?",
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primaryBlue,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      if (errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            errorMessage!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),

                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryBlue,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: isLoading
                              ? null
                              : () async {
                                  final cleanUsername = username.trim();
                                  final cleanPassword = password;

                                  if (cleanUsername.isEmpty ||
                                      cleanPassword.isEmpty) {
                                    setState(() {
                                      errorMessage =
                                          "Please enter username and password";
                                    });
                                    return;
                                  }

                                  setState(() {
                                    isLoading = true;
                                    errorMessage = null;
                                  });

                                  try {
                                    await widget.onLoginClick(
                                      cleanUsername,
                                      cleanPassword,
                                    );
                                  } catch (e) {
                                    setState(() {
                                      errorMessage = e.toString().replaceAll(
                                        "Exception: ",
                                        "",
                                      );
                                    });
                                  } finally {
                                    setState(() {
                                      isLoading = false;
                                    });
                                  }
                                },
                          child: isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  "Log In",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      Row(
                        children: [
                          Expanded(child: Divider(color: AppColors.stroke)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              "Or Continue with",
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.hint,
                              ),
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
                              onTap: widget.onGuestClick ?? () {},
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: SocialButton(
                              iconPath: "assets/images/out.png",
                              label: "Sign Up",
                              onTap: widget.onSignUpClick,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
