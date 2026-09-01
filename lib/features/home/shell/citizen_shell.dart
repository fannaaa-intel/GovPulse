import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/user_profile_provider.dart';
import '../../../core/theme/citizen_ui.dart';
import '../../../core/widgets/Home/Newsfeed/citizen_web_notification_panel.dart';
import '../../../core/widgets/Home/home_enums.dart';
import '../../../core/widgets/Home/nav/home_top_nav.dart';
import '../../../core/widgets/Home/nav/nav_band.dart';
import '../../../core/widgets/Home/sections/Web/home_quick_actions_section_web.dart';
import '../../../core/widgets/Home/sections/Web/home_app_download_card.dart';
import '../../../core/widgets/Home/sections/Web/home_upcoming_events_card.dart';
import '../../../core/widgets/Home/sections/Web/rail_verify_card.dart';
import '../../../core/widgets/citizen_shell_scope.dart';
import '../../../core/router/legacy_nav.dart';
import '../../../core/services/auth_ready.dart';
import '../../../core/services/citizen_guard.dart';
import '../../../core/services/citizen_logout.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/citizen_guard_modals.dart';
import '../../../core/widgets/no_scrollbar_behavior.dart';
import '../../../core/widgets/modal/verification_required_dialog.dart';
import '../Quick-action/Events/events_screen.dart';
import '../Quick-action/Feedback/feedback_screen.dart';
import '../Quick-action/Report/report_issue_screen.dart';
import '../Quick-action/Suggestion/suggestion_screen.dart';
import '../screen/notification_popup.dart';
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
const double kCitizenRailWidth = 288;

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

  /// The full current location's path, e.g. `/home` or
  /// `/settings/edit-profile`.
  ///
  /// `navigationShell.currentIndex` answers WHICH BRANCH, which is all the top
  /// nav needs. It cannot answer WHERE IN IT — and the ACCOUNT pages are five
  /// different locations inside the one Settings branch, so the rail's
  /// highlight and the right sidebar's stand-down both need the path itself.
  final String location;

  const CitizenShell({
    super.key,
    required this.navigationShell,
    required this.location,
  });

  /// Switch the shell under [context] to [tab]. Used by Bodies that need to
  /// send the user to another destination (Home's "View all" → NewsFeed).
  static void goToTab(BuildContext context, CitizenTab tab) {
    StatefulNavigationShell.of(context).goBranch(tab.index);
  }

  /// Runs the quick action [key] — the same dispatch the left rail and the right
  /// sidebar use, so the caller inherits the verification and restriction gates
  /// rather than reimplementing them.
  ///
  /// Peer of [goToTab], and there for the same reason: a Body mounted in the
  /// centre column needs a shell-level behaviour it cannot otherwise name. The
  /// feed's empty-state CTA is the first caller.
  ///
  /// Does nothing when there is no shell above [context] — the GUEST feed is not
  /// in one — so callers must only offer the affordance when they know they are
  /// embedded, rather than relying on this to no-op.
  static void runQuickAction(BuildContext context, String key) {
    context.findAncestorStateOfType<_CitizenShellState>()?._handleQuickAction(
      key,
    );
  }

  @override
  ConsumerState<CitizenShell> createState() => _CitizenShellState();
}

class _CitizenShellState extends ConsumerState<CitizenShell> {
  int get _index => widget.navigationShell.currentIndex;

  /// True while one of the rail's ACCOUNT pages is the current location.
  ///
  /// Two things read it — the right sidebar and the rail's quick-action
  /// section — and they must agree, so it is asked once here rather than
  /// recomputed at each site.
  bool get _onAccountPage => isCitizenAccountLocation(widget.location);

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
    // Listener only — deliberately NOT CitizenGuard.I.stop().
    //
    // stop() ends by assigning status.value, which notifies synchronously, and
    // dispose() runs inside finalizeTree where the tree is locked. Removing the
    // listener above covers _onGuardStatus but NOT _FeedOrRestricted's
    // ValueListenableBuilder, which watches the same notifier from inside this
    // shell's own subtree — so stopping here mutated shared state mid-teardown.
    //
    // The symmetry argument that put it here was wrong: a shell unmount is not
    // a session end. Session end is tearDownSession's job, and it still calls
    // stop(). Nothing leaks in the meantime — start() re-subscribes for a
    // different uid, and the channel is dropped at sign-out. Mobile's HomePage
    // has always done exactly this: remove the listener, leave stop() alone.
    CitizenGuard.I.status.removeListener(_onGuardStatus);
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
      // An approved progress update on this citizen's report. Same destination
      // and the same reference_id shape as a status change — the updates live
      // inside the processing timeline on that screen — so it shares the arm
      // rather than duplicating it.
      //
      // ⚠ This switch is the SECOND place the type vocabulary lives (see the
      // note above). A new notification type needs adding HERE as well as in
      // routeCitizenNotificationTap, or it works on mobile and silently does
      // nothing on web — which is exactly how report_update shipped.
      case 'report_update':
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
        _openSubmissionsFromNotification(
          initialTab: 1,
          highlightId: n.referenceId,
        );
        break;

