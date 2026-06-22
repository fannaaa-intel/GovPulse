import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../../core/widgets/responsive_page.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/mobile_form_shell.dart';
import 'change_password_new_screen.dart';

class ChangePasswordVerifyScreen extends StatefulWidget {
  final String email;
  const ChangePasswordVerifyScreen({super.key, required this.email});
  @override
  State<ChangePasswordVerifyScreen> createState() =>
      _ChangePasswordVerifyScreenState();
}

class _ChangePasswordVerifyScreenState extends State<ChangePasswordVerifyScreen>
    with TickerProviderStateMixin {
  static const String _baseUrl =
      'https://vxvflhjbafqwehuxnmeq.supabase.co/functions/v1';
  static const String _apiKey = 'eyJhbGciOiJIUzI1Ni...';

  final List<TextEditingController> _controllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  bool _isVerifying = false;
  bool _isResending = false;
  bool _showError = false;
  String _resendStatus = '';
  int _secondsLeft = 58;
  Timer? _timer;

  late final AnimationController _slideCtrl;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;
  late final AnimationController _shakeCtrl;
  late final Animation<double> _shakeAnim;
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  String get _code => _controllers.map((c) => c.text).join();

  String get _maskedEmail {
    if (widget.email.contains('@')) {
      final parts = widget.email.split('@');
      final name = parts[0];
      final domain = parts[1];
      final visible = name.length > 3 ? name.substring(0, 2) : name[0];
      return '$visible*****@$domain';
    }
    return widget.email;
  }

  @override
  void initState() {
    super.initState();
    _startCountdown();

    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.10),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));
    _fadeAnim = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut));

    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -10), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -10, end: 10), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10, end: -10), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -10, end: 10), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10, end: 0), weight: 1),
    ]).animate(_shakeCtrl);

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(
      begin: 1.0,
      end: 1.08,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _slideCtrl.forward();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _slideCtrl.dispose();
    _shakeCtrl.dispose();
    _pulseCtrl.dispose();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    _secondsLeft = 58;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_secondsLeft == 0) {
        t.cancel();
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  void _triggerError() {
    setState(() => _showError = true);
    _shakeCtrl.forward(from: 0);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showError = false);
    });
  }

  Future<void> _verifyOtp() async {
    if (_isVerifying || _code.length != 6) return;
    setState(() => _isVerifying = true);
    final supabase = Supabase.instance.client;
    try {
      final canVerify = await supabase.rpc(
        'can_verify_otp',
        params: {'p_identifier': widget.email},
      );
      if (!mounted) return;
      if (canVerify['allowed'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(canVerify['message'] as String),
            backgroundColor: AppColors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      final response = await http.post(
        Uri.parse('$_baseUrl/reset-verify-otp'),
        headers: {'Content-Type': 'application/json', 'apikey': _apiKey},
        body: jsonEncode({'email': widget.email, 'code': _code.trim()}),
      );
      if (!mounted) return;
      Map<String, dynamic> data = {};
      try {
        data = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {}
      if (response.statusCode == 200 && data['success'] == true) {
        await supabase.rpc(
          'clear_otp_failures',
          params: {'p_identifier': widget.email},
        );
        if (!mounted) return;
        final session = data['session'] as Map<String, dynamic>;
        Navigator.push(
          context,
          PageRouteBuilder(
            transitionDuration: Duration.zero,
            reverseTransitionDuration: const Duration(milliseconds: 280),
            pageBuilder: (_, _, _) => ChangePasswordNewScreen(
              accessToken: session['access_token'] as String,
              refreshToken: session['refresh_token'] as String,
            ),
            transitionsBuilder: (_, anim, _, child) =>
                FadeTransition(opacity: anim, child: child),
          ),
        );
      } else {
        await supabase.rpc(
          'record_otp_failure',
          params: {'p_identifier': widget.email},
        );
        if (!mounted) return;
        _triggerError();
      }
    } catch (_) {
      if (mounted) _triggerError();
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Future<void> _resendOtp() async {
    if (_isResending) return;
    setState(() {
      _isResending = true;
      _resendStatus = 'Sending...';
    });
    try {
      final supabase = Supabase.instance.client;
      final canSend = await supabase.rpc(
        'can_send_otp',
        params: {'p_identifier': widget.email, 'p_purpose': 'reset'},
      );
      if (!mounted) return;
      if (canSend['allowed'] != true) {
        setState(() => _resendStatus = canSend['message'] as String);
        return;
      }
      final response = await http.post(
        Uri.parse('$_baseUrl/reset-send-otp'),
        headers: {
          'Content-Type': 'application/json',
          'apikey': _apiKey,
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({'email': widget.email}),
      );
      if (!mounted) return;
      Map<String, dynamic> data = {};
      try {
        data = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {}
      if (response.statusCode == 200 && data['success'] == true) {
        for (final c in _controllers) {
          c.clear();
        }
        setState(() => _resendStatus = 'Sent successfully');
        Future.delayed(const Duration(seconds: 2), () {
          if (!mounted) return;
          setState(() => _resendStatus = '');
          _startCountdown();
        });
      } else {
        setState(() => _resendStatus = 'Failed to resend. Try again.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _resendStatus = 'Failed to resend. Try again.');
      }
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width.clamp(0.0, 480.0);
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      body: ResponsivePageBody(
        maxWidth: 520,
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(w),
              Expanded(
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: SlideTransition(
                    position: _slideAnim,
                    child: MobileFormShell(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: EdgeInsets.symmetric(horizontal: w * 0.06),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            SizedBox(height: w * 0.08),
                            _buildAnimatedIcon(w),
                            SizedBox(height: w * 0.07),
                            Text(
                              'Check your email',
                              style: TextStyle(
                                fontSize: w * 0.058,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primaryBlue,
                                letterSpacing: -0.3,
                              ),
                            ),
                            SizedBox(height: w * 0.025),
                            RichText(
                              textAlign: TextAlign.center,
                              text: TextSpan(
                                style: TextStyle(
                                  fontSize: w * 0.036,
                                  color: AppColors.hint,
                                  height: 1.5,
                                ),
                                children: [
                                  const TextSpan(
                                    text: 'We sent a 6-digit code to\n',
                                  ),
                                  TextSpan(
                                    text: _maskedEmail,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primaryBlue,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: w * 0.08),
                            _buildOtpBoxes(w),
                            SizedBox(height: w * 0.05),
                            _buildResendRow(w),
                            SizedBox(height: w * 0.08),
                            _buildVerifyButton(w),
                            SizedBox(height: w * 0.06),
                            Divider(color: AppColors.stroke),
                            SizedBox(height: w * 0.04),
                            _buildResendLink(w),
                            SizedBox(height: w * 0.05),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(double w) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(w * 0.04, w * 0.04, w * 0.04, w * 0.035),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: w * 0.09,
              height: w * 0.09,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(w * 0.025),
                border: Border.all(color: AppColors.stroke),
              ),
              child: Icon(
                Icons.arrow_back_ios_rounded,
                size: w * 0.04,
                color: AppColors.primaryBlue,
              ),
            ),
          ),
          SizedBox(width: w * 0.035),
          Text(
            'Change Password',
            style: TextStyle(
              fontSize: w * 0.052,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryBlue,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedIcon(double w) {
    final size = (w * 0.28).clamp(80.0, 140.0);
    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (_, child) =>
          Transform.scale(scale: _pulseAnim.value, child: child),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.primaryBlue.withValues(alpha: 0.07),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Container(
            width: size * 0.65,
            height: size * 0.65,
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Padding(
              padding: EdgeInsets.all(size * 0.14),
              child: Image.asset(
                'assets/images/mail.webp',
                fit: BoxFit.contain,
                color: AppColors.primaryBlue,
                colorBlendMode: BlendMode.srcIn,
                errorBuilder: (_, _, _) => Icon(
                  Icons.mark_email_unread_outlined,
                  size: size * 0.38,
                  color: AppColors.primaryBlue,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOtpBoxes(double w) {
    return AnimatedBuilder(
      animation: _shakeAnim,
      builder: (_, child) => Transform.translate(
        offset: Offset(_shakeAnim.value, 0),
        child: child,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(6, (i) {
          return SizedBox(
            width: 46,
            child: TextField(
              controller: _controllers[i],
              focusNode: _focusNodes[i],
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 1,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1F2937),
              ),
              decoration: InputDecoration(
                counterText: '',
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: _showError ? AppColors.red : AppColors.stroke,
                    width: 1.2,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: _showError ? AppColors.red : AppColors.primaryBlue,
                    width: 1.8,
                  ),
                ),
                filled: true,
                fillColor: _showError
                    ? AppColors.red.withValues(alpha: 0.04)
                    : (_controllers[i].text.isNotEmpty
                          ? AppColors.primaryBlue.withValues(alpha: 0.05)
                          : Colors.white),
              ),
              onChanged: (val) {
                if (val.isNotEmpty && i < 5) {
                  _focusNodes[i + 1].requestFocus();
                } else if (val.isEmpty && i > 0)
                  // ignore: curly_braces_in_flow_control_structures
                  _focusNodes[i - 1].requestFocus();
                setState(() {});
              },
            ),
          );
        }),
      ),
    );
  }

  Widget _buildResendRow(double w) {
    if (_resendStatus.isNotEmpty) {
      return Text(
        _resendStatus,
        style: TextStyle(
          fontSize: w * 0.034,
          color: _resendStatus == 'Sent successfully'
              ? AppColors.green
              : AppColors.red,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    if (_secondsLeft > 0) {
      return RichText(
        text: TextSpan(
          style: TextStyle(fontSize: w * 0.034, color: AppColors.hint),
          children: [
            const TextSpan(text: 'Resend code in '),
            TextSpan(
              text: '00:${_secondsLeft.toString().padLeft(2, '0')}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.primaryBlue,
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildVerifyButton(double w) {
    final enabled = _code.length == 6 && !_isVerifying;
    return SizedBox(
      width: double.infinity,
      height: w * 0.138,
      child: ElevatedButton(
        onPressed: enabled ? _verifyOtp : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryBlue,
          disabledBackgroundColor: AppColors.primaryBlue.withValues(
            alpha: 0.45,
          ),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(w * 0.035),
          ),
        ),
        child: _isVerifying
            ? SizedBox(
                width: w * 0.052,
                height: w * 0.052,
                child: const CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Colors.white,
                ),
              )
            : Text(
                'Verify code',
                style: TextStyle(
                  fontSize: w * 0.042,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }

  Widget _buildResendLink(double w) {
    final canResend =
        _secondsLeft == 0 && !_isResending && _resendStatus.isEmpty;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          "Didn't receive a code? ",
          style: TextStyle(fontSize: w * 0.034, color: AppColors.hint),
        ),
        GestureDetector(
          onTap: canResend ? _resendOtp : null,
          child: Text(
            _isResending
                ? 'Sending...'
                : _resendStatus.isNotEmpty
                ? _resendStatus
                : 'Resend',
            style: TextStyle(
              fontSize: w * 0.034,
              fontWeight: FontWeight.w700,
              color: _isResending
                  ? AppColors.hint
                  : _resendStatus == 'Sent successfully'
                  ? AppColors.green
                  : canResend
                  ? AppColors.primaryBlue
                  : AppColors.hint,
            ),
          ),
        ),
      ],
    );
  }
}
