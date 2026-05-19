import 'package:flutter/material.dart';
import '../../../core/network/network_wrapper.dart';
import '../../../core/widgets/modal/verification_required_dialog.dart';
import '../../../features/home/screen/home_screen.dart';

class AppBottomNav extends StatelessWidget {
  final double width;
  final int currentIndex;
  final String username;
  final bool isVerified;

  const AppBottomNav({
    super.key,
    required this.width,
    required this.currentIndex,
    required this.username,
    required this.isVerified,
  });

  void _handleTap(BuildContext context, int index) {
    if (index == currentIndex) return;

    switch (index) {
      case 0:
        Navigator.pushAndRemoveUntil(
          context,
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 400),
            pageBuilder: (_, _, _) =>
                NetworkWrapper(child: HomePage(username: username)),
            transitionsBuilder: (_, anim, _, child) => SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(-1, 0),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: anim, curve: Curves.easeInOut)),
              child: child,
            ),
          ),
          (route) => false,
        );
        break;

      case 1:
        if (!isVerified) {
          showVerificationRequiredDialog(
            context,
            message: 'Only verified citizens can access My Reports.',
          );
          return;
        }
        Navigator.pushNamed(context, '/my_reports', arguments: username);
        break;

      case 2:
        Navigator.pushNamed(
          context,
          '/newsfeed',
          arguments: {'username': username, 'isVerified': isVerified},
        );
        break;

      case 3:
        Navigator.pushNamed(
          context,
          '/emergency',
          arguments: {'username': username, 'isVerified': isVerified},
        );
        break;

      case 4:
        Navigator.pushNamed(context, '/settings', arguments: username);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final iconSize = width * 0.065;
    const activeColor = Color(0xFF60A5FA);
    const inactiveColor = Color(0xFF9CA3AF);

    Widget buildIcon(String path, bool isActive) {
      return SizedBox(
        width: iconSize,
        height: iconSize,
        child: ColorFiltered(
          colorFilter: ColorFilter.mode(
            isActive ? activeColor : inactiveColor,
            BlendMode.srcIn,
          ),
          child: Image.asset(path),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .06),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        elevation: 0,
        currentIndex: currentIndex,
        selectedItemColor: activeColor,
        unselectedItemColor: inactiveColor,
        selectedFontSize: width * 0.028,
        unselectedFontSize: width * 0.028,
        onTap: (index) => _handleTap(context, index),
        items: [
          BottomNavigationBarItem(
            icon: buildIcon('assets/images/home.png', currentIndex == 0),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: buildIcon('assets/images/my_reports.png', currentIndex == 1),
            label: 'My Reports',
          ),
          BottomNavigationBarItem(
            icon: buildIcon('assets/images/news_feed.png', currentIndex == 2),
            label: 'NewsFeed',
          ),
          BottomNavigationBarItem(
            icon: buildIcon('assets/images/emergency.png', currentIndex == 3),
            label: 'Emergency',
          ),
          BottomNavigationBarItem(
            icon: buildIcon('assets/images/settings.png', currentIndex == 4),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
