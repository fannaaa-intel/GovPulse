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

bool? cachedInternetStatus;

class NetworkWrapper extends ConsumerStatefulWidget {
  final Widget child;
  const NetworkWrapper({super.key, required this.child});

  @override
  ConsumerState<NetworkWrapper> createState() => _NetworkWrapperState();
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
        if (!online && !_webOffline) {
          _reconnectedTimer?.cancel();
          setState(() {
            _webOffline = true;
            _showReconnected = false;
          });
        } else if (online && _webOffline) {
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Web: keep the page fully usable; just float a reconnect / reconnected
    // toast at the bottom. No full-screen takeover.
    if (kIsWeb) {
      return Stack(
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

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          reverseDuration: const Duration(milliseconds: 250),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.4),
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
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
