import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppNotification {
  final IconData icon;
  final String title;
  final String subtitle;
  final String time;
  final Color color;

  AppNotification({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.time,
    required this.color,
  });

  Map<String, dynamic> toJson() => {
    'icon': icon.codePoint,
    'title': title,
    'subtitle': subtitle,
    'time': time,
    'color': color.value,
  };

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      icon: IconData(json['icon'], fontFamily: 'MaterialIcons'),
      title: json['title'],
      subtitle: json['subtitle'],
      time: json['time'],
      color: Color(json['color']),
    );
  }
}

class NotificationService {
  static List<AppNotification> notifications = [];

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('notifications');

    if (data != null) {
      List decoded = jsonDecode(data);
      notifications = decoded.map((e) => AppNotification.fromJson(e)).toList();
    }
  }

  static Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(notifications.map((e) => e.toJson()).toList());
    await prefs.setString('notifications', data);
  }

  static Future<void> add(AppNotification notification) async {
    notifications.insert(0, notification);
    await save();
  }

  static Future<void> clearAll() async {
    notifications.clear();
    await save();
  }

  static Future<void> remove(int index) async {
    notifications.removeAt(index);
    await save();
  }

  static int get count => notifications.length;
}

class NotificationPopup extends StatefulWidget {
  final double width;

  const NotificationPopup({super.key, required this.width});

  @override
  State<NotificationPopup> createState() => _NotificationPopupState();
}

class _NotificationPopupState extends State<NotificationPopup> {
  @override
  void initState() {
    super.initState();
    NotificationService.load().then((_) {
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = widget.width;

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 250),
      tween: Tween(begin: 0, end: 1),
      builder: (context, value, child) {
        return Stack(
          children: [
            /// BACKDROP
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8 * value, sigmaY: 8 * value),
                child: Container(color: Colors.black.withOpacity(0.2 * value)),
              ),
            ),

            /// POPUP
            Center(
              child: GestureDetector(
                onTap: () {},
                child: Material(
                  color: Colors.transparent,
                  child: Opacity(
                    opacity: value,
                    child: Transform.scale(
                      scale: 0.95 + (0.05 * value),
                      child: Container(
                        width: width * 0.90,
                        height: width * 1.1,
                        padding: EdgeInsets.all(width * 0.045),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(28),
                          color: Colors.white.withOpacity(0.75),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.4),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.15),
                              blurRadius: 25,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),

                        child: Column(
                          children: [
                            /// HEADER
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "Notifications",
                                  style: TextStyle(
                                    fontSize: width * 0.045,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () async {
                                    await NotificationService.clearAll();
                                    setState(() {});
                                  },
                                  child: Text(
                                    "Clear All",
                                    style: TextStyle(
                                      fontSize: width * 0.032,
                                      color: Colors.blue,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            SizedBox(height: width * 0.04),

                            /// LIST
                            Expanded(
                              child: NotificationService.notifications.isEmpty
                                  ? Center(
                                      child: Text(
                                        "No notifications",
                                        style: TextStyle(
                                          color: Colors.grey,
                                          fontSize: width * 0.035,
                                        ),
                                      ),
                                    )
                                  : ListView(
                                      padding: EdgeInsets.zero,
                                      children: NotificationService
                                          .notifications
                                          .asMap()
                                          .entries
                                          .map((entry) {
                                            var n = entry.value;

                                            return Dismissible(
                                              key:
                                                  UniqueKey(), // 🔥 FIXED (no duplicate / stale keys)
                                              direction:
                                                  DismissDirection.endToStart,

                                              background: Container(
                                                alignment:
                                                    Alignment.centerRight,
                                                padding: EdgeInsets.only(
                                                  right: width * 0.05,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.red,
                                                  borderRadius:
                                                      BorderRadius.circular(18),
                                                ),
                                                child: Image.asset(
                                                  'assets/images/trash.png',
                                                  width: width * 0.06,
                                                ),
                                              ),

                                              onDismissed: (_) async {
                                                setState(() {
                                                  NotificationService
                                                      .notifications
                                                      .remove(
                                                        n,
                                                      ); // 🔥 remove by object
                                                });

                                                await NotificationService.save();
                                              },

                                              child: _item(
                                                width: width,
                                                icon: n.icon,
                                                title: n.title,
                                                subtitle: n.subtitle,
                                                time: n.time,
                                                color: n.color,
                                              ),
                                            );
                                          })
                                          .toList(),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _item({
    required double width,
    required IconData icon,
    required String title,
    required String subtitle,
    required String time,
    required Color color,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: width * 0.025),
      padding: EdgeInsets.all(width * 0.03),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.65),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(width * 0.025),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: width * 0.055),
          ),
          SizedBox(width: width * 0.025),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: width * 0.036,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: width * 0.029,
                    color: Colors.grey[700],
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  time,
                  style: TextStyle(fontSize: width * 0.027, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
