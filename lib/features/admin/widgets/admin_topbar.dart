import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../theme/admin_ui.dart';
import 'admin_notifications.dart';

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
    final width = MediaQuery.of(context).size.width;
    final showSearch = width >= 720;
    final showName = width >= 560;

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: AdminUi.surface,
        border: Border(bottom: BorderSide(color: AdminUi.border, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Color(0x080F1E40),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          if (showMenuButton) ...[
            _IconCircle(icon: Icons.menu_rounded, onTap: onMenuTap),
            const SizedBox(width: 12),
          ],
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AdminUi.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          const Spacer(),
          if (showSearch) ...[_SearchField(), const SizedBox(width: 12)],
          const AdminNotificationBell(),
          const SizedBox(width: 10),
          _AvatarChip(showName: showName),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      width: 220,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AdminUi.subtle,
        borderRadius: BorderRadius.circular(AdminUi.controlRadius),
        border: Border.all(color: AdminUi.border),
      ),
      child: const Row(
        children: [
          Icon(Icons.search_rounded, size: 16, color: AdminUi.textMuted),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Search…',
              style: TextStyle(fontSize: 13, color: AdminUi.textMuted),
            ),
          ),
          Text(
            '⌘K',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AdminUi.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _IconCircle extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _IconCircle({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 22, color: AdminUi.textSecondary),
        ),
      ),
    );
  }
}

class _AvatarChip extends StatelessWidget {
  final bool showName;
  const _AvatarChip({required this.showName});

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Center(
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
              if (showName) ...[
                const SizedBox(width: 8),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Administrator',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AdminUi.textPrimary,
                      ),
                    ),
                    Text(
                      'LGU Aparri',
                      style: TextStyle(fontSize: 11, color: AdminUi.textMuted),
                    ),
                  ],
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: AdminUi.textMuted,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
