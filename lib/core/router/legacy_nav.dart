import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/home/screen/home_screen.dart';
import '../../features/home/settings/my-submission/my_submissions_screen.dart'
    show MySubmissionsArgs;
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
/// is the same guard that protects this. The `assert` below states that
/// contract to anyone who reaches for this from a new call site.
///
/// PUBLIC because callers outside this file need it: the verification wizard's
/// terminal step has to leave nine pageless routes behind, and its mobile route
/// differs enough from [goToCitizenHome] that it cannot share that helper.
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
void goClearingPageless(BuildContext context, String location) {
  assert(
    kIsWeb,
    'goClearingPageless is web-only: it resolves a GoRouter, and on mobile the '
    'legacy MaterialApp owns these screens so there is none. Call it inside an '
    'if (kIsWeb) branch.',
  );

  // Both looked up BEFORE the pop. `popUntil` can tear down the very screen
  // that called this — the password-changed, email-verified and face-scan
  // screens are all themselves pageless — and a defunct context resolves
  // neither lookup. Same hazard [pushLegacyOn] exists for, handled the same way.
  final navigator = Navigator.of(context);
  final router = GoRouter.of(context);

  // Unconditional by design. `popUntil` pops via `Navigator.pop`, which does
  // not consult `PopScope` — only `maybePop` and the system back gesture do —
  // so a guarded screen in the chain cannot stall this into a loop.
  navigator.popUntil((route) => route.settings is Page);

  // ── Why the `go` waits a frame ─────────────────────────────────────────────
  // `popUntil` leaves the navigator mid-operation: its history flush has not
  // settled, so `_debugLocked` is still set. Firing `go` in the same turn
  // re-resolves the match list and deactivates this very Navigator, and at
  // finalizeTree `NavigatorState.dispose` asserts `!_debugLocked` and throws —
  // which aborts the frame, so the destination never paints and the user is
  // left on a blank page.
  //
  // The pop and the re-resolve therefore have to be in different frames.
  //
  // ── Why this cannot strand the user ───────────────────────────────────────
  // [router] was captured above, BEFORE the pop, so the callback holds no
  // BuildContext and does not care whether the caller's widget survived — a
  // defunct context cannot stop the navigation.
  //
  // The remaining risk is the callback never running because no frame is
  // scheduled. `popUntil` dirties the tree and so normally schedules one, but
  // "normally" is not a guarantee worth a stuck sign-out: scheduleFrame() makes
  // the frame unconditional, so the callback always fires and a logout always
  // lands on /login.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    // ── Already there ────────────────────────────────────────────────────────
    // The web auth guard navigates on its own whenever the session changes, so
    // it can reach the destination before this callback runs. Going again from
    // here re-resolves a match list that already describes where we are: the
    // page keys are the route PATTERNS, so the pages themselves are reused and
    // nothing visibly moves — but it still reports a fresh navigation to the
    // engine and pushes a second browser history entry for one destination, so
    // Back then has to be pressed twice to leave.
    //
    // The pop above has already done the part that is NOT redundant — clearing
    // the pageless routes — and it ran unconditionally, so skipping the `go`
    // cannot leave the stack half-cleared.
    //
    // Both call sites pass a bare path with no query string, so comparing
    // against `matchedLocation` is exact. A caller that ever passes a query
    // (a feed deep link, say) would compare unequal and simply go, which is the
    // safe direction to be wrong in.
    if (router.state.matchedLocation == location) return;

    router.go(location);
  });
  WidgetsBinding.instance.scheduleFrame();
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
    // See [goClearingPageless].
    goClearingPageless(context, _kLoginPath);
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
    // See [goClearingPageless].
    goClearingPageless(context, CitizenTab.home.path);
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

// ── After a submission lands ────────────────────────────────────────────────
//
// A citizen who has just filed something is not trying to get back to the feed;
// they are trying to see the thing they filed. So the three quick actions no
// longer merely dismiss themselves on success — they dismiss themselves AND go
// to the list the new row is in: a report to My Reports, a suggestion or a
// piece of feedback to the matching tab of My Submissions.
//
// ── Why one helper for both platforms ──────────────────────────────────────
// The forms are hosted in two quite different ways, and neither of them is the
// call site's business:
//
//   • mobile — the form is a route pushed over HomePage, so the destination is
//     a second push and the dismissal is a pop.
//   • web — the form is a dialog over the shell (see
//     showCitizenSplitPanelDialog), so the destination is a `go` into the
//     shell's own branches and the dismissal is popping the dialog.
//
// Putting the split here keeps it in the one file that already owns "which
// router am I under", and leaves each form with a single unconditional call.
//
// ── Why the navigator and router are captured FIRST ────────────────────────
// Both branches destroy the calling context: the pop tears down the very form
// that is calling this. A lookup afterwards would run against a defunct
// context. This is the same hazard [pushLegacyOn] and [goClearingPageless] are
// each documented for, handled the same way — resolve both BEFORE popping.
//
// ── Why the pop is unconditional and not `onClose` ─────────────────────────
// The split-panel's `close` callback consults the form's discard guard, which
// asks "discard this submission?" — the wrong question once the row is already
// in the database. Popping the dialog directly is what the success path always
// did; only the navigation after it is new.

