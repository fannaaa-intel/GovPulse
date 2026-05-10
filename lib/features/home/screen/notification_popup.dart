import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ── Model ─────────────────────────────────────────────────────────────────────
class AppNotification {
  final String? id;
  final IconData icon;
  final String title;
  final String subtitle;
  final DateTime time;
  final Color color;
  final String type;

  AppNotification({
    this.id,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.time,
    required this.color,
    this.type = 'general',
  });

  String formatTimeAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 60) return "Just now";
    if (diff.inMinutes < 60) return "${diff.inMinutes} min ago";
    if (diff.inHours < 24) return "${diff.inHours} hr ago";
    if (diff.inDays < 7) return "${diff.inDays} d ago";
    return "${t.day}/${t.month}/${t.year}";
  }

  factory AppNotification.fromRow(Map<String, dynamic> row) {
    return AppNotification(
      id: row['id'] as String?,
      icon: IconData(row['icon_code'] as int, fontFamily: 'MaterialIcons'),
      title: row['title'] as String,
      subtitle: row['subtitle'] as String,
      time: DateTime.parse(row['created_at'] as String),
      color: Color((row['color_value'] as int)),
      type: row['type'] as String? ?? 'general',
    );
  }
}

// ── Service ───────────────────────────────────────────────────────────────────
class NotificationService {
  static List<AppNotification> notifications = [];

  static SupabaseClient get _db => Supabase.instance.client;
  static String? get _uid => _db.auth.currentUser?.id;

  // Load all notifications for this user from Supabase
  static Future<void> load() async {
    final uid = _uid;
    if (uid == null) return;

    try {
      final rows = await _db
          .from('notifications')
          .select()
          .eq('user_id', uid)
          .order('created_at', ascending: false);

      notifications = (rows as List)
          .map((r) => AppNotification.fromRow(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('NotificationService.load error: $e');
    }
  }

  /// Insert a notification and add it to the in-memory list.
  /// Returns false if a non-general typed notification already exists
  /// (prevents duplicate reminders).
  static Future<bool> add(AppNotification n) async {
    final uid = _uid;
    if (uid == null) return false;

    try {
      // ── One-time guard for typed (non-general) notifications ──────────
      if (n.type != 'general') {
        final existing = await _db
            .from('notifications')
            .select('id')
            .eq('user_id', uid)
            .eq('type', n.type)
            .maybeSingle();

        if (existing != null) {
          debugPrint(
            'NotificationService: type "${n.type}" already exists, skipping.',
          );
          return false;
        }
      }

      // ── Insert row ────────────────────────────────────────────────────
      final row = await _db
          .from('notifications')
          .insert({
            'user_id': uid,
            'icon_code': n.icon.codePoint,
            'title': n.title,
            'subtitle': n.subtitle,
            'color_value': n.color.toARGB32(),
            'type': n.type,
            'is_approved': true, // ← ADD THIS
          })
          .select()
          .single();

      // ── Update in-memory list immediately ─────────────────────────────
      notifications.insert(0, AppNotification.fromRow(row));
      debugPrint(
        'NotificationService: inserted "${n.title}" (type: ${n.type})',
      );
      return true;
    } catch (e) {
      debugPrint('NotificationService.add error: $e');
      return false;
    }
  }

  // Delete a single notification
  static Future<void> remove(AppNotification n) async {
    if (n.id == null) return;
    try {
      await _db.from('notifications').delete().eq('id', n.id!);
      notifications.removeWhere((x) => x.id == n.id);
    } catch (e) {
      debugPrint('NotificationService.remove error: $e');
    }
  }

  // Delete all notifications for this user
  static Future<void> clearAll() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _db.from('notifications').delete().eq('user_id', uid);
      notifications.clear();
    } catch (e) {
      debugPrint('NotificationService.clearAll error: $e');
    }
  }

  // ── ADD THESE TWO METHODS HERE ────────────────────────────────────────────

