import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_colors.dart';

Future<bool> showVerificationRequiredDialog(
  BuildContext context, {
  String message =
      'Only verified citizens can access this feature. Please complete the identity verification process first.',
  bool? isVerified,
}) async {
  final width = MediaQuery.of(context).size.width;

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
            SizedBox(
              width: width * 0.22,
              height: width * 0.22,
              child: Center(
                child: Image.asset(
                  'assets/images/verification/verified.png',
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
                  'Got it',
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

  return false;
}
