// Preview target: the internal-notes thread as it now renders — chat-shaped
// bubbles, day separators, and a composer pinned to the pane floor — at the
// three widths the two consoles actually seat it in.
//
//   flutter run -d web-server --web-port 57932 -t tool/preview_work_log_thread.dart
//
// ── WHY THIS FILE EXISTS ────────────────────────────────────────────────────
// The real ReportWorkLog hits Supabase in initState, so it cannot be mounted
// in a preview or a widget test without a live session. What is being checked
// here is pure layout — which side a bubble sits on, whether the composer
// holds the floor as the thread grows, whether a long note still leaves a
// margin at 320px — so the thread's geometry is rebuilt from the same values
// the widget uses.
//
// Kept deliberately close to the real _bubble(): if that changes shape, this
// should be changed with it, or it stops being evidence.
//
// Query params:
//   ?role=admin|staff   which console is holding it — flips which side is
//                       "mine", the thing most easily got wrong
//   ?notes=0..N         how many notes, to see an empty thread, a short one,
//                       and one long enough to scroll
//   ?locked=1           closed report: the composer goes, the record stays
import 'package:flutter/material.dart';

const Color kAdmin = Color(0xFF0D47A1);
const Color kStaff = Color(0xFF0EA5A4);
const double kBubbleMaxWidth = 0.78;
const double kComposerFieldHeight = 44;
const double kComposerSendSize = 32;
const double kComposerShellPad = 5;
const double kComposerRadius = 12;
const double kComposerSendRadius = 9;

void main() {
  final q = Uri.base.queryParameters;
  runApp(
    _App(
      role: q['role'] == 'staff' ? 'staff' : 'admin',
      count: int.tryParse(q['notes'] ?? '6')?.clamp(0, 40) ?? 6,
      locked: q['locked'] == '1',
    ),
  );
}

class _Note {
  final String role;
  final String name;
  final String body;
  final DateTime at;
  const _Note(this.role, this.name, this.body, this.at);
}

List<_Note> _sample(int n) {
  final now = DateTime.now();
  final base = <_Note>[
    _Note('staff', 'Engineering Office',
        'Crew dispatched this morning. Blockage cleared at the Rizal St. outfall.',
        now.subtract(const Duration(days: 2, hours: 5))),
    _Note('admin', 'LGU Admin',
        'Noted. Please attach photos before you mark it done.',
        now.subtract(const Duration(days: 2, hours: 3))),
    _Note('staff', 'Engineering Office',
        'Understood — the crew is back out tomorrow with a camera.',
        now.subtract(const Duration(days: 1, hours: 7))),
    _Note('admin', 'LGU Admin', 'Thanks.',
        now.subtract(const Duration(days: 1, hours: 6))),
    _Note('staff', 'Engineering Office',
        'Photos uploaded. Requesting closure.',
        now.subtract(const Duration(hours: 4))),
    _Note('admin', 'LGU Admin',
        'Received — reviewing them now. If the second one shows the far end '
        'of the culvert as well, this can close today.',
        now.subtract(const Duration(hours: 1))),
  ];
  if (n <= base.length) return base.take(n).toList();
  // Pad with alternating traffic so the thread is long enough to scroll.
  final out = [...base];
  for (var i = base.length; i < n; i++) {
    final mine = i.isEven;
    out.add(_Note(
      mine ? 'staff' : 'admin',
      mine ? 'Engineering Office' : 'LGU Admin',
      'Follow-up note #$i on this report.',
      now.subtract(Duration(minutes: (n - i) * 7)),
    ));
  }
  return out;
}

class _App extends StatelessWidget {
  final String role;
  final int count;
  final bool locked;
  const _App({required this.role, required this.count, required this.locked});

