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
import '../../../core/router/legacy_nav.dart';
import '../../../core/services/auth_ready.dart';
import '../../../core/services/citizen_guard.dart';
import '../../../core/services/citizen_logout.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/citizen_guard_modals.dart';
import '../../../core/widgets/modal/verification_required_dialog.dart';
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

/// Left rail width, in logical pixels, when it shows labels.
const double _kRailLabelledWidth = 288;

// There is deliberately no icon-only rail width any more. The 900–1024 band
// used to collapse the rail to icons, but with NAVIGATE, ACCOUNT and QUICK
// ACTIONS all living there that became ~11 unlabelled icons in three unlabelled
// clusters, and hover tooltips did not rescue it. That band now gets the drawer
// instead — see [_isDrawerMode].

/// Right quick-actions sidebar width.
const double _kRightSidebarWidth = 340;

/// Below this the top nav's user chip collapses to its avatar.
///
/// Local to the shell rather than in nav_band.dart: that file is imported by
/// responsive_nav_scaffold and home_screen, so a constant there would put a
/// diff in the mobile app for a web-only concern.
const double _kAvatarOnlyChipBelow = 600;

/// Quick actions, as rail rows. Same keys [_handleQuickAction] switches on, so
/// tapping one here is identical to tapping its card in the right sidebar.
const List<({String key, IconData icon, String label})> _kQuickActions = [
  (
    key: 'report',
    icon: Icons.report_gmailerrorred_rounded,
    label: 'Report an Issue',
  ),
  (
    key: 'suggestion',
    icon: Icons.lightbulb_outline_rounded,
    label: 'Share a Suggestion',
  ),
  (key: 'feedback', icon: Icons.rate_review_outlined, label: 'Send Feedback'),
  (key: 'chat', icon: Icons.support_agent_rounded, label: 'Chat with an Agent'),
  (key: 'events', icon: Icons.event_rounded, label: 'View Events'),
];

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

  /// Needed because the hamburger is built in the SAME build() that returns the
  /// Scaffold, so `Scaffold.of(context)` there would look above it and fail.
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  /// Runs [action], closing the drawer first when the tap came from inside it.
  ///
  /// Every rail control does the same thing in the drawer as it does inline —
  /// same handler, same gate, same dialog — and the only difference is that the
  /// drawer has to get out of the way first, or the panel it opens would be
  /// stacked over a still-open drawer.
  VoidCallback _fromDrawer(VoidCallback action, {required bool inDrawer}) {
    return () {
      if (inDrawer) _scaffoldKey.currentState?.closeDrawer();
      action();
    };
  }

  /// The docked chat window. Lives on the shell, not on a tab, so the
  /// conversation stays open across tab switches — the point of a docked window.
  DockedChatState _chat = DockedChatState.closed;

  @override
  void initState() {
    super.initState();
    NotificationService.load().then((_) {
      if (mounted) setState(() {});
    });
    _startGuard();
  }

  // ── Account enforcement ───────────────────────────────────────────────────
  //
  // The web twin of what the mobile HomePage does in its own initState:
  // suspension → blocking modal + sign out, restriction → one notice. Until
  // this existed the web shell started no guard at all, so a suspended or
  // restricted citizen saw nothing here and their refusals arrived only as
  // opaque RLS failures.
  //
  // NOT an enforcement boundary — a browser user can edit the URL or go back.
  // RLS and the DB triggers are the boundary; this makes the refusal legible.

  /// True while a guard modal is on screen, so a second status event during a
  /// modal's lifetime cannot stack another one on top.
  bool _guardModalOpen = false;

  /// The restriction signature already announced in THIS process.
  String? _shownRestrictionSig;

  /// Starts the guard once a session actually exists.
  ///
  /// [CitizenGuard.start] reads `currentUser` and returns SILENTLY when there
  /// is none, so calling it straight from initState would be a no-op on a cold
  /// load — the shell mounts while Supabase is still restoring, and the guard
  /// would simply never subscribe. Mobile never meets this because the splash
  /// animation guarantees a session before HomePage builds; the web shell has
  /// no such gap, which is exactly how this would have shipped silently broken.
  ///
  /// [awaitAuthReady] returns immediately when a session is already restored,
  /// so in-session navigation pays nothing.
  Future<void> _startGuard() async {
    await awaitAuthReady();
    if (!mounted) return;
    await CitizenGuard.I.start();
    if (!mounted) return;
    CitizenGuard.I.status.addListener(_onGuardStatus);
    // First evaluation: start() already refreshed, so a suspension that was in
    // place BEFORE this mount is announced now rather than waiting for a change.
    _onGuardStatus();
  }

  void _onGuardStatus() {
    if (!mounted || _guardModalOpen) return;
    final status = CitizenGuard.I.status.value;

    // Suspension wins: it is blocking and ends in a sign-out, so there is no
    // point announcing a restriction the user is about to lose access to.
    final suspension = status.suspension;
    if (suspension != null) {
      _guardModalOpen = true;
      showSuspendedModal(
        context,
        suspension,
      ).whenComplete(() => _guardModalOpen = false);
      return;
    }

    final restriction = status.restriction;
    if (restriction != null) _maybeShowRestriction(restriction);
  }

  /// Shows the restriction notice once per distinct restriction per session —
  /// on a live change, and once on first entry — but NOT on every reload.
  ///
  /// Two checks because they cover different lifetimes. [_shownRestrictionSig]
  /// is this process and answers instantly, which keeps the common case off the
  /// plugin channel. The persisted marker survives a browser refresh, which is
  /// a new process on the SAME session and would otherwise re-fire the notice
  /// on every F5.
  Future<void> _maybeShowRestriction(RestrictionInfo restriction) async {
    final signature = restriction.signature;
    if (_shownRestrictionSig == signature) return;

    if (await CitizenGuard.restrictionNoticeShown(signature)) {
      // Already announced earlier in this session, in a previous process.
      // Remember it here too so later events skip the async check entirely.
      _shownRestrictionSig = signature;
      return;
    }

    // Re-checked after the await: the shell may have gone, or a suspension may
    // have opened its own modal while this was resolving.
    if (!mounted || _guardModalOpen) return;

    _shownRestrictionSig = signature;
    await CitizenGuard.markRestrictionNoticeShown(signature);
    if (!mounted) return;

    _guardModalOpen = true;
    showRestrictionNotice(
      context,
      restriction,
    ).whenComplete(() => _guardModalOpen = false);
  }

  @override
  void dispose() {
    // Symmetric with [_startGuard]. stop() unsubscribes the realtime channel,
    // clears _subUid and resets status to a blank CitizenStatus, so no guard
    // state can survive into another session. The sign-out teardown stops it
    // too; both are idempotent, and between them the shell unmounting and the
    // session ending are each covered on their own.
    CitizenGuard.I.status.removeListener(_onGuardStatus);
    CitizenGuard.I.stop();
    super.dispose();
  }

  /// Tapping the ALREADY-selected tab resets that branch to its root, which is
  /// how a shell is expected to behave (it pops a detail back to the list).
  /// Any other tab switches branch, keeping wherever that branch was left.
  ///
  /// My Reports is gated, matching the mobile nav. The check runs BEFORE
  /// `goBranch`, and a refusal simply returns — so the branch never switches.
  /// Nothing goes half-selected as a result: [HomeTopNav] derives its highlight
  /// from `currentIndex`, which is `navigationShell.currentIndex`, and that is
  /// unchanged when `goBranch` is not called. Home and Emergency are not gated.
  Future<void> _selectIndex(int index) async {
    if (index < 0 || index >= CitizenTab.values.length) return;

    if (CitizenTab.values[index] == CitizenTab.myReports) {
      if (!await _requireVerified(
        'Only verified citizens can access My Reports.',
      )) {
        return;
      }
      if (!mounted) return;
    }

    widget.navigationShell.goBranch(index, initialLocation: index == _index);
  }

  // ── Chrome callbacks ──────────────────────────────────────────────────────

  Future<void> _showNotifications(double width) async {
    await showCitizenNotifications(
      context,
      width: width,
      onTap: (n) {
        // Opening it IS reading it — retire it from the badge before routing,
        // so the count drops on tap instead of waiting for a delete. Same
        // ordering the two legacy surfaces use.
        NotificationService.markRead(n);
        Navigator.pop(context); // close the panel, then route the tap
        _routeNotificationTap(n);
      },
    );
    if (mounted) setState(() {});
  }

  /// Routes a notification tap to a SHELL destination.
  ///
  /// ── Why not routeCitizenNotificationTap ────────────────────────────────────
  /// That function is shared with the mobile surface, and five of its seven
  /// branches reach their destination with `pushLegacy` — /my_submissions,
  /// /chat, /report_detail. Calling it here would push full-screen legacy
  /// routes over the shell: the wrong destination model (the same reason the
  /// drawer below hosts _leftRail rather than HomeNavDrawer), and pageless
  /// pushes over go_router's stack, which is the desync class the auth flows
  /// were just cleaned of.
  ///
  /// So the shell owns its own switch. That duplicates the type vocabulary in
  /// two places and the two can drift — a real cost, accepted deliberately:
  /// the alternative is refactoring a function two mobile screens depend on,
  /// which would turn a web-only change into a shared-file one. If a third
  /// surface ever needs this, extract a pure type→intent function and let each
  /// surface keep its own destinations.
  ///
  /// ── Coverage ───────────────────────────────────────────────────────────────
  /// The five types with a destination the shell already has. The four social
  /// types (post_like / post_comment / comment_reply / comment_like) fall
  /// through to the default: the shell mounts `const NewsFeedBody(embedded:
  /// true)` with no initialPostId, so there is no way to point the Home pane at
  /// a post yet. They do nothing today and continue to do nothing — no
  /// regression, and deep-linking into the shell feed is its own piece of work.
  /// Everything else (verification_submitted, the verified notice, broadcasts,
  /// staff messages, general) is informational on every surface.
  void _routeNotificationTap(AppNotification n) {
    switch (n.type) {
      case 'report_decision':
        // reference_id holds the report id — read straight through by
        // AppNotification.fromRow. (_effectivePostId deliberately does NOT
        // claim it: that helper is restricted to social types precisely so a
        // report's reference_id is never mistaken for a post id.)
        //
        // Older rows predate the deep-link column and carry no id; they route
        // nowhere, same as on mobile.
        final reportId = n.referenceId;
        if (reportId == null || reportId.isEmpty) return;
        // No pre-fetch, unlike the legacy path's _openReportFromNotification:
        // this route is id-addressable and ResolveById fetches by id when no
        // `extra` rides along. That also makes the destination reload-proof
        // and shareable, which the legacy /report_detail cannot be.
        //
        // go(), not push() — a push would leave the reported location on the
        // branch root, so the address bar would keep saying /my-reports.
        context.go(shellReportDetailPath(reportId));
        break;

      case 'verification_reminder':
        // Reuses the shell's own entry point, which already carries both
        // guards this needs: it no-ops when the profile has not loaded, and
        // when verifStatus is anything but none — so a verified or
        // already-pending citizen taps into nothing, matching mobile.
        _startVerification();
        break;

      case 'suggestion_response':
        _openSubmissionsFromNotification(initialTab: 1, highlightId: n.referenceId);
        break;

      case 'feedback_response':
        _openSubmissionsFromNotification(initialTab: 2, highlightId: n.referenceId);
        break;

      case 'post_like':
      case 'post_comment':
      case 'comment_reply':
      case 'comment_like':
        // `n.postId`, NOT `n.referenceId`. AppNotification.fromRow already ran
        // _effectivePostId for social types, which reads whichever column the
        // writing trigger used — the triggers this repo ships stamp
        // reference_id, but some live ones stamp a post_id column instead, and
        // reading only one of them is what made these taps land nowhere before.
        // referenceId is the raw column and would miss half the writers.
        final postRef = n.postId;
        if (postRef == null || postRef.isEmpty) return;
        // Same split as the legacy surfaces: anything about a comment opens the
        // thread, a heart just jumps to the post and flashes it. The flash and
        // the sheet are mutually exclusive — a ring behind an open sheet is
        // only discovered after closing it.
        final openComments = n.type != 'post_like';
        // A URL, not shell state: this location is reload-proof and pasteable,
        // and go() re-resolves the branch so this works from any tab.
        context.go(
          shellFeedPostPath(
            postRef,
            openComments: openComments,
            highlight: !openComments,
          ),
        );
        break;

      case 'chat':
        // A citizen has exactly one LGU thread, so there is nothing to
        // disambiguate and no id to carry — opening the window IS landing on
        // the message. Not routed through the quick action, which gates on
        // verification: this notification is evidence the thread already
        // exists, and refusing someone their own staff reply is the worse
        // failure. The legacy path does not gate it either.
        setState(() => _chat = DockedChatState.open);
        break;

      default:
        break;
    }
  }

  /// My Submissions, opened on the tab the notification refers to with its item
  /// flashed. The screen already accepts both — the rail simply never passed
  /// them, so the parameters existed with no caller.
  ///
  /// Ungated, unlike the rail's copy of this dialog. Receiving a response means
  /// they submitted, which required verification at the time; and the screen
  /// shows only their own RLS-scoped rows. This matches the legacy notification
  /// path, which does not gate it either.
  void _openSubmissionsFromNotification({
    required int initialTab,
    String? highlightId,
  }) {
    // Don't stack a second copy over one already open — same guard the legacy
    // path uses.
    if (MySubmissionsScreen.isOpen) return;
    showCitizenPanelDialog<void>(
      context: context,
      child: MySubmissionsScreen(
        username: _username,
        initialTab: initialTab,
        highlightId: highlightId,
      ),
    );
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

  // ── Verification gate ─────────────────────────────────────────────────────
  //
  // The shell reimplemented the citizen chrome — quick actions, the left rail,
  // the top nav — and in doing so left every gated entry point ungated, so an
  // unverified citizen on web had no way to be prompted to verify at all. This
  // is the single place that gap is closed, mirroring what the mobile Home
  // screen and nav already do at each of their entry points.
  //
  // The feed's own Like / Comment gates are NOT routed through here: they live
  // in NewsFeedBody, are shared with mobile, and already work.

  /// Told to the user when they act before [userProfileProvider] has landed.
  /// Shared by the gate and by the rail's Verify affordance so the
  /// loading-window answer is written once.
  void _notifyProfileStillLoading() {
    showAppSnackBar(
      context,
      'Still loading your profile — please try that again in a moment.',
      type: AppSnackType.info,
    );
  }

  /// Opens the verification wizard DIRECTLY, without a gate modal in front.
  ///
  /// Until this existed the wizard was reachable only by tripping a gate, so a
  /// citizen who simply wanted to verify had nowhere to click. Same launch path
  /// as the gate modal's Verify button and as mobile's "Verify Now" button:
  /// the legacy `/verification` route with the account handle.
  void _startVerification() {
    final profile = ref.read(userProfileProvider).valueOrNull;

    // Defensive: the affordance is not rendered until the profile loads, so
    // this should be unreachable — but it must never launch the wizard with the
    // '' that the loading window would produce.
    if (profile == null) {
      _notifyProfileStillLoading();
      return;
    }

    // Mirrors mobile's _goToVerification: a pending submission must not re-enter
    // the wizard, since the submit step rejects a second pending row outright.
    if (profile.verifStatus != VerifStatus.none) return;

    pushLegacy(context, '/verification', arguments: profile.username ?? '');
  }

  /// True when [message]'s action may proceed. False means it was refused and
  /// the caller must return without doing anything — the dialog (or toast) has
  /// already been shown.
  Future<bool> _requireVerified(String message) async {
    final profile = ref.read(userProfileProvider).valueOrNull;

    // Profile not resolved yet. On a cold load the shell paints before the
    // provider lands, and in that window `_isVerified` reads false and
    // `_username` reads '' — so gating on them here would pop the dialog and
    // then hand the wizard an EMPTY username. A tap that lands early is not a
    // refusal, it is just early, so say so and let them tap again.
    if (profile == null) {
      _notifyProfileStillLoading();
      return false;
    }

    if (profile.isVerified) return true;

    await showVerificationRequiredDialog(
      context,
      // Status is already known here, so the dialog must not re-query for it.
      isVerified: false,
      // Non-null by construction: the profile has loaded, so the wizard is
      // never opened with the '' that the loading window would have produced.
      username: profile.username ?? '',
      message: message,
    );
    return false;
  }

  /// The three long quick-action forms, as BIG modals over the feed.
  ///
  /// Each hosts the same `XxxForm` the standalone screen hosts, with
  /// `embedded: true` so the page chrome and the decorative hero panel are left
  /// out and the form scrolls inside the dialog. A [FormDialogGuard] carries the
  /// form's own discard confirmation to the dialog's close button.
  Future<void> _handleQuickAction(String key) async {
    final (String title, IconData icon) = switch (key) {
      'report' => ('Report an Issue', Icons.report_gmailerrorred_rounded),
      'suggestion' => ('Share a Suggestion', Icons.lightbulb_outline_rounded),
      'feedback' => ('Send Feedback', Icons.rate_review_outlined),
      'chat' => ('Chat with an Agent', Icons.support_agent_rounded),
      'events' => ('Events', Icons.event_rounded),
      _ => ('', Icons.help_outline_rounded),
    };
    if (title.isEmpty) return;

    // Gated BEFORE anything opens, so an unverified citizen never gets a form
    // they cannot submit or a docked chat they cannot use. Wording matches the
    // mobile Home screen's tiles one for one.
    //
    // Events is the one that diverges: mobile does not gate browsing events.
    // Gating it here is a deliberate product call, not an oversight.
    final gateMessage = switch (key) {
      'report' =>
        'Only verified Aparri citizens can submit a report. '
            'Please complete your identity verification first.',
      'suggestion' =>
        'Only verified Aparri citizens can submit a suggestion. '
            'Please complete your identity verification first.',
      'feedback' =>
        'Only verified Aparri citizens can submit feedback. '
            'Please complete your identity verification first.',
      'chat' =>
        'Only verified Aparri citizens can chat with an agent. '
            'Please complete your identity verification first.',
      _ =>
        'Only verified Aparri citizens can browse community events. '
            'Please complete your identity verification first.',
    };
    if (!await _requireVerified(gateMessage)) return;
    if (!mounted) return;

    // Read AFTER the gate: it only passes once the profile has loaded, so this
    // can never be the '' of the loading window.
    final username = _username;

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
  /// `verifyMessage` non-null means the item is behind the verification gate.
  /// Only Edit Profile and My Submissions are — matching the mobile Settings
  /// page, which gates exactly those two and leaves Change Password, Contact
  /// Support and About open to everyone. Support in particular must stay
  /// reachable: an unverified citizen having trouble verifying needs it most.
  List<({IconData icon, String label, String? verifyMessage, Widget Function() build})>
  get _railItems => [
    (
      icon: Icons.person_outline_rounded,
      label: 'Edit Profile',
      verifyMessage:
          'Only verified citizens can edit their profile information. '
          'Please complete the identity verification process first.',
      build: () => EditProfileScreen(username: _username),
    ),
    (
      icon: Icons.lock_outline_rounded,
      label: 'Change Password',
      verifyMessage: null,
      build: () => ChangePasswordSendScreen(
        email: ref.read(userProfileProvider).valueOrNull?.email ?? '',
      ),
    ),
    (
      icon: Icons.folder_open_rounded,
      label: 'My Submissions',
      verifyMessage:
          'Only verified citizens can view their submission history. '
          'Please complete the identity verification process first.',
      build: () => MySubmissionsScreen(username: _username),
    ),
    (
      icon: Icons.support_agent_rounded,
      label: 'Contact Support',
      verifyMessage: null,
      build: () => ContactSupportScreen(username: _username),
    ),
    (
      icon: Icons.info_outline_rounded,
      label: 'About GovPulse',
      verifyMessage: null,
      build: () => const AboutGovPulseScreen(),
    ),
  ];

  Future<void> _openRailItem(
    ({
      IconData icon,
      String label,
      String? verifyMessage,
      Widget Function() build,
    })
    item,
  ) async {
    final gate = item.verifyMessage;
    if (gate != null && !await _requireVerified(gate)) return;
    if (!mounted) return;
    await showCitizenPanelDialog<void>(context: context, child: item.build());
  }

  /// Section heading in the rail ("ACCOUNT", "NAVIGATE", "QUICK ACTIONS").
  Widget _railHeading(String text) => Padding(
    padding: const EdgeInsets.only(left: 6, bottom: 6),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: .8,
        color: CitizenUi.textFaint,
      ),
    ),
  );

  /// The rail's contents, inline in the columns or inside the drawer.
  ///
  /// Always labelled. The icon-only variant is gone: it only ever applied to
  /// the 900–1024 band, and once the rail carried three sections that band was
  /// showing ~11 bare icons in three unlabelled clusters. Below 1024 the drawer
  /// takes over instead, and the drawer is always labelled.
  ///
  /// [inDrawer] changes one thing: every tap closes the drawer first.
  ///
  /// [showNav] appends the NAVIGATE section — the tab destinations. It is set
  /// exactly when the top nav is NOT showing its centred links, so the two are
  /// complements and the destinations are always reachable from exactly one
  /// place. It routes through [_selectIndex], the same handler the top nav
  /// uses, so the My Reports verification gate applies identically.
  ///
  /// [showQuickActions] appends the QUICK ACTIONS section — set whenever the
  /// right sidebar is not there to hold them.
  Widget _leftRail({
    required UserProfile? profile,
    required bool showNav,
    required bool showQuickActions,
    bool inDrawer = false,
  }) {
    return SizedBox(
      width: _kRailLabelledWidth,
      // Scrolls because the rail carries up to three sections — ~760px of
      // content, which overflows any window shorter than ~820, and a 1366x768
      // laptop leaves about 708. Under the Row's loose vertical constraints a
      // SingleChildScrollView shrink-wraps to its content and only scrolls once
      // it would exceed the height, so the rail still hugs the top exactly as
      // before on a tall window.
      //
      // This is also why [_shellDrawer] does NOT add a scroll view of its own:
      // nesting two in the same axis would hand this one an unbounded height.
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 8, 20),
          child: Column(
            // mainAxisSize.min is what pins the rail to the top rather than
            // letting it centre against the centre column.
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _profileCard(profile: profile, inDrawer: inDrawer),
              const SizedBox(height: 16),
              if (showNav) ...[
                _railHeading('NAVIGATE'),
                // Mirrors the top nav's destinations exactly. Settings is left
                // out for the same reason it is not a top-nav link: the user
                // chip owns it, and the chip is visible at every width.
                for (final tab in CitizenTab.values)
                  if (tab != CitizenTab.settings)
                    _railRow(
                      tab.icon,
                      tab.label,
                      _fromDrawer(
                        () => _selectIndex(tab.index),
                        inDrawer: inDrawer,
                      ),
                      selected: tab.index == _index,
                    ),
                const SizedBox(height: 14),
              ],
              _railHeading('ACCOUNT'),
              // Each opens its existing screen in a standard-size dialog over
              // the still-mounted shell — see [_openRailItem].
              for (final item in _railItems)
                _railRow(
                  item.icon,
                  item.label,
                  _fromDrawer(
                    () => _openRailItem(item),
                    inDrawer: inDrawer,
                  ),
                ),
              // Quick actions have no home once the right sidebar is dropped,
              // so the rail takes them. Routed through [_handleQuickAction] —
              // the SAME handler the sidebar's cards call — so the verification
              // gate fires, the forms open as dialogs and chat docks.
              if (showQuickActions) ...[
                const SizedBox(height: 14),
                _railHeading('QUICK ACTIONS'),
                for (final qa in _kQuickActions)
                  _railRow(
                    qa.icon,
                    qa.label,
                    _fromDrawer(
                      () => _handleQuickAction(qa.key),
                      inDrawer: inDrawer,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _profileCard({required UserProfile? profile, bool inDrawer = false}) {
    final photo = profile?.facePhotoUrl;
    final avatar = CircleAvatar(
      radius: 24,
      backgroundColor: CitizenUi.accentWash,
      backgroundImage: (photo != null && photo.isNotEmpty)
          ? CachedNetworkImageProvider(photo)
          : null,
      child: (photo == null || photo.isEmpty)
          ? const Icon(Icons.person_rounded, size: 26, color: CitizenUi.accent)
          : null,
    );

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
                _statusPill(
                  label: statusLabel,
                  color: statusColor,
                  // Only an account we KNOW is unverified gets the affordance.
                  // `verif` falls back to none while the profile is still
                  // loading, so without the null test the rail would flash
                  // "Verify now" at a verified citizen on every cold load —
                  // the same trap mobile's profile card guards with
                  // `!profileLoading`.
                  canVerify: profile != null && verif == VerifStatus.none,
                  onTap: _fromDrawer(_startVerification, inDrawer: inDrawer),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The account card's status line.
  ///
  /// Verified and Pending render EXACTLY as before — dot plus label, inert.
  /// Only a known-unverified account gets the extra "Verify now" affordance and
  /// becomes tappable, which is the shell's one direct route into the wizard.
  /// Pending is deliberately not actionable, matching mobile, where the Verify
  /// button is present but disabled while a submission is under review.
  Widget _statusPill({
    required String label,
    required Color color,
    required bool canVerify,
    required VoidCallback onTap,
  }) {
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
        if (canVerify) ...[
          const SizedBox(width: 7),
          const Text(
            '·',
            style: TextStyle(fontSize: 12, color: CitizenUi.textFaint),
          ),
          const SizedBox(width: 7),
          const Text(
            'Verify now',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: CitizenUi.accent,
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            size: 15,
            color: CitizenUi.accent,
          ),
        ],
      ],
    );

    if (!canVerify) return row;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(CitizenUi.controlRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: row,
      ),
    );
  }

  /// [selected] is only ever set by the drawer's NAVIGATE rows, so it marks the
  /// branch you are currently on. The account rows never pass it — they open
  /// dialogs, and a dialog is not a destination you can be "on".
  Widget _railRow(
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool selected = false,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(CitizenUi.controlRadius),
      onTap: onTap,
      child: Container(
        decoration: selected
            ? BoxDecoration(
                color: CitizenUi.accentWash,
                borderRadius: BorderRadius.circular(CitizenUi.controlRadius),
              )
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        child: Row(
          children: [
            Icon(
              icon,
              size: 19,
              color: selected ? CitizenUi.accent : CitizenUi.textMuted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: selected
                      ? CitizenUi.accent
                      : CitizenUi.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    // No Tooltip wrapper any more: it existed only to name the icons in the
    // icon-only rail, and every row carries its own label now.
  }

  // ── Drawer (<1024) ────────────────────────────────────────────────────────
  //
  // Below kShellRailLabelsMin the inline rail is gone, and before this existed
  // nothing replaced it — Edit Profile, Change Password, My Submissions,
  // Contact Support, About and the "Verify now" pill were all simply
  // unreachable on a narrow browser. This is that rail, in a drawer.
  //
  // It hosts the SHELL's rail, not HomeNavDrawer: that widget belongs to the
  // legacy nav contract and routes with pushLegacy('/my_reports') and friends,
  // which is the wrong destination model for the shell (and its file is shared
  // with the mobile app). Reusing [_leftRail] means the gates, the verification
  // entry point and every rail dialog keep working with no second copy.

  Widget _shellDrawer(UserProfile? profile) {
    return Drawer(
      width: _kRailLabelledWidth,
      backgroundColor: CitizenUi.pageBg,
      child: SafeArea(
        // No scroll view here — [_leftRail] owns its own, and nesting two in
        // the same axis would give the inner one an unbounded height.
        child: SizedBox.expand(
          child: _leftRail(
            profile: profile,
            inDrawer: true,
            // The drawer only exists below 1024 — below the line where the top
            // nav can fit its links, and below the line where the right sidebar
            // survives — so it always carries both sections.
            showNav: true,
            showQuickActions: true,
          ),
        ),
      ),
    );
  }

  /// The hamburger, drawn as a seamless extension of [HomeTopNav]'s bar.
  ///
  /// It has to sit BESIDE the nav rather than inside it: HomeTopNav is shared
  /// with responsive_nav_scaffold and home_screen, so adding a menu slot to it
  /// would put a diff in the mobile app for a web-only affordance. Matching its
  /// height, fill, border and shadow makes the two read as one bar.
  Widget _hamburger() {
    return Container(
      height: 60,
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(
          bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      // Tight tap target rather than IconButton's default 48px box: every
      // pixel here comes straight off the nav's remaining width, and the nav is
      // already the tightest thing on screen in this band.
      child: Center(
        child: IconButton(
          icon: const Icon(Icons.menu_rounded, color: CitizenUi.textSecondary),
          iconSize: 22,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 36, height: 36),
          tooltip: 'Menu',
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
      ),
    );
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

    // ── Three bands, not four ────────────────────────────────────────────────
    //
    //   >= 1280  three columns: rail + centre + right sidebar
    //   1024..   rail + centre; quick actions move into the rail
    //   < 1024   hamburger + drawer; centre full width
    //
    // ShellLayout.railIcons is folded into the drawer case rather than rendered.
    // It described a 900–1024 rail collapsed to icons, and once that rail
    // carried NAVIGATE, ACCOUNT and QUICK ACTIONS it was ~11 bare icons in three
    // unlabelled clusters. The enum value still exists because nav_band.dart is
    // shared with the mobile app and is not ours to edit; nothing renders it.
    final isDrawerMode =
        layout == ShellLayout.drawer || layout == ShellLayout.railIcons;

    // Equivalently `width >= kShellRailLabelsMin`, but expressed against the
    // same flag the rest of the layout uses so the two can never disagree.
    //
    // The links need ~920px on their own — MEASURED, not estimated: brand +
    // links + bell + chip overflow at exactly 900 and are clean from 920, and
    // with the hamburger added they do not fit until 960. An earlier 600px
    // cutoff was simply too low, which is what left 607px striped.
    //
    // Nothing becomes unreachable when they go: the rail (inline or in the
    // drawer) carries a NAVIGATE section whenever this is false.
    //
    // An empty `items` list is all it takes — HomeTopNav renders its centred Row
    // with no children — so this stays a caller-side change.
    final showNavLinks = !isDrawerMode;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: CitizenUi.pageBg,
      // Only in drawer mode: at >= 1024 the rail is inline, so a drawer would be
      // a second copy of it reachable by an edge swipe.
      drawer: isDrawerMode ? _shellDrawer(profile) : null,
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
                // beneath it rather than beside it. In drawer mode the
                // hamburger is prepended as a seamless extension of the bar.
                Row(
                  children: [
                    if (isDrawerMode) _hamburger(),
                    Expanded(
                      child: HomeTopNav(
                        currentIndex: _index,
                        onTap: _selectIndex,
                        // Home · My Reports · Emergency. NewsFeed is gone: Home's centre
                        // is the feed now. Settings is reached from the user chip, so it
                        // is not a nav link — but its index moved to 3 when NewsFeed left,
                        // hence settingsIndex.
                        items: [
                          if (showNavLinks)
                            for (final tab in CitizenTab.values)
                              if (tab != CitizenTab.settings)
                                (label: tab.label, index: tab.index),
                        ],
                        settingsIndex: CitizenTab.settings.index,
                        notificationCount: NotificationService.count,
                        onNotificationTap: () => _showNotifications(width),
                        // The shared flow, same as Settings and the nav chrome use.
                        onLogoutTap: () => performCitizenLogout(context),
                        // Below ~600 the brand + bell + named chip cannot fit
                        // alongside the hamburger, and the chip's name is the
                        // only part that is redundant — the dropdown still
                        // shows it in full. Opt-in, so no other caller of this
                        // shared widget is affected.
                        avatarOnlyChip: width < _kAvatarOnlyChipBelow,
                        username: profile?.username ?? '',
                        fullName: profile?.fullName,
                        facePhotoUrl: profile?.facePhotoUrl,
                        verifStatus: switch (verif) {
                          VerifStatus.verified => 'approved',
                          VerifStatus.pending => 'pending',
                          VerifStatus.none => 'none',
                        },
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: Row(
                    // Pins both rails to the top; only the centre column stretches.
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Inline only above the drawer line. Not
                      // shellHasLeftRail(layout), which still counts railIcons
                      // as a rail — that band is the drawer's now.
                      if (!isDrawerMode)
                        _leftRail(
                          profile: profile,
                          // The inline rail only exists at >= 1024, where the
                          // top nav is showing the destinations itself, so it
                          // never duplicates them. Always false in practice;
                          // kept as the explicit complement of the nav.
                          showNav: !showNavLinks,
                          // The rail takes the quick actions whenever the right
                          // sidebar is not there to hold them. Without this they
                          // were reachable only at >= 1280 (sidebar) and in the
                          // drawer, and vanished in between.
                          //
                          // At >= 1280 this is false, so they live in the
                          // sidebar and are NOT duplicated here.
                          showQuickActions: !shellHasRightSidebar(layout),
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
