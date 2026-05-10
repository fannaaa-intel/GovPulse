import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../core/widgets/indicators/double_back_exit.dart';

class VerificationScreen extends StatefulWidget {
  final String email;
  final String username;
  final String password;

  final VoidCallback onVerifiedSuccess;
  final VoidCallback onTermsClick;
  final VoidCallback onConditionsClick;

  const VerificationScreen({
    super.key,
    required this.email,
    required this.username,
    required this.password,
    required this.onVerifiedSuccess,
    required this.onTermsClick,
    required this.onConditionsClick,
  });

  @override
  State<VerificationScreen> createState() => VerificationScreenState();
}

class VerificationScreenState extends State<VerificationScreen>
    with SingleTickerProviderStateMixin {
  final Color primaryBlue = const Color(0xFF0D47A1);
  final Color hint = const Color(0xFF8A8A8A);
  final Color stroke = const Color(0xFFE3E6EF);

  final List<TextEditingController> controllers = List.generate(
    6,
    (_) => TextEditingController(),
  );

  final List<FocusNode> focusNodes = List.generate(6, (_) => FocusNode());

  int secondsLeft = 58;
  Timer? timer;

  bool isResending = false;
  bool isVerifying = false;
  String resendStatusText = "";

  /// 🔥 ERROR STATE
  bool showError = false;

  /// 🔥 SHAKE
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  static const String baseUrl =
      "https://vxvflhjbafqwehuxnmeq.supabase.co/functions/v1";

  @override
  void initState() {
    super.initState();
    startCountdown();

    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -10), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -10, end: 10), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10, end: -10), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -10, end: 10), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10, end: 0), weight: 1),
    ]).animate(_shakeController);
  }

  void triggerErrorAnimation() {
    setState(() => showError = true);

    _shakeController.forward(from: 0);

    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => showError = false);
    });
  }

  void startCountdown() {
    timer?.cancel();
    secondsLeft = 58;

    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;

      if (secondsLeft == 0) {
        t.cancel();
      } else {
        setState(() => secondsLeft--);
      }
    });
  }

  String get code => controllers.map((c) => c.text).join();

  String get maskedEmail {
    if (widget.email.contains("@")) {
      final parts = widget.email.split("@");
      final name = parts[0];
      final domain = parts[1];
      final visible = name.length > 3 ? name.substring(0, 2) : name[0];
      return "$visible*****@$domain";
    }
    return widget.email;
  }

  @override
  void dispose() {
    timer?.cancel();
    _shakeController.dispose();

    for (final c in controllers) {
      c.dispose();
    }

    for (final f in focusNodes) {
      f.dispose();
    }

    super.dispose();
  }

  Future<void> verifyOtp() async {
    if (isVerifying || code.length != 6) return;

    setState(() => isVerifying = true);

    try {
      final response = await http.post(
        Uri.parse("$baseUrl/verify-email-otp"),
        headers: {
          "Content-Type": "application/json",
          "apikey": "sb_publishable_ZBDaQPQdFyC5kOHGbce9Ig_zdtIi6Mo",
        },
        body: jsonEncode({
          "email": widget.email,
          "code": code.trim(),
          "password": widget.password,
          "username": widget.username,
        }),
      );

      final data = jsonDecode(response.body);

      if (!mounted) return;

      if (response.statusCode == 200 && data["success"] == true) {
        widget.onVerifiedSuccess();
      } else {
        triggerErrorAnimation(); // 🔥 NO SNACKBAR
      }
    } catch (_) {
      if (!mounted) return;
      triggerErrorAnimation();
    } finally {
      if (mounted) setState(() => isVerifying = false);
    }
  }

  Future<void> resendOtp() async {
    setState(() {
      isResending = true;
      resendStatusText = "Please wait";
    });

    try {
      final response = await http.post(
        Uri.parse("$baseUrl/send-email-otp"),
        headers: {
          "Content-Type": "application/json",
          "apikey": "sb_publishable_ZBDaQPQdFyC5kOHGbce9Ig_zdtIi6Mo",
        },
        body: jsonEncode({"email": widget.email}),
      );

      final data = jsonDecode(response.body);

      if (!mounted) return;

      if (response.statusCode == 200 && data["success"] == true) {
        setState(() => resendStatusText = "Sent successfully");

        for (final c in controllers) {
          c.clear();
        }

        Future.delayed(const Duration(seconds: 2), () {
          if (!mounted) return;
          setState(() => resendStatusText = "");
          startCountdown();
        });
      }
    } finally {
      if (mounted) setState(() => isResending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canResend = secondsLeft == 0;

    return DoubleBackExit(
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
            child: Column(
              children: [
                Image.asset(
                  "assets/images/applogocrop.png",
                  width: MediaQuery.of(context).size.width * 0.42,
                ),

                const SizedBox(height: 16),

                Text(
                  "Continue with Email",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: primaryBlue,
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  "We sent a 6-digit code to\n$maskedEmail",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: hint),
                ),

                const SizedBox(height: 28),

                /// 🔥 SHAKE + OTP
                AnimatedBuilder(
                  animation: _shakeAnimation,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(_shakeAnimation.value, 0),
                      child: child,
                    );
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(6, (index) {
                      return SizedBox(
                        width: 46,
                        child: TextField(
                          controller: controllers[index],
                          focusNode: focusNodes[index],
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          maxLength: 1,
                          decoration: InputDecoration(
                            counterText: "",
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: showError ? Colors.red : stroke,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: showError ? Colors.red : primaryBlue,
                                width: 1.5,
                              ),
                            ),
                          ),
                          onChanged: (value) {
                            if (value.isNotEmpty && index < 5) {
                              focusNodes[index + 1].requestFocus();
                            } else if (value.isEmpty && index > 0) {
                              focusNodes[index - 1].requestFocus();
                            }
                            setState(() {});
                          },
                        ),
                      );
                    }),
                  ),
                ),

                const SizedBox(height: 18),

                Text(
                  "Resend code in 00:${secondsLeft.toString().padLeft(2, '0')}",
                  style: TextStyle(fontSize: 12, color: hint),
                ),

                const SizedBox(height: 28),

                /// 🔥 VERIFY BUTTON (WITH LOADING)
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: (code.length == 6 && !isVerifying)
                        ? verifyOtp
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryBlue,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: isVerifying
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            "Verify",
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 22),

                Divider(color: stroke),

                const SizedBox(height: 16),

                /// RESEND
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Didn’t receive a code? ",
                      style: TextStyle(fontSize: 13, color: hint),
                    ),
                    GestureDetector(
                      onTap: canResend && !isResending
                          ? () async => await resendOtp()
                          : null,
                      child: Text(
                        isResending
                            ? "Please wait"
                            : resendStatusText.isNotEmpty
                            ? resendStatusText
                            : "Resend",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isResending
                              ? hint
                              : resendStatusText == "Sent successfully"
                              ? Colors.green
                              : canResend
                              ? primaryBlue
                              : hint,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                Divider(color: stroke),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
