import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/user_profile_provider.dart';
import '../../../core/theme/citizen_ui.dart';
import '../Quick-action/Chat-with-Agent/chat_agent_screen.dart';
import '../Quick-action/Events/events_screen.dart';
import '../Quick-action/Feedback/feedback_screen.dart';
import '../Quick-action/Report/report_issue_screen.dart';
import '../Quick-action/Suggestion/suggestion_screen.dart';
import '../emergency/emergency_screen.dart';
import '../my_report/my_reports_screen.dart';
import '../my_report/report_detail_screen.dart';
import '../newsfeed/news_feed_screen.dart';
import '../screen/home_screen.dart';
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

/// The five top-level destinations, in nav order. The index into
/// [CitizenTab.values] IS the branch index, so order is load-bearing and
/// matches the 0–4 contract [HomeTopNav] and the legacy nav widgets use.
enum CitizenTab {
  home('home', 'Home', Icons.home_rounded),
  myReports('my-reports', 'My Reports', Icons.assignment_rounded),
  newsfeed('newsfeed', 'NewsFeed', Icons.dynamic_feed_rounded),
  emergency('emergency', 'Emergency', Icons.emergency_rounded),
  settings('settings', 'Settings', Icons.settings_rounded);

  final String segment;
  final String label;
  final IconData icon;
  const CitizenTab(this.segment, this.label, this.icon);

  /// Full location for this tab, e.g. `/shell-preview/newsfeed`.
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

/// Path of a quick-action screen, e.g. `/shell-preview/action/report`.
String shellActionPath(String key) => '$kShellPreviewPrefix/action/$key';

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
      return HomeBody(
        onOpenNewsfeed: () => CitizenShell.goToTab(context, CitizenTab.newsfeed),
      );
    case CitizenTab.myReports:
      return MyReportsBody(
        onOpenReport: (report) =>
            context.push(shellReportDetailPath, extra: report),
      );
    case CitizenTab.newsfeed:
      return const NewsFeedBody();
    case CitizenTab.emergency:
      return const EmergencyBody();
    case CitizenTab.settings:
      return const SettingsBody();
  }
}

/// A quick-action screen, still full-screen over the shell.
Widget _actionFor(String key) {
  return _WithIdentity((username, isVerified) {
    switch (key) {
      case 'report':
        return ReportIssueScreen(username: username);
      case 'suggestion':
        return SuggestionScreen(username: username);
      case 'feedback':
        return FeedbackScreen(username: username);
      case 'chat':
        return ChatAgentScreen(username: username);
      case 'events':
        return EventsScreen(username: username, isVerified: isVerified);
      default:
        return const SizedBox.shrink();
    }
  });
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

    // Quick actions: over the shell, not inside a column.
    GoRoute(
      path: '$kShellPreviewPrefix/action/:key',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => _actionFor(state.pathParameters['key']!),
    ),

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
