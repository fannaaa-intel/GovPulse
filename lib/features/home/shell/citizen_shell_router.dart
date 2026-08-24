import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/network/network_wrapper.dart';
import '../../../core/providers/user_profile_provider.dart';
import '../../../core/router/app_router.dart'
    show buildLoginScreen, buildSignupScreen, kScanRoutePrefix;
import '../../../core/services/auth_ready.dart';
import '../../../core/services/citizen_guard.dart';
import '../../../core/services/events_service.dart';
import '../../../core/theme/citizen_ui.dart';
import '../../../core/widgets/citizen_guard_modals.dart';
import '../../../core/widgets/resolve_by_id.dart';
import '../../admin/screens/admin_dashboard_screen.dart';
import '../../guest/screen/guest.dart';
import '../../scan/scan_page.dart';
import '../../staff/screens/staff_console_screen.dart';
import '../Quick-action/Events/event_detail_screen.dart';
import '../Quick-action/Events/events_screen.dart' show EventItem;
import '../emergency/emergency_screen.dart';
import '../my_report/my_reports_screen.dart';
import '../my_report/report_detail_screen.dart';
import '../newsfeed/news_feed_screen.dart';
import '../settings/about/about_govpulse_screen.dart';
import '../settings/change-password/change_password_send_screen.dart';
import '../settings/contact-support/contact_support_screen.dart';
import '../settings/edit_profile_screen.dart';
import '../settings/my-submission/my_submissions_screen.dart';
import '../settings/settings_screen.dart';
import 'citizen_shell.dart';

// ════════════════════════════════════════════════════════════════════════════
//  THE citizen web router.
//
//  On web this is the only router: main.dart builds [GovPulseWebApp] and
//  go_router owns the address bar outright. The Navigator 1.0 table in
//  core/router/app_router.dart is still very much alive, but on web it is now
//  reached imperatively through the legacy_nav shim rather than by name, so
//  exactly one router writes history entries.
//
//  Mobile is untouched: it still builds the legacy `MaterialApp` with `routes`
//  + `onGenerateRoute`, and never builds anything in this file.
//
//  ── What has a URL, and what deliberately does not ─────────────────────────
//  A route earns a path here when the URL is worth something — when it should
//  survive a reload or be pasteable. That is: the four shell tabs, report and
//  event detail (id-addressable, see [shellReportDetailPath]), the auth screens,
//  and the public /scan/<token> endorsement page.
//
//  Everything else stays off go_router on purpose:
//    • Quick actions open as DIALOGS over a still-mounted feed
//      (citizen_shell_dialogs.dart). A route would unmount the feed and add a
//      history entry for what is really a panel. The settings rail used to work
//      the same way and no longer does — its five ACCOUNT screens are pages
//      under the Settings branch now; see [CitizenAccountPage].
//    • The verification wizard passes Uint8List ID images between its six steps,
//      and change-password carries access/refresh tokens. Neither belongs in an
//      address bar. They stay on the legacy table, pushed via pushLegacy.
//
//  ── StatefulShellRoute.indexedStack ────────────────────────────────────────
//  Branches are built LAZILY on first visit and kept alive after, so a tab keeps
//  its scroll offset and loaded data while tabs nobody opened never run their
//  fetches. Each branch owns a Navigator, so a detail route pushed from a pane
//  stacks INSIDE that pane and the other tabs keep their state.
// ════════════════════════════════════════════════════════════════════════════

/// Auth screens. Same strings the legacy table uses, so both routers agree on
/// what a destination is called even though they reach it differently.
const String _kLoginPath = '/login';
const String _kSignupPath = '/signup';
const String _kGuestPath = '/guest';

/// The GUEST feed. Deliberately not a shell destination: a guest gets the bare,
/// self-chroming [NewsFeedScreen], never the citizen shell.
///
/// A citizen's feed is the shell's Home pane, so the two never share a URL —
/// see the redirect in [_authRedirect].
const String _kNewsFeedPath = '/newsfeed';

/// The two NON-citizen consoles.
///
/// Peers of the auth routes and deliberately outside the StatefulShellRoute:
/// that shell is the citizen surface, and both consoles chrome themselves —
/// each brings its own Scaffold, drawer and desktop/tablet breakpoints, so
/// wrapping them in citizen chrome would be wrong twice over.
///
/// Nothing navigates here yet. The login branch still pushes both consoles
/// imperatively, and the guard below still classifies every session as a
/// citizen, so for now these are reachable only by typing the URL — and the
/// sweep in [_citizenRedirect] turns even that away. Both of those become real
/// in the commits that follow.
const String _kAdminPath = '/admin';
const String _kStaffPath = '/staff';

/// The shell's top-level destinations, in nav order. The index into
/// [CitizenTab.values] IS the branch index, so order is load-bearing.
///
/// NOTE this is a SHORTER list than the standalone pages use. Home and NewsFeed
/// were two tabs showing two halves of the same thing — an empty "Latest
/// Updates" panel and the real community feed — so the shell merged them: Home's
/// centre column IS the feed now, and there is no separate NewsFeed tab. That
/// also shifts Settings from index 4 to 3, which is why the shell passes
/// [HomeTopNav.settingsIndex].
///
/// The standalone NewsFeed page still exists untouched for the mobile app and
/// the live web route — only the shell merges the two.
enum CitizenTab {
  home('home', 'Home', Icons.home_rounded),
  myReports('my-reports', 'My Reports', Icons.assignment_rounded),
  emergency('emergency', 'Emergency', Icons.emergency_rounded),
  settings('settings', 'Settings', Icons.settings_rounded);

