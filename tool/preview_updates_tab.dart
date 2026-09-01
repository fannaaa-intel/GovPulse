// Preview target: the Updates tab now that it fills the pane — a composer that
// keeps its natural height at the top, and a review queue that takes the rest
// and scrolls inside it.
//
//   flutter run -d web-server --web-port 57946 -t tool/preview_updates_tab.dart
//
// ── WHAT THIS IS CHECKING ───────────────────────────────────────────────────
// The failure mode this design exists to avoid is the composer eating the
// pane. ReportProgressUpdates' composer is a multi-line field, a kind picker,
// an optional staged-photo strip and two buttons — close to 300px before a
// single update is drawn. If the whole column were handed a fixed height and
// left to divide itself, the form would take most of it and the queue would
// get a sliver, which is the opposite of what a reviewer opens the tab for.
//
// So what to look at, at every width:
//   • the composer is fully visible and not compressed
//   • the queue below it scrolls, with no scrollbar drawn
//   • "Waiting for your decision" is above the fold, not below it
//   • at 320px the two composer buttons wrap rather than overflow
//
// The real widget hits Supabase in initState, so the layout is rebuilt from
// the same structure rather than mounted.
//
// Query params:
//   ?mode=reviewer|author   admin's review queue, or the office's composer
//   ?updates=0..N           how many updates, to see empty / short / scrolling
//   ?pending=N              how many of them are still awaiting a decision
//   ?locked=1               closed report: composer goes, history stays
import 'package:flutter/material.dart';

const Color kBlue = Color(0xFF0D47A1);
const Color kAmber = Color(0xFFB45309);

void main() {
  final q = Uri.base.queryParameters;
  runApp(
    _App(
      reviewer: q['mode'] != 'author',
      count: int.tryParse(q['updates'] ?? '5')?.clamp(0, 30) ?? 5,
      pending: int.tryParse(q['pending'] ?? '2')?.clamp(0, 30) ?? 2,
      locked: q['locked'] == '1',
    ),
  );
}

class _App extends StatelessWidget {
  final bool reviewer;
  final int count;
  final int pending;
  final bool locked;
  const _App({
    required this.reviewer,
    required this.count,
    required this.pending,
    required this.locked,
  });

