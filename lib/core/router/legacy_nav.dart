import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/home/screen/home_screen.dart';
import '../../features/home/shell/citizen_shell_router.dart';
import '../network/network_wrapper.dart';
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

// ── Where the user goes ─────────────────────────────────────────────────────
//
// The two destinations that differ per platform now that go_router owns the web
// URL. Both are centralised here so the split lives in ONE file rather than at
// every sign-out and every post-login branch.
//
// The paths are deliberately the SAME strings the legacy table uses ('/login'),
// so the two routers agree on what a destination is named even though they
// reach it differently. citizen_shell_router.dart declares its own copies —
// they are private there, and a shared constants file for three strings would
// be more indirection than it buys.
const String _kLoginPath = '/login';
const String _kSignupPath = '/signup';
const String _kGuestPath = '/guest';
const String _kNewsFeedPath = '/newsfeed';

/// `context.go`, with any imperatively-pushed pageless routes cleared first.
///
/// ── WEB ONLY ───────────────────────────────────────────────────────────────
/// Every call sits inside an `if (kIsWeb)` branch, and this must stay true.
/// [GoRouter.of] throws when there is no GoRouter above the context, and on
/// mobile there never is — the legacy `MaterialApp` owns those screens. That is
/// not a new hazard introduced here: the plain `context.go` this replaces had
/// exactly the same requirement, so the guard that already protects the branch
/// is the same guard that protects this.
///
/// ── Why the pop ────────────────────────────────────────────────────────────
/// Several flows are reached by imperative push and deliberately have no URL —
/// the reset-password chain and the sign-up verification chain carry auth
/// tokens and a plaintext password, which must not be addressable (see the
/// route policy note in citizen_shell_router.dart). Those pushes are correct.
/// What is not correct is firing `go()` while they are still on the stack: the
/// new match list only replaces go_router's OWN pages, so the imperative routes
/// stay mounted above the destination and the address bar stops describing what
/// is on screen.
///
/// Popping them first makes the stack match the match list before it changes.
///
/// ── Why `settings is Page` ─────────────────────────────────────────────────
/// That test is exactly what separates go_router's routes from imperative ones:
/// go_router builds Page-based routes, while `pushLegacy` and `Navigator.push`
/// build pageless ones. So this pops the pageless stack above the topmost
/// go_router page and stops there — it never pops a route go_router believes it
/// owns, which would be its own kind of desync.
///
/// It is a no-op in the common case: with nothing pushed, the top route's
/// settings is already a Page and the predicate passes on the first test.
void _goClearingPageless(BuildContext context, String location) {
  // Both looked up BEFORE the pop. `popUntil` can tear down the very screen
  // that called this — the password-changed and email-verified screens are
  // themselves pageless — and a defunct context resolves neither lookup. This
  // is the same hazard [pushLegacyOn] exists for, handled the same way.
  final navigator = Navigator.of(context);
  final router = GoRouter.of(context);

  // Unconditional by design. `popUntil` pops via `Navigator.pop`, which does
  // not consult `PopScope` — only `maybePop` and the system back gesture do —
  // so a guarded screen in the chain cannot stall this into a loop.
  navigator.popUntil((route) => route.settings is Page);

  router.go(location);
}

/// Sends the user to the login screen.
///
/// On web this is a `go`, so the address bar becomes `/#/login` and the shell is
/// torn down properly. `go` re-resolves the whole match list either way, so
/// [clearStack] is a MOBILE-only distinction.
///
/// [clearStack] defaults to true — the sign-out contract every existing caller
/// relies on. Sign-up passes false: moving between the two auth screens is
/// ordinary navigation and must stay the plain push it has always been, or
/// backing out of login would no longer return to sign-up on a phone.
Future<void> goToLogin(BuildContext context, {bool clearStack = true}) {
  if (kIsWeb) {
    // Cleared, not plain `go`: this is the way OUT of the reset-password and
    // sign-up verification chains, both of which are stacks of pageless routes.
    // See [_goClearingPageless].
    _goClearingPageless(context, _kLoginPath);
    return Future<void>.value();
  }
  if (!clearStack) return pushLegacy<void>(context, _kLoginPath);
  return Navigator.of(context).pushAndRemoveUntil<void>(
    _legacyRoute<void>(_kLoginPath, null),
    (route) => false,
  );
}