  final String segment;
  final String label;
  final IconData icon;
  const CitizenTab(this.segment, this.label, this.icon);

  /// Full location for this tab, e.g. `/my-reports`.
  String get path => '/$segment';
}

/// The ACCOUNT destinations — the five entries in the shell's left rail.
///
/// ── Why these are PAGES and the quick actions are not ──────────────────────
/// Both used to open as dialogs over the feed, and for the quick actions that
/// is still right: a report is an interruption you finish and return from, so
/// keeping the feed mounted behind it is the point. These five are somewhere
/// you GO. Editing a profile or reading a submission history is a task measured
/// in minutes, and a 620px card floating over a blurred feed gave it no width,
/// no address, no browser Back and no way to say which section you are in.
///
/// They live under the SETTINGS branch, so the cost the file's opening comment
/// warns about does not apply: [StatefulShellRoute.indexedStack] keeps the Home
/// branch mounted while you are here, so the feed does not reload and its
/// scroll offset survives the round trip. It is the same construction as
/// `detail/:reportId` under My Reports.
///
/// [verifyMessage] non-null means the item is behind the verification gate.
/// Only Edit Profile and My Submissions are — matching the mobile Settings
/// page, which gates exactly those two and leaves Change Password, Contact
/// Support and About open to everyone. Support in particular must stay
/// reachable: an unverified citizen having trouble verifying needs it most.
///
/// The gate is enforced at the TAP, not by a redirect. Typing the URL directly
/// while unverified is not a hole: Edit Profile renders its own not-verified
/// state, and My Submissions can only ever show the caller's own RLS-scoped
/// rows.
enum CitizenAccountPage {
  editProfile(
    segment: 'edit-profile',
    label: 'Edit Profile',
    icon: Icons.person_outline_rounded,
    verifyMessage:
        'Only verified citizens can edit their profile information. '
        'Please complete the identity verification process first.',
  ),
  changePassword(
    segment: 'password',
    label: 'Change Password',
    icon: Icons.lock_outline_rounded,
  ),
  submissions(
    segment: 'submissions',
    label: 'My Submissions',
    icon: Icons.folder_open_rounded,
    verifyMessage:
        'Only verified citizens can view their submission history. '
        'Please complete the identity verification process first.',
  ),
  support(
    segment: 'support',
    label: 'Contact Support',
    icon: Icons.support_agent_rounded,
  ),
  about(
    segment: 'about',
    label: 'About GovPulse',
    icon: Icons.info_outline_rounded,
  );

  final String segment;
  final String label;
  final IconData icon;
  final String? verifyMessage;

  const CitizenAccountPage({
    required this.segment,
    required this.label,
    required this.icon,
    this.verifyMessage,
  });

  /// Full location, e.g. `/settings/edit-profile`.
  String get path => '${CitizenTab.settings.path}/$segment';
}

/// True when [location] is one of the [CitizenAccountPage] paths.
///
/// The shell asks this to decide whether to stand the right sidebar down and
/// hand its width to the account page. Compared against `uri.path`, so a query
/// string (My Submissions carries one) does not defeat the match.
bool isCitizenAccountLocation(String location) =>
    CitizenAccountPage.values.any((page) => location == page.path);

// ── My Submissions deep link ────────────────────────────────────────────────
//
// Query parameters, for the same reason the feed's are: `/settings/submissions`
// on its own is a valid location, and the tab and the flashed row are an
// initial STATE of that page rather than a different page.
const String _kSubmissionsTabParam = 'tab';
const String _kSubmissionsHighlightParam = 'highlight';

/// Deep link into My Submissions on [tab] (0 Reports · 1 Suggestions ·
/// 2 Feedback), optionally flashing [highlightId].
///
/// Both omitted gives the bare path — [Uri] would otherwise emit a trailing
/// `?`, which would make the location stop matching [isCitizenAccountLocation].
String shellSubmissionsPath({int? tab, String? highlightId}) {
  final query = <String, String>{
    if (tab != null) _kSubmissionsTabParam: '$tab',
    _kSubmissionsHighlightParam: ?highlightId,
  };
  return Uri(
    path: CitizenAccountPage.submissions.path,
    queryParameters: query.isEmpty ? null : query,
  ).toString();
}

/// Quick actions and other full-bleed flows open over the WHOLE shell rather
/// than inside a column, so they are pushed onto the root navigator.
final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

/// Detail route for one report, pushed inside the My Reports branch so it
/// stacks over that pane and leaves the other tabs untouched.
///
/// ID-ADDRESSABLE: the report id is in the PATH, so this URL survives a hard
/// refresh and can be pasted to someone else. The [ReportItem] still rides in
/// `extra` when we already have it — that keeps in-session navigation instant
/// with no fetch and no loading flash — but it is an optimisation, never a
/// requirement. On a cold load `extra` is null and the report is fetched by id.
String shellReportDetailPath(String reportId) =>
    '${CitizenTab.myReports.path}/detail/$reportId';

/// Detail route for one event, same contract as [shellReportDetailPath].
///
/// Lives under the Home branch rather than getting a tab of its own: Events is a
/// quick action, so the branch it stacks on is simply wherever the shell's
/// primary column is.
String shellEventDetailPath(String eventId) =>
    '${CitizenTab.home.path}/event/$eventId';

