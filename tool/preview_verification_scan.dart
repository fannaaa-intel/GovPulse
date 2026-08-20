// Dev-only preview harness for the web ID-scan screen's camera startup.
//
// Not part of the app: nothing under lib/ imports it, and it is never a build
// target for a shipped bundle. It exists because `VerificationScanScreen`'s
// web branches sit behind `kIsWeb`, a compile-time false in the VM, so
// `flutter test` never reaches the getUserMedia path at all.
//
//   flutter run -d web-server --web-port 57812 -t tool/preview_verification_scan.dart
//
// Drive it with a Chrome that has a fake camera:
//   --use-fake-device-for-media-stream --use-fake-ui-for-media-stream
//
// `window.__camlog` collects every camera-plugin milestone the screen hits, so
// a frozen spinner can be told apart from a refused device without reading the
// Dart console.
import 'dart:js_interop';

import 'package:flutter/material.dart';

import 'package:govpulse/features/profileVerification/verification_scan_screen.dart';

@JS('eval')
external JSAny? _jsEval(String code);

void main() {
  _installGumRecorder();
  runApp(const _PreviewApp());
}

/// Records every getUserMedia call, its outcome, and every track still live.
///
/// The browser's own "Using now" indicator is the thing being investigated:
/// a stream that was acquired and never stopped is exactly what keeps it lit
/// while the screen claims the camera could not be opened.
void _installGumRecorder() {
  _jsEval(r'''
    window.__camlog = [];
    window.__tracks = [];
    const md = navigator.mediaDevices;
    const realGum = md.getUserMedia.bind(md);
    md.getUserMedia = function (constraints) {
      window.__camlog.push({ ev: 'gum', constraints: JSON.stringify(constraints) });
      return realGum(constraints).then((stream) => {
        stream.getVideoTracks().forEach((t) => {
          window.__tracks.push(t);
          const realStop = t.stop.bind(t);
          t.stop = function () { window.__camlog.push({ ev: 'stop' }); return realStop(); };
        });
        window.__camlog.push({ ev: 'gum-ok', settings: JSON.stringify(stream.getVideoTracks()[0].getSettings()) });
        return stream;
      }).catch((e) => {
        window.__camlog.push({ ev: 'gum-fail', name: e.name, msg: String(e.message) });
        throw e;
      });
    };
    // How many camera tracks are still live — the "Using now" answer.
    window.__liveTracks = () => window.__tracks.filter((t) => t.readyState === 'live').length;
  ''');
}

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const VerificationScanScreen(
        username: 'preview',
        selectedId: 'PhilSys ID',
      ),
    );
  }
}
