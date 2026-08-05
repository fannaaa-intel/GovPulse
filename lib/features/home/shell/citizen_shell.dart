import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/user_profile_provider.dart';
import '../../../core/router/app_router.dart' as legacy_router;
import '../../../core/theme/citizen_ui.dart';
import '../../../core/widgets/Home/home_enums.dart';
import '../../../core/widgets/Home/nav/home_top_nav.dart';
import '../../../core/widgets/Home/nav/nav_band.dart';
import '../../../core/widgets/Home/Newsfeed/citizen_web_notification_panel.dart';
import '../../../core/widgets/Home/sections/Web/home_quick_actions_section_web.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../emergency/emergency_screen.dart';
import '../my_report/my_reports_screen.dart';
import '../newsfeed/news_feed_screen.dart';
import '../screen/home_screen.dart';
import '../screen/notification_popup.dart';
import '../settings/settings_screen.dart';
import 'citizen_shell_router.dart';

// ════════════════════════════════════════════════════════════════════════════
//  CitizenShell — the persistent 3-column web shell, PREVIEW BUILD.
//
//  Reachable only at /shell-preview (see citizen_shell_router.dart). No live
//  route points here, and the mobile app never builds it.
//
//  Structure is lifted from staff_console_screen.dart, which has been running
//  this shape in production: one Scaffold, a selected-tab int, and the sections
//  swapped underneath fixed chrome. The one deliberate divergence is the centre
//  pane — staff rebuilds via a `_pageFor(key)` switch, this uses an IndexedStack
//  so all five panes stay mounted and keep their scroll offset and loaded data
//  across tab switches. That persistence is the entire point of the shell, and
//  a switch cannot provide it.
//
//  ── What is deliberately temporary here ────────────────────────────────────
//  The centre hosts the CURRENT screens unchanged, each of which still brings
//  its own Scaffold and its own nav chrome. That doubling is expected at this
//  step: the goal is to prove the shell and the routing, not to redress the
//  screens. Phase 2 splits each into a route-entry screen and a chromeless body,
//  and the body is what the IndexedStack will hold.
//
//  Each pane also gets its own Navigator wired to the LEGACY route table. That
//  is scaffolding, not architecture — without it, every in-pane tap (open a
//  report, a settings sub-page, a quick action) throws, because the preview's
//  go_router has no '/report_detail' or '/my_submissions'. With it, the preview
//  is actually explorable side-by-side against the live app, and pushes stay
//  inside the pane they came from, which is roughly where Phase 2 lands anyway.
// ════════════════════════════════════════════════════════════════════════════

/// Left rail width when it shows labels.
const double _kRailLabelledWidth = 264;

/// Left rail width when collapsed to icons.
const double _kRailIconWidth = 76;

/// Right quick-actions sidebar width.
const double _kRightSidebarWidth = 320;

class CitizenShell extends ConsumerStatefulWidget {
  /// Current location path, from the router. Drives the selected tab — the
  /// shell never stores the index as its own source of truth, so the URL and
  /// the visible pane cannot drift apart.
  final String location;

  /// Optional deep-link target for the pane being opened, from `?target=`.
  final String? target;

  const CitizenShell({super.key, required this.location, this.target});

  @override
  ConsumerState<CitizenShell> createState() => _CitizenShellState();
}

class _CitizenShellState extends ConsumerState<CitizenShell> {
  /// Resolved once, then the panes are built. Null while loading: the hosted
  /// screens take `username` as a constructor argument and each pane's Navigator
  /// builds its root route exactly once, so constructing them before the name is
  /// known would pin an empty username for the life of the shell.
  String? _username;

  /// One Navigator per pane — see the scaffolding note in the file header.
  final List<GlobalKey<NavigatorState>> _paneKeys = [
    for (final tab in CitizenTab.values)
      GlobalKey<NavigatorState>(debugLabel: 'pane-${tab.segment}'),
  ];

  // ── Deep-link plumbing (mirrors staff_console_screen.dart) ─────────────────
  /// Target awaiting the pane that owns it. One-shot.
  String? _pendingHighlightId;

