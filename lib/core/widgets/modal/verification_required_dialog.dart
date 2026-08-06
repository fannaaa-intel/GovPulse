import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../router/legacy_nav.dart';
import '../../theme/app_colors.dart';

Future<bool> showVerificationRequiredDialog(
  BuildContext context, {
  String message =
      'Only verified citizens can access this feature. Please complete the identity verification process first.',
  bool? isVerified,
  String? username,
}) async {
  // Cap the effective width so relative sizing stays phone-scaled and the
  // dialog doesn't stretch too wide on web/desktop (mirrors app_snackbar.dart).
  const maxDialogWidth = 440.0;
  final width = math.min(MediaQuery.of(context).size.width, maxDialogWidth);

  // ── If caller knows the status, use it directly ───────────────────────────
  if (isVerified != null) {
    if (isVerified) return true;
  } else {
    // ── No status passed — check Supabase silently (no spinner) ──────────
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user != null) {
        final verifRow = await supabase
            .from('verification_submissions')
            .select('status')
            .eq('user_id', user.id)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
        final verified = (verifRow?['status'] as String?) == 'approved';
        if (verified) return true;
      }
    } catch (_) {
      return false;
    }
  }

  if (!context.mounted) return false;

  // ── Show dialog ───────────────────────────────────────────────────────────
  await showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: '',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 180),
    transitionBuilder: (ctx, anim, _, child) {
      final curve = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curve,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.06),
            end: Offset.zero,
          ).animate(curve),
          child: child,
        ),
      );
    },
    pageBuilder: (ctx, _, _) => Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(width * 0.06),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxDialogWidth),
        child: Padding(
          padding: EdgeInsets.all(width * 0.06),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: width * 0.22,
                height: width * 0.22,
                child: Center(
                  child: Image.asset(
                    'assets/images/verification/verified.webp',
                    width: width * 0.18,
                    height: width * 0.18,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              SizedBox(height: width * 0.045),
              Text(
                'Verification Required',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: width * 0.052,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1F2937),
                ),
              ),
              SizedBox(height: width * 0.022),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: width * 0.034,
                  color: AppColors.hint,
                  height: 1.55,
                ),
              ),
              SizedBox(height: width * 0.055),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF1F2937),
                        side: BorderSide(
                          color: AppColors.hint.withValues(alpha: 0.4),
                        ),
                        padding: EdgeInsets.symmetric(vertical: width * 0.042),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(width * 0.03),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: width * 0.04,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: width * 0.035),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        // Close the dialog first, then route — popping after
                        // pushing would tear down the verification screen.
                        final navigator = Navigator.of(ctx);
                        navigator.pop();
                        if (username != null) {
                          pushLegacyOn(
                            navigator,
                            '/verification',
                            arguments: username,
                          );
                        } else {
                          debugPrint(
                            'showVerificationRequiredDialog: username was null; '
                            'cannot navigate to /verification. Caller must pass '
                            'username:.',
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        elevation: 0,
                        padding: EdgeInsets.symmetric(vertical: width * 0.042),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(width * 0.03),
                        ),
                      ),
                      child: Text(
                        'Verify',
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: width * 0.04,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );

  return false;
}

Future<void> showSuccessDialog(
  BuildContext context, {
  required String title,
  required String message,
  String buttonLabel = 'Done',
  String iconAsset = 'assets/images/verification/verified.webp',
  IconData? iconData,
  Color? iconColor,
  Color? iconBgColor,
}) async {
  final width = MediaQuery.of(context).size.width;

  await showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierLabel: '',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 320),
    transitionBuilder: (ctx, anim, _, child) {
      final curve = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curve,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.08),
            end: Offset.zero,
          ).animate(curve),
          child: child,
        ),
      );
    },
    pageBuilder: (ctx, _, _) => Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(width * 0.06),
      ),
      child: Padding(
        padding: EdgeInsets.all(width * 0.06),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Icon with optional tinted circle background ──────────────
            () {
              final size = width * 0.22;
              final bg =
                  iconBgColor ??
                  (iconColor != null
                      ? iconColor.withValues(alpha: 0.12)
                      : const Color(0xFFE7F0FF));

              // ── Flutter IconData (no asset needed) ───────────────────
              if (iconData != null) {
                return Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                  child: Center(
                    child: Icon(
                      iconData,
                      size: size * 0.55,
                      color: iconColor ?? AppColors.primaryBlue,
                    ),
                  ),
                );
              }

              if (iconColor != null) {
                return Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                  child: Center(
                    child: Image.asset(
                      iconAsset,
                      width: size * 0.55,
                      height: size * 0.55,
                      fit: BoxFit.contain,
                      color: iconColor,
                      colorBlendMode: BlendMode.srcIn,
                      errorBuilder: (_, _, _) => Icon(
                        Icons.check_circle_outline_rounded,
                        size: size * 0.55,
                        color: iconColor,
                      ),
                    ),
                  ),
                );
              }
              // No color — render as-is (for full-color PNGs like verified.webp)
              return SizedBox(
                width: size,
                height: size,
                child: Center(
                  child: Image.asset(
                    iconAsset,
                    width: size * 0.82,
                    height: size * 0.82,
                    fit: BoxFit.contain,
                  ),
                ),
              );
            }(),
            SizedBox(height: width * 0.045),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: width * 0.052,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1F2937),
              ),
            ),
            SizedBox(height: width * 0.022),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: width * 0.034,
                color: AppColors.hint,
                height: 1.55,
              ),
            ),
            SizedBox(height: width * 0.055),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  elevation: 0,
                  padding: EdgeInsets.symmetric(vertical: width * 0.042),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(width * 0.03),
                  ),
                ),
                child: Text(
                  buttonLabel,
                  style: TextStyle(
                    fontSize: width * 0.04,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
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

/// Reusable error dialog — same look as [showSuccessDialog], with a red
/// error icon. Use this everywhere for surfacing errors (no SnackBars).
Future<void> showErrorDialog(
  BuildContext context, {
  String title = 'Something went wrong',
  required String message,
  String buttonLabel = 'OK',
}) {
  return showSuccessDialog(
    context,
    title: title,
    message: message,
    buttonLabel: buttonLabel,
    iconData: Icons.error_outline_rounded,
    iconColor: AppColors.red,
  );
}
