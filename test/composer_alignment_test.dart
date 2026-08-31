import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:govpulse/core/theme/app_colors.dart';

/// The internal-notes composer — the field and its send button.
///
/// ── What this file used to assert, and why it was the wrong question ────────
/// Every earlier version of these tests measured ALIGNMENT: shared bottom
/// edges, shared centre lines, a 1px ink inset, a radius on the button larger
/// than the one on the field. All of them passed. The bottoms were 0.0px apart
/// through three rounds of "the button is too big", because a shared bottom
/// edge was never what was wrong.
///
/// The complaint was MASS: a 44x44 slab of saturated brand blue sitting across
/// an 8px gap from a field that was mostly empty space, and the gap is what let
/// the eye compare the two as separate objects of unequal size.
///
/// So the button moved INSIDE the field's shell, and these tests changed to
/// match. What is pinned now is the containment and the proportion — the
/// things that, if they regress, bring the complaint back:
///
///   • the send button is inside ONE shell with the field, not beside it
///   • it is materially SMALLER than the shell that holds it
///   • the shell holds its 44px floor and grows with the text
///   • the button is a tint at rest and fills only when there is text
///
/// ── And then alignment WAS the complaint, once mass was fixed ───────────────
/// With the button inside the shell, what was left was real and small: the
/// placeholder sat 2px below the centre line. A 30px field bottom-aligned
/// against a 32px button put both missing pixels above the text. The fix is a
/// padding that makes the two boxes equal PLUS a row that centres while
/// single-line and bottom-aligns once wrapped — because padding alone only
/// holds at 1.0 text scale. See the centre-line group for the measurements.
///
/// These rebuild the composer's geometry from the same constants rather than
/// mounting [ReportWorkLog], which reads Supabase.instance in its state and
/// cannot be pumped in a unit test. That is a real limit — it pins the
/// arithmetic, not the widget tree — and the guard against drift is the
/// derivation comments in report_work_log.dart plus tool/preview_note_composer
/// .dart, which now compiles. It did not, for the whole time this was broken,
/// which is how three passes shipped without anyone seeing the result.
void main() {
  // Mirror report_work_log.dart.
  const shellMinHeight = 44.0;
  const sendSize = 32.0;
  const shellPad = 5.0;
  const fieldPad = 7.0;
  const radius = 12.0;
  const sendRadius = 9.0;
  const accent = AppColors.primaryBlue;

  /// Mirrors _ReportWorkLogState._isWrapped.
  bool isWrapped(BuildContext context, String text, double maxWidth) {
    if (text.isEmpty) return false;
    if (text.contains('\n')) return true;
    if (!maxWidth.isFinite) return false;
    final avail =
        maxWidth - 2 * (shellPad + 1) - 2 * 6 - sendSize;
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

  Widget composer({
    String text = '',
    bool sending = false,
    bool focused = false,
    double width = 420,
    double textScale = 1.0,
  }) {
    final hasText = text.trim().isNotEmpty;
    final canSend = hasText && !sending;

    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: Builder(
              builder: (context) => LayoutBuilder(
                builder: (context, constraints) {
                  final wrapped =
                      isWrapped(context, text, constraints.maxWidth);
                  return Container(
              key: const Key('shell'),
              constraints: const BoxConstraints(minHeight: shellMinHeight),
              padding: const EdgeInsets.all(shellPad),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F6FB),
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(
                  color: focused ? accent : const Color(0xFFCBD3DF),
                  width: focused ? 1.5 : 1,
                ),
              ),
              child: Row(
                crossAxisAlignment: wrapped
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6),
                      child: TextField(
                        key: const Key('field'),
                        controller: TextEditingController(text: text),
                        minLines: 1,
                        maxLines: 4,
                        maxLength: 500,
                        style: const TextStyle(fontSize: 13.5, height: 1.35),
                        decoration: const InputDecoration(
                          isDense: true,
                          counterText: '',
                          hintText: 'Add a note…',
                          hintStyle: TextStyle(
                            fontSize: 13.5,
                            color: Color(0xFF9CA3AF),
                          ),
                          filled: false,
                          isCollapsed: true,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding:
                              EdgeInsets.symmetric(vertical: fieldPad),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    key: const Key('send'),
                    width: sendSize,
                    height: sendSize,
                    child: AnimatedContainer(
                      key: const Key('sendInk'),
                      duration: const Duration(milliseconds: 160),
                      decoration: BoxDecoration(
                        color:
                            canSend ? accent : accent.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(sendRadius),
                      ),
                      child: Center(
                        child: sending
                            ? const SizedBox(
                                width: 15,
                                height: 15,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(
                                Icons.send_rounded,
                                size: 16,
                                color: canSend ? Colors.white : accent,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }

  group('the composer is one control, not two', () {
    testWidgets('the send button sits INSIDE the shell', (tester) async {
      // The regression this guards is the one that was actually shipped: a
      // button placed as a sibling of the field with a gap between them. Any
      // such layout puts the button outside the shell rect and fails here.
      await tester.pumpWidget(composer());

      final shell = tester.getRect(find.byKey(const Key('shell')));
      final send = tester.getRect(find.byKey(const Key('send')));

      expect(shell.contains(send.topLeft), isTrue,
          reason: 'the button escaped the shell — it is a neighbour again');
      expect(shell.contains(send.bottomRight - const Offset(0.01, 0.01)),
          isTrue);
    });

    testWidgets('the button is visibly smaller than its container',
        (tester) async {
      // The complaint in one number. A button that fills its shell edge to
      // edge is the slab again, wearing a border.
      await tester.pumpWidget(composer());

      final shell = tester.getRect(find.byKey(const Key('shell')));
      final send = tester.getRect(find.byKey(const Key('send')));

      expect(send.height, lessThan(shell.height * 0.8),
          reason: 'the send button must read as part of the field, not as an '
              'equal partner beside it');
      expect(shell.height - send.height, greaterThanOrEqualTo(2 * shellPad),
          reason: 'the shell must show above and below the button');
    });

    testWidgets('the field is the widest thing in the row', (tester) async {
      // At every width, including the narrowest. The old layout gave the
      // button a fixed 44 while the field was Expanded, so the button owned a
      // larger and larger share as the pane narrowed — worst exactly on the
      // phone.
      for (final w in [520.0, 420.0, 340.0, 280.0]) {
        await tester.pumpWidget(composer(width: w));
        await tester.pump();

        final field = tester.getRect(find.byKey(const Key('field')));
        final send = tester.getRect(find.byKey(const Key('send')));

        expect(field.width, greaterThan(send.width * 3),
            reason: 'at ${w}px the note has to dominate the send button');
      }
    });
  });

  group('the shell holds its shape', () {
    testWidgets('a one-line composer is 44 tall', (tester) async {
      await tester.pumpWidget(composer());

      final shell = tester.getRect(find.byKey(const Key('shell')));
      expect(shell.height, moreOrLessEquals(shellMinHeight, epsilon: 0.5),
          reason: 'the resting height is what the send button and its 44px '
              'tap target are sized against');
    });

    testWidgets('it grows with the text and the button does not',
        (tester) async {
      for (final lines in [2, 3, 4]) {
        await tester.pumpWidget(
          composer(text: List.filled(lines, 'x').join('\n')),
        );
        await tester.pump();

        final shell = tester.getRect(find.byKey(const Key('shell')));
        final send = tester.getRect(find.byKey(const Key('send')));

        expect(shell.height, greaterThan(shellMinHeight),
            reason: 'the shell should have grown at $lines lines');
        expect(send.height, moreOrLessEquals(sendSize, epsilon: 0.5),
            reason: 'the button must not stretch with the text');
        expect(shell.bottom - send.bottom,
            moreOrLessEquals(shellPad + 1, epsilon: 1.0),
            reason: 'the button stays at the bottom of the shell, beside the '
                'last line where the caret is');
      }
    });

    testWidgets('the spinner does not resize the button', (tester) async {
      await tester.pumpWidget(composer(text: 'x', sending: true));
      final send = tester.getRect(find.byKey(const Key('send')));

      expect(send.height, moreOrLessEquals(sendSize, epsilon: 0.5));
      expect(send.width, moreOrLessEquals(sendSize, epsilon: 0.5),
          reason: 'swapping icon for spinner must not change the footprint');
    });
  });

  group('the send button earns its weight', () {
    BoxDecoration inkOf(WidgetTester tester) =>
        tester.widget<AnimatedContainer>(find.byKey(const Key('sendInk')))
            .decoration! as BoxDecoration;

    testWidgets('at rest it is a tint, not a slab', (tester) async {
      await tester.pumpWidget(composer());
      await tester.pump();

      expect(inkOf(tester).color, isNot(accent));
      expect(inkOf(tester).color!.a, lessThan(0.5));
      // The glyph carries the accent, so it still reads as Send.
      expect(tester.widget<Icon>(find.byIcon(Icons.send_rounded)).color,
          accent);
    });

    testWidgets('with text it fills', (tester) async {
      await tester.pumpWidget(composer(text: 'Crew dispatched.'));
      await tester.pump();

      expect(inkOf(tester).color, accent);
      expect(tester.widget<Icon>(find.byIcon(Icons.send_rounded)).color,
          Colors.white);
    });

    testWidgets('it stays quiet while a send is in flight', (tester) async {
      // canSend is hasText AND !sending. A button that stayed filled during a
      // send invites the second tap that posts the note twice.
      await tester.pumpWidget(composer(text: 'x', sending: true));
      await tester.pump();

      expect(inkOf(tester).color, isNot(accent));
    });

    testWidgets('the accent is the app blue, not a stray hex', (tester) async {
      // The old preview and tests hardcoded 0xFF1D4ED8 while the widget used
      // AppColors.primaryBlue (0xFF0D47A1) — so the thing being reviewed was
      // never the thing being shipped.
      expect(accent, const Color(0xFF0D47A1));
    });
  });

  group('the text sits on the composer\'s centre line', () {
    // ── The round this group was added for ────────────────────────────────
    //
    // With the button inside the shell, the remaining complaint was that the
    // placeholder was not vertically centred. It was not: the field's content
    // box was 30px against a 32px button, and under CrossAxisAlignment.end
    // both missing pixels landed ABOVE the text, dropping the hint 2px below
    // the shell's centre.
    //
    // Two things fix it together, and each is useless alone:
    //   • fieldPad 6 → 7, so a one-line field is 32 — the button's height
    //   • the row centres while single-line, bottom-aligns once wrapped
    //
    // The second is what makes it survive text scaling. Padding alone is only
    // correct at 1.0: the field's line box grows with the scale factor and the
    // button does not, so past ~1.15 the field is the TALLER of the two and
    // `end` starts pushing the BUTTON off-centre instead — the error changes
    // owner rather than going away. These run the scales to prove it.

    Finder hint() => find.text('Add a note…');

    testWidgets('the placeholder is centred against the send button',
        (tester) async {
      for (final scale in [1.0, 1.15, 1.3, 1.6]) {
        for (final w in [520.0, 420.0, 320.0]) {
          await tester.pumpWidget(composer(width: w, textScale: scale));
          await tester.pump();

          final send = tester.getRect(find.byKey(const Key('send')));
          final text = tester.getRect(hint());

          expect(text.center.dy, moreOrLessEquals(send.center.dy, epsilon: 0.5),
              reason: 'at ${w}px / ${scale}x the hint is off the button\'s '
                  'centre line — this is the misalignment users reported');
        }
      }
    });

    testWidgets('the placeholder is centred in the shell', (tester) async {
      for (final scale in [1.0, 1.15, 1.3, 1.6]) {
        await tester.pumpWidget(composer(textScale: scale));
        await tester.pump();

        final shell = tester.getRect(find.byKey(const Key('shell')));
        final text = tester.getRect(hint());

        expect(text.center.dy, moreOrLessEquals(shell.center.dy, epsilon: 0.5),
            reason: 'at ${scale}x the hint is off the shell\'s centre line');
      }
    });

    testWidgets('a short typed note is centred too', (tester) async {
      // The hint and the real text share a line box, so if one is centred the
      // other must be — but only while the field has not wrapped, which is the
      // case this pins.
      await tester.pumpWidget(composer(text: 'Crew dispatched.'));
      await tester.pump();

      final send = tester.getRect(find.byKey(const Key('send')));
      final text = tester.getRect(find.text('Crew dispatched.'));

      expect(text.center.dy, moreOrLessEquals(send.center.dy, epsilon: 0.5));
    });

    testWidgets('a one-line field is exactly as tall as the button',
        (tester) async {
      // The arithmetic behind fieldPad: 7 + 18 + 7 = 32. If this drifts, the
      // centring above starts depending on which alignment happens to be in
      // force, which is how the 2px got in.
      await tester.pumpWidget(composer());

      final field = tester.getRect(find.byKey(const Key('field')));
      final send = tester.getRect(find.byKey(const Key('send')));

      expect(field.height, moreOrLessEquals(send.height, epsilon: 0.5),
          reason: 'the field and the button must be the same height at rest, '
              'so centre- and bottom-alignment agree');
    });

    testWidgets('once wrapped, the button returns to the last line',
        (tester) async {
      // The other half of the trade. Centring a wrapped composer would float
      // the button against the middle of a growing block of text, away from
      // the caret — so the switch has to actually switch.
      for (final scale in [1.0, 1.3]) {
        await tester.pumpWidget(
          composer(text: 'a\nb\nc', textScale: scale),
        );
        await tester.pump();

        final shell = tester.getRect(find.byKey(const Key('shell')));
        final send = tester.getRect(find.byKey(const Key('send')));

        expect(shell.bottom - send.bottom,
            moreOrLessEquals(shellPad + 1, epsilon: 1.0),
            reason: 'at ${scale}x the button drifted off the last line');
      }
    });

    testWidgets('wrapping is decided by width, not by newlines',
        (tester) async {
      // The same sentence is one line in an admin pane and two on a phone, so
      // the switch reads a real text layout at the real width. A newline count
      // would leave the narrow case mis-aligned — the pane where it shows most.
      const long =
          'Crew dispatched to the site this morning and the culvert is now '
          'clear, pending a final inspection by the district engineer.';

      await tester.pumpWidget(composer(text: long, width: 320));
      await tester.pump();
      final narrowShell = tester.getRect(find.byKey(const Key('shell')));
      final narrowSend = tester.getRect(find.byKey(const Key('send')));

      expect(narrowShell.height, greaterThan(shellMinHeight),
          reason: 'this sentence must wrap at 320px for the test to mean '
              'anything');
      expect(narrowShell.bottom - narrowSend.bottom,
          moreOrLessEquals(shellPad + 1, epsilon: 1.0),
          reason: 'a wrapped field must bottom-align even with no newline in '
              'the text');
    });
  });

  group('the focus ring moved to the shell', () {
    // The field draws no border of its own any more; if the shell does not
    // pick the ring up, focus becomes invisible.
    BoxDecoration shellOf(WidgetTester tester) =>
        tester.widget<Container>(find.byKey(const Key('shell')))
            .decoration! as BoxDecoration;

    testWidgets('unfocused is the hairline', (tester) async {
      await tester.pumpWidget(composer());
      expect(shellOf(tester).border!.top.color, const Color(0xFFCBD3DF));
    });

    testWidgets('focused is the accent, and thicker', (tester) async {
      await tester.pumpWidget(composer(focused: true));
      expect(shellOf(tester).border!.top.color, accent);
      expect(shellOf(tester).border!.top.width, greaterThan(1.0));
    });
  });
}
