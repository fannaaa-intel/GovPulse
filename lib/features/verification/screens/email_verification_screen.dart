import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../core/widgets/indicators/double_back_exit.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/widgets/web/web.dart';
import '../../../core/widgets/mobile_form_shell.dart';
import '../../../core/theme/app_colors.dart';

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
    with TickerProviderStateMixin {
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
  bool showError = false;

  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;
  late AnimationController _heroController;

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
    _heroController.dispose();
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
      final supabase = Supabase.instance.client;

      final canVerify = await supabase.rpc(
        'can_verify_otp',
        params: {'p_identifier': widget.email},
      );
      if (canVerify['allowed'] != true) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(canVerify['message'] as String)));
        return;
      }

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
        }),
      );

      final data = jsonDecode(response.body);
      if (!mounted) return;

      if (response.statusCode == 200 && data["success"] == true) {
        try {
          final session = data["session"];
          await supabase.auth.setSession(session["access_token"] as String);
        } catch (_) {
          // Session will be established on next app launch via refresh
        }

        await supabase.rpc(
          'clear_otp_failures',
          params: {'p_identifier': widget.email},
        );
        widget.onVerifiedSuccess();
      } else {
        await supabase.rpc(
          'record_otp_failure',
          params: {'p_identifier': widget.email},
        );
        triggerErrorAnimation();
      }
    } catch (e) {
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
      final supabase = Supabase.instance.client;

      final canSend = await supabase.rpc(
        'can_send_otp',
        params: {'p_identifier': widget.email, 'p_purpose': 'signup'},
      );
      if (canSend['allowed'] != true) {
        if (!mounted) return;
        setState(() => resendStatusText = canSend['message'] as String);
        return;
      }

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
    if (kIsWeb) return _webScaffold(context);
    return _mobileScaffold(context);
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  WEB — uses WebAuthScaffold + kit components
  // ══════════════════════════════════════════════════════════════════════════
  Widget _webScaffold(BuildContext context) {
    final bool canResend = secondsLeft == 0;

    return WebAuthScaffold(
      heroController: _heroController,
      headline: "Verify your\nemail.",
      subtitle: "Enter the 6-digit code we sent\nto confirm your account.",
      card: WebAuthCard(
        children: [
          const WebCardHeader(
            title: "Verify your email",
            subtitle: "We sent a 6-digit code to",
          ),
          const SizedBox(height: 4),
          // Masked email below the subtitle
          Center(
            child: Text(
              maskedEmail,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: WebUi.ink,
              ),
            ),
          ),
          const SizedBox(height: 28),

          // OTP boxes — uses shared WebOtpBoxes from the kit
          WebOtpBoxes(
            controllers: controllers,
            focusNodes: focusNodes,
            showError: showError,
            shakeAnimation: _shakeAnimation,
            onChanged: () => setState(() {}),
          ),

          const SizedBox(height: 14),

          // Countdown timer
          Center(child: WebResendTimer(secondsLeft: secondsLeft)),

          const SizedBox(height: 24),

          // Verify button
          WebPrimaryButton(
            label: "Verify email",
            loading: isVerifying,
            onPressed: code.length == 6 ? verifyOtp : null,
          ),

          const SizedBox(height: 20),

          Divider(color: WebUi.divider),

          const SizedBox(height: 14),

          // Resend row
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Didn't receive a code?  ",
                  style: TextStyle(fontSize: 13, color: WebUi.sub),
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
                      fontWeight: FontWeight.w600,
                      color: isResending
                          ? WebUi.faint
                          : resendStatusText == "Sent successfully"
                          ? AppColors.green
                          : canResend
                          ? AppColors.primaryBlue
                          : WebUi.faint,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  MOBILE — logic untouched, MobileFormShell + logo clamp applied
  // ══════════════════════════════════════════════════════════════════════════
  Widget _mobileScaffold(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final canResend = secondsLeft == 0;

    return DoubleBackExit(
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: MobileFormShell(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
              child: Column(
                children: [
                  Image.asset(
                    "assets/images/applogocrop.png",
                    width: (w * 0.42).clamp(0.0, 180.0).toDouble(),
                  ),

                  const SizedBox(height: 16),

                  Text(
                    "Continue with Email",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryBlue,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    "We sent a 6-digit code to\n$maskedEmail",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: AppColors.hint),
                  ),

                  const SizedBox(height: 28),

                  AnimatedBuilder(
                    animation: _shakeAnimation,
                    builder: (context, child) => Transform.translate(
                      offset: Offset(_shakeAnimation.value, 0),
                      child: child,
                    ),
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
                                  color: showError
                                      ? Colors.red
                                      : AppColors.stroke,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: showError
                                      ? Colors.red
                                      : AppColors.primaryBlue,
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
                    style: TextStyle(fontSize: 12, color: AppColors.hint),
                  ),

                  const SizedBox(height: 28),

                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: (code.length == 6 && !isVerifying)
                          ? verifyOtp
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
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

                  Divider(color: AppColors.stroke),

                  const SizedBox(height: 16),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Didn't receive a code? ",
                        style: TextStyle(fontSize: 13, color: AppColors.hint),
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
                                ? AppColors.hint
                                : resendStatusText == "Sent successfully"
                                ? Colors.green
                                : canResend
                                ? AppColors.primaryBlue
                                : AppColors.hint,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  Divider(color: AppColors.stroke),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
