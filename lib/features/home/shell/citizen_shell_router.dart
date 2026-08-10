import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/network/network_wrapper.dart';
import '../../../core/providers/user_profile_provider.dart';
import '../../../core/router/app_router.dart'
    show buildLoginScreen, buildSignupScreen, kScanRoutePrefix;
import '../../../core/services/auth_ready.dart';
import '../../../core/services/events_service.dart';
import '../../../core/theme/citizen_ui.dart';
import '../../../core/widgets/resolve_by_id.dart';
import '../../guest/screen/guest.dart';
import '../../scan/scan_page.dart';
import '../Quick-action/Events/event_detail_screen.dart';
import '../Quick-action/Events/events_screen.dart' show EventItem;
import '../emergency/emergency_screen.dart';
import '../my_report/my_reports_screen.dart';
import '../my_report/report_detail_screen.dart';
import '../newsfeed/news_feed_screen.dart';
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
//    • Quick actions and the settings rail open as DIALOGS over a still-mounted
//      feed (citizen_shell_dialogs.dart). A route would unmount the feed and add
//      a history entry for what is really a panel.
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
Widget _bodyFor(BuildContext context, CitizenTab tab) {
  switch (tab) {
    case CitizenTab.home:
      // Home IS the community feed. NewsFeedBody already renders exactly that —
      // the posts, the filter, and the loading/error/empty states — with no
      // chrome of its own, so the merge is a matter of mounting it here rather
      // than reimplementing a feed in a second place.
      return const NewsFeedBody(embedded: true);
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
        onOpenReport: (report) => context.go(
          shellReportDetailPath(report.fullId),
          extra: report,
        ),
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

// ── Auth guard ──────────────────────────────────────────────────────────────
//
// Synchronous by necessity — go_router's redirect cannot await. The cold-load
// race that [awaitAuthReady] exists to absorb is handled by treating "no session
// yet" as UNKNOWN rather than as signed-out; see [AuthRestoration].
String? _authRedirect(BuildContext context, GoRouterState state) {
  final loc = state.matchedLocation;

  // The printed-QR endorsement page is public in BOTH directions: an agency
  // officer scanning it has no session and must not be sent to login, and a
  // signed-in citizen opening it must not be swept into the shell.
  if (loc.startsWith(kScanRoutePrefix)) return null;

  final signedIn = Supabase.instance.client.auth.currentSession != null;

  if (signedIn) {
    // Neither the root nor the login screen is a destination for someone who is
    // already in. /signup and /guest are deliberately left alone: an anonymous
    // guest IS signed in (Firebase anonymous auth) and is still mid-flow there.
    if (loc == '/' || loc == _kLoginPath) return CitizenTab.home.path;
    // A citizen's feed is the shell's Home pane, so the bare guest feed is not
    // a place they can be. Without this the catch-all below would let a citizen
    // who typed or was linked /#/newsfeed onto it, and mounting it flips
    // CommunityPostsProvider into guest mode — anonymised authors and a cleared
    // post list — for the rest of the session.
    if (loc == _kNewsFeedPath) return CitizenTab.home.path;
    return null;
  }

  // No session — but that is not the same as signed OUT until restoration has
  // settled. On a cold load (F5 straight onto a detail URL) the restored
  // session lands a few hundred ms after the first frame, and bouncing now
  // would throw a logged-in user off their own URL and lose it. Hold the
  // requested location; refreshListenable re-runs this the moment we know.
  if (!AuthRestoration.instance.settled) return null;

  if (loc == _kLoginPath || loc == _kSignupPath || loc == _kGuestPath) {
    return null;
  }
  return _kLoginPath;
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
      builder: (_, _) => NetworkWrapper(child: Builder(builder: buildLoginScreen)),
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

    // NOTE: there is deliberately no full-screen route for the quick actions.
    // Inside the shell they open as big dialogs over the still-mounted feed
    // (see citizen_shell_dialogs.dart), which is the whole point — a route
    // would unmount the feed and add a history entry for what is really a panel.
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          CitizenShell(navigationShell: navigationShell),
      branches: <StatefulShellBranch>[
        for (final tab in CitizenTab.values)
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: tab.path,
                builder: (context, _) => _bodyFor(context, tab),
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
                ],
              ),
            ],
          ),
      ],
    ),
  ],
);

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
      theme: ThemeData(scaffoldBackgroundColor: Colors.white),
      routerConfig: citizenRouter,
    );
  }
}