  /// Bumped on every deep-link request. Panes must re-arm on a CHANGE to this
  /// rather than on the target's value: tapping the same notification twice
  /// produces an identical id, which reads as "nothing changed" and silently
  /// drops the second tap. This is the bug the nonce exists to prevent, and it
  /// is why [openTarget] bumps unconditionally instead of diffing the id.
  int _deepLinkNonce = 0;

  CitizenTab get _tab => tabForLocation(widget.location);
  int get _index => _tab.index;

  @override
  void initState() {
    super.initState();
    _resolveUsername();
    NotificationService.load().then((_) {
      if (mounted) setState(() {});
    });
    if (widget.target != null) _adoptTarget(widget.target!);
  }

  @override
  void didUpdateWidget(covariant CitizenShell old) {
    super.didUpdateWidget(old);
    // A target arriving on the URL (or changing) is a fresh deep link.
    final t = widget.target;
    if (t != null && (t != old.target || widget.location != old.location)) {
      _adoptTarget(t);
    }
  }

  Future<void> _resolveUsername() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    String? name;
    if (user != null) {
      try {
        final row = await client
            .from('profiles')
            .select('username')
            .eq('id', user.id)
            .maybeSingle();
        name = row?['username'] as String?;
      } catch (_) {
        // Fall through to the profile provider's display name.
      }
    }
    if (!mounted) return;
    setState(() {
      _username =
          name ?? ref.read(userProfileProvider).valueOrNull?.fullName ?? '';
    });
  }

  void _adoptTarget(String id) {
    setState(() {
      _pendingHighlightId = id;
      _deepLinkNonce++;
    });
  }

  /// Switch tabs, optionally carrying a deep-link target into the destination.
  ///
  /// The nonce bump is unconditional — see the field doc on [_deepLinkNonce].
  void openTarget(CitizenTab tab, {String? highlightId}) {
    if (highlightId != null) {
      setState(() {
        _pendingHighlightId = highlightId;
        _deepLinkNonce++;
      });
      context.go('${tab.path}?target=$highlightId');
      return;
    }
    context.go(tab.path);
  }

  void _selectIndex(int index) {
    if (index < 0 || index >= CitizenTab.values.length) return;
    final tab = CitizenTab.values[index];
    if (tab == _tab) return;
    // context.go pushes a browser history entry, which is what makes Back walk
    // between tabs instead of leaving the shell.
    context.go(tab.path);
  }

  // ── Chrome callbacks ──────────────────────────────────────────────────────

  Future<void> _showNotifications(double width) async {
    await showCitizenNotifications(
      context,
      width: width,
      onTap: (n) {
        NotificationService.markRead(n);
        Navigator.pop(context);
        // Routing a notification into a pane lands in Phase 2, when panes take
        // a highlightId. The mechanism it will use is already here: this is
        // exactly the openTarget(...) call the real wiring makes.
      },
    );
    if (mounted) setState(() {});
  }

  void _previewOnly(String what) {
    showAppSnackBar(
      context,
      '$what is disabled in the shell preview.',
      type: AppSnackType.info,
    );
  }

  /// Quick actions push into the CURRENT pane's Navigator, using the legacy
  /// route table. Phase 2 turns these into shell-owned dialogs.
  void _handleQuickAction(String key, bool isVerified) {
    final nav = _paneKeys[_index].currentState;
    if (nav == null || _username == null) return;
    switch (key) {
      case 'report':
        nav.pushNamed('/report', arguments: _username);
      case 'suggestion':
        nav.pushNamed('/suggestion', arguments: _username);
      case 'feedback':
        nav.pushNamed('/feedback', arguments: _username);
      case 'chat':
        nav.pushNamed('/chat', arguments: _username);
      case 'events':
        nav.pushNamed(
          '/events',
          arguments: {'username': _username, 'isVerified': isVerified},
        );
    }
  }

  // ── Panes ─────────────────────────────────────────────────────────────────

  Widget _screenFor(
    CitizenTab tab,
    String username,
    bool isVerified,
    String? barangay,
  ) {
    switch (tab) {
      case CitizenTab.home:
        return HomePage(username: username);
      case CitizenTab.myReports:
        return MyReportsScreen(username: username);
      case CitizenTab.newsfeed:
        return NewsFeedScreen(
          username: username,
          isVerified: isVerified,
          userBarangay: barangay,
        );
      case CitizenTab.emergency:
        return EmergencyScreen(username: username, isVerified: isVerified);
      case CitizenTab.settings:
        return SettingScreen(username: username);
    }
  }

  /// A pane: the hosted screen at the root of its own Navigator, with the
  /// legacy router handling anything pushed on top of it. Scaffolding — see the
  /// file header.
  Widget _pane(
    CitizenTab tab,
    String username,
    bool isVerified,
    String? barangay,
  ) {
    return Navigator(
      key: _paneKeys[tab.index],
      onGenerateRoute: (settings) {
        if (settings.name == Navigator.defaultRouteName) {
          return PageRouteBuilder(
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            pageBuilder: (_, _, _) =>
                _screenFor(tab, username, isVerified, barangay),
          );
        }
        return legacy_router.onGenerateRoute(settings);
      },
    );
  }

  // ── Deep-link instrumentation (preview only) ──────────────────────────────
  //
  // The hosted screens are full screens with no highlight parameter, and each
  // pane's Navigator builds its root exactly once, so a target cannot actually
  // be DELIVERED into a pane yet — that lands in Phase 2 along with the body
  // split. Until then this strip is where the target surfaces, which keeps the
  // mechanism honest (it is observably working rather than dead state) and
  // makes the nonce's purpose demonstrable: "Re-fire" repeats the SAME id and
  // the counter still advances, which is precisely the second tap that would
  // be dropped if panes diffed on the id alone.
  Widget _deepLinkStrip() {
    final id = _pendingHighlightId;
    if (id == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: CitizenUi.accentWash,
        border: Border(bottom: BorderSide(color: CitizenUi.border)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.my_location_rounded,
            size: 16,
            color: CitizenUi.accent,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Deep-link target "$id" pending for ${_tab.label} '
              '· nonce $_deepLinkNonce · delivery lands in Phase 2',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: CitizenUi.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => openTarget(_tab, highlightId: id),
            child: const Text('Re-fire'),
          ),
          TextButton(
            onPressed: () {
              setState(() => _pendingHighlightId = null);
              context.go(_tab.path);
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  // ── Left rail ─────────────────────────────────────────────────────────────

  static const List<(IconData, String)> _settingsStub = [
    (Icons.person_outline_rounded, 'Edit Profile'),
    (Icons.lock_outline_rounded, 'Change Password'),
    (Icons.folder_open_rounded, 'My Submissions'),
    (Icons.support_agent_rounded, 'Contact Support'),
    (Icons.info_outline_rounded, 'About GovPulse'),
  ];

  Widget _leftRail({
    required bool labelled,
    required String? fullName,
    required String? facePhotoUrl,
    required VerifStatus verif,
  }) {
    return Container(
      width: labelled ? _kRailLabelledWidth : _kRailIconWidth,
      decoration: const BoxDecoration(
        color: CitizenUi.surface,
        border: Border(right: BorderSide(color: CitizenUi.border)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: labelled ? 16 : 10,
          vertical: 18,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _profileCard(
              labelled: labelled,
              fullName: fullName,
              facePhotoUrl: facePhotoUrl,
              verif: verif,
            ),
            const SizedBox(height: 18),
            if (labelled) ...[
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  'ACCOUNT',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .8,
                    color: CitizenUi.textFaint,
                  ),
                ),
              ),
            ],
            // Stub rows. Phase 2 opens each of these as a showAppDialog instead
            // of a route; for now they surface the Settings pane so the rail is
            // real rather than dead.
            for (final (icon, label) in _settingsStub)
              _railRow(icon, label, labelled),
          ],
        ),
      ),
    );
  }

  Widget _profileCard({
    required bool labelled,
    required String? fullName,
    required String? facePhotoUrl,
    required VerifStatus verif,
  }) {
    final avatar = CircleAvatar(
      radius: labelled ? 26 : 18,
      backgroundColor: CitizenUi.accentWash,
      backgroundImage: (facePhotoUrl != null && facePhotoUrl.isNotEmpty)
          ? CachedNetworkImageProvider(facePhotoUrl)
          : null,
      child: (facePhotoUrl == null || facePhotoUrl.isEmpty)
          ? Icon(
              Icons.person_rounded,
              size: labelled ? 28 : 20,
              color: CitizenUi.accent,
            )
          : null,
    );

    if (!labelled) return Center(child: avatar);

    final (String statusLabel, Color statusColor) = switch (verif) {
      VerifStatus.verified => ('Verified', CitizenUi.success),
      VerifStatus.pending => ('Pending', CitizenUi.pending),
      VerifStatus.none => ('Not verified', CitizenUi.textMuted),
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CitizenUi.subtle,
        borderRadius: BorderRadius.circular(CitizenUi.cardRadius),
        border: Border.all(color: CitizenUi.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          avatar,
          const SizedBox(height: 10),
          Text(
            (fullName?.trim().isNotEmpty ?? false)
                ? fullName!.trim()
                : (_username ?? ''),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: CitizenUi.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                statusLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: statusColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _railRow(IconData icon, String label, bool labelled) {
    final row = _railRowBody(icon, label, labelled);
    // Only the icon-only rail needs a tooltip. Wrapping the labelled rows in a
    // Tooltip with an empty message would add a hover target that shows nothing
    // — and this app already carries a deliberate suppression for a framework
    // Tooltip assertion (see main.dart), so gratuitous tooltips are not free.
    return labelled ? row : Tooltip(message: label, child: row);
  }

  Widget _railRowBody(IconData icon, String label, bool labelled) {
    return InkWell(
      borderRadius: BorderRadius.circular(CitizenUi.controlRadius),
      onTap: () => _selectIndex(CitizenTab.settings.index),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: labelled ? 10 : 0,
          vertical: 11,
        ),
        child: Row(
          mainAxisAlignment: labelled
              ? MainAxisAlignment.start
              : MainAxisAlignment.center,
          children: [
            Icon(icon, size: 19, color: CitizenUi.textMuted),
            if (labelled) ...[
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: CitizenUi.textSecondary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Right sidebar ─────────────────────────────────────────────────────────

  Widget _rightSidebar(bool isVerified) {
    return Container(
      width: _kRightSidebarWidth,
      decoration: const BoxDecoration(
        color: CitizenUi.surface,
        border: Border(left: BorderSide(color: CitizenUi.border)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: HomeQuickActionsSectionWeb(
          onActionTap: (key) => _handleQuickAction(key, isVerified),
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final width = size.width;
    final layout = resolveShellLayout(size);

    final profile = ref.watch(userProfileProvider).valueOrNull;
    final verif = profile?.verifStatus ?? VerifStatus.none;
    final isVerified = verif == VerifStatus.verified;
    final username = _username;

    final Widget centre;
    if (username == null) {
      centre = const Center(child: CircularProgressIndicator());
    } else {
      centre = IndexedStack(
        index: _index,
        sizing: StackFit.expand,
        children: [
          for (final tab in CitizenTab.values)
            _pane(tab, username, isVerified, profile?.barangay),
        ],
      );
    }

    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeTopNav(
          currentIndex: _index,
          onTap: _selectIndex,
          notificationCount: NotificationService.count,
          onNotificationTap: () => _showNotifications(width),
          onLogoutTap: () => _previewOnly('Logout'),
          compact: width < 1050,
          username: username ?? '',
          fullName: profile?.fullName,
          facePhotoUrl: profile?.facePhotoUrl,
          verifStatus: switch (verif) {
            VerifStatus.verified => 'approved',
            VerifStatus.pending => 'pending',
            VerifStatus.none => 'none',
          },
        ),
        _deepLinkStrip(),
        Expanded(child: centre),
      ],
    );

    return Scaffold(
      backgroundColor: CitizenUi.pageBg,
      body: SafeArea(
        child: Row(
          children: [
            if (shellHasLeftRail(layout))
              _leftRail(
                labelled: layout != ShellLayout.railIcons,
                fullName: profile?.fullName,
                facePhotoUrl: profile?.facePhotoUrl,
                verif: verif,
              ),
            Expanded(child: column),
            if (shellHasRightSidebar(layout)) _rightSidebar(isVerified),
          ],
        ),
      ),
    );
  }
}
