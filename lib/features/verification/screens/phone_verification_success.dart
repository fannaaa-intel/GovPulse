import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

class PhoneVerificationSuccess extends StatelessWidget {
  final String phone;

  const PhoneVerificationSuccess({super.key, required this.phone});

  String maskPhone(String phone) {
    if (phone.length < 6) return phone;

    final start = phone.substring(0, 3);
    final end = phone.substring(phone.length - 2);
    final hidden = "*" * (phone.length - 5);

    return "$start$hidden$end";
  }

  @override
  Widget build(BuildContext context) {
    final maskedPhone = maskPhone(phone);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26),
          child: Column(
            children: [
              const SizedBox(height: 40),

              /// LOGO
              Image.asset(
                "assets/images/applogocrop.png",
                width: MediaQuery.of(context).size.width * 0.28,
              ),

              const SizedBox(height: 20),

              /// SUCCESS GIF
              Center(
                child: Image.asset("assets/images/success.gif", height: 130),
              ),

              const SizedBox(height: 20),

              /// TITLE
              Text(
                "Phone Verification",
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryBlue,
                ),
              ),

              const SizedBox(height: 14),

              /// PHONE MESSAGE
              Text(
                "Your phone number $maskedPhone\nhas been successfully verified.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.hint),
              ),

              const Spacer(),

              /// ✅ FIXED BUTTON
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
