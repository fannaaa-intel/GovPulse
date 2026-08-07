import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/router/legacy_nav.dart';
import '../../core/widgets/inputs/rounded_input_field.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/web/web.dart';
import '../../core/widgets/mobile_form_shell.dart';
import '../../core/network/network_wrapper.dart';
import '../../core/services/facebook_signin_service.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../core/widgets/auth/facebook_auth_overlay.dart';
import '../auth/facebook_username_screen.dart';

class LoginScreen extends StatefulWidget {
  final Future<void> Function(String, String) onLoginClick;
  final VoidCallback onSignUpClick;
  final VoidCallback? onGuestClick;
  final VoidCallback? onFacebookClick;

  const LoginScreen({
    super.key,
    required this.onLoginClick,
    required this.onSignUpClick,
    this.onGuestClick,
    this.onFacebookClick,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  String username = "";
  String password = "";
  bool showPassword = false;
  String? errorMessage;
  bool isLoading = false;
  bool _fbBusy = false;

  late final AnimationController _entranceController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;
  late final AnimationController _bgController;

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
    _entranceController.dispose();
    _bgController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    // Native app (phones & tablets) — mobile UI, identical on every size.
    // Web — responsive across all widths.
    final Widget content = !kIsWeb
        ? _mobileScaffold(context)
        : (width >= kWebTwoPanelMinWidth
            ? _webWideScaffold(context)
            : _webCompactScaffold(context));

    // While Facebook sign-in is in flight, cover the whole screen with a
    // blocking spinner so the login form never flashes back mid-process.
    return Stack(
      children: [
        content,
        if (_fbBusy) const FacebookAuthOverlay(),
      ],
    );
  }

  // ── Mobile layout — caps + centers on tablets, always scrolls ─────────────
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 26,
                    vertical: 20,
                  ),
                  child: _mobileFormContent(context),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Web layout — wide (two panel) ─────────────────────────────────────────
  Widget _webWideScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: kHeroBgBottom,
      body: Row(
        children: [
          Expanded(
            flex: 56,
            child: WebHeroPanel(
              bgController: _bgController,
              headline: "Your community,\ndigitally\nconnected.",
              subtitle:
                  "Access services, report issues, and engage\nwith your local government — all in one place.",
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
                          vertical: 48,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 440),
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
                      vertical: 40,
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
    );
  }

  // ── Mobile form (unchanged) ──────────────────────────────────────────────
  Widget _mobileFormContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Image.asset(
          "assets/images/applogocrop.webp",
          width: MediaQuery.of(context).size.width * 0.30,
        ),
        const SizedBox(height: 32),
        Text(
          "Welcome Back",
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.primaryBlue,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          "Please enter your details to access the services",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: AppColors.hint),
        ),
        const SizedBox(height: 20),
        _buildSharedFields(isWeb: false),
      ],
    );
  }

  // ── Web form (used by both wide and compact web layouts) ──────────────────
  Widget _webFormContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Logo mark
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

        const SizedBox(height: 56),

        // Heading
        const Text(
          "Sign in",
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
          "Enter your credentials to access your account",
          style: TextStyle(fontSize: 14, color: AppColors.hint, height: 1.5),
        ),

        const SizedBox(height: 36),

        // Fields
        _buildSharedFields(isWeb: true),

        const SizedBox(height: 28),

        // Footer note
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "Don't have an account? ",
              style: TextStyle(fontSize: 13, color: AppColors.hint),
            ),
            GestureDetector(
              onTap: widget.onSignUpClick,
              child: Text(
                "Sign up",
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

  // ── Shared fields ────────────────────────────────────────────────────────
  // `isWeb` is passed explicitly from the layout, replacing the deprecated
  // WidgetsBinding.instance.window lookup. Mobile output is identical to before.
  Widget _buildSharedFields({required bool isWeb}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isWeb) ...[
          // ── Web-styled fields ──────────────────────────────────────────
          WebInputField(
            hint: "Username",
            icon: Icons.person_outline_rounded,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.next,
            onChanged: (val) => username = val,
          ),
          const SizedBox(height: 14),
          WebInputField(
            hint: "Password",
            icon: Icons.lock_outline_rounded,
            keyboardType: TextInputType.text,
            obscure: !showPassword,
            textInputAction: TextInputAction.done,
            onChanged: (val) => password = val,
            onSubmitted: (_) {
              if (!isLoading) _handleLogin();
            },
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
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () => pushLegacy(context, '/reset_password'),
              child: Text(
                "Forgot password?",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.primaryBlue,
                ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          if (errorMessage != null)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: AppColors.red.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.red.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 16,
                    color: AppColors.red,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      errorMessage!,
                      style: TextStyle(color: AppColors.red, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          // Web sign-in button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style:
                  ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    disabledBackgroundColor: AppColors.primaryBlue.withValues(
                      alpha: 0.55,
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
              onPressed: isLoading ? null : _handleLogin,
              child: isLoading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      "Sign in",
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
              onTap: widget.onGuestClick ?? () {},
            ),
          ),
        ] else ...[
          // ── Mobile fields (unchanged) ──────────────────────────────────
          RoundedInputField(
            value: username,
            hintText: "Username",
            icon: Icons.person,
            onChanged: (val) => username = val,
          ),
          const SizedBox(height: 20),
          RoundedInputField(
            value: password,
            hintText: "Password",
            icon: Icons.lock,
            obscureText: !showPassword,
            onChanged: (val) => password = val,
            suffixWidget: GestureDetector(
              onTap: () => setState(() => showPassword = !showPassword),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Icon(
                  showPassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 22,
                  color: AppColors.primaryBlue,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () => pushLegacy(context, '/reset_password'),
              child: Text(
                "Forgot Password?",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryBlue,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SizedBox(
                width: double.infinity,
                child: Text(
                  errorMessage!,
                  style: const TextStyle(
                    color: Colors.red,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
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
              onPressed: isLoading ? null : _handleLogin,
              child: isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      "Log In",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: Divider(color: AppColors.stroke)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  "Or Continue with",
                  style: TextStyle(fontSize: 13, color: AppColors.hint),
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
                side: const BorderSide(color: Color(0xFFCBD2DE), width: 1.2),
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
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
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
                side: const BorderSide(color: Color(0xFFCBD2DE), width: 1.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: widget.onGuestClick ?? () {},
              icon: const Icon(
                Icons.person_outline_rounded,
                size: 20,
                color: Color(0xFF374151),
              ),
              label: const Text(
                "Continue as guest",
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "Don't have an account? ",
                style: TextStyle(fontSize: 13, color: AppColors.hint),
              ),
              GestureDetector(
                onTap: widget.onSignUpClick,
                child: Text(
                  "Sign up",
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
      ],
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

      // Check if this user already has a username set
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
        widget.onFacebookClick?.call();
      } else {
        // New Facebook user — pick a username first
        final fbData = await FacebookSignInService.getUserData();
        final fbName = fbData['name'] as String? ?? '';

        if (!mounted) return;

        // The username screen fully covers this one; drop the overlay so a
        // back-out from there returns to a normal login (not a stuck spinner).
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
                  widget.onFacebookClick?.call();
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
      }
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

  Future<void> _handleLogin() async {
    final cleanUsername = username.trim();
    final cleanPassword = password;

    if (cleanUsername.isEmpty || cleanPassword.isEmpty) {
      setState(() => errorMessage = "Please enter username and password");
      return;
    }

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      await widget.onLoginClick(cleanUsername, cleanPassword);
    } catch (e) {
      if (mounted) {
        setState(() {
          errorMessage = e.toString().replaceAll("Exception: ", "");
        });
      }
    } finally {
      // A SUCCESSFUL sign-in flips Supabase auth state, which the web router's
      // guard reacts to by redirecting off /login — disposing this screen
      // before the await above resolves here. So by the time this runs there
      // may be no State left to set. Mobile never hits it: there is no guard
      // there, and the screen stays mounted until it is pushed away.
      //
      // `if (mounted)` rather than `if (!mounted) return;` because a return
      // inside a finally block swallows any in-flight exception.
      if (mounted) setState(() => isLoading = false);
    }
  }
}
