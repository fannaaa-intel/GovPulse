import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/user_profile_provider.dart';
import '../../../core/services/chat_service.dart';
import '../../../core/widgets/deeplink_highlight.dart' show kNonFlashingNotifTopics;
import '../../../core/services/push_service.dart';
import '../../../core/widgets/Home/Chat-bubbles/home_chat_bubble.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/logout_confirm_dialog.dart';
import '../../admin/pages/admin_change_password.dart' show showAdminChangePassword;
import '../data/staff_repository.dart';
import '../pages/staff_community_page.dart';
import '../pages/staff_conversations_page.dart';
import '../pages/staff_history_page.dart';
import '../pages/staff_overview_page.dart';
import '../pages/staff_reports_page.dart'
    show StaffReportsPage, StaffEndorsementsPage;
import '../pages/staff_settings_page.dart';
import '../providers/staff_providers.dart';
import '../theme/staff_ui.dart';
import '../widgets/staff_command_palette.dart';
import '../widgets/staff_notifications.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Staff console — the role_id 2 shell.
//
//  A helpdesk/inbox surface (teal), deliberately distinct from the blue admin
//  console. Nav adapts to the account: internal offices get Conversations +
//  Reports; external entities (DPWH, …) get Endorsements instead.
// ════════════════════════════════════════════════════════════════════════════

class _NavItem {
  final IconData icon;
  final String label;
  final String key;
  const _NavItem(this.icon, this.label, this.key);
}

class StaffConsoleScreen extends ConsumerStatefulWidget {
  const StaffConsoleScreen({super.key});

  @override
  ConsumerState<StaffConsoleScreen> createState() => _StaffConsoleScreenState();
}

