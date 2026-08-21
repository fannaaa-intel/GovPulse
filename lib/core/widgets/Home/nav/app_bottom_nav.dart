import 'package:flutter/material.dart';
import '../../../theme/mobile_metrics.dart';
import '../../../network/network_wrapper.dart';
import '../../../router/legacy_nav.dart';
import '../../modal/verification_required_dialog.dart';
import '../../../../features/home/screen/home_screen.dart';

class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final String username;
  final bool isVerified;
  final String? userBarangay;

  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.username,
    required this.isVerified,
    this.userBarangay,
  });

  void _handleTap(BuildContext context, int index) {
    if (index == currentIndex) return;

    switch (index) {
      case 0:
        Navigator.pushAndRemoveUntil(
          context,
          PageRouteBuilder(
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            pageBuilder: (_, _, _) =>
                NetworkWrapper(child: HomePage(username: username)),
            transitionsBuilder: (_, _, _, child) => child,
          ),
          (route) => false,
        );
        break;

      case 1:
        if (!isVerified) {
          showVerificationRequiredDialog(
            context,
            username: username,
            message: 'Only verified citizens can access My Reports.',
          );
          return;
        }
        pushLegacy(context, '/my_reports', arguments: username);
        break;

      case 2:
        pushLegacy(
          context,
          '/newsfeed',
          arguments: {
            'username': username,
            'isVerified': isVerified,
            'userBarangay': userBarangay,
          },
        );
        break;

      case 3:
        pushLegacy(
          context,
          '/emergency',
          arguments: {'username': username, 'isVerified': isVerified},
        );
        break;

      case 4:
        pushLegacy(context, '/settings', arguments: username);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Same rule, and the same reason, as HomeBottomNav — these two bars are
    // the same bar on two different scaffolds and must not drift.
    // ── Android system navigation ─────────────────────────────────────────
    //
    // targetSdk is 36, so the window is edge-to-edge whether it asks to be or
    // not — Android 15 removed the opt-out. That means this bar is drawn
    // UNDERNEATH the system navigation, and `viewPadding` is the only thing
    // that says how much of it is covered.
    //
    // Material's BottomNavigationBar already handles the VERTICAL case: it
    // adds `viewPadding.bottom` itself, so the buttons sit above a 48dp
    // 3-button bar and the white fill runs down behind a 24dp gesture handle
    // rather than leaving a strip of page showing through. That part was
    // right and is left alone.
    //
    // What it does not handle is LANDSCAPE, where a phone moves the 3-button
    // bar to a SIDE — `viewPadding.right` (or `.left`, if the device was
    // rotated the other way) becomes ~48 and `.bottom` becomes 0. The bar was
    // laid out across the full width regardless, so Settings ended 8dp past
    // the usable edge with its tap target half-swallowed by the system bar.
    //
    // The padding goes INSIDE the Container, not around it, on purpose: the
    // items move inboard while the white fill and its shadow still span the
    // whole width, so the strip behind the system bar stays app-coloured
    // instead of showing the page scrolling past underneath.
    final viewPad = MediaQuery.viewPaddingOf(context);
    final width = uiScaleWidth(context);
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
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 10,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.only(left: viewPad.left, right: viewPad.right),
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
              icon: buildIcon('assets/images/home.webp', currentIndex == 0),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: buildIcon(
                'assets/images/my_reports.webp',
                currentIndex == 1,
              ),
              label: 'My Reports',
            ),
            BottomNavigationBarItem(
              icon: buildIcon(
                'assets/images/news_feed.webp',
                currentIndex == 2,
              ),
              label: 'NewsFeed',
            ),
            BottomNavigationBarItem(
              icon: buildIcon(
                'assets/images/emergency.webp',
                currentIndex == 3,
              ),
              label: 'Emergency',
            ),
            BottomNavigationBarItem(
              icon: buildIcon('assets/images/settings.webp', currentIndex == 4),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
