import 'package:flutter/material.dart';

import '../widgets/admin_sidebar.dart';
import '../widgets/admin_topbar.dart';
import '../pages/admin_overview_page.dart';

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
    // We'll wire up all pages as we build them,
    // for now all point to overview
    return AdminOverviewPage(selectedIndex: _selectedIndex);
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
