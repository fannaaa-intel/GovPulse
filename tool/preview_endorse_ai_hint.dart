// Preview target: the Endorse dialog carrying the AI agency hint.
//
//   flutter build web --release -t tool/preview_endorse_ai_hint.dart
//
// ai_endorse_hint has been written on every classified report since migration
// 20260914000000 and was surfaced NOWHERE. This is the first UI that reads it,
// so there is no prior art to compare against — only looking will do.
//
// The specific risk being checked: the Accept & Assign dialog had this exact
// bug, where an "AI Recommended" pill positioned at the card's top edge landed
// ON the office illustration. The automated overflow probe passed the whole
// time, because a Positioned child overlapping its Stack sibling is legal
// layout — just an ugly one. This dialog's COMPACT card centres a 52px logo at
// the very top, which is why the pill here sits inline beside the category tag
// instead of in a corner. These frames are how that choice gets verified.
//
// Frames, chosen so each one exercises a different branch:
//   • desktop, AI hint      — roomy 2-column card, pill beside a long tag
//   • desktop, no hint      — the unchanged dialog; must look untouched
//   • phone, AI hint        — compact card, where the logo collision would be
//   • phone, longest tag    — DENR ("Environment & Sustainability") + pill,
//                             the widest tag/pill pair in the roster
//
// ?w= renders a single frame at that width instead.
import 'package:flutter/material.dart';

import 'package:govpulse/features/admin/widgets/endorse_entity_dialog.dart';

void main() {
  final w = double.tryParse(Uri.base.queryParameters['w'] ?? '');
  runApp(_App(single: w));
}

class _Case {
  final String label;
  final double width;
  final String? aiAgency;
  const _Case(this.label, this.width, {this.aiAgency});
}

const _cases = [
  _Case('desktop · AI hint (DPWH)', 900, aiAgency: 'DPWH'),
  _Case('desktop · no hint (unchanged)', 900),
  _Case('phone · AI hint (DPWH)', 390, aiAgency: 'DPWH'),
  // DENR carries the longest tag in the roster; pairing it with the pill on the
  // narrowest card is the worst case for the Wrap.
  _Case('phone · longest tag (DENR)', 360, aiAgency: 'DENR'),
];

class _App extends StatelessWidget {
  final double? single;
  const _App({this.single});

  @override
  Widget build(BuildContext context) {
    final cases = single != null
        ? [_Case('w=$single', single!, aiAgency: 'DENR')]
        : _cases;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF2B2F3A),
        body: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final c in cases) ...[
                _Frame(spec: c),
                const SizedBox(width: 24),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Frame extends StatelessWidget {
  final _Case spec;
  const _Frame({required this.spec});

  @override
  Widget build(BuildContext context) {
    const height = 900.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: spec.width,
          child: Text(
            '${spec.width.toInt()} — ${spec.label}',
            style: const TextStyle(
                color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: spec.width,
          height: height,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(6)),
          // The dialog reads the viewport to choose full-screen vs modal, so
          // each frame declares its own rather than inheriting the browser's.
          child: MediaQuery(
            data: MediaQueryData(size: Size(spec.width, height)),
            // Nested Navigator: showDialog pushes a route, and without this it
            // would escape the simulated viewport and cover the whole page.
            child: Navigator(
              onGenerateRoute: (_) => MaterialPageRoute(
                builder: (ctx) => Stack(
                  children: [
                    Container(color: const Color(0xFFF1F4F9)),
                    _AutoOpen(spec: spec),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Opens the dialog through its real public entry point, so the preview
/// exercises the same code path the console does rather than a copy of it.
class _AutoOpen extends StatefulWidget {
  final _Case spec;
  const _AutoOpen({required this.spec});

  @override
  State<_AutoOpen> createState() => _AutoOpenState();
}

class _AutoOpenState extends State<_AutoOpen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showEndorseEntityDialog(
        context,
        aiSuggestedAgency: widget.spec.aiAgency,
      );
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
