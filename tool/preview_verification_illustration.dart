// Dev-only harness for the Profile Verification illustration at the widths
// both platforms actually hand it.
//
//   flutter build web --release -t tool/preview_verification_illustration.dart
//
// Two things are being checked here, and they pull against each other:
//
//   SIZE     The asset used to be a 500x500 canvas that was 36% transparent
//            padding, sized by height. At height:150 the FIGURE was ~96px and
//            read as an afterthought floating above the card. The asset is now
//            cropped to its artwork (393x329), so a height is the figure's
//            height and the same number draws it far larger.
//
//   SHARPNESS The artwork only exists at 329px tall - the source GIF is 500x500
//            with the same padding, so there is no higher-resolution original
//            to go back to. Past ~329 logical px the image is upscaled. Each
//            frame below prints the height it asked for so the point where
//            detail runs out can be judged by eye rather than by arithmetic.
//
// The top row is the real widget geometry. The bottom row is the OLD sizing
// (the same cropped asset drawn at the heights the screen used to pass) so the
// change is visible side by side rather than from memory.

import 'package:flutter/material.dart';

const String _asset = 'assets/images/verification/getverified.webp';

/// Mirrors the mobile screen's LayoutBuilder rule exactly.
double _mobileHeight(double contentWidth) =>
    (contentWidth * 0.44).clamp(150.0, 210.0);

class _Frame extends StatelessWidget {
  final String label;
  final double width;
  final double height;
  final Color bg;

  const _Frame({
    required this.label,
    required this.width,
    required this.height,
    this.bg = const Color(0xFFF3F4F6),
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 4),
          child: Text(
            '$label · box ${width.toStringAsFixed(0)} · '
            'h ${height.toStringAsFixed(0)}'
            '${height > 329 ? "  ⚠ upscaled" : ""}',
            style: TextStyle(
              color: height > 329 ? const Color(0xFFFFC46B) : Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Container(
          width: width,
          color: bg,
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: Image.asset(
              _asset,
              height: height,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
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
    // Content widths, not window widths: MobileFormShell and AccountPageBody
    // both cap and pad what the illustration is given.
    const double phoneSmall = 320; // smallest device still supported
    const double phoneTypical = 380;
    const double webStacked = 440; // narrow browser -> stack: true
    const double webWide = 824; // 880 cap less the page gutters

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF2B2F3A),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'NOW — cropped asset, new sizing',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Frame(
                      label: 'mobile 320',
                      width: phoneSmall,
                      height: _mobileHeight(phoneSmall),
                    ),
                    const SizedBox(width: 20),
                    _Frame(
                      label: 'mobile 380',
                      width: phoneTypical,
                      height: _mobileHeight(phoneTypical),
                    ),
                    const SizedBox(width: 20),
                    _Frame(
                      label: 'web stacked',
                      width: webStacked,
                      height: 190,
                      bg: Colors.white,
                    ),
                    const SizedBox(width: 20),
                    _Frame(
                      label: 'web wide',
                      width: webWide,
                      height: 240,
                      bg: Colors.white,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'BEFORE — same asset at the heights the screen used to pass',
                style: TextStyle(
                  color: Color(0xFF9BA3B4),
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Note: the old build ALSO padded the canvas, so the figure was '
                'a further 36% smaller than these show.',
                style: TextStyle(color: Color(0xFF9BA3B4), fontSize: 12),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    _Frame(label: 'mobile old', width: phoneTypical, height: 150),
                    SizedBox(width: 20),
                    _Frame(
                      label: 'web stacked old',
                      width: webStacked,
                      height: 150,
                      bg: Colors.white,
                    ),
                    SizedBox(width: 20),
                    _Frame(
                      label: 'web wide old',
                      width: webWide,
                      height: 180,
                      bg: Colors.white,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void main() => runApp(const _PreviewApp());
