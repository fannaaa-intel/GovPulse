import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/user_profile_provider.dart';
import '../../../core/theme/citizen_ui.dart';
import '../../../core/widgets/Home/Newsfeed/citizen_web_notification_panel.dart';
import '../../../core/widgets/Home/home_enums.dart';
import '../../../core/widgets/Home/nav/home_top_nav.dart';
import '../../../core/widgets/Home/nav/nav_band.dart';
import '../../../core/widgets/Home/sections/Web/home_quick_actions_section_web.dart';
import '../../../core/services/citizen_logout.dart';
import '../Quick-action/Events/events_screen.dart';
import '../Quick-action/Feedback/feedback_screen.dart';
import '../Quick-action/Report/report_issue_screen.dart';
import '../Quick-action/Suggestion/suggestion_screen.dart';
import '../screen/notification_popup.dart';
import '../settings/about/about_govpulse_screen.dart';
import '../settings/change-password/change_password_send_screen.dart';
import '../settings/contact-support/contact_support_screen.dart';
import '../settings/edit_profile_screen.dart';
import '../settings/my-submission/my_submissions_screen.dart';
import 'citizen_docked_chat.dart';
import 'citizen_shell_dialogs.dart';
import 'citizen_shell_router.dart';

// ════════════════════════════════════════════════════════════════════════════
//  CitizenShell — the persistent 3-column citizen web shell.
//
//  This is what citizens land on after signing in on web. The mobile app never
//  builds it — it keeps HomePage and the Navigator 1.0 table.
//
//  ── Layout ────────────────────────────────────────────────────────────────
//  A full-width top nav, and beneath it three columns:
//
//    ┌──────────────────────── HomeTopNav ────────────────────────┐
//    │  left rail   │        centre (branch)        │ right rail  │
//    │  profile +   │   the only column that swaps  │   quick     │
//    │  settings    │        on a tab change        │   actions   │
//    └──────────────┴───────────────────────────────┴─────────────┘
//
//  The Row is crossAxisAlignment.start, and each rail is a mainAxisSize.min
//  Column, so the rails HUG THE TOP flush under the nav instead of centring
//  themselves against a tall centre column. That is the Facebook arrangement and
//  the thing that stops short rails from floating in the middle of the page.
//
//  ── Persistence ───────────────────────────────────────────────────────────
//  The centre is [StatefulNavigationShell] — go_router's own IndexedStack over
//  the branches. Branches are built lazily on first visit and kept alive after,
//  so a tab keeps its scroll offset and loaded data, and tabs nobody opened
//  never run their fetches. Each branch owns a Navigator, so a detail route
//  pushed from a pane stacks inside that pane.
//
//  ── Bodies, not Screens ───────────────────────────────────────────────────
//  The shell mounts chromeless Bodies (NewsFeedBody, MyReportsBody, …), never
//  the standalone Screens. Hosting whole Screens would double the nav chrome,
//  the hero and Quick Actions, and would need a hand-rolled Navigator per pane
//  just so in-pane taps did not throw. go_router owns the branch navigators
//  instead, so neither hack is needed.
//
//  Settings is the one Body that knows it is in here: it takes `embedded: true`
//  so it can drop the account actions the left rail already provides.
// ════════════════════════════════════════════════════════════════════════════

/// Left rail width when it shows labels.
const double _kRailLabelledWidth = 288;

/// Left rail width when collapsed to icons.
const double _kRailIconWidth = 76;

/// Right quick-actions sidebar width.
const double _kRightSidebarWidth = 340;

class CitizenShell extends ConsumerStatefulWidget {
  /// go_router's branch container — both the selected index and the
  /// lazily-built IndexedStack of panes.
  final StatefulNavigationShell navigationShell;

  const CitizenShell({super.key, required this.navigationShell});

  /// Switch the shell under [context] to [tab]. Used by Bodies that need to
  /// send the user to another destination (Home's "View all" → NewsFeed).
  static void goToTab(BuildContext context, CitizenTab tab) {
    StatefulNavigationShell.of(context).goBranch(tab.index);
  }

  @override
  ConsumerState<CitizenShell> createState() => _CitizenShellState();
}

class _CitizenShellState extends ConsumerState<CitizenShell> {
  int get _index => widget.navigationShell.currentIndex;

  /// The docked chat window. Lives on the shell, not on a tab, so the
  /// conversation stays open across tab switches — the point of a docked window.
  DockedChatState _chat = DockedChatState.closed;