/// Dismisses a just-submitted quick-action form and lands the citizen on the
/// list their new row appears in.
///
/// [tab] is the My Submissions tab — 0 Reports · 1 Suggestions · 2 Feedback —
/// and matches [MySubmissionsArgs.initialTab]. Tab 0 is special: a REPORT has
/// its own dedicated screen (My Reports on mobile, the My Reports branch of the
/// shell on web) which is richer than the submissions list's Reports tab, so
/// that is where a report goes.
///
/// [username] is only read on mobile, where the legacy routes still take a name
/// rather than resolving identity from the profile provider.
void goToSubmissionList(
  BuildContext context, {
  required int tab,
  required String username,
}) {
  assert(tab >= 0 && tab <= 2, 'tab must be 0 (Reports), 1 or 2.');

  if (kIsWeb) {
    // All three resolved BEFORE anything is dismissed — see the note above.
    final navigator = Navigator.of(context);
    final router = GoRouter.of(context);
    // The form's OWN route: the split-panel dialog when hosted as one, and the
    // shell's page when the form is somewhere with no dialog around it.
    final route = ModalRoute.of(context);
    final location = tab == 0
        ? CitizenTab.myReports.path
        // `justSubmitted` rides the URL so the screen knows the row it is
        // looking for was written seconds ago and may not be readable yet.
        // See [MySubmissionsScreen.justSubmitted].
        : shellSubmissionsPath(tab: tab, justSubmitted: true);

    // ── Dismissed BY IDENTITY, not by popping the top ─────────────────────
    // `Navigator.pop` removes whatever is on top of the navigator, which is
    // only the split panel while the split panel is certainly on top — the
    // confusion [AppDialogHandle] exists to prevent, and worth avoiding here
    // for the same reason even though nothing is currently pushed over a
    // submitting form.
    //
    // `settings is! Page` is the same test [goClearingPageless] uses to tell
    // go_router's own routes from imperatively-pushed ones: the split panel is
    // pageless, so this removes it, while a form hosted AS a go_router page has
    // nothing to dismiss and the `go` below is the whole navigation. Removing a
    // page-based route by hand would desync go_router from its match list.
    if (route != null && route.isActive && route.settings is! Page) {
      if (route.isCurrent) {
        navigator.pop();
      } else {
        navigator.removeRoute(route);
      }
    }

    // ── Why this waits a frame ────────────────────────────────────────────
    // Identical to [goClearingPageless]: the dismissal leaves the navigator
    // mid-operation with `_debugLocked` still set, and a `go` in the same turn
    // re-resolves the match list and deactivates that Navigator, which trips
    // the `!_debugLocked` assert in dispose and aborts the frame — leaving the
    // citizen on a blank page instead of their submission. The router was
    // captured above, so the callback holds no BuildContext and does not care
    // that the form is gone by the time it runs.
    WidgetsBinding.instance.addPostFrameCallback((_) => router.go(location));
    WidgetsBinding.instance.scheduleFrame();
    return;
  }

  // ── Mobile ───────────────────────────────────────────────────────────────
  final navigator = Navigator.of(context);
  final String name;
  final Object arguments;
  if (tab == 0) {
    name = '/my_reports';
    arguments = username;
  } else {
    name = '/my_submissions';
    arguments = MySubmissionsArgs(
      username: username,
      initialTab: tab,
      justSubmitted: true,
    );
  }

  // ── REPLACE, not pop-then-push ───────────────────────────────────────────
  // Both leave the same stack — HomePage with the list on top, so Back returns
  // to Home exactly as it did before this feature and never to the form that
  // was just submitted. `pushReplacement` is chosen for the TRANSITION.
  //
  // Popping first plays the form route's 300ms reverse fade, and the push then
  // covers it mid-fade: two route animations racing over one hand-off, which
  // reads as a flicker of Home between the form and the list. A replacement is
  // one route change — the old route is removed without its reverse transition
  // once the new one is in place.
  //
  // The result is the convention the rest of the app already uses (see
  // `_instant` / `_slideUp` in app_router): the route swap is instant, and the
  // motion the citizen actually sees is the destination's OWN entry animation
  // — MyReportsScreen's `_entryCtrl` fade+slide, MySubmissionsScreen's
  // `_slideCtrl`. No double-slide, nothing sliding out from under them.
  //
  // `PopScope` is not a concern: the forms guard with `canPop: false` and a
  // discard prompt, but that only intercepts `maybePop` and the system back
  // gesture — never an imperative pop or replacement. Which is correct here;
  // the row is already in the database, so "discard this?" is the wrong
  // question, and it is why the success path was an imperative pop before too.
  navigator.pushReplacement<void, void>(_legacyRoute<void>(name, arguments));
}
