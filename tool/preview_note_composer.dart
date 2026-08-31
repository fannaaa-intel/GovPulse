// Preview target: the internal-notes composer — the field and its send button.
//
//   flutter run -d web-server --web-port 57951 -t tool/preview_note_composer.dart
//
// The complaint this exists to answer: "the input is thin and the send button
// is too big", seen in the admin and staff consoles. The two were always the
// same HEIGHT — that was measured and pinned long ago. What was wrong was
// WEIGHT: a pale outlined field beside a fully saturated square of brand blue,
// so the eye landed on Send rather than on the note being written.
//
// Both states are drawn at four widths, empty above and typed below, because
// the imbalance is only visible in comparison — a lone composer looks fine.
//
// The real ReportWorkLog talks to Supabase in initState, so this rebuilds the
// composer from the same constants. What is checked here is colour and
// proportion, which is pure layout.
import 'package:flutter/material.dart';

const double kComposerFieldHeight = 44;
const double kRadius = 12;
const Color kAccent = Color(0xFF1D4ED8);

void main() => runApp(const _App());

class _App extends StatelessWidget {
  const _App();

  @override
  Widget build(BuildContext context) {
    // A wide admin detail pane, the two-pane breakpoint, a narrow staff column,
    // and a phone.
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
                const Text(
                  'Internal notes composer',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                const Text(
                  'At rest the button is a TINT of the accent — Send is only '
                  'meaningful with something to send. With text it fills. Both '
                  'halves share radius 12 and height 44.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 22),
                const _Label('Empty — the resting state'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 20,
                  runSpacing: 20,
                  children: [
                    for (final w in widths) _Pane(width: w, text: ''),
                  ],
                ),
                const SizedBox(height: 28),
                const _Label('Typed — Send is live'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 20,
                  runSpacing: 20,
                  children: [
                    for (final w in widths)
                      _Pane(width: w, text: 'Crew dispatched this morning.'),
                  ],
                ),
                const SizedBox(height: 28),
                const _Label('Four lines — the bottoms still agree'),
                const SizedBox(height: 10),
                _Pane(
                  width: 420,
                  text: 'Line one\nLine two\nLine three\nLine four',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.7,
      color: Colors.black54,
    ),
  );
}

class _Pane extends StatelessWidget {
  final double width;
  final String text;
  const _Pane({required this.width, required this.text});

  @override
  Widget build(BuildContext context) {
    final hasText = text.trim().isNotEmpty;

    return Container(
      width: width,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${width.toInt()}px',
            style: const TextStyle(fontSize: 10.5, color: Colors.black38),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: TextEditingController(text: text),
                  minLines: 1,
                  maxLines: 4,
                  style: const TextStyle(
                      fontSize: 13.5, color: Color(0xFF1F2937)),
                  decoration: InputDecoration(
                    isDense: true,
                    counterText: '',
                    hintText: 'Add a note…',
                    hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                    filled: true,
                    fillColor: const Color(0xFFF4F6FB),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(kRadius),
                      borderSide: const BorderSide(color: Color(0xFFCBD3DF)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(kRadius),
                      borderSide: const BorderSide(color: Color(0xFFCBD3DF)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: kComposerFieldHeight,
                height: kComposerFieldHeight,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  decoration: BoxDecoration(
                    color: hasText
                        ? kAccent
                        : kAccent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(kRadius),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.send_rounded,
                      size: 19,
                      color: hasText ? Colors.white : kAccent,
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
