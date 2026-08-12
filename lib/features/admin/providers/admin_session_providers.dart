import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'admin_activity_provider.dart';
import 'admin_dashboard_provider.dart';
import 'admin_events_provider.dart';
import 'admin_feedback_provider.dart';
import 'admin_flagged_comments_provider.dart';
import 'admin_identity_reveal_provider.dart';
import 'admin_moderation_config_provider.dart';
import 'admin_profile_provider.dart';
import 'admin_reports_provider.dart';
import 'admin_settings_provider.dart';
import 'admin_spam_watch_provider.dart';
import 'admin_suggestions_provider.dart';
import 'admin_users_provider.dart';
import 'admin_verification_provider.dart';
import 'community_updates_provider.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Admin providers scoped to the signed-in account, for the sign-out teardown
//  in `core/services/session_teardown.dart`.
//
//  Why this list has to exist: none of these is `.autoDispose`, so each one's
//  state lives for the lifetime of the root ProviderScope. On web that scope
//  outlives sign-out, and an admin's cached dashboard, user list and moderation
//  state were still in the container when the next account signed in.
//
//  Unlike the staff equivalent — which sits directly below its declarations in
//  staff_providers.dart — the admin providers are spread across fourteen files,
//  so a barrel is the only way to gather them. That makes drift easier here, not
//  harder: KEEP THIS IN SYNC when adding a provider under features/admin.
//
//  `communityUpdatesRepoProvider` is absent on purpose: it wraps a stateless
//  repository singleton and holds nothing to clear.
// ════════════════════════════════════════════════════════════════════════════

/// The admin half of the sign-out teardown set.
///
/// Includes the derived providers ([pendingCountProvider]) even though they
/// recompute from sources already in this list. Invalidating them is a no-op
/// today and cheap insurance against one of them growing state later.
final List<ProviderOrFamily> adminSessionProviders = <ProviderOrFamily>[
  adminActivityProvider,
  adminDashboardProvider,
  adminEventsProvider,
  adminFeedbackProvider,
  adminFlaggedCommentsProvider,
  currentAdminIsFullAdminProvider,
  adminModerationConfigProvider,
  adminProfileProvider,
  adminReportsProvider,
  adminSettingsProvider,
  adminSpamWatchProvider,
  adminSuggestionsProvider,
  adminUsersProvider,
  manageUserQueryProvider,
  adminVerificationProvider,
  communityUpdatesProvider,
  pendingCountProvider,
];