      case 'feedback_response':
        _openSubmissionsFromNotification(
          initialTab: 2,
          highlightId: n.referenceId,
        );
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
  /// Goes to the page rather than opening a dialog, so the notification and the
  /// rail now reach My Submissions the same way — and the tab and the flashed
  /// row ride in the query string, which makes the target of a reply
  /// notification pasteable and reload-proof for the first time.
  ///
  /// The old `MySubmissionsScreen.isOpen` guard is gone with the dialog. It
  /// existed to stop a second copy stacking over the first, and `go` replaces
  /// rather than stacks. Tapping a notification while already on the page is
  /// therefore a no-op, exactly as the guard made it: [GoRoute] derives its page
  /// key from the path, which has not changed, so the State is reused and
  /// `initialTab` is not re-read.
  void _openSubmissionsFromNotification({
    required int initialTab,
    String? highlightId,
  }) {
    context.go(shellSubmissionsPath(tab: initialTab, highlightId: highlightId));
  }

  // ── Quick actions open as dialogs; account items are pages ────────────────
  //
  // Nothing below pushes a FULL-SCREEN route. The quick-action forms open as
  // dialogs, so the shell — feed, both rails, the top nav — stays mounted
  // underneath and closing one returns you exactly where you were, with no
  // reload and no history entry for what is really a panel.
  //
  // The ACCOUNT items do navigate, but within the shell: they are routes under
  // the Settings branch, so the chrome never unmounts and neither does the feed.
  // See [_openAccountPage].

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

    // Restriction gate, AFTER the verification gate and before anything opens.
    //
    // Order matters and matches mobile: an unverified citizen is told to verify
    // (the thing they can act on) rather than being told a feature they never
    // had is restricted.
    //
    // Every quick action funnels through this one function, so unlike mobile —
    // which repeats citizenGuardAllow at five separate call sites — this is the
    // single place the check belongs. 'events' is absent by design: there is no
    // restrictable feature key for browsing events, and citizenGuardAllow would
    // wave through an unknown key anyway.
    final restrictedFeature = switch (key) {
      'report' => 'reports',
      'suggestion' => 'suggestions',
      'feedback' => 'feedback',
      'chat' => 'ai_chat',
      _ => null,
    };
    if (restrictedFeature != null &&
        !citizenGuardAllow(context, restrictedFeature)) {
      return;
    }
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

    // Events is a browsing surface, not a form — the same split panel, with the
    // list on the left and the selected event on the right, but no form guard
    // because there is nothing half-filled to discard.
    if (key == 'events') {
      await showCitizenSplitPanelDialog<void>(
        context: context,
        builder: (dialogContext, close) => EventsScreen(
          username: username,
          isVerified: _isVerified,
          splitPanel: true,
          onClose: close,
          // ── The panel reads events in place; it does not navigate ────────
          // `onOpenEvent` is deliberately NOT passed. It closed the modal and
          // went to the standalone `/home/event/:id` page — a phone-scaled
          // surface with its own hero panel, reached by throwing away the
          // browsing context. The split panel renders the full detail in its
          // own left column instead, so there is nowhere to go.
          //
          // The route is untouched and still the address of an event: pasting
          // one still opens the page, and it stays reload-proof. What changed
          // is only that the modal hands that address out rather than
          // following it.
          onShareEvent: (event) => _shareEventLink(event),
        ),
      );
      return;
    }

    final guard = FormDialogGuard();

