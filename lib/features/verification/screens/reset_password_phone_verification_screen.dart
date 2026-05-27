import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../core/widgets/indicators/double_back_exit.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/web/web.dart';
import '../../../core/widgets/mobile_form_shell.dart';

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

class _PhoneVerificationScreenState extends State<PhoneVerificationScreen>
    with TickerProviderStateMixin {
  // Mobile-only color constants — kept for _mobileScaffold, never used in web.
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

  // FIX: shake controller added — required for WebOtpBoxes error animation.
  bool showError = false;
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;
  late AnimationController _heroController;

  String get code => controllers.map((c) => c.text).join();

  String get maskedPhone {
    if (widget.phone.length >= 6) {
      return "+63 XXXX XXX ${widget.phone.substring(widget.phone.length - 3)}";
    }
    return widget.phone;
  }

  @override
  void initState() {
    super.initState();
    startCountdown();

    // Shake controller for OTP error animation (web).
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

    _heroController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);
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
      if (secondsLeft == 0) {
        t.cancel();
      } else {
        setState(() => secondsLeft--);
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    _shakeController.dispose();
    _heroController.dispose();
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
    if (kIsWeb) return _webScaffold(context);
    return _mobileScaffold(context);
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  MOBILE — untouched
  // ══════════════════════════════════════════════════════════════════════════
  Widget _mobileScaffold(BuildContext context) {
    bool canResend = secondsLeft == 0;

    return DoubleBackExit(
      child: Scaffold(
        backgroundColor: Colors.white,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: MobileFormShell(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 26),
              child: Column(
                children: [
                  const SizedBox(height: 30),
                  Image.asset(
                    "assets/images/applogocrop.png",
                    width: (MediaQuery.of(context).size.width * 0.42)
                        .clamp(0.0, 180.0)
                        .toDouble(),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "Reset Password",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: primaryBlue,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "We sent a 6-digit code to $maskedPhone",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: hint),
                  ),
                  const SizedBox(height: 26),
                  Image.asset("assets/images/otplogo.png", height: 140),
                  const SizedBox(height: 30),
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Didn't receive a code? ",
                        style: TextStyle(fontSize: 13, color: hint),
                      ),
                      GestureDetector(
                        onTap: canResend
                            ? () {
                                for (var c in controllers) {
                                  c.clear();
                                }
                                startCountdown();
                                setState(() {});
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
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  WEB — glass via WebAuthScaffold + WebAuthCard (kit)
  //  Rule 3 FIX: WebOtpBoxes now receives showError + shakeAnimation.
  //  Token FIX:  resend link uses AppColors.primaryBlue + WebUi tokens only,
  //              not the mobile-only `primaryBlue` instance field.
  // ══════════════════════════════════════════════════════════════════════════
  Widget _webScaffold(BuildContext context) {
    return WebAuthScaffold(
      heroController: _heroController,
      headline: "Reset your\npassword.",
      subtitle: "Enter the code we sent to your phone\nto continue securely.",
      card: _webCard(),
    );
  }

  Widget _webCard() {
    final bool canResend = secondsLeft == 0;

    return WebAuthCard(
      children: [
        WebCardHeader(
          title: "Reset password",
          subtitle: "We sent a 6-digit code to\n$maskedPhone",
        ),
        const SizedBox(height: 28),

        // ── OTP boxes — gray empty / blue filled / red error / shake (kit) ──
        WebOtpBoxes(
          controllers: controllers,
          focusNodes: focusNodes,
          showError: showError, // FIX: was missing
          shakeAnimation: _shakeAnimation, // FIX: was missing
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: 14),

        // ── Resend countdown ──────────────────────────────────────────────
        WebResendTimer(secondsLeft: secondsLeft),
        const SizedBox(height: 28),

        // ── CTA — blue-fill, deepen-on-hover (WebPrimaryButton) ──────────
        WebPrimaryButton(
          label: "Verify",
          onPressed: code.length == 6 ? widget.onVerifiedSuccess : null,
        ),
        const SizedBox(height: 24),
        const Divider(color: WebUi.divider),
        const SizedBox(height: 16),

        // ── Resend link — ALL colors use AppColors / WebUi tokens ─────────
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "Didn't receive a code? ",
              style: TextStyle(fontSize: 13, color: WebUi.sub),
            ),
            GestureDetector(
              onTap: canResend
                  ? () {
                      for (var c in controllers) {
                        c.clear();
                      }
                      startCountdown();
                      setState(() {});
                    }
                  : null,
              child: Text(
                "Resend",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  // FIX: was using `primaryBlue` (mobile instance field).
                  // Now uses AppColors.primaryBlue + WebUi.faint only.
                  color: canResend ? AppColors.primaryBlue : WebUi.faint,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Divider(color: WebUi.divider),
      ],
    );
  }
}
