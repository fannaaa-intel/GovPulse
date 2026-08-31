// Preview target: the work-log composer's field/send-button alignment, across
// the widths it actually has to hold — a wide admin pane down to a narrow
// staff column on a phone.
//
//   flutter run -d web-server --web-port 57931 -t tool/preview_work_log_composer.dart
//
// The real ReportWorkLog talks to Supabase in initState, so this rebuilds the
// composer's geometry from the same constants rather than mounting it. What is
// being checked here is alignment, which is pure layout.
//
// Rendered side by side rather than one width at a time: the 2px error this
// was written to catch is far easier to see when a correct edge sits next to a
// suspect one. Query params: ?lines=1..4 to grow the field, ?sending=1 for the
// in-flight state.
import 'package:flutter/material.dart';

const double kComposerFieldHeight = 40;
const Color kAccent = Color(0xFF1D4ED8);

void main() {
  final q = Uri.base.queryParameters;
  final lines = int.tryParse(q['lines'] ?? '1')?.clamp(1, 4) ?? 1;
  final sending = q['sending'] == '1';
  runApp(_App(lines: lines, sending: sending));
}

class _App extends StatelessWidget {
  final int lines;
  final bool sending;
  const _App({required this.lines, required this.sending});

  @override
  Widget build(BuildContext context) {
    // The widths that matter: a wide admin detail pane, the two-pane breakpoint,
    // a narrow staff column, and a phone.
    const widths = [520.0, 420.0, 340.0, 280.0];

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFEEF1F6),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Work-log composer — lines=$lines  sending=$sending',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                const Text(
                  'The field bottom and the send-button bottom must sit on one '
                  'line at every width and every line count.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 20,
                  runSpacing: 20,
                  children: [
                    for (final w in widths)
                      _Pane(
                        width: w,
                        lines: lines,
                        sending: sending,
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

class _Pane extends StatelessWidget {
  final double width;
  final int lines;
  final bool sending;
  const _Pane({
    required this.width,
    required this.lines,
    required this.sending,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${width.toInt()}px',
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: Colors.black54)),
        const SizedBox(height: 6),
        Container(
          width: width,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE3E8EF)),
          ),
          child: Stack(
            children: [
              _composer(),
              // A hairline on the composer's baseline. If the button's bottom
              // edge does not sit exactly on it, the misalignment is obvious
              // rather than a matter of opinion.
              Positioned.fill(
                child: IgnorePointer(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(height: 1, color: Colors.red.withValues(alpha: 0.55)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _composer() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: TextEditingController(
              text: lines == 1 ? '' : List.filled(lines, 'Sample note').join('\n'),
            ),
            minLines: 1,
            maxLines: 4,
            maxLength: 500,
            style: const TextStyle(fontSize: 13.5, color: Color(0xFF1F2937)),
            decoration: InputDecoration(
              isDense: true,
              counterText: '',
              hintText: 'Add a note…',
              hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
              filled: true,
              fillColor: const Color(0xFFF4F6FB),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFCBD3DF)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFCBD3DF)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: kComposerFieldHeight,
          height: kComposerFieldHeight,
          child: Material(
            color: kAccent,
            borderRadius: BorderRadius.circular(11),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {},
              child: Center(
                child: sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded,
                        size: 18, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
