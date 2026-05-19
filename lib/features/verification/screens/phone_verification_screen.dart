import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/indicators/double_back_exit.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

class _PhoneVerificationScreenState extends State<PhoneVerificationScreen>
    with SingleTickerProviderStateMixin {
  final List<TextEditingController> controllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> focusNodes = List.generate(6, (_) => FocusNode());

  int secondsLeft = 58;
  Timer? timer;

  bool isVerifying = false;
  bool isResending = false;
  String resendStatusText = '';
  bool showError = false;

  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  static const _baseUrl =
      'https://vxvflhjbafqwehuxnmeq.supabase.co/functions/v1';
  static const _apiKey = 'sb_publishable_ZBDaQPQdFyC5kOHGbce9Ig_zdtIi6Mo';

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

  void triggerErrorAnimation() {
    setState(() => showError = true);
    _shakeController.forward(from: 0);
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => showError = false);
    });
  }

  String get code => controllers.map((c) => c.text).join();

  String get maskedPhone {
    if (widget.phone.length >= 6) {
      return '+63 XXXX XXX ${widget.phone.substring(widget.phone.length - 3)}';
    }
    return widget.phone;
  }

  Future<void> verifyOtp() async {
    if (isVerifying || code.length != 6) return;
    setState(() => isVerifying = true);

    // ✅ Capture EVERYTHING that uses context BEFORE any await
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final supabase = Supabase.instance.client;

    try {
      final canVerify = await supabase.rpc(
        'can_verify_otp',
        params: {'p_identifier': widget.phone},
      );

      if (!mounted) return;

      if (canVerify['allowed'] != true) {
        messenger.showSnackBar(
          SnackBar(content: Text(canVerify['message'] as String)),
        );
        return;
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/verify-phone-otp'),
        headers: {'Content-Type': 'application/json', 'apikey': _apiKey},
        body: jsonEncode({'phone': widget.phone, 'code': code.trim()}),
      );

      final data = jsonDecode(response.body);

      if (!mounted) return;

      if (response.statusCode == 200 && data['success'] == true) {
        await supabase.rpc(
          'clear_otp_failures',
          params: {'p_identifier': widget.phone},
        );

        if (!mounted) return;

        // ✅ Use the captured navigator, NOT Navigator.pushReplacementNamed(context, ...)
        navigator.pushReplacementNamed(
          '/phone_verification_success',
          arguments: widget.phone,
        );
      } else {
        await supabase.rpc(
          'record_otp_failure',
          params: {'p_identifier': widget.phone},
        );

        if (!mounted) return;
        triggerErrorAnimation();
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
      resendStatusText = 'Please wait';
    });

    try {
      final supabase = Supabase.instance.client;

      // ── Rate-limit check ─────────────────────────────────────────────
      final canSend = await supabase.rpc(
        'can_send_otp',
        params: {'p_identifier': widget.phone, 'p_purpose': 'signup'},
      );
      if (canSend['allowed'] != true) {
        if (!mounted) return;
        setState(() => resendStatusText = canSend['message'] as String);
        return;
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/send-phone-otp'),
        headers: {'Content-Type': 'application/json', 'apikey': _apiKey},
        body: jsonEncode({'phone': widget.phone}),
      );

      final data = jsonDecode(response.body);
      if (!mounted) return;

      if (response.statusCode == 200 && data['success'] == true) {
        setState(() => resendStatusText = 'Sent successfully');
        for (final c in controllers) {
          c.clear();
        }
        Future.delayed(const Duration(seconds: 2), () {
          if (!mounted) return;
          setState(() => resendStatusText = '');
          startCountdown();
        });
      }
    } finally {
      if (mounted) setState(() => isResending = false);
    }
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

  @override
  Widget build(BuildContext context) {
    final canResend = secondsLeft == 0;

    return DoubleBackExit(
      child: Scaffold(
        backgroundColor: Colors.white,
        resizeToAvoidBottomInset: true,
        body: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
              child: Column(
                children: [
                  Image.asset(
                    'assets/images/applogocrop.png',
                    width: MediaQuery.of(context).size.width * 0.42,
                  ),

                  const SizedBox(height: 16),

                  Text(
                    'Continue with Mobile Number',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryBlue,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    'We sent a 6-digit code to\n$maskedPhone',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: AppColors.hint),
                  ),

                  const SizedBox(height: 28),

                  Image.asset('assets/images/otplogo.png', height: 110),

                  const SizedBox(height: 24),

                  // OTP input with shake on error
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
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            decoration: InputDecoration(
                              counterText: '',
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 14,
                              ),
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

                  const SizedBox(height: 12),

                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'Resend code in ',
                          style: TextStyle(fontSize: 12, color: AppColors.hint),
                        ),
                        TextSpan(
                          text: '00:${secondsLeft.toString().padLeft(2, '0')}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.green,
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
                              'Verify',
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
                              ? 'Please wait'
                              : resendStatusText.isNotEmpty
                              ? resendStatusText
                              : 'Resend',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: isResending
                                ? AppColors.hint
                                : resendStatusText == 'Sent successfully'
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

                  const SizedBox(height: 10),

                  Text(
                    'By signing up, you agree to our',
                    style: TextStyle(fontSize: 11, color: AppColors.hint),
                  ),
                  const SizedBox(height: 4),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: widget.onTermsClick,
                        child: Text(
                          'Terms of Service',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryBlue,
                          ),
                        ),
                      ),
                      Text(
                        ' and ',
                        style: TextStyle(fontSize: 11, color: AppColors.hint),
                      ),
                      GestureDetector(
                        onTap: widget.onConditionsClick,
                        child: Text(
                          'Conditions.',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryBlue,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
