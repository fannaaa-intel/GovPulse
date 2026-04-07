import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

class EmailVerificationSuccess extends StatelessWidget {
  final String email;

  const EmailVerificationSuccess({super.key, required this.email});

  String maskEmail(String email) {
    final parts = email.split('@');
    if (parts.length != 2) return email;

    final name = parts[0];
    final domain = parts[1];

    if (name.length <= 2) return email;

    final visible = name.substring(0, 2);
    final hidden = "*" * (name.length - 2);

    return "$visible$hidden@$domain";
  }

  @override
  Widget build(BuildContext context) {
    final maskedEmail = maskEmail(email);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26),
          child: Column(
            children: [
              const SizedBox(height: 40),

              Image.asset(
                "assets/images/applogocrop.png",
                width: MediaQuery.of(context).size.width * 0.28,
              ),

              const SizedBox(height: 20),

              Center(
                child: Image.asset("assets/images/success.gif", height: 130),
              ),

              const SizedBox(height: 20),

              Text(
                "Email Verification",
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryBlue,
                ),
              ),

              const SizedBox(height: 14),

              Text(
                "Your email $maskedEmail\nhas been successfully verified.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.hint),
              ),

              const Spacer(),

              /// ✅ FIXED BUTTON (SAFE CONTEXT)
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
                  onPressed: () {
                    Navigator.of(
                      context,
                    ).pushNamedAndRemoveUntil('/login', (route) => false);
                  },
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
    );
  }
}