  @override
  Widget build(BuildContext context) {
    // The widths the thread is actually given: a wide admin pane at the
    // desktop two-pane split, the narrow single-pane fallback, and a phone.
    const widths = [560.0, 420.0, 320.0];
    final notes = _sample(count);

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
                  'Internal notes — held by ${role == 'admin' ? 'LGU Admin' : 'Engineering Office'}'
                  '${locked ? '  ·  report closed' : ''}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Filled bubbles are "mine". The composer must stay on the '
                  'floor at every width and every thread length.',
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
                        role: role,
                        notes: notes,
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

/// A stand-in for DetailPane(fill: true) holding the thread.
class _PaneMock extends StatelessWidget {
  final double width;
  final String role;
  final List<_Note> notes;
  final bool locked;
  const _PaneMock({
    required this.width,
    required this.role,
    required this.notes,
    required this.locked,
  });

  @override
  Widget build(BuildContext context) {
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
          // A real pane inside the dialog gets roughly this once the title and
          // tab bar are taken off a 900px dialog.
          height: 560,
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
              const Text(
                'Between the admin and the owning office only. The citizen '
                'never sees these.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: Color(0xFF8A94A6),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: notes.isEmpty
                    ? const Align(
                        alignment: Alignment.topLeft,
                        child: Text(
                          'No notes yet. Post progress updates or instructions '
                          'here — the citizen never sees these.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF8A94A6),
                            height: 1.4,
                          ),
                        ),
                      )
                    : ScrollConfiguration(
                        behavior: const _NoBars(),
                        child: ListView(
                          padding: const EdgeInsets.only(bottom: 4),
                          children: _threadChildren(notes, role),
                        ),
                      ),
              ),
              if (!locked) ...[
                const SizedBox(height: 10),
                const _ComposerMock(),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _NoBars extends MaterialScrollBehavior {
  const _NoBars();
  @override
  Widget buildScrollbar(BuildContext c, Widget child, ScrollableDetails d) =>
      child;
}

List<Widget> _threadChildren(List<_Note> notes, String role) {
  final out = <Widget>[];
  DateTime? lastDay;
  for (final n in notes) {
    final day = DateTime(n.at.year, n.at.month, n.at.day);
    if (lastDay == null || day != lastDay) {
      out.add(_daySeparator(day));
      lastDay = day;
    }
    out.add(_bubble(n, role));
  }
  return out;
}

Widget _daySeparator(DateTime day) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  final label = diff == 0
      ? 'Today'
      : diff == 1
          ? 'Yesterday'
          : '${day.day}/${day.month}/${day.year}';
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        const Expanded(child: Divider(height: 1, color: Color(0xFFE1E7F0))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: Color(0xFF9CA3AF),
            ),
          ),
        ),
        const Expanded(child: Divider(height: 1, color: Color(0xFFE1E7F0))),
      ],
    ),
  );
}

Widget _bubble(_Note n, String viewerRole) {
  final mine = n.role == viewerRole;
  final isAdmin = n.role == 'admin';
  final accent = isAdmin ? kAdmin : kStaff;
  return Align(
    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
    child: FractionallySizedBox(
      widthFactor: kBubbleMaxWidth,
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 3, right: 3, bottom: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isAdmin ? Icons.shield_rounded : Icons.engineering_rounded,
                  size: 11,
                  color: accent,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    n.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _ago(n.at),
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.only(bottom: 9),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: mine ? accent : const Color(0xFFF6F8FC),
              border: mine ? null : Border.all(color: const Color(0xFFE1E7F0)),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(13),
                topRight: const Radius.circular(13),
                bottomLeft: Radius.circular(mine ? 13 : 4),
                bottomRight: Radius.circular(mine ? 4 : 13),
              ),
            ),
            child: Text(
              n.body,
              style: TextStyle(
                fontSize: 13,
                color: mine ? Colors.white : const Color(0xFF1F2937),
                height: 1.42,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  if (d.inDays < 7) return '${d.inDays}d';
  return '${t.day}/${t.month}/${t.year}';
}

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
                          color: i == 2 ? kAdmin : Colors.transparent,
                        ),
                      ),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: i == 2
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

class _ComposerMock extends StatelessWidget {
  const _ComposerMock();
  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: kComposerFieldHeight),
      padding: const EdgeInsets.all(kComposerShellPad),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6FB),
        borderRadius: BorderRadius.circular(kComposerRadius),
        border: Border.all(color: const Color(0xFFCBD3DF)),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 7),
              child: Text(
                'Add a note…',
                style: TextStyle(fontSize: 13.5, color: Color(0xFF9CA3AF)),
              ),
            ),
          ),
          Container(
            width: kComposerSendSize,
            height: kComposerSendSize,
            decoration: BoxDecoration(
              color: kAdmin.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(kComposerSendRadius),
            ),
            child: const Icon(Icons.send_rounded, size: 16, color: kAdmin),
          ),
        ],
      ),
    );
  }
}
