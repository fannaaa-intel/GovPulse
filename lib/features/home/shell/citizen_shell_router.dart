import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/citizen_ui.dart';
import 'citizen_shell.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Routing for the citizen web shell PREVIEW.
//
//  This is a scratch mount. Nothing here is reachable from the live app: the
//  shell is only built when the browser is loaded directly at /shell-preview,
//  and every real route still goes through the existing Navigator 1.0 table in
//  core/router/app_router.dart. The mobile app never sees any of it.
//
//  ── Why a whole separate MaterialApp ───────────────────────────────────────
//  Two routers cannot both own the browser URL. The live app is a MaterialApp
//  with `routes` + `onGenerateRoute`, and on web Navigator 1.0 already reports
//  its route names to the address bar. Nesting a go_router Router inside it
//  would leave both writing history entries and fighting over the location.
//
//  So the two are mutually exclusive at launch, exactly the way main.dart
//  already treats the /scan/<token> deep link: the app inspects the launch URL
//  once and builds EITHER the normal MaterialApp OR this one. They never
//  coexist, so go_router genuinely owns the URL here — which is the whole point,
//  since URL-addressable tabs and a working browser Back are what this step is
//  meant to prove.
//
//  ── Why the tabs are namespaced under /shell-preview ───────────────────────
//  The tab paths are /shell-preview/home, /shell-preview/newsfeed, … rather
//  than bare /home, /newsfeed. Two reasons, both load-bearing:
//
//    1. Reload safety. Selecting a tab rewrites the address bar. If the paths
//       were bare, reloading on /newsfeed would hand main.dart a launch route
//       it doesn't recognise as the preview, and the user would silently drop
//       into the live app instead. Namespacing keeps every reachable preview
//       URL inside the prefix, so refresh always lands back in the shell.
//    2. Zero collision. The live table already owns '/newsfeed', '/settings',
//       '/emergency' and friends. Sharing those names between two routers is
//       how a scratch mount stops being scratch.
//
//  Phase 2 drops the prefix when the shell takes over the real routes.
// ════════════════════════════════════════════════════════════════════════════

/// URL prefix every preview route lives under. See the note above.
const String kShellPreviewPrefix = '/shell-preview';

/// The five top-level destinations, in nav order. The index into
/// [CitizenTab.values] IS the IndexedStack index, so order is load-bearing and
/// matches the 0–4 contract [HomeTopNav] and the legacy nav widgets already use.
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

/// The tab a location belongs to, defaulting to [CitizenTab.home] for anything
/// unrecognised. Matches sub-paths too, so a future
/// `/shell-preview/newsfeed/<postId>` still resolves to the NewsFeed tab.
CitizenTab tabForLocation(String location) => CitizenTab.values.firstWhere(
  (t) => location == t.path || location.startsWith('${t.path}/'),
  orElse: () => CitizenTab.home,
);

/// True when the app was launched at a preview URL and should build
/// [CitizenShellPreviewApp] instead of the live MaterialApp.
///
/// Deliberately strict about the boundary: it matches the prefix exactly, or
/// followed by `/` or `?`, so a real route that merely *starts with* the same
/// letters could never be swallowed by the preview.
bool isShellPreviewLaunch(String? route) {
  if (route == null) return false;
  return route == kShellPreviewPrefix ||
      route.startsWith('$kShellPreviewPrefix/') ||
      route.startsWith('$kShellPreviewPrefix?');
}

/// The preview's router.
///
/// The [ShellRoute] is what keeps [CitizenShell] mounted ONCE while the
/// location changes underneath it — a plain list of top-level routes would give
/// each tab its own page, rebuilding the shell's State on every switch and
/// destroying exactly the persistence this is meant to demonstrate.
///
/// The child routes build `SizedBox.shrink()` on purpose. They exist to make
/// each tab a real, addressable location; the visible pane comes from the
/// shell's own IndexedStack, which has to hold all five panes at once and so
/// cannot be fed one-at-a-time by the router. `child` is therefore discarded in
/// the builder — see the note in citizen_shell.dart.
final GoRouter citizenShellRouter = GoRouter(
  initialLocation: CitizenTab.home.path,
  routes: <RouteBase>[
    // Bare /shell-preview is not a destination — send it to the first tab.
    GoRoute(
      path: kShellPreviewPrefix,
      redirect: (_, _) => CitizenTab.home.path,
    ),
    ShellRoute(
      builder: (context, state, child) => CitizenShell(
        location: state.uri.path,
        // Deep-link target for the pane being opened, e.g.
        // /shell-preview/newsfeed?target=<postId>. Carried in the URL so a
        // deep link is shareable and survives reload.
        target: state.uri.queryParameters['target'],
      ),
      routes: <RouteBase>[
        for (final tab in CitizenTab.values)
          GoRoute(path: tab.path, builder: (_, _) => const SizedBox.shrink()),
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
