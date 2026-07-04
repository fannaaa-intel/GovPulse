import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import '../home_enums.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../modal/verification_required_dialog.dart';

class HomeNavDrawer extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final String username;
  final String? fullName;
  final String? facePhotoUrl;
  final VerifStatus verifStatus;
  final VoidCallback onLogout;

  const HomeNavDrawer({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.username,
    required this.fullName,
    required this.facePhotoUrl,
    required this.verifStatus,
    required this.onLogout,
  });

  static const _items = <_DrawerItem>[
    _DrawerItem('Home', 'assets/images/home.webp', 0),
    _DrawerItem('My Reports', 'assets/images/my_reports.webp', 1),
    _DrawerItem('NewsFeed', 'assets/images/news_feed.webp', 2),
    _DrawerItem('Emergency', 'assets/images/emergency.webp', 3),
    _DrawerItem('Settings', 'assets/images/settings.webp', 4),
  ];

  @override
  Widget build(BuildContext context) {
    final isVerified = verifStatus == VerifStatus.verified;
    final isPending = verifStatus == VerifStatus.pending;

    final statusLabel = isVerified
        ? 'Verified'
        : isPending
        ? 'Pending'
        : 'Not Verified';
    final statusColor = isVerified
        ? const Color(0xFF15803D)
        : const Color(0xFFB45309);
    final dotColor = isVerified
        ? const Color(0xFF22C55E)
        : const Color(0xFFF59E0B);

    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: const Color(0xFFE5E7EB),

                    child: (facePhotoUrl != null && facePhotoUrl!.isNotEmpty)
                        ? ClipOval(
                            child: CachedNetworkImage(
                              imageUrl: facePhotoUrl!,
                              cacheKey: Uri.parse(facePhotoUrl!).path,
                              width: 52,
                              height: 52,
                              fit: BoxFit.cover,
                              placeholder: (_, _) =>
                                  const CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                              errorWidget: (_, _, _) =>
                                  Image.asset('assets/images/profilenew.webp'),
                            ),
                          )
                        : Image.asset('assets/images/profilenew.webp'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          fullName ?? username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '@$username',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF9CA3AF),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: dotColor,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              statusLabel,
                              style: TextStyle(
                                fontSize: 12,
                                color: statusColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE5E7EB)),
            const SizedBox(height: 8),
            // ── Items ──
            // ── Items ──
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (final item in _items)
                    _DrawerTile(
                      label: item.label,
                      iconPath: item.iconPath,
                      active: currentIndex == item.index,
                      onTap: () {
                        // My Reports is restricted to verified citizens.
                        if (item.index == 1 && !isVerified) {
                          showVerificationRequiredDialog(
                            context,
                            username: username,
                            message:
                                'Only verified citizens can access My Reports.',
                          );
                          return;
                        }
                        if (Navigator.of(context).canPop()) {
                          Navigator.of(context).pop();
                        }

                        onTap(item.index);
                      },
                    ),
                ],
              ),
            ),
            // ── Sign out — pinned to the bottom ──
            const Divider(height: 1, color: Color(0xFFE5E7EB)),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  }
                  onLogout();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.logout_rounded,
                        size: 22,
                        color: Color(0xFFEF4444),
                      ),
                      const SizedBox(width: 16),
                      const Text(
                        'Sign Out',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFEF4444),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem {
  final String label;
  final String iconPath;
  final int index;
  const _DrawerItem(this.label, this.iconPath, this.index);
}

class _DrawerTile extends StatelessWidget {
  final String label;
  final String iconPath;
  final bool active;
  final VoidCallback onTap;

  const _DrawerTile({
    required this.label,
    required this.iconPath,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primaryBlue : const Color(0xFF6B7280);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: active
                ? AppColors.primaryBlue.withValues(alpha: 0.08)
                : Colors.transparent,
            border: active
                ? const Border(
                    left: BorderSide(color: AppColors.primaryBlue, width: 3),
                  )
                : null,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: ColorFiltered(
                  colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                  child: Image.asset(iconPath),
                ),
              ),
              const SizedBox(width: 16),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
