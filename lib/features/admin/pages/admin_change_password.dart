import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../theme/admin_ui.dart';
import '../widgets/admin_dialog_back.dart';
import '../widgets/admin_snackbar.dart';
import '../../../core/widgets/app_dialog.dart';

/// Dedicated admin change-password flow (send code → verify → new password),
/// styled for the console. Responsive: centred dialog on web/desktop/tablet
/// (≥ 900px), full-screen page on phones. Reuses the same Supabase edge
/// functions + RPCs as the citizen flow via `functions.invoke`.
void showAdminChangePassword(BuildContext context) {
  final wide = MediaQuery.of(context).size.width >= 900;
  if (wide) {
    showAppDialog(
      context: context,
      barrierColor: Colors.black54,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460, maxHeight: 640),
          child: const _AdminChangePasswordFlow(fullScreen: false),
        ),
      ),
    );
  } else {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const Scaffold(
          backgroundColor: AdminUi.surface,
          body: SafeArea(child: _AdminChangePasswordFlow(fullScreen: true)),
        ),
      ),
    );
  }
}

enum _Step { send, verify, newPassword }

class _AdminChangePasswordFlow extends StatefulWidget {
  final bool fullScreen;
  const _AdminChangePasswordFlow({required this.fullScreen});

  @override
  State<_AdminChangePasswordFlow> createState() =>
      _AdminChangePasswordFlowState();
}

class _AdminChangePasswordFlowState extends State<_AdminChangePasswordFlow> {
  SupabaseClient get _sb => Supabase.instance.client;
  String get _email => _sb.auth.currentUser?.email ?? '';

  _Step _step = _Step.send;
  bool _busy = false;
  String? _error;

  // ── Step 2: OTP ────────────────────────────────────────────────────────────
  final _codeCtrl = TextEditingController();
  Timer? _timer;
  int _secondsLeft = 0;
  String? _refreshToken;

  // ── Step 3: new password ─────────────────────────────────────────────────
  final _pwCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _showPw = false;
  bool _showConfirm = false;

