import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/user_profile_provider.dart';
import '../../../core/services/chat_service.dart';
import '../../../core/services/push_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/Home/Chat-bubbles/home_chat_bubble.dart';
import '../widgets/admin_sidebar.dart';
import '../widgets/admin_topbar.dart';
import '../pages/admin_overview_page.dart';
import '../pages/admin_reports_page.dart';
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
    AdminNavItem(icon: Icons.dashboard_rounded, label: 'Dashboard'),
    AdminNavItem(icon: Icons.flag_rounded, label: 'Reports'),
    AdminNavItem(icon: Icons.campaign_rounded, label: 'Announcements'),
    AdminNavItem(icon: Icons.people_alt_rounded, label: 'Community'),
    AdminNavItem(icon: Icons.event_rounded, label: 'Events'),
    AdminNavItem(icon: Icons.lightbulb_rounded, label: 'Suggestions'),
    AdminNavItem(icon: Icons.emergency_rounded, label: 'Emergency'),
    AdminNavItem(icon: Icons.manage_accounts_rounded, label: 'Users'),
    AdminNavItem(icon: Icons.settings_rounded, label: 'Settings'),
  ];

  Widget _buildPage() {
    switch (_selectedIndex) {
      case 0:
        return AdminOverviewPage(
          selectedIndex: _selectedIndex,
          onNavigate: (i) => setState(() => _selectedIndex = i),
        );
      case 1:
        return const AdminReportsPage();
      case 3:
        return const CommunityUpdatesPage();
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Logout failed: $e'),
          backgroundColor: AppColors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
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
      body: Row(
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
                ),
                Expanded(child: _buildPage()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Tablet: collapsed icon-only sidebar ───────────────────────────────────
  Widget _buildTabletLayout() {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: Row(
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
                ),
                Expanded(child: _buildPage()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Mobile: hidden sidebar, hamburger drawer ──────────────────────────────
  Widget _buildMobileLayout() {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF4F6FB),
      drawer: Drawer(
        backgroundColor: Colors.white,
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
      body: Column(
        children: [
          AdminTopBar(
            title: navItems[_selectedIndex].label,
            showMenuButton: true,
            onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
          ),
          Expanded(child: _buildPage()),
        ],
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