// ── Feed deep link ──────────────────────────────────────────────────────────
//
// QUERY PARAMETERS, not a nested route, and the distinction is the point.
// /my-reports/detail/:id and /home/event/:id are different SCREENS. A feed deep
// link is the same Home pane in a different initial state — scrolled to a post,
// maybe with its comment thread open — so it belongs in the query string, where
// dropping it leaves a valid location rather than a different page.
//
// The payoff is bigger than the notification tap that motivated it:
// /#/home?post=<id>&comments=1 survives a reload and can be pasted to someone
// else, which makes a community post permalinkable for the first time.
const String _kFeedPostParam = 'post';
const String _kFeedCommentsParam = 'comments';
const String _kFeedHighlightParam = 'highlight';

/// The restrictable feature key for the community feed, spelled as the admin
/// toggles and the DB triggers spell it. See [_FeedOrRestricted].
const String _kNewsFeedFeature = 'newsfeed';

/// Deep link to one post in the shell's feed.
///
/// [postRef] may be a POST id or a COMMENT id — the feed resolves which (see
/// `_tryResolveCommentRef` in news_feed_screen.dart), so callers pass the single
/// reference the notification carried and never have to know which they hold.
///
/// [openComments] opens that post's thread; [highlight] flashes the post. They
/// are deliberately independent: a comment tap opens the thread (where the
/// flash would be behind the sheet), a heart flashes the post instead.
String shellFeedPostPath(
  String postRef, {
  bool openComments = false,
  bool highlight = false,
}) => Uri(
  path: CitizenTab.home.path,
  queryParameters: <String, String>{
    _kFeedPostParam: postRef,
    if (openComments) _kFeedCommentsParam: '1',
    if (highlight) _kFeedHighlightParam: '1',
  },
).toString();

/// `state.extra`, but only when it really is a [T].
///
/// NEVER cast `extra` directly. On a browser reload go_router restores its
/// navigation state from `window.history.state`, and whatever comes back is not
/// the object we put in — the model is not serialisable, so at best it is null
/// and at worst it is a decoded Map. `state.extra as ReportItem?` throws a
/// TypeError on the second case, and a TypeError thrown inside a route builder
/// takes out the whole router subtree: a blank page with no shell chrome, which
/// is precisely the cold-load symptom.
///
/// A type test degrades to "no fast path, fetch by id" instead, which is the
/// behaviour a cold load wants anyway.
T? _extraAs<T>(GoRouterState state) {
  final extra = state.extra;
  return extra is T ? extra : null;
}

/// Reads identity from [userProfileProvider] for route builders whose screens
/// still take `username`. The Bodies no longer need this; the quick-action and
/// detail screens have not been split yet.
class _WithIdentity extends ConsumerWidget {
  final Widget Function(String username, bool isVerified) builder;
  const _WithIdentity(this.builder);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).valueOrNull;
    return builder(profile?.username ?? '', profile?.isVerified ?? false);
  }
}

/// Body for a tab. This is the whole point of the Phase 2 split: the shell
/// mounts chromeless Bodies, not the standalone Screens.
Widget _bodyFor(BuildContext context, CitizenTab tab, GoRouterState state) {
  switch (tab) {
    case CitizenTab.home:
      // Home IS the community feed. NewsFeedBody already renders exactly that —
      // the posts, the filter, and the loading/error/empty states — with no
      // chrome of its own, so the merge is a matter of mounting it here rather
      // than reimplementing a feed in a second place.
      //
      // No longer const, so the deep link in the query string can reach it. That
      // costs nothing: the Element and State are reused across rebuilds (same
      // type, same position), so initState — and with it the one-shot
      // setGuestMode — still runs exactly once. Only the widget instance is new,
      // which is precisely what lets didUpdateWidget see a changed target.
      final query = state.uri.queryParameters;
      return _FeedOrRestricted(
        child: NewsFeedBody(
          embedded: true,
          initialPostId: query[_kFeedPostParam],
          initialOpenComments: query[_kFeedCommentsParam] == '1',
          initialHighlightPost: query[_kFeedHighlightParam] == '1',
          // Deliberately no initialCommentId. When the reference is a comment
          // id the feed resolves it to (post, comment) itself and fills its own
          // target — passing one here would mean the caller guessing which kind
          // of id it holds.
        ),
      );
    case CitizenTab.myReports:
      return MyReportsBody(
        // Both are passed: the id makes the URL real and reload-proof, the
        // object makes this navigation instant. Only the id is load-bearing.
        //
        // go(), NOT push(). An imperative push stacks the detail on the branch
        // navigator but leaves the reported location on the branch ROOT, so the
        // address bar still said /my-reports while a report was open — which is
        // exactly how an id-addressable route ends up with no id to reload from.
        // go() re-resolves the whole match list, so the location becomes the
        // detail path and the browser URL follows. Because the detail route is a
        // direct child of the branch route, the resulting stack is still
        // [list, detail] — Back returns to the list with its scroll intact,
        // same as push gave us.
        onOpenReport: (report) =>
            context.go(shellReportDetailPath(report.fullId), extra: report),
      );
    case CitizenTab.emergency:
      return const EmergencyBody();
    case CitizenTab.settings:
      // embedded: the left rail already carries Edit Profile, Change Password,
      // My Submissions, Contact Support and Log Out, so the pane drops its
      // duplicates of them and shows only what the rail does not.
      return const SettingsBody(embedded: true);
  }
}

