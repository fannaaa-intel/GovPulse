// ════════════════════════════════════════════════════════════════════════════
//  lib/features/admin/widgets/admin_notifications.dart
//
//  The admin console's notification bell + panel. Fully self-contained:
//   • AdminNotifCenter — a singleton that keeps a live unread count and a
//     Realtime subscription so the WEB console updates without a refresh.
//   • AdminNotificationBell — the topbar bell, with a live count badge.
//   • showAdminNotifications() — opens a top-right dropdown panel with topic
//     tabs (All / Reports / Verifications / Hearts / Comments / Feedback /
//     Suggestions). Opening a tab marks its notifications read.
//
//  Backed by the `notifications` table + the `topic` / `read_at` columns and
//  the `mark_notifications_read` RPC added in the SQL migrations. This file
//  deliberately does NOT touch the citizen-facing NotificationService.
// ════════════════════════════════════════════════════════════════════════════

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/admin_ui.dart';
import 'admin_skeleton.dart';

// ── Tab model ─────────────────────────────────────────────────────────────────
class AdminNotifTab {
  final String id;
  final String label;
  final List<String> topics; // topic values this tab filters to
  final Color color;
  const AdminNotifTab(this.id, this.label, this.topics, this.color);
}

// The full set of topics the admin center cares about. Excludes personal,
// citizen-style notifications (topic = null, e.g. "X liked your post"), so an
// admin who also uses the app as a citizen doesn't see their own personal
// notifications in the admin bell.
const List<String> kAllAdminTopics = [
  'report',
  'verification',
  'post_heart',
  'comment_heart',
  'comment',
  'feedback',
  'suggestion',
];

// Topics grouped under "Others".
const List<String> kOtherTopics = [
  'post_heart',
  'comment_heart',
  'comment',
  'feedback',
  'suggestion',
];

// Primary row — always visible.
const List<AdminNotifTab> kPrimaryTabs = [
  AdminNotifTab('all', 'All', kAllAdminTopics, Color(0xFF2563EB)),
  AdminNotifTab('report', 'Reports', ['report'], Color(0xFFF59E0B)),
  AdminNotifTab('verification', 'Verifications', [
    'verification',
  ], Color(0xFF6366F1)),
  AdminNotifTab('others', 'Others', kOtherTopics, Color(0xFF64748B)),
];

// Second row — revealed only when "Others" is open.
const List<AdminNotifTab> kOtherTabs = [
  AdminNotifTab('hearts', 'Hearts', [
    'post_heart',
    'comment_heart',
  ], Color(0xFFEC4899)),
  AdminNotifTab('comments', 'Comments', ['comment'], Color(0xFF2563EB)),
  AdminNotifTab('feedback', 'Feedback', ['feedback'], Color(0xFF14B8A6)),
  AdminNotifTab('suggestions', 'Suggestions', [
    'suggestion',
  ], Color(0xFF22C55E)),
];

IconData _iconForTopic(String topic) {
  switch (topic) {
    case 'report':
      return Icons.report_gmailerrorred_rounded;
    case 'verification':
      return Icons.verified_user_outlined;
    case 'post_heart':
    case 'comment_heart':
      return Icons.favorite_rounded;
    case 'comment':
      return Icons.mode_comment_outlined;
    case 'feedback':
      return Icons.reviews_outlined;
    case 'suggestion':
      return Icons.lightbulb_outline_rounded;
    default:
      return Icons.notifications_none_rounded;
  }
}

// ── Model ─────────────────────────────────────────────────────────────────────
class AdminNotif {
  final String id;
  final String topic;
  final String title;
  final String subtitle;
  final DateTime createdAt;
  final bool read;
  final Color color;

  /// The user who performed the action (like/comment/reply). Null for events
  /// with no acting user (report/feedback/suggestion/verification) and for
  /// staff-actor activity.
  final String? actorId;

  /// A ready-to-render, full public URL to the actor's profile photo. When
  /// present it replaces the leading icon with that person's photo.
  final String? actorPhotoUrl;

  AdminNotif({
    required this.id,
    required this.topic,
    required this.title,
    required this.subtitle,
    required this.createdAt,
    required this.read,
    required this.color,
    this.actorId,
    this.actorPhotoUrl,
  });

