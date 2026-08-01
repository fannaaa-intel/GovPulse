import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/modal/media_picker_sheet.dart';
import '../../admin/pages/admin_change_password.dart' show showAdminChangePassword;
import '../providers/staff_providers.dart';
import '../theme/staff_ui.dart';
import '../widgets/staff_common.dart';

class StaffSettingsPage extends ConsumerWidget {
  final VoidCallback onLogout;
  const StaffSettingsPage({super.key, required this.onLogout});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(staffIdentityProvider);
    final id = async.valueOrNull;

    return StaffPageBody(
      maxWidth: 640,
      onRefresh: () => ref.read(staffIdentityProvider.notifier).refresh(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Until the identity lands there is no name, department or photo to
          // show — shimmer the card rather than rendering the "Staff" / blank
          // fallbacks, which read as a real (wrong) profile. A *failed* fetch
          // still falls through to those fallbacks; pull-to-refresh retries.
          if (id == null && async.isLoading)
            const _ProfileCardSkeleton()
          else
            StaffCard(
              child: Row(
                children: [
                  _EditableAvatar(
                    photoUrl: id?.photoUrl,
                    initials: id?.initials ?? 'S',
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          id?.displayName ?? 'Staff',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: StaffUi.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            StaffPill(
                              label: id?.isExternal == true
                                  ? 'External entity'
                                  : 'Staff',
                              color: StaffUi.accent,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                id?.department ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12.5, color: StaffUi.textMuted),
                              ),
                            ),
                          ],
                        ),
                        if ((id?.email ?? '').isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(id!.email,
                              style: const TextStyle(
                                  fontSize: 12, color: StaffUi.textMuted)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          StaffCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _Tile(
                  icon: Icons.lock_outline_rounded,
                  label: 'Change password',
                  onTap: () => showAdminChangePassword(context),
                ),
                const Divider(height: 1, color: StaffUi.border),
                _PresenceTile(),
              ],
            ),
          ),
          const SizedBox(height: 12),
          StaffCard(
            padding: EdgeInsets.zero,
            child: _Tile(
              icon: Icons.logout_rounded,
              label: 'Log out',
              danger: true,
              onTap: onLogout,
            ),
          ),
        ],
      ),
    );
  }

}

/// The identity card while [staffIdentityProvider] is loading. Mirrors the real
/// card — 56px avatar, name line, pill + department row, email line — inside the
/// same [StaffCard], so the page holds its layout on phone and web alike. The
/// text bars are `Expanded`/fixed-width rather than absolute, so the row stays
/// intact on narrow screens.
class _ProfileCardSkeleton extends StatelessWidget {
  const _ProfileCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return StaffCard(
      child: StaffShimmer(
        child: Row(
          children: const [
            StaffSkeletonCircle(size: 56),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StaffSkeletonBox(width: 150, height: 16),
                  SizedBox(height: 9),
                  Row(
                    children: [
                      StaffSkeletonBox(width: 54, height: 16, radius: 8),
                      SizedBox(width: 6),
                      StaffSkeletonBox(width: 104, height: 11),
                    ],
                  ),
                  SizedBox(height: 8),
                  StaffSkeletonBox(width: 178, height: 11),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The staff member's avatar in Settings — tap to pick a new photo, which is
/// uploaded and persisted immediately. Shows initials until a photo is set.
class _EditableAvatar extends ConsumerStatefulWidget {
  final String? photoUrl;
  final String initials;
  const _EditableAvatar({required this.photoUrl, required this.initials});

  @override
  ConsumerState<_EditableAvatar> createState() => _EditableAvatarState();
}

class _EditableAvatarState extends ConsumerState<_EditableAvatar> {
  bool _busy = false;

  Future<void> _pickAndUpload() async {
    if (_busy) return;
    final picker = ImagePicker();
    final wide = MediaQuery.of(context).size.width >= 900;
    try {
      XFile? picked;
      if (wide) {
        picked = await picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 82,
          maxWidth: 800,
        );
      } else {
        final mode = await showMediaPickerSheet(context, allowVideo: false);
        if (mode == null) return;
        picked = await picker.pickImage(
          source: mode == 'camera' ? ImageSource.camera : ImageSource.gallery,
          imageQuality: 82,
          maxWidth: 800,
        );
      }
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final ext = picked.name.contains('.') ? picked.name.split('.').last : 'jpg';
      if (!mounted) return;
      setState(() => _busy = true);
      await ref.read(staffIdentityProvider.notifier).setPhoto(bytes, ext);
      if (mounted) {
        showAppSnackBar(context, 'Profile photo updated.',
            type: AppSnackType.success);
      }
    } catch (e) {
      if (mounted) showAppSnackBar(context, '$e', type: AppSnackType.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.photoUrl;
    return GestureDetector(
      onTap: _pickAndUpload,
      child: Stack(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: StaffUi.accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            clipBehavior: Clip.antiAlias,
            child: (url != null && url.isNotEmpty)
                ? CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    // Shimmer while the photo downloads, matching the card's
                    // own loading state rather than flashing the initials.
                    placeholder: (_, _) => const StaffShimmer(
                      child: StaffSkeletonCircle(size: 56),
                    ),
                    errorWidget: (_, _, _) => _initials(widget.initials),
                  )
                : _initials(widget.initials),
          ),
          if (_busy)
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.black38,
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  ),
                ),
              ),
            )
          else
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: StaffUi.accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: StaffUi.surface, width: 2),
                ),
                child: const Icon(Icons.photo_camera_rounded,
                    size: 11, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  Widget _initials(String initials) => Center(
        child: Text(
          initials,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: StaffUi.accent,
          ),
        ),
      );
}

class _PresenceTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(
      staffIdentityProvider.select((s) => s.valueOrNull?.isOnline ?? false),
    );
    return SwitchListTile(
      value: online,
      activeColor: StaffUi.online,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      secondary: Icon(
        online ? Icons.circle : Icons.circle_outlined,
        color: online ? StaffUi.online : StaffUi.offline,
        size: 18,
      ),
      title: Text(online ? 'On duty (Online)' : 'Off duty (Offline)',
          style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: StaffUi.textPrimary)),
      subtitle: const Text('Only online staff receive live citizen chats.',
          style: TextStyle(fontSize: 11.5, color: StaffUi.textMuted)),
      onChanged: (v) async {
        try {
          await ref.read(staffIdentityProvider.notifier).setOnline(v);
        } catch (e) {
          if (context.mounted) {
            showAppSnackBar(context, '$e', type: AppSnackType.error);
          }
        }
      },
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool danger;
  final VoidCallback onTap;
  const _Tile({
    required this.icon,
    required this.label,
    this.danger = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = danger ? StaffUi.danger : StaffUi.textPrimary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          child: Row(
            children: [
              Icon(icon, size: 20, color: danger ? StaffUi.danger : StaffUi.accent),
              const SizedBox(width: 14),
              Text(label,
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600, color: c)),
              const Spacer(),
              if (!danger)
                const Icon(Icons.chevron_right_rounded, color: StaffUi.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