/// Body for one [CitizenAccountPage].
///
/// The existing screens are hosted AS-IS. Each still brings its own Scaffold
/// and header, which inside the centre column reads as the page's own title bar
/// — and their back chevrons still call `Navigator.pop`, which on a route
/// nested under the Settings branch returns to `/settings`, exactly as the
/// report detail route behaves. So none of them needed changing to stop being
/// dialogs.
///
/// They size themselves off `MediaQuery`, and the shell overrides it to report
/// the CENTRE COLUMN's box rather than the viewport's — which is what makes
/// hosting them here correct where hosting them in a fixed-width dialog was
/// not.
Widget _accountBodyFor(CitizenAccountPage page, GoRouterState state) {
  switch (page) {
    case CitizenAccountPage.editProfile:
      return _WithIdentity(
        (username, _) => EditProfileScreen(username: username),
      );
    case CitizenAccountPage.changePassword:
      return const _ChangePasswordBody();
    case CitizenAccountPage.submissions:
      final query = state.uri.queryParameters;
      return _WithIdentity(
        (username, _) => MySubmissionsScreen(
          username: username,
          initialTab: int.tryParse(query[_kSubmissionsTabParam] ?? '') ?? 0,
          highlightId: query[_kSubmissionsHighlightParam],
        ),
      );
    case CitizenAccountPage.support:
      return _WithIdentity(
        (username, _) => ContactSupportScreen(username: username),
      );
    case CitizenAccountPage.about:
      return const AboutGovPulseScreen();
  }
}

/// Change Password, which needs the EMAIL rather than the username — the one
/// account screen [_WithIdentity] cannot serve.
class _ChangePasswordBody extends ConsumerWidget {
  const _ChangePasswordBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) => ChangePasswordSendScreen(
    email: ref.watch(userProfileProvider).valueOrNull?.email ?? '',
  );
}

// ── Auth guard ──────────────────────────────────────────────────────────────
//
// Synchronous by necessity — go_router's redirect cannot await. The cold-load
// race that [awaitAuthReady] exists to absorb is handled by treating "no session
// yet" as UNKNOWN rather than as signed-out; see [AuthRestoration].
//
// ── Three states, not two ──────────────────────────────────────────────────
// A GUEST is not a Supabase session. They hold a Firebase ANONYMOUS user and no
// Supabase session at all, which is indistinguishable from signed-out unless
// both systems are consulted. Collapsing that into a boolean is what made the
// old guard unable to route guests: it could only say "in" or "out", and a
// guest is neither.
String? _authRedirect(BuildContext context, GoRouterState state) {
  final loc = state.matchedLocation;

  // The printed-QR endorsement page is public in ALL directions: an agency
  // officer scanning it has no session and must not be sent to login, and
  // neither a citizen nor a guest opening it should be swept anywhere else.
  if (loc.startsWith(kScanRoutePrefix)) return null;

  // A screen is mid-way through driving auth state on purpose — hold.
  //
  // The reset-password screen has to setSession() before it can read the
  // cooldown or call updateUser(), and that sign-in re-runs this guard
  // synchronously while the screen sits on /login. Without this hold,
  // _citizenRedirect below sweeps it to /home mid-flow and the user never sees
  // whether the reset succeeded — see AuthRestoration.beginAuthFlow.
  //
  // Holding is safe: returning null means "use the requested location", the
  // same thing the settled/roleKnown holds do, and it is released in a finally
  // so it cannot stick. Every route still enforces its own access rules.
  if (AuthRestoration.instance.authFlowActive) return null;

  // Citizen is tested FIRST, and deliberately ahead of the settled hold below.
  //
  // A present Supabase session is positive evidence: it can only mean citizen,
  // so there is nothing to wait for, and the reload-onto-a-deep-link fast path
  // [AuthRestoration] is built around stays instant. ABSENCE is the ambiguous
  // case — guest or signed out — so the hold sits between the two rather than
  // above both.
  //
  // Testing citizen first is also what makes citizen WIN: someone who signed up
  // while still holding a stale anonymous user is a citizen, not a guest.
  if (Supabase.instance.client.auth.currentSession != null) {
    // A session says WHO is here but not WHAT they are, and the three surfaces
    // are mutually exclusive — so the role decides, and until the lookup lands
    // we hold rather than guess. Guessing citizen would sweep an admin off
    // their own console on every reload, which is the bug this whole sequence
    // exists to fix.
    //
    // Holding is cheap for everyone whose location already matches their role:
    // returning null means "use the requested location", so their page builds
    // immediately and the re-run after the role arrives changes nothing. The
    // cost falls only on a MISMATCH — a citizen who typed /admin — and that is
    // what [_consoleOrHold] covers at the builder.
    if (!AuthRestoration.instance.roleKnown) return null;
    switch (AuthRestoration.instance.roleId) {
      case 1:
        return _adminRedirect(loc);
      case 2:
        return _staffRedirect(loc);
      default:
        return _citizenRedirect(loc);
    }
  }

  // No Supabase session — but that is not the same as signed OUT until
  // restoration has settled, and on web `settled` waits for FIREBASE too.
  //
  // Both halves matter. Bouncing a citizen mid-restore would throw them off
  // their own URL; classifying a guest before Firebase has reported would read
  // them as a stranger and bounce them off the guest feed — the exact URL the
  // guest flow exists to make reloadable. Hold the requested location;
  // refreshListenable re-runs this the moment we know.
  if (!AuthRestoration.instance.settled) return null;

  final firebaseUser = FirebaseAuth.instance.currentUser;
  // `isAnonymous`, not merely non-null: a REAL Firebase user with no Supabase
  // session is some other flow mid-flight, not a guest.
  final isGuest = firebaseUser != null && firebaseUser.isAnonymous;

  return isGuest ? _guestRedirect(loc) : _signedOutRedirect(loc);
}