  factory AdminNotif.fromRow(Map<String, dynamic> r) => AdminNotif(
    id: r['id'] as String,
    topic: (r['topic'] as String?) ?? 'general',
    title: (r['title'] as String?) ?? '',
    subtitle: (r['subtitle'] as String?) ?? '',
    createdAt:
        DateTime.tryParse((r['created_at'] as String?) ?? '')?.toLocal() ??
        DateTime.now(),
    read: r['read_at'] != null,
    color: Color(((r['color_value'] as num?)?.toInt() ?? 0xFF2563EB)),
    actorId: r['actor_id'] as String?,
    actorPhotoUrl: r['actor_photo_url'] as String?,
  );

  IconData get icon => _iconForTopic(topic);

  String get timeAgo {
    final d = DateTime.now().difference(createdAt);
    if (d.inSeconds < 60) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} hr ago';
    if (d.inDays < 7) return '${d.inDays} d ago';
    return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
  }
}

// ── Data + live-count singleton ───────────────────────────────────────────────
class AdminNotifCenter {
  AdminNotifCenter._();
  static final AdminNotifCenter I = AdminNotifCenter._();

  SupabaseClient get _sb => Supabase.instance.client;
  String? get _uid => _sb.auth.currentUser?.id;

  /// Live unread count for the bell badge.
  final ValueNotifier<int> unread = ValueNotifier<int>(0);

  /// Bumped whenever a Realtime change lands, so an open panel can reload.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Set to a notification's [topic] when an admin taps a row in the panel.
  /// The dashboard shell listens, maps the topic to the matching nav tab and
  /// switches to it, then resets this to null. Kept as a topic (not a raw tab
  /// index) so the notification panel stays decoupled from the nav order.
  final ValueNotifier<String?> openTopic = ValueNotifier<String?>(null);

  /// Topics the admin has muted in Settings — excluded from the unread badge.
  /// Fed by AdminSettingsNotifier (persisted in SharedPreferences).
  Set<String> _mutedTopics = const {};
  Set<String> get mutedTopics => _mutedTopics;

  /// Admin topics that still count toward the badge (all topics minus muted).
  List<String> get _countedTopics =>
      kAllAdminTopics.where((t) => !_mutedTopics.contains(t)).toList();

  /// Replace the muted-topic set and immediately recompute the unread badge, so
  /// muting/unmuting is reflected the instant it's toggled in Settings.
  void setMutedTopics(Set<String> topics) {
    _mutedTopics = {...topics};
    refreshUnread();
  }

  RealtimeChannel? _channel;
  String? _subscribedUid;

