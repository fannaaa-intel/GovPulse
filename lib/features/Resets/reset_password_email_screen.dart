import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../verification/screens/reset_password_email_verify_screen.dart';
import '../../core/theme/app_colors.dart';
import '../onboarding/otp_loading_screen.dart';

class ResetPasswordEmailScreen extends StatefulWidget {
  final VoidCallback onVerify;
  final VoidCallback onLogin;

  const ResetPasswordEmailScreen({
    super.key,
    required this.onVerify,
    required this.onLogin,
  });

  @override
  State<ResetPasswordEmailScreen> createState() =>
      _ResetPasswordEmailScreenState();
}

class _ResetPasswordEmailScreenState extends State<ResetPasswordEmailScreen> {
  String email = "";
  String errorText = "";
  bool showError = false;

  @override
  Widget build(BuildContext context) {
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: isKeyboardOpen
              ? const ClampingScrollPhysics()
              : const NeverScrollableScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.only(
            left: 26,
            right: 26,
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            children: [
              const SizedBox(height: 30),

              Image.asset(
                "assets/images/applogocrop.png",
                width: MediaQuery.of(context).size.width * 0.50,
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
                "Enter your email address to receive a\nverification code.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),

              const SizedBox(height: 22),

              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 58,
                    child: TextField(
                      keyboardType: TextInputType.emailAddress,
                      onChanged: (val) {
                        setState(() {
                          email = val;
                          showError = false;
                          errorText = "";
                        });
                      },
                      decoration: InputDecoration(
                        hintText: "Email Address",
                        prefixIcon: Icon(
                          Icons.email,
                          color: showError ? Colors.red : AppColors.primaryBlue,
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 18,
                          horizontal: 16,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: showError
                                ? Colors.red
                                : Colors.grey.shade300,
                            width: 1.2,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: showError
                                ? Colors.red
                                : AppColors.primaryBlue,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),

                  if (showError)
                    Padding(
                      padding: const EdgeInsets.only(left: 8, top: 6),
                      child: Text(
                        errorText,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                ],
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
                  onPressed: email.trim().isNotEmpty
                      ? () async {
                          setState(() {
                            showError = false;
                            errorText = "";
                          });

                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => OtpLoadingScreen(
                                type: "email",
                                onSendOtp: () async {
                                  final response = await http.post(
                                    Uri.parse(
                                      "https://vxvflhjbafqwehuxnmeq.supabase.co/functions/v1/reset-send-otp",
                                    ),
                                    headers: {
                                      "Content-Type": "application/json",
                                      "apikey": "eyJhbGciOiJIUzI1Ni...",
                                      "Authorization":
                                          "Bearer eyJhbGciOiJIUzI1Ni...",
                                    },
                                    body: jsonEncode({"email": email.trim()}),
                                  );

                                  final data = jsonDecode(response.body);

                                  if (response.statusCode != 200 ||
                                      !(data["success"] ?? false)) {
                                    throw (data["message"] ??
                                            "Email not registered")
                                        .toString();
                                  }
                                },
                              ),
                            ),
                          );

                          if (!context.mounted) return;

                          if (result != null && result["success"] == true) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ResetPasswordEmailVerifyScreen(
                                  email: email.trim(),
                                  onVerifiedSuccess: () {},
                                  onTermsClick: () {},
                                  onConditionsClick: () {},
                                ),
                              ),
                            );
                          } else {
                            if (!mounted) return;
                            setState(() {
                              showError = true;
                              errorText =
                                  result?["error"] ?? "Email not registered";
                            });
                          }
                        }
                      : null,
                  child: const Text(
                    "Verify Email",
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
                "We will send you a verification code via Email",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),

              const SizedBox(height: 26),

              Row(
                children: [
                  Expanded(child: Divider(color: Colors.grey.shade300)),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
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
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
