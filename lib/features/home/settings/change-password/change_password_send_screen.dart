import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../../../core/widgets/responsive_page.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/services/password_cooldown.dart';
import '../../../../core/widgets/mobile_form_shell.dart';
import 'change_password_verify_screen.dart';
import '../../../../core/widgets/loading/loading_overlay.dart';
import '../../../../core/theme/citizen_ui.dart';
import '../../../../core/widgets/Home/Account/account_web_kit.dart';

class ChangePasswordSendScreen extends StatefulWidget {
  final String email;
  const ChangePasswordSendScreen({super.key, required this.email});
  @override
  State<ChangePasswordSendScreen> createState() =>
      _ChangePasswordSendScreenState();
}

class _ChangePasswordSendScreenState extends State<ChangePasswordSendScreen>
    with TickerProviderStateMixin {
  static const String _baseUrl =
      'https://vxvflhjbafqwehuxnmeq.supabase.co/functions/v1';
  static const String _apiKey =
      'sb_publishable_ZBDaQPQdFyC5kOHGbce9Ig_zdtIi6Mo';

  bool _isLoading = false;
  bool _isCheckingLock = true;
  String? _errorText;
  bool _isLocked = false;
  int _daysRemaining = 0;

  late final AnimationController _slideCtrl;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));
    _fadeAnim = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut));
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(
      begin: 1.0,
      end: 1.08,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkLockStatus();
    });
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  /// Reads the cooldown from `profiles`, NOT `citizen_details`.
  ///
  /// The old query hit citizen_details, whose rows exist only after a
  /// verification submission is approved. A pending or unverified citizen has
  /// no row there, so maybeSingle() returned null, the lock never engaged, and
  /// the cooldown simply did not apply to them. Every account has a profiles
  /// row. See [PasswordCooldown].
  Future<void> _checkLockStatus() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user != null) {
      final remaining = await PasswordCooldown.remainingDays(supabase, user.id);
      if (remaining != null && mounted) {
        setState(() {
          _isLocked = true;
          _daysRemaining = remaining;
        });
      }
    }
    if (mounted) {
      setState(() => _isCheckingLock = false);
      _slideCtrl.forward();
    }
  }

  Future<void> _sendOtp() async {
    if (_isLoading || _isLocked) return;
    setState(() {
      _isLoading = true;
      _errorText = null;
    });
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/reset-send-otp'),
        headers: {
          'Content-Type': 'application/json',
          'apikey': _apiKey,
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({'email': widget.email.trim()}),
      );
      if (!mounted) return;
      Map<String, dynamic> data = {};
      try {
        data = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {}
      if (response.statusCode == 200 && (data['success'] ?? false) == true) {
        Navigator.push(
          context,
          PageRouteBuilder(
            transitionDuration: Duration.zero,
            reverseTransitionDuration: const Duration(milliseconds: 280),
            pageBuilder: (_, _, _) =>
                ChangePasswordVerifyScreen(email: widget.email),
            transitionsBuilder: (_, anim, _, child) =>
                FadeTransition(opacity: anim, child: child),
          ),
        ).then((_) {
          // Re-check lock when returning from S2/S3 — catches the case where
          // S3 just wrote last_password_changed_at and we need to show the banner
          if (mounted) _checkLockStatus();
        });
      } else {
        final msg =
            data['message'] as String? ??
            data['error'] as String? ??
            'Failed to send code. Please try again.';
        setState(
          () => _errorText = response.statusCode == 429
              ? msg // server message is already user-friendly
              : _friendlyError(msg),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorText = _friendlyError(e.toString()));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _friendlyError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('network') ||
        lower.contains('socket') ||
        lower.contains('connection') ||
        lower.contains('clientexception')) {
      return 'Network error. Please check your connection and try again.';
    }
    if (lower.contains('too many') || lower.contains('rate limit')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    if (raw.length < 120 && !raw.contains('uri=') && !raw.contains('://')) {
      return raw;
    }
    return 'Something went wrong. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width.clamp(0.0, 480.0);

    // ── WEB ────────────────────────────────────────────────────────────────
    //
    // `kIsWeb` with no width test: a browser always gets this, the app never
    // does. Everything below this branch is the mobile screen, untouched.
    //
    // It bypasses [ResponsivePageBody] rather than configuring it. That widget
    // would wrap the page in SettingsWebShell — a 600px column beside a
    // decorative brand panel — which was right when this was a standalone route
    // and is wrong inside a pane that already has a top nav and a left rail.
    //
    // And there is no header, so there is no back chevron. On a phone the
    // chevron returns you to the screen you pushed from; here it would pop the
    // whole account route and drop you on Settings, a page you did not ask for.
    if (kIsWeb) {
      return Scaffold(
        backgroundColor: CitizenUi.pageBg,
        body: SafeArea(
          // Mirrors this step exactly: title, stepper, one section holding the
          // email field, a notice, and the action row. See the note on
          // [AccountPageSkeleton] for why the SkeletonLayout entry is not used.
          child: _isCheckingLock
              ? const AccountPageSkeleton(
                  stepper: true,
                  sections: [
                    [1],
                  ],
                  notice: true,
                  actions: true,
                )
              : _buildWebBody(),
        ),
      );
    }

    if (_isCheckingLock) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: ResponsivePageBody(
          maxWidth: 520,
          shellTitle: 'Change Password',
          shellSubtitle:
              'Update your password to keep your GovPulse account secure.',
          shellIcon: Icons.lock_rounded,
          shellHighlights: const [
            (Icons.mark_email_read_rounded, "Verify it's you by email"),
            (Icons.shield_rounded, 'Choose a strong new password'),
            (Icons.check_circle_rounded, 'Takes less than a minute'),
          ],
          child: SafeArea(
            child: Column(
              children: [
                _buildHeader(w),
                Expanded(
                  child: LoadingOverlay.bodyOrSkeleton(
                    isLoading: true,
                    layout: SkeletonLayout.changePassword,
                    child: const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      body: ResponsivePageBody(
        maxWidth: 520,
        shellTitle: 'Change Password',
        shellSubtitle:
            'Update your password to keep your GovPulse account secure.',
        shellIcon: Icons.lock_rounded,
        shellHighlights: const [
          (Icons.mark_email_read_rounded, "Verify it's you by email"),
          (Icons.shield_rounded, 'Choose a strong new password'),
          (Icons.check_circle_rounded, 'Takes less than a minute'),
        ],
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
                              'Change Password',
                              style: TextStyle(
                                fontSize: w * 0.058,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primaryBlue,
                                letterSpacing: -0.3,
                              ),
                            ),
                            SizedBox(height: w * 0.025),
                            Text(
                              _isLocked
                                  ? 'You recently changed your password.\nPlease wait before changing it again.'
                                  : 'We\'ll send a 6-digit verification code\nto your registered email address.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: w * 0.036,
                                color: AppColors.hint,
                                height: 1.5,
                              ),
                            ),
                            SizedBox(height: w * 0.07),
                            _buildEmailField(w),
                            SizedBox(height: w * 0.04),
                            _isLocked ? _buildLockBanner(w) : _buildInfoChip(w),
                            SizedBox(height: w * 0.07),
                            if (_errorText != null)
                              Padding(
                                padding: EdgeInsets.only(bottom: w * 0.04),
                                child: Text(
                                  _errorText!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: w * 0.033,
                                    color: AppColors.red,
                                  ),
                                ),
                              ),
                            _buildSendButton(w),
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

  // ══════════════════════════════════════════════════════════════════════════
  //  WEB LAYOUT — step 1 of 3
  //
  //  Built from account_web_kit.dart, like Edit Profile and Settings.
  //
  //  The three steps stay three pushed routes, as they are on mobile: they
  //  stack INSIDE this pane, so the shell chrome never unmounts and the address
  //  bar stays on /settings/password throughout. Finishing pops back to here,
  //  which is why this step re-checks the cooldown on return — you land on the
  //  page you started from with the new cooldown showing, never on Settings.
  //
  //  Step 1 has no secondary action. Steps 2 and 3 offer "Back", which moves
  //  one step inside the flow; here there is nothing to go back TO that is not
  //  outside the flow entirely.
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildWebBody() {
    return AccountPageBody(
      builder: (context, stack) => FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AccountPageTitle(
                title: 'Change Password',
                subtitle:
                    'Confirm your email, enter the code we send you, then '
                    'choose a new password.',
              ),
              const AccountStepper(step: 0, labels: kChangePasswordSteps),
              AccountFieldSection(
                title: 'Your email',
                stack: stack,
                rows: [
                  [
                    AccountReadonlyField(label: 'Email', value: widget.email),
                    // Holds the second column open so the address keeps a
                    // sensible input width instead of spanning the card.
                    const SizedBox.shrink(),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              if (_isLocked)
                AccountNotice(
                  stack: stack,
                  tone: AccountNoticeTone.warning,
                  icon: Icons.lock_clock_rounded,
                  title: 'Password recently changed',
                  message:
                      'You can change it again once the cooldown has passed.',
                  trailing: AccountNoticePill(
                    label:
                        '$_daysRemaining ${_daysRemaining == 1 ? 'day' : 'days'} left',
                  ),
                )
              else
                AccountNotice(
                  stack: stack,
                  icon: Icons.mark_email_read_rounded,
                  title: 'We will email you a 6-digit code',
                  message:
                      'It goes to the address above and expires shortly, so '
                      'keep this tab open.',
                ),
              if (_errorText != null) ...[
                const SizedBox(height: 16),
                AccountErrorStrip(_errorText!),
              ],
              const SizedBox(height: 28),
              AccountActions(
                stack: stack,
                busy: _isLoading,
                primaryLabel: _isLocked
                    ? 'Change unavailable'
                    : 'Send verification code',
                onPrimary: (_isLoading || _isLocked) ? null : _sendOtp,
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
                border: Border.all(color: CitizenUi.sharedStroke),
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
                'assets/images/padlock.webp',
                fit: BoxFit.contain,
                color: AppColors.primaryBlue,
                colorBlendMode: BlendMode.srcIn,
                errorBuilder: (_, _, _) => Icon(
                  Icons.lock_outline_rounded,
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

  Widget _buildEmailField(double w) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: w * 0.04, vertical: w * 0.038),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(w * 0.035),
        border: Border.all(color: CitizenUi.sharedStroke),
      ),
      child: Row(
        children: [
          Icon(Icons.email_outlined, size: w * 0.052, color: AppColors.hint),
          SizedBox(width: w * 0.03),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Email address',
                  style: TextStyle(
                    fontSize: w * 0.028,
                    color: AppColors.hint,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: w * 0.005),
                Text(
                  widget.email,
                  style: TextStyle(
                    fontSize: w * 0.038,
                    color: const Color(0xFF9CA3AF),
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Icon(
            Icons.lock_rounded,
            size: w * 0.042,
            color: const Color(0xFFD1D5DB),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(double w) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: w * 0.04, vertical: w * 0.032),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(w * 0.03),
        border: Border.all(
          color: AppColors.primaryBlue.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: w * 0.042,
            color: AppColors.primaryBlue,
          ),
          SizedBox(width: w * 0.025),
          Expanded(
            child: Text(
              'A 6-digit code will be sent to this email. The code expires in 2 minutes.',
              style: TextStyle(
                fontSize: w * 0.032,
                color: const Color(0xFF1E40AF),
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLockBanner(double w) {
    const amber = Color(0xFFF59E0B);
    const amberDark = Color(0xFFB45309);
    const amberText = Color(0xFF92400E);
    // Fills up as the unlock date approaches (elapsed days / 30).
    final progress = ((30 - _daysRemaining) / 30.0).clamp(0.0, 1.0);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(w * 0.045),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFBEB), Color(0xFFFFF1D6)],
        ),
        borderRadius: BorderRadius.circular(w * 0.05),
        border: Border.all(color: amber.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: amber.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 8),
            spreadRadius: -6,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Vivid icon chip ──────────────────────────────────────
              Container(
                width: w * 0.12,
                height: w * 0.12,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFBBF24), Color(0xFFF59E0B)],
                  ),
                  borderRadius: BorderRadius.circular(w * 0.036),
                  boxShadow: [
                    BoxShadow(
                      color: amber.withValues(alpha: 0.40),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                      spreadRadius: -3,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.lock_clock_rounded,
                  color: Colors.white,
                  size: w * 0.062,
                ),
              ),
              SizedBox(width: w * 0.035),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Password Change Locked',
                      style: TextStyle(
                        fontSize: w * 0.040,
                        fontWeight: FontWeight.w800,
                        color: amberDark,
                        letterSpacing: -0.2,
                      ),
                    ),
                    SizedBox(height: w * 0.012),
                    Text(
                      'For your security, you can change your password again '
                      'in $_daysRemaining day${_daysRemaining == 1 ? '' : 's'}.',
                      style: TextStyle(
                        fontSize: w * 0.032,
                        color: amberText,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: w * 0.04),
          // ── Progress + days-left pill ──────────────────────────────────
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(w * 0.02),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: w * 0.022,
                    backgroundColor: amber.withValues(alpha: 0.18),
                    valueColor: const AlwaysStoppedAnimation<Color>(amber),
                  ),
                ),
              ),
              SizedBox(width: w * 0.03),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: w * 0.028,
                  vertical: w * 0.012,
                ),
                decoration: BoxDecoration(
                  color: amber.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(w * 0.05),
                ),
                child: Text(
                  '$_daysRemaining day${_daysRemaining == 1 ? '' : 's'} left',
                  style: TextStyle(
                    fontSize: w * 0.028,
                    fontWeight: FontWeight.w800,
                    color: amberDark,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSendButton(double w) {
    final disabled = _isLoading || _isLocked || _isCheckingLock;
    return SizedBox(
      width: double.infinity,
      height: w * 0.138,
      child: ElevatedButton(
        onPressed: disabled ? null : _sendOtp,
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
        child: _isLoading || _isCheckingLock
            ? SizedBox(
                width: w * 0.052,
                height: w * 0.052,
                child: const CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Colors.white,
                ),
              )
            : Text(
                _isLocked ? 'Locked' : 'Send verification code',
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
