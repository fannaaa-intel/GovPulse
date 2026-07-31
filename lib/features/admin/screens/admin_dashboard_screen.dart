import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/user_profile_provider.dart';
import '../../../core/services/chat_service.dart';
import '../../../core/services/push_service.dart';
import '../../../core/widgets/Home/Chat-bubbles/home_chat_bubble.dart';
import '../../../core/widgets/logout_confirm_dialog.dart';
import '../providers/admin_dashboard_provider.dart';
import '../providers/admin_events_provider.dart';
import '../providers/admin_settings_provider.dart';
import '../providers/admin_feedback_provider.dart';
import '../providers/admin_reports_provider.dart';
import '../providers/admin_suggestions_provider.dart';
import '../providers/admin_users_provider.dart';
import '../providers/admin_verification_provider.dart';
import '../providers/community_updates_provider.dart';
import '../widgets/admin_command_palette.dart';
import '../widgets/admin_notifications.dart';
import '../widgets/admin_sidebar.dart';
import '../widgets/admin_snackbar.dart';
import '../widgets/admin_topbar.dart';
import '../pages/admin_overview_page.dart';
import '../pages/admin_reports_page.dart';
import '../pages/admin_verification_page.dart';
import '../pages/admin_events_page.dart';
import '../pages/admin_feedback_page.dart';
import '../pages/admin_suggestions_page.dart';
import '../pages/admin_settings_page.dart';
import '../pages/admin_users_page.dart';
import '../pages/admin_team_page.dart';
import '../pages/community_updates_page.dart';
import '../../../core/widgets/app_dialog.dart';

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen>
    with WidgetsBindingObserver {
  int _selectedIndex = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  /// The visible section silently refetches so the admin sees near-realtime
  /// numbers without a manual pull. Only the current tab polls — switching tabs
  /// and resuming the app also trigger an immediate refresh. The interval is
  /// configurable in Settings (adminSettingsProvider.pollSeconds; 0 = Off).
  Timer? _pollTimer;

  final List<AdminNavItem> navItems = const [
    AdminNavItem(icon: Icons.dashboard_rounded, label: 'Dashboard'), // 0
    AdminNavItem(icon: Icons.people_alt_rounded, label: 'Community'), // 1
    AdminNavItem(icon: Icons.event_rounded, label: 'Events'), // 2
    AdminNavItem(icon: Icons.flag_rounded, label: 'Reports'), // 3
    AdminNavItem(icon: Icons.lightbulb_rounded, label: 'Suggestions'), // 4
    AdminNavItem(icon: Icons.reviews_rounded, label: 'Feedback'), // 5
    AdminNavItem(icon: Icons.verified_user_rounded, label: 'Verification'), // 6
    AdminNavItem(icon: Icons.manage_accounts_rounded, label: 'Citizens'), // 7
    AdminNavItem(icon: Icons.badge_rounded, label: 'Team'), // 8
    AdminNavItem(icon: Icons.settings_rounded, label: 'Settings'), // 9
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Tapping a notification in the panel sets AdminNotifCenter.openTopic; we
    // map that topic to its nav tab here and switch to it.
    AdminNotifCenter.I.openTopic.addListener(_onNotifNavigate);
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    AdminNotifCenter.I.openTopic.removeListener(_onNotifNavigate);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back to the app should show fresh data immediately, not wait for
    // the next poll tick; pause polling entirely while backgrounded.
    if (state == AppLifecycleState.resumed) {
      _refreshCurrentTab();
      _startPolling();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _pollTimer?.cancel();
    }
  }

  // ── Silent auto-refresh ──────────────────────────────────────────────────
  void _startPolling() {
    _pollTimer?.cancel();
    final seconds = ref.read(adminSettingsProvider).pollSeconds;
    if (seconds <= 0) return; // "Off" — no auto-refresh
    _pollTimer =
        Timer.periodic(Duration(seconds: seconds), (_) => _refreshCurrentTab());
  }

  /// Silently refetches the data behind the currently visible tab. Guarded by
  /// `hasValue` so the very first visit (still loading its initial data) isn't
  /// double-fetched — only already-loaded sections get the background refresh.
  /// Tabs without a data provider (Users/Settings) are no-ops.
  void _refreshCurrentTab() {
    // Keep the bell badge honest even if a Realtime INSERT was missed (e.g. a
    // dropped web socket) — recount unread on every poll tick as a backstop.
    AdminNotifCenter.I.refreshUnread();
    switch (_selectedIndex) {
      case 0:
        if (ref.read(adminDashboardProvider).hasValue) {
          ref.read(adminDashboardProvider.notifier).silentRefresh();
        }
      case 1:
        if (ref.read(communityUpdatesProvider).hasValue) {
          ref.read(communityUpdatesProvider.notifier).silentRefresh();
        }
      case 2:
        if (ref.read(adminEventsProvider).hasValue) {
          ref.read(adminEventsProvider.notifier).silentRefresh();
        }
      case 3:
        if (ref.read(adminReportsProvider).hasValue) {
          ref.read(adminReportsProvider.notifier).silentRefresh();
        }
      case 4:
        if (ref.read(adminSuggestionsProvider).hasValue) {
          ref.read(adminSuggestionsProvider.notifier).silentRefresh();
        }
      case 5:
        if (ref.read(adminFeedbackProvider).hasValue) {
          ref.read(adminFeedbackProvider.notifier).silentRefresh();
        }
      case 6:
        if (ref.read(adminVerificationProvider).hasValue) {
          ref.read(adminVerificationProvider.notifier).silentRefresh();
        }
      case 7:
      case 8:
        if (ref.read(adminUsersProvider).hasValue) {
          ref.read(adminUsersProvider.notifier).silentRefresh();
        }
    }
  }

  /// Switches to tab [i] and immediately refreshes it, then restarts the poll
  /// clock so the freshly-shown tab gets a full interval before its next tick.
  ///
  /// [highlightId] deep-links to a specific row: the destination page scrolls
  /// it into view and flashes it once. One-shot — consumed by the next build so
  /// returning to the tab later doesn't re-flash a stale target.
  void _selectTab(int i, {String? highlightId, bool openComments = false}) {
    setState(() {
      _selectedIndex = i;
      _pendingHighlightId = highlightId;
      _pendingOpenComments = openComments;
      // Every deep-link tap gets a fresh token. Pages can't re-arm by comparing
      // highlightId/openComments alone: tapping the SAME heart notification
      // twice delivers identical values, so nothing looks "changed" and the
      // second tap is dropped. (Tapping a comment in between flips
      // openComments, which is exactly why interleaving one made the next heart
      // tap appear to work.) A token makes each tap its own event.
      if (highlightId != null) _deepLinkNonce++;
    });
    _refreshCurrentTab();
    _startPolling();
  }

  /// Deep-link target awaiting the page that owns it. See [_selectTab].
  String? _pendingHighlightId;

  /// Comment/reply notifications open the post's comments panel on arrival.
  bool _pendingOpenComments = false;

  /// Bumped on every deep-link tap. Pages re-arm on a CHANGE to this rather
  /// than on the target's value, so repeat taps on the same target still fire.
  int _deepLinkNonce = 0;

  /// Opens the ⌘K command palette. Feeds it the nav list (so results can jump
  /// to any section) and the same tab-switch used by the sidebar.
  void _openCommandPalette() {
    showAdminCommandPalette(
      context,
      sections: [
        for (final n in navItems) (icon: n.icon, label: n.label),
      ],
      onNavigate: _selectTab,
    );
  }

  void _onNotifNavigate() {
    final target = AdminNotifCenter.I.openTopic.value;
    if (target == null) return;
    AdminNotifCenter.I.openTopic.value = null; // consume it
    final idx = _tabIndexForTopic(target.topic);
    if (idx == null || !mounted) return;

    // Anything ABOUT a comment (comment / reply / comment-like) opens the post's
    // comments panel; a bare post like just lands on the post.
    const commentTopics = {
      'comment', 'comment_heart', 'post_comment', 'comment_reply',
      'comment_like',
    };
    final isCommentTopic = commentTopics.contains(target.topic);
    // Always carry the referenceId so the post scrolls into view and flashes —
    // engagement included (blue highlight on likes/comments is intended here).
    _selectTab(idx, highlightId: target.referenceId, openComments: isCommentTopic);
  }

  /// Maps a notification topic to the nav tab that owns it. Resolved by label
  /// (not a hard-coded index) so it survives any nav reordering.
  int? _tabIndexForTopic(String topic) {
    final label = switch (topic) {
      'report' => 'Reports',
      'suggestion' => 'Suggestions',
      'feedback' => 'Feedback',
      'verification' => 'Verification',
      // A staff submission awaiting review lands on Community too — the page
      // itself flips to the Requests tab when the highlighted post is pending.
      // Both engagement vocabularies route here (see kAllAdminTopics).
      'comment' ||
      'post_heart' ||
      'comment_heart' ||
      'post_like' ||
      'comment_like' ||
      'post_comment' ||
      'comment_reply' ||
      'community_request' =>
        'Community',
      _ => null,
    };
    if (label == null) return null;
    final i = navItems.indexWhere((n) => n.label == label);
    return i >= 0 ? i : null;
  }

  Widget _buildPage() {
    // One-shot read: the page mounting now owns this target. Cleared after the
    // frame so a later return to the same tab starts clean. Cleared without
    // setState — the page already has the value it needs for this build.
    final highlightId = _pendingHighlightId;
    final openComments = _pendingOpenComments;
    if (highlightId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pendingHighlightId = null;
        _pendingOpenComments = false;
      });
    }

    switch (_selectedIndex) {
      case 0:
        return AdminOverviewPage(
          selectedIndex: _selectedIndex,
          onNavigate: _selectTab,
        );
      case 1:
        return CommunityUpdatesPage(
          highlightId: highlightId,
          openComments: openComments,
          deepLinkNonce: _deepLinkNonce,
        );
      case 2:
        return const AdminEventsPage();
      case 3:
        return AdminReportsPage(highlightId: highlightId);
      case 4:
        return AdminSuggestionsPage(highlightId: highlightId);
      case 5:
        return AdminFeedbackPage(highlightId: highlightId);
      case 6:
        return AdminVerificationPage(highlightId: highlightId);
      case 7:
        return const AdminUsersPage();
      case 8:
        return const AdminTeamPage();
      case 9:
        return AdminSettingsPage(onLogout: _confirmLogout);
      default:
        return _ComingSoon(label: navItems[_selectedIndex].label);
    }
  }

  // ── Logout flow (mirrors Settings) ───────────────────────────────────────
  Future<void> _confirmLogout() async {
    final shouldLogout = await showLogoutConfirmDialog(context);
    if (!shouldLogout || !mounted) return;

    showAppDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const LogoutLoadingOverlay(),
    );

    try {
      // Drop the realtime channel and zero the badge BEFORE signing out. The
      // count and the subscription live in a process-wide singleton, so without
      // this an admin's unread total survives into whoever signs in next on the
      // same device. Mirrors staff_console_screen's _confirmLogout.
      AdminNotifCenter.I.stop();
      await PushService.I.unregister();
      await Supabase.instance.client.auth.signOut();
      await ChatService.onUserSignedOut();
      HomeChatBubble.hideGlobal();

      if (!mounted) return;
      Navigator.pop(context); // dismiss loading spinner
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      ref.invalidate(userProfileProvider);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      showAdminSnackBar(context, 'Logout failed: $e', type: AdminSnackType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keep settings alive (loads prefs + pushes muted topics into the notif
    // center) and restart polling immediately when the interval is changed.
    ref.listen(adminSettingsProvider.select((s) => s.pollSeconds), (_, _) {
      _startPolling();
    });

    final width = MediaQuery.of(context).size.width;
    final bool isDesktop = width >= 1024;
    final bool isTablet = width >= 600 && width < 1024;

    final Widget layout = isDesktop
        ? _buildDesktopLayout()
        : (isTablet ? _buildTabletLayout() : _buildMobileLayout());

    // Global ⌘K / Ctrl-K opens the command palette from anywhere in the console.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _openCommandPalette,
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            _openCommandPalette,
      },
      child: Focus(autofocus: true, child: layout),
    );
  }

  // ── Desktop: permanent full sidebar ──────────────────────────────────────
  Widget _buildDesktopLayout() {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: SafeArea(
        child: Row(
          children: [
            AdminSidebar(
              items: navItems,
              selectedIndex: _selectedIndex,
              collapsed: false,
              onItemTap: _selectTab,
              onLogout: _confirmLogout,
            ),
            Expanded(
              child: Column(
                children: [
                  AdminTopBar(
                    title: navItems[_selectedIndex].label,
                    showMenuButton: false,
                    onLogout: _confirmLogout,
                    onSearchTap: _openCommandPalette,
                  ),
                  Expanded(child: _buildPage()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Tablet: collapsed icon-only sidebar ───────────────────────────────────
  Widget _buildTabletLayout() {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: SafeArea(
        child: Row(
          children: [
            AdminSidebar(
              items: navItems,
              selectedIndex: _selectedIndex,
              collapsed: true,
              onItemTap: _selectTab,
              onLogout: _confirmLogout,
            ),
            Expanded(
              child: Column(
                children: [
                  AdminTopBar(
                    title: navItems[_selectedIndex].label,
                    showMenuButton: false,
                    onLogout: _confirmLogout,
                    onSearchTap: _openCommandPalette,
                  ),
                  Expanded(child: _buildPage()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Mobile: hidden sidebar, hamburger drawer ──────────────────────────────
  Widget _buildMobileLayout() {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF4F6FB),
      drawerScrimColor: Colors.black.withValues(alpha: 0.55),
      drawer: Drawer(
        width: 244,
        backgroundColor: Colors.white,
        elevation: 8,
        child: SafeArea(
          child: AdminSidebar(
            items: navItems,
            selectedIndex: _selectedIndex,
            collapsed: false,
            onItemTap: (i) {
              _selectTab(i);
              Navigator.pop(context);
            },
            onLogout: () {
              Navigator.pop(context); // close the drawer first
              _confirmLogout();
            },
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            AdminTopBar(
              title: navItems[_selectedIndex].label,
              showMenuButton: true,
              onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
              onLogout: _confirmLogout,
              onSearchTap: _openCommandPalette,
            ),
            Expanded(child: _buildPage()),
          ],
        ),
      ),
    );
  }
}

class AdminNavItem {
  final IconData icon;
  final String label;
  const AdminNavItem({required this.icon, required this.label});
}

class _ComingSoon extends StatelessWidget {
  final String label;
  const _ComingSoon({required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.construction_rounded,
            size: 40,
            color: Colors.black.withValues(alpha: 0.18),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'This section is coming soon.',
            style: TextStyle(
              fontSize: 13,
              color: Colors.black.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );
  }
}