  @override
  Widget build(BuildContext context) {
    const widths = [560.0, 420.0, 320.0];
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFEEF2F8),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Updates tab — ${reviewer ? 'LGU Admin (reviewer)' : 'Engineering Office (author)'}'
                  '${locked ? '  ·  report closed' : ''}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'The composer keeps its height; only the queue below it '
                  'scrolls. No scrollbar should be drawn.',
                  style: TextStyle(fontSize: 12.5, color: Color(0xFF6B7280)),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 18,
                  runSpacing: 18,
                  children: [
                    for (final w in widths)
                      _PaneMock(
                        width: w,
                        reviewer: reviewer,
                        count: count,
                        pending: pending,
                        locked: locked,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoBars extends MaterialScrollBehavior {
  const _NoBars();
  @override
  Widget buildScrollbar(BuildContext c, Widget child, ScrollableDetails d) =>
      child;
}

class _PaneMock extends StatelessWidget {
  final double width;
  final bool reviewer;
  final int count;
  final int pending;
  final bool locked;
  const _PaneMock({
    required this.width,
    required this.reviewer,
    required this.count,
    required this.pending,
    required this.locked,
  });

  @override
  Widget build(BuildContext context) {
    final pendingCount = pending.clamp(0, count);
    final decidedCount = count - pendingCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${width.toInt()}px',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF8A94A6),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: width,
          height: 620,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFCBD3DF)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Update Report Status',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 16),
              const _TabsMock(),
              const SizedBox(height: 16),
              // ── head: heading + composer, natural height ────────────────
              Row(
                children: [
                  const Icon(Icons.timeline_rounded, size: 18, color: kBlue),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Progress updates',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (!locked) ...[
                _ComposerMock(reviewer: reviewer),
                const SizedBox(height: 12),
              ],
              // ── list: takes the rest, scrolls, no bar ───────────────────
              Expanded(
                child: count == 0
                    ? const Align(
                        alignment: Alignment.topLeft,
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Text(
                            'No updates yet.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                      )
                    : ScrollConfiguration(
                        behavior: const _NoBars(),
                        child: ListView(
                          padding: const EdgeInsets.only(bottom: 4),
                          children: [
                            if (reviewer && pendingCount > 0) ...[
                              _sectionLabel(
                                'Waiting for your decision',
                                pendingCount,
                                kAmber,
                              ),
                              const SizedBox(height: 8),
                              for (var i = 0; i < pendingCount; i++)
                                _UpdateTile(index: i, pending: true,
                                    reviewer: reviewer),
                              if (decidedCount > 0) ...[
                                const SizedBox(height: 6),
                                _sectionLabel('Earlier updates', decidedCount,
                                    const Color(0xFF8A94A6)),
                                const SizedBox(height: 8),
                              ],
                            ],
                            for (var i = 0; i < decidedCount; i++)
                              _UpdateTile(
                                index: pendingCount + i,
                                pending: false,
                                reviewer: reviewer,
                              ),
                          ],
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

Widget _sectionLabel(String text, int count, Color color) => Row(
      children: [
        Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: color,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );

class _UpdateTile extends StatelessWidget {
  final int index;
  final bool pending;
  final bool reviewer;
  const _UpdateTile({
    required this.index,
    required this.pending,
    required this.reviewer,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
          color: pending ? kAmber.withValues(alpha: 0.35) : Colors.black12,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: (pending ? kAmber : kBlue).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  pending ? 'Pending' : 'Approved',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: pending ? kAmber : kBlue,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '${index + 1}d',
                style: const TextStyle(fontSize: 10.5, color: Colors.black45),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            index.isEven
                ? 'Crew completed the section fronting the lyceum. Debris '
                    'hauled out and the shoulder re-graded.'
                : 'Assessment done — the culvert needs a full clear, not a '
                    'patch. Scheduling a second visit.',
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: Color(0xFF1F2937),
            ),
          ),
          if (reviewer && pending) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MiniButton(label: 'Approve', filled: true),
                _MiniButton(label: 'Return', filled: false),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  final String label;
  final bool filled;
  const _MiniButton({required this.label, required this.filled});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 34),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: filled ? kBlue : Colors.transparent,
        border: filled ? null : Border.all(color: Colors.black26),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: filled ? Colors.white : const Color(0xFF3D4655),
        ),
      ),
    );
  }
}

/// The tall one — this is what must NOT be allowed to eat the pane.
class _ComposerMock extends StatelessWidget {
  final bool reviewer;
  const _ComposerMock({required this.reviewer});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 62,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F9FC),
            border: Border.all(color: Colors.black12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text(
            'What has happened since the last update?',
            style: TextStyle(fontSize: 13, color: Colors.black38),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _kindChip('Progress', true)),
            const SizedBox(width: 8),
            Expanded(child: _kindChip('Completion', false)),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'A routine update on work in progress.',
          style: TextStyle(fontSize: 11.5, color: Colors.black45),
        ),
        const SizedBox(height: 10),
        // Wrap, so at 320px these stack instead of overflowing.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              decoration: BoxDecoration(
                border: Border.all(color: kBlue.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_photo_alternate_outlined,
                      size: 17, color: kBlue),
                  SizedBox(width: 7),
                  Text('Add photos',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: kBlue)),
                ],
              ),
            ),
            Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              decoration: BoxDecoration(
                color: kBlue,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.send_rounded, size: 16, color: Colors.white),
                  const SizedBox(width: 7),
                  Text(
                    reviewer ? 'Post update' : 'Submit for approval',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

Widget _kindChip(String label, bool on) => Container(
      constraints: const BoxConstraints(minHeight: 40),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: on ? kBlue.withValues(alpha: 0.07) : Colors.white,
        border: Border.all(color: on ? kBlue : Colors.black12),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: on ? kBlue : const Color(0xFF6B7280),
        ),
      ),
    );

class _TabsMock extends StatelessWidget {
  const _TabsMock();
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: Stack(
        children: [
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Divider(height: 1, color: Color(0xFFCBD3DF)),
          ),
          Row(
            children: [
              for (final (i, label) in [
                'Timeline',
                'Updates',
                'Internal notes',
              ].indexed)
                Padding(
                  padding: const EdgeInsets.only(right: 18),
                  child: Container(
                    padding: const EdgeInsets.only(bottom: 7),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          width: 2,
                          color: i == 1 ? kBlue : Colors.transparent,
                        ),
                      ),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: i == 1
                            ? const Color(0xFF111827)
                            : const Color(0xFF8A94A6),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
