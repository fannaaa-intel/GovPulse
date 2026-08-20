// Dev-only preview harness for the emergency screen's dial paths.
//
// Not part of the app: nothing under lib/ imports it, and it is never a build
// target for a shipped bundle. It exists because the emergency screen's whole
// job — handing a number to the browser's dialer — is the one thing a widget
// test cannot observe. `kIsWeb` is a compile-time false in the VM, so the web
// branch of `_call` is unreachable from `flutter test`, and a headless Chrome
// has no dialer to hand the number to.
//
//   flutter run -d web-server --web-port 57811 -t tool/preview_emergency_dial.dart
//
// So the harness stubs the last step instead. It replaces
// `HTMLAnchorElement.prototype.click` with a recorder that pushes the anchor's
// href onto `window.__dialed` and swallows the navigation. Reading that list
// after a simulated drag proves three things at once: that the slider fires,
// that it fires with '911', and — because the recorder also stamps whether the
// browser still considered itself inside a user gesture — that it fires from
// somewhere Safari would have allowed.
//
// EmergencyBody is mounted bare. It takes no identity and reads no Supabase
// client; every hotline it renders is a const in the same file.

import 'dart:js_interop';

import 'package:flutter/material.dart';

import 'package:govpulse/features/home/emergency/emergency_screen.dart';

@JS('eval')
external JSAny? _jsEval(String code);

void main() {
  _installDialRecorder();
  runApp(const _PreviewApp());
}

/// Swaps the anchor click for a recorder, so a dial is observable and the
/// headless browser never tries to leave the page.
void _installDialRecorder() {
  _jsEval('''
    window.__dialed = [];
    const realClick = HTMLAnchorElement.prototype.click;
    HTMLAnchorElement.prototype.click = function () {
      if ((this.href || '').startsWith('tel:')) {
        window.__dialed.push({
          href: this.href,
          target: this.target,
          // navigator.userActivation.isActive is exactly the bit Safari's
          // popup blocker consults. False here means the real build would
          // have been blocked.
          activation: !!(navigator.userActivation &&
                         navigator.userActivation.isActive),
        });
        return;
      }
      return realClick.apply(this, arguments);
    };
  ''');
}

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Color(0xFFF6F7FB),
        body: SafeArea(child: EmergencyBody()),
      ),
    );
  }
}
