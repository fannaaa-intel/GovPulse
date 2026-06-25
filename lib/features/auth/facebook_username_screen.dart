import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:async';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/inputs/rounded_input_field.dart';
import '../../core/widgets/mobile_form_shell.dart';
import '../../core/widgets/web/web.dart';
import '../../core/services/auth_service.dart';

/// Shown right after a successful Facebook sign-in.
/// The user picks a username before entering the app.
///
/// [facebookName]  — pre-filled suggestion derived from their Facebook name.
/// [onComplete]    — called with the chosen username once saved.
/// [onCancel]      — called if the user cancels / backs out.
class FacebookUsernameScreen extends StatefulWidget {
  final String? facebookName;
  final Future<void> Function(String username) onComplete;
  final VoidCallback onCancel;

  const FacebookUsernameScreen({
    super.key,
    this.facebookName,
    required this.onComplete,
    required this.onCancel,
  });

  @override
  State<FacebookUsernameScreen> createState() => _FacebookUsernameScreenState();
}

class _FacebookUsernameScreenState extends State<FacebookUsernameScreen>
    with TickerProviderStateMixin {
  late final TextEditingController _usernameController;

  String username = '';
  String? usernameErrorText;
  bool isCheckingUsername = false;
  bool isSubmitting = false;

  Timer? _debounce;

  // ── Entrance animation (matches signup_screen pattern) ────────────────────
  late final AnimationController _entranceController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;
  late final AnimationController _bgController;

  @override
  void initState() {
    super.initState();

    // Pre-fill with a sanitised version of their Facebook name, e.g.
    // "Juan Dela Cruz" → "juan_dela_cruz"
    final suggestion = _sanitise(widget.facebookName ?? '');
    _usernameController = TextEditingController(text: suggestion);
    username = suggestion;

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

    // Validate the pre-filled suggestion immediately
    if (suggestion.isNotEmpty) {
      _onUsernameChanged(suggestion);
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _debounce?.cancel();
    _entranceController.dispose();
    _bgController.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Lowercase, replace spaces with underscores, strip everything else.
  String _sanitise(String raw) {
    return raw
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'[^a-z0-9_]'), '')
        .substring(0, raw.length.clamp(0, 30));
  }

  bool get canSubmit =>
      username.isNotEmpty &&
      usernameErrorText == null &&
      !isCheckingUsername &&
      !isSubmitting;

  void _onUsernameChanged(String val) {
    setState(() {
      username = val;
      usernameErrorText = null;
    });

    if (_debounce?.isActive ?? false) _debounce!.cancel();

    if (val.isEmpty) return;

    setState(() => isCheckingUsername = true);

    _debounce = Timer(const Duration(milliseconds: 600), () async {
      final exists = await AuthService.checkUsernameExists(val);
      if (!mounted) return;
      // Guard against stale debounce firing after the user kept typing
      if (val != _usernameController.text) return;
      setState(() {
        isCheckingUsername = false;
        usernameErrorText = exists ? 'Username is already taken' : null;
      });
    });
  }

  Future<void> _submit() async {
    if (!canSubmit) return;
    setState(() => isSubmitting = true);
    try {
      await widget.onComplete(username.trim());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isSubmitting = false;
        usernameErrorText = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    if (!kIsWeb) return _mobileScaffold(context);
    if (width >= kWebTwoPanelMinWidth) return _webScaffold(context);
    return _webCompactScaffold(context);
  }

  // ── Mobile ────────────────────────────────────────────────────────────────

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
                        'assets/images/applogocrop.webp',
                        width: (MediaQuery.of(context).size.width * 0.30)
                            .clamp(0.0, 150.0)
                            .toDouble(),
                      ),

                      const SizedBox(height: 10),

                      Text(
                        'Almost there!',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryBlue,
                        ),
                      ),

                      const SizedBox(height: 6),

                      Text(
                        'Choose a username for your GovPulse account.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: AppColors.hint),
                      ),

                      const SizedBox(height: 24),

                      // Facebook badge
                      _facebookBadge(),

                      const SizedBox(height: 24),

                      // Username field
                      RoundedInputField(
                        controller: _usernameController,
                        value: username,
                        hintText: 'Username',
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

                      const SizedBox(height: 24),

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
                          child: isSubmitting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Text(
                                  'Continue',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: AppColors.stroke),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: isSubmitting ? null : widget.onCancel,
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: AppColors.hint,
                            ),
                          ),
                        ),
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

  // ── Web — wide ────────────────────────────────────────────────────────────

  Widget _webScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: kHeroBgBottom,
      body: Row(
        children: [
          Expanded(
            flex: 56,
            child: WebHeroPanel(
              bgController: _bgController,
              headline: 'One last\nstep.',
              subtitle:
                  'Pick a username for your GovPulse account\nand you\'re all set.',
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

  // ── Web — compact ─────────────────────────────────────────────────────────

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

  // ── Web form content (shared by wide + compact) ───────────────────────────

  Widget _webFormContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Image.asset('assets/images/applogo.webp', height: 30),
            const SizedBox(width: 10),
            Text(
              'GovPulse',
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
          'Almost there!',
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
          'Choose a username for your GovPulse account.',
          style: TextStyle(fontSize: 14, color: AppColors.hint, height: 1.5),
        ),

        const SizedBox(height: 28),

        _facebookBadge(),

        const SizedBox(height: 28),

        WebInputField(
          hint: 'Username',
          icon: Icons.person_outline_rounded,
          keyboardType: TextInputType.text,
          controller: _usernameController,
          isError: usernameErrorText != null,
          textInputAction: TextInputAction.done,
          onChanged: _onUsernameChanged,
          onSubmitted: (_) => _submit(),
          suffix: isCheckingUsername
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
        ),
        WebFieldError(text: usernameErrorText),

        const SizedBox(height: 28),

        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
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
            ),
            onPressed: canSubmit ? _submit : null,
            child: isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : const Text(
                    'Continue',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      letterSpacing: 0.1,
                    ),
                  ),
          ),
        ),

        const SizedBox(height: 16),

        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppColors.stroke),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: isSubmitting ? null : widget.onCancel,
            child: Text(
              'Cancel',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.hint,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Shared widgets ────────────────────────────────────────────────────────

  /// Small pill showing the user they connected via Facebook.
  Widget _facebookBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFE7F0FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBFD4FA)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Facebook "f" logo colour
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFF1877F2),
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.facebook, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Text(
            'Connected with Facebook',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.primaryBlue,
            ),
          ),
        ],
      ),
    );
  }
}
