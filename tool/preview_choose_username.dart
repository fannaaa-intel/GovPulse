// Dev-only harness for the username picker's WEB layouts.
//
//   flutter build web --release -t tool/preview_choose_username.dart
//
// The widget test sweep runs with kIsWeb == false, so it measures the MOBILE
// arm. This target is the only way to see the two web layouts the screen
// actually shows a citizen: the two-panel form above kWebTwoPanelMinWidth
// (1000px) and the compact one below it.
//
// Reaching the real thing would mean completing a Facebook OAuth round trip,
// so the screen is mounted directly with a representative name.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:govpulse/features/auth/facebook_username_screen.dart';

void main() => runApp(const ProviderScope(child: _PreviewApp()));

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'GovPulse — choose a username',
      home: FacebookUsernameScreen(
        facebookName: 'Juan Dela Cruz',
        onComplete: (picked) async {
          debugPrint('picked: $picked');
        },
        onCancel: () {
          debugPrint('cancelled');
        },
      ),
    );
  }
}