  @override
  void dispose() {
    _timer?.cancel();
    _codeCtrl.dispose();
    _pwCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _secondsLeft = 58);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_secondsLeft <= 0) {
        t.cancel();
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  Future<void> _sendCode() async {
    if (_busy || _email.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await _sb.functions.invoke(
        'reset-send-otp',
        body: {'email': _email.trim()},
      );
      final data = (res.data is Map) ? res.data as Map : const {};
      if (res.status == 200 && (data['success'] ?? false) == true) {
        _codeCtrl.clear();
        _startCountdown();
        setState(() => _step = _Step.verify);
      } else {
        setState(() => _error =
            (data['message'] ?? data['error'] ?? 'Failed to send code.')
                .toString());
      }
    } catch (_) {
      setState(() => _error = 'Network error. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyCode() async {
    final code = _codeCtrl.text.trim();
    if (_busy || code.length != 6) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final can = await _sb.rpc(
        'can_verify_otp',
        params: {'p_identifier': _email},
      );
      if (can is Map && can['allowed'] != true) {
        setState(() => _error = (can['message'] ?? 'Too many attempts.').toString());
        return;
      }
      final res = await _sb.functions.invoke(
        'reset-verify-otp',
        body: {'email': _email, 'code': code},
      );
      final data = (res.data is Map) ? res.data as Map : const {};
      if (res.status == 200 && data['success'] == true) {
        await _sb.rpc('clear_otp_failures', params: {'p_identifier': _email});
        final session = data['session'] as Map;
        _refreshToken = session['refresh_token'] as String;
        setState(() => _step = _Step.newPassword);
      } else {
        await _sb.rpc('record_otp_failure', params: {'p_identifier': _email});
        setState(() => _error = 'Incorrect or expired code. Please try again.');
      }
    } catch (_) {
      setState(() => _error = 'Could not verify the code. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _savePassword() async {
    if (_busy) return;
    final pw = _pwCtrl.text.trim();
    final rules = _PwRules(pw);
    if (!rules.allValid) {
      setState(() => _error = 'Please meet all password requirements.');
      return;
    }
    if (pw != _confirmCtrl.text.trim()) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_refreshToken != null) {
        await _sb.auth.setSession(_refreshToken!);
      }
      final res = await _sb.auth.updateUser(UserAttributes(password: pw));
      if (res.user == null) throw 'update-failed';
      if (!mounted) return;
      Navigator.pop(context);
      showAdminSnackBar(context, 'Password changed successfully.',
          type: AdminSnackType.success);
    } catch (_) {
      setState(() {
        _busy = false;
        _error = 'Could not update the password. Please try again.';
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final content = switch (_step) {
      _Step.send => _sendStep(),
      _Step.verify => _verifyStep(),
      _Step.newPassword => _newPasswordStep(),
    };

    return Material(
      color: AdminUi.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: widget.fullScreen ? MainAxisSize.max : MainAxisSize.min,
        children: [
          _header(),
          const Divider(height: 1, color: AdminUi.border),
          Flexible(
            child: LayoutBuilder(
              builder: (context, c) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: ConstrainedBox(
                  // On the full-screen phone layout, centre the (short) content
                  // vertically instead of clustering it at the top.
                  constraints: BoxConstraints(
                    minHeight: widget.fullScreen ? c.maxHeight - 40 : 0,
                  ),
                  child: Center(child: content),
                ),
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      size: 15, color: AppColors.red),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(fontSize: 12, color: AppColors.red),
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 1, color: AdminUi.border),
          _footer(),
        ],
      ),
    );
  }

  Widget _header() {
    final titles = {
      _Step.send: 'Change password',
      _Step.verify: 'Enter code',
      _Step.newPassword: 'New password',
    };
    return Padding(
      padding: EdgeInsets.fromLTRB(widget.fullScreen ? 12 : 18, 12, 8, 12),
      child: Row(
        children: [
          // Phone: back chevron on the left. Web/desktop: X on the right.
          if (widget.fullScreen) ...[
            AdminDialogBack(onTap: () => Navigator.pop(context)),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              titles[_step]!,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AdminUi.textPrimary,
              ),
            ),
          ),
          _StepDots(step: _step),
          if (!widget.fullScreen)
            IconButton(
              icon: const Icon(Icons.close_rounded, color: AdminUi.textMuted),
              onPressed: () => Navigator.pop(context),
            ),
        ],
      ),
    );
  }

  Widget _lockIcon() => Center(
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppColors.primaryBlue.withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.lock_outline_rounded,
              size: 34, color: AppColors.primaryBlue),
        ),
      );

  // ── Step 1 ──────────────────────────────────────────────────────────────────
  Widget _sendStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _lockIcon(),
        const SizedBox(height: 18),
        const Text(
          "We'll send a 6-digit verification code to your admin email.",
          style: TextStyle(fontSize: 13, color: AdminUi.textSecondary, height: 1.5),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: AdminUi.subtle,
            borderRadius: BorderRadius.circular(AdminUi.controlRadius),
            border: Border.all(color: AdminUi.border),
          ),
          child: Row(
            children: [
              const Icon(Icons.mail_outline_rounded,
                  size: 18, color: AdminUi.textMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _email.isEmpty ? '—' : _email,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AdminUi.textPrimary,
                  ),
                ),
              ),
              const Icon(Icons.lock_rounded, size: 15, color: AdminUi.textMuted),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  // ── Step 2 ──────────────────────────────────────────────────────────────────
  Widget _verifyStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Enter the 6-digit code sent to $_email.',
          style: const TextStyle(
            fontSize: 13,
            color: AdminUi.textSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _codeCtrl,
          keyboardType: TextInputType.number,
          maxLength: 6,
          autofocus: true,
          textAlign: TextAlign.center,
          onChanged: (_) => setState(() {}),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            letterSpacing: 12,
            color: AdminUi.textPrimary,
          ),
          decoration: InputDecoration(
            counterText: '',
            hintText: '••••••',
            hintStyle: const TextStyle(
              fontSize: 26,
              letterSpacing: 12,
              color: AdminUi.textMuted,
            ),
            filled: true,
            fillColor: AdminUi.subtle,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            border: _border(AdminUi.border),
            enabledBorder: _border(AdminUi.border),
            focusedBorder: _border(AppColors.primaryBlue),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: _secondsLeft > 0
              ? Text(
                  'Resend code in ${_secondsLeft}s',
                  style: const TextStyle(fontSize: 12, color: AdminUi.textMuted),
                )
              : TextButton(
                  onPressed: _busy ? null : _sendCode,
                  child: const Text('Resend code'),
                ),
        ),
      ],
    );
  }

  // ── Step 3 ──────────────────────────────────────────────────────────────────
  Widget _newPasswordStep() {
    final rules = _PwRules(_pwCtrl.text.trim());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Create a new password for your admin account.',
          style: TextStyle(fontSize: 13, color: AdminUi.textSecondary, height: 1.5),
        ),
        const SizedBox(height: 16),
        _pwField(
          _pwCtrl,
          'New password',
          _showPw,
          () => setState(() => _showPw = !_showPw),
        ),
        const SizedBox(height: 12),
        _pwField(
          _confirmCtrl,
          'Confirm password',
          _showConfirm,
          () => setState(() => _showConfirm = !_showConfirm),
        ),
        const SizedBox(height: 14),
        _rule('At least 8 characters', rules.minLength),
        _rule('One uppercase letter', rules.upper),
        _rule('One number', rules.number),
        _rule('One special character', rules.special),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _pwField(
    TextEditingController ctrl,
    String label,
    bool visible,
    VoidCallback toggle,
  ) {
    return TextField(
      controller: ctrl,
      obscureText: !visible,
      onChanged: (_) => setState(() {}),
      style: const TextStyle(fontSize: 13, color: AdminUi.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 13, color: AdminUi.textMuted),
        filled: true,
        fillColor: AdminUi.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        suffixIcon: IconButton(
          icon: Icon(
            visible ? Icons.visibility_off_rounded : Icons.visibility_rounded,
            size: 18,
            color: AdminUi.textMuted,
          ),
          onPressed: toggle,
        ),
        border: _border(AdminUi.border),
        enabledBorder: _border(AdminUi.border),
        focusedBorder: _border(AppColors.primaryBlue),
      ),
    );
  }

  Widget _rule(String label, bool ok) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.circle_outlined,
            size: 15,
            color: ok ? AppColors.green : AdminUi.textMuted,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: ok ? AdminUi.textSecondary : AdminUi.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer() {
    final (String label, VoidCallback? onTap) = switch (_step) {
      _Step.send => ('Send verification code', _busy ? null : _sendCode),
      _Step.verify => (
          'Verify code',
          (_busy || _codeCtrl.text.trim().length != 6) ? null : _verifyCode
        ),
      _Step.newPassword => ('Update password', _busy ? null : _savePassword),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: SizedBox(
        width: double.infinity,
        height: 54,
        child: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryBlue,
            disabledBackgroundColor: AppColors.primaryBlue.withValues(alpha: 0.45),
            foregroundColor: Colors.white,
            elevation: 2,
            shadowColor: AppColors.primaryBlue.withValues(alpha: 0.40),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: _busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.6,
                    color: Colors.white,
                  ),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
        ),
      ),
    );
  }

  static OutlineInputBorder _border(Color c) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(AdminUi.controlRadius),
        borderSide: BorderSide(color: c),
      );
}

class _StepDots extends StatelessWidget {
  final _Step step;
  const _StepDots({required this.step});

  @override
  Widget build(BuildContext context) {
    final index = _Step.values.indexOf(step);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < _Step.values.length; i++) ...[
          Container(
            width: i == index ? 18 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: i <= index ? AppColors.primaryBlue : AdminUi.border,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          if (i < _Step.values.length - 1) const SizedBox(width: 4),
        ],
      ],
    );
  }
}

class _PwRules {
  final bool minLength;
  final bool upper;
  final bool number;
  final bool special;
  _PwRules(String pw)
      : minLength = pw.length >= 8,
        upper = pw.contains(RegExp(r'[A-Z]')),
        number = pw.contains(RegExp(r'[0-9]')),
        special = pw.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>_\-]'));

  bool get allValid => minLength && upper && number && special;
}
