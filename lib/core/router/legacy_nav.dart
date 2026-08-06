import 'package:flutter/material.dart';

import 'app_router.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Legacy named-route navigation that works under BOTH routers.
//
//  `Navigator.pushNamed` resolves a name against the enclosing Navigator's
//  `onGenerateRoute`. Under the legacy `MaterialApp` that is
//  [onGenerateRoute] in app_router.dart, so it works. Under
//  `MaterialApp.router` it is NULL — go_router builds its own Navigator and
//  never sets one — so every named push throws:
//
//      Navigator.onGenerateRoute was null, but the route named "/settings"
//      was referenced.
//
//  These helpers do by hand what the framework does internally: resolve the
//  name through [onGenerateRoute] and push the resulting [Route] imperatively.
//  An imperative push works on any Navigator, so the same call site is correct
//  before and after the go_router cutover.
//
//  ── Deliberately no URL ────────────────────────────────────────────────────
//  A screen pushed this way does not appear in the address bar and does not
//  survive a reload. That is the trade: the whole legacy table keeps working on
//  web on day one, and routes graduate to real `GoRoute`s — with a real,
//  shareable, reload-proof URL — one at a time, as each earns it. Until a route
//  graduates, this is how it is reached.
//
//  ── Behaviour is identical to what it replaces ─────────────────────────────
//  Same resolver, same `RouteSettings`, same returned `Route`, same
//  `Navigator.of(context)` lookup (nearest, not root). So on mobile — which
//  keeps the legacy `MaterialApp` — nothing observable changes.
//
//  NOT for imperative pushes. `Navigator.push(ctx, PageRouteBuilder(...))`
//  already works under both routers and must be left exactly as it is.
// ════════════════════════════════════════════════════════════════════════════

/// Resolves [name] through the app's [onGenerateRoute], or throws with the
/// offending name — which beats the framework's `onUnknownRoute` assertion,
/// since these calls are all internal and a miss is always a typo.
Route<T?> _legacyRoute<T extends Object?>(String name, Object? arguments) {
  final route = onGenerateRoute(
    RouteSettings(name: name, arguments: arguments),
  );
  if (route == null) {
    throw FlutterError(
      'legacy_nav: no route generated for "$name".\n'
      'Every name passed to pushLegacy/pushReplacementLegacy must be handled '
      'by onGenerateRoute in core/router/app_router.dart.',
    );
  }
  // The same cast Navigator._routeNamed performs. Legacy routes are built
  // untyped (`PageRouteBuilder` with no type argument), so this succeeds for
  // the untyped call sites and fails loudly for a wrongly-typed one — again
  // matching pushNamed.
  return route as Route<T?>;
}

/// `Navigator.pushNamed`, resolved through [onGenerateRoute] so it also works
/// under go_router's Navigator.
///
/// Returns the pushed route's result, so callers awaiting a value — a screen
/// that pops `true` to signal "something changed" — keep working unchanged.
Future<T?> pushLegacy<T extends Object?>(
  BuildContext context,
  String name, {
  Object? arguments,
}) {
  return Navigator.of(context).push<T?>(_legacyRoute<T>(name, arguments));
}

/// [pushLegacy] against an already-resolved [NavigatorState].
///
/// For the one shape `Navigator.of(context)` cannot serve: a dialog that pops
/// ITSELF and then routes. Its context is defunct the moment it pops, so the
/// navigator has to be captured beforehand — and the pop must come first, or
/// the pop tears down the screen that was just pushed.
Future<T?> pushLegacyOn<T extends Object?>(
  NavigatorState navigator,
  String name, {
  Object? arguments,
}) {
  return navigator.push<T?>(_legacyRoute<T>(name, arguments));
}

/// `Navigator.pushReplacementNamed`, same contract as [pushLegacy].
Future<T?> pushReplacementLegacy<T extends Object?, TO extends Object?>(
  BuildContext context,
  String name, {
  Object? arguments,
  TO? result,
}) {
  return Navigator.of(context).pushReplacement<T?, TO>(
    _legacyRoute<T>(name, arguments),
    result: result,
  );
}

/// Sends the user to the login screen and clears the whole stack behind them.
///
/// Every sign-out and every "back to sign in" path funnels through here. It is
/// centralised precisely because it is the one destination that must change
/// when go_router takes over the web URL: this becomes `context.go('/login')`
/// on web, and that will be a one-file edit rather than a fourteen-site sweep.
Future<void> goToLogin(BuildContext context) {
  return Navigator.of(context).pushAndRemoveUntil<void>(
    _legacyRoute<void>('/login', null),
    (route) => false,
  );
}
