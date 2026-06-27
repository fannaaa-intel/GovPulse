import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../theme/admin_ui.dart';

class AdminTopBar extends StatelessWidget {
  final String title;
  final bool showMenuButton;
  final VoidCallback? onMenuTap;

  const AdminTopBar({
    super.key,
    required this.title,
    required this.showMenuButton,
    this.onMenuTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AdminUi.border, width: 1)),
      ),
      child: Row(
        children: [
          if (showMenuButton) ...[
            GestureDetector(
              onTap: onMenuTap,
              child: Icon(
                Icons.menu_rounded,
                size: 22,
                color: const Color(0xFF4B5563),
              ),
            ),
            const SizedBox(width: 16),
          ],
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF111827),
              letterSpacing: -0.3,
            ),
          ),
          const Spacer(),
          // Search
          Container(
            height: 36,
            width: 200,
            decoration: BoxDecoration(
              color: const Color(0xFFF4F6FB),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AdminUi.border),
            ),
            child: Row(
              children: [
                const SizedBox(width: 10),
                Icon(
                  Icons.search_rounded,
                  size: 16,
                  color: const Color(0xFF8A94A6),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Search...',
                  style: TextStyle(fontSize: 13, color: Color(0xFF8A94A6)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Notification bell
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_none_rounded, size: 22),
                color: const Color(0xFF4B5563),
                onPressed: () {},
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppColors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
          // Admin avatar
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                'A',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryBlue,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
