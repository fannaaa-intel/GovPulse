import 'package:flutter/material.dart';
import '../../../../core/widgets/responsive_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/password_validator.dart';
import '../../../../core/widgets/inputs/rounded_input_field.dart';
import '../../../../core/widgets/indicators/password_strength_bar.dart';
import '../../../../core/widgets/mobile_form_shell.dart';
import '../../../../core/widgets/modal/verification_required_dialog.dart';

class ChangePasswordNewScreen extends StatefulWidget {
  final String accessToken;
  final String refreshToken;
  const ChangePasswordNewScreen({
    super.key,
    required this.accessToken,
    required this.refreshToken,
  });
  @override
  State<ChangePasswordNewScreen> createState() =>
      _ChangePasswordNewScreenState();
}

class _ChangePasswordNewScreenState extends State<ChangePasswordNewScreen>
    with TickerProviderStateMixin {
  final TextEditingController _passwordCtrl = TextEditingController();
  final TextEditingController _confirmCtrl = TextEditingController();

  bool _showPassword = false;
  bool _showConfirm = false;
  bool _isLoading = false;
  String? _apiError;

  bool _hasMinLength = false;
  bool _hasUpper = false;
  bool _hasNumber = false;
  bool _hasSpecial = false;

  late final AnimationController _slideCtrl;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;
  // Float animation for shield icon
  late final AnimationController _floatCtrl;
  late final Animation<double> _floatAnim;

  bool get _isMismatch =>
      _confirmCtrl.text.isNotEmpty && _passwordCtrl.text != _confirmCtrl.text;
  bool get _isFormValid =>
      _passwordCtrl.text.isNotEmpty &&
      _confirmCtrl.text.isNotEmpty &&
      _passwordCtrl.text == _confirmCtrl.text &&
      _hasMinLength &&
      _hasUpper &&
      _hasNumber &&
      _hasSpecial;

  int get _strengthScore => PasswordValidator.strengthScore(_passwordCtrl.text);
  Color get _strengthColor {
    if (_strengthScore <= 1) return AppColors.red;
    if (_strengthScore <= 3) return AppColors.orange;
    return AppColors.green;
  }

  String get _strengthText {
    if (_strengthScore <= 1) return 'Weak';
    if (_strengthScore <= 3) return 'Medium';
    return 'Strong';
  }

  void _validatePassword(String value) {
    setState(() {
      _hasMinLength = PasswordValidator.hasMinLength(value);
      _hasUpper = PasswordValidator.hasUpper(value);
      _hasNumber = PasswordValidator.hasNumber(value);
      _hasSpecial = PasswordValidator.hasSpecial(value);
    });
  }

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));
    _fadeAnim = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut));

    // Pulse for outer ring
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(
      begin: 1.0,
      end: 1.08,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    // Float for the icon itself — slightly different speed for depth
    _floatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _floatAnim = Tween<double>(
      begin: -4.0,
      end: 4.0,
    ).animate(CurvedAnimation(parent: _floatCtrl, curve: Curves.easeInOut));

    _slideCtrl.forward();
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _slideCtrl.dispose();
    _pulseCtrl.dispose();
    _floatCtrl.dispose();
    super.dispose();
  }

  Future<void> _updatePassword() async {
    if (_isLoading || !_isFormValid) return;
    setState(() {
      _isLoading = true;
      _apiError = null;
    });
    try {
      final supabase = Supabase.instance.client;
      await supabase.auth.setSession(widget.refreshToken);
      final res = await supabase.auth.updateUser(
        UserAttributes(password: _passwordCtrl.text.trim()),
      );
      if (!mounted) return;
      if (res.user != null) {
        // ── Write last_password_changed_at to DB ──────────────────────────────
        try {
          await supabase
              .from('citizen_details')
              .update({
                'last_password_changed_at': DateTime.now()
                    .toUtc()
                    .toIso8601String(),
              })
              .eq('user_id', res.user!.id);
        } catch (_) {}

        if (!mounted) return;

        // ── Show success modal then pop back to S1 ────────────────────────────
        await showSuccessDialog(
          context,
          title: 'Password Changed!',
          message:
              'Your password has been updated successfully. You can now use your new password to sign in.',
          buttonLabel: 'Done',
          iconAsset: 'assets/images/protection.webp',
          iconColor: AppColors.green, // ← tints the shield green
          iconBgColor: AppColors.green.withValues(
            alpha: 0.10,
          ), // ← light green circle
        );

        if (!mounted) return;
        // Pop S3 + S2 → land back on S1 (which will now show the lock banner)
        Navigator.of(context)
          ..pop()
          ..pop();
      } else {
        throw Exception('Failed to update password');
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().toLowerCase();
      setState(() {
        if (msg.contains('same') || msg.contains('different')) {
          _apiError =
              'New password must be different from your current password.';
        } else if (msg.contains('weak') || msg.contains('strength'))
          // ignore: curly_braces_in_flow_control_structures
          _apiError = 'Password is too weak. Please choose a stronger one.';
        else
          // ignore: curly_braces_in_flow_control_structures
          _apiError = 'Something went wrong. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(height: w * 0.07),
                            Center(child: _buildAnimatedIcon(w)),
                            SizedBox(height: w * 0.06),
                            Center(
                              child: Text(
                                'Set new password',
                                style: TextStyle(
                                  fontSize: w * 0.058,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primaryBlue,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                            SizedBox(height: w * 0.018),
                            Center(
                              child: Text(
                                'Choose a strong password to\nkeep your account secure.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: w * 0.036,
                                  color: AppColors.hint,
                                  height: 1.5,
                                ),
                              ),
                            ),
                            SizedBox(height: w * 0.07),

                            RoundedInputField(
                              controller: _passwordCtrl,
                              value: _passwordCtrl.text,
                              hintText: 'New password',
                              icon: Icons.lock_outline,
                              obscureText: !_showPassword,
                              onChanged: (val) => _validatePassword(val),
                              suffixWidget: GestureDetector(
                                onTap: () => setState(
                                  () => _showPassword = !_showPassword,
                                ),
                                child: Padding(
                                  padding: EdgeInsets.all(w * 0.03),
                                  child: Image.asset(
                                    _showPassword
                                        ? 'assets/images/eye.webp'
                                        : 'assets/images/closed_eye.webp',
                                    height: w * 0.05,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: w * 0.038),

                            RoundedInputField(
                              controller: _confirmCtrl,
                              value: _confirmCtrl.text,
                              hintText: 'Confirm new password',
                              icon: Icons.lock_outline,
                              obscureText: !_showConfirm,
                              isError: _isMismatch,
                              onChanged: (_) => setState(() {}),
                              suffixWidget: GestureDetector(
                                onTap: () => setState(
                                  () => _showConfirm = !_showConfirm,
                                ),
                                child: Padding(
                                  padding: EdgeInsets.all(w * 0.03),
                                  child: Image.asset(
                                    _showConfirm
                                        ? 'assets/images/eye.webp'
                                        : 'assets/images/closed_eye.webp',
                                    height: w * 0.05,
                                  ),
                                ),
                              ),
                            ),

                            // Mismatch — no icon
                            if (_isMismatch)
                              Padding(
                                padding: EdgeInsets.only(
                                  top: w * 0.02,
                                  left: w * 0.02,
                                ),
                                child: Text(
                                  'Passwords do not match',
                                  style: TextStyle(
                                    fontSize: w * 0.032,
                                    color: AppColors.red,
                                  ),
                                ),
                              ),

                            SizedBox(height: w * 0.04),

                            if (_passwordCtrl.text.isNotEmpty)
                              _buildStrengthBar(w),
                            SizedBox(height: w * 0.035),
                            _buildRequirements(w),
                            SizedBox(height: w * 0.06),

                            // API error — centered, no outline, no icon
                            if (_apiError != null)
                              Padding(
                                padding: EdgeInsets.only(bottom: w * 0.04),
                                child: Center(
                                  child: Text(
                                    _apiError!,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: w * 0.034,
                                      color: AppColors.red,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ),

                            _buildUpdateButton(w),
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

  // Shield icon — pulse outer ring + float inner icon (distinct from S1/S2)
  Widget _buildAnimatedIcon(double w) {
    final size = (w * 0.28).clamp(80.0, 140.0);
    return AnimatedBuilder(
      animation: Listenable.merge([_pulseAnim, _floatAnim]),
      builder: (_, child) => Transform.scale(
        scale: _pulseAnim.value,
        child: Transform.translate(
          offset: Offset(0, _floatAnim.value),
          child: child,
        ),
      ),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.green.withValues(alpha: 0.08),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Container(
            width: size * 0.65,
            height: size * 0.65,
            decoration: BoxDecoration(
              color: AppColors.green.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Padding(
              padding: EdgeInsets.all(size * 0.14),
              child: Image.asset(
                'assets/images/protection.webp',
                fit: BoxFit.contain,
                color: AppColors.green,
                colorBlendMode: BlendMode.srcIn,
                errorBuilder: (_, _, _) => Icon(
                  Icons.shield_outlined,
                  size: size * 0.38,
                  color: AppColors.green,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStrengthBar(double w) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Strength: ',
              style: TextStyle(fontSize: w * 0.032, color: AppColors.hint),
            ),
            Text(
              _strengthText,
              style: TextStyle(
                fontSize: w * 0.032,
                color: _strengthColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        SizedBox(height: w * 0.02),
        PasswordStrengthBar(score: _strengthScore),
      ],
    );
  }

  Widget _buildRequirements(double w) {
    return Column(
      children: [
        Row(
          children: [
            _requirement(w, 'At least 8 characters', _hasMinLength),
            SizedBox(width: w * 0.03),
            _requirement(w, 'One number', _hasNumber),
          ],
        ),
        SizedBox(height: w * 0.02),
        Row(
          children: [
            _requirement(w, 'One uppercase letter', _hasUpper),
            SizedBox(width: w * 0.03),
            _requirement(w, 'One special character', _hasSpecial),
          ],
        ),
      ],
    );
  }

  Widget _requirement(double w, String label, bool met) {
    return Expanded(
      child: Row(
        children: [
          Icon(
            met ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            size: w * 0.042,
            color: met ? AppColors.green : AppColors.hint,
          ),
          SizedBox(width: w * 0.018),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: w * 0.030,
                color: met ? AppColors.green : AppColors.hint,
                fontWeight: met ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpdateButton(double w) {
    return SizedBox(
      width: double.infinity,
      height: w * 0.138,
      child: ElevatedButton(
        onPressed: (_isLoading || !_isFormValid) ? null : _updatePassword,
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
        child: _isLoading
            ? SizedBox(
                width: w * 0.052,
                height: w * 0.052,
                child: const CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Colors.white,
                ),
              )
            : Text(
                'Update password',
                style: TextStyle(
                  fontSize: w * 0.042,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.1,
                ),
              ),
      ),
    );
  }
}
