import 'dart:async';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math' as math;

// ── Model ─────────────────────────────────────────────────────────────────────
class AppNotification {
  final String? id;
  final IconData icon;
  final String title;
  final String subtitle;
  final DateTime time;
  final Color color;
  final String type;

  /// The user who performed the action (like/comment/reply). Null for
  /// system/self notifications and staff-actor activity.
  final String? actorId;

  /// A ready-to-render, full public URL to the actor's profile photo. Null
  /// unless the notification was caused by another user's action. When present
  /// it replaces the leading icon with that person's photo.
  final String? actorPhotoUrl;

  /// The community post this notification refers to (likes / comments / replies).
  /// Null for notifications with no post context. Lets a tap jump to that post.
  final String? postId;

  AppNotification({
    this.id,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.time,
    required this.color,
    this.type = 'general',
    this.actorId,
    this.actorPhotoUrl,
    this.postId,
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
      icon: _iconForType(row['type'] as String? ?? 'general'),
      title: row['title'] as String,
      subtitle: row['subtitle'] as String,
      time: DateTime.parse(row['created_at'] as String),
      color: Color((row['color_value'] as int)),
      type: row['type'] as String? ?? 'general',
      actorId: row['actor_id'] as String?,
      actorPhotoUrl: row['actor_photo_url'] as String?,
      postId: row['post_id'] as String?,
    );
  }

  /// Maps a notification `type` to a constant icon. Using const icons (instead
  /// of building IconData from a stored code) is what lets Flutter tree-shake
  /// the icon font, so the release build works without --no-tree-shake-icons.
  static IconData _iconForType(String type) {
    switch (type) {
      case 'post_like':
        return Icons.favorite_rounded;
      case 'post_comment':
        return Icons.mode_comment_rounded;
      case 'comment_reply':
        return Icons.reply_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }
}

// ── Service ───────────────────────────────────────────────────────────────────
class NotificationService {
  static List<AppNotification> notifications = [];

  /// Live badge count. Every bell listens to this via [ValueListenableBuilder],
  /// so the badge updates the instant a notification is loaded / added /
  /// removed / cleared — no navigation or manual setState needed, and it can
  /// never drift negative because it's always exactly the list length.
  static final ValueNotifier<int> unread = ValueNotifier<int>(0);

  /// Keep [unread] in lock-step with the backing list. Called after every
  /// mutation below.
  static void _sync() => unread.value = notifications.length;

  static SupabaseClient get _db => Supabase.instance.client;
  static String? get _uid => _db.auth.currentUser?.id;

  // ── Local (phone) notifications ────────────────────────────────────────────
  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  static bool _localReady = false;

  /// Initialise the local-notifications plugin once and request the runtime
  /// permission (required on Android 13+ and on iOS).
  static Future<void> _ensureLocalReady() async {
    if (_localReady) return;
    const init = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      ),
    );
    await _local.initialize(init);

    // Android 13+ (API 33) POST_NOTIFICATIONS runtime permission.
    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();

