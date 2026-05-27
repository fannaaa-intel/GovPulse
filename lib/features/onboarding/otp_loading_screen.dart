import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../core/theme/app_colors.dart'; // adjust to your import path

class OtpLoadingScreen extends StatefulWidget {
  final Future<void> Function() onSendOtp;
  final String type; // "email" or "phone"

  const OtpLoadingScreen({
    super.key,
    required this.onSendOtp,
    required this.type,
  });

  @override
  State<OtpLoadingScreen> createState() => _OtpLoadingScreenState();
}

class _OtpLoadingScreenState extends State<OtpLoadingScreen> {
  @override
  void initState() {
    super.initState();
    _startProcess();
  }

  Future<void> _startProcess() async {
    try {
      await widget.onSendOtp();
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop({"success": true});
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop({
        "success": false,
        "error": e.toString().replaceFirst("Exception: ", ""),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // ── Web: render a compact centered card (showDialog provides the barrier) ──
    if (kIsWeb) return _webCard();

    // ── Mobile: full-screen scaffold, unchanged ────────────────────────────────
    return _mobileScaffold();
  }

  // ── Web compact card ────────────────────────────────────────────────────────
  Widget _webCard() {
    final isEmail = widget.type == "email";

    return PopScope(
      canPop: false,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 340,
            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 40),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 32,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo
                Image.asset(
                  'assets/images/applogocrop.png',
                  width: 72,
                  height: 72,
                ),
                const SizedBox(height: 24),

                // Spinner
                SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.primaryBlue,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Title
                const Text(
                  "Please wait…",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 8),

                // Subtitle
                Text(
                  isEmail
                      ? "We're verifying your email.\nThis will just take a moment."
                      : "We're verifying your phone number.\nThis will just take a moment.",
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6B7280),
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Mobile full-screen scaffold (untouched) ──────────────────────────────────
  Widget _mobileScaffold() {
    final isEmail = widget.type == "email";

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.grey[100],
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/images/applogocrop.png', width: 150),
              const SizedBox(height: 40),
              Image.asset('assets/images/loading.gif', width: 200),
              const SizedBox(height: 20),
              const Text(
                "Please wait...",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Text(
                isEmail
                    ? "We're verifying your Email\nit'll just take a moment"
                    : "We're verifying your Phone Number\nit'll just take a moment",
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
