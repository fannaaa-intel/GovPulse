import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../../core/router/legacy_nav.dart';
import '../../core/widgets/inputs/rounded_input_field.dart';
import '../../core/utils/password_validator.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/indicators/password_strength_bar.dart';
import '../../core/widgets/web/web.dart';
import '../../features/verification/screens/email_verification_screen.dart';
import '../../features/onboarding/otp_loading_screen.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/facebook_signin_service.dart';
import '../../core/widgets/auth/facebook_auth_overlay.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../core/network/network_wrapper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/widgets/mobile_form_shell.dart';
import 'dart:async';

// Screens navigated to from here — imported so PageRouteBuilder can reference them.
import '../auth/facebook_username_screen.dart';
import '../guest/screen/guest.dart';
import '../../core/widgets/app_dialog.dart';

// Route observer — declare once at app level and pass to MaterialApp's navigatorObservers.
// If you already have one, just reuse it here instead.
final RouteObserver<ModalRoute<void>> signupRouteObserver =
    RouteObserver<ModalRoute<void>>();

class SignupScreen extends StatefulWidget {
  final Function(String, String, String) onSignUpClick;
  final VoidCallback onLoginClick;
  final VoidCallback onGuestClick;
  final VoidCallback onFacebookClick;

  const SignupScreen({
    super.key,
    required this.onSignUpClick,
    required this.onLoginClick,
    required this.onGuestClick,
    required this.onFacebookClick,
  });

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen>
    with TickerProviderStateMixin, RouteAware {
  String email = "";
  String username = "";
  String password = "";
  String confirmPassword = "";

  bool showPassword = false;
  bool showConfirmPassword = false;
  bool emailLocked = false;
  bool _fbBusy = false;

  Timer? _emailDebounce;
  Timer? _usernameDebounce;

  String? emailErrorText;
  String? usernameErrorText;

  bool isCheckingEmail = false;
  bool isCheckingUsername = false;

  bool get isPasswordMismatch =>
      confirmPassword.isNotEmpty && password != confirmPassword;

  final TextEditingController emailController = TextEditingController();
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();

  final FocusNode passwordFocusNode = FocusNode();

  bool hasMinLength = false;
  bool hasUpper = false;
  bool hasNumber = false;
  bool hasSpecial = false;

  // ── Entrance + background animations ──────────────────────────────────────
  late final AnimationController _entranceController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;
  late final AnimationController _bgController;

  String _friendly(String raw) {
    final cleaned = raw.replaceFirst('Exception: ', '');
    if (cleaned.toLowerCase().contains('invalid format')) {
      return 'Unable to validate email address';
    }
    return cleaned;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    signupRouteObserver.subscribe(this, ModalRoute.of(context)!);
  }

  /// Called when a route above this one is popped.
  /// Resets and replays the entrance animation so content slides up again.
  @override
  void didPopNext() {
    _entranceController.reset();
    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) _entranceController.forward();
    });
  }

  @override
  void initState() {
    super.initState();

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOut,
    );
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _entranceController,
            curve: Curves.easeOutCubic,
          ),
        );

    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    )..repeat(reverse: true);

    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) _entranceController.forward();
    });
  }

  @override
  void dispose() {
    signupRouteObserver.unsubscribe(this);
    emailController.dispose();
    usernameController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    passwordFocusNode.dispose();
    _emailDebounce?.cancel();
    _usernameDebounce?.cancel();
    _entranceController.dispose();
    _bgController.dispose();
    super.dispose();
  }

  // ── Shared logic ──────────────────────────────────────────────────────────
  void validatePassword(String value) {
    hasMinLength = PasswordValidator.hasMinLength(value);
    hasUpper = PasswordValidator.hasUpper(value);
    hasNumber = PasswordValidator.hasNumber(value);
    hasSpecial = PasswordValidator.hasSpecial(value);
  }

  bool get isPasswordValid =>
      hasMinLength &&
      hasUpper &&
      hasNumber &&
      hasSpecial &&
      password == confirmPassword;

  bool get canSubmit =>
      isPasswordValid && emailErrorText == null && usernameErrorText == null;

  int get strengthScore => PasswordValidator.strengthScore(password);

  Color get strengthColor {
    if (strengthScore <= 1) return AppColors.red;
    if (strengthScore == 2 || strengthScore == 3) return AppColors.orange;
    return AppColors.green;
  }

  String get strengthText {
    if (strengthScore <= 1) return "Weak";
    if (strengthScore == 2 || strengthScore == 3) return "Medium";
    return "Strong";
  }

  void _onEmailChanged(String val) {
    setState(() {
      email = val;
      emailErrorText = null;
    });

    if (_emailDebounce?.isActive ?? false) _emailDebounce!.cancel();

    _emailDebounce = Timer(const Duration(milliseconds: 600), () async {
      setState(() => isCheckingEmail = true);

      final exists = await AuthService.checkEmailExists(email);
      if (!mounted) return;
      setState(() {
        isCheckingEmail = false;
        emailErrorText = exists ? "Email is already used" : null;
      });
    });
  }

  void _onUsernameChanged(String val) {
    setState(() {
      username = val;
      usernameErrorText = null;
    });

    if (_usernameDebounce?.isActive ?? false) _usernameDebounce!.cancel();

    _usernameDebounce = Timer(const Duration(milliseconds: 600), () async {
      if (username.isEmpty) return;

      setState(() => isCheckingUsername = true);

      final exists = await AuthService.checkUsernameExists(username);
      if (!mounted) return;

      if (username != usernameController.text) return;

      setState(() {
        isCheckingUsername = false;
        usernameErrorText = exists ? "Username is already taken" : null;
      });
    });
  }

  void _onPasswordChanged(String val) {
    setState(() {
      password = val;
      validatePassword(val);
    });
  }

  void _onConfirmChanged(String val) {
    setState(() => confirmPassword = val);
  }

  // ── Navigation helpers ────────────────────────────────────────────────────

  void _goToGuest() {
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => const GuestScreen(),
      ),
    );
  }

  Future<void> _signInWithFacebook() async {
    if (_fbBusy) return;
    setState(() => _fbBusy = true);
    try {
      final user = await facebookSignInDetectingCancel();

      if (!mounted) return;
      if (user == null) {
        // User backed out of the Facebook browser — drop the overlay and tell
        // them it didn't go through (instead of silently returning).
        setState(() => _fbBusy = false);
        showAppSnackBar(
          context,
          "Facebook sign-in cancelled.",
          type: AppSnackType.error,
        );
        return;
      }

      // This Facebook account may already belong to an existing user. If they
      // already picked a username, they're not signing up — send them straight
      // into the app (same as the login screen), instead of the username picker
      // where their existing handle would collide as "already exists".
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('username')
          .eq('id', user.id)
          .maybeSingle();

      final hasUsername =
          profile != null &&
          (profile['username'] as String?)?.isNotEmpty == true;

      if (!mounted) return;

      if (hasUsername) {
        // Existing Facebook user — go straight into the app. Leave the overlay
        // up; the app screen replaces this one, so it never flashes back.
        widget.onFacebookClick();
        return;
      }

      // New user — fetch their Facebook display name to pre-fill the suggestion.
      final fbData = await FacebookSignInService.getUserData();
      final fbName = fbData['name'] as String? ?? '';

      if (!mounted) return;

      // The username screen fully covers this one; drop the overlay so a
      // back-out from there returns to a normal sign-up (not a stuck spinner).
      setState(() => _fbBusy = false);
      Navigator.push(
        context,
        PageRouteBuilder(
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, _, _) => NetworkWrapper(
            child: FacebookUsernameScreen(
              facebookName: fbName,
              onComplete: (username) async {
                await Supabase.instance.client
                    .from('profiles')
                    .update({'username': username})
                    .eq('id', user.id);

                if (!mounted) return;
                widget.onFacebookClick();
              },
              onCancel: () async {
                await FacebookSignInService.signOut();
                if (!mounted) return;
                Navigator.pop(context);
              },
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _fbBusy = false);
      final msg = e.toString().replaceFirst('Exception: ', '');
      // Surface via the shared dialog (not a SnackBar / inline text).
      if (msg != 'Facebook sign-in was cancelled.') {
        showAppSnackBar(
          context,
          "Facebook sign-in failed. Please try again.",
          type: AppSnackType.error,
        );
      }
    }
  }

  Future<void> _submitSignup(BuildContext context) async {
    final email = emailController.text.trim();
    final username = usernameController.text.trim();
    final password = passwordController.text.trim();

    try {
      Map<String, dynamic>? result;

      if (kIsWeb) {
        result = await showAppDialog<Map<String, dynamic>>(
          context: context,
          barrierDismissible: false,
          barrierColor: Colors.black.withValues(alpha: 0.45),
          builder: (_) => OtpLoadingScreen(
            type: "email",
            onSendOtp: () => _sendEmailOtp(email, username, password),
          ),
        );
      } else {
        result = await Navigator.push<Map<String, dynamic>>(
          context,
          PageRouteBuilder(
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            pageBuilder: (_, _, _) => OtpLoadingScreen(
              type: "email",
              onSendOtp: () => _sendEmailOtp(email, username, password),
            ),
          ),
        );
      }

      if (!context.mounted) return;

      if (result == null || result["success"] != true) {
        final raw =
            result?["error"] as String? ??
            "Failed to send OTP. Please try again.";

        // Duplicate gate: email OR username already registered (server does not
        // disclose which). Show a clear "already registered — log in" state,
        // not a generic per-field error.
        if (raw == "already_registered") {
          const msg =
              "This email or username is already registered. Try logging in instead.";
          setState(() => emailErrorText = msg);
          showAppSnackBar(context, msg, type: AppSnackType.error);
          return;
        }

        setState(() => emailErrorText = _friendly(raw));
        return;
      }

      Navigator.push(
        context,
        PageRouteBuilder(
          transitionDuration: Duration.zero,
          reverseTransitionDuration: const Duration(milliseconds: 220),
          pageBuilder: (_, _, _) => VerificationScreen(
            email: email,
            username: username,
            password: password,
            onVerifiedSuccess: () {
              pushReplacementLegacy(
                context,
                '/email_verification_success',
                arguments: email,
              );
            },
            onTermsClick: () {},
            onConditionsClick: () {},
          ),
          transitionsBuilder: (_, anim, _, child) =>
              FadeTransition(opacity: anim, child: child),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      setState(() => emailErrorText = _friendly(e.toString()));
    }
  }

  Future<void> _sendEmailOtp(
    String email,
    String username,
    String password,
  ) async {
    final supabase = Supabase.instance.client;

    final canSend = await supabase.rpc(
      'can_send_otp',
      params: {'p_identifier': email, 'p_purpose': 'signup'},
    );
    if (canSend['allowed'] != true) {
      throw Exception(canSend['message'] as String? ?? 'Failed to send OTP');
    }

    // functions.invoke sends the publishable key automatically (satisfies
    // send-email-otp's verify_jwt=true at the gateway) and JSON-decodes the
    // response. It THROWS FunctionException on any non-2xx, so the 409
    // duplicate-gate handling lives in the catch below — mirroring
    // AuthService.login's pattern.
    try {
      final response = await supabase.functions.invoke(
        'send-email-otp',
        body: {
          "email": email,
          "username": username,
          "password": password,
        },
      );

      final data = response.data;
      if (data is! Map || data["success"] != true) {
        throw Exception(
          (data is Map ? data["message"] : null) ?? "Failed to send OTP",
        );
      }
    } on FunctionException catch (e) {
      final details = e.details;
      // 409 already_registered — server-side duplicate gate. Uniform by design:
      // it does NOT say whether email or username matched. Throw a stable
      // sentinel so _submitSignup can route to the dedicated "already
      // registered" state instead of the generic OTP-failure text.
      if (e.status == 409 &&
          details is Map &&
          details["error"] == "already_registered") {
        throw Exception("already_registered");
      }
      throw Exception(
        (details is Map ? details["message"] : null) ?? "Failed to send OTP",
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    final Widget content = !kIsWeb
        ? _mobileScaffold(context)
        : (width >= kWebTwoPanelMinWidth
            ? _webScaffold(context)
            : _webCompactScaffold(context));

    // While Facebook sign-up is in flight, cover the screen with a blocking
    // spinner so the sign-up form never flashes back mid-process.
    return Stack(
      children: [
        content,
        if (_fbBusy) const FacebookAuthOverlay(),
      ],
    );
  }

  // ── Mobile layout ─────────────────────────────────────────────────────────
  Widget _mobileScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SlideTransition(
              position: _slideAnim,
              child: MobileFormShell(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 26),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 18),

                      Image.asset(
                        "assets/images/applogocrop.webp",
                        width: (MediaQuery.of(context).size.width * 0.30)
                            .clamp(0.0, 150.0)
                            .toDouble(),
                      ),

                      const SizedBox(height: 10),

                      Column(
                        children: [
                          Text(
                            "Sign Up for GovPulse",
                            style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primaryBlue,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            "Stay Updated and report community\nissues in Aparri",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.hint,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // EMAIL
                      RoundedInputField(
                        controller: emailController,
                        enabled: !emailLocked,
                        value: email,
                        hintText: "Email Address",
                        icon: Icons.email,
                        isError: emailErrorText != null,
                        suffixWidget: isCheckingEmail
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : null,
                        onChanged: _onEmailChanged,
                      ),

                      if (emailErrorText != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6, left: 6),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              emailErrorText!,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),

                      const SizedBox(height: 12),

                      // USERNAME
                      RoundedInputField(
                        controller: usernameController,
                        value: username,
                        hintText: "Username",
                        icon: Icons.person,
                        isError: usernameErrorText != null,
                        suffixWidget: isCheckingUsername
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : null,
                        onChanged: _onUsernameChanged,
                      ),

                      if (usernameErrorText != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6, left: 6),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              usernameErrorText!,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),

                      const SizedBox(height: 14),

                      // PASSWORD
                      RoundedInputField(
                        controller: passwordController,
                        focusNode: passwordFocusNode,
                        value: password,
                        hintText: "Password",
                        icon: Icons.lock,
                        obscureText: !showPassword,
                        onChanged: _onPasswordChanged,
                        suffixWidget: GestureDetector(
                          onTap: () =>
                              setState(() => showPassword = !showPassword),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Icon(
                              showPassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 20,
                              color: AppColors.primaryBlue,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // CONFIRM PASSWORD
                      RoundedInputField(
                        controller: confirmPasswordController,
                        value: confirmPassword,
                        hintText: "Confirm Password",
                        icon: Icons.lock,
                        obscureText: !showConfirmPassword,
                        isError: isPasswordMismatch,
                        onChanged: _onConfirmChanged,
                        suffixWidget: GestureDetector(
                          onTap: () => setState(
                            () => showConfirmPassword = !showConfirmPassword,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Icon(
                              showConfirmPassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 20,
                              color: AppColors.primaryBlue,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 8),

                      if (password.isNotEmpty)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Strength: $strengthText",
                              style: TextStyle(
                                fontSize: 12,
                                color: strengthColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            PasswordStrengthBar(score: strengthScore),
                            const SizedBox(height: 10),
                          ],
                        ),

                      Row(
                        children: [
                          _requirement("Atleast 8 characters", hasMinLength),
                          const SizedBox(width: 12),
                          _requirement("Must have number", hasNumber),
                        ],
                      ),

                      const SizedBox(height: 6),

                      Row(
                        children: [
                          _requirement("One uppercase letter", hasUpper),
                          const SizedBox(width: 12),
                          _requirement("One special Character", hasSpecial),
                        ],
                      ),

                      const SizedBox(height: 16),

                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: canSubmit
                                ? AppColors.primaryBlue
                                : AppColors.primaryBlue.withValues(alpha: 0.4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: canSubmit
                              ? () => _submitSignup(context)
                              : null,
                          child: const Text(
                            "Sign Up",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),

                      Row(
                        children: [
                          Expanded(child: Divider(color: AppColors.stroke)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              "Or Continue with",
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.hint,
                              ),
                            ),
                          ),
                          Expanded(child: Divider(color: AppColors.stroke)),
                        ],
                      ),

                      const SizedBox(height: 12),

                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF374151),
                            side: const BorderSide(
                              color: Color(0xFFCBD2DE),
                              width: 1.2,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: _signInWithFacebook,
                          icon: const Icon(
                            Icons.facebook,
                            size: 20,
                            color: Color(0xFF1877F2),
                          ),
                          label: const Text(
                            "Continue with Facebook",
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF374151),
                            side: const BorderSide(
                              color: Color(0xFFCBD2DE),
                              width: 1.2,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: _goToGuest,
                          icon: const Icon(
                            Icons.person_outline_rounded,
                            size: 20,
                            color: Color(0xFF374151),
                          ),
                          label: const Text(
                            "Continue as guest",
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "Already have an account? ",
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.hint,
                            ),
                          ),
                          GestureDetector(
                            onTap: widget.onLoginClick,
                            child: Text(
                              "Log In",
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primaryBlue,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 18),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Web layout — wide (two panel) ─────────────────────────────────────────
  Widget _webScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: kHeroBgBottom,
      body: Row(
        children: [
          Expanded(
            flex: 56,
            child: WebHeroPanel(
              bgController: _bgController,
              headline: "Join your\ncommunity\ntoday.",
              subtitle:
                  "Create an account to report issues, discover\nevents, and stay connected with Aparri.",
            ),
          ),
          Expanded(
            flex: 44,
            child: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: WebGlassSurface(
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: SlideTransition(
                    position: _slideAnim,
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 48,
                          vertical: 44,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 460),
                          child: WebGlassCard(child: _webFormContent(context)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Web layout — compact (single centered column) ─────────────────────────
  Widget _webCompactScaffold(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final double hPad = width < 600 ? 24 : 40;

    return Scaffold(
      backgroundColor: const Color(0xFFEFF3FB),
      resizeToAvoidBottomInset: true,
      body: WebGlassSurface(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SafeArea(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: Center(
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    padding: EdgeInsets.symmetric(
                      horizontal: hPad,
                      vertical: 36,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: WebGlassCard(child: _webFormContent(context)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _webFormContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Image.asset("assets/images/applogo.webp", height: 30),
            const SizedBox(width: 10),
            Text(
              "GovPulse",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryBlue,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),

        const SizedBox(height: 44),

        const Text(
          "Create account",
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w700,
            color: Color(0xFF111827),
            letterSpacing: -0.9,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          "Join your community and report issues in Aparri",
          style: TextStyle(fontSize: 14, color: AppColors.hint, height: 1.5),
        ),

        const SizedBox(height: 32),

        // Email
        WebInputField(
          hint: "Email address",
          icon: Icons.mail_outline_rounded,
          keyboardType: TextInputType.emailAddress,
          controller: emailController,
          enabled: !emailLocked,
          isError: emailErrorText != null,
          textInputAction: TextInputAction.next,
          onChanged: _onEmailChanged,
          suffix: isCheckingEmail
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
        ),
        WebFieldError(text: emailErrorText),

        const SizedBox(height: 14),

        // Username
        WebInputField(
          hint: "Username",
          icon: Icons.person_outline_rounded,
          keyboardType: TextInputType.text,
          controller: usernameController,
          isError: usernameErrorText != null,
          textInputAction: TextInputAction.next,
          onChanged: _onUsernameChanged,
          suffix: isCheckingUsername
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
        ),
        WebFieldError(text: usernameErrorText),

        const SizedBox(height: 14),

        // Password
        WebInputField(
          hint: "Password",
          icon: Icons.lock_outline_rounded,
          keyboardType: TextInputType.visiblePassword,
          controller: passwordController,
          focusNode: passwordFocusNode,
          obscure: !showPassword,
          textInputAction: TextInputAction.next,
          onChanged: _onPasswordChanged,
          suffix: GestureDetector(
            onTap: () => setState(() => showPassword = !showPassword),
            child: Icon(
              showPassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              size: 18,
              color: AppColors.hint,
            ),
          ),
        ),

        const SizedBox(height: 14),

        // Confirm password
        WebInputField(
          hint: "Confirm password",
          icon: Icons.lock_outline_rounded,
          keyboardType: TextInputType.visiblePassword,
          controller: confirmPasswordController,
          obscure: !showConfirmPassword,
          isError: isPasswordMismatch,
          textInputAction: TextInputAction.done,
          onChanged: _onConfirmChanged,
          onSubmitted: (_) {
            if (canSubmit) _submitSignup(context);
          },
          suffix: GestureDetector(
            onTap: () =>
                setState(() => showConfirmPassword = !showConfirmPassword),
            child: Icon(
              showConfirmPassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              size: 18,
              color: AppColors.hint,
            ),
          ),
        ),
        if (isPasswordMismatch)
          const WebFieldError(text: "Passwords don't match"),

        const SizedBox(height: 18),

        if (password.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Password strength",
                style: TextStyle(fontSize: 12, color: AppColors.hint),
              ),
              Text(
                strengthText,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: strengthColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          WebStrengthBar(
            score: strengthScore.clamp(0, 4),
            color: strengthColor,
          ),
          const SizedBox(height: 18),
        ],

        Row(
          children: [
            _requirement("Atleast 8 characters", hasMinLength),
            const SizedBox(width: 12),
            _requirement("Must have number", hasNumber),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _requirement("One uppercase letter", hasUpper),
            const SizedBox(width: 12),
            _requirement("One special Character", hasSpecial),
          ],
        ),

        const SizedBox(height: 26),

        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            style:
                ElevatedButton.styleFrom(
                  backgroundColor: canSubmit
                      ? AppColors.primaryBlue
                      : AppColors.primaryBlue.withValues(alpha: 0.4),
                  disabledBackgroundColor: AppColors.primaryBlue.withValues(
                    alpha: 0.4,
                  ),
                  elevation: 0,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ).copyWith(
                  overlayColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.pressed)) {
                      return Colors.black.withValues(alpha: 0.14);
                    }
                    if (states.contains(WidgetState.hovered)) {
                      return Colors.black.withValues(alpha: 0.08);
                    }
                    return null;
                  }),
                ),
            onPressed: canSubmit ? () => _submitSignup(context) : null,
            child: const Text(
              "Create account",
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ),

        const SizedBox(height: 22),

        Row(
          children: [
            Expanded(child: Divider(color: AppColors.stroke, thickness: 1)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(
                "or",
                style: TextStyle(fontSize: 12, color: AppColors.grey),
              ),
            ),
            Expanded(child: Divider(color: AppColors.stroke, thickness: 1)),
          ],
        ),

        const SizedBox(height: 18),

        SizedBox(
          width: double.infinity,
          child: WebOutlinedButton(
            icon: Icons.facebook,
            label: "Continue with Facebook",
            onTap: _signInWithFacebook,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: WebOutlinedButton(
            icon: Icons.person_outline_rounded,
            label: "Continue as guest",
            onTap: _goToGuest,
          ),
        ),

        const SizedBox(height: 28),

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "Already have an account? ",
              style: TextStyle(fontSize: 13, color: AppColors.hint),
            ),
            GestureDetector(
              onTap: widget.onLoginClick,
              child: Text(
                "Log in",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryBlue,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _requirement(String text, bool met) {
    return Expanded(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Row(
          key: ValueKey(met),
          children: [
            Icon(
              met ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 16,
              color: met ? AppColors.green : AppColors.grey,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 12,
                  color: met ? AppColors.green : AppColors.grey,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