/// Where an admin belongs, and where a staff member belongs.
///
/// Both delegate to [_consoleRedirect] because the rule is the same for each:
/// their own console, and nothing else in this router.
String? _adminRedirect(String loc) => _consoleRedirect(loc, _kAdminPath);
String? _staffRedirect(String loc) => _consoleRedirect(loc, _kStaffPath);

/// An ALLOWLIST OF ONE, and deliberately so.
///
/// Every other location this router serves is either a citizen surface or the
/// other role's console, and neither is a destination for a console user. So
/// rather than enumerate what to sweep — which would silently let a NEW citizen
/// route become admin-reachable the day someone adds one — this permits the
/// console and its nested routes and sends everything else home. Same reasoning
/// as [_guestRedirect]: closed by default.
///
/// The public scan page is not caught by this: [_authRedirect] returns for it
/// before any role branch is reached, so an admin can still open a printed QR
/// link like anyone else.
String? _consoleRedirect(String loc, String consoleHome) {
  if (loc == consoleHome || loc.startsWith('$consoleHome/')) return null;
  return consoleHome;
}

/// Where a signed-in citizen belongs.
String? _citizenRedirect(String loc) {
  // None of these is a destination for someone already signed in:
  //
  //   /          the router's placeholder, never a real location
  //   /login     nothing left to do there
  //   /signup    likewise
  //   /guest     a citizen has no use for the guest landing page, and letting
  //              them mount it would mint a junk anonymous Firebase user —
  //              GuestScreen does that on init
  //   /newsfeed  the GUEST feed. A citizen's feed is the shell's Home pane;
  //              mounting the guest one flips CommunityPostsProvider into guest
  //              mode — anonymised authors, cleared posts — for the rest of the
  //              session
  //
  // This replaces a note claiming /signup and /guest were "deliberately left
  // alone" because "an anonymous guest IS signed in". That was never true — a
  // guest holds no Supabase session and so never reached this branch at all —
  // and now that guests are classified in their own right it is misleading.
  // /admin and /staff are swept here permanently. This function is now reached
  // only by an actual citizen — the guard branches on role first — so this is
  // the rule that a citizen who types a console URL is sent home. Their data is
  // RLS-protected either way, but the chrome is not, and a citizen has no
  // business seeing an admin dashboard frame at all.
  //
  // It is the builder, not this sweep, that covers the moment BEFORE the role
  // is known — see [_consoleOrHold]. The two are complementary: this one turns
  // a citizen away once we know they are one, that one declines to render
  // while we still do not.
  if (loc == '/' ||
      loc == _kLoginPath ||
      loc == _kSignupPath ||
      loc == _kGuestPath ||
      loc == _kNewsFeedPath ||
      loc == _kAdminPath ||
      loc == _kStaffPath) {
    return CitizenTab.home.path;
  }
  return null;
}

/// Where a guest belongs: the two guest surfaces, plus the way out to an account.
///
/// An ALLOWLIST rather than a list of exclusions, so the shell is closed by
/// default. /home, /my-reports, /emergency, /settings and every nested route
/// beneath them fall through without being enumerated — which also means a new
/// shell route cannot quietly become guest-reachable later.
String? _guestRedirect(String loc) {
  // The router's placeholder is not a location, and a guest already holds an
  // anonymous session — letting this fall through to /login would eject them
  // from guest mode for no reason. Mirrors the citizen '/' → /home sweep.
  if (loc == '/') return _kGuestPath;

  // /newsfeed is the permission this whole three-state split exists for: it is
  // what lets a guest hold a real, reloadable URL for the feed instead of a
  // screen pushed over /#/guest with no address of its own.
  if (loc == _kGuestPath ||
      loc == _kNewsFeedPath ||
      loc == _kLoginPath ||
      loc == _kSignupPath) {
    return null;
  }
  return _kLoginPath;
}

/// Where a visitor with no identity at all belongs.
///
/// Unchanged from the two-state guard, deliberately.
String? _signedOutRedirect(String loc) {
  // /newsfeed is absent on purpose. The bare feed is for visitors who CHOSE to
  // browse as a guest — a pasted link does not make that choice for them, and
  // auto-minting an anonymous user to honour it would create accounts nobody
  // asked for. They get /login, and the guest button is one tap away.
  if (loc == _kLoginPath || loc == _kSignupPath || loc == _kGuestPath) {
    return null;
  }
  return _kLoginPath;
}