    // Report, Suggestion and Feedback all open as the two-column split panel.
    // This is the ONLY place `splitPanel: true` is passed anywhere in the app —
    // each form defaults it to false, so mobile, the native-tablet home body and
    // the standalone '/report', '/suggestion' and '/feedback' routes all keep
    // the widget tree they had.
    //
    // One host, one guard, one close callback for all three: the panel supplies
    // its own header and its own × (see [showCitizenSplitPanelDialog]), which is
    // why none of them takes a `title` or an `icon` here any more.
    await showCitizenSplitPanelDialog<void>(
      context: context,
      guard: guard,
      builder: (_, close) => switch (key) {
        'report' => ReportIssueForm(
          username: username,
          splitPanel: true,
          guard: guard,
          onClose: close,
        ),
        'suggestion' => SuggestionForm(
          username: username,
          splitPanel: true,
          guard: guard,
          onClose: close,
        ),
        _ => FeedbackForm(
          username: username,
          splitPanel: true,
          guard: guard,
          onClose: close,
        ),
      },
    );
  }

  /// Copies an event's own address to the clipboard.
  ///
  /// The split panel reads events in place rather than navigating, so this is
  /// what keeps `/home/event/:id` useful: the citizen gets a link they can send
  /// someone, and following it still lands on the standalone page.
  ///
  /// `Uri.base` is the browser's current address, so resolving the route
  /// against it produces the real origin — localhost in development, the
  /// deployed host in production — instead of a bare path nobody can paste.
  /// The route is hash-based (see the router's `#/` URLs), which is why the
  /// fragment is set rather than the path.
  Future<void> _shareEventLink(EventItem event) async {
    final path = shellEventDetailPath(event.id);
    final link = Uri.base.replace(fragment: path).toString();

    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    showAppSnackBar(
      context,
      'Event link copied. Paste it to share "${event.title}".',
      type: AppSnackType.success,
    );
  }

  // ── Left rail ─────────────────────────────────────────────────────────────

  /// Opens one of the rail's ACCOUNT destinations.
  ///
  /// `go`, not a dialog. The item is a real location under the Settings branch
  /// — see [CitizenAccountPage] for why these five stopped being pop-ups — so
  /// the address bar follows it, a reload lands back on the page, and Back
  /// returns to `/settings` instead of leaving the shell.
  ///
  /// The verification gate is unchanged and still runs BEFORE the navigation,
  /// so a refusal leaves the citizen exactly where they were.
  Future<void> _openAccountPage(CitizenAccountPage page) async {
    final gate = page.verifyMessage;
    if (gate != null && !await _requireVerified(gate)) return;
    if (!mounted) return;
    context.go(page.path);
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
      width: kCitizenRailWidth,
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
              // Each navigates to its page under the Settings branch — see
              // [_openAccountPage]. Because they are destinations now, they can
              // and do show which one you are on.
              for (final page in CitizenAccountPage.values)
                _railRow(
                  page.icon,
                  page.label,
                  _fromDrawer(() => _openAccountPage(page), inDrawer: inDrawer),
                  selected: widget.location == page.path,
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
              // The rail's single verify affordance, pinned last so it never
              // crowds the profile block or the sections above it. The status
              // line in [_profileCard] is status-only now; this is the only
              // place the wizard can be started from the rail.
              //
              // [RailVerifyCard.maybe] renders nothing until the profile has
              // loaded — VerifStatus falls back to `none`, so keying on status
              // alone would flash the red "unverified" card at a verified
              // citizen on every cold load.
              const SizedBox(height: 16),
              RailVerifyCard.maybe(
                profileLoaded: profile != null,
                status: profile?.verifStatus ?? VerifStatus.none,
                // _fromDrawer closes the drawer FIRST — otherwise the wizard
                // opens behind a still-open drawer.
                onVerify: _fromDrawer(_startVerification, inDrawer: inDrawer),
              ),
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
      VerifStatus.pending => ('Pending review', CitizenUi.pending),
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
                _statusPill(label: statusLabel, color: statusColor),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The account card's status line — STATUS ONLY, a dot plus a label, inert in
  /// all three states.
  ///
  /// It used to append a tappable "Verify now ›" for a known-unverified account,
  /// which made it the shell's one direct route into the wizard. That affordance
  /// now lives in [RailVerifyCard] at the bottom of the rail, so there is
  /// exactly one verify entry point instead of two competing ones, and this line
  /// is free to do the single job its name implies.
  Widget _statusPill({required String label, required Color color}) {
    return Row(
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
      ],
    );
  }

  /// [selected] marks where you currently are. The NAVIGATE rows compare branch
  /// indices; the ACCOUNT rows compare paths, which is the finer question — all
  /// five live in the SAME branch, so `currentIndex` cannot tell them apart.
  ///
  /// The account rows could not pass it at all while they opened dialogs: a
  /// dialog is not a destination you can be "on". Making them pages is what
  /// gave the rail something true to highlight.
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
                  color: selected ? CitizenUi.accent : CitizenUi.textSecondary,
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
      width: kCitizenRailWidth,
      backgroundColor: CitizenUi.pageBg,
      // The drawer sits in the Scaffold's `drawer:` slot, which is OUTSIDE the
      // `body:` the shell's ScrollConfiguration wraps — so the rail kept
      // painting a scrollbar here while the identical rail in the docked
      // layout did not. Same behaviour object, applied where it actually
      // reaches this subtree.
      child: ScrollConfiguration(
        behavior: const NoScrollbarBehavior(),
        child: SafeArea(
          // No scroll view here — [_leftRail] owns its own, and nesting two in
          // the same axis would give the inner one an unbounded height.
          child: SizedBox.expand(
            child: _leftRail(
              profile: profile,
              inDrawer: true,
              // The drawer only exists below 1024 — below the line where the
              // top nav can fit its links, and below the line where the right
              // sidebar survives — so it always carries the destinations.
              showNav: true,
              // Quick actions drop on an account page here too. The drawer is
              // the same rail at a narrower width, and the reason they do not
              // belong on an account page is about the PAGE, not the width.
              showQuickActions: !_onAccountPage,
            ),
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
          bottom: BorderSide(color: CitizenUi.sharedBorder, width: 1),
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
      // Mirrors [_leftRail]: the Row lays both rails out under LOOSE vertical
      // constraints (crossAxisAlignment.start), so a scroll view here
      // shrink-wraps to its content on a tall window — the rail still hugs the
      // top and stays pinned while the centre scrolls — and only scrolls
      // internally once the content would exceed the height.
      //
      // Without this the rail was a bare Column and simply OVERFLOWED: its
      // content runs ~849px once the quick actions, the download card and the
      // events card are all in it, against ~610px of usable height on a
      // 1366x768 browser.
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 20, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // flat: the rail's quick actions sit on the page background like the
              // left rail's ACCOUNT / NAVIGATE sections. The two cards below keep
              // their card treatment — that mix is the intended arrangement.
              HomeQuickActionsSectionWeb(
                onActionTap: _handleQuickAction,
                flat: true,
              ),
              const SizedBox(height: 16),
              const HomeAppDownloadCard(),
              const SizedBox(height: 16),
              // Same dispatch the rail's "View Events" row uses, so this inherits
              // the verification and restriction gates rather than side-stepping
              // them. The LIST itself is deliberately visible to unverified
              // citizens — consistent with the feed, which shows posts to everyone
              // and gates only the interactions.
              HomeUpcomingEventsCard(
                onViewAll: () => _handleQuickAction('events'),
              ),
            ],
          ),
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

    // ── The sidebar stands down for an account page ──────────────────────────
    //
    // An account page is a working surface — a profile form, a submission
    // history — and the centre column alone is about 600px of it. Standing the
    // quick-actions sidebar down hands that page the sidebar's width too, which
    // is what lets Edit Profile seat its identity card BESIDE its fields
    // instead of stacking everything in a phone-width strip.
    //
    // The quick actions do NOT follow the sidebar into the rail here, and that
    // is deliberate. They normally do — the rail takes them whenever the
    // sidebar is not there to hold them, which is what the 1024–1280 band
    // relies on — but an account page is the one place that rule is wrong.
    //
    // Report, Suggestion and Feedback belong to the FEED: you are reading the
    // community and you act on it. On your own account settings there is
    // nothing to act on, and offering them there turns a five-row account menu
    // into a twelve-row column that mixes "where am I" with "what can I make".
    // Facebook's settings nav carries settings and nothing else, for the same
    // reason. They are one click away — Home — rather than gone.
    final showRightSidebar = shellHasRightSidebar(layout) && !_onAccountPage;

    // ── Line the nav links up with the CENTRE COLUMN, not the window ─────────
    //
    // The body below is [left rail | centre | right sidebar], and the rails are
    // NOT the same width — 288 against 340. So the centre column's midpoint
    // sits 26px left of the window's, and nav links centred on the window are
    // 26px off from the column they head. On a wide screen that reads as a
    // crooked nav, which is what it is: centred on the viewport, not on the
    // content.
    //
    // Derived from the rails THIS WIDTH calls for rather than from bare
    // constants, so it stays correct if either rail is resized and collapses to
    // zero in drawer mode, where there are no rails at all.
    final double leftRailWidth = isDrawerMode ? 0 : kCitizenRailWidth;
    // ── Deliberately NOT `showRightSidebar` ──────────────────────────────────
    // That flag is false on an account page too, because the sidebar stands
    // down there to hand its width to the form. Feeding it into this offset
    // would move the NAV every time you opened My Submissions or Edit Profile
    // — a 170px jump, from -26 to +144, on a bar that has nothing to do with
    // which page is below it.
    //
    // The links belong to the WINDOW's arrangement, not to one page's use of
    // it: they sit still while you move between pages, and only shift when the
    // shell itself changes shape (a resize across 1280, or into the drawer).
    // So this asks the LAYOUT whether this width has a sidebar, and ignores
    // whether the current page chose to show it.
    final double rightRailWidth = shellHasRightSidebar(layout)
        ? _kRightSidebarWidth
        : 0;
    // The centre column spans [leftRail, width - rightRail]; its midpoint is
    // therefore offset from the window's by half the difference of the rails.
    final double navLinksOffset = (leftRailWidth - rightRailWidth) / 2;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: CitizenUi.pageBg,
      // Only in drawer mode: at >= 1024 the rail is inline, so a drawer would be
      // a second copy of it reachable by an edge swipe.
      drawer: isDrawerMode ? _shellDrawer(profile) : null,
      // The docked chat floats over the columns in a Stack rather than in a
      // route or a dialog. No barrier is inserted, so everything behind it stays
      // scrollable and clickable while it is open.
      //
      // ── Scrollbars ───────────────────────────────────────────────────────
      // Hidden for every scrollable in the shell — both rails and whichever
      // pane the centre is showing — so the columns read like a feed rather
      // than like three boxes with grey bars. Scrolling itself is untouched:
      // [NoScrollbarBehavior] only declines to PAINT the thumb.
      //
      // This wrapper is now REDUNDANT rather than wrong: GovPulseWebApp sets
      // the same behaviour at the web root, which is where it had to move to
      // reach the consoles' detail dialogs (a dialog mounts above this `body:`
      // and never saw this wrapper). It is kept because the shell is also
      // built under the legacy MaterialApp, and deleting a working guard to
      // prove a point is how a regression gets in.
      body: ScrollConfiguration(
        behavior: const NoScrollbarBehavior(),
        child: Stack(
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
                        // LISTEN, don't read — see NotificationService.count.
                        // This is the citizen web shell's bell, and the snapshot
                        // that used to be here is what made it look dead on web:
                        // the badge only moved when the shell happened to rebuild,
                        // i.e. when the citizen changed screens.
                        child: ValueListenableBuilder<int>(
                          valueListenable: NotificationService.unread,
                          builder: (_, unreadCount, _) => HomeTopNav(
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
                            // See [navLinksOffset]: centres the links on the
                            // feed rather than on the viewport.
                            linksOffset: navLinksOffset,
                            notificationCount: unreadCount,
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
                            // sidebar and are NOT duplicated here. On an
                            // account page it is false at EVERY width — see the
                            // note on [showRightSidebar]; the section is not
                            // relocated there, it is dropped.
                            showQuickActions:
                                !showRightSidebar && !_onAccountPage,
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
                              // Marks everything in the centre column as
                              // living inside the shell, so a screen shared
                              // with the mobile app can drop the standalone
                              // page chrome it would otherwise bring.
                              child: CitizenShellScope(
                                child: SizedBox.expand(
                                  child: widget.navigationShell,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (showRightSidebar) _rightSidebar(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            CitizenDockedChat(
              state: _chat,
              onMinimise: () =>
                  setState(() => _chat = DockedChatState.minimised),
              onRestore: () => setState(() => _chat = DockedChatState.open),
              onClose: () => setState(() => _chat = DockedChatState.closed),
            ),
          ],
        ),
      ),
    );
  }
}

