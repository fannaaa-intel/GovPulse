import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../pages/admin_change_password.dart';
import '../pages/admin_profile_editor.dart';
import '../providers/admin_profile_provider.dart';
import '../theme/admin_ui.dart';
import 'admin_skeleton.dart';

enum _AccountAction { editProfile, changePassword, logout }

/// The signed-in admin's avatar + name, shown in the topbar and the sidebar
/// footer. Tapping opens a menu: Edit profile · Change password · Log out.
/// Shows a shimmer while the profile is loading, and reflects updates live
/// (both placements watch the same [adminProfileProvider]).
class AdminAccountChip extends ConsumerWidget {
  final bool showName;
  final VoidCallback onLogout;

  /// When false the chip is a read-only identity display (no menu, no chevron)
  /// — used in the sidebar footer. The topbar uses the interactive version.
  final bool interactive;

  const AdminAccountChip({
    super.key,
    required this.showName,
    required this.onLogout,
    this.interactive = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminProfileProvider);

    // Interactive (topbar) shows the organisation; the static sidebar block
    // labels the account as "Administrator" so it clearly reads as the admin.
    return async.when(
      loading: () => _Skeleton(showName: showName),
      error: (_, _) => _Chip(
        interactive: interactive,
        showName: showName,
        onLogout: onLogout,
        name: 'Administrator',
        subtitle: interactive ? 'LGU Aparri' : 'Administrator',
        photoUrl: null,
        initials: 'A',
        email: '',
      ),
      data: (p) => _Chip(
        interactive: interactive,
        showName: showName,
        onLogout: onLogout,
        name: p.displayName,
        subtitle: interactive ? p.organization : 'Administrator',
        photoUrl: p.photoUrl,
        initials: p.initials,
        email: p.email,
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final bool interactive;
  final bool showName;
  final VoidCallback onLogout;
  final String name;
  final String subtitle;
  final String? photoUrl;
  final String initials;
  final String email;

  const _Chip({
    required this.interactive,
    required this.showName,
    required this.onLogout,
    required this.name,
    required this.subtitle,
    required this.photoUrl,
    required this.initials,
    required this.email,
  });

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Avatar(photoUrl: photoUrl, initials: initials),
          if (showName) ...[
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AdminUi.textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AdminUi.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (interactive) ...[
              const SizedBox(width: 4),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: AdminUi.textMuted,
              ),
            ],
          ],
        ],
      ),
    );

    if (!interactive) return content;

    return PopupMenuButton<_AccountAction>(
      tooltip: 'Account',
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (a) {
        switch (a) {
          case _AccountAction.editProfile:
            showAdminProfileEditor(context);
            break;
          case _AccountAction.changePassword:
            showAdminChangePassword(context);
            break;
          case _AccountAction.logout:
            onLogout();
            break;
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: _AccountAction.editProfile,
          child: _MenuRow(icon: Icons.edit_rounded, label: 'Edit profile'),
        ),
        PopupMenuItem(
          value: _AccountAction.changePassword,
          child: _MenuRow(
            icon: Icons.lock_outline_rounded,
            label: 'Change password',
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: _AccountAction.logout,
          child: _MenuRow(
            icon: Icons.logout_rounded,
            label: 'Log out',
            danger: true,
          ),
        ),
      ],
      child: content,
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? photoUrl;
  final String initials;
  const _Avatar({required this.photoUrl, required this.initials});

  @override
  Widget build(BuildContext context) {
    final fallback = Center(
      child: Text(
        initials,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.primaryBlue,
        ),
      ),
    );

    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: (photoUrl != null && photoUrl!.isNotEmpty)
          ? CachedNetworkImage(
              imageUrl: photoUrl!,
              fit: BoxFit.cover,
              errorWidget: (_, _, _) => fallback,
            )
          : fallback,
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool danger;
  const _MenuRow({
    required this.icon,
    required this.label,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = danger ? AppColors.red : AdminUi.textSecondary;
    return Row(
      children: [
        Icon(icon, size: 18, color: c),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: c,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _Skeleton extends StatelessWidget {
  final bool showName;
  const _Skeleton({required this.showName});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: AdminShimmer(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SkeletonCircle(size: 34),
            if (showName) ...[
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: const [
                  SkeletonBox(width: 92, height: 11),
                  SizedBox(height: 6),
                  SkeletonBox(width: 64, height: 9),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