    _localReady = true;
  }

  /// Mirror an in-app notification to the device's notification tray so the
  /// user is notified on the phone as well as inside the app.
  static Future<void> _showOnPhone(AppNotification n) async {
    try {
      await _ensureLocalReady();
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'general_channel',
          'Notifications',
          channelDescription: 'Aparri app notifications',
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(),
      );
      await _local.show(
        n.title.hashCode & 0x7fffffff, // stable-ish id per title
        n.title,
        n.subtitle,
        details,
      );
    } catch (e) {
      debugPrint('NotificationService._showOnPhone error: $e');
    }
  }

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
      _sync();
    } catch (e) {
      debugPrint('NotificationService.load error: $e');
    }
  }

  static Future<bool> add(AppNotification n) async {
    final uid = _uid;
    if (uid == null) return false;
    try {
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
      final row = await _db
          .from('notifications')
          .insert({
            'user_id': uid,
            'icon_code': n.icon.codePoint,
            'title': n.title,
            'subtitle': n.subtitle,
            'color_value': n.color.toARGB32(),
            'type': n.type,
            'is_approved': true,
          })
          .select()
          .single();
      notifications.insert(0, AppNotification.fromRow(row));
      _sync();
      await _showOnPhone(n); // mirror to the phone's notification tray
      debugPrint(
        'NotificationService: inserted "${n.title}" (type: ${n.type})',
      );
      return true;
    } catch (e) {
      debugPrint('NotificationService.add error: $e');
      return false;
    }
  }

  static Future<void> remove(AppNotification n) async {
    if (n.id == null) return;
    try {
      await _db.from('notifications').delete().eq('id', n.id!);
      notifications.removeWhere((x) => x.id == n.id);
      _sync();
    } catch (e) {
      debugPrint('NotificationService.remove error: $e');
    }
  }

  static Future<void> clearAll() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _db.from('notifications').delete().eq('user_id', uid);
      notifications.clear();
      _sync();
    } catch (e) {
      debugPrint('NotificationService.clearAll error: $e');
    }
  }

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

  static int get count => notifications.length;
}

/// Routes a tap on a citizen notification. Only actionable notifications
/// navigate; everything else is informational and does nothing.
///
///  • `verification_reminder` ("please verify your account") → opens the
///    verification flow, but ONLY for a user who still needs it. A verified or
///    already-pending (submitted, awaiting review) user has nothing to open, so
///    tapping does nothing.
///  • social activity (`post_like` / `post_comment` / `comment_reply` /
///    `comment_like`) → opens the community feed, jumping to the post when its
///    id is known; anything about a comment opens that post's comment thread.
///  • `verification_submitted` ("we've received your ID"), the verification-
///    approved / "you're verified" notice, LGU broadcasts, staff messages and
///    admin responses (`general`) → informational, no navigation.
///
/// The caller closes the notification sheet before calling this.
void routeCitizenNotificationTap(
  BuildContext context,
  AppNotification n, {
  required String username,
  required bool isVerified,
  required bool isPending,
  required void Function({String? postId, bool openComments}) onOpenNewsFeed,
}) {
  switch (n.type) {
    case 'verification_reminder':
      if (isVerified || isPending) return; // nothing to do → stays on home
      Navigator.pushNamed(context, '/verification', arguments: username);
      break;
    case 'post_like':
    case 'post_comment':
    case 'comment_reply':
    case 'comment_like':
      // Anything about a comment (comment/reply/comment-like) opens the post's
      // thread; a post like just jumps to the post.
      onOpenNewsFeed(
        postId: n.postId,
        openComments: n.type != 'post_like',
      );
      break;
    default:
      break;
  }
}

// ── Swipeable Notification Item ───────────────────────────────────────────────
//
// Behaviour contract:
//   • Drag left  → card slides, trash button grows + fades in from right
//   • Slow drag  → on release, elastic snap-back to origin
//   • Fast drag (velocity > threshold) OR drag > 35% width → slide off & delete
//   • Tap trash  → slide off & delete
//   • External   → slideOut(force: true) lets Clear-All drive it
//
class _AnimatedNotifItem extends StatefulWidget {
  final double width;
  final AppNotification notification;
  final bool enabled; // false while Clear-All is running
  final VoidCallback onDelete; // called after exit animation completes
  final VoidCallback? onTap; // fired when a closed card is tapped

  const _AnimatedNotifItem({
    super.key,
    required this.width,
    required this.notification,
    required this.onDelete,
    this.onTap,
    this.enabled = true,
  });

  @override
  State<_AnimatedNotifItem> createState() => _AnimatedNotifItemState();
}

