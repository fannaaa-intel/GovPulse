// Preview target: the Accept & Assign dialog carrying an AI recommendation.
//
//   flutter build web --release -t tool/preview_accept_assign_ai.dart
//
// The automated half of this is test/ai_category_routing_test.dart, which
// proves nothing OVERFLOWS at eight phone sizes. That is not the same as the
// thing looking right: a badge can fit and still crowd the card's corner, and
// an amber notice can lay out cleanly and still read as an error rather than as
// information. See [[preview-target-before-reporting]].
//
// Four frames, side by side, because the interesting comparisons are between
// states rather than within one:
//   • AI + mis-filed notice   — the densest case, and the new UI
//   • AI, correctly filed     — badge only, no notice
//   • the deterministic rule  — what every unclassified report still shows
//   • phone width             — where the wider badge and the 2-up grid meet
//
// ?w= renders a single frame at that width instead.
import 'package:flutter/material.dart';

import 'package:govpulse/features/admin/widgets/accept_assign_dialog.dart';

void main() {
  final w = double.tryParse(Uri.base.queryParameters['w'] ?? '');
  runApp(_App(single: w));
}

class _Case {
  final String label;
  final double width;
  final bool isAi;
  final String? miscategorizedAs;
  final String? aiReason;
  const _Case(this.label, this.width,
      {required this.isAi, this.miscategorizedAs, this.aiReason});
}

const _cases = [
  _Case(
    'AI + mis-filed (desktop)',
    900,
    isAi: true,
    miscategorizedAs: 'Road & Infrastructure',
    aiReason: 'describes a collapsed bridge, not a general concern',
  ),
  _Case('AI, correctly filed (desktop)', 900, isAi: true),
  _Case('deterministic rule (desktop)', 900, isAi: false),
  _Case(
    'AI + mis-filed (phone)',
    390,
    isAi: true,
    miscategorizedAs: 'Road & Infrastructure',
    aiReason: 'describes a collapsed bridge, not a general concern',
  ),
];

class _App extends StatelessWidget {
  final double? single;
  const _App({this.single});

  @override
  Widget build(BuildContext context) {
    final cases = single != null
        ? [
            _Case('w=$single', single!,
                isAi: true,
                miscategorizedAs: 'Road & Infrastructure',
                aiReason: 'describes a collapsed bridge, not a general concern')
          ]
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
    const height = 860.0;
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
                    // Opened for real through the public entry point, so the
                    // preview exercises the same code path the console does.
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

/// Opens the dialog once on first frame and leaves it open. Re-opens if it is
/// dismissed, so the frame is never left empty during a screenshot pass.
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    if (!mounted) return;
    await showAcceptAssignDialog(
      context,
      recommendedOffice: 'Engineering Office',
      isAiRecommendation: widget.spec.isAi,
      miscategorizedAs: widget.spec.miscategorizedAs,
      aiReason: widget.spec.aiReason,
    );
    if (mounted) _open();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
