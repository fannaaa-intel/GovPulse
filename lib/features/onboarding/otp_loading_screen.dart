import 'package:flutter/material.dart';

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

      // ✅ ONLY proceed if OTP SUCCESS
      Navigator.pop(context, {"success": true}); // return success
    } catch (e) {
      if (!mounted) return;

      Navigator.pop(context, {"success": false, "error": e.toString()});
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    ? "We’re verifying your Email\nit’ll just take a moment"
                    : "We’re verifying your Phone Number\nit’ll just take a moment",
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
