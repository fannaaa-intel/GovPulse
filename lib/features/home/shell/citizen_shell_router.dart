import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/user_profile_provider.dart';
import '../../../core/theme/citizen_ui.dart';
import '../emergency/emergency_screen.dart';
import '../my_report/my_reports_screen.dart';
import '../my_report/report_detail_screen.dart';
import '../newsfeed/news_feed_screen.dart';
import '../settings/settings_screen.dart';
import 'citizen_shell.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Routing for the citizen web shell PREVIEW.
//
//  Still a scratch mount: nothing live points here, the shell is only built
//  when the browser is loaded directly at /shell-preview, and every real route
//  still goes through the Navigator 1.0 table in core/router/app_router.dart.
//
//  ── Why a whole separate MaterialApp ───────────────────────────────────────
//  Two routers cannot both own the browser URL. The live app is a MaterialApp
//  with `routes` + `onGenerateRoute`, and on web Navigator 1.0 already reports
//  its route names to the address bar. Nesting a go_router Router inside it
//  would leave both writing history entries and fighting over the location. So
//  main.dart inspects the launch URL once and builds EITHER the live app OR
//  this one — the same trick already used for the /scan/<token> deep link,
//  which still bypasses the shell entirely.
//
//  ── Why the tabs are namespaced under /shell-preview ───────────────────────
//  Selecting a tab rewrites the address bar. With bare paths, reloading on
//  /newsfeed would hand main.dart a route it does not recognise as the preview
//  and silently drop the user into the live app. The live table also already
//  owns /newsfeed, /settings and /emergency. Phase 3 drops the prefix.
//
//  ── StatefulShellRoute.indexedStack ────────────────────────────────────────
//  Replaces the plain ShellRoute the first preview used. That version had to
//  build its own IndexedStack over all five panes, which meant every pane
//  mounted on first paint: five fetches, two realtime channels and Emergency's
//  animation controllers all running for tabs nobody had opened.
//
//  StatefulShellRoute builds each branch LAZILY on first visit and keeps it
//  alive afterwards, which is the persistence the shell wants without the eager
//  cost. It also gives each branch its own Navigator, so a detail route pushed
//  from a pane stacks INSIDE that pane and the other tabs keep their state —
//  and it removes the hand-rolled per-pane Navigator the preview needed before.
// ════════════════════════════════════════════════════════════════════════════

/// URL prefix every preview route lives under.
const String kShellPreviewPrefix = '/shell-preview';

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

  /// Full location for this tab, e.g. `/shell-preview/my-reports`.
  String get path => '$kShellPreviewPrefix/$segment';
}

/// True when the app was launched at a preview URL and should build
/// [CitizenShellPreviewApp] instead of the live MaterialApp.
///
/// Strict about the boundary — exact match, or followed by `/` or `?` — so a
/// real route that merely starts with the same letters is never swallowed.
bool isShellPreviewLaunch(String? route) {
  if (route == null) return false;
  return route == kShellPreviewPrefix ||
      route.startsWith('$kShellPreviewPrefix/') ||
      route.startsWith('$kShellPreviewPrefix?');
}

/// Quick actions and other full-bleed flows open over the WHOLE shell rather
/// than inside a column, so they are pushed onto the root navigator.
final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

/// Detail route for one report, pushed inside the My Reports branch so it
/// stacks over that pane and leaves the other tabs untouched. The item rides in
/// `extra` — the same in-memory hand-off the legacy '/report_detail' route uses.
/// Making it id-addressable needs a fetch-by-id path and is Phase 3 work.
String get shellReportDetailPath => '${CitizenTab.myReports.path}/detail';

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
        onOpenReport: (report) =>
            context.push(shellReportDetailPath, extra: report),
      );
    case CitizenTab.emergency:
      return const EmergencyBody();
    case CitizenTab.settings:
      return const SettingsBody();
  }
}

final GoRouter citizenShellRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: CitizenTab.home.path,
  routes: <RouteBase>[
    // Bare /shell-preview is not a destination — send it to the first tab.
    GoRoute(
      path: kShellPreviewPrefix,
      redirect: (_, _) => CitizenTab.home.path,
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
                  if (tab == CitizenTab.myReports)
                    GoRoute(
                      path: 'detail',
                      builder: (context, state) => _WithIdentity(
                        (username, _) => ReportDetailScreen(
                          report: state.extra as ReportItem,
                          username: username,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
      ],
    ),
  ],
);

/// The preview's app root. Built by main.dart only for a preview launch URL.
class CitizenShellPreviewApp extends StatelessWidget {
  const CitizenShellPreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'GovPulse — citizen shell preview',
      color: Colors.white,
      theme: ThemeData(scaffoldBackgroundColor: CitizenUi.pageBg),
      routerConfig: citizenShellRouter,
    );
  }
}
