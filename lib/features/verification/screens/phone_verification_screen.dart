import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/indicators/double_back_exit.dart';

class PhoneVerificationScreen extends StatefulWidget {
  final String phone;

  final VoidCallback onTermsClick;
  final VoidCallback onConditionsClick;

  const PhoneVerificationScreen({
    super.key,
    required this.phone,
    required this.onTermsClick,
    required this.onConditionsClick,
  });

  @override
  State<PhoneVerificationScreen> createState() =>
      _PhoneVerificationScreenState();
}

class _PhoneVerificationScreenState extends State<PhoneVerificationScreen> {
  List<TextEditingController> controllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  List<FocusNode> focusNodes = List.generate(6, (_) => FocusNode());

  String? errorText;
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

    /// ✅ ADDED
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return DoubleBackExit(
      child: Scaffold(
        backgroundColor: Colors.white,

        /// ✅ FIXED
        resizeToAvoidBottomInset: true,

        body: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SafeArea(
            child: SingleChildScrollView(
              /// ✅ ADDED
              physics: isKeyboardOpen
                  ? const ClampingScrollPhysics()
                  : const NeverScrollableScrollPhysics(),

              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 26,
                  vertical: 20,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    /// 🔹 TOP
                    Column(
                      children: [
                        Image.asset(
                          "assets/images/applogocrop.png",
                          width: MediaQuery.of(context).size.width * 0.55,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          "Continue with Mobile Number",
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryBlue,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "We sent a 6-digit code to\n$maskedPhone",
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: AppColors.hint),
                        ),
                      ],
                    ),

                    /// 🔹 MIDDLE
                    Column(
                      children: [
                        Image.asset("assets/images/otplogo.png", height: 110),
                        const SizedBox(height: 20),

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
                                    borderSide: BorderSide(
                                      color: AppColors.stroke,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: AppColors.primaryBlue,
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

                                  setState(() => errorText = null);
                                },
                              ),
                            );
                          }),
                        ),

                        const SizedBox(height: 12),

                        if (errorText != null)
                          Text(
                            errorText!,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.red,
                            ),
                          ),

                        const SizedBox(height: 6),

                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: "Resend code in ",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.hint,
                                ),
                              ),
                              TextSpan(
                                text:
                                    "00:${secondsLeft.toString().padLeft(2, '0')}",
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.green,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 18),

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
                            onPressed: code.length == 6
                                ? () {
                                    Navigator.pushReplacementNamed(
                                      context,
                                      '/phone_verification_success',
                                      arguments: widget.phone,
                                    );
                                  }
                                : () {
                                    setState(() {
                                      errorText =
                                          "Please enter the 6-digit code.";
                                    });
                                  },
                            child: const Text(
                              "Verify",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    /// 🔹 BOTTOM
                    Column(
                      children: [
                        Divider(color: AppColors.stroke),
                        const SizedBox(height: 10),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "Didn’t receive a code? ",
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.hint,
                              ),
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
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: canResend
                                      ? AppColors.primaryBlue
                                      : AppColors.hint,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 18),

                        Divider(color: AppColors.stroke),
                        const SizedBox(height: 10),

                        Text(
                          "By signing up, you agree to our",
                          style: TextStyle(fontSize: 11, color: AppColors.hint),
                        ),
                        const SizedBox(height: 4),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            GestureDetector(
                              onTap: widget.onTermsClick,
                              child: Text(
                                "Terms of Service",
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primaryBlue,
                                ),
                              ),
                            ),
                            Text(
                              " and ",
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.hint,
                              ),
                            ),
                            GestureDetector(
                              onTap: widget.onConditionsClick,
                              child: Text(
                                "Conditions.",
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primaryBlue,
                                ),
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
      ),
    );
  }
}
