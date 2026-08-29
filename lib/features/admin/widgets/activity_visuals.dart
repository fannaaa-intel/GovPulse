import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/admin_dashboard_provider.dart' show ActivityKind;

// ════════════════════════════════════════════════════════════════════════════
//  Shared visual vocabulary for the recent-activity feed.
//
//  The dashboard card and the full "View all" feed render the same events at
//  two densities. The icon and colour for a kind must not be able to drift
//  between them — an event that is orange on the card and green in the feed
//  reads as two different events — so both read from here.
//
//  The provider stays free of any Flutter import; the mapping lives on the UI
//  side, which is why this is a widget-layer file rather than part of the
//  ActivityKind enum.
// ════════════════════════════════════════════════════════════════════════════

IconData activityKindIcon(ActivityKind kind) => switch (kind) {
  ActivityKind.reportNew => Icons.flag_rounded,
  ActivityKind.reportReviewing => Icons.hourglass_top_rounded,
  ActivityKind.reportResolved => Icons.check_circle_rounded,
  ActivityKind.reportRejected => Icons.do_not_disturb_on_rounded,
  ActivityKind.verifPending => Icons.how_to_reg_rounded,
  ActivityKind.verifApproved => Icons.verified_user_rounded,
  ActivityKind.verifRejected => Icons.cancel_rounded,
};

Color activityKindColor(ActivityKind kind) => switch (kind) {
  ActivityKind.reportNew => AppColors.primaryBlue,
  ActivityKind.reportReviewing => AppColors.orange,
  ActivityKind.reportResolved => AppColors.green,
  ActivityKind.reportRejected => AppColors.red,
  ActivityKind.verifPending => AppColors.orange,
  ActivityKind.verifApproved => AppColors.green,
  ActivityKind.verifRejected => AppColors.red,
};
