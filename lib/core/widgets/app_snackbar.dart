import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Semantic kind of a toast — drives its colour + icon.
enum AppSnackType { success, error, info }

/// App-wide SnackBar that always appears at the **top** of the screen, coloured
/// from the shared palette (green / red / blue). Used by both the citizen app
/// and the admin console so toasts look and behave identically everywhere.
///
/// Flutter has no native top placement, so a floating SnackBar is pushed up
/// with a near-full-height bottom margin, landing just under the status bar.
/// On wide screens (tablet / web) it's centred and capped so it stays a
/// comfortable phone width instead of stretching edge to edge.
void showAppSnackBar(
  BuildContext context,
  String message, {
  AppSnackType type = AppSnackType.info,
}) {
  final (Color bg, IconData icon) = switch (type) {
    AppSnackType.success => (AppColors.green, Icons.check_circle_rounded),
    AppSnackType.error => (AppColors.red, Icons.error_outline_rounded),
    AppSnackType.info => (AppColors.primaryBlue, Icons.info_outline_rounded),
  };

  final media = MediaQuery.of(context);
  final screenW = media.size.width;

  // Cap the width on wide screens so it reads as a phone-sized toast; hug the
  // edges (16px) on phones.
  const maxWidth = 460.0;
  final side = screenW > maxWidth + 32 ? (screenW - maxWidth) / 2 : 16.0;

  // Bottom margin ≈ full height pushes the floating bar to the top; the clamp
  // keeps it on-screen on very short windows.
  final bottomMargin =
      (media.size.height - media.padding.top - 96).clamp(0.0, double.infinity);

  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        elevation: 6,
        margin: EdgeInsets.only(left: side, right: side, bottom: bottomMargin),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
}
