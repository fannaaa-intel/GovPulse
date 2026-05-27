import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'connectivity_service.dart';
import 'no_internet_screen.dart';

bool? cachedInternetStatus;

class NetworkWrapper extends StatefulWidget {
  final Widget child;
  const NetworkWrapper({super.key, required this.child});

  @override
  State<NetworkWrapper> createState() => _NetworkWrapperState();
}

class _NetworkWrapperState extends State<NetworkWrapper> {
  bool? _hasInternet;
  StreamSubscription? _subscription;
  Timer? _offlineDebounce;
  Timer? _onlineDebounce;

  @override
  void initState() {
    super.initState();

    // Web: browser handles connectivity — always treat as online.
    if (kIsWeb) {
      _hasInternet = true;
      cachedInternetStatus = true;
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
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
