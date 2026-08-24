// Dev-only harness for the ACCOUNT header's back control at five content
// widths.
//
//   flutter build web --release -t tool/preview_account_back_link.dart
//
// AccountPageTitle picks its shape from the box it is GIVEN, not from the
// window, so the way to see both shapes is to hand it boxes — which is what
// these frames are. Each one is a content box of the stated width, holding the
// header exactly as the report detail builds it (title, subtitle, a pill row
// under AccountHeaderIndent) over a card, so the left edges can be compared.
//
//   730  what the shell actually hands a detail page on a desktop: the 760
//        content cap less the page's own padding. Labelled.
//   600  a medium window. Labelled.
//   560  kAccountBackLabelAbove exactly — the first labelled width.
//   540  just under it: the compact chevron, level with the title.
//   420  a phone-width pane. Compact.
//
// Nothing here signs in or fetches: the header is a pure widget.

import 'package:flutter/material.dart';

import 'package:govpulse/core/theme/citizen_ui.dart';
import 'package:govpulse/core/widgets/Home/Account/account_web_kit.dart';

void main() => runApp(const _PreviewApp());

Widget _pill(String text, Color fg, Color bg, Color border) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
  decoration: BoxDecoration(
    color: bg,
    borderRadius: BorderRadius.circular(999),
    border: Border.all(color: border),
  ),
  child: Text(
    text,
    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg),
  ),
);

class _Frame extends StatelessWidget {
  final double width;
  const _Frame({required this.width});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 4),
          child: Text(
            'content ${width.toStringAsFixed(0)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Container(
          width: width,
          color: CitizenUi.pageBg,
          padding: const EdgeInsets.fromLTRB(0, 24, 0, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AccountPageTitle(
                title: 'Environment & Pollution',
                subtitle: 'Report details · RPT-0CA73FC3',
                onBack: () {},
                backLabel: 'Back to My Reports',
              ),
              AccountHeaderIndent(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _pill(
                      'Pending',
                      Colors.white,
                      CitizenUi.warn,
                      CitizenUi.warn,
                    ),
                    _pill(
                      'Copy ID',
                      CitizenUi.textMuted,
                      CitizenUi.surface,
                      CitizenUi.border,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // The card is the point of comparison: the header's left edge
              // should meet it.
              const AccountCard(
                child: SizedBox(
                  height: 96,
                  width: double.infinity,
                  child: Center(
                    child: Text(
                      'card below the header',
                      style: TextStyle(color: CitizenUi.textMuted),
                    ),
                  ),
                ),
              ),
            ],
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
              _Frame(width: 730),
              SizedBox(width: 24),
              _Frame(width: 600),
              SizedBox(width: 24),
              _Frame(width: 560),
              SizedBox(width: 24),
              _Frame(width: 540),
              SizedBox(width: 24),
              _Frame(width: 420),
            ],
          ),
        ),
      ),
    );
  }
}
