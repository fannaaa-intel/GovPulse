import 'package:flutter/material.dart';

import '../../../core/widgets/app_snackbar.dart';

/// Semantic kind of an admin toast — drives its colour + icon.
enum AdminSnackType { success, error, info }

/// Admin-console toast. Thin wrapper over the shared [showAppSnackBar] so the
/// admin console and the citizen app share one top-anchored, palette-coloured
/// SnackBar design.
void showAdminSnackBar(
  BuildContext context,
  String message, {
  AdminSnackType type = AdminSnackType.info,
}) {
  showAppSnackBar(
    context,
    message,
    type: switch (type) {
      AdminSnackType.success => AppSnackType.success,
      AdminSnackType.error => AppSnackType.error,
      AdminSnackType.info => AppSnackType.info,
    },
  );
}
