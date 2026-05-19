import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';

/// Small grey pill at the top of every bottom sheet.
Widget dragHandle(double width) => Container(
  margin: EdgeInsets.only(bottom: width * 0.025),
  width: width * 0.12,
  height: width * 0.012,
  decoration: BoxDecoration(
    color: const Color(0xFFD1D5DB),
    borderRadius: BorderRadius.circular(width * 0.006),
  ),
);

String formatTimeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 60) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m Ago';
  if (diff.inHours < 24) return '${diff.inHours}h Ago';
  if (diff.inDays < 7) return '${diff.inDays}d Ago';
  if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w Ago';
  if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo Ago';
  return '${(diff.inDays / 365).floor()}y Ago';
}

Widget buildImagePlaceholder(double width) => Container(
  color: const Color(0xFFE5E7EB),
  alignment: Alignment.center,
  child: Icon(
    Icons.image_outlined,
    size: width * 0.08,
    color: const Color(0xFF9CA3AF),
  ),
);

/// Circular avatar for comments and replies.
Widget buildAvatar(double size, String? photoUrl) {
  return Container(
    width: size,
    height: size,
    decoration: const BoxDecoration(
      shape: BoxShape.circle,
      color: Color(0xFFE5E7EB),
    ),
    clipBehavior: Clip.antiAlias,
    child: (photoUrl != null && photoUrl.isNotEmpty)
        ? Image.network(
            photoUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Icon(
              Icons.person_rounded,
              size: size * 0.6,
              color: const Color(0xFF9CA3AF),
            ),
          )
        : Icon(
            Icons.person_rounded,
            size: size * 0.6,
            color: const Color(0xFF9CA3AF),
          ),
  );
}

/// Post-author avatar (green border, citizen photo or institution fallback).
Widget buildAuthorAvatar(double size, String? photoUrl) {
  if (photoUrl != null && photoUrl.isNotEmpty) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.green, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.network(
        photoUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          color: AppColors.green.withValues(alpha: 0.12),
          child: Icon(
            Icons.account_balance_rounded,
            size: size * 0.5,
            color: AppColors.green,
          ),
        ),
      ),
    );
  }
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: AppColors.green.withValues(alpha: 0.12),
      border: Border.all(color: AppColors.green, width: 1.5),
    ),
    child: Icon(
      Icons.account_balance_rounded,
      size: size * 0.5,
      color: AppColors.green,
    ),
  );
}
