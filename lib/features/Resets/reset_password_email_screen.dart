import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../verification/screens/reset_password_email_verify_screen.dart';
import '../../core/theme/app_colors.dart';
import '../onboarding/otp_loading_screen.dart';
import '../../core/widgets/web/web.dart';
import '../../core/widgets/mobile_form_shell.dart';
import '../../core/theme/mobile_metrics.dart';

class ResetPasswordEmailScreen extends StatefulWidget {
  final VoidCallback onLogin;

  const ResetPasswordEmailScreen({
    super.key,
    required this.onLogin,
  });

  @override
  State<ResetPasswordEmailScreen> createState() =>
      _ResetPasswordEmailScreenState();
}

class _ResetPasswordEmailScreenState extends State<ResetPasswordEmailScreen>
    with TickerProviderStateMixin {
  String email = "";
  String errorText = "";
  bool showError = false;
  bool _webLoading = false;

  late AnimationController _heroController;

  // ── Content entrance: instant screen, content fades + slides up ──────────
  late final AnimationController _entranceController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _heroController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);

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

    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) _entranceController.forward();
    });
  }

  @override
  void dispose() {
    _heroController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp({required bool isWeb}) async {
    if (isWeb) setState(() => _webLoading = true);

    try {
      final response = await http.post(
        Uri.parse(
          "https://vxvflhjbafqwehuxnmeq.supabase.co/functions/v1/reset-send-otp",
        ),
        headers: {
          "Content-Type": "application/json",
          "apikey": "sb_publishable_ZBDaQPQdFyC5kOHGbce9Ig_zdtIi6Mo",
          "Authorization": "Bearer sb_publishable_ZBDaQPQdFyC5kOHGbce9Ig_zdtIi6Mo",
        },
        body: jsonEncode({"email": email.trim()}),
      );

      if (!mounted) return;

      Map<String, dynamic> data = {};
      try {
        data = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {}

      if (response.statusCode == 200 && (data["success"] ?? false) == true) {
        if (!mounted) return;
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (_, _, _) => ResetPasswordEmailVerifyScreen(
              email: email.trim(),
              onVerifiedSuccess: () {},
              onTermsClick: () {},
              onConditionsClick: () {},
            ),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
        );
      } else {
        final msg =
            data["message"] as String? ??
            data["error"] as String? ??
            "Something went wrong. Please try again.";
        if (!mounted) return;
        setState(() {
          showError = true;
          errorText = _friendlyError(msg);
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        showError = true;
        errorText = _friendlyError(e.toString());
      });
    } finally {
      if (mounted && isWeb) setState(() => _webLoading = false);
    }
  }

  String _friendlyError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains("failed to fetch") ||
        lower.contains("clientexception") ||
        lower.contains("socketexception") ||
        lower.contains("network") ||
        lower.contains("connection")) {
      return "Network error. Please check your internet connection and try again.";
    }
    // NOTE: reset-send-otp no longer reveals whether an address is registered
    // (anti-enumeration, audit 2026-08-23), so this branch is effectively dead.
    // Kept defensively, but it must NOT assert non-registration — that would
    // reintroduce the oracle in the UI.
    if (lower.contains("not registered") || lower.contains("not found")) {
      return "We couldn't send a code. Please check the address and try again.";
    }
    if (lower.contains("too many") || lower.contains("rate limit")) {
      return "Too many attempts. Please wait a moment and try again.";
    }
    if (raw.length < 120 && !raw.contains("uri=") && !raw.contains("://")) {
      return raw;
    }
    return "Something went wrong. Please try again.";
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return _webScaffold(context);
    return _mobileScaffold(context);
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  MOBILE — MobileFormShell replaces buggy isKeyboardOpen scroll pattern
  //           Logo clamped so it doesn't balloon on tablets
  // ══════════════════════════════════════════════════════════════════════════
  Widget _mobileScaffold(BuildContext context) {
    final w = uiScaleWidth(context);

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
                    children: [
                      const SizedBox(height: 30),

                      Image.asset(
                        "assets/images/applogocrop.webp",
                        width: (w * 0.50).clamp(0.0, 220.0).toDouble(),
                      ),

                      const SizedBox(height: 14),

                      Text(
                        "Reset Password",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryBlue,
                        ),
                      ),

                      const SizedBox(height: 6),

                      Text(
                        "Enter your email address to receive a\nverification code.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),

                      const SizedBox(height: 22),

                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: 58,
                            child: TextField(
                              keyboardType: TextInputType.emailAddress,
                              onChanged: (val) {
                                setState(() {
                                  email = val;
                                  showError = false;
                                  errorText = "";
                                });
                              },
                              decoration: InputDecoration(
                                hintText: "Email Address",
                                prefixIcon: Icon(
                                  Icons.email,
                                  color: showError
                                      ? Colors.red
                                      : AppColors.primaryBlue,
                                ),
                                filled: true,
                                fillColor: Colors.white,
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 18,
                                  horizontal: 16,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                    color: showError
                                        ? Colors.red
                                        : Colors.grey.shade300,
                                    width: 1.2,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                    color: showError
                                        ? Colors.red
                                        : AppColors.primaryBlue,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (showError)
                            Padding(
                              padding: const EdgeInsets.only(left: 8, top: 6),
                              child: Text(
                                errorText,
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        ],
                      ),

                      const SizedBox(height: 18),

                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryBlue,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: email.trim().isNotEmpty
                              ? () async {
                                  setState(() {
                                    showError = false;
                                    errorText = "";
                                  });

                                  final result = await Navigator.push(
                                    context,
                                    PageRouteBuilder(
                                      transitionDuration: Duration.zero,
                                      reverseTransitionDuration: Duration.zero,
                                      pageBuilder: (_, _, _) => OtpLoadingScreen(
                                        type: "email",
                                        onSendOtp: () async {
                                          final response = await http.post(
                                            Uri.parse(
                                              "https://vxvflhjbafqwehuxnmeq.supabase.co/functions/v1/reset-send-otp",
                                            ),
                                            headers: {
                                              "Content-Type":
                                                  "application/json",
                                              "apikey": "sb_publishable_ZBDaQPQdFyC5kOHGbce9Ig_zdtIi6Mo",
                                              "Authorization":
                                                  "Bearer sb_publishable_ZBDaQPQdFyC5kOHGbce9Ig_zdtIi6Mo",
                                            },
                                            body: jsonEncode({
                                              "email": email.trim(),
                                            }),
                                          );
                                          final data = jsonDecode(
                                            response.body,
                                          );
                                          if (response.statusCode != 200 ||
                                              !(data["success"] ?? false)) {
                                            throw (data["message"] ??
                                                    "Couldn't send the code. Please try again.")
                                                .toString();
                                          }
                                        },
                                      ),
                                    ),
                                  );

                                  if (!context.mounted) return;

                                  if (result != null &&
                                      result["success"] == true) {
                                    Navigator.push(
                                      context,
                                      PageRouteBuilder(
                                        transitionDuration: Duration.zero,
                                        reverseTransitionDuration:
                                            Duration.zero,
                                        pageBuilder: (_, _, _) =>
                                            ResetPasswordEmailVerifyScreen(
                                              email: email.trim(),
                                              onVerifiedSuccess: () {},
                                              onTermsClick: () {},
                                              onConditionsClick: () {},
                                            ),
                                      ),
                                    );
                                  } else {
                                    if (!mounted) return;
                                    setState(() {
                                      showError = true;
                                      errorText =
                                          result?["error"] ??
                                          "Couldn't send the code. Please try again.";
                                    });
                                  }
                                }
                              : null,
                          child: const Text(
                            "Verify Email",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),

                      Text(
                        "We will send you a verification code via Email",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),

                      const SizedBox(height: 26),

                      Row(
                        children: [
                          Expanded(child: Divider(color: Colors.grey.shade300)),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              "Or Return to",
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                          Expanded(child: Divider(color: Colors.grey.shade300)),
                        ],
                      ),

                      const SizedBox(height: 16),

                      SizedBox(
                        height: 56,
                        width: 170,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.grey.shade300),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: widget.onLogin,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Image.asset(
                                "assets/images/out.webp",
                                width: 20,
                                height: 20,
                                color: AppColors.primaryBlue,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                "Log In",
                                style: TextStyle(
                                  color: AppColors.primaryBlue,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
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

  // ══════════════════════════════════════════════════════════════════════════
  //  WEB — already on kit, unchanged
  // ══════════════════════════════════════════════════════════════════════════
  Widget _webScaffold(BuildContext context) {
    return WebAuthScaffold(
      heroController: _heroController,
      headline: "Reset your\npassword.",
      subtitle:
          "Enter your email and we'll send\na verification code your way.",
      card: WebAuthCard(
        children: [
          const WebCardHeader(
            title: "Reset password",
            subtitle:
                "Enter your email address to receive a verification code.",
          ),
          const SizedBox(height: 28),
          WebInputField(
            hint: "Email address",
            icon: Icons.email_outlined,
            isError: showError,
            keyboardType: TextInputType.emailAddress,
            onChanged: (val) => setState(() {
              email = val;
              showError = false;
              errorText = "";
            }),
          ),
          if (showError) WebFieldError(text: errorText),
          const SizedBox(height: 20),
          WebPrimaryButton(
            label: "Send verification code",
            loading: _webLoading,
            onPressed: email.trim().isNotEmpty
                ? () async {
                    setState(() {
                      showError = false;
                      errorText = "";
                    });
                    await _sendOtp(isWeb: true);
                  }
                : null,
          ),
          const SizedBox(height: 10),
          const WebCaption("We'll send a 6-digit code to your email."),
          const SizedBox(height: 24),
          WebOutlinedButton(
            icon: Icons.arrow_back_rounded,
            label: "Back to sign in",
            onTap: widget.onLogin,
          ),
        ],
      ),
    );
  }
}
