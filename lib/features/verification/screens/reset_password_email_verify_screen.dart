import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../features/Resets/reset_new_password_screen.dart';
import '../../../core/widgets/indicators/double_back_exit.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/widgets/web/web.dart';
import '../../../core/widgets/mobile_form_shell.dart';
import '../../../core/theme/app_colors.dart';

class ResetPasswordEmailVerifyScreen extends StatefulWidget {
  final String email;
  final VoidCallback onVerifiedSuccess;
  final VoidCallback onTermsClick;
  final VoidCallback onConditionsClick;

  const ResetPasswordEmailVerifyScreen({
    super.key,
    required this.email,
    required this.onVerifiedSuccess,
    required this.onTermsClick,
    required this.onConditionsClick,
  });

  @override
  State<ResetPasswordEmailVerifyScreen> createState() =>
      _ResetPasswordEmailVerifyScreenState();
}

class _ResetPasswordEmailVerifyScreenState
    extends State<ResetPasswordEmailVerifyScreen>
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

  bool isResending = false;
  String resendStatusText = "";
  bool isVerifying = false;
  bool showError = false;

  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;
  late AnimationController _heroController;

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

  Future<void> resendOtp() async {
    setState(() {
      isResending = true;
      resendStatusText = "Please wait";
    });

    try {
      final supabase = Supabase.instance.client;

      final canSend = await supabase.rpc(
        'can_send_otp',
        params: {'p_identifier': widget.email, 'p_purpose': 'reset'},
      );
      if (canSend['allowed'] != true) {
        if (!mounted) return;
        setState(() => resendStatusText = canSend['message'] as String);
        return;
      }

      final response = await http.post(
        Uri.parse(
          "https://vxvflhjbafqwehuxnmeq.supabase.co/functions/v1/reset-send-otp",
        ),
        headers: {
          "Content-Type": "application/json",
          "apikey": "eyJhbGciOiJIUzI1Ni...",
        },
        body: jsonEncode({"email": widget.email}),
      );

      final data = jsonDecode(response.body);
      if (!mounted) return;

      if (response.statusCode == 200 && data["success"] == true) {
        setState(() => resendStatusText = "Sent successfully");
        for (var c in controllers) {
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

  Future<void> verifyOtp() async {
    setState(() => isVerifying = true);

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final supabase = Supabase.instance.client;

    try {
      final canVerify = await supabase.rpc(
        'can_verify_otp',
        params: {'p_identifier': widget.email},
      );

      if (!mounted) return;

      if (canVerify['allowed'] != true) {
        messenger.showSnackBar(
          SnackBar(content: Text(canVerify['message'] as String)),
        );
        setState(() => isVerifying = false);
        return;
      }

      final response = await http.post(
        Uri.parse(
          "https://vxvflhjbafqwehuxnmeq.supabase.co/functions/v1/reset-verify-otp",
        ),
        headers: {
          "Content-Type": "application/json",
          "apikey": "eyJhbGciOiJIUzI1Ni...",
        },
        body: jsonEncode({"email": widget.email, "code": code}),
      );

      final data = jsonDecode(response.body);
      if (!mounted) return;

      if (response.statusCode == 200 && data["success"] == true) {
        await supabase.rpc(
          'clear_otp_failures',
          params: {'p_identifier': widget.email},
        );
        if (!mounted) return;

        final session = data["session"];
        navigator.push(
          kIsWeb
              ? PageRouteBuilder(
                  pageBuilder: (_, _, _) => ResetNewPasswordScreen(
                    accessToken: session["access_token"],
                    refreshToken: session["refresh_token"],
                  ),
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: Duration.zero,
                )
              : MaterialPageRoute(
                  builder: (_) => ResetNewPasswordScreen(
                    accessToken: session["access_token"],
                    refreshToken: session["refresh_token"],
                  ),
                ),
        );
      } else {
        await supabase.rpc(
          'record_otp_failure',
          params: {'p_identifier': widget.email},
        );
        if (!mounted) return;
        triggerErrorAnimation();
      }
    } finally {
      if (mounted) setState(() => isVerifying = false);
    }
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
        body: SafeArea(
          child: MobileFormShell(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
              child: Column(
                children: [
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
                    "We send a 6-digit code to\n$maskedEmail",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: hint),
                  ),
                  const SizedBox(height: 28),
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
                      onPressed: (code.length == 6 && !isVerifying)
                          ? () async {
                              setState(() => isVerifying = true);
                              final messenger = ScaffoldMessenger.of(context);
                              final navigator = Navigator.of(context);
                              final supabase = Supabase.instance.client;
                              try {
                                final canVerify = await supabase.rpc(
                                  'can_verify_otp',
                                  params: {'p_identifier': widget.email},
                                );
                                if (!mounted) return;
                                if (canVerify['allowed'] != true) {
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        canVerify['message'] as String,
                                      ),
                                    ),
                                  );
                                  setState(() => isVerifying = false);
                                  return;
                                }
                                final response = await http.post(
                                  Uri.parse(
                                    "https://vxvflhjbafqwehuxnmeq.supabase.co/functions/v1/reset-verify-otp",
                                  ),
                                  headers: {
                                    "Content-Type": "application/json",
                                    "apikey": "eyJhbGciOiJIUzI1Ni...",
                                  },
                                  body: jsonEncode({
                                    "email": widget.email,
                                    "code": code,
                                  }),
                                );
                                final data = jsonDecode(response.body);
                                if (!mounted) return;
                                if (response.statusCode == 200 &&
                                    data["success"] == true) {
                                  await supabase.rpc(
                                    'clear_otp_failures',
                                    params: {'p_identifier': widget.email},
                                  );
                                  if (!mounted) return;
                                  final session = data["session"];
                                  navigator.push(
                                    MaterialPageRoute(
                                      builder: (_) => ResetNewPasswordScreen(
                                        accessToken: session["access_token"],
                                        refreshToken: session["refresh_token"],
                                      ),
                                    ),
                                  );
                                } else {
                                  await supabase.rpc(
                                    'record_otp_failure',
                                    params: {'p_identifier': widget.email},
                                  );
                                  if (!mounted) return;
                                  triggerErrorAnimation();
                                }
                              } finally {
                                if (mounted) {
                                  setState(() => isVerifying = false);
                                }
                              }
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryBlue,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: isVerifying
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.4,
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Didn't receive a code? ",
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
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  WEB — glass via WebAuthScaffold + WebAuthCard (kit)
  //  Rule 3 FIX: WebOtpBoxes receives showError + shakeAnimation (was missing)
  //  Token FIX:  resend link color uses AppColors / WebUi tokens, not the
  //              mobile-only `primaryBlue` instance field
  // ══════════════════════════════════════════════════════════════════════════
  Widget _webScaffold(BuildContext context) {
    return WebAuthScaffold(
      heroController: _heroController,
      headline: "Reset your\npassword.",
      subtitle: "Enter the code we sent to your email\nto continue securely.",
      card: _webCard(),
    );
  }

  Widget _webCard() {
    final bool canResend = secondsLeft == 0;

    return WebAuthCard(
      children: [
        WebCardHeader(
          title: "Reset password",
          subtitle: "We sent a 6-digit code to\n$maskedEmail",
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
          loading: isVerifying,
          onPressed: code.length == 6 ? verifyOtp : null,
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
                  // FIX: was using `primaryBlue` (mobile instance field).
                  // Now uses AppColors.primaryBlue + WebUi kit tokens only.
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
        const SizedBox(height: 16),
        const Divider(color: WebUi.divider),
      ],
    );
  }
}