  /// Call once after the admin is authenticated (e.g. in the dashboard shell).
  /// Safe to call repeatedly — no-ops when already live for the same user, and
  /// re-subscribes automatically if a different user has signed in.
  Future<void> start() async {
    final uid = _uid;
    if (uid == null) return;
    if (_channel != null && _subscribedUid == uid) return;
    if (_channel != null) stop(); // different user — tear down the old channel
    _subscribedUid = uid;
    await refreshUnread();

    _channel = _sb.channel('admin-notifs-$uid')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'notifications',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: uid,
        ),
        callback: (_) {
          refreshUnread();
          revision.value++;
        },
      )
      ..subscribe();
  }

  /// Tear down on logout so a new session re-subscribes cleanly.
  void stop() {
    _channel?.unsubscribe();
    _channel = null;
    _subscribedUid = null;
    unread.value = 0;
  }

  Future<void> refreshUnread() async {
    final uid = _uid;
    if (uid == null) {
      unread.value = 0;
      return;
    }
    final counted = _countedTopics;
    if (counted.isEmpty) {
      // Every admin topic is muted → nothing to badge.
      unread.value = 0;
      return;
    }
    try {
      final rows = await _sb
          .from('notifications')
          .select('id')
          .eq('user_id', uid)
          .inFilter('topic', counted)
          .isFilter('read_at', null);
      unread.value = (rows as List).length;
    } catch (_) {
      // Leave the last known value on transient errors.
    }
  }

  Future<List<AdminNotif>> fetch(List<String>? topics) async {
    final uid = _uid;
    if (uid == null) return const [];
    try {
      var q = _sb.from('notifications').select().eq('user_id', uid);
      if (topics != null) q = q.inFilter('topic', topics);
      final rows = await q.order('created_at', ascending: false).limit(100);
      return (rows as List)
          .map((r) => AdminNotif.fromRow(r as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> markRead(List<String>? topics) async {
    try {
      await _sb.rpc('mark_notifications_read', params: {'p_topics': topics});
    } catch (_) {}
    await refreshUnread();
  }

  /// Deletes a single notification by id (mirrors the citizen swipe-to-delete).
  Future<void> delete(String id) async {
    try {
      await _sb.from('notifications').delete().eq('id', id);
    } catch (_) {}
    await refreshUnread();
  }
}

// ── The topbar bell ───────────────────────────────────────────────────────────
class AdminNotificationBell extends StatefulWidget {
  const AdminNotificationBell({super.key});

  @override
  State<AdminNotificationBell> createState() => _AdminNotificationBellState();
}

class _AdminNotificationBellState extends State<AdminNotificationBell> {
  @override
  void initState() {
    super.initState();
    // Idempotent — starts the live count + Realtime once.
    AdminNotifCenter.I.start();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () => showAdminNotifications(context),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: ValueListenableBuilder<int>(
            valueListenable: AdminNotifCenter.I.unread,
            builder: (context, count, _) {
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(
                    Icons.notifications_none_rounded,
                    size: 22,
                    color: AdminUi.textSecondary,
                  ),
                  if (count > 0)
                    Positioned(
                      top: -4,
                      right: -5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                            color: AdminUi.surface,
                            width: 1.5,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            count > 99 ? '99+' : '$count',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ── The dropdown panel ────────────────────────────────────────────────────────
Future<void> showAdminNotifications(BuildContext context) {
  // Phone → centered modal with a firmer scrim so it reads as a focused sheet.
  // Desktop/tablet → the top-right dropdown anchored by the bell. The old build
  // always pinned the panel to the top-right with a hairline scrim, which on a
  // phone left the near-full-width panel hugging the left edge (4px on one side,
  // 16px on the other) with the dashboard bleeding through — this fixes both.
  final narrow = MediaQuery.of(context).size.width < 480;
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Notifications',
    barrierColor: Colors.black.withValues(alpha: narrow ? 0.35 : 0.12),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, _, _) => const _AdminNotifPanel(),
    transitionBuilder: (_, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      final panel = SlideTransition(
        position: Tween(
          begin: Offset(0, narrow ? 0.04 : -0.03),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
      return FadeTransition(
        opacity: curved,
        child: narrow
            ? Center(child: panel)
            : SafeArea(
                child: Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 60, right: 16),
                    child: panel,
                  ),
                ),
              ),
      );
    },
  );
}

class _AdminNotifPanel extends StatefulWidget {
  const _AdminNotifPanel();

  @override
  State<_AdminNotifPanel> createState() => _AdminNotifPanelState();
}

class _AdminNotifPanelState extends State<_AdminNotifPanel> {
  // Fresh every time the panel opens (initState defaults), so closing and
  // reopening always resets to the collapsed base tabs with "All" selected.
  String _selectedId = 'all';
  bool _othersOpen = false;
  bool _loading = true;
  List<AdminNotif> _items = const [];

  @override
  void initState() {
    super.initState();
    AdminNotifCenter.I.revision.addListener(_onRevision);
    _selectTab(kPrimaryTabs.first);
  }

  @override
  void dispose() {
    AdminNotifCenter.I.revision.removeListener(_onRevision);
    super.dispose();
  }

  AdminNotifTab get _selectedTab {
    for (final t in kPrimaryTabs) {
      if (t.id == _selectedId) return t;
    }
    for (final t in kOtherTabs) {
      if (t.id == _selectedId) return t;
    }
    return kPrimaryTabs.first;
  }

  void _onRevision() {
    if (mounted) _load(_selectedTab.topics);
  }

  Future<void> _selectTab(AdminNotifTab tab) async {
    // "Others" is a pure disclosure toggle: it only reveals/hides the sub-tab
    // row and never changes or reloads the list content.
    if (tab.id == 'others') {
      setState(() => _othersOpen = !_othersOpen);
      return;
    }
    setState(() {
      _selectedId = tab.id;
      // A base tab collapses the Others row; a sub-tab keeps it open.
      if (!kOtherTabs.any((t) => t.id == tab.id)) _othersOpen = false;
      _loading = true;
    });
    await _load(tab.topics);
    await AdminNotifCenter.I.markRead(tab.topics); // opening a tab clears it
    if (mounted) _load(tab.topics);
  }

  Future<void> _load(List<String>? topics) async {
    final items = await AdminNotifCenter.I.fetch(topics);
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  // Removes a notification locally + in the DB. Shared by the swipe gesture
  // (touch) and the trash button (pointer / wide layouts).
  void _deleteItem(AdminNotif item) {
    setState(() {
      _items = _items.where((n) => n.id != item.id).toList();
    });
    AdminNotifCenter.I.delete(item.id);
  }

  // Tapping a notification closes the panel and asks the dashboard shell to jump
  // to the tab that owns this topic (Reports / Suggestions / Feedback /
  // Verification / Community). The shell maps the topic → tab and resets it.
  void _handleTap(AdminNotif item) {
    Navigator.of(context).pop();
    AdminNotifCenter.I.openTopic.value = item.topic;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    // Responsive: centered modal on phones (symmetric 16px side margins, room
    // top+bottom so it never runs off the bottom edge), fixed dropdown on
    // desktop.
    final bool narrow = size.width < 480;
    final w = narrow ? size.width - 32 : 380.0;
    final h = narrow
        ? (size.height * 0.72).clamp(360.0, size.height - 120)
        : (size.height * 0.7).clamp(320.0, 560.0);

    return Material(
      color: Colors.transparent,
      child: Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: AdminUi.surface,
          borderRadius: BorderRadius.circular(AdminUi.cardRadius),
          border: Border.all(color: AdminUi.border),
          boxShadow: AdminUi.cardShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
              child: Row(
                children: [
                  const Text(
                    'Notifications',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AdminUi.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () async {
                      await AdminNotifCenter.I.markRead(kAllAdminTopics);
                      if (mounted) _load(_selectedTab.topics);
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF2563EB),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                    ),
                    child: const Text(
                      'Mark all read',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Tabs: base row (All / Reports / Verifications / Others). The
            // second row (Hearts / Comments / Feedback / Suggestions) appears
            // only after "Others" is tapped, and collapses again on reopen.
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final t in kPrimaryTabs)
                        _TabChip(
                          label: t.label,
                          color: t.color,
                          active: t.id == 'others'
                              ? _othersOpen
                              : _selectedId == t.id,
                          trailing: t.id == 'others'
                              ? (_othersOpen
                                    ? Icons.expand_less_rounded
                                    : Icons.expand_more_rounded)
                              : null,
                          onTap: () => _selectTab(t),
                        ),
                    ],
                  ),
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 160),
                    crossFadeState: _othersOpen
                        ? CrossFadeState.showFirst
                        : CrossFadeState.showSecond,
                    firstChild: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final t in kOtherTabs)
                            _TabChip(
                              label: t.label,
                              color: t.color,
                              active: _selectedId == t.id,
                              onTap: () => _selectTab(t),
                            ),
                        ],
                      ),
                    ),
                    secondChild: const SizedBox(width: double.infinity),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 6),
            const Divider(height: 1, color: AdminUi.border),

            // List
            Expanded(
              child: _loading
                  ? const _NotifListSkeleton()
                  : _items.isEmpty
                  ? const Center(
                      child: Text(
                        'No notifications',
                        style: TextStyle(
                          color: AdminUi.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: _items.length,
                      separatorBuilder: (_, _) => const Divider(
                        height: 1,
                        color: AdminUi.subtle,
                        indent: 56,
                      ),
                      itemBuilder: (_, i) {
                        final item = _items[i];
                        // Swipe left to delete — mirrors the citizen
                        // notification's swipe-to-delete (red trash panel).
                        // Works with touch and mouse-drag. On wider (pointer)
                        // layouts we also show an explicit trash button, since
                        // swiping isn't discoverable with a mouse.
                        return Dismissible(
                          key: ValueKey(item.id),
                          direction: DismissDirection.endToStart,
                          onDismissed: (_) => _deleteItem(item),
                          background: Container(
                            color: const Color(0xFFEF4444),
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            child: const Icon(
                              Icons.delete_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                          child: _NotifRow(
                            item,
                            onDelete: narrow ? null : () => _deleteItem(item),
                            onTap: () => _handleTap(item),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// A single wrapping tab chip.
class _TabChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool active;
  final IconData? trailing;
  final VoidCallback onTap;
  const _TabChip({
    required this.label,
    required this.color,
    required this.active,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.12) : AdminUi.subtle,
          borderRadius: BorderRadius.circular(AdminUi.controlRadius),
          border: Border.all(
            color: active ? color.withValues(alpha: 0.5) : AdminUi.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active ? color : AdminUi.textSecondary,
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 3),
              Icon(
                trailing,
                size: 15,
                color: active ? color : AdminUi.textSecondary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Skeleton shown while the panel's notifications load. Mirrors _NotifRow so the
// list doesn't shift when data arrives.
class _NotifListSkeleton extends StatelessWidget {
  const _NotifListSkeleton();

  @override
  Widget build(BuildContext context) {
    return const AdminShimmer(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            _NotifSkeletonRow(),
            _NotifSkeletonRow(),
            _NotifSkeletonRow(),
            _NotifSkeletonRow(),
            _NotifSkeletonRow(),
            _NotifSkeletonRow(),
          ],
        ),
      ),
    );
  }
}

class _NotifSkeletonRow extends StatelessWidget {
  const _NotifSkeletonRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: 30, height: 30, radius: 9),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: double.infinity, height: 12),
                SizedBox(height: 7),
                SkeletonBox(width: 160, height: 11),
                SizedBox(height: 7),
                SkeletonBox(width: 70, height: 9),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NotifRow extends StatelessWidget {
  final AdminNotif n;

  /// When non-null, a trash button is shown (pointer / wide layouts, where
  /// swipe-to-delete isn't discoverable). On touch layouts this is null and
  /// deletion is via the swipe gesture instead.
  final VoidCallback? onDelete;

  /// Tapping the row navigates to the tab that owns this notification's topic.
  final VoidCallback? onTap;

  const _NotifRow(this.n, {this.onDelete, this.onTap});

  @override
  Widget build(BuildContext context) {
    // Current icon leading — kept unchanged for every notification without an
    // actor photo (reports, verifications, staff activity, old rows, …).
    final Widget iconLeading = Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: n.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(n.icon, size: 16, color: n.color),
    );

    // Actor photos only make sense for another citizen's activity (likes /
    // comments). Submission notifications — report / feedback / suggestion /
    // verification — describe an event, not a person, so they keep their icon
    // even if the row happens to carry an actor photo URL.
    const iconOnlyTopics = {'report', 'verification', 'feedback', 'suggestion'};

    // When the notification carries a real actor photo URL, show that person's
    // photo instead of the icon. Same 30×30 footprint so the row doesn't shift;
    // a broken/unreachable URL falls back to [iconLeading].
    final String? photoUrl = iconOnlyTopics.contains(n.topic)
        ? null
        : n.actorPhotoUrl;
    final Widget leading = (photoUrl != null && photoUrl.isNotEmpty)
        ? ClipOval(
            child: SizedBox(
              width: 30,
              height: 30,
              child: CachedNetworkImage(
                imageUrl: photoUrl,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => iconLeading,
              ),
            ),
          )
        : iconLeading;

    return InkWell(
      onTap: onTap,
      child: Container(
        color: n.read ? null : n.color.withValues(alpha: 0.05),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          n.title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: n.read
                                ? FontWeight.w600
                                : FontWeight.w700,
                            color: AdminUi.textPrimary,
                          ),
                        ),
                      ),
                      if (!n.read)
                        Container(
                          width: 7,
                          height: 7,
                          margin: const EdgeInsets.only(left: 6, top: 4),
                          decoration: const BoxDecoration(
                            color: Color(0xFF2563EB),
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  if (n.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      n.subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AdminUi.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 3),
                  Text(
                    n.timeAgo,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AdminUi.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (onDelete != null) ...[
              const SizedBox(width: 4),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded),
                iconSize: 18,
                color: AdminUi.textMuted,
                tooltip: 'Delete',
                splashRadius: 18,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
