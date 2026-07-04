import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../screens/admin_dashboard_screen.dart';
import '../theme/admin_ui.dart';
import 'admin_account_chip.dart';

class AdminSidebar extends StatelessWidget {
  final List<AdminNavItem> items;
  final int selectedIndex;
  final bool collapsed;
  final void Function(int) onItemTap;
  final VoidCallback onLogout;

  const AdminSidebar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.collapsed,
    required this.onItemTap,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      width: collapsed ? 72 : 244,
      decoration: const BoxDecoration(
        color: AdminUi.surface,
        border: Border(right: BorderSide(color: AdminUi.border, width: 1)),
      ),
      // The rail's WIDTH animates (72 ↔ 244) but `collapsed` flips instantly, so
      // for the frames mid-animation the expanded content (labels, the wordmark,
      // "Logout") would render while the rail is still narrow → RenderFlex
      // overflow. Deriving the content state from the live width keeps it
      // icon-only until there's genuinely room for labels.
      child: LayoutBuilder(
        builder: (context, c) {
          final showCollapsed = collapsed || c.maxWidth < 220;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLogo(showCollapsed),
              const SizedBox(height: 6),
              Expanded(
                child: ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  itemCount: items.length,
                  itemBuilder: (ctx, i) => _NavTile(
                    item: items[i],
                    selected: i == selectedIndex,
                    collapsed: showCollapsed,
                    onTap: () => onItemTap(i),
                  ),
                ),
              ),
              const Divider(height: 1, color: AdminUi.border),
              _buildFooter(showCollapsed),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLogo(bool collapsed) {
    return Container(
      height: 64,
      padding: EdgeInsets.symmetric(horizontal: collapsed ? 16 : 20),
      alignment: collapsed ? Alignment.center : Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset('assets/images/applogo.webp', height: 30, width: 30),
          if (!collapsed) ...[
            const SizedBox(width: 10),
            const Text(
              'GovPulse',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryBlue,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Admin',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryBlue,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFooter(bool collapsed) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Align(
              alignment: collapsed ? Alignment.center : Alignment.centerLeft,
              child: AdminAccountChip(
                showName: !collapsed,
                interactive: false,
                onLogout: onLogout,
              ),
            ),
          ),
          _LogoutTile(collapsed: collapsed, onLogout: onLogout),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final AdminNavItem item;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  const _NavTile({
    required this.item,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      margin: const EdgeInsets.only(bottom: 2),
      padding: EdgeInsets.symmetric(
        horizontal: collapsed ? 0 : 12,
        vertical: 11,
      ),
      decoration: BoxDecoration(
        color: selected
            ? AppColors.primaryBlue.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: collapsed
            ? MainAxisAlignment.center
            : MainAxisAlignment.start,
        children: [
          Icon(
            item.icon,
            size: 20,
            color: selected ? AppColors.primaryBlue : const Color(0xFF8A94A6),
          ),
          if (!collapsed) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected
                      ? AppColors.primaryBlue
                      : const Color(0xFF4B5563),
                ),
              ),
            ),
          ],
        ],
      ),
    );

    // Left active-indicator bar + hover, the hallmark of a web admin nav.
    return Tooltip(
      message: collapsed ? item.label : '',
      preferBelow: false,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            children: [
              content,
              if (selected)
                Positioned(
                  left: 0,
                  top: 8,
                  bottom: 8,
                  child: Container(
                    width: 3,
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LogoutTile extends StatelessWidget {
  final bool collapsed;
  final VoidCallback onLogout;
  const _LogoutTile({required this.collapsed, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: collapsed ? 'Logout' : '',
      preferBelow: false,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onLogout,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: collapsed ? 0 : 12,
              vertical: 11,
            ),
            child: Row(
              mainAxisAlignment: collapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                const Icon(
                  Icons.logout_rounded,
                  size: 20,
                  color: Color(0xFFEF4444),
                ),
                if (!collapsed) ...[
                  const SizedBox(width: 12),
                  const Text(
                    'Logout',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFEF4444),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
