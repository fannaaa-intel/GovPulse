import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/staff/providers/staff_providers.dart';
import '../providers/user_profile_provider.dart';
import '../services/connectivity_service.dart';
import 'no_internet_screen.dart';
import 'web_reachability.dart';

bool? cachedInternetStatus;

class NetworkWrapper extends ConsumerStatefulWidget {
  final Widget child;
  const NetworkWrapper({super.key, required this.child});

  @override
  ConsumerState<NetworkWrapper> createState() => _NetworkWrapperState();
}

/// Marks that a [NetworkWrapper] is already painting the toast further up the
/// tree, so a nested one renders its child and nothing else.
///
/// On web the wrapper is mounted once at the app root (see
/// `GovPulseWebApp.builder`), but the per-route wrappers below it are still
/// needed by the LEGACY MOBILE router, which shares those same route builders
/// and relies on the wrapper for its full-screen offline screen. Without this
/// marker every such route on web would stack a second toast at the identical
/// top-centre position — both wrappers go offline on the same event, so the
/// two pills would land exactly on top of each other and read as one
/// double-shadowed, over-dark pill.
///
/// Only the toast is suppressed. The nested wrapper still listens and still
/// runs [_NetworkWrapperState._refreshAfterReconnect], which is idempotent.
class _ToastMountedAbove extends InheritedWidget {
  const _ToastMountedAbove({required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ToastMountedAbove>() != null;

  @override
  bool updateShouldNotify(_ToastMountedAbove oldWidget) => false;
}

class _NetworkWrapperState extends ConsumerState<NetworkWrapper> {
  bool? _hasInternet;
  StreamSubscription? _subscription;
  Timer? _offlineDebounce;
  Timer? _onlineDebounce;

  // ── Web-only connectivity toast state ──────────────────────────────────────
  // On the website we don't take over the screen; we trust the browser's
  // online/offline signal (navigator.onLine) and float a small toast instead —
  // a persistent "Trying to reconnect…" while offline, then a brief
  // "Reconnected" when it returns. See [_ConnectivityToast].
  bool _webOffline = false;
  bool _showReconnected = false;
  Timer? _reconnectedTimer;
  StreamSubscription<bool>? _reachabilitySub;

  /// Single entry point for every web offline/online transition, so the
  /// browser signal and the confirmed-reachability signal can never disagree
  /// about what the toast is showing.
  ///
  /// Idempotent: re-reporting the state already on screen does nothing, which
  /// matters because both sources fire on the same real-world event and the
  /// probe retries on a timer.
  void _setWebOffline(bool offline) {
    if (!mounted || offline == _webOffline) return;

    if (offline) {
      _reconnectedTimer?.cancel();
      setState(() {
        _webOffline = true;
        _showReconnected = false;
      });
      return;
    }

    setState(() {
      _webOffline = false;
      _showReconnected = true;
    });
    _refreshAfterReconnect();
    // Auto-dismiss the "Reconnected" pill after a moment.
    _reconnectedTimer?.cancel();
    _reconnectedTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showReconnected = false);
    });
  }

  @override
  void initState() {
    super.initState();

    // Web: dart:io pings aren't available, so rely on the browser's
    // online/offline events and surface a toast rather than the mobile
    // full-screen overlay. The page stays fully interactive.
    if (kIsWeb) {
      _hasInternet = true;
      cachedInternetStatus = true;

      // Seed the initial state in case we mount while already offline.
      Connectivity().checkConnectivity().then((results) {
        final online = !results.every((r) => r == ConnectivityResult.none);
        if (mounted && !online) setState(() => _webOffline = true);
      });

      _subscription = Connectivity().onConnectivityChanged.listen((results) {
        final online = !results.every((r) => r == ConnectivityResult.none);
        // `online` here is navigator.onLine — it only says an interface EXISTS.
        // The negative direction is trustworthy and applied immediately; the
        // positive direction is only a candidate, and [WebReachability]
        // confirms it against the backend before the toast is taken down.
        if (!online) {
          _setWebOffline(true);
        }
        WebReachability.instance.reportBrowserSignal(online: online);
      });

      // ── The signal navigator.onLine cannot give ─────────────────────────
      // Captive portals, a dead uplink, and a connection so weak that requests
      // connect and never answer all read as ONLINE to the browser. This
      // stream carries the CONFIRMED answer — probed against the backend, and
      // triggered by real request failures rather than by polling.
      _reachabilitySub = WebReachability.instance.onChanged.listen((reachable) {
        if (!mounted) return;
        _setWebOffline(!reachable);
      });
      return;
    }

    if (cachedInternetStatus != null) {
      _hasInternet = cachedInternetStatus;
    } else {
      Future.delayed(const Duration(milliseconds: 300), _checkInternet);
    }

    _subscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) async {
      final hasConnection = !results.every((r) => r == ConnectivityResult.none);

      if (!hasConnection) {
        _onlineDebounce?.cancel();
        _onlineDebounce = null;
        if (_offlineDebounce != null) return;

        _offlineDebounce = Timer(const Duration(seconds: 3), () async {
          _offlineDebounce = null;
          final reallyOffline = !(await hasRealInternet());
          if (mounted && reallyOffline) {
            cachedInternetStatus = false;
            setState(() => _hasInternet = false);
          }
        });
      } else {
        _offlineDebounce?.cancel();
        _offlineDebounce = null;
        if (_onlineDebounce != null) return;

        _onlineDebounce = Timer(const Duration(seconds: 2), () async {
          _onlineDebounce = null;
          final reallyOnline = await hasRealInternet();
          if (mounted && reallyOnline) {
            cachedInternetStatus = true;
            setState(() => _hasInternet = true);
            _refreshAfterReconnect();
          }
        });
      }
    });
  }

  Future<void> _checkInternet() async {
    final result = await hasRealInternet();
    cachedInternetStatus = result;
    if (mounted) setState(() => _hasInternet = result);
    if (result) _refreshAfterReconnect();
  }

  /// Re-reads the signed-in account's profile once the connection returns.
  ///
  /// ── Why this is needed ────────────────────────────────────────────────────
  /// A cold start with no internet renders the profile from
  /// [SessionCache] — or, before that cache existed, from a default that read
  /// as "unverified with no data". Either way the answer on screen was decided
  /// while offline, and NOTHING re-fetched it afterwards: every existing
  /// invalidation of `userProfileProvider` hangs off a login, a sign-out, or a
  /// manual profile edit. So a user who opened the app offline kept a stale or
  /// wrong account view for the entire session, even after reconnecting.
  ///
  /// [UserProfileNotifier.silentRefresh] keeps the current value when the
  /// re-fetch fails, so a flapping connection can never blank the account out.
  void _refreshAfterReconnect() {
    if (!mounted) return;

    // `Supabase.instance` ASSERTS when the client was never initialized, so a
    // bare read crashes anywhere the app is not fully booted — widget tests
    // that pump a screen in isolation being the common case. A reconnect
    // refresh is a nicety; it must never be the thing that brings a screen
    // down. Same reasoning for the provider reads below.
    try {
      if (Supabase.instance.client.auth.currentUser == null) return;
    } catch (_) {
      return;
    }

    ref.read(userProfileProvider.notifier).silentRefresh();

    // Staff and admin consoles carry their own identity — name, photo,
    // department — and lose it offline exactly the same way. Only refreshed
    // when that provider is already alive, so a citizen never triggers a staff
    // query: reading it unconditionally would CREATE the provider and fetch an
    // identity the signed-in user has no rows for.
    if (ref.exists(staffIdentityProvider)) {
      ref.read(staffIdentityProvider.notifier).silentRefresh();
    }
  }


  @override
  void dispose() {
    _offlineDebounce?.cancel();
    _onlineDebounce?.cancel();
    _reconnectedTimer?.cancel();
    _subscription?.cancel();
    _reachabilitySub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Web: keep the page fully usable; just float a reconnect / reconnected
    // toast at the top. No full-screen takeover.
    if (kIsWeb) {
      // Already covered from above — render the child only. See
      // [_ToastMountedAbove] for why the nested wrapper still exists at all.
      if (_ToastMountedAbove.of(context)) return widget.child;

      return _ToastMountedAbove(
        child: Stack(
          children: [
            widget.child,
            Positioned.fill(
              child: SafeArea(
                child: IgnorePointer(
                  child: _ConnectivityToast(
                    offline: _webOffline,
                    showReconnected: _showReconnected,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        widget.child,
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 450),
          reverseDuration: const Duration(milliseconds: 350),
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position:
                    Tween<Offset>(
                      begin: const Offset(0, 0.06),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      ),
                    ),
                child: child,
              ),
            );
          },
          child: _hasInternet == false
              ? NoInternetScreen(
                  key: const ValueKey('no-internet'),
                  hasInternet: false,
                  onContinue: () {
                    cachedInternetStatus = true;
                    setState(() => _hasInternet = true);
                  },
                )
              : const SizedBox.shrink(key: ValueKey('online')),
        ),
      ],
    );
  }
}

