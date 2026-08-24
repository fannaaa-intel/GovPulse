// Dev-only harness for the EMERGENCY page's web layout at four pane widths.
//
//   flutter build web --release -t tool/preview_emergency_web.dart
//
// EmergencyBody takes no identity and hits no network — every hotline it draws
// is static — so it renders standalone with no Supabase and no sign-in, and all
// four widths fit on ONE page side by side.
//
// The widths are the shapes the 911 band switches between (see
// _hero911CardWeb): 1032 is what the shell actually hands this page on an
// ordinary desktop (band + watermark), 900 the band without it, 700 the stacked
// shape a narrow window falls back to, and 560 the smallest pane the web shell
// will hand this page.
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