/// A console route's screen, or the startup spinner while we do not yet know
/// who is asking.
///
/// ── Why the builder needs this at all ──────────────────────────────────────
/// The guard holds by returning null, and null means "use the requested
/// location" — so during the hold the location STANDS and the route BUILDS.
/// For a matching visitor that is exactly right: an admin reloading /admin
/// gets their console immediately. For a MISMATCHED one it is not: a citizen
/// who pasted /#/admin would render real admin chrome for the length of the
/// restore, before the guard learned their role and swept them away.
///
/// So the console builders decline to render until the answer is in. This is
/// the same thing '/' already does with [_StartingUp] during its own hold; the
/// consoles simply had no equivalent.
///
/// ── It is never a citizen-facing state ─────────────────────────────────────
/// Once the role IS known, go_router resolves redirects BEFORE building pages,
/// so a citizen on /admin is sent to /home without this builder ever running.
/// The spinner therefore only ever appears during genuine unknown, and for the
/// visitor who actually belongs here it is replaced by their console rather
/// than by a redirect.
Widget _consoleOrHold(Widget console) {
  // LISTENS, rather than reading AuthRestoration once at build time.
  //
  // Reading it imperatively here left the console stuck on [_StartingUp] after
  // a WEB login, until the user manually reloaded:
  //
  //   1. sign-in fires -> onAuthStateChange re-arms _roleKnown = false
  //      (deliberately — see AuthRestoration.begin)
  //   2. the login handler calls ctx.go('/admin'), this builder runs, sees
  //      roleKnown == false and returns the spinner
  //   3. _refreshRole() lands ~2s later, sets _roleKnown = true and notifies
  //   4. refreshListenable re-runs _authRedirect — which returns NULL, because
  //      an admin sitting on /admin is already exactly where they belong
  //   5. a null redirect changes no location, so nothing marks this builder
  //      dirty, and the spinner stays on screen forever
  //
  // The guard and the builder are complementary by design (see
  // [_citizenRedirect]): the redirect turns the WRONG person away, this one
  // declines to render while we do not yet know WHO they are. But only the
  // redirect was wired to re-run. This subscribes the builder to the same
  // ChangeNotifier the router already uses as its refreshListenable, so step 3
  // rebuilds it and the console appears on its own.
  //
  // Web-only symptom, which is why mobile never hit it: _roleKnown initialises
  // to `!kIsWeb`, so on mobile it is true before this builder ever runs.
  //
  // `console` is a const widget from the route table, so re-running this
  // builder re-uses the same instance and the mounted console is not rebuilt.
  return ListenableBuilder(
    listenable: AuthRestoration.instance,
    builder: (_, _) {
      final restoration = AuthRestoration.instance;
      if (!restoration.settled || !restoration.roleKnown) {
        return const _StartingUp();
      }
      return NetworkWrapper(child: console);
    },
  );
}

final GoRouter citizenRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  // '/' is not a destination; _authRedirect resolves it once auth is known.
  initialLocation: '/',
  // Re-runs _authRedirect when session restoration settles and on every
  // sign-in / sign-out, so the guard is never deciding on stale information.
  refreshListenable: AuthRestoration.instance,
  redirect: _authRedirect,
  // A routing failure must never be a blank page. Without this, an unmatched
  // location or a builder that throws leaves nothing on screen — and on a cold
  // load that is indistinguishable from the app being broken. This puts a
  // readable message and a way back on screen instead.
  errorBuilder: (context, state) => _ShellRouteError(
    location: state.uri.toString(),
    error: state.error?.toString(),
  ),
  routes: <RouteBase>[
    // '/' still needs something to build: until restoration settles the guard
    // deliberately returns null, and a location with no route is an error page.
    GoRoute(path: '/', builder: (_, _) => const _StartingUp()),

    // ── Auth ────────────────────────────────────────────────────────────────
    // The screens themselves come from app_router.dart, so there is ONE
    // definition of what login and signup do. NetworkWrapper matches what the
    // legacy _instantInFadeOut helper wraps them in.
    GoRoute(
      path: _kLoginPath,
      builder: (_, _) =>
          NetworkWrapper(child: Builder(builder: buildLoginScreen)),
    ),
    GoRoute(
      path: _kSignupPath,
      builder: (_, _) =>
          NetworkWrapper(child: Builder(builder: buildSignupScreen)),
    ),
    GoRoute(
      path: _kGuestPath,
      builder: (_, _) => const NetworkWrapper(child: GuestScreen()),
    ),

    // ── Public endorsement scan ─────────────────────────────────────────────
    // A real route now, not a launch-URL special case, so /#/scan/<token>
    // survives a reload and can be pasted to a colleague.
    //
    // No NetworkWrapper, matching the legacy route: that wrapper is built for
    // signed-in users, and this page has no session and covers offline itself.
    GoRoute(
      path: '$kScanRoutePrefix:token',
      builder: (_, state) => ScanPage(token: state.pathParameters['token']!),
    ),

    // ── Guest feed ──────────────────────────────────────────────────────────
    // A PEER of /guest, deliberately outside the StatefulShellRoute: guests get
    // the bare feed, never the shell. [NewsFeedScreen] chromes itself — its
    // `showNav: !isGuest` drops the nav entirely — so there is nothing for a
    // shell branch to add here except chrome a guest must not see.
    //
    // [isGuest] is a constant, not an auth-derived value: this route IS the
    // guest surface. A citizen's feed is the same content mounted as the
    // shell's Home pane (NewsFeedBody), and _authRedirect sends any signed-in
    // citizen who lands here back to it.
    //
    // Nothing navigates here yet — guest.dart still reaches the feed with an
    // imperative push — so for now this is only reachable by typing the URL.
    GoRoute(
      path: _kNewsFeedPath,
      builder: (_, _) =>
          const NetworkWrapper(child: NewsFeedScreen(isGuest: true)),
    ),

    // ── Admin and staff consoles ────────────────────────────────────────────
    // Mounted DIRECTLY, not inside the shell. Both are self-chroming — each
    // builds its own Scaffold, its own drawer, and its own desktop/tablet
    // breakpoints — so there is nothing for a shell branch to add here except
    // citizen chrome that neither should ever show.
    //
    // Neither constructor takes arguments: both read identity from
    // userProfileProvider themselves, which is why these are const and why the
    // routes carry nothing. NetworkWrapper matches how the login branch pushes
    // them today, so the surface is identical either way in.
    //
    // INERT in this commit. Nothing routes here yet, and [_citizenRedirect]
    // sweeps anyone who types the URL, because the guard cannot yet tell an
    // admin from a citizen.
    GoRoute(
      path: _kAdminPath,
      builder: (_, _) => _consoleOrHold(const AdminDashboardScreen()),
    ),
    GoRoute(
      path: _kStaffPath,
      builder: (_, _) => _consoleOrHold(const StaffConsoleScreen()),
    ),

    // NOTE: there is deliberately no full-screen route for the quick actions.
    // Inside the shell they open as big dialogs over the still-mounted feed
    // (see citizen_shell_dialogs.dart), which is the whole point — a route
    // would unmount the feed and add a history entry for what is really a panel.
    StatefulShellRoute.indexedStack(
      // `state.uri` here is the FULL current location, not just the shell's own
      // match — which is what lets the shell know it is on an account page and
      // stand the right sidebar down. Taken from the builder rather than looked
      // up inside the shell so it arrives as a plain value that rebuilds the
      // shell when it changes.
      builder: (context, state, navigationShell) => CitizenShell(
        navigationShell: navigationShell,
        location: state.uri.path,
      ),
      branches: <StatefulShellBranch>[
        for (final tab in CitizenTab.values)
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: tab.path,
                // `state` is no longer discarded: the Home branch reads its
                // feed deep link from the query string. See [shellFeedPostPath].
                builder: (context, state) => _bodyFor(context, tab, state),
                routes: <RouteBase>[
                  // Report detail lives INSIDE the My Reports branch, so it
                  // stacks over that pane and Back returns to the list with its
                  // scroll position intact.
                  //
                  // The id is in the path and `extra` is optional, so pasting or
                  // reloading /my-reports/detail/<id> reconstructs the report
                  // instead of bouncing to the splash the way the legacy
                  // '/report_detail' route has to.
                  if (tab == CitizenTab.myReports)
                    GoRoute(
                      path: 'detail/:reportId',
                      builder: (context, state) {
                        final id = state.pathParameters['reportId']!;
                        return _WithIdentity(
                          (username, _) => ResolveById<ReportItem>(
                            initial: _extraAs<ReportItem>(state),
                            fetch: () => ReportItem.fetchById(id),
                            loadingLabel: 'Loading report…',
                            notFoundTitle: 'Report not found',
                            notFoundMessage:
                                'This report may have been removed, or the '
                                'link may be incorrect.',
                            builder: (_, report) => ReportDetailScreen(
                              report: report,
                              username: username,
                            ),
                          ),
                        );
                      },
                    ),

                  // Event detail, same contract. Events is a quick action, so it
                  // stacks on the primary (Home) branch.
                  if (tab == CitizenTab.home)
                    GoRoute(
                      path: 'event/:eventId',
                      builder: (context, state) {
                        final id = state.pathParameters['eventId']!;
                        return _WithIdentity(
                          (username, _) => ResolveById<EventItem>(
                            initial: _extraAs<EventItem>(state),
                            fetch: () async {
                              final model = await EventsService.instance
                                  .fetchEventById(id);
                              return model == null
                                  ? null
                                  : EventItem.fromModel(model);
                            },
                            loadingLabel: 'Loading event…',
                            notFoundTitle: 'Event not found',
                            notFoundMessage:
                                'This event may have ended or been removed, or '
                                'the link may be incorrect.',
                            builder: (_, event) => EventDetailScreen(
                              event: event,
                              username: username,
                            ),
                          ),
                        );
                      },
                    ),

                  // The five ACCOUNT pages, nested under Settings for the same
                  // reason report detail nests under My Reports: the pane they
                  // replace is this branch's, so the other three branches keep
                  // their state and Back returns to /settings.
                  //
                  // These are what the left rail's ACCOUNT section opens. They
                  // used to be dialogs; see [CitizenAccountPage] for why they
                  // are not any more.
                  if (tab == CitizenTab.settings)
                    for (final page in CitizenAccountPage.values)
                      GoRoute(
                        path: page.segment,
                        builder: (context, state) =>
                            _accountBodyFor(page, state),
                      ),
                ],
              ),
            ],
          ),
      ],
    ),
  ],
);

