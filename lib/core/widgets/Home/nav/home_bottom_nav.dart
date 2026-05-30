import 'package:flutter/material.dart';

class HomeBottomNav extends StatelessWidget {
  final double width;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const HomeBottomNav({
    super.key,
    required this.width,
    required this.currentIndex,
    required this.onTap,
  });

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
        onTap: onTap,
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
