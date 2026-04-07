import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../features/home/screen/notification_popup.dart';
import '../../../core/theme/app_colors.dart';

class HomePage extends StatefulWidget {
  final String username;

  const HomePage({super.key, required this.username});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FlutterLocalNotificationsPlugin notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool isVerified = false;

  @override
  void initState() {
    super.initState();
    _initNotifications();

    Future.delayed(const Duration(minutes: 5), () {
      if (!isVerified) {
        _triggerVerificationReminder();
      }
    });
  }

  void _initNotifications() async {
    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings settings = InitializationSettings(
      android: androidInit,
    );

    await notificationsPlugin.initialize(settings);
  }

  void _triggerVerificationReminder() {
    NotificationService.add(
      AppNotification(
        icon: Icons.verified_user,
        title: "Verification Required",
        subtitle: "Complete your identity verification now",
        time: "Just now",
        color: Colors.orange,
      ),
    );

    setState(() {});

    _showLocalNotification();
  }

  Future<void> _showLocalNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'verification_channel',
      'Verification Reminder',
      importance: Importance.max,
      priority: Priority.high,
    );

    const details = NotificationDetails(android: androidDetails);

    await notificationsPlugin.show(
      0,
      'Complete Verification',
      'Tap to verify your account now',
      details,
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final width = size.width;
    final height = size.height;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            children: [
              _buildHeader(width),

              Transform.translate(
                offset: Offset(0, -width * 0.05),
                child: _buildProfileCard(context, width),
              ),

              SizedBox(height: width * 0.002),

              _buildCommunityUpdatesSection(context, width),
              SizedBox(height: width * 0.05),
              _buildQuickActionsSection(width),
              SizedBox(height: height * 0.02),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(width),
    );
  }

  Widget _buildHeader(double width) {
    return SizedBox(
      width: double.infinity,
      height: width * 0.52,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/bg.png', fit: BoxFit.cover),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: width * 0.20,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, const Color(0xFFF3F4F6)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard(BuildContext context, double width) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: width * 0.04),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(width * 0.04),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(width * 0.04),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: width * 0.17,
                  height: width * 0.17,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/images/profilenew.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                SizedBox(width: width * 0.03),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(top: width * 0.012),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.username,
                          style: TextStyle(
                            fontSize: width * 0.052,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF1F2937),
                          ),
                        ),
                        SizedBox(height: width * 0.008),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: width * 0.025,
                            vertical: width * 0.012,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF7ED),
                            borderRadius: BorderRadius.circular(width * 0.03),
                            border: Border.all(color: const Color(0xFFF59E0B)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: width * 0.010,
                                height: width * 0.010,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFF59E0B),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              SizedBox(width: width * 0.012),
                              Text(
                                'Status: Semi Verified',
                                style: TextStyle(
                                  fontSize: width * 0.030,
                                  color: const Color(0xFFB45309),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _buildNotificationBadge(context, width),
              ],
            ),
            SizedBox(height: width * 0.04),
            Text(
              'Complete your identity verification as Aparri citizen to access full local government unit of Aparri services',
              style: TextStyle(
                fontSize: width * 0.032,
                color: const Color(0xFF374151),
              ),
            ),
            SizedBox(height: width * 0.045),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.green,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(width * 0.03),
                  ),
                  padding: EdgeInsets.symmetric(vertical: width * 0.035),
                ),
                child: Text(
                  'Verify Now',
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
      ),
    );
  }

  Widget _buildNotificationBadge(BuildContext context, double width) {
    return GestureDetector(
      onTap: () => _showNotifications(context, width),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Image.asset(
            'assets/images/notifications.png',
            width: width * 0.090,
            height: width * 0.090,
          ),
          Positioned(
            right: -width * 0.008,
            top: -width * 0.008,
            child: Container(
              width: width * 0.04,
              height: width * 0.04,
              decoration: BoxDecoration(
                color: AppColors.green,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              alignment: Alignment.center,
              child: Text(
                '${NotificationService.count}',
                style: TextStyle(
                  fontSize: width * 0.022,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showNotifications(BuildContext context, double width) async {
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Notifications",
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, __, ___) {
        return NotificationPopup(width: width);
      },
      transitionBuilder: (_, animation, __, child) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutBack,
            ),
            child: child,
          ),
        );
      },
    );

    setState(() {});
  }

  Widget _buildCommunityUpdatesSection(BuildContext context, double width) {
    final scrollController = ScrollController();

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: width * 0.04),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(width * 0.03),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(width * 0.04),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// HEADER
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Community Updates',
                  style: TextStyle(
                    color: AppColors.primaryBlue,
                    fontSize: width * 0.047,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Row(
                  children: [
                    Text(
                      'View All',
                      style: TextStyle(
                        color: const Color(0xFF6B7280),
                        fontSize: width * 0.035,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(width: width * 0.01),
                    Icon(
                      Icons.arrow_forward_ios,
                      size: width * 0.032,
                      color: const Color(0xFF9CA3AF),
                    ),
                  ],
                ),
              ],
            ),

            SizedBox(height: width * 0.015),

            ///  SCROLLABLE AREA WITH SCROLLBAR
            SizedBox(
              height:
                  MediaQuery.of(context).size.height * 0.30, //  FIXED HEIGHT
              child: Scrollbar(
                controller: scrollController,
                thumbVisibility: true,
                trackVisibility: true, //  TEMP (so you SEE it)
                thickness: 4, // 👈TEMP (easy to see)
                radius: const Radius.circular(20),
                child: ListView(
                  controller: scrollController,
                  physics: const BouncingScrollPhysics(),

                  /// KEEP THESE
                  shrinkWrap: true,
                  primary: false,

                  padding: EdgeInsets.only(right: width * 0.01),

                  ///  TEMP: FORCE SCROLL (so scrollbar appears)
                  children: [
                    _buildUpdateItem(
                      width,
                      iconPath: 'assets/images/water_interruption.png',
                      title: 'Water Supply Interruption in Brgy. Maura',
                      category: 'Public Service',
                      time: '45m Ago',
                      comments: '51',
                      likes: '192',
                      accentColor: const Color(0xFF60A5FA),
                    ),
                    _buildUpdateItem(
                      width,
                      iconPath: 'assets/images/fire.png',
                      title: 'Fire Out beside Florida Terminal',
                      category: 'Public Service',
                      time: '1d',
                      comments: '41',
                      likes: '180',
                      accentColor: const Color(0xFFEF4444),
                    ),
                    _buildUpdateItem(
                      width,
                      iconPath: 'assets/images/innaguration.png',
                      title: 'New Barangay Health Center Inauguration',
                      category: 'Development',
                      time: 'April 13',
                      comments: '12',
                      likes: '86',
                      accentColor: const Color(0xFF22C55E),
                    ),
                    _buildUpdateItem(
                      width,
                      iconPath: 'assets/images/events.png',
                      title: 'Assembly meeting for Public Market Rehab...',
                      category: 'Event',
                      time: '',
                      comments: '2',
                      likes: '53',
                      accentColor: const Color(0xFF60A5FA),
                    ),

                    _buildUpdateItem(
                      width,
                      iconPath: 'assets/images/fire.png',
                      title: 'Extra Item 1',
                      category: 'Public Service',
                      time: 'Now',
                      comments: '10',
                      likes: '50',
                      accentColor: const Color(0xFFEF4444),
                    ),
                    _buildUpdateItem(
                      width,
                      iconPath: 'assets/images/fire.png',
                      title: 'Extra Item 2',
                      category: 'Public Service',
                      time: 'Now',
                      comments: '10',
                      likes: '50',
                      accentColor: const Color(0xFFEF4444),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpdateItem(
    double width, {
    required String iconPath,
    required String title,
    required String category,
    required String time,
    required String comments,
    required String likes,
    required Color accentColor,
    bool isLast = false,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: isLast ? 0 : width * 0.018),
      padding: EdgeInsets.symmetric(
        horizontal: width * 0.015,
        vertical: width * 0.018,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isLast ? Colors.transparent : const Color(0xFFF1F5F9),
            width: 1,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: width * 0.08,
            height: width * 0.08,
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(width * 0.022),
              border: Border.all(color: accentColor.withOpacity(0.5)),
            ),
            alignment: Alignment.center,
            child: Image.asset(
              iconPath,
              width: width * 0.045,
              height: width * 0.045,
            ),
          ),
          SizedBox(width: width * 0.022),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: width * 0.040,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF374151),
                    height: 1.1,
                  ),
                ),
                SizedBox(height: width * 0.008),
                Text(
                  time.isEmpty ? category : '$category • $time',
                  style: TextStyle(
                    fontSize: width * 0.028,
                    color: const Color(0xFF9CA3AF),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: width * 0.015),
          Padding(
            padding: EdgeInsets.only(top: width * 0.018),
            child: Row(
              children: [
                Icon(
                  Icons.chat_bubble,
                  size: width * 0.03,
                  color: const Color(0xFF9CA3AF),
                ),
                SizedBox(width: width * 0.006),
                Text(
                  comments,
                  style: TextStyle(
                    fontSize: width * 0.028,
                    color: const Color(0xFF9CA3AF),
                  ),
                ),
                SizedBox(width: width * 0.02),
                Icon(
                  Icons.thumb_up,
                  size: width * 0.03,
                  color: const Color(0xFF9CA3AF),
                ),
                SizedBox(width: width * 0.006),
                Text(
                  likes,
                  style: TextStyle(
                    fontSize: width * 0.028,
                    color: const Color(0xFF9CA3AF),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsSection(double width) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: width * 0.04),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(width * 0.03),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(width * 0.04),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quick Action',
              style: TextStyle(
                color: AppColors.primaryBlue,
                fontSize: width * 0.047,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: width * 0.015),
            Row(
              children: [
                Expanded(
                  child: _buildQuickCard(
                    width,
                    iconPath: 'assets/images/customer.png',
                    title: 'Chat with Agent',
                    subtitle: 'Talk to an LGU support agent',
                  ),
                ),
                SizedBox(width: width * 0.025),
                Expanded(
                  child: _buildQuickCard(
                    width,
                    iconPath: 'assets/images/report.png',
                    title: 'Report Issue',
                    subtitle: 'Report problem in your area',
                  ),
                ),
              ],
            ),
            SizedBox(height: width * 0.025),
            Row(
              children: [
                Expanded(
                  child: _buildQuickCard(
                    width,
                    iconPath: 'assets/images/feedback.png',
                    title: 'Feedback',
                    subtitle: 'Share your experience',
                  ),
                ),
                SizedBox(width: width * 0.025),
                Expanded(
                  child: _buildQuickCard(
                    width,
                    iconPath: 'assets/images/trends.png',
                    title: 'See Trends',
                    subtitle: 'View reports and insights',
                  ),
                ),
              ],
            ),
            SizedBox(height: width * 0.025),
            Row(
              children: [
                Expanded(
                  child: _buildQuickCard(
                    width,
                    iconPath: 'assets/images/suggest.png',
                    title: 'Suggestion',
                    subtitle: 'Share ideas for better services',
                  ),
                ),
                SizedBox(width: width * 0.025),
                Expanded(
                  child: _buildQuickCard(
                    width,
                    iconPath: 'assets/images/events.png',
                    title: 'Events',
                    subtitle: 'See upcoming local activities',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickCard(
    double width, {
    required String iconPath,
    required String title,
    required String subtitle,
  }) {
    final iconSize = width * 0.10;

    return GestureDetector(
      onTap: () {},
      child: Container(
        height: width * 0.22, // ✅ fixed rectangle
        padding: EdgeInsets.symmetric(
          horizontal: width * 0.028,
          vertical: width * 0.025,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(width * 0.03),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            /// 🔥 CENTERED ICON
            Center(
              child: Container(
                width: iconSize,
                height: iconSize,
                decoration: BoxDecoration(
                  color: const Color(0xFFE0ECFF),
                  borderRadius: BorderRadius.circular(width * 0.025),
                ),
                alignment: Alignment.center,
                child: SizedBox(
                  width: iconSize * 0.6,
                  height: iconSize * 0.6,
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: Image.asset(iconPath),
                  ),
                ),
              ),
            ),

            SizedBox(width: width * 0.025),

            /// 🔥 TEXT (TUNED — NO OVERFLOW)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: width * 0.030, // 🔥 reduced slightly
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF111827),
                      height: 1.2,
                    ),
                  ),
                  SizedBox(height: width * 0.006),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: width * 0.022, // 🔥 reduced to fit
                      color: const Color(0xFF6B7280),
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(width: width * 0.01),

            /// ARROW
            Icon(
              Icons.arrow_forward_ios,
              size: width * 0.03,
              color: const Color(0xFF9CA3AF),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNav(double width) {
    final iconSize = width * 0.065;
    final navColor = const Color(0xFF60A5FA);

    Widget buildIcon(String path) {
      return SizedBox(
        width: iconSize,
        height: iconSize,
        child: ColorFiltered(
          colorFilter: ColorFilter.mode(navColor, BlendMode.srcIn),
          child: Image.asset(path),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        elevation: 0,
        currentIndex: 0,
        selectedItemColor: navColor,
        unselectedItemColor: navColor,
        selectedFontSize: width * 0.028,
        unselectedFontSize: width * 0.028,
        items: [
          BottomNavigationBarItem(
            icon: buildIcon('assets/images/home.png'),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: buildIcon('assets/images/my_reports.png'), // ✅ fixed
            label: 'My Reports',
          ),
          BottomNavigationBarItem(
            icon: buildIcon('assets/images/news_feed.png'), // ✅ fixed
            label: 'NewsFeed',
          ),
          BottomNavigationBarItem(
            icon: buildIcon('assets/images/emergency.png'), // ✅ fixed
            label: 'Emergency',
          ),
          BottomNavigationBarItem(
            icon: buildIcon('assets/images/settings.png'),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
