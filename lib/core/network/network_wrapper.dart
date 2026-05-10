import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'connectivity_service.dart';
import 'no_internet_screen.dart';

/// Cached internet status shared across all [NetworkWrapper] instances.
/// Set to null on cold start; updated on first check.
bool? cachedInternetStatus;

/// Wraps any screen with connectivity monitoring.
/// Shows [NoInternetScreen] as an overlay when the device goes offline.
class NetworkWrapper extends StatefulWidget {
  final Widget child;
  const NetworkWrapper({super.key, required this.child});

  @override
  State<NetworkWrapper> createState() => _NetworkWrapperState();
}

class _NetworkWrapperState extends State<NetworkWrapper> {
  bool? _hasInternet;
  late StreamSubscription _subscription;
  Timer? _offlineDebounce;
  Timer? _onlineDebounce;

  @override
  void initState() {
    super.initState();

    // Use cached status immediately to avoid a blank-screen flash.
    if (cachedInternetStatus != null) {
      _hasInternet = cachedInternetStatus;
    } else {
      // First launch only — check after a short delay so the UI renders first.
      Future.delayed(const Duration(milliseconds: 300), _checkInternet);
    }

    _subscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) async {
      final hasConnection = !results.every((r) => r == ConnectivityResult.none);

      if (!hasConnection) {
        _onlineDebounce?.cancel();
        _offlineDebounce?.cancel();
        _offlineDebounce = Timer(const Duration(seconds: 5), () async {
          final reallyOffline = !(await hasRealInternet());
          if (mounted && reallyOffline) {
            cachedInternetStatus = false;
            setState(() => _hasInternet = false);
          }
        });
      } else {
        _offlineDebounce?.cancel();
        _onlineDebounce?.cancel();
        _onlineDebounce = Timer(const Duration(seconds: 2), () async {
          final reallyOnline = await hasRealInternet();
          if (mounted && reallyOnline) {
            cachedInternetStatus = true;
            setState(() => _hasInternet = true);
          }
        });
      }
    });
  }

  Future<void> _checkInternet() async {
    final result = await hasRealInternet();
    cachedInternetStatus = result;
    if (mounted) setState(() => _hasInternet = result);
  }

  @override
  void dispose() {
    _offlineDebounce?.cancel();
    _onlineDebounce?.cancel();
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Always render the child immediately — no blank screen while checking.
    // NoInternetScreen overlay is only shown once status is confirmed.
    return Stack(
      children: [
        widget.child,
        if (_hasInternet != null)
          NoInternetScreen(
            hasInternet: _hasInternet!,
            onContinue: () {
              cachedInternetStatus = true;
              setState(() => _hasInternet = true);
            },
          ),
      ],
    );
  }
}
