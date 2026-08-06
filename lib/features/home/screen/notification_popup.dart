import 'dart:async';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math' as math;
import '../../../core/router/legacy_nav.dart';
import '../settings/my-submission/my_submissions_screen.dart'
    show MySubmissionsArgs, MySubmissionsScreen;
import '../my_report/my_reports_screen.dart' show ReportItem;

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

  /// Generic target id for deep-linking (currently a suggestion/feedback id on
  /// `suggestion_response` / `feedback_response` replies). Null when the column
  /// isn't migrated yet or the notification has no target.
  final String? referenceId;

  /// Whether the user has already opened this one (`read_at` is set).
  ///
  /// The badge counts UNREAD rows only, so tapping a notification retires it
  /// from the count while the row stays in the list — the same model the admin
  /// and staff bells use on this table. Before this existed the count was just
  /// the list length, so it never moved until a row was deleted.
  final bool read;

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
    this.referenceId,
    this.read = false,
  });

  AppNotification copyWith({bool? read}) => AppNotification(
        id: id,
        icon: icon,
        title: title,
        subtitle: subtitle,
        time: time,
        color: color,
        type: type,
        actorId: actorId,
        actorPhotoUrl: actorPhotoUrl,
        postId: postId,
        referenceId: referenceId,
        read: read ?? this.read,
      );

  String formatTimeAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 60) return "Just now";
    if (diff.inMinutes < 60) return "${diff.inMinutes} min ago";
    if (diff.inHours < 24) return "${diff.inHours} hr ago";
    if (diff.inDays < 7) return "${diff.inDays} d ago";
    return "${t.day}/${t.month}/${t.year}";
  }

  factory AppNotification.fromRow(Map<String, dynamic> row) {
    final type = _effectiveType(row);
    return AppNotification(
      id: row['id'] as String?,
      icon: _iconForType(type),
      title: row['title'] as String,
      subtitle: row['subtitle'] as String,
      time: DateTime.parse(row['created_at'] as String),
      color: Color((row['color_value'] as int)),
      type: type,
      actorId: row['actor_id'] as String?,
      actorPhotoUrl: row['actor_photo_url'] as String?,
      postId: _effectivePostId(row, type),
      referenceId: row['reference_id'] as String?,
      read: row['read_at'] != null,
    );
  }

  /// The social types this side routes, plus the admin/staff `topic` vocabulary
  /// for the same events. A citizen liking a staff-authored post (or vice
  /// versa) can be stamped with either set depending on which trigger fired, so
  /// both are accepted and folded onto the citizen names below. Mirrors
  /// StaffNotif._routable, which accepts both for the same reason.
  static const Map<String, String> _typeAliases = {
    'post_heart': 'post_like',
    'comment_heart': 'comment_like',
    'comment': 'post_comment',
  };

  static String _effectiveType(Map<String, dynamic> row) {
    final raw = (row['type'] as String?)?.trim() ?? 'general';
    return _typeAliases[raw] ?? raw;
  }

  /// The community post a social notification points at.
  ///
  /// Written to `reference_id` by every trigger this repo ships (see
  /// notification_deeplink_targets_*.sql); some live triggers instead stamp a
  /// `post_id` column that no migration here creates. Reading only `post_id`
  /// is why a like/comment tap opened the feed but never jumped or flashed —
  /// the id was always null. Read whichever the writer used.
  ///
  /// Restricted to social types on purpose: `reference_id` on a
  /// suggestion/feedback/report notification is a submission id, not a post,
  /// and must not be mistaken for one.
  ///
  /// The id may be a COMMENT id rather than a post id — the feed resolves that
  /// case itself (see _tryResolveCommentRef in news_feed_screen.dart).
  static String? _effectivePostId(Map<String, dynamic> row, String type) {
    final postId = (row['post_id'] as String?)?.trim();
    if (postId != null && postId.isNotEmpty) return postId;
    if (!_socialTypes.contains(type)) return null;
    final ref = (row['reference_id'] as String?)?.trim();
    return (ref != null && ref.isNotEmpty) ? ref : null;
  }

  /// Notification types whose target is a community post (after aliasing).
  static const Set<String> _socialTypes = {
    'post_like',
    'comment_like',
    'post_comment',
    'comment_reply',
  };

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
  /// removed / cleared / read — no navigation or manual setState needed, and it
  /// can never drift negative because it's always recomputed from the list.
  static final ValueNotifier<int> unread = ValueNotifier<int>(0);

  /// Keep [unread] in lock-step with the backing list. Called after every
  /// mutation below.
  ///
  /// Counts UNREAD rows, not the list length: a tapped notification stays in
  /// the list (the user may want to find it again) but must stop counting, or
  /// the badge sits there at 1 after the thing it pointed at has been opened.
  static void _sync() =>
      unread.value = notifications.where((n) => !n.read).length;

  static SupabaseClient get _db => Supabase.instance.client;
  static String? get _uid => _db.auth.currentUser?.id;

  // ── Live badge updates (Supabase Realtime) ─────────────────────────────────
  //
  // Without this the badge only refreshed when something in-app called load()
  // (opening the sheet, navigating back, a manual reload) — so a notification
  // arriving while the user just sat on the home page didn't bump the number
  // until they moved. This subscription watches the user's own rows in the
  // `notifications` table and reloads on every INSERT/DELETE, so the count
  // ticks up the instant one lands and back down when one is removed — even
  // from another device — with no navigation or manual refresh. Mirrors the
  // admin console's AdminNotifCenter.
  static RealtimeChannel? _channel;
  static String? _subscribedUid;

  /// Start the live subscription for the signed-in user. Call once the user is
  /// authenticated (see main.dart). Idempotent: no-ops when already live for the
  /// same user, and re-subscribes cleanly if a different user has signed in.
  static Future<void> startRealtime() async {
    final uid = _uid;
    if (uid == null) return;
    if (_channel != null && _subscribedUid == uid) return;
    if (_channel != null) stopRealtime(); // different user — drop the old channel
    _subscribedUid = uid;

    // Pull the current state immediately so the badge is correct the moment the
    // subscription comes up (Realtime only delivers changes from here on).
    await load();

    _channel = _db.channel('citizen-notifs-$uid')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'notifications',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: uid,
        ),
        // Any change to this user's rows → reload the list, which re-syncs
        // `unread` (== list length). Handles both increase and decrease.
        callback: (_) => load(),
      )
      ..subscribe();
  }

  /// Tear down on sign-out so the next session re-subscribes cleanly and the
  /// badge doesn't linger on the previous user's count.
  static void stopRealtime() {
    _channel?.unsubscribe();
    _channel = null;
    _subscribedUid = null;
    notifications = [];
    _sync();
  }

  // The device's notification tray is PushService's job, not this service's.
  // This class owns the in-app list + badge; a row inserted here reaches the
  // phone via push_on_notification → send-push → FCM. It deliberately keeps no
  // local-notifications plugin of its own — two independent things showing the
  // same tray notification is how the same alert ends up on screen twice.

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
      // NOT mirrored to the tray from here. This insert already fires the
      // push_on_notification trigger → send-push → FCM, which PushService shows
      // in the foreground — so showing a local copy too meant the same
      // notification twice. It also bypassed the user's push master-switch,
      // which send-push honours and a raw local .show() cannot.
      debugPrint(
        'NotificationService: inserted "${n.title}" (type: ${n.type})',
      );
      return true;
    } catch (e) {
      debugPrint('NotificationService.add error: $e');
      return false;
    }
  }

  /// Retires [n] from the badge count by stamping `read_at`.
  ///
  /// The local list is updated first and unconditionally, so the badge drops
  /// the moment the user taps even if the write is slow or refused — an
  /// unreachable database must not leave the count stuck on a notification the
  /// user has demonstrably seen. A realtime echo or the next [load] simply
  /// re-affirms the same state.
  ///
  /// Falls back to the shared `mark_notifications_read` RPC when a direct
  /// update is blocked by RLS, mirroring StaffNotifCenter.markAllRead.
  static Future<void> markRead(AppNotification n) async {
    final id = n.id;
    if (id == null || n.read) return;

    final idx = notifications.indexWhere((x) => x.id == id);
    if (idx >= 0) {
      notifications[idx] = notifications[idx].copyWith(read: true);
      _sync();
    }

    final nowIso = DateTime.now().toUtc().toIso8601String();
    try {
      await _db.from('notifications').update({'read_at': nowIso}).eq('id', id);
    } catch (e) {
      debugPrint('NotificationService.markRead direct update failed: $e');
      try {
        await _db.rpc('mark_notifications_read', params: {'p_topics': null});
      } catch (e2) {
        // Local state already reflects the tap; the badge stays correct for
        // this session and reconciles on the next successful write.
        debugPrint('NotificationService.markRead RPC fallback failed: $e2');
      }
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

  /// Unread count — what every badge shows. Kept in step with [unread]; the
  /// two must never disagree, so both are derived the same way.
  static int get count => unread.value;

  /// Total rows currently held, read or not. Only for callers that need the
  /// list size (empty-state checks), never for a badge.
  static int get total => notifications.length;
}

/// Reaction notification types. These navigate like any other, but never flash
/// their target: a heart is ambient acknowledgement, not work arriving, so
/// accenting a row for one would overstate it. Mirrors the admin/staff shells.
const Set<String> kHeartNotifTypes = {'post_like', 'comment_like'};

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
///  • `suggestion_response` / `feedback_response` (an LGU reply) → open My
///    Submissions on the matching tab and highlight the item (via referenceId).
///  • `report_decision` (a report status change) → open that report's detail
///    screen, fetched by referenceId.
///  • `chat` (a staff reply in the citizen's LGU conversation) → open the chat
///    screen. No id needed: a citizen has a single thread.
///  • `verification_submitted` ("we've received your ID"), the verification-
///    approved / "you're verified" notice, LGU broadcasts, staff messages and
///    other admin responses (`general`) → informational, no navigation.
///
/// The caller closes the notification sheet before calling this.
void routeCitizenNotificationTap(
  BuildContext context,
  AppNotification n, {
  required String username,
  required bool isVerified,
  required bool isPending,
  required void Function({String? postId, bool openComments, bool highlight})
      onOpenNewsFeed,
}) {
  switch (n.type) {
    case 'verification_reminder':
      if (isVerified || isPending) return; // nothing to do → stays on home
      pushLegacy(context, '/verification', arguments: username);
      break;
    case 'post_like':
    case 'post_comment':
    case 'comment_reply':
    case 'comment_like':
      // Anything about a comment (comment/reply/comment-like) opens the post's
      // thread; a post like just jumps to the post.
      final openComments = n.type != 'post_like';
      // The blue flash belongs to reactions, not to comments. A heart has
      // nowhere else to land, so the ring IS the destination. A comment or
      // reply opens the thread instead — and leaving a ring under the sheet
      // just means finding the post still lit up after closing it.
      onOpenNewsFeed(
        postId: n.postId,
        openComments: openComments,
        highlight: !openComments,
      );
      break;
    case 'suggestion_response':
      // LGU replied to a suggestion → open My Submissions on the Suggestions
      // tab and highlight the item (when its id is known / column migrated).
      // Skip if that screen is already open so we don't stack a duplicate.
      if (MySubmissionsScreen.isOpen) return;
      pushLegacy(
        context,
        '/my_submissions',
        arguments: MySubmissionsArgs(
          username: username,
          initialTab: 1,
          highlightId: n.referenceId,
        ),
      );
      break;
    case 'feedback_response':
      if (MySubmissionsScreen.isOpen) return;
      pushLegacy(
        context,
        '/my_submissions',
        arguments: MySubmissionsArgs(
          username: username,
          initialTab: 2,
          highlightId: n.referenceId,
        ),
      );
      break;
    case 'chat':
      // A staff reply landed. Unlike the staff console — where a staffer picks
      // one of many conversations — a citizen has exactly ONE LGU thread, held
      // by ChatService.I. So there's nothing to disambiguate and no id needed:
      // opening the chat screen IS landing on the message.
      pushLegacy(context, '/chat', arguments: username);
      break;
    case 'report_decision':
      // LGU changed a report's status → open that report's detail. Needs the
      // report id from reference_id (report_notification_deeplink.sql); older
      // rows without it fall through to no navigation.
      final reportId = n.referenceId;
      if (reportId != null && reportId.isNotEmpty) {
        _openReportFromNotification(context, reportId, username);
      }
      break;
    default:
      break;
  }
}

/// Fetches the owner's report by id and opens its detail screen. Best-effort —
/// a fetch failure (offline / RLS / deleted row) simply does nothing.
Future<void> _openReportFromNotification(
  BuildContext context,
  String reportId,
  String username,
) async {
  try {
    final row = await Supabase.instance.client
        .from('reports')
        .select('*, report_media(id)')
        .eq('id', reportId)
        .maybeSingle();
    if (row == null || !context.mounted) return;
    final item = ReportItem.fromMap(row);
    // Use the canonical /report_detail route: instant enter, fade-out exit,
    // NetworkWrapper — matching how the report detail opens everywhere else.
    pushLegacy(
      context,
      '/report_detail',
      arguments: {'report': item, 'username': username},
    );
  } catch (_) {
    // best-effort — no navigation on failure
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
                                  ? _NotifLoadingSkeleton(width: w)
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

// ── Loading skeleton ──────────────────────────────────────────────────────────
//
// Shown while notifications load, in place of a bare spinner, so the list area
// reads as "content is coming" and doesn't jump when the real cards land. A
// single shimmer band sweeps across a small stack of placeholder cards shaped
// like [_NotifItem].
class _NotifLoadingSkeleton extends StatefulWidget {
  final double width;
  const _NotifLoadingSkeleton({required this.width});

  @override
  State<_NotifLoadingSkeleton> createState() => _NotifLoadingSkeletonState();
}

class _NotifLoadingSkeletonState extends State<_NotifLoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const Color _base = Color(0xFFE7EBF1);
  static const Color _highlight = Color(0xFFF5F7FB);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1250),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.width;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            final dx = (_controller.value * 2 - 1) * bounds.width;
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: const [_base, _highlight, _base],
              stops: const [0.25, 0.5, 0.75],
              transform: GradientTranslation(dx),
            ).createShader(bounds);
          },
          child: child,
        );
      },
      // Render only as many placeholder cards as actually fit the available
      // height, and clip the rest, so the skeleton never overflows a short
      // popup (small phones, split-screen, tiny web windows). A fixed count
      // used to spill past the list area and trip a RenderFlex overflow.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cardExtent = w * 0.209; // card height + bottom margin
          final maxH = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : cardExtent * 5;
          final count = (maxH / cardExtent).floor().clamp(1, 5);
          return ClipRect(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(count, (_) => _NotifSkeletonCard(width: w)),
            ),
          );
        },
      ),
    );
  }
}

