// Preview target: the internal-notes composer — admin console and staff.
//
//   flutter run -d chrome -t tool/preview_note_composer.dart
//
// ── Why this file exists, and why it failed to do its job ──────────────────
// The complaint was "the input is small, the button is big". Three passes
// answered it with alignment arithmetic — equal heights, a 1px ink inset, a
// 14 radius — when the bottoms were already 0.0px apart and always had been.
//
// This preview would have shown that immediately. It did not, because it had
// an unescaped apostrophe in a single-quoted string and had not compiled
// since it was written. It also hardcoded 0xFF1D4ED8 while the app's
// AppColors.primaryBlue is 0xFF0D47A1, so even had it run it would have been
// previewing the wrong blue.
//
// Both fixed. This now imports the REAL colour and mirrors the real
// constants, and it renders the OLD and NEW composers side by side, because
// the imbalance is only legible in comparison — a lone composer looks fine,
// which is how this survived three rounds.
import 'package:flutter/material.dart';

import 'package:govpulse/core/theme/app_colors.dart';

// Mirrors report_work_log.dart.
const double kShellMinHeight = 44;
const double kSendSize = 32;
const double kShellPad = 5;
const double kRadius = 12;
const double kSendRadius = 9;
const Color kAccent = AppColors.primaryBlue;

void main() => runApp(const _App());

class _App extends StatelessWidget {
  const _App();

  @override
  Widget build(BuildContext context) {
    // A wide admin detail pane, the two-pane breakpoint, a narrow staff
    // column, and a small phone. The old layout got WORSE as this narrowed —
    // fixed button, Expanded field — so the 280 column is the one to read.
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
                  'BEFORE: a 44px slab of brand blue across an 8px gap from a '
                  'mostly-empty field. The gap is what let the eye compare '
                  'them as two objects of unequal size, and the button owned '
                  'more of the row the narrower the pane got.\n'
                  'AFTER: one control. The send button moved inside the '
                  "field's shell at 32px, so it is visibly the smaller half "
                  'of its own container and there is no gap left to read a '
                  'mismatch across.',
                  style: TextStyle(
                      fontSize: 12, color: Colors.black54, height: 1.5),
                ),
                const SizedBox(height: 24),
                for (final state in const [
                  ('Empty — the resting state', ''),
                  ('Typed — Send is live', 'Crew dispatched this morning.'),
                ]) ...[
                  _Label(state.$1),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 20,
                    runSpacing: 20,
                    children: [
                      for (final w in widths) _Pane(width: w, text: state.$2),
                    ],
                  ),
                  const SizedBox(height: 28),
                ],
                const _Label('Four lines — the shell grows as one object'),
                const SizedBox(height: 10),
                const _Pane(
                  width: 420,
                  text: 'Line one\nLine two\nLine three\nLine four',
                ),
                const SizedBox(height: 28),
                const _Label('Focused — the ring is on the shell now'),
                const SizedBox(height: 10),
                const _Pane(width: 420, text: 'Typing…', focused: true),
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

/// One card holding the OLD composer above the NEW one at the same width.
class _Pane extends StatelessWidget {
  final double width;
  final String text;
  final bool focused;
  const _Pane({required this.width, required this.text, this.focused = false});

  @override
  Widget build(BuildContext context) {
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
          const _Tag('BEFORE', Color(0xFFB91C1C)),
          const SizedBox(height: 6),
          _Old(text: text),
          const SizedBox(height: 16),
          const _Tag('AFTER', Color(0xFF15803D)),
          const SizedBox(height: 6),
          _New(text: text, focused: focused),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  const _Tag(this.text, this.color);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: color,
        ),
      );
}

/// The composer as it was: a field, an 8px gap, and a 44px square.
class _Old extends StatelessWidget {
  final String text;
  const _Old({required this.text});

  @override
  Widget build(BuildContext context) {
    final hasText = text.trim().isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: TextEditingController(text: text),
            minLines: 1,
            maxLines: 4,
            style: const TextStyle(fontSize: 13.5, color: Color(0xFF1F2937)),
            decoration: InputDecoration(
              isDense: true,
              counterText: '',
              hintText: 'Add a note…',
              hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
              filled: true,
              fillColor: const Color(0xFFF4F6FB),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
          width: 44,
          height: 44,
          child: Container(
            decoration: BoxDecoration(
              color: hasText ? kAccent : kAccent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
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
    );
  }
}

/// The composer as it is now: one shell holding both halves.
class _New extends StatelessWidget {
  final String text;
  final bool focused;
  const _New({required this.text, required this.focused});

  @override
  Widget build(BuildContext context) {
    final hasText = text.trim().isNotEmpty;
    return Container(
      constraints: const BoxConstraints(minHeight: kShellMinHeight),
      padding: const EdgeInsets.all(kShellPad),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6FB),
        borderRadius: BorderRadius.circular(kRadius),
        border: Border.all(
          color: focused ? kAccent : const Color(0xFFCBD3DF),
          width: focused ? 1.5 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: TextField(
                controller: TextEditingController(text: text),
                minLines: 1,
                maxLines: 4,
                style: const TextStyle(
                    fontSize: 13.5, color: Color(0xFF1F2937), height: 1.35),
                decoration: const InputDecoration(
                  isDense: true,
                  counterText: '',
                  hintText: 'Add a note…',
                  hintStyle:
                      TextStyle(fontSize: 13.5, color: Color(0xFF9CA3AF)),
                  filled: false,
                  isCollapsed: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 6),
                ),
              ),
            ),
          ),
          SizedBox(
            width: kSendSize,
            height: kSendSize,
            child: Container(
              decoration: BoxDecoration(
                color: hasText ? kAccent : kAccent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(kSendRadius),
              ),
              child: Center(
                child: Icon(
                  Icons.send_rounded,
                  size: 16,
                  color: hasText ? Colors.white : kAccent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