class _StaffConsoleScreenState extends ConsumerState<StaffConsoleScreen> {
  int _index = 0;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    // Tapping a notification row sets openTopic; map it to the owning section.
    StaffNotifCenter.I.openTopic.addListener(_onNotifNavigate);
  }

  @override
  void dispose() {
    StaffNotifCenter.I.openTopic.removeListener(_onNotifNavigate);
    super.dispose();
  }

  void _onNotifNavigate() {
    final target = StaffNotifCenter.I.openTopic.value;
    if (target == null) return;
    StaffNotifCenter.I.openTopic.value = null; // consume
    final topic = target.topic;
    final key = switch (topic) {
      'report' => 'reports',
      'endorsement' => 'endorsements',
      'chat' || 'ticket' || 'message' => 'conversations',
      // Approval decisions AND engagement (hearts/comments) on the staff's own
      // post all open the Community section where their submissions live.
      'post_approved' ||
      'post_rejected' ||
      'community' ||
      'post_heart' ||
      'comment_heart' ||
      'comment' =>
        'community',
      _ => null,
    };
    if (key == null || !mounted) return;
    final isExternal =
        ref.read(staffIdentityProvider).valueOrNull?.isExternal ?? false;

    // Reactions navigate but never flash — see [kNonFlashingNotifTopics].
    final flash = kNonFlashingNotifTopics.contains(topic)
        ? null
        : target.referenceId;
    _goToKey(_navFor(isExternal), key, highlightId: flash);
  }

  void _openPalette(List<_NavItem> nav) {
    showStaffCommandPalette(
      context,
      sections: [for (final n in nav) (icon: n.icon, label: n.label)],
      onNavigate: (i) => _select(i, nav),
    );
  }

  List<_NavItem> _navFor(bool isExternal) => [
        const _NavItem(Icons.dashboard_rounded, 'Dashboard', 'dashboard'),
        if (!isExternal)
          const _NavItem(Icons.forum_rounded, 'Conversations', 'conversations'),
        if (isExternal)
          const _NavItem(
              Icons.forward_to_inbox_rounded, 'Endorsements', 'endorsements')
        else
          const _NavItem(Icons.flag_rounded, 'Reports', 'reports'),
        const _NavItem(Icons.campaign_rounded, 'Community', 'community'),
        const _NavItem(Icons.history_rounded, 'History', 'history'),
        const _NavItem(Icons.settings_rounded, 'Settings', 'settings'),
      ];

  void _goToKey(List<_NavItem> nav, String key, {String? highlightId}) {
    final i = nav.indexWhere((n) => n.key == key);
    if (i >= 0) _select(i, nav, highlightId: highlightId);
  }

  /// Deep-link target awaiting the section that owns it. One-shot: consumed by
  /// the next [_pageFor] so returning later doesn't re-flash a stale row.
  String? _pendingHighlightId;

  /// Switches to section [i] and silently refetches its data. The staff console
  /// has no background poller (unlike admin), so refreshing on tab entry is what
  /// makes a chat/report that landed while you were on another tab show up.
  void _select(int i, List<_NavItem> nav, {String? highlightId}) {
    if (i < 0 || i >= nav.length) return;
    setState(() {
      _index = i;
      _pendingHighlightId = highlightId;
    });
    _refreshSection(nav[i].key);
  }

  void _refreshSection(String key) {
    switch (key) {
      case 'dashboard':
        ref.read(staffConversationsProvider.notifier).silentRefresh();
        ref.read(staffReportsProvider.notifier).silentRefresh();
        ref.read(staffEndorsementsProvider.notifier).silentRefresh();
      case 'conversations':
        ref.read(staffConversationsProvider.notifier).silentRefresh();
      case 'reports':
        ref.read(staffReportsProvider.notifier).silentRefresh();
      case 'endorsements':
        ref.read(staffEndorsementsProvider.notifier).silentRefresh();
      case 'community':
        ref.read(staffCommunityProvider.notifier).refresh();
    }
  }

  Widget _pageFor(String key, List<_NavItem> nav) {
    // One-shot read: the section mounting now owns this target. Cleared after
    // the frame, without setState — the page already has it for this build.
    final highlightId = _pendingHighlightId;
    if (highlightId != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _pendingHighlightId = null,
      );
    }

    switch (key) {
      case 'dashboard':
        return StaffOverviewPage(onNavigate: (k) => _goToKey(nav, k));
      case 'conversations':
        // Chat/message notifications open the thread itself rather than
        // flashing a list row — see StaffConversationsPage.openTicketId.
        return StaffConversationsPage(openTicketId: highlightId);
      case 'reports':
        return StaffReportsPage(highlightId: highlightId);
      case 'endorsements':
        return StaffEndorsementsPage(highlightId: highlightId);
      case 'community':
        return StaffCommunityPage(highlightId: highlightId);
      case 'history':
        return const StaffHistoryPage();
      case 'settings':
        return StaffSettingsPage(onLogout: _confirmLogout);
      default:
        return const SizedBox.shrink();
    }
  }

  Future<void> _confirmLogout() async {
    final ok = await showLogoutConfirmDialog(
      context,
      message:
          "You'll go off duty and need to sign in again to access the console.",
    );
    if (!ok || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: StaffUi.accent)),
    );
    try {
      // Go off duty so no chats route to a signed-out staff member.
      try {
        await StaffRepository.I.setOnline(false);
      } catch (_) {}
      StaffNotifCenter.I.stop();
      await PushService.I.unregister();
      await Supabase.instance.client.auth.signOut();
      await ChatService.onUserSignedOut();
      HomeChatBubble.hideGlobal();
      if (!mounted) return;
      Navigator.pop(context); // dismiss spinner
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false);
      ref.invalidate(userProfileProvider);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      showAppSnackBar(context, 'Logout failed: $e', type: AppSnackType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final identity = ref.watch(staffIdentityProvider).valueOrNull;
    final isExternal = identity?.isExternal ?? false;
    final nav = _navFor(isExternal);
    if (_index >= nav.length) _index = 0;

    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 1024;
    final isTablet = width >= 600 && width < 1024;

    final title = nav[_index].label;
    final page = _pageFor(nav[_index].key, nav);

    final Widget shell;
    if (isDesktop || isTablet) {
      shell = Scaffold(
        backgroundColor: StaffUi.pageBg,
        body: SafeArea(
          child: Row(
            children: [
              _Sidebar(
                items: nav,
                selectedIndex: _index,
                collapsed: isTablet,
                department: identity?.department ?? '',
                onTap: (i) => _select(i, nav),
                onLogout: _confirmLogout,
              ),
              Expanded(
                child: Column(
                  children: [
                    _TopBar(
                      title: title,
                      showMenu: false,
                      onLogout: _confirmLogout,
                      onSearch: () => _openPalette(nav),
                    ),
                    Expanded(child: page),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      // Mobile: drawer + bottom sheet-free layout.
      shell = Scaffold(
        key: _scaffoldKey,
        backgroundColor: StaffUi.pageBg,
        drawer: Drawer(
          width: 250,
          backgroundColor: StaffUi.surface,
          child: SafeArea(
            child: _Sidebar(
              items: nav,
              selectedIndex: _index,
              collapsed: false,
              department: identity?.department ?? '',
              onTap: (i) {
                _select(i, nav);
                Navigator.pop(context);
              },
              onLogout: () {
                Navigator.pop(context);
                _confirmLogout();
              },
            ),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              _TopBar(
                title: title,
                showMenu: true,
                onMenu: () => _scaffoldKey.currentState?.openDrawer(),
                onLogout: _confirmLogout,
                onSearch: () => _openPalette(nav),
              ),
              Expanded(child: page),
            ],
          ),
        ),
      );
    }

    // Global ⌘K / Ctrl-K opens the command palette from anywhere in the console.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            _openPalette(nav),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
            _openPalette(nav),
      },
      child: Focus(autofocus: true, child: shell),
    );
  }
}

// ── Sidebar ──────────────────────────────────────────────────────────────────
class _Sidebar extends StatelessWidget {
  final List<_NavItem> items;
  final int selectedIndex;
  final bool collapsed;
  final String department;
  final void Function(int) onTap;
  final VoidCallback onLogout;
  const _Sidebar({
    required this.items,
    required this.selectedIndex,
    required this.collapsed,
    required this.department,
    required this.onTap,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: collapsed ? 72 : 244,
      decoration: const BoxDecoration(
        color: StaffUi.surface,
        border: Border(right: BorderSide(color: StaffUi.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 64,
            padding: EdgeInsets.symmetric(horizontal: collapsed ? 16 : 18),
            alignment: collapsed ? Alignment.center : Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/images/applogo.webp',
                    height: 30, width: 30),
                if (!collapsed) ...[
                  const SizedBox(width: 10),
                  const Text('GovPulse',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: StaffUi.accent,
                        letterSpacing: -0.3,
                      )),
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: StaffUi.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('Staff',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: StaffUi.accent,
                        )),
                  ),
                ],
              ],
            ),
          ),
          if (!collapsed && department.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
              child: Text(department,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11.5, color: StaffUi.textMuted)),
            ),
          const SizedBox(height: 4),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: items.length,
              itemBuilder: (_, i) => _NavTile(
                item: items[i],
                selected: i == selectedIndex,
                collapsed: collapsed,
                onTap: () => onTap(i),
              ),
            ),
          ),
          const Divider(height: 1, color: StaffUi.border),
          _LogoutTile(collapsed: collapsed, onLogout: onLogout),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final _NavItem item;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;
  const _NavTile({
    required this.item,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: collapsed ? item.label : '',
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            margin: const EdgeInsets.only(bottom: 2),
            padding: EdgeInsets.symmetric(
                horizontal: collapsed ? 0 : 12, vertical: 11),
            decoration: BoxDecoration(
              color: selected
                  ? StaffUi.accent.withValues(alpha: 0.10)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: collapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Icon(item.icon,
                    size: 20,
                    color: selected ? StaffUi.accent : StaffUi.textMuted),
                if (!collapsed) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected
                              ? StaffUi.accent
                              : StaffUi.textSecondary,
                        )),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LogoutTile extends StatelessWidget {
  final bool collapsed;
  final VoidCallback onLogout;
  const _LogoutTile({required this.collapsed, required this.onLogout});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onLogout,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: collapsed ? 0 : 12, vertical: 11),
            child: Row(
              mainAxisAlignment: collapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                const Icon(Icons.logout_rounded,
                    size: 20, color: StaffUi.danger),
                if (!collapsed) ...[
                  const SizedBox(width: 12),
                  const Text('Logout',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: StaffUi.danger,
                      )),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Top bar (title + presence toggle + account) ──────────────────────────────
class _TopBar extends ConsumerWidget {
  final String title;
  final bool showMenu;
  final VoidCallback? onMenu;
  final VoidCallback onLogout;
  final VoidCallback onSearch;
  const _TopBar({
    required this.title,
    required this.showMenu,
    this.onMenu,
    required this.onLogout,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.of(context).size.width;
    final showSearch = width >= 760;
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: StaffUi.surface,
        border: Border(bottom: BorderSide(color: StaffUi.border)),
      ),
      child: Row(
        children: [
          if (showMenu) ...[
            IconButton(
              icon: const Icon(Icons.menu_rounded, color: StaffUi.textSecondary),
              onPressed: onMenu,
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: StaffUi.textPrimary,
                  letterSpacing: -0.3,
                )),
          ),
          if (showSearch) ...[
            _SearchField(onTap: onSearch),
            const SizedBox(width: 10),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.search_rounded, color: StaffUi.textSecondary),
              onPressed: onSearch,
              tooltip: 'Search',
            ),
          ],
          const _PresenceToggle(),
          const SizedBox(width: 6),
          const StaffNotificationBell(),
          const SizedBox(width: 8),
          _AccountMenu(
            compact: width < 560,
            onLogout: onLogout,
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final VoidCallback onTap;
  const _SearchField({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: StaffUi.subtle,
      borderRadius: BorderRadius.circular(StaffUi.controlRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(StaffUi.controlRadius),
        child: Container(
          height: 38,
          width: 220,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(StaffUi.controlRadius),
            border: Border.all(color: StaffUi.border),
          ),
          child: const Row(
            children: [
              Icon(Icons.search_rounded, size: 16, color: StaffUi.textMuted),
              SizedBox(width: 8),
              Expanded(
                child: Text('Search…',
                    style: TextStyle(fontSize: 13, color: StaffUi.textMuted)),
              ),
              Text('⌘K',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: StaffUi.textMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The on-duty toggle — the single most important staff control: only online
/// staff receive live citizen chats (findAvailableStaffId reads is_online).
class _PresenceToggle extends ConsumerWidget {
  const _PresenceToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(
      staffIdentityProvider.select((s) => s.valueOrNull?.isOnline ?? false),
    );
    return Material(
      color: online
          ? StaffUi.online.withValues(alpha: 0.12)
          : StaffUi.subtle,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () async {
          try {
            await ref.read(staffIdentityProvider.notifier).setOnline(!online);
          } catch (e) {
            if (context.mounted) {
              showAppSnackBar(context, '$e', type: AppSnackType.error);
            }
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: online ? StaffUi.online : StaffUi.offline,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                online ? 'Online' : 'Offline',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: online ? StaffUi.online : StaffUi.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _AccountAction { changePassword, logout }

class _AccountMenu extends ConsumerWidget {
  final bool compact;
  final VoidCallback onLogout;
  const _AccountMenu({required this.compact, required this.onLogout});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = ref.watch(staffIdentityProvider).valueOrNull;
    final avatar = Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: StaffUi.accent.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: (id?.photoUrl != null && id!.photoUrl!.isNotEmpty)
          ? CachedNetworkImage(
              imageUrl: id.photoUrl!,
              fit: BoxFit.cover,
              errorWidget: (_, _, _) => _mono(id.initials),
            )
          : _mono(id?.initials ?? 'S'),
    );

    return PopupMenuButton<_AccountAction>(
      tooltip: 'Account',
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (a) {
        switch (a) {
          case _AccountAction.changePassword:
            showAdminChangePassword(context);
          case _AccountAction.logout:
            onLogout();
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: _AccountAction.changePassword,
          child: Row(children: [
            Icon(Icons.lock_outline_rounded, size: 18, color: StaffUi.textSecondary),
            SizedBox(width: 10),
            Text('Change password'),
          ]),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: _AccountAction.logout,
          child: Row(children: [
            Icon(Icons.logout_rounded, size: 18, color: StaffUi.danger),
            SizedBox(width: 10),
            Text('Log out', style: TextStyle(color: StaffUi.danger)),
          ]),
        ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          avatar,
          if (!compact) ...[
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 130),
              child: Text(
                id?.displayName ?? 'Staff',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: StaffUi.textPrimary,
                ),
              ),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded,
                size: 18, color: StaffUi.textMuted),
          ],
        ],
      ),
    );
  }

  Widget _mono(String initials) => Center(
        child: Text(initials,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: StaffUi.accent,
            )),
      );
}