/// Slides the shimmer gradient horizontally across the wrapped bounds.
class GradientTranslation extends GradientTransform {
  final double dx;
  const GradientTranslation(this.dx);
  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(dx, 0, 0);
}

class _NotifSkeletonCard extends StatelessWidget {
  final double width;
  const _NotifSkeletonCard({required this.width});

  @override
  Widget build(BuildContext context) {
    final w = width;
    Widget bar(double bw, double bh) => Container(
          width: bw,
          height: bh,
          decoration: BoxDecoration(
            color: const Color(0xFFE7EBF1),
            borderRadius: BorderRadius.circular(6),
          ),
        );
    return Container(
      margin: EdgeInsets.only(bottom: w * 0.025),
      padding: EdgeInsets.all(w * 0.03),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .65),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: w * 0.105,
            height: w * 0.105,
            decoration: BoxDecoration(
              color: const Color(0xFFE7EBF1),
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          SizedBox(width: w * 0.025),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                bar(double.infinity, w * 0.032),
                SizedBox(height: w * 0.02),
                bar(w * 0.5, w * 0.028),
                SizedBox(height: w * 0.02),
                bar(w * 0.22, w * 0.024),
              ],
            ),
          ),
        ],
      ),
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

    // A tapped notification stays in the list but stops counting, so it has to
    // LOOK spent — otherwise the badge dropping while the row is unchanged
    // reads as the badge being wrong. Unread keeps the solid card and bold
    // title; read recedes.
    final unread = !n.read;

    return Container(
      margin: spaced ? EdgeInsets.only(bottom: w * 0.025) : EdgeInsets.zero,
      padding: EdgeInsets.all(w * 0.03),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: unread ? .65 : .38),
        borderRadius: borderRadius ?? BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Opacity(opacity: unread ? 1 : .6, child: leading),
          SizedBox(width: w * 0.025),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  n.title,
                  style: TextStyle(
                    fontSize: w * 0.036,
                    fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                    color: unread ? Colors.black87 : Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  n.subtitle,
                  style: TextStyle(
                    fontSize: w * 0.029,
                    color: unread ? Colors.grey[700] : Colors.grey[600],
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
          // Unread marker, mirroring the admin/staff panels.
          if (unread) ...[
            SizedBox(width: w * 0.02),
            Container(
              width: w * 0.019,
              height: w * 0.019,
              decoration: BoxDecoration(color: n.color, shape: BoxShape.circle),
            ),
          ],
        ],
      ),
    );
  }
}
