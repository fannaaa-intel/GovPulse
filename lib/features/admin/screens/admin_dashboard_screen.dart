import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/user_profile_provider.dart';
import '../../../core/services/chat_service.dart';
import '../../../core/services/push_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/Home/Chat-bubbles/home_chat_bubble.dart';
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
import '../pages/community_updates_page.dart';

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  int _selectedIndex = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final List<AdminNavItem> navItems = const [
    AdminNavItem(icon: Icons.dashboard_rounded, label: 'Dashboard'), // 0
    AdminNavItem(icon: Icons.people_alt_rounded, label: 'Community'), // 1
    AdminNavItem(icon: Icons.event_rounded, label: 'Events'), // 2
    AdminNavItem(icon: Icons.flag_rounded, label: 'Reports'), // 3
    AdminNavItem(icon: Icons.lightbulb_rounded, label: 'Suggestions'), // 4
    AdminNavItem(icon: Icons.reviews_rounded, label: 'Feedback'), // 5
    AdminNavItem(icon: Icons.verified_user_rounded, label: 'Verification'), // 6
    AdminNavItem(icon: Icons.emergency_rounded, label: 'Emergency'), // 7
    AdminNavItem(icon: Icons.manage_accounts_rounded, label: 'Users'), // 8
    AdminNavItem(icon: Icons.settings_rounded, label: 'Settings'), // 9
  ];

  @override
  void initState() {
    super.initState();
    // Tapping a notification in the panel sets AdminNotifCenter.openTopic; we
    // map that topic to its nav tab here and switch to it.
    AdminNotifCenter.I.openTopic.addListener(_onNotifNavigate);
  }

  @override
  void dispose() {
    AdminNotifCenter.I.openTopic.removeListener(_onNotifNavigate);
    super.dispose();
  }

  void _onNotifNavigate() {
    final topic = AdminNotifCenter.I.openTopic.value;
    if (topic == null) return;
    AdminNotifCenter.I.openTopic.value = null; // consume it
    final idx = _tabIndexForTopic(topic);
    if (idx != null && mounted) setState(() => _selectedIndex = idx);
  }

  /// Maps a notification topic to the nav tab that owns it. Resolved by label
  /// (not a hard-coded index) so it survives any nav reordering.
  int? _tabIndexForTopic(String topic) {
    final label = switch (topic) {
      'report' => 'Reports',
      'suggestion' => 'Suggestions',
      'feedback' => 'Feedback',
      'verification' => 'Verification',
      'comment' || 'post_heart' || 'comment_heart' => 'Community',
      _ => null,
    };
    if (label == null) return null;
    final i = navItems.indexWhere((n) => n.label == label);
    return i >= 0 ? i : null;
  }

  Widget _buildPage() {
    switch (_selectedIndex) {
      case 0:
        return AdminOverviewPage(
          selectedIndex: _selectedIndex,
          onNavigate: (i) => setState(() => _selectedIndex = i),
        );
      case 1:
        return const CommunityUpdatesPage();
      case 2:
        return const AdminEventsPage();
      case 3:
        return const AdminReportsPage();
      case 4:
        return const AdminSuggestionsPage();
      case 5:
        return const AdminFeedbackPage();
      case 6:
        return const AdminVerificationPage();
      default:
        return _ComingSoon(label: navItems[_selectedIndex].label);
    }
  }

  // ── Logout flow (mirrors Settings) ───────────────────────────────────────
  Future<void> _confirmLogout() async {
    final width = MediaQuery.of(context).size.width.clamp(0.0, 480.0);

    final shouldLogout = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(width * 0.045),
        ),
        child: Padding(
          padding: EdgeInsets.all(width * 0.055),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: width * 0.16,
                height: width * 0.16,
                decoration: BoxDecoration(
                  color: AppColors.red.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.logout_rounded,
                  size: width * 0.085,
                  color: AppColors.red,
                ),
              ),
              SizedBox(height: width * 0.04),
              Text(
                'Log Out?',
                style: TextStyle(
                  fontSize: width * 0.052,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1F2937),
                ),
              ),
              SizedBox(height: width * 0.022),
              Text(
                'You\'ll need to sign in again to access your account.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: width * 0.034,
                  color: const Color(0xFF6B7280),
                  height: 1.45,
                ),
              ),
              SizedBox(height: width * 0.055),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.stroke),
                        padding: EdgeInsets.symmetric(vertical: width * 0.035),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(width * 0.03),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: width * 0.038,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF374151),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: width * 0.025),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.red,
                        elevation: 0,
                        padding: EdgeInsets.symmetric(vertical: width * 0.035),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(width * 0.03),
                        ),
                      ),
                      child: Text(
                        'Log Out',
                        style: TextStyle(
                          fontSize: width * 0.038,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (shouldLogout != true || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppColors.primaryBlue),
      ),
    );

    try {
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
    final width = MediaQuery.of(context).size.width;
    final bool isDesktop = width >= 1024;
    final bool isTablet = width >= 600 && width < 1024;

    if (isDesktop) {
      return _buildDesktopLayout();
    } else if (isTablet) {
      return _buildTabletLayout();
    } else {
      return _buildMobileLayout();
    }
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
              onItemTap: (i) => setState(() => _selectedIndex = i),
              onLogout: _confirmLogout,
            ),
            Expanded(
              child: Column(
                children: [
                  AdminTopBar(
                    title: navItems[_selectedIndex].label,
                    showMenuButton: false,
                    onLogout: _confirmLogout,
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
              onItemTap: (i) => setState(() => _selectedIndex = i),
              onLogout: _confirmLogout,
            ),
            Expanded(
              child: Column(
                children: [
                  AdminTopBar(
                    title: navItems[_selectedIndex].label,
                    showMenuButton: false,
                    onLogout: _confirmLogout,
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
              setState(() => _selectedIndex = i);
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