class _AnimatedNotifItemState extends State<_AnimatedNotifItem>
    with TickerProviderStateMixin {
  // Slides the card fully off-screen, then fires onDelete()
  late final AnimationController _exitCtrl;
  // Eases the card to a resting offset (the open detent, or back to closed)
  late final AnimationController _settleCtrl;

  double _offset = 0; // current translate-X (always <= 0)
  double _exitOrigin = 0; // _offset captured when exit begins
  double _settleFrom = 0; // _offset captured when a settle begins
  double _settleTo = 0; // settle target offset
  Curve _settleCurve = Curves.easeOutCubic;

  bool _deleted = false; // exit animation started
  bool _open = false; // currently resting at the revealed detent
  bool _silentExit = false; // exit with NO trash panel (Clear-All cascade)

  // ── Geometry ─────────────────────────────────────────────────────────────

  // How far the card slides left to fully reveal the trash, then STOP.
  double get _openOffset => -widget.width * 0.22;

  // Hard left bound while dragging (lets the user pull past the detent to
  // trigger a "slide-again" delete).
  double get _maxDrag => -widget.width * 0.55;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    _exitCtrl =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 300),
          )
          ..addListener(_onExitTick)
          ..addStatusListener((s) {
            if (s == AnimationStatus.completed && mounted) widget.onDelete();
          });

    _settleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..addListener(_onSettleTick);
  }

  @override
  void dispose() {
    _exitCtrl.dispose();
    _settleCtrl.dispose();
    super.dispose();
  }

  // ── Animation ticks ──────────────────────────────────────────────────────

  void _onExitTick() {
    if (!mounted) return;
    // Clear-All exits glide on a gentler curve and travel a shorter distance
    // (a fade finishes the disappearance), so the motion reads much softer
    // than a hard shoot-off-screen.
    final curve = _silentExit ? Curves.easeInOutCubic : Curves.easeInCubic;
    final t = curve.transform(_exitCtrl.value);
    final target = _silentExit ? -widget.width * 0.6 : -(widget.width + 80);
    setState(() => _offset = _exitOrigin + (target - _exitOrigin) * t);
  }

  void _onSettleTick() {
    if (!mounted) return;
    final t = _settleCurve.transform(_settleCtrl.value.clamp(0.0, 1.0));
    setState(() => _offset = _settleFrom + (_settleTo - _settleFrom) * t);
  }

  // ── Internal helpers ───────────────────────────────────────────────────────

  void _settleTowards(
    double target, {
    Curve curve = Curves.easeOutCubic,
    int ms = 300,
  }) {
    if (_deleted) return;
    _settleCtrl.stop();
    _settleFrom = _offset;
    _settleTo = target;
    _settleCurve = curve;
    _settleCtrl
      ..duration = Duration(milliseconds: ms)
      ..forward(from: 0);
  }

  void _startExit() {
    if (_deleted) return;
    _deleted = true;
    _settleCtrl.stop();
    _exitOrigin = _offset;
    _exitCtrl.forward(from: 0);
  }

  // ── Public API (used by Clear-All in parent) ───────────────────────────────

  /// Drive the exit/delete animation from outside (Clear-All cascade).
  void slideOut({bool force = false}) {
    if (_deleted) return;
    // Clear-All passes force:true — peel the card away with no trash panel.
    if (force) _silentExit = true;
    _startExit();
  }

  // ── Gesture handlers ───────────────────────────────────────────────────────

  void _onDragUpdate(DragUpdateDetails d) {
    if (_deleted || !widget.enabled) return;
    _settleCtrl.stop(); // re-grab interrupts any in-flight settle
    setState(() {
      _offset = (_offset + d.delta.dx).clamp(_maxDrag, 0.0);
    });
  }

  void _onDragEnd(DragEndDetails d) {
    if (_deleted || !widget.enabled) return;
    final w = widget.width;
    final vx = d.velocity.pixelsPerSecond.dx;

    if (!_open) {
      // From CLOSED: either reveal-and-stop, or snap back home.
      final shouldOpen = _offset <= -w * 0.08 || vx < -250;
      if (shouldOpen) {
        _open = true;
        _settleTowards(_openOffset, curve: Curves.easeOutCubic, ms: 280);
      } else {
        _settleTowards(0, curve: Curves.elasticOut, ms: 460);
      }
    } else {
      // From OPEN: sliding further (or a left flick) deletes; dragging back
      // closes; anything else re-settles at the detent.
      final deleteByDrag = _offset < _openOffset - w * 0.12 || vx < -650;
      final closeByDrag = _offset > -w * 0.11 || vx > 600;
      if (deleteByDrag) {
        _startExit();
      } else if (closeByDrag) {
        _open = false;
        _settleTowards(0, curve: Curves.easeOutCubic, ms: 260);
      } else {
        _settleTowards(_openOffset, curve: Curves.easeOutCubic, ms: 220);
      }
    }
  }

  // Tapping the visible card closes it if open, otherwise acts on it.
  void _onTapCard() {
    if (_deleted) return;
    if (_open) {
      _open = false;
      _settleTowards(0, curve: Curves.easeOutCubic, ms: 260);
    } else {
      widget.onTap?.call();
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final w = widget.width;
    final regionW = -_openOffset; // width of the revealed trash area
    final reveal = (-_offset / regionW).clamp(0.0, 1.0);

    // The card stays fully rounded while it sits closed. As soon as it
    // starts opening, its RIGHT corners straighten so it meets the red
    // panel with a clean flush seam (no rounded gap, no red peeking).
    final rightR = (18.0 * (1.0 - reveal / 0.15)).clamp(0.0, 18.0);
    final cardRadius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      bottomLeft: const Radius.circular(18),
      topRight: Radius.circular(rightR),
      bottomRight: Radius.circular(rightR),
    );

    // During a Clear-All exit the card also fades out, so the slide and the
    // height-collapse blend into one soft motion instead of a hard slide.
    final exitFade = _silentExit
        ? (1.0 - _exitCtrl.value / 0.9).clamp(0.0, 1.0)
        : 1.0;

    return Padding(
      // Vertical gap between rows lives out here so the card itself can be
      // cleanly clipped (the trash never spills outside the row).
      padding: EdgeInsets.only(bottom: w * 0.025),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            // ── Red delete panel: pinned right, fills the card height ───────
            Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              width: regionW,
              child: IgnorePointer(
                ignoring: !_open || _deleted,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _startExit, // tap trash → slide out + delete
                  child: Opacity(
                    opacity: _silentExit ? 0.0 : reveal,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Color.lerp(
                          Colors.red.shade300,
                          Colors.red.shade600,
                          reveal,
                        ),
                        // Straight on the left (flush with the card),
                        // rounded on the right to match the row's corners.
                        borderRadius: const BorderRadius.only(
                          topRight: Radius.circular(18),
                          bottomRight: Radius.circular(18),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Transform.scale(
                        scale: 0.7 + 0.3 * reveal,
                        child: Image.asset(
                          'assets/images/trash.webp',
                          width: w * 0.07,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── Sliding notification card ───────────────────────────────────
            // Transform is the PARENT of the gesture detector so the card's
            // hit-test area travels with it. If the detector wrapped the
            // Transform instead, it would keep its full-width bounds and keep
            // swallowing taps meant for the trash panel sitting behind it.
            Transform.translate(
              offset: Offset(_offset, 0),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _onTapCard,
                onHorizontalDragUpdate: _onDragUpdate,
                onHorizontalDragEnd: _onDragEnd,
                child: Opacity(
                  opacity: exitFade,
                  child: _NotifItem(
                    width: w,
                    notification: widget.notification,
                    spaced: false, // gap is handled by the outer Padding
                    borderRadius: cardRadius,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── NotificationPopup ─────────────────────────────────────────────────────────

class NotificationPopup extends StatefulWidget {
  final double width;
  final void Function(AppNotification notification)? onTap;
  const NotificationPopup({super.key, required this.width, this.onTap});

  @override
  State<NotificationPopup> createState() => _NotificationPopupState();
}

class _NotificationPopupState extends State<NotificationPopup> {
  static const double _kMaxSizingWidth = 420;

  // Duration for the height-collapse after a card slides out
  static const Duration _kCollapseD = Duration(milliseconds: 240);

  // Delay between each card during Clear-All stagger
  static const Duration _kStagger = Duration(milliseconds: 60);

  bool _loading = true;
  bool _clearingAll = false;

  // Cached effective layout width — set in build(), safe to read in callbacks
  // because every callback is triggered by user interaction (post-first-build).
  double _w = 0;

  final GlobalKey<AnimatedListState> _listKey = GlobalKey();
  final List<AppNotification> _notifications = [];
  final List<GlobalKey<_AnimatedNotifItemState>> _itemKeys = [];

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    NotificationService.load().then((_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _notifications
          ..clear()
          ..addAll(NotificationService.notifications);
        _itemKeys
          ..clear()
          ..addAll(List.generate(_notifications.length, (_) => GlobalKey()));
      });
    });
  }

  // ── Removal helpers ────────────────────────────────────────────────────────

  /// Removes [target] from local list + AnimatedList + DB.
  /// Uses ID-lookup (not index) so concurrent deletions can't corrupt state.
  void _removeNotification(AppNotification target) {
    final idx = _notifications.indexWhere(
      (n) => target.id != null ? n.id == target.id : identical(n, target),
    );
    if (idx < 0) return;

    final removed = _notifications.removeAt(idx);
    _itemKeys.removeAt(idx);

    // Collapse the freed vertical space with a smooth height animation.
    // We render the already-offscreen card as a size placeholder so Flutter
    // knows the natural height to collapse from.
    _listKey.currentState?.removeItem(
      idx,
      (_, anim) => SizeTransition(
        sizeFactor: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        axisAlignment: -1, // top-anchored collapse (bottom shrinks up)
        child: IgnorePointer(
          child: Transform.translate(
            offset: Offset(-_w * 2, 0), // already off-screen
            child: _NotifItem(width: _w, notification: removed),
          ),
        ),
      ),
      duration: _kCollapseD,
    );

    // Persist to DB (fire-and-forget)
    NotificationService.remove(removed);

    // Rebuild: updates the empty-state overlay; resets _clearingAll when done
    if (mounted) {
      setState(() {
        if (_notifications.isEmpty) _clearingAll = false;
      });
    }
  }

  // ── Clear All ──────────────────────────────────────────────────────────────

  Future<void> _clearAll() async {
    if (_clearingAll || _notifications.isEmpty) return;
    setState(() => _clearingAll = true);

    final count = _itemKeys.length;

    // Snapshot key list before any mutations (removals shift the live list)
    final keys = List<GlobalKey<_AnimatedNotifItemState>>.from(_itemKeys);

    // Stagger slide-outs bottom → top so notifications peel away sequentially
    for (int i = count - 1; i >= 0; i--) {
      if (!mounted) break;
      keys[i].currentState?.slideOut(force: true);
      if (i > 0) await Future.delayed(_kStagger);
    }

    // Failsafe: reset flag even if some onDelete callbacks never fire
    // (e.g. widget disposed mid-animation, or a state was null)
    final fallback = Duration(
      milliseconds: _kStagger.inMilliseconds * count + 900,
    );
    await Future.delayed(fallback);
    if (mounted && _clearingAll) setState(() => _clearingAll = false);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final sz = MediaQuery.of(context).size;
    final w = sz.width < _kMaxSizingWidth ? sz.width : _kMaxSizingWidth;
    _w = w; // cache for callbacks

    final popupWidth = w * 0.90;
    final double maxH = sz.height * 0.85;
    final double minH = math.min(360.0, maxH);
    final double popupHeight = (w * 1.1).clamp(minH, maxH);

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 250),
      tween: Tween(begin: 0, end: 1),
      builder: (context, v, _) {
        return Stack(
          children: [
            // ── Blurred / dimmed backdrop ────────────────────────────────
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8 * v, sigmaY: 8 * v),
                child: Container(color: Colors.black.withValues(alpha: .2 * v)),
              ),
            ),

            // ── Frosted-glass panel ──────────────────────────────────────
            Center(
              child: GestureDetector(
                onTap: () {}, // absorb taps so backdrop doesn't close
                child: Material(
                  color: Colors.transparent,
                  child: Opacity(
                    opacity: v,
                    child: Transform.scale(
                      scale: 0.95 + 0.05 * v,
                      child: Container(
                        width: popupWidth,
                        height: popupHeight,
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
                                  onTap: _clearingAll ? null : _clearAll,
                                  child: AnimatedOpacity(
                                    duration: const Duration(milliseconds: 200),
                                    opacity: _clearingAll ? 0.35 : 1.0,
                                    child: Text(
                                      "Clear All",
                                      style: TextStyle(
                                        fontSize: w * 0.032,
                                        color: Colors.blue,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: w * 0.04),

                            // ── List area ─────────────────────────────────
                            Expanded(
                              child: _loading
                                  ? const Center(
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Stack(
                                      children: [
                                        // AnimatedList: always present when
                                        // loaded; manages its own item-level
                                        // enter/exit animations.
                                        AnimatedList(
                                          key: _listKey,
                                          initialItemCount:
                                              _notifications.length,
                                          padding: EdgeInsets.zero,
                                          itemBuilder: (ctx, idx, anim) {
                                            if (idx >= _notifications.length) {
                                              return const SizedBox.shrink();
                                            }
                                            final n = _notifications[idx];
                                            final key = _itemKeys[idx];
                                            return SizeTransition(
                                              sizeFactor: CurvedAnimation(
                                                parent: anim,
                                                curve: Curves.easeOut,
                                              ),
                                              axisAlignment: -1,
                                              child: _AnimatedNotifItem(
                                                key: key,
                                                width: w,
                                                notification: n,
                                                enabled: !_clearingAll,
                                                onTap: () =>
                                                    widget.onTap?.call(n),
                                                onDelete: () =>
                                                    _removeNotification(n),
                                              ),
                                            );
                                          },
                                        ),

                                        // Empty-state overlay fades in once
                                        // all notifications are gone.
                                        // Hidden during Clear-All so it
                                        // doesn't flash during the cascade.
                                        AnimatedOpacity(
                                          duration: const Duration(
                                            milliseconds: 400,
                                          ),
                                          opacity:
                                              _notifications.isEmpty &&
                                                  !_clearingAll
                                              ? 1.0
                                              : 0.0,
                                          child: IgnorePointer(
                                            child: Center(
                                              child: Text(
                                                "No notifications",
                                                style: TextStyle(
                                                  color: Colors.grey,
                                                  fontSize: w * 0.035,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
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

// ── Single notification item (visual only, no gesture logic) ──────────────────
class _NotifItem extends StatelessWidget {
  final double width;
  final AppNotification notification;
  final bool spaced; // include the bottom gap margin
  final BorderRadius? borderRadius; // null -> fully rounded (r = 18)
  const _NotifItem({
    required this.width,
    required this.notification,
    this.spaced = true,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final w = width;

    // Current icon leading — kept unchanged for every notification without an
    // actor photo (reports, verifications, staff activity, old rows, …).
    final Widget iconLeading = Container(
      padding: EdgeInsets.all(w * 0.025),
      decoration: BoxDecoration(
        color: n.color.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(n.icon, color: n.color, size: w * 0.055),
    );

    // When the notification carries a real actor photo URL, show that person's
    // photo instead of the icon. Same footprint as the icon container
    // (icon w*0.055 + padding w*0.025 on each side = w*0.105) so the row layout
    // doesn't shift. A broken/unreachable URL falls back to [iconLeading].
    final String? photoUrl = n.actorPhotoUrl;
    final Widget leading =
        (photoUrl != null && photoUrl.isNotEmpty)
        ? ClipOval(
            child: SizedBox(
              width: w * 0.105,
              height: w * 0.105,
              child: CachedNetworkImage(
                imageUrl: photoUrl,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => iconLeading,
              ),
            ),
          )
        : iconLeading;

    return Container(
      margin: spaced ? EdgeInsets.only(bottom: w * 0.025) : EdgeInsets.zero,
      padding: EdgeInsets.all(w * 0.03),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .65),
        borderRadius: borderRadius ?? BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          leading,
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
