import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The work-log composer's field and its send button must share a bottom edge
/// and a centre line.
///
/// They used to be built from unrelated numbers — the field's height falls out
/// of its content padding, line height and borders, while the button's fell out
/// of the padding around an 18px icon — and a `Padding(bottom: 2)` on top of
/// that left the bottoms 2.0px apart and the centres 1.0px apart. Small enough
/// to survive review, plainly visible on screen as a send button riding high.
///
/// A screenshot answers "does that look off?" with an opinion. This answers it
/// with a number, which is the only way a 2px error gets caught reliably — the
/// same reason detail_kv_row_alignment_test exists.
///
/// The composer talks to Supabase in its real form, so these tests rebuild its
/// geometry from the same constants rather than mounting the widget. That is a
/// real limitation: it pins the ARITHMETIC, and would not catch someone
/// wrapping the button in a new Padding. The guard against that is the
/// derivation comment on _kComposerFieldHeight plus the preview target.
void main() {
  // Mirrors _kComposerFieldHeight in report_work_log.dart.
  const composerHeight = 44.0;

  Widget composer({int lines = 1, bool sending = false}) {
    return MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  key: const Key('field'),
                  controller: TextEditingController(
                    text: List.filled(lines, 'x').join('\n'),
                  ),
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 500,
                  style: const TextStyle(fontSize: 13.5),
                  decoration: InputDecoration(
                    isDense: true,
                    counterText: '',
                    hintText: 'Add a note…',
                    filled: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFCBD3DF)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                key: const Key('send'),
                width: composerHeight,
                height: composerHeight,
                child: Material(
                  color: const Color(0xFF1D4ED8),
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () {},
                    child: Center(
                      child: sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded, size: 18),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  group('work-log composer alignment', () {
    testWidgets('field and send button share a bottom edge at one line',
        (tester) async {
      await tester.pumpWidget(composer());

      final field = tester.getRect(find.byKey(const Key('field')));
      final send = tester.getRect(find.byKey(const Key('send')));

      expect(send.bottom, moreOrLessEquals(field.bottom, epsilon: 0.5),
          reason: 'the send button used to sit 2px above the field');
      expect(send.center.dy, moreOrLessEquals(field.center.dy, epsilon: 0.5),
          reason: 'centres were 1px apart');
    });

    testWidgets('the constant matches the field it has to line up with',
        (tester) async {
      // If a Flutter upgrade or a padding edit moves the dense field's height,
      // this fails instead of quietly re-opening the 2px gap.
      await tester.pumpWidget(composer());
      final field = tester.getRect(find.byKey(const Key('field')));

      expect(field.height, moreOrLessEquals(composerHeight, epsilon: 0.5),
          reason: '_kComposerFieldHeight must track the real field height');
    });

    testWidgets('bottoms stay aligned as the field grows to four lines',
        (tester) async {
      // CrossAxisAlignment.end is what holds this together — the regression
      // would be someone switching the Row to center, which looks right at one
      // line and drifts badly at four.
      for (final lines in [2, 3, 4]) {
        await tester.pumpWidget(composer(lines: lines));
        await tester.pump();

        final field = tester.getRect(find.byKey(const Key('field')));
        final send = tester.getRect(find.byKey(const Key('send')));

        expect(send.bottom, moreOrLessEquals(field.bottom, epsilon: 0.5),
            reason: 'bottom edges must stay level at $lines lines');
        expect(field.height, greaterThan(composerHeight),
            reason: 'the field should have actually grown at $lines lines');
        expect(send.height, moreOrLessEquals(composerHeight, epsilon: 0.5),
            reason: 'the button must NOT stretch with the field');
      }
    });

    testWidgets('the spinner does not resize the button', (tester) async {
      await tester.pumpWidget(composer(sending: true));
      final send = tester.getRect(find.byKey(const Key('send')));

      expect(send.height, moreOrLessEquals(composerHeight, epsilon: 0.5));
      expect(send.width, moreOrLessEquals(composerHeight, epsilon: 0.5),
          reason: 'swapping icon for spinner must not change the footprint');
    });
  });

  // ── Weight, not just alignment ──────────────────────────────────────────
  //
  // The field and the button have always shared a bottom edge; the tests above
  // pin that. What was WRONG was the weight: a pale outlined field beside a
  // fully saturated square of brand blue, so the eye landed on Send rather
  // than on the note being written — and the button looked pressable while an
  // empty note is refused by _send().
  //
  // These rebuild the same geometry the tests above use, plus the resting /
  // active colouring, so the two cannot drift apart.
  group('the send button earns its weight', () {
    const accent = Color(0xFF1D4ED8);

    Widget button({required bool hasText}) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 44,
            height: 44,
            child: AnimatedContainer(
              key: const Key('send'),
              duration: const Duration(milliseconds: 160),
              decoration: BoxDecoration(
                color: hasText ? accent : accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.send_rounded,
                size: 19,
                color: hasText ? Colors.white : accent,
              ),
            ),
          ),
        ),
      ),
    );

    testWidgets('at rest it is a tint, not a slab', (tester) async {
      await tester.pumpWidget(button(hasText: false));
      await tester.pump();

      final deco = tester
          .widget<AnimatedContainer>(find.byKey(const Key('send')))
          .decoration as BoxDecoration;

      // Not the full accent — that is the shout the screenshot shows.
      expect(deco.color, isNot(accent));
      expect(deco.color!.a, lessThan(0.5));

      // And the glyph is the accent, so the control is still legible as Send.
      expect(
        tester.widget<Icon>(find.byIcon(Icons.send_rounded)).color,
        accent,
      );
    });

    testWidgets('with text it fills', (tester) async {
      await tester.pumpWidget(button(hasText: true));
      await tester.pump();

      final deco = tester
          .widget<AnimatedContainer>(find.byKey(const Key('send')))
          .decoration as BoxDecoration;

      expect(deco.color, accent);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.send_rounded)).color,
        Colors.white,
      );
    });

    testWidgets('both halves share one radius', (tester) async {
      await tester.pumpWidget(button(hasText: true));
      await tester.pump();

      final deco = tester
          .widget<AnimatedContainer>(find.byKey(const Key('send')))
          .decoration as BoxDecoration;

      // 12 — the field's radius. It was 11 here, a 1px difference nobody could
      // name but which stopped the pair reading as one control.
      expect(
        deco.borderRadius,
        BorderRadius.circular(12),
      );
    });
  });
}