  /// Admin sends a notification to a specific user
  static Future<bool> adminSend({
    required String targetUserId,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) async {
    try {
      await _db.from('notifications').insert({
        'user_id': targetUserId,
        'icon_code': icon.codePoint,
        'title': title,
        'subtitle': subtitle,
        'color_value': color.toARGB32(),
        'type': 'admin_broadcast',
        'is_approved': true,
        'sent_by': _uid,
      });
      return true;
    } catch (e) {
      debugPrint('adminSend error: $e');
      return false;
    }
  }

  /// Staff sends a notification — requires admin approval
  static Future<bool> staffSend({
    required String targetUserId,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) async {
    try {
      await _db.from('notifications').insert({
        'user_id': targetUserId,
        'icon_code': icon.codePoint,
        'title': title,
        'subtitle': subtitle,
        'color_value': color.toARGB32(),
        'type': 'staff_message',
        'is_approved': false,
        'sent_by': _uid,
      });
      return true;
    } catch (e) {
      debugPrint('staffSend error: $e');
      return false;
    }
  }

  static int get count => notifications.length; // ← this was already here
}

// ── UI ────────────────────────────────────────────────────────────────────────
class NotificationPopup extends StatefulWidget {
  final double width;
  const NotificationPopup({super.key, required this.width});

  @override
  State<NotificationPopup> createState() => _NotificationPopupState();
}

class _NotificationPopupState extends State<NotificationPopup> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // ✅ Always re-fetch from Supabase when popup opens
    NotificationService.load().then((_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.width;

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 250),
      tween: Tween(begin: 0, end: 1),
      builder: (context, value, _) {
        return Stack(
          children: [
            // ── Blur backdrop ─────────────────────────────────────────────
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8 * value, sigmaY: 8 * value),
                child: Container(
                  color: Colors.black.withValues(alpha: .2 * value),
                ),
              ),
            ),

            // ── Panel ─────────────────────────────────────────────────────
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
                        width: w * 0.90,
                        height: w * 1.1,
                        padding: EdgeInsets.all(w * 0.045),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(28),
                          color: Colors.white.withValues(alpha: .75),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: .4),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: .15),
                              blurRadius: 25,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            // ── Header ────────────────────────────────────
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "Notifications",
                                  style: TextStyle(
                                    fontSize: w * 0.045,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () async {
                                    await NotificationService.clearAll();
                                    if (mounted) setState(() {});
                                  },
                                  child: Text(
                                    "Clear All",
                                    style: TextStyle(
                                      fontSize: w * 0.032,
                                      color: Colors.blue,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: w * 0.04),

                            // ── List ──────────────────────────────────────
                            Expanded(
                              child: _loading
                                  ? const Center(
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : NotificationService.notifications.isEmpty
                                  ? Center(
                                      child: Text(
                                        "No notifications",
                                        style: TextStyle(
                                          color: Colors.grey,
                                          fontSize: w * 0.035,
                                        ),
                                      ),
                                    )
                                  : ListView.builder(
                                      padding: EdgeInsets.zero,
                                      itemCount: NotificationService
                                          .notifications
                                          .length,
                                      itemBuilder: (_, i) {
                                        final n = NotificationService
                                            .notifications[i];
                                        return Dismissible(
                                          key: ValueKey(n.id ?? i),
                                          direction:
                                              DismissDirection.endToStart,
                                          background: Container(
                                            alignment: Alignment.centerRight,
                                            padding: EdgeInsets.only(
                                              right: w * 0.05,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.red,
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                            ),
                                            child: Image.asset(
                                              'assets/images/trash.png',
                                              width: w * 0.06,
                                            ),
                                          ),
                                          onDismissed: (_) async {
                                            await NotificationService.remove(n);
                                            if (mounted) setState(() {});
                                          },
                                          child: _NotifItem(
                                            width: w,
                                            notification: n,
                                          ),
                                        );
                                      },
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
}

// ── Single notification item ──────────────────────────────────────────────────
class _NotifItem extends StatelessWidget {
  final double width;
  final AppNotification notification;
  const _NotifItem({required this.width, required this.notification});

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final w = width;

    return Container(
      margin: EdgeInsets.only(bottom: w * 0.025),
      padding: EdgeInsets.all(w * 0.03),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .65),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(w * 0.025),
            decoration: BoxDecoration(
              color: n.color.withValues(alpha: .15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(n.icon, color: n.color, size: w * 0.055),
          ),
          SizedBox(width: w * 0.025),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  n.title,
                  style: TextStyle(
                    fontSize: w * 0.036,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  n.subtitle,
                  style: TextStyle(
                    fontSize: w * 0.029,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  n.formatTimeAgo(n.time),
                  style: TextStyle(fontSize: w * 0.027, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
