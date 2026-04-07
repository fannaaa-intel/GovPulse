import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/widgets/indicators/double_back_exit.dart';

class PhoneVerificationScreen extends StatefulWidget {
  final String phone;
  final VoidCallback onVerifiedSuccess;
  final VoidCallback onTermsClick;
  final VoidCallback onConditionsClick;

  const PhoneVerificationScreen({
    super.key,
    required this.phone,
    required this.onVerifiedSuccess,
    required this.onTermsClick,
    required this.onConditionsClick,
  });

  @override
  State<PhoneVerificationScreen> createState() =>
      _PhoneVerificationScreenState();
}

class _PhoneVerificationScreenState extends State<PhoneVerificationScreen> {
  final Color primaryBlue = const Color(0xFF0D47A1);
  final Color hint = const Color(0xFF8A8A8A);
  final Color stroke = const Color(0xFFE3E6EF);

  List<TextEditingController> controllers = List.generate(
    6,
    (_) => TextEditingController(),
  );

  List<FocusNode> focusNodes = List.generate(6, (_) => FocusNode());

  int secondsLeft = 58;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    startCountdown();
  }

  void startCountdown() {
    timer?.cancel();
    secondsLeft = 58;

    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (secondsLeft == 0) {
        t.cancel();
      } else {
        setState(() => secondsLeft--);
      }
    });
  }

  String get code => controllers.map((c) => c.text).join();

  String get maskedPhone {
    if (widget.phone.length >= 6) {
      return "+63 XXXX XXX ${widget.phone.substring(widget.phone.length - 3)}";
    }
    return widget.phone;
  }

  @override
  void dispose() {
    timer?.cancel();
    for (var c in controllers) {
      c.dispose();
    }
    for (var f in focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool canResend = secondsLeft == 0;

    return DoubleBackExit(
      child: Scaffold(
        backgroundColor: Colors.white,
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 26),
            child: Column(
              children: [
                const SizedBox(height: 30),

                /// LOGO
                Image.asset(
                  "assets/images/applogocrop.png",
                  width: MediaQuery.of(context).size.width * 0.42,
                ),

                const SizedBox(height: 16),

                /// TITLE
                Text(
                  "Reset Password",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: primaryBlue,
                  ),
                ),

                const SizedBox(height: 8),

                /// MESSAGE
                Text(
                  "We sent a 6-digit code to $maskedPhone",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: hint),
                ),

                const SizedBox(height: 26),

                /// OTP IMAGE
                Image.asset("assets/images/otplogo.png", height: 140),

                const SizedBox(height: 30),

                /// OTP INPUT BOXES
                Row(
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
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: InputDecoration(
                          counterText: "",
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 14,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: stroke),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: primaryBlue,
                              width: 1.5,
                            ),
                          ),
                        ),
                        onChanged: (value) {
                          if (value.isNotEmpty && index < 5) {
                            focusNodes[index + 1].requestFocus();
                          }
                        },
                      ),
                    );
                  }),
                ),

                const SizedBox(height: 18),

                /// RESEND TIMER
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: "Resend code in ",
                        style: TextStyle(fontSize: 12, color: hint),
                      ),
                      TextSpan(
                        text: "00:${secondsLeft.toString().padLeft(2, '0')}",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: primaryBlue,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                /// VERIFY BUTTON
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryBlue,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: code.length == 6
                        ? () {
                            widget.onVerifiedSuccess();
                          }
                        : null,
                    child: const Text(
                      "Verify",
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 26),

                Divider(color: stroke),

                const SizedBox(height: 16),

                /// RESEND LINK
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Didn’t receive a code? ",
                      style: TextStyle(fontSize: 13, color: hint),
                    ),
                    GestureDetector(
                      onTap: canResend
                          ? () {
                              for (var c in controllers) {
                                c.clear();
                              }
                              startCountdown();
                            }
                          : null,
                      child: Text(
                        "Resend",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: canResend ? primaryBlue : hint,
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
