// ════════════════════════════════════════════════════════════════════════════
//  Staff console notification bell + panel.
//
//  Mirrors the admin/citizen notification design so the whole app stays
//  consistent — same `notifications` table, same "profile photo for a person's
//  action, icon for an event" rule for the leading avatar. Teal-themed for the
//  staff surface. Self-contained: live unread count + Realtime subscription.
// ════════════════════════════════════════════════════════════════════════════

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/staff_ui.dart';
import 'staff_common.dart';

IconData _iconForTopic(String topic) {
  switch (topic) {
    case 'report':
      return Icons.report_gmailerrorred_rounded;
    case 'endorsement':
      return Icons.forward_to_inbox_rounded;
    case 'chat':
    case 'ticket':
    case 'message':
      return Icons.forum_rounded;
    case 'post_approved':
    case 'community':
      return Icons.campaign_rounded;
    case 'post_rejected':
      return Icons.gpp_bad_outlined;
    case 'post_heart':
    case 'comment_heart':
      return Icons.favorite_rounded;
    case 'comment':
      return Icons.mode_comment_outlined;
    default:
      return Icons.notifications_none_rounded;
  }
}

// Topics that describe an EVENT, not a person — always keep the icon even if a
// stray actor photo is attached. Same rule the admin panel uses.
const _iconOnlyTopics = {
  'report',
  'endorsement',
  'chat',
  'ticket',
  'message',
  'post_approved',
  'post_rejected',
  'community',
  'feedback',
  'suggestion',
  'verification',
};

// ── Model ────────────────────────────────────────────────────────────────────
class StaffNotif {
  final String id;
  final String topic;
  final String title;
  final String subtitle;
  final DateTime createdAt;
  final bool read;
  final Color color;
  final String? actorPhotoUrl;

  /// The row this notification is about, so a tap can land on that exact item
  /// and flash it. Null when the trigger that wrote the row doesn't set
  /// `reference_id` → the tap still opens the right section, without a flash.
  final String? referenceId;

  StaffNotif({
    required this.id,
    required this.topic,
    required this.title,
    required this.subtitle,
    required this.createdAt,
    required this.read,
    required this.color,
    this.actorPhotoUrl,
    this.referenceId,
  });

  factory StaffNotif.fromRow(Map<String, dynamic> r) => StaffNotif(
        id: r['id'].toString(),
        topic: (r['topic'] as String?) ?? 'general',
        title: (r['title'] as String?) ?? '',
        subtitle: (r['subtitle'] as String?) ?? '',
        createdAt:
            DateTime.tryParse((r['created_at'] as String?) ?? '')?.toLocal() ??
                DateTime.now(),
        read: r['read_at'] != null,
        color: (r['color_value'] as num?) != null
            ? Color((r['color_value'] as num).toInt())
            : StaffUi.accent,
        actorPhotoUrl: r['actor_photo_url'] as String?,
        referenceId: r['reference_id'] as String?,
      );

  IconData get icon => _iconForTopic(topic);

  /// Same rule as admin/citizen: a person's action shows their photo; an event
  /// keeps its icon.
  String? get leadingPhotoUrl =>
      _iconOnlyTopics.contains(topic) ? null : actorPhotoUrl;
}

/// Where a tapped staff notification wants the console to go: which section,
/// and which row to flash once it's there.
class StaffNotifTarget {
  final String topic;

  /// The row to scroll to and flash. Null when the notification's trigger
  /// doesn't record one → the console just opens the section.
  final String? referenceId;
  const StaffNotifTarget(this.topic, {this.referenceId});
}

// ── Live-count + data singleton ──────────────────────────────────────────────
class StaffNotifCenter {
  StaffNotifCenter._();
  static final StaffNotifCenter I = StaffNotifCenter._();

  SupabaseClient get _sb => Supabase.instance.client;
  String? get _uid => _sb.auth.currentUser?.id;

  final ValueNotifier<int> unread = ValueNotifier<int>(0);
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Set to a notification's topic when a staff row is tapped; the console maps
  /// it to the section that owns it (kept as a topic so it stays decoupled from
  /// nav order).
  final ValueNotifier<StaffNotifTarget?> openTopic =
      ValueNotifier<StaffNotifTarget?>(null);

  RealtimeChannel? _channel;
  String? _subscribedUid;

