// Dev-only harness for the WEB offline toast.
//
//   flutter build web --release -t tool/preview_offline_toast.dart
//   (then serve build/web and drive it with CDP)
//
// ── Why this target exists ──────────────────────────────────────────────────
// The toast lives behind [NetworkWrapper]'s `if (kIsWeb)` branch, and that
// branch is UNREACHABLE from `flutter test`: kIsWeb is a compile-time false in
// the test VM, so the wrapper always takes its mobile full-screen path there.
// `--platform chrome` does not work in this checkout either (a trivial browser
// test fails with "Connection closed before test suite loaded"), so a real
// build loaded in a real browser is the ONLY way to see this code run.
//
// ── What it is meant to show ────────────────────────────────────────────────
// Two claims about the hoist, neither of which was verified by execution:
//
//   1. ONE wrapper paints ONE pill.
//   2. A NESTED wrapper — the shape the hoist creates, since the root
//      `GovPulseWebApp.builder` now wraps routes that carry their own wrapper
//      for the legacy mobile router — paints ONE pill, not two stacked at the
//      same bottom-centre position.
//
// Both frames are driven OFFLINE by Chrome DevTools' `Network.emulateNetworkConditions`
// (offline: true), which is what fires the browser online/offline event that
// connectivity_plus listens to on web.
//
// The frames are side by side and each is a fixed box, so a doubled pill is
// visible as a darker, heavier-shadowed pill in the right frame than the left.
// To make that difference unmissable the frames are also labelled with a live
// count of how many toast layers each subtree actually mounted — see
// [_ToastCounter], which does not depend on reading pixels.

import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:govpulse/core/network/network_wrapper.dart';
import 'package:govpulse/core/network/web_reachability.dart';

void main() {
  // ── Frame C: the captive-portal case ──────────────────────────────────────
  // The whole point of [WebReachability] is the situation navigator.onLine gets
  // WRONG: the browser still reports online, so nothing in frames A or B would
  // ever raise a pill, yet no request reaches the backend.
  //
  // Driving that from CDP is not possible — Chrome's offline emulation flips
  // navigator.onLine too, which is the very signal this is meant to bypass. So
  // the probe itself is overridden to fail while the browser stays online,
  // which is exactly what a captive portal looks like from inside the app.
  //
  // `window.__probeFails` is read on EVERY probe, so the CDP driver can flip it
  // at runtime and watch the pill appear and then clear.
  WebReachability.instance.configure(
    supabaseUrl: 'https://example.invalid',
    anonKey: 'preview',
  );
  WebReachability.instance.debugProbeOverride = (uri, headers) async {
    final fails = _probeFailsFlag();
    return !fails;
  };

  runApp(const ProviderScope(child: _PreviewApp()));
}

@JS('window.__probeFails')
external JSAny? _probeFailsRaw;

/// Reads `window.__probeFails`, which the CDP driver flips at runtime.
///
/// Undefined until the driver sets it, so absence must read as "probe
/// succeeds" — otherwise frame C would start failing before it is asked to.
bool _probeFailsFlag() {
  final raw = _probeFailsRaw;
  if (raw == null) return false;
  return raw.dartify() == true;
}

/// Stand-in for a real page, so the pill has something to float over.
class _Page extends StatelessWidget {
  final String label;
  const _Page({required this.label});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF1F5F9),
      child: Center(
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Color(0xFF334155),
          ),
        ),
      ),
    );
  }
}

class _Frame extends StatelessWidget {
  final String title;
  final String note;
  final Widget child;
  const _Frame({required this.title, required this.note, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          note,
          style: const TextStyle(color: Colors.white70, fontSize: 11.5),
        ),
        const SizedBox(height: 8),
        // Fixed-size frames so the two are directly comparable, plus a live
        // count of the toast layers each subtree actually mounted.
        _ToastCounter(child: ClipRect(child: child)),
      ],
    );
  }
}

/// Counts the toast layers actually mounted inside [child] and prints the
/// number under the frame.
///
/// Comparing pixels is weak evidence here: two identical pills drawn exactly on
/// top of each other differ from one pill only by shadow density, which is
/// exactly the kind of difference a screenshot invites you to talk yourself
/// into seeing either way. Walking the element tree and counting the real
/// widgets is unambiguous — 1 or 2, no interpretation.
///
/// [NetworkWrapper]'s toast layer is its `IgnorePointer` wrapping the toast, so
/// that pair is what gets counted. Counted after layout via a post-frame
/// callback, because the subtree does not exist during this widget's build.
class _ToastCounter extends StatefulWidget {
  final Widget child;
  const _ToastCounter({required this.child});

  @override
  State<_ToastCounter> createState() => _ToastCounterState();
}

class _ToastCounterState extends State<_ToastCounter> {
  final GlobalKey _key = GlobalKey();
  int? _count;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(_ToastCounter oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedule();
  }

  void _schedule() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _key.currentContext;
      if (ctx == null || !mounted) return;
      var n = 0;
      void visit(Element el) {
        // Count the wrapper's toast LAYER. An earlier version of this matched
        // `IgnorePointer` whose direct child is an `Align` — which never
        // matched anything, because the IgnorePointer's child is the
        // _ConnectivityToast WIDGET and the Align only appears inside that
        // widget's own build. The counter therefore read 0 and printed FAIL
        // while the screenshot plainly showed one correct pill in each frame.
        //
        // Matching on the runtime type NAME keeps this working without making
        // the private toast class visible outside its library.
        if (el.widget.runtimeType.toString() == '_ConnectivityToast') n++;
        el.visitChildren(visit);
      }

      ctx.visitChildElements(visit);
      if (n != _count) setState(() => _count = n);
    });
  }

  @override
  Widget build(BuildContext context) {
    final n = _count;
    final ok = n == 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(key: _key, width: 420, height: 460, child: widget.child),
        const SizedBox(height: 6),
        Text(
          n == null
              ? 'toast layers: counting…'
              : 'toast layers mounted: $n  ${ok ? "✓ PASS" : "✗ FAIL (want 1)"}',
          style: TextStyle(
            color: n == null
                ? Colors.white54
                : (ok ? const Color(0xFF4ADE80) : const Color(0xFFF87171)),
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Web offline toast — go offline in DevTools to raise the pill',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Both frames must show EXACTLY ONE pill, and the two pills must '
                'look identical. A heavier/darker pill on the right means the '
                'nested wrapper is stacking a second copy.',
                style: TextStyle(color: Colors.white70, fontSize: 12.5),
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 28,
                runSpacing: 28,
                children: [
                  _Frame(
                    title: 'A · single wrapper',
                    note: 'the baseline — one NetworkWrapper',
                    child: NetworkWrapper(
                      child: _Page(label: 'single wrapper\n(expect 1 pill)'),
                    ),
                  ),
                  _Frame(
                    title: 'B · nested wrapper (the hoist shape)',
                    note: 'root builder + a route that carries its own wrapper',
                    child: NetworkWrapper(
                      child: NetworkWrapper(
                        child: _Page(label: 'nested wrapper\n(expect 1 pill)'),
                      ),
                    ),
                  ),
                  _Frame(
                    title: 'C · captive portal',
                    note: 'browser says ONLINE, backend unreachable',
                    child: NetworkWrapper(
                      child: _Page(
                        label: 'captive portal\n'
                            '(pill only after __probeFails = true)',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
