import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/auth_ready.dart' show awaitAuthReady;
import '../../core/services/connectivity_service.dart';
import '../../core/services/session_cache.dart';
import '../../core/network/network_wrapper.dart';
import '../../core/network/no_internet_screen.dart';
import '../../core/router/app_router.dart';
import '../../core/router/legacy_nav.dart';
import '../../core/providers/community_posts_provider.dart';
import '../admin/screens/admin_dashboard_screen.dart';
import '../staff/screens/staff_console_screen.dart';
import '../auth/facebook_username_screen.dart';

/// ===============================
/// SPLASH SCREEN
/// ===============================
class GovPulseSplashScreen extends StatefulWidget {
  const GovPulseSplashScreen({super.key});

  @override
  State<GovPulseSplashScreen> createState() => _GovPulseSplashScreenState();
}

class _GovPulseSplashScreenState extends State<GovPulseSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  late final Animation<double> _containerScale;
  late final Animation<double> _logoScale;
  late final Animation<double> _textSlide;
  late final Animation<double> _floodProgress;

  bool _showLoader = false;
  Timer? _loaderArmTimer;
  bool _goOffline = false;
  bool _navigated = false; // ensures we only navigate away from splash once

  late final TextPainter _textPainter;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3400),
    );

    _containerScale = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.28, curve: Curves.easeOutBack),
    );

    _logoScale = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.2, 0.5, curve: Curves.easeOutExpo),
    );

    _textSlide = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.35, 0.65, curve: Curves.easeOutCubic),
    );

    _floodProgress = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.55, 1.0, curve: Curves.easeInOutCubic),
    );

    _textPainter = TextPainter(
      text: const TextSpan(
        text: "GovPulse",
        style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Let the raster thread finish cold-start work before the first
      // heavy paint (shadow + gradient). Removes the entrance stutter.
      await Future.delayed(const Duration(milliseconds: 150));
      if (mounted) _start();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Decode the logo before the animation needs it, so the logo-scale
    // step doesn't drop a frame.
    precacheImage(const AssetImage('assets/images/applogo.webp'), context);
  }

  /// Re-reads `profiles` / `user_roles` after an offline-cached route has
  /// already landed, so a role or username that changed while this device was
  /// offline is corrected on the next start rather than never.
  ///
  /// Also catches the one case the cache must not paper over: an account
  /// soft-deactivated while offline. The cached hints would happily route it
  /// into Home, so when the refresh reports `is_deactivated` we sign out and
  /// send them to /login, where the next sign-in surfaces the message.
  Future<void> _refreshSessionBehindDestination() async {
    final deactivated =
        await SessionCache.instance.refreshInBackground();
    if (deactivated != true) return;

    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
    await SessionCache.instance.clear();
    if (!mounted) return;

    final route = onGenerateRoute(const RouteSettings(name: '/login'));
    if (route == null) return;
    Navigator.of(context).pushAndRemoveUntil(route, (r) => false);
  }

  /// Whether this cold start can route from local state alone — no network.
  ///
  /// The SINGLE source of truth for that question, consulted by both
  /// [_start] (to decide whether the no-internet screen may be skipped) and
  /// [_navigateNext] (to decide whether to route from the cache). They must
  /// answer identically: when they disagreed, the splash skipped the offline
  /// screen and then declined to resume, stranding the user on a login form
  /// with no connection.
  ///
  /// Mobile only — web routes through the go_router guard instead.
  Future<bool> _canResumeFromCache() async {
    if (kIsWeb) return false;

    // Session restoration is ASYNCHRONOUS — it lands via `onAuthStateChange`,
    // which is the whole premise [AuthRestoration] exists for. Reading
    // `currentUser` without waiting therefore raced it, and a restored user
    // whose session had not yet landed read as signed-out: no cache hit, so the
    // no-internet screen appeared instead of Home. Returns instantly when the
    // session is already restored, and is bounded and non-throwing when there
    // is genuinely nobody to wait for.
    await awaitAuthReady(timeout: const Duration(seconds: 2));

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return false;
    if (!SessionCache.instance.hasEntryFor(user.id)) return false;

    // A user who has never finished onboarding is not resumable, however good
    // their cache: [_navigateNext] sends them to /intro, which leads to a
    // login form that needs the network.
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('seenOnboarding') ?? false;
    } catch (_) {
      // Unreadable prefs means the intro flag is unknown; treat that as "not
      // resumable" so we fall back to the connectivity-gated path rather than
      // skipping it on a guess.
      return false;
    }
  }

  /// Stops the spinner at the moment the next screen is about to be pushed.
  ///
  /// Called from every navigation point in [_navigateNext] rather than once up
  /// front, because the paths do different amounts of work: a cached resume
  /// pushes immediately, while a cold start still has `profiles` and
  /// `user_roles` to await. Tearing down at a single early point would end the
  /// spinner while the slowest path was still working — the exact confusion
  /// this exists to remove.
  ///
  /// Synchronous, and paired with no delay: the push happens on the same
  /// frame, so the spinner is replaced by the destination rather than leaving
  /// a bare white screen behind it.
  void _stopLoader() {
    _loaderArmTimer?.cancel();
    _loaderArmTimer = null;
    if (!_showLoader) return;
    setState(() => _showLoader = false);
  }

  /// Shows the spinner only if the work outlasts a short grace period.
  ///
  /// See the note at the call site: below the threshold the spinner would be a
  /// flicker announcing a wait that has already ended, so nothing is shown.
  void _armLoader() {
    _loaderArmTimer?.cancel();
    _loaderArmTimer = Timer(const Duration(milliseconds: 120), () {
      _loaderArmTimer = null;
      if (mounted) setState(() => _showLoader = true);
    });
  }

  Future<void> _navigateNext() async {
    if (_navigated) return; // guard against any duplicate navigation
    _navigated = true;

    bool goToIntro = false;

    // First launch on the app → show the onboarding intro once.
    // (Web is intentionally skipped.) The "seen" flag is set only when the
    // user actually finishes the intro (see the /intro route), so an
    // interrupted first launch still shows it next time.
    if (!kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      goToIntro = !(prefs.getBool('seenOnboarding') ?? false);
    }

    // Same restoration race as [_canResumeFromCache] guards against: without
    // this, `currentUser` below could read null for a user whose session was
    // still landing, dropping a signed-in citizen on /login. Instant when the
    // session is already restored.
    await awaitAuthReady(timeout: const Duration(seconds: 2));

    if (!mounted) return;

    // ── Session persistence ───────────────────────────────────────────────
    // Supabase restores a saved session automatically on app start. If a user
    // is still logged in (and this isn't the very first launch), skip login
    // and land them on Home instantly. Logging out clears the session, so
    // after sign-out this check is null and we fall through to /login.
    final user = Supabase.instance.client.auth.currentUser;
    if (!goToIntro && user != null) {
      // ── Offline / slow-network fast path ────────────────────────────────
      // The restored session is local, but `username` and `role_id` were not:
      // both came from queries that hang or throw with no connection, so a
      // signed-in user could not be ROUTED offline even though they were
      // demonstrably still signed in.
      //
      // [SessionCache] persists those two answers alongside the session that
      // proved them. On a hit we route from it immediately — no socket — and
      // let the real queries correct anything stale from behind the
      // destination screen. On a miss we fall through to the original
      // query-first path below, which is still right for a first cold start.
      // `goToIntro` is already false here, which is the other half of
      // [_canResumeFromCache]'s answer — so this is that same condition, not a
      // second copy of it.
      if (!kIsWeb && SessionCache.instance.hasEntryFor(user.id)) {
        final cachedRole = SessionCache.instance.roleFor(user.id);
        final cachedName =
            SessionCache.instance.usernameFor(user.id) ?? '';

        // Refresh behind the destination. Deliberately NOT awaited: waiting is
        // the exact stall this path exists to remove.
        unawaited(_refreshSessionBehindDestination());

        CommunityPostsProvider.instance.resetForAuthenticatedUser();

        if (cachedRole != 1 && cachedRole != 2) {
          _stopLoader();
          goToCitizenHome(context, username: cachedName);
          return;
        }
        _stopLoader();
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            pageBuilder: (_, _, _) => cachedRole == 1
                ? const NetworkWrapper(child: AdminDashboardScreen())
                : const NetworkWrapper(child: StaffConsoleScreen()),
          ),
        );
        return;
      }

      String username = '';
      int? roleId;
      bool deactivated = false;
      try {
        final row = await Supabase.instance.client
            .from('profiles')
            .select('username, is_deactivated')
            .eq('id', user.id)
            .maybeSingle();
        username = (row?['username'] as String?) ?? '';
        deactivated = (row?['is_deactivated'] as bool?) ?? false;
      } catch (_) {}

      // A soft-deactivated account must not resume its saved session. Drop the
      // session and fall through to /login, where the next sign-in attempt
      // surfaces the deactivation message.
      if (deactivated) {
        try {
          await Supabase.instance.client.auth.signOut();
        } catch (_) {}
        await SessionCache.instance.clear();
      } else {
        // Resolve role the same way AuthService.login does, so a restored
        // session routes by role instead of always landing on citizen Home.
        try {
          final roleRow = await Supabase.instance.client
              .from('user_roles')
              .select('role_id')
              .eq('user_id', user.id)
              .maybeSingle();
          roleId = roleRow?['role_id'] as int?;

          // Seed the offline fast path for the NEXT cold start. Only after a
          // real answer — caching a failed lookup is what would make a wrong
          // role stick across restarts.
          unawaited(
            SessionCache.instance.save(
              uid: user.id,
              username: username,
              roleId: roleId,
            ),
          );
        } catch (_) {}

        if (!mounted) return;

        // ── Finish an OAuth sign-up that a page reload interrupted ──────────
        // On mobile the Facebook round trip happens in an external browser and
        // hands control back to the STILL-RUNNING app, so login_screen can
        // await it and push the username picker itself.
        //
        // On web there is no running app to come back to: signInWithOAuth
        // navigates the whole page away, and the redirect back is a cold start.
        // Every await in that flow is gone, so a first-time Facebook user would
        // otherwise land straight in Home having never chosen a username.
        //
        // Catching it here is the only place that survives the reload. Scoped
        // to provider == 'facebook' AND a blank username so it cannot divert an
        // ordinary email account, which always has a username from signup.
        final provider = user.appMetadata['provider'] as String?;
        if (username.trim().isEmpty && provider == 'facebook') {
          final fbName =
              (user.userMetadata?['full_name'] ??
                      user.userMetadata?['name'] ??
                      '')
                  as String;
          _stopLoader();
          Navigator.of(context).pushReplacement(
            PageRouteBuilder(
              transitionDuration: Duration.zero,
              reverseTransitionDuration: Duration.zero,
              pageBuilder: (_, _, _) => NetworkWrapper(
                child: FacebookUsernameScreen(
                  facebookName: fbName,
                  onComplete: (picked) async {
                    await Supabase.instance.client
                        .from('profiles')
                        .update({'username': picked})
                        .eq('id', user.id);
                    if (!mounted) return;
                    CommunityPostsProvider.instance
                        .resetForAuthenticatedUser();
                    goToCitizenHome(
                      context,
                      username: picked,
                      clearStack: true,
                    );
                  },
                  onCancel: () async {
                    await Supabase.instance.client.auth.signOut();
                    if (!mounted) return;
                    Navigator.of(context).pushAndRemoveUntil(
                      onGenerateRoute(const RouteSettings(name: '/login'))!,
                      (route) => false,
                    );
                  },
                ),
              ),
            ),
          );
          return;
        }

        // Make sure the community feed is in authenticated (non-guest) mode.
        CommunityPostsProvider.instance.resetForAuthenticatedUser();

        // role_id == 1 → admin dashboard; 2 → staff console; else → Home.
        //
        // Citizens go through goToCitizenHome so the destination is right on
        // both platforms: the go_router shell on web, HomePage on mobile. The
        // two consoles keep their imperative push, which works under either
        // Navigator and is outside this cutover.
        if (roleId != 1 && roleId != 2) {
          _stopLoader();
          goToCitizenHome(context, username: username);
          return;
        }

        _stopLoader();
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            pageBuilder: (_, _, _) => roleId == 1
                ? const NetworkWrapper(child: AdminDashboardScreen())
                : const NetworkWrapper(child: StaffConsoleScreen()),
          ),
        );
        return;
      }
    }

    final routeName = goToIntro ? '/intro' : '/login';

    final route = onGenerateRoute(RouteSettings(name: routeName));
    if (!mounted) return;

    _stopLoader();
    Navigator.of(context).pushReplacement(
      route ??
          PageRouteBuilder(
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            pageBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
    );
  }

  Future<void> _start() async {
    // Warm up the intro screen's assets (logo + the first onboarding frames)
    // while the splash animation plays, so they're decoded before intro appears
    // and don't "pop"/resize a moment after the screen shows.
    //
    // Only the first two of the six frames are warmed: page one is what the
    // intro actually renders, page two covers the first swipe. Warming all six
    // would put ~1 MB of decoding on the launch path for pages the user may
    // never reach — the rest decode lazily as they're swiped to.
    if (mounted) {
      precacheImage(
        const AssetImage('assets/images/applogocrop.webp'),
        context,
      );
      precacheImage(
        const AssetImage('assets/images/storyboard/all_in_one.webp'),
        context,
      );
      precacheImage(
        const AssetImage('assets/images/storyboard/report.webp'),
        context,
      );
    }

    // Fire the check immediately, in parallel — don't block on it.
    final internetCheck = hasRealInternet();

    // Always let the full animation play.
    await _controller.forward();
    if (!mounted) return;

    // ── Spinner: armed when the background turns white ─────────────────────
    // It used to be armed AFTER the resume check and torn down as soon as the
    // internet probe answered — which is not when the next screen is ready.
    // Online with no session that read as: ~1s of spinner, then a second of
    // nothing while /login was still being resolved and pushed. A spinner that
    // stops before the wait does is worse than no spinner, because it says
    // "done" when nothing is.
    //
    // Now its lifetime is the WORK: armed here, cleared in [_navigateNext] at
    // the moment of the push.
    //
    // ── Why armed rather than shown ────────────────────────────────────────
    // Through a 120ms grace period, not immediately. A cached resume finishes
    // in a few frames, and a spinner that appears and vanishes inside 100ms is
    // a flicker — it draws the eye to report a wait that already ended. Under
    // the grace period nothing is shown at all and the handover looks clean;
    // past it the wait is real and the spinner is genuinely useful.
    _armLoader();

    // ── Destination first, connectivity second ────────────────────────────
    // The old order gated EVERYTHING on the internet check, so an offline
    // start showed the no-internet screen even to a user whose session was
    // sitting right there in local storage and who only wanted to look at
    // cached content. Now a cached session lands on its own screen and the
    // connectivity story is told from there (the NetworkWrapper each
    // destination is already wrapped in owns that), while a start with NO
    // session still can't do anything useful offline — login needs the
    // network — so that one keeps the blocking screen.
    //
    // Computed BEFORE the check is awaited, and that ordering is the whole
    // point: `hasRealInternet()` waits up to 8s on a dead connection, and the
    // animation only covers 3.4s of that. Awaiting it first therefore parked a
    // resumable user on the splash for seconds waiting on an answer their
    // route never consults. Reading local state first means the offline
    // resume costs nothing.
    // Must agree with the fast-path condition in [_navigateNext], INCLUDING
    // the onboarding flag. A user can hold a cached session while
    // `seenOnboarding` is still false — the flag is only written when someone
    // taps through the intro, and it lives in SharedPreferences while the
    // session lives in Supabase's own store, so the two can desynchronize.
    // When they disagreed, this skipped the no-internet screen and
    // [_navigateNext] then declined to resume, dropping the user on an intro →
    // login form with no connection to submit it to.
    final canResumeOffline = !kIsWeb && await _canResumeFromCache();
    if (!mounted) return;

    if (canResumeOffline) {
      // Don't await the probe — let it settle `cachedInternetStatus` in the
      // background so the destination's NetworkWrapper inherits a real answer
      // instead of re-probing from scratch.
      unawaited(
        internetCheck
            .then((v) => cachedInternetStatus = v)
            .catchError((_) => cachedInternetStatus = false),
      );

      await _navigateNext();
      return;
    }

    bool online;
    try {
      online = await internetCheck;
    } catch (_) {
      online = false;
    }
    if (!mounted) return;

    cachedInternetStatus = online;

    if (!online) {
      // Settle delay so the offline swap doesn't collide with the
      // animation's final frame.
      await Future.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      _loaderArmTimer?.cancel();
      _loaderArmTimer = null;
      setState(() {
        _showLoader = false;
        _goOffline = true;
      });
      _waitForInternet();
      return;
    }

    await _navigateNext();
  }

  Future<void> _waitForInternet() async {
    while (mounted) {
      await Future.delayed(const Duration(seconds: 3));
      final online = await hasRealInternet();
      if (online && mounted) {
        cachedInternetStatus = true;
        await _navigateNext();
        return;
      }
    }
  }

  @override
  void dispose() {
    _loaderArmTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_goOffline) {
      return const NoInternetScreen(hasInternet: false, onContinue: null);
    }

    final media = MediaQuery.of(context);
    final size = media.size;
    final safeBottom = media.padding.bottom;
    final textRowHeight = _textPainter.height;

    return Scaffold(
      backgroundColor: Colors.white,
      body: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final flood = _floodProgress.value;

            final gradientOpacity = 1 - ((flood - 0.9) / 0.1).clamp(0.0, 1.0);

            final whiteFade = Curves.easeInOut.transform(
              ((flood - 0.8) / 0.2).clamp(0.0, 1.0),
            );

            final bloomGlow = Curves.easeOut.transform(
              ((flood - 0.82) / 0.18).clamp(0.0, 1.0),
            );

            final settleScale =
                1 + (sin(flood * pi) * 0.02 * pow(1 - flood, 1.4));

            final subtleFloat = -8 * ((flood - 0.8).clamp(0.0, 0.2) / 0.2);

            final textColorProgress = ((flood - 0.7) / 0.3).clamp(0.0, 1.0);

            final shimmer = (sin(_controller.value * pi * 3) * 0.03).clamp(
              -0.015,
              0.015,
            );

            final translateY = -35 + subtleFloat;

            final containerCenter = Offset(
              size.width / 2,
              (size.height / 2) + translateY - (12 + textRowHeight / 2),
            );

            final maxRadius = [
              (Offset.zero - containerCenter).distance,
              (Offset(size.width, 0) - containerCenter).distance,
              (Offset(0, size.height) - containerCenter).distance,
              (Offset(size.width, size.height) - containerCenter).distance,
            ].reduce(max);

            return Stack(
              children: [
                // ── Gradient background ──
                Opacity(
                  opacity: gradientOpacity,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color(0xFF00448F),
                          Color(0xFF2380C3),
                          Color(0xFF2A9648),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                ),

                // ── Radial wave burst ──
                if (flood > 0 && flood < 1)
                  SizedBox.expand(
                    child: CustomPaint(
                      painter: RadialWaveBurstPainter(
                        progress: flood,
                        center: containerCenter,
                        maxRadius: maxRadius,
                      ),
                    ),
                  ),

                // ── White fade overlay — stays fully opaque at end ──
                Opacity(
                  opacity: whiteFade,
                  child: Container(color: Colors.white),
                ),

                // ── Bloom glow ──
                if (bloomGlow > 0)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: bloomGlow * 0.12,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: Alignment(
                                (containerCenter.dx / size.width) * 2 - 1,
                                (containerCenter.dy / size.height) * 2 - 1,
                              ),
                              radius: 0.8 + bloomGlow * 0.6,
                              colors: [
                                Colors.white,
                                Colors.white.withValues(alpha: 0.6),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                // ── Logo + text ──
                Center(
                  child: Transform.translate(
                    offset: Offset(0, translateY),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Transform.scale(
                          scale:
                              (_containerScale.value *
                                  (1 + flood * 0.025) *
                                  settleScale) +
                              shimmer,
                          child: Container(
                            width: 104,
                            height: 104,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(26),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(
                                    alpha:
                                        (0.05 + (whiteFade * 0.15)) *
                                        _containerScale.value.clamp(0.0, 1.0),
                                  ),
                                  blurRadius:
                                      (24 + (whiteFade * 20)) *
                                      _containerScale.value.clamp(0.0, 1.0),
                                  offset: Offset(
                                    0,
                                    (8 + (whiteFade * 6)) *
                                        _containerScale.value.clamp(0.0, 1.0),
                                  ),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(26),
                              child: Center(
                                child: Transform.scale(
                                  scale: _logoScale.value,
                                  child: Image.asset(
                                    'assets/images/applogo.webp',
                                    width: 70,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildText(
                              text: "Gov",
                              slide: -60,
                              progress: _textSlide.value,
                              color: Color.lerp(
                                Colors.white,
                                const Color(0xFF00448F),
                                textColorProgress,
                              )!,
                              letterSpacing: 1.2 * textColorProgress,
                            ),
                            _buildText(
                              text: "Pulse",
                              slide: 60,
                              progress: _textSlide.value,
                              color: Color.lerp(
                                Colors.white,
                                const Color(0xFF2A9648),
                                textColorProgress,
                              )!,
                              letterSpacing: 1.2 * textColorProgress,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Loader — kept in tree so AnimatedOpacity can fade it out ──
                //
                // Asymmetric on purpose. It appears INSTANTLY (0ms) the moment
                // the background finishes turning white, so the wait is
                // acknowledged the frame it begins rather than ramping in over
                // 300ms — on the fastest paths the push landed before a 300ms
                // fade-in even finished, which read as a flicker. It still
                // fades OUT over 300ms, so handing over to the next screen
                // stays soft.
                AnimatedOpacity(
                  opacity: _showLoader ? 1.0 : 0.0,
                  duration: Duration(milliseconds: _showLoader ? 0 : 300),
                  curve: Curves.easeOut,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: EdgeInsets.only(bottom: safeBottom + 85),
                      child: const SizedBox(
                        width: 42,
                        height: 42,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.6,
                          valueColor: AlwaysStoppedAnimation(Color(0xFF00448F)),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildText({
    required String text,
    required double slide,
    required double progress,
    required Color color,
    required double letterSpacing,
  }) {
    return Transform.translate(
      offset: Offset(slide * (1 - progress), 0),
      child: Opacity(
        opacity: progress,
        child: Text(
          text,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: color,
            letterSpacing: letterSpacing,
          ),
        ),
      ),
    );
  }
}

/// ===============================
/// ENHANCED WAVE PAINTER
/// ===============================
class RadialWaveBurstPainter extends CustomPainter {
  final double progress;
  final Offset center;
  final double maxRadius;

  RadialWaveBurstPainter({
    required this.progress,
    required this.center,
    required this.maxRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final eased = const Cubic(0.16, 1.0, 0.3, 1.0).transform(progress);

    final snappedCenter = Offset(
      center.dx.roundToDouble(),
      center.dy.roundToDouble(),
    );

    final radius = maxRadius * eased;

    final outerGlow = Paint()
      ..isAntiAlias = true
      ..shader =
          RadialGradient(
            colors: [
              Colors.white.withValues(alpha: 0.18 * (1 - progress)),
              Colors.white.withValues(alpha: 0.08 * (1 - progress)),
              Colors.transparent,
            ],
          ).createShader(
            Rect.fromCircle(center: snappedCenter, radius: radius * 1.4),
          );

    canvas.drawCircle(snappedCenter, radius * 1.4, outerGlow);

    final fillPaint = Paint()
      ..isAntiAlias = true
      ..shader = RadialGradient(
        colors: [
          Colors.white,
          Colors.white.withValues(alpha: 0.98),
          Colors.white.withValues(alpha: 0.92),
        ],
      ).createShader(Rect.fromCircle(center: snappedCenter, radius: radius));

    canvas.drawCircle(snappedCenter, radius, fillPaint);
  }

  @override
  bool shouldRepaint(covariant RadialWaveBurstPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.center != center ||
      oldDelegate.maxRadius != maxRadius;
}
