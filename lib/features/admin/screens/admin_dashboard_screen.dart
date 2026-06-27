import 'package:flutter/material.dart';

import '../widgets/admin_sidebar.dart';
import '../widgets/admin_topbar.dart';
import '../pages/admin_overview_page.dart';
import '../pages/admin_reports_page.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
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
      default:
        return _ComingSoon(label: navItems[_selectedIndex].label);
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