/// Sends the user to the sign-up screen.
///
/// Web gets a real `/#/signup` URL; mobile keeps the imperative push it has
/// always had. Same split as [goToLogin], same reason.
Future<void> goToSignup(BuildContext context) {
  if (kIsWeb) {
    context.go(_kSignupPath);
    return Future<void>.value();
  }
  return pushLegacy<void>(context, _kSignupPath);
}

/// Sends a visitor who chose "Continue as Guest" to the guest landing screen.
///
/// On web this is a `go`, so `/#/guest` is a real URL a guest can reload onto
/// instead of being dropped back to login. The auth guard already treats
/// `/guest` as public, so this passes without a redirect even though a guest
/// holds no Supabase session.
///
/// On mobile it stays the imperative push: the auth screens are shared by BOTH
/// routers, and under the legacy `MaterialApp` there is no GoRouter above them
/// for `context.go` to resolve against.
Future<void> goToGuest(BuildContext context) {
  if (kIsWeb) {
    context.go(_kGuestPath);
    return Future<void>.value();
  }
  return pushLegacy<void>(context, _kGuestPath);
}

/// Sends a guest from the landing screen into the community feed.
///
/// On web this is the payoff of the whole guest flow: `/#/newsfeed` is a real
/// route, so a guest can reload onto the feed or share the link instead of
/// sitting on a screen pushed over `/#/guest` with no address of its own. The
/// route bakes in `isGuest: true`, and the auth guard permits it for guests —
/// which is why no arguments travel with the web branch.
///
/// On mobile there is no such route: the feed is still the standalone
/// [NewsFeedScreen] resolved through the legacy table, and it needs the
/// arguments to know it is in guest mode. Unchanged from before.
Future<void> goToGuestFeed(BuildContext context) {
  if (kIsWeb) {
    context.go(_kNewsFeedPath);
    return Future<void>.value();
  }
  return pushLegacy<void>(
    context,
    _kNewsFeedPath,
    arguments: const {'isGuest': true, 'isVerified': false},
  );
}

/// Backs a guest out of the feed, to the guest landing screen.
///
/// The two platforms genuinely differ here, which is why this is a navigation
/// on web and a pop on mobile rather than one call with a guard inside it:
///
///   • web — the feed is its own top-level route, so there is nothing beneath
///     it to pop. Back has to be an actual navigation to /guest.
///   • mobile — the feed is pushed on top of the guest screen, so popping is
///     both correct and the only thing that preserves the screen underneath.
void leaveGuestFeed(BuildContext context) {
  if (kIsWeb) {
    context.go(_kGuestPath);
    return;
  }
  Navigator.of(context).pop();
}

/// Sends an authenticated citizen to their home surface.
///
/// On web that is the SHELL at `/home` — this is the call that makes the
/// cutover real, because it is what every successful login funnels through.
/// On mobile it is [HomePage], pushed exactly as before: [clearStack] picks
/// between the `pushReplacement` the password login used and the
/// `pushAndRemoveUntil` the Facebook and splash paths used.
void goToCitizenHome(
  BuildContext context, {
  required String username,
  bool clearStack = false,
}) {
  if (kIsWeb) {
    // go() re-resolves the whole match list, so the shell replaces whatever
    // auth screen was on screen and the URL follows.
    //
    // There IS a stack to clear, though — the note that used to say otherwise
    // was written before the Facebook path was traced. Both callers push
    // FacebookUsernameScreen imperatively over /login or /signup and land here
    // from its `onComplete`, so the picker is still mounted at this point.
    // See [_goClearingPageless].
    _goClearingPageless(context, CitizenTab.home.path);
    return;
  }

  final route = PageRouteBuilder<void>(
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (_, _, _) => NetworkWrapper(child: HomePage(username: username)),
    transitionsBuilder: (_, _, _, child) => child,
  );

  if (clearStack) {
    Navigator.of(context).pushAndRemoveUntil<void>(route, (route) => false);
  } else {
    Navigator.of(context).pushReplacement<void, void>(route);
  }
}
