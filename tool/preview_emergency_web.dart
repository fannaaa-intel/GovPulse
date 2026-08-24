// Dev-only harness for the EMERGENCY page's web layout at four pane widths.
//
//   flutter build web --release -t tool/preview_emergency_web.dart
//
// EmergencyBody takes no identity and hits no network — every hotline it draws
// is static — so it renders standalone with no Supabase and no sign-in, and all
// four widths fit on ONE page side by side.
//
// The widths are PANES, not content. Since the page joined the citizen record
// band its content is min(pane, kAccountMaxWidth) - 2 * kAccountPageGutter, so
// a 1032 pane and a 900 pane now resolve to the same 816 and the same layout —
// which is the point of the band. 700 and 560 are below the cap, so they still
// exercise the shapes the 911 band and the service grid fall back to.
//
// The watermark is no longer reachable from this page: it needs 960 of content
// and the band tops out at 816. That is deliberate — see _hero911CardWeb.
//
// `canPlaceCalls` reads the WINDOW, not the frame, so on a desktop-sized
// browser window every frame here shows the copy control — which is the
// desktop case these frames are for. A phone browser is the app's own mobile
// layout and is not what this target checks.

import 'package:flutter/material.dart';

import 'package:govpulse/features/home/emergency/emergency_screen.dart';

void main() => runApp(const _PreviewApp());

class _Frame extends StatelessWidget {
  final double width;
  final double height;
  const _Frame({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 4),
          child: Text(
            'pane ${width.toStringAsFixed(0)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Container(
          width: width,
          height: height,
          color: const Color(0xFFF6F7FB),
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(size: Size(width, height)),
            child: const EmergencyBody(),
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
        backgroundColor: const Color(0xFF2B2F3A),
        body: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              _Frame(width: 1032, height: 820),
              SizedBox(width: 24),
              _Frame(width: 900, height: 820),
              SizedBox(width: 24),
              _Frame(width: 700, height: 820),
              SizedBox(width: 24),
              _Frame(width: 560, height: 820),
            ],
          ),
        ),
      ),
    );
  }
}