  @override
  void initState() {
    super.initState();
    NotificationService.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  /// Tapping the ALREADY-selected tab resets that branch to its root, which is
  /// how a shell is expected to behave (it pops a detail back to the list).
  /// Any other tab switches branch, keeping wherever that branch was left.
  void _selectIndex(int index) {
    if (index < 0 || index >= CitizenTab.values.length) return;
    widget.navigationShell.goBranch(index, initialLocation: index == _index);
  }

  // ── Chrome callbacks ──────────────────────────────────────────────────────

  Future<void> _showNotifications(double width) async {
    await showCitizenNotifications(
      context,
      width: width,
      onTap: (n) {
        NotificationService.markRead(n);
        Navigator.pop(context);
      },
    );
    if (mounted) setState(() {});
  }

  // ── Everything opens as a dialog ──────────────────────────────────────────
  //
  // Nothing below pushes a full-screen route. The shell — feed, both rails, the
  // top nav — stays mounted underneath, so closing returns you exactly where you
  // were with no reload and no history entry for what is really a panel.

  String get _username =>
      ref.read(userProfileProvider).valueOrNull?.username ?? '';

  bool get _isVerified =>
      ref.read(userProfileProvider).valueOrNull?.isVerified ?? false;

  /// The three long quick-action forms, as BIG modals over the feed.
  ///
  /// Each hosts the same `XxxForm` the standalone screen hosts, with
  /// `embedded: true` so the page chrome and the decorative hero panel are left
  /// out and the form scrolls inside the dialog. A [FormDialogGuard] carries the
  /// form's own discard confirmation to the dialog's close button.
  Future<void> _handleQuickAction(String key) async {
    final username = _username;
    final (String title, IconData icon) = switch (key) {
      'report' => ('Report an Issue', Icons.report_gmailerrorred_rounded),
      'suggestion' => ('Share a Suggestion', Icons.lightbulb_outline_rounded),
      'feedback' => ('Send Feedback', Icons.rate_review_outlined),
      'chat' => ('Chat with an Agent', Icons.support_agent_rounded),
      'events' => ('Events', Icons.event_rounded),
      _ => ('', Icons.help_outline_rounded),
    };
    if (title.isEmpty) return;

    // Chat is NOT a modal here. It opens the docked window: bottom-right,
    // no barrier, page stays live behind it. Re-triggering the action restores a
    // minimised or closed window rather than stacking a second one.
    if (key == 'chat') {
      setState(() => _chat = DockedChatState.open);
      return;
    }

    // Events is a browsing surface, not a form — same big modal, no form guard.
    if (key == 'events') {
      await showCitizenFormDialog<void>(
        context: context,
        title: title,
        icon: icon,
        builder: (dialogContext, close) => EventsScreen(
          username: username,
          isVerified: _isVerified,
          // Close the browsing modal, then open the event at its own
          // id-addressable URL so the detail is reload-proof and shareable
          // rather than trapped inside a dialog.
          //
          // go(), not push() — see the note on onOpenReport: a push leaves the
          // reported location on the branch root, so the address bar would keep
          // saying /home while an event was open and F5 would have no id.
          onOpenEvent: (event) {
            close();
            context.go(shellEventDetailPath(event.id), extra: event);
          },
        ),
      );
      return;
    }

    final guard = FormDialogGuard();
    await showCitizenFormDialog<void>(
      context: context,
      title: title,
      icon: icon,
      guard: guard,
      builder: (_, _) => switch (key) {
        'report' => ReportIssueForm(
          username: username,
          embedded: true,
          guard: guard,
        ),
        'suggestion' => SuggestionForm(
          username: username,
          embedded: true,
          guard: guard,
        ),
        _ => FeedbackForm(username: username, embedded: true, guard: guard),
      },
    );
  }

  // ── Left rail ─────────────────────────────────────────────────────────────

  /// Rail items, each opening the existing screen in a standard-size dialog.
  /// The hosted screen keeps its own header and its back button pops the
  /// dialog, so none of those screens needed changing.
  List<(IconData, String, Widget Function())> get _railItems => [
    (
      Icons.person_outline_rounded,
      'Edit Profile',
      () => EditProfileScreen(username: _username),
    ),
    (
      Icons.lock_outline_rounded,
      'Change Password',
      () => ChangePasswordSendScreen(
        email: ref.read(userProfileProvider).valueOrNull?.email ?? '',
      ),
    ),
    (
      Icons.folder_open_rounded,
      'My Submissions',
      () => MySubmissionsScreen(username: _username),
    ),
    (
      Icons.support_agent_rounded,
      'Contact Support',
      () => ContactSupportScreen(username: _username),
    ),
    (
      Icons.info_outline_rounded,
      'About GovPulse',
      () => const AboutGovPulseScreen(),
    ),
  ];

  Future<void> _openRailItem(Widget Function() build) =>
      showCitizenPanelDialog<void>(context: context, child: build());

  Widget _leftRail({required bool labelled, required UserProfile? profile}) {
    return SizedBox(
      width: labelled ? _kRailLabelledWidth : _kRailIconWidth,
      child: Padding(
        padding: EdgeInsets.fromLTRB(labelled ? 20 : 10, 20, 8, 20),
        child: Column(
          // mainAxisSize.min + the Row's start alignment is what pins the rail
          // to the top instead of letting it centre against the centre column.
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _profileCard(labelled: labelled, profile: profile),
            const SizedBox(height: 16),
            if (labelled)
              const Padding(
                padding: EdgeInsets.only(left: 6, bottom: 6),
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
            // Each opens its existing screen in a standard-size dialog over the
            // still-mounted shell — see [_openRailItem].
            for (final (icon, label, build) in _railItems)
              _railRow(icon, label, labelled, () => _openRailItem(build)),
          ],
        ),
      ),
    );
  }

  Widget _profileCard({required bool labelled, required UserProfile? profile}) {
    final photo = profile?.facePhotoUrl;
    final avatar = CircleAvatar(
      radius: labelled ? 24 : 18,
      backgroundColor: CitizenUi.accentWash,
      backgroundImage: (photo != null && photo.isNotEmpty)
          ? CachedNetworkImageProvider(photo)
          : null,
      child: (photo == null || photo.isEmpty)
          ? Icon(
              Icons.person_rounded,
              size: labelled ? 26 : 20,
              color: CitizenUi.accent,
            )
          : null,
    );

    if (!labelled) return Center(child: avatar);

    final verif = profile?.verifStatus ?? VerifStatus.none;
    final (String statusLabel, Color statusColor) = switch (verif) {
      VerifStatus.verified => ('Verified', CitizenUi.success),
      VerifStatus.pending => ('Pending', CitizenUi.pending),
      VerifStatus.none => ('Not verified', CitizenUi.textMuted),
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CitizenUi.surface,
        borderRadius: BorderRadius.circular(CitizenUi.cardRadius),
        border: Border.all(color: CitizenUi.border),
      ),
      child: Row(
        children: [
          avatar,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  profile?.displayName ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: CitizenUi.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
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
          ),
        ],
      ),
    );
  }

  Widget _railRow(
    IconData icon,
    String label,
    bool labelled,
    VoidCallback onTap,
  ) {
    final row = InkWell(
      borderRadius: BorderRadius.circular(CitizenUi.controlRadius),
      onTap: onTap,
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
    // Only the icon-only rail needs a tooltip. An empty-message Tooltip is a
    // hover target that shows nothing, and this app already carries a deliberate
    // suppression for a framework Tooltip assertion (see main.dart).
    return labelled ? row : Tooltip(message: label, child: row);
  }

  // ── Right sidebar ─────────────────────────────────────────────────────────

  Widget _rightSidebar() {
    return SizedBox(
      width: _kRightSidebarWidth,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 20, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HomeQuickActionsSectionWeb(onActionTap: _handleQuickAction),
          ],
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

    return Scaffold(
      backgroundColor: CitizenUi.pageBg,
      // The docked chat floats over the columns in a Stack rather than in a
      // route or a dialog. No barrier is inserted, so everything behind it stays
      // scrollable and clickable while it is open.
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // One top nav, spanning ALL three columns — the rails sit flush
                // beneath it rather than beside it.
                HomeTopNav(
                  currentIndex: _index,
                  onTap: _selectIndex,
                  // Home · My Reports · Emergency. NewsFeed is gone: Home's centre
                  // is the feed now. Settings is reached from the user chip, so it
                  // is not a nav link — but its index moved to 3 when NewsFeed left,
                  // hence settingsIndex.
                  items: [
                    for (final tab in CitizenTab.values)
                      if (tab != CitizenTab.settings)
                        (label: tab.label, index: tab.index),
                  ],
                  settingsIndex: CitizenTab.settings.index,
                  notificationCount: NotificationService.count,
                  onNotificationTap: () => _showNotifications(width),
                  // The shared flow, same as Settings and the nav chrome use.
                  onLogoutTap: () => performCitizenLogout(context, ref),
                  compact: width < 1050,
                  username: profile?.username ?? '',
                  fullName: profile?.fullName,
                  facePhotoUrl: profile?.facePhotoUrl,
                  verifStatus: switch (verif) {
                    VerifStatus.verified => 'approved',
                    VerifStatus.pending => 'pending',
                    VerifStatus.none => 'none',
                  },
                ),
                Expanded(
                  child: Row(
                    // Pins both rails to the top; only the centre column stretches.
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (shellHasLeftRail(layout))
                        _leftRail(
                          labelled: layout != ShellLayout.railIcons,
                          profile: profile,
                        ),
                      // The centre must fill the height — it owns the scrolling.
                      //
                      // The MediaQuery override reports the CENTRE COLUMN's size to
                      // the panes rather than the viewport's. Bodies size themselves
                      // off MediaQuery (`width * 0.0x`, and a >= 900 "wide" test),
                      // so without this a pane in a ~650px column would lay itself
                      // out for a 1280px page and overflow. Same trick
                      // ResponsiveNavScaffold._constrained already uses to keep a
                      // max-width body self-consistent.
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) => MediaQuery(
                            data: MediaQuery.of(context).copyWith(
                              size: Size(
                                constraints.maxWidth,
                                constraints.maxHeight,
                              ),
                            ),
                            child: SizedBox.expand(
                              child: widget.navigationShell,
                            ),
                          ),
                        ),
                      ),
                      if (shellHasRightSidebar(layout)) _rightSidebar(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          CitizenDockedChat(
            state: _chat,
            onMinimise: () => setState(() => _chat = DockedChatState.minimised),
            onRestore: () => setState(() => _chat = DockedChatState.open),
            onClose: () => setState(() => _chat = DockedChatState.closed),
          ),
        ],
      ),
    );
  }
}
