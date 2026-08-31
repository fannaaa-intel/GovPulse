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

// ── This round: the text was not on the centre line ────────────────────────
// With the button inside the shell, the remaining complaint was the
// placeholder's vertical position. The field's content box was 30px against a
// 32px button, and CrossAxisAlignment.end put both missing pixels above the
// text — so the hint sat 2px low.
//
// 2px is under what anyone can point at in a screenshot and above what the eye
// notices as "off", which is exactly why it needed a guide rather than another
// screenshot. BEFORE and AFTER below are drawn over a red centre line so the
// gap is legible, and every pane is rendered at four text scales, because
// padding alone fixes 1.0 and then breaks 1.3.

// Mirrors report_work_log.dart.
const double kShellMinHeight = 44;
const double kSendSize = 32;
const double kShellPad = 5;
const double kFieldPad = 7; // was 6 — see report_work_log.dart
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
                  'The red hairline is the composer\'s true centre. BEFORE, '
                  'the placeholder sits below it — a 30px field bottom-aligned '
                  'against a 32px button drops the text by 2px. AFTER, the '
                  'field is padded to the button\'s own 32px and the row '
                  'centres while it is one line, so the text lands on the '
                  'line at every scale.',
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
                const _Label(
                  'Text scale — padding alone holds at 1.0 and breaks at 1.3',
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 20,
                  runSpacing: 20,
                  children: [
                    for (final s in const [1.0, 1.15, 1.3, 1.6])
                      MediaQuery(
                        data: MediaQueryData(
                          textScaler: TextScaler.linear(s),
                        ),
                        child: _Pane(width: 340, text: '', scaleLabel: '${s}x'),
                      ),
                  ],
                ),
                const SizedBox(height: 28),
                const _Label(
                  'Wrapped — the button goes back to the last line, by design',
                ),
                const SizedBox(height: 10),
                const _Pane(
                  width: 420,
                  text: 'Line one\nLine two\nLine three\nLine four',
                ),
                const SizedBox(height: 28),
                const _Label(
                  'Wrapped by WIDTH, not by a newline — the narrow pane',
                ),
                const SizedBox(height: 10),
                const _Pane(
                  width: 280,
                  text: 'Crew dispatched to the site and the culvert is clear.',
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
  final String? scaleLabel;
  const _Pane({
    required this.width,
    required this.text,
    this.focused = false,
    this.scaleLabel,
  });

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
            scaleLabel == null
                ? '${width.toInt()}px'
                : '${width.toInt()}px · text scale $scaleLabel',
            style: const TextStyle(fontSize: 10.5, color: Colors.black38),
          ),
          const SizedBox(height: 10),
          const _Tag('BEFORE', Color(0xFFB91C1C)),
          const SizedBox(height: 6),
          _Guide(child: _Old(text: text)),
          const SizedBox(height: 16),
          const _Tag('AFTER', Color(0xFF15803D)),
          const SizedBox(height: 6),
          _Guide(child: _New(text: text, focused: focused)),
        ],
      ),
    );
  }
}

/// Draws a hairline across the exact vertical centre of whatever it wraps.
///
/// The whole defect is 2px. Without a reference edge it is invisible in a
/// screenshot, which is how it survived a round of "looks fine to me" — so the
/// preview supplies the edge rather than asking anyone to eyeball it.
class _Guide extends StatelessWidget {
  final Widget child;
  const _Guide({required this.child});

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          child,
          Positioned.fill(
            child: Center(
              child: Container(height: 1, color: const Color(0x66DC2626)),
            ),
          ),
        ],
      );
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

/// The composer as it was BEFORE this round: the right shell, the wrong
/// vertical placement — a 6px field pad under an unconditional `end`.
///
/// The slab-and-gap version this file used to show is settled and gone; the
/// only comparison worth drawing now is the one still on screen.
class _Old extends StatelessWidget {
  final String text;
  const _Old({required this.text});

  @override
  Widget build(BuildContext context) => _Shell(
        text: text,
        focused: false,
        fieldPad: 6,
        crossAxisAlignment: CrossAxisAlignment.end,
      );
}

/// The composer as it is now: the field padded to the button's own height, and
/// the row centred until the text actually wraps.
class _New extends StatelessWidget {
  final String text;
  final bool focused;
  const _New({required this.text, required this.focused});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => _Shell(
          text: text,
          focused: focused,
          fieldPad: kFieldPad,
          crossAxisAlignment:
              _isWrapped(context, text, constraints.maxWidth)
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.center,
        ),
      );
}

/// Mirrors _ReportWorkLogState._isWrapped.
bool _isWrapped(BuildContext context, String text, double maxWidth) {
  if (text.isEmpty) return false;
  if (text.contains('\n')) return true;
  if (!maxWidth.isFinite) return false;
  final avail = maxWidth - 2 * (kShellPad + 1) - 2 * 6 - kSendSize;
  if (avail <= 0) return false;
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: const TextStyle(fontSize: 13.5, height: 1.35),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 4,
  )..layout(maxWidth: avail);
  final wrapped = painter.computeLineMetrics().length > 1;
  painter.dispose();
  return wrapped;
}

/// The shared shell, parameterised on the two things this round changed, so
/// BEFORE and AFTER differ by exactly those and nothing else.
class _Shell extends StatelessWidget {
  final String text;
  final bool focused;
  final double fieldPad;
  final CrossAxisAlignment crossAxisAlignment;
  const _Shell({
    required this.text,
    required this.focused,
    required this.fieldPad,
    required this.crossAxisAlignment,
  });

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
        crossAxisAlignment: crossAxisAlignment,
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
                decoration: InputDecoration(
                  isDense: true,
                  counterText: '',
                  hintText: 'Add a note…',
                  hintStyle: const TextStyle(
                      fontSize: 13.5, color: Color(0xFF9CA3AF)),
                  filled: false,
                  isCollapsed: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: fieldPad),
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
