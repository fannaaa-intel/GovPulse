import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/modal/media_picker_sheet.dart';
import '../providers/admin_profile_provider.dart';
import '../theme/admin_ui.dart';
import '../widgets/admin_dialog_back.dart';
import '../widgets/admin_snackbar.dart';

/// Opens the admin profile editor — a centred dialog on web/desktop/tablet
/// (≥ 900px) and a full-screen page on phones, matching the rest of the console.
void showAdminProfileEditor(BuildContext context) {
  final wide = MediaQuery.of(context).size.width >= 900;
  if (wide) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
          child: const _AdminProfileForm(fullScreen: false),
        ),
      ),
    );
  } else {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const Scaffold(
          backgroundColor: AdminUi.surface,
          body: SafeArea(child: _AdminProfileForm(fullScreen: true)),
        ),
      ),
    );
  }
}

class _AdminProfileForm extends ConsumerStatefulWidget {
  final bool fullScreen;
  const _AdminProfileForm({required this.fullScreen});

  @override
  ConsumerState<_AdminProfileForm> createState() => _AdminProfileFormState();
}

class _AdminProfileFormState extends ConsumerState<_AdminProfileForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _title;
  late final TextEditingController _org;

  String? _photoUrl; // existing
  Uint8List? _pickedBytes; // freshly picked
  String? _pickedExt;
  bool _saving = false;
  bool _seeded = false;

  @override
  void initState() {
    super.initState();
    final p = ref.read(adminProfileProvider).valueOrNull;
    _name = TextEditingController(text: p?.fullName ?? '');
    _title = TextEditingController(text: p?.title ?? 'Administrator');
    _org = TextEditingController(text: p?.organization ?? 'LGU Aparri');
    _photoUrl = p?.photoUrl;
    _seeded = p != null;
  }

  @override
  void dispose() {
    _name.dispose();
    _title.dispose();
    _org.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final floating = MediaQuery.of(context).size.width >= 900;
    try {
      XFile? picked;
      if (floating) {
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
      if (!mounted) return;
      setState(() {
        _pickedBytes = bytes;
        _pickedExt =
            picked!.name.contains('.') ? picked.name.split('.').last : 'jpg';
      });
    } catch (e) {
      if (!mounted) return;
      showAdminSnackBar(context, 'Could not add photo: $e',
          type: AdminSnackType.error);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final notifier = ref.read(adminProfileProvider.notifier);
    try {
      var photoUrl = _photoUrl;
      if (_pickedBytes != null) {
        photoUrl = await notifier.uploadAvatar(_pickedBytes!, _pickedExt ?? 'jpg');
      }
      await notifier.save(
        fullName: _name.text,
        title: _title.text,
        organization: _org.text,
        photoUrl: photoUrl,
      );
      if (!mounted) return;
      Navigator.pop(context);
      showAdminSnackBar(context, 'Profile updated.',
          type: AdminSnackType.success);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAdminSnackBar(context, 'Could not save profile: $e',
          type: AdminSnackType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    // If the profile finished loading after the form opened, seed the fields
    // once so an editor opened mid-fetch still prefills.
    ref.listen(adminProfileProvider, (_, next) {
      final p = next.valueOrNull;
      if (!_seeded && p != null) {
        _seeded = true;
        _name.text = p.fullName ?? '';
        _title.text = p.title;
        _org.text = p.organization;
        setState(() => _photoUrl = p.photoUrl);
      }
    });

    final email = ref.watch(adminProfileProvider).valueOrNull?.email ?? '';

    return Material(
      color: AdminUi.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: widget.fullScreen ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(widget.fullScreen ? 12 : 18, 12, 8, 12),
            child: Row(
              children: [
                // Phone: back chevron on the left. Web/desktop: X on the right.
                if (widget.fullScreen) ...[
                  AdminDialogBack(onTap: () => Navigator.pop(context)),
                  const SizedBox(width: 12),
                ],
                const Expanded(
                  child: Text(
                    'Edit profile',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AdminUi.textPrimary,
                    ),
                  ),
                ),
                if (!widget.fullScreen)
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: AdminUi.textMuted),
                    onPressed: () => Navigator.pop(context),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: AdminUi.border),
          Flexible(
            child: LayoutBuilder(
              builder: (context, c) => SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: widget.fullScreen ? c.maxHeight - 40 : 0,
                  ),
                  child: Center(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(child: _buildAvatar()),
                          const SizedBox(height: 20),
                          _field(_name, 'Full name',
                              hint: 'e.g. Juan Dela Cruz'),
                          const SizedBox(height: 12),
                          _field(_title, 'Title', hint: 'e.g. Administrator'),
                          const SizedBox(height: 12),
                          _field(_org, 'Organization', hint: 'e.g. LGU Aparri'),
                          const SizedBox(height: 12),
                          _readOnlyEmail(email),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const Divider(height: 1, color: AdminUi.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AdminUi.textSecondary,
                        side: const BorderSide(color: AdminUi.border),
                        textStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_rounded, size: 20),
                      label: const Text('Save changes'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        foregroundColor: Colors.white,
                        elevation: 2,
                        shadowColor: AppColors.primaryBlue.withValues(alpha: 0.4),
                        textStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    return GestureDetector(
      onTap: _pickImage,
      child: Stack(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.10),
              shape: BoxShape.circle,
              border: Border.all(color: AdminUi.border, width: 2),
            ),
            clipBehavior: Clip.antiAlias,
            child: _pickedBytes != null
                ? Image.memory(_pickedBytes!, fit: BoxFit.cover)
                : (_photoUrl != null && _photoUrl!.isNotEmpty)
                    ? CachedNetworkImage(
                        imageUrl: _photoUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => const Icon(
                          Icons.person_rounded,
                          size: 42,
                          color: AppColors.primaryBlue,
                        ),
                      )
                    : const Icon(
                        Icons.person_rounded,
                        size: 42,
                        color: AppColors.primaryBlue,
                      ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.primaryBlue,
                shape: BoxShape.circle,
                border: Border.all(color: AdminUi.surface, width: 2),
              ),
              child: const Icon(
                Icons.photo_camera_rounded,
                size: 15,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label, {
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AdminUi.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: ctrl,
          style: const TextStyle(fontSize: 13, color: AdminUi.textPrimary),
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Required' : null,
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 13, color: AdminUi.textMuted),
            filled: true,
            fillColor: AdminUi.surface,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            border: _border(AdminUi.border),
            enabledBorder: _border(AdminUi.border),
            focusedBorder: _border(AppColors.primaryBlue),
            errorBorder: _border(AppColors.red),
            focusedErrorBorder: _border(AppColors.red),
          ),
        ),
      ],
    );
  }

  Widget _readOnlyEmail(String email) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Email',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AdminUi.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: AdminUi.subtle,
            borderRadius: BorderRadius.circular(AdminUi.controlRadius),
            border: Border.all(color: AdminUi.border),
          ),
          child: Row(
            children: [
              const Icon(Icons.lock_outline_rounded,
                  size: 15, color: AdminUi.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  email.isEmpty ? '—' : email,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AdminUi.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static OutlineInputBorder _border(Color c) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(AdminUi.controlRadius),
        borderSide: BorderSide(color: c),
      );
}
