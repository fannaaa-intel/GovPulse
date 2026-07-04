import 'package:flutter/material.dart';

import '../theme/admin_ui.dart';
import 'admin_account_chip.dart';
import 'admin_notifications.dart';

class AdminTopBar extends StatelessWidget {
  final String title;
  final bool showMenuButton;
  final VoidCallback? onMenuTap;
  final VoidCallback onLogout;

  const AdminTopBar({
    super.key,
    required this.title,
    required this.showMenuButton,
    this.onMenuTap,
    required this.onLogout,
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
          AdminAccountChip(showName: showName, onLogout: onLogout),
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