  Future<void> start() async {
    final uid = _uid;
    if (uid == null) return;
    if (_channel != null && _subscribedUid == uid) return;
    if (_channel != null) stop();
    _subscribedUid = uid;
    await refreshUnread();

    _channel = _sb.channel('staff-notifs-$uid')
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
    try {
      final rows = await _sb
          .from('notifications')
          .select('id')
          .eq('user_id', uid)
          .isFilter('read_at', null);
      unread.value = (rows as List).length;
    } catch (_) {/* keep last value on transient error */}
  }

  Future<List<StaffNotif>> fetch() async {
    final uid = _uid;
    if (uid == null) return const [];
    try {
      final rows = await _sb
          .from('notifications')
          .select()
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(100);
      return (rows as List)
          .map((r) => StaffNotif.fromRow(r as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> markAllRead() async {
    final uid = _uid;
    if (uid == null) return;
    final nowIso = DateTime.now().toUtc().toIso8601String();
    try {
      await _sb
          .from('notifications')
          .update({'read_at': nowIso})
          .eq('user_id', uid)
          .isFilter('read_at', null);
    } catch (_) {
      // Fall back to the shared RPC if a direct update is blocked by RLS.
      try {
        await _sb.rpc('mark_notifications_read', params: {'p_topics': null});
      } catch (_) {}
    }
    await refreshUnread();
    revision.value++;
  }

  Future<void> delete(String id) async {
    try {
      await _sb.from('notifications').delete().eq('id', id);
    } catch (_) {}
    await refreshUnread();
  }
}

// ── Topbar bell ──────────────────────────────────────────────────────────────
class StaffNotificationBell extends StatefulWidget {
  const StaffNotificationBell({super.key});
  @override
  State<StaffNotificationBell> createState() => _StaffNotificationBellState();
}

class _StaffNotificationBellState extends State<StaffNotificationBell> {
  @override
  void initState() {
    super.initState();
    StaffNotifCenter.I.start();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () => showStaffNotifications(context),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: ValueListenableBuilder<int>(
            valueListenable: StaffNotifCenter.I.unread,
            builder: (context, count, _) {
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.notifications_none_rounded,
                      size: 22, color: StaffUi.textSecondary),
                  if (count > 0)
                    Positioned(
                      top: -4,
                      right: -5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        constraints:
                            const BoxConstraints(minWidth: 16, minHeight: 16),
                        decoration: BoxDecoration(
                          color: StaffUi.danger,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: StaffUi.surface, width: 1.5),
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

// ── Dropdown panel ───────────────────────────────────────────────────────────
Future<void> showStaffNotifications(BuildContext context) {
  final narrow = MediaQuery.of(context).size.width < 480;
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Notifications',
    barrierColor: Colors.black.withValues(alpha: narrow ? 0.35 : 0.12),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, _, _) => const _StaffNotifPanel(),
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

class _StaffNotifPanel extends StatefulWidget {
  const _StaffNotifPanel();
  @override
  State<_StaffNotifPanel> createState() => _StaffNotifPanelState();
}

class _StaffNotifPanelState extends State<_StaffNotifPanel> {
  bool _loading = true;
  List<StaffNotif> _items = const [];

  /// Ids removed locally whose DELETE may not have propagated to the read
  /// replica yet. A Realtime DELETE event triggers [_load], and for a brief
  /// window that refetch can still return the just-deleted row (replication
  /// lag) — which flashed the notification back before it vanished for good.
  /// Filtering these out of every refetch keeps the deletion final.
  final Set<String> _pendingDeleted = {};

  @override
  void initState() {
    super.initState();
    StaffNotifCenter.I.revision.addListener(_onRevision);
    _load();
    // Opening the panel clears the badge.
    StaffNotifCenter.I.markAllRead();
  }

  @override
  void dispose() {
    StaffNotifCenter.I.revision.removeListener(_onRevision);
    super.dispose();
  }

  void _onRevision() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    final items = await StaffNotifCenter.I.fetch();
    if (!mounted) return;
    setState(() {
      _items =
          items.where((n) => !_pendingDeleted.contains(n.id)).toList();
      _loading = false;
    });
  }

  void _deleteItem(StaffNotif item) {
    _pendingDeleted.add(item.id);
    setState(() => _items = _items.where((n) => n.id != item.id).toList());
    StaffNotifCenter.I.delete(item.id);
  }

  void _handleTap(StaffNotif item) {
    Navigator.of(context).pop();
    StaffNotifCenter.I.openTopic.value =
        StaffNotifTarget(item.topic, referenceId: item.referenceId);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final narrow = size.width < 480;
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
          color: StaffUi.surface,
          borderRadius: BorderRadius.circular(StaffUi.cardRadius),
          border: Border.all(color: StaffUi.border),
          boxShadow: StaffUi.cardShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
              child: Row(
                children: [
                  const Text('Notifications',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: StaffUi.textPrimary)),
                  const Spacer(),
                  TextButton(
                    onPressed: () async {
                      await StaffNotifCenter.I.markAllRead();
                      if (mounted) _load();
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: StaffUi.accent,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                    ),
                    child: const Text('Mark all read',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: StaffUi.border),
            Expanded(
              child: _loading
                  ? const _NotifListSkeleton()
                  : _items.isEmpty
                      ? const StaffEmptyState(
                          icon: Icons.notifications_off_outlined,
                          title: 'No notifications',
                          subtitle: 'New chats, reports and approvals show here.',
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          itemCount: _items.length,
                          separatorBuilder: (_, _) => const Divider(
                              height: 1, color: StaffUi.subtle, indent: 56),
                          itemBuilder: (_, i) {
                            final item = _items[i];
                            return Dismissible(
                              key: ValueKey(item.id),
                              direction: DismissDirection.endToStart,
                              onDismissed: (_) => _deleteItem(item),
                              background: Container(
                                color: StaffUi.danger,
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                child: const Icon(Icons.delete_rounded,
                                    color: Colors.white, size: 22),
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

// Skeleton shown while the panel's notifications load. Mirrors _NotifRow's
// layout so the list doesn't shift once the data arrives.
class _NotifListSkeleton extends StatelessWidget {
  const _NotifListSkeleton();

  @override
  Widget build(BuildContext context) {
    // Only draw as many placeholder rows as fit the panel's height, then clip,
    // so the skeleton never overflows a short panel (small phones, split-screen,
    // tiny web windows). A fixed six rows used to spill past the list area.
    return LayoutBuilder(
      builder: (context, constraints) {
        const rowExtent = 68.0; // row content + vertical padding
        final maxH = constraints.maxHeight.isFinite
            ? constraints.maxHeight - 12 // outer vertical padding (6 + 6)
            : rowExtent * 6;
        final count = (maxH / rowExtent).floor().clamp(1, 6);
        return StaffShimmer(
          child: ClipRect(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children:
                    List.generate(count, (_) => const _NotifSkeletonRow()),
              ),
            ),
          ),
        );
      },
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
          StaffSkeletonBox(width: 30, height: 30, radius: 9),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StaffSkeletonBox(width: double.infinity, height: 12),
                SizedBox(height: 7),
                StaffSkeletonBox(width: 160, height: 11),
                SizedBox(height: 7),
                StaffSkeletonBox(width: 70, height: 9),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NotifRow extends StatelessWidget {
  final StaffNotif n;
  final VoidCallback? onDelete;
  final VoidCallback? onTap;
  const _NotifRow(this.n, {this.onDelete, this.onTap});

  @override
  Widget build(BuildContext context) {
    final iconLeading = Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: n.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(n.icon, size: 16, color: n.color),
    );

    final photoUrl = n.leadingPhotoUrl;
    final leading = (photoUrl != null && photoUrl.isNotEmpty)
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
                            fontWeight:
                                n.read ? FontWeight.w600 : FontWeight.w700,
                            color: StaffUi.textPrimary,
                          ),
                        ),
                      ),
                      if (!n.read)
                        Container(
                          width: 7,
                          height: 7,
                          margin: const EdgeInsets.only(left: 6, top: 4),
                          decoration: const BoxDecoration(
                              color: StaffUi.accent, shape: BoxShape.circle),
                        ),
                    ],
                  ),
                  if (n.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(n.subtitle,
                        style: const TextStyle(
                            fontSize: 12, color: StaffUi.textSecondary)),
                  ],
                  const SizedBox(height: 3),
                  Text(staffAgo(n.createdAt),
                      style: const TextStyle(
                          fontSize: 11, color: StaffUi.textMuted)),
                ],
              ),
            ),
            if (onDelete != null) ...[
              const SizedBox(width: 4),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded),
                iconSize: 18,
                color: StaffUi.textMuted,
                tooltip: 'Delete',
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
