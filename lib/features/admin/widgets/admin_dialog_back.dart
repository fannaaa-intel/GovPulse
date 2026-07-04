import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../theme/admin_ui.dart';

/// Back control for admin dialogs / full-screen forms — a rounded chevron
/// button placed at the LEFT of the header title, mirroring the citizen
/// settings screens (instead of a top-right X).
class AdminDialogBack extends StatelessWidget {
  final VoidCallback onTap;
  const AdminDialogBack({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AdminUi.subtle,
      borderRadius: BorderRadius.circular(AdminUi.controlRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AdminUi.controlRadius),
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AdminUi.controlRadius),
            border: Border.all(color: AdminUi.border),
          ),
          child: const Icon(
            Icons.chevron_left_rounded,
            size: 24,
            color: AppColors.primaryBlue,
          ),
        ),
      ),
    );
  }
}