/// The Home pane's feed, or the restriction notice in its place.
///
/// The one guard surface that could not be a modal. Every other restrictable
/// feature is reached by tapping something, so `citizenGuardAllow` can refuse at
/// the entry point — but on web the feed IS the Home tab and the landing
/// surface, with nothing to gate. Mobile has it easier: its feed is a
/// destination you navigate to, so home_screen.dart gates it like the rest.
///
/// So the refusal replaces the content instead of interrupting it. Deliberately
/// not a route-out: a citizen restricted from the feed still has My Reports,
/// Emergency and Settings, and ejecting them from the shell's landing tab would
/// cut them off from all of it.
///
/// Wraps rather than living inside [NewsFeedBody] because that body is shared —
/// the GUEST feed mounts it too, and a guest has no session and no restrictions
/// to read.
///
/// Listens rather than reads, so a restriction lifted mid-session restores the
/// feed without a reload.
class _FeedOrRestricted extends StatelessWidget {
  final Widget child;
  const _FeedOrRestricted({required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CitizenStatus>(
      valueListenable: CitizenGuard.I.status,
      builder: (context, status, _) {
        final restriction = status.restriction;
        if (restriction == null ||
            !restriction.features.contains(_kNewsFeedFeature)) {
          return child;
        }
        return _RestrictedFeedNotice(info: restriction);
      },
    );
  }
}

/// The feed pane's restriction notice.
///
/// Copy is the modal's, line for line: same title, same three sentences in the
/// same order, through the same [citizenFeatureLabel] and
/// [citizenGuardUntilLine] helpers — so a citizen reads the same words whether
/// the refusal arrives as a pop-up or as a pane.
///
/// The PALETTE is the shell's rather than the modal's, because this is a full
/// pane inside the shell's chrome and has to sit with it: [CitizenUi.warn] in
/// place of the modal's AppColors.orange. Voice is what carries across surfaces;
/// colour belongs to the surface.
class _RestrictedFeedNotice extends StatelessWidget {
  final RestrictionInfo info;
  const _RestrictedFeedNotice({required this.info});