/// Web-only connectivity toast: a persistent "Trying to reconnect…" pill while
/// offline, swapped for a brief "Reconnected" pill when the connection returns.
/// Slides up + fades in on show; fades out when dismissed.
class _ConnectivityToast extends StatelessWidget {
  final bool offline;
  final bool showReconnected;
  const _ConnectivityToast({
    required this.offline,
    required this.showReconnected,
  });

  @override
  Widget build(BuildContext context) {
    Widget? pill;
    if (offline) {
      pill = _pill(
        key: const ValueKey('offline'),
        bg: const Color(0xFF1F2937),
        leading: const SizedBox(
          width: 15,
          height: 15,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(Color(0xFFFBBF24)),
          ),
        ),
        label: 'Trying to reconnect…',
      );
    } else if (showReconnected) {
      pill = _pill(
        key: const ValueKey('reconnected'),
        bg: const Color(0xFF15803D),
        leading: const Icon(Icons.wifi_rounded, size: 16, color: Colors.white),
        label: 'Reconnected',
      );
    }

    // ── Placement ─────────────────────────────────────────────────────────
    // TOP centre, not bottom. The bottom edge is the busiest part of a phone
    // browser — Safari's tab bar and Chrome Android's URL bar both live there,
    // and the citizen shell puts its own navigation there too — so a pill
    // anchored to it competed with chrome the app does not control. The top
    // edge is quiet on every surface this wrapper covers.
    //
    // ── Responsive ────────────────────────────────────────────────────────
    // The pill used to sit at a flat offset with no side padding and no width
    // limit, which on a phone meant it could run edge to edge, and on a
    // desktop monitor that it could stretch.
    //
    // A phone gets more clearance because that is where the browser's own
    // top chrome sits. `MediaQuery.sizeOf` rebuilds only on a size change,
    // not on every MediaQuery field.
    final width = MediaQuery.sizeOf(context).width;
    final isPhone = width < 600;

    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.only(
          top: isPhone ? 20 : 24,
          left: 16,
          right: 16,
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          reverseDuration: const Duration(milliseconds: 250),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              // Drops DOWN into place from above. The offset is negative to
              // match the move to the top edge: the old +0.4 slid the pill up
              // from below, which against a top anchor would have read as the
              // pill rising out of the page rather than descending into it.
              position: Tween<Offset>(
                begin: const Offset(0, -0.4),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
              child: child,
            ),
          ),
          child: pill ?? const SizedBox.shrink(key: ValueKey('none')),
        ),
      ),
    );
  }

  Widget _pill({
    required Key key,
    required Color bg,
    required Widget leading,
    required String label,
  }) {
    return Material(
      key: key,
      color: Colors.transparent,
      child: ConstrainedBox(
        // A ceiling so the pill never stretches across a desktop monitor, and
        // — with the gutters applied by the caller — never reaches the edge of
        // a phone. The Row below is still mainAxisSize.min, so a short label
        // stays a small pill; this only caps the maximum.
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.20),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              leading,
              const SizedBox(width: 10),
              // Flexible, not a bare Text: at the 420 ceiling — or inside the
              // gutters on a very narrow phone — an unbounded Text would
              // overflow the Row and stripe the pill. Ellipsis is the right
              // failure here; the label is a status, not content to read.
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
