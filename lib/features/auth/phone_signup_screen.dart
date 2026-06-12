import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../core/widgets/mobile_form_shell.dart';
import '../../core/utils/password_validator.dart';
import '../../core/widgets/inputs/rounded_input_field.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/indicators/password_strength_bar.dart';
import '../../core/widgets/web/web.dart';

class PhoneSignupScreen extends StatefulWidget {
  final Function(String, String) onContinueClick;
  final VoidCallback onBackClick;
  final VoidCallback onLoginClick;

  const PhoneSignupScreen({
    super.key,
    required this.onContinueClick,
    required this.onBackClick,
    required this.onLoginClick,
  });

  @override
  State<PhoneSignupScreen> createState() => _PhoneSignupScreenState();
}

class _PhoneSignupScreenState extends State<PhoneSignupScreen>
    with TickerProviderStateMixin {
  String phone = "";
  String username = "";
  String password = "";
  String confirmPassword = "";

  bool showPassword = false;
  bool showConfirmPassword = false;

  bool hasMinLength = false;
  bool hasUpper = false;
  bool hasNumber = false;
  bool hasSpecial = false;
  bool get isPasswordMismatch =>
      confirmPassword.isNotEmpty && password != confirmPassword;

  // ── Entrance + background animations ─────────────────────────────────────
  // Content slides up and fades in — the screen itself appears instantly
  // (PageRouteBuilder with zero transitionDuration handled by the caller).
  late final AnimationController _entranceController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;
  late final AnimationController _bgController;

  final TextEditingController _webPhoneController = TextEditingController();

  @override
  void initState() {
    super.initState();

    // Content entrance: 500 ms, slight upward slide + fade
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

    // Background blob animation (web hero panel)
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    )..repeat(reverse: true);

    // Tiny delay lets the route settle before starting — avoids a 1-frame stutter
    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) _entranceController.forward();
    });
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _bgController.dispose();
    _webPhoneController.dispose();
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

  bool get canSubmit => isPasswordValid && phone.length == 10;

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

  void _onPhoneChanged(String val) {
    if (val.length <= 10) {
      setState(() => phone = val);
    } else {
      _webPhoneController.value = TextEditingValue(
        text: phone,
        selection: TextSelection.collapsed(offset: phone.length),
      );
    }
  }

  void _onUsernameChanged(String val) => setState(() => username = val);

  void _onPasswordChanged(String val) {
    setState(() {
      password = val;
      validatePassword(val);
    });
  }

  void _onConfirmChanged(String val) => setState(() => confirmPassword = val);

  Future<void> _submit() async {
    await widget.onContinueClick(phone, password);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    if (!kIsWeb) return _mobileScaffold(context);

    if (width >= kWebTwoPanelMinWidth) return _webScaffold(context);
    return _webCompactScaffold(context);
  }

  // ── Mobile layout ─────────────────────────────────────────────────────────
  Widget _mobileScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          // Wrap the entire scrollable body in the entrance animation so every
          // element slides and fades together.
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

                      const SizedBox(height: 6),

                      Text(
                        "Continue with Mobile Number",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryBlue,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 6),

                      Text(
                        "Verify your mobile number to create an account",
                        style: TextStyle(fontSize: 13, color: AppColors.hint),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 14),

                      // PHONE
                      RoundedInputField(
                        value: phone,
                        hintText: "Phone Number",
                        icon: Icons.phone,
                        prefix: Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Text(
                            "+63 ",
                            style: TextStyle(
                              color: AppColors.primaryBlue,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        onChanged: (val) {
                          if (val.length <= 10) {
                            setState(() => phone = val);
                          }
                        },
                      ),

                      const SizedBox(height: 12),

                      // USERNAME
                      RoundedInputField(
                        value: username,
                        hintText: "Username",
                        icon: Icons.person,
                        onChanged: _onUsernameChanged,
                      ),

                      const SizedBox(height: 14),

                      // PASSWORD
                      RoundedInputField(
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
                            child: Image.asset(
                              showPassword
                                  ? "assets/images/eye.webp"
                                  : "assets/images/closed_eye.webp",
                              height: 20,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // CONFIRM PASSWORD
                      RoundedInputField(
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
                            child: Image.asset(
                              showConfirmPassword
                                  ? "assets/images/eye.webp"
                                  : "assets/images/closed_eye.webp",
                              height: 20,
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
                          _requirement("At least 8 characters", hasMinLength),
                          const SizedBox(width: 10),
                          _requirement("Must have number", hasNumber),
                        ],
                      ),

                      const SizedBox(height: 6),

                      Row(
                        children: [
                          _requirement("One uppercase letter", hasUpper),
                          const SizedBox(width: 10),
                          _requirement("One special character", hasSpecial),
                        ],
                      ),

                      const SizedBox(height: 18),

                      // SIGN UP BUTTON
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
                          onPressed: canSubmit ? _submit : null,
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

                      const SizedBox(height: 8),

                      Text(
                        "We will send you a verification code via SMS",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: AppColors.hint),
                      ),

                      const SizedBox(height: 16),

                      Row(
                        children: [
                          Expanded(child: Divider(color: AppColors.stroke)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              "Or Return to",
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
                        width: 220,
                        height: 56,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: AppColors.stroke),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: widget.onBackClick,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Image.asset(
                                "assets/images/out.webp",
                                width: 28,
                                height: 28,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                "Sign Up",
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primaryBlue,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

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

                      const SizedBox(height: 20),
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
                  "Verify your mobile number to report issues, discover\nevents, and stay connected with Aparri.",
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
          "Continue with mobile",
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
          "Verify your mobile number to create an account",
          style: TextStyle(fontSize: 14, color: AppColors.hint, height: 1.5),
        ),

        const SizedBox(height: 32),

        // Phone (with +63 prefix)
        WebInputField(
          hint: "Phone number",
          icon: Icons.phone_outlined,
          keyboardType: TextInputType.phone,
          controller: _webPhoneController,
          textInputAction: TextInputAction.next,
          onChanged: _onPhoneChanged,
          prefix: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              "+63",
              style: TextStyle(
                color: AppColors.primaryBlue,
                fontWeight: FontWeight.w600,
                fontSize: 14.5,
              ),
            ),
          ),
        ),

        const SizedBox(height: 14),

        // Username
        WebInputField(
          hint: "Username",
          icon: Icons.person_outline_rounded,
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.next,
          onChanged: _onUsernameChanged,
        ),

        const SizedBox(height: 14),

        // Password
        WebInputField(
          hint: "Password",
          icon: Icons.lock_outline_rounded,
          keyboardType: TextInputType.visiblePassword,
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
          obscure: !showConfirmPassword,
          isError: isPasswordMismatch,
          textInputAction: TextInputAction.done,
          onChanged: _onConfirmChanged,
          onSubmitted: (_) {
            if (canSubmit) _submit();
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
            _requirement("At least 8 characters", hasMinLength),
            const SizedBox(width: 12),
            _requirement("Must have number", hasNumber),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _requirement("One uppercase letter", hasUpper),
            const SizedBox(width: 12),
            _requirement("One special character", hasSpecial),
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
                  overlayColor: WidgetStateProperty.all(
                    Colors.white.withValues(alpha: 0.08),
                  ),
                ),
            onPressed: canSubmit ? _submit : null,
            child: const Text(
              "Sign up",
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ),

        const SizedBox(height: 12),

        Text(
          "We will send you a verification code via SMS",
          style: TextStyle(fontSize: 12, color: AppColors.hint),
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

        Center(
          child: SizedBox(
            width: 220,
            child: WebOutlinedButton(
              icon: Icons.arrow_back_rounded,
              label: "Back to sign up",
              onTap: widget.onBackClick,
            ),
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