  @override
  Widget build(BuildContext context) {
    final reason = (info.reason ?? '').trim();
    final lines = <String>[
      'Your access to ${citizenFeatureLabel(_kNewsFeedFeature)} is currently '
          'limited by an administrator.',
      if (reason.isNotEmpty) 'Reason: $reason',
      citizenGuardUntilLine(info.expiresAt),
    ];

    return Center(
      // Scrollable because the centre column is short at the tablet breakpoint.
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_rounded, size: 44, color: CitizenUi.warn),
              const SizedBox(height: 16),
              const Text(
                'Feature unavailable',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: CitizenUi.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              for (final line in lines) ...[
                Text(
                  line,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: CitizenUi.textMuted,
                  ),
                ),
                const SizedBox(height: 6),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown instead of a blank page when a location cannot be resolved.
class _ShellRouteError extends StatelessWidget {
  final String location;
  final String? error;
  const _ShellRouteError({required this.location, this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CitizenUi.pageBg,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.link_off_rounded,
                  size: 44,
                  color: CitizenUi.accent,
                ),
                const SizedBox(height: 16),
                const Text(
                  "This page couldn't be opened",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: CitizenUi.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  location,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: CitizenUi.textMuted,
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  SelectableText(
                    error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: CitizenUi.textFaint,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => context.go(CitizenTab.home.path),
                  icon: const Icon(Icons.home_rounded, size: 18),
                  label: const Text('Back to Home'),
                  style: FilledButton.styleFrom(
                    backgroundColor: CitizenUi.accent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown at '/' for the moment between first paint and knowing whether there is
/// a session. Deliberately quiet — it is on screen for a few hundred
/// milliseconds on a warm load, and never at all once the guard resolves.
class _StartingUp extends StatelessWidget {
  const _StartingUp();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SizedBox(
          width: 34,
          height: 34,
          child: CircularProgressIndicator(
            strokeWidth: 2.6,
            valueColor: AlwaysStoppedAnimation(Color(0xFF00448F)),
          ),
        ),
      ),
    );
  }
}

/// The citizen web app root. Built by main.dart for every web launch.
///
/// Theme matches the legacy `MaterialApp` exactly — white scaffold, white app
/// colour — so the auth screens, which were written against that background,
/// look identical to how they do on the old router. The shell does not inherit
/// it: [CitizenShell] sets `CitizenUi.pageBg` on its own Scaffold.
///
/// No global chat-bubble overlay, unlike the legacy app's `builder`. That bubble
/// is only ever raised by HomePage (`HomeChatBubble.showGlobal()`), which is
/// mobile-only now; the shell has its own docked chat window instead.
class GovPulseWebApp extends StatelessWidget {
  const GovPulseWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'GovPulse',
      color: Colors.white,
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.white,
        // Every platform key maps to the same builder. This ThemeData is only
        // ever built by GovPulseWebApp, so "every platform" only ever means the
        // browser — but Flutter web reports the HOST OS as its TargetPlatform,
        // so a single entry would leave Chrome-on-Windows on one builder and
        // Chrome-on-macOS on another.
        pageTransitionsTheme: PageTransitionsTheme(
          builders: <TargetPlatform, PageTransitionsBuilder>{
            for (final platform in TargetPlatform.values)
              platform: const _WebFadePageTransitionsBuilder(),
          },
        ),
      ),
      routerConfig: citizenRouter,
    );
  }
}

/// Cross-fades the INCOMING page in over the outgoing one, and leaves the
/// outgoing one alone.
///
/// ── Why not the platform default ───────────────────────────────────────────
/// Flutter web reports the host OS as its [TargetPlatform], so Chrome on
/// Windows was getting [ZoomPageTransitionsBuilder]. That builder animates both
/// halves — `_ZoomExitTransition` fades the OUTGOING page out while
/// `_ZoomEnterTransition` fades the incoming one in — so for a few frames both
/// are partly transparent and the white canvas shows through between them. On
/// screens whose left half is an opaque hero panel that is a very visible flash,
/// and it is why the panel flashed while the card (which has its own floored
/// entrance fade) did not.
///
/// [secondaryAnimation] is therefore deliberately unused: not animating the
/// outgoing page is the entire point. It stays fully opaque underneath until
/// the incoming page has faded in over it, so there is never a frame showing
/// neither.
///
/// ── Why not FadeUpwards ────────────────────────────────────────────────────
/// [FadeUpwardsPageTransitionsBuilder] has the property we want — it discards
/// `secondaryAnimation` too — but it also slides the incoming page up from 25%
/// of the screen height. Every screen here already runs its own slide-up
/// entrance, and app_router's `_slideUp` notes the same trade: keep the route
/// level instant so the screen's own controller does the real motion and there
/// is no double-slide. A plain fade keeps that contract.
///
/// ── Layering ───────────────────────────────────────────────────────────────
/// Independent of the floored entrance fades in the auth screens and the feed.
/// This one covers the OUTGOING screen's teardown; those cover the INCOMING
/// content's first frame. Their opacities multiply, which is fine — neither
/// starts at zero any more.
class _WebFadePageTransitionsBuilder extends PageTransitionsBuilder {
  const _WebFadePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(opacity: animation, child: child);
  }
}
