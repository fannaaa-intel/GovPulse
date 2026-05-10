import 'package:flutter/material.dart';

class GuestScreen extends StatelessWidget {
  const GuestScreen({super.key});

  static const Color primaryBlue = Color(0xFF0D47A1);
  static const Color hint = Color(0xFF8A8A8A);
  static const Color stroke = Color(0xFFE3E6EF);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
          child: Column(
            children: [
              const Spacer(),

              /// LOGO
              Image.asset(
                "assets/images/applogocrop.png",
                width: MediaQuery.of(context).size.width * 0.55,
              ),

              const SizedBox(height: 30),

              /// TITLE
              const Text(
                "Continue as Guest",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: primaryBlue,
                ),
              ),

              const SizedBox(height: 10),

              const Text(
                "Explore GovPulse without creating an account.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: hint),
              ),

              const SizedBox(height: 30),

              /// INFO CARD
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: stroke),
                  color: const Color(0xFFF6F7FB),
                ),
                child: Column(
                  children: const [
                    _FeatureItem(
                      icon: Icons.visibility_outlined,
                      text: "View community reports and updates",
                    ),

                    SizedBox(height: 12),

                    _FeatureItem(
                      icon: Icons.map_outlined,
                      text: "Explore reported issues around Aparri",
                    ),

                    SizedBox(height: 12),

                    _FeatureItem(
                      icon: Icons.lock_outline,
                      text: "Reporting issues requires an account",
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              /// CONTINUE BUTTON
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () {},
                  child: const Text(
                    "Continue as Guest",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              /// CREATE ACCOUNT BUTTON
              SizedBox(
                width: double.infinity,
                height: 55,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: primaryBlue),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pushNamed(context, '/signup');
                  },
                  child: const Text(
                    "Create Account",
                    style: TextStyle(
                      color: primaryBlue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureItem extends StatelessWidget {
  final IconData icon;
  final String text;

  const _FeatureItem({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: GuestScreen.primaryBlue, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14, color: GuestScreen.hint),
          ),
        ),
      ],
    );
  }
}
