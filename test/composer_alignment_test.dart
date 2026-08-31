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
  const radius = 12.0;
  const sendRadius = 9.0;
  const accent = AppColors.primaryBlue;

  Widget composer({
    String text = '',
    bool sending = false,
    bool focused = false,
    double width = 420,
  }) {
    final hasText = text.trim().isNotEmpty;
    final canSend = hasText && !sending;

    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: Container(
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
                crossAxisAlignment: CrossAxisAlignment.end,
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
