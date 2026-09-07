import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Enter posts an internal note; Shift+Enter breaks the line.
///
/// ── The bug this pins ───────────────────────────────────────────────────────
/// The admin/staff internal-note composer (report_work_log.dart) was a plain
/// multiline TextField with `textInputAction: TextInputAction.newline` and no
/// key handling at all. On a desk — which is where consoles are actually used —
/// pressing Enter after typing a note did what Shift+Enter does everywhere
/// else: it inserted a blank second line and left the note UNSENT. The officer
/// had to find the send button. Every other composer in the product (the
/// citizen chat bar, the staff conversation reply) already read Enter as
/// "send", so the note thread was the lone outlier.
///
/// ── Why this rebuilds the handler instead of pumping ReportWorkLog ──────────
/// [ReportWorkLog] reads `Supabase.instance` in its state and cannot be pumped
/// in a unit test — the same limit composer_alignment_test.dart documents. So
/// what is pinned here is the KEY CONTRACT the widget installs, exercised
/// against a real TextField and a real focus tree: the behaviour that broke,
/// in the form it broke in. The guard against the widget drifting away from it
/// is that this is the identical Focus/onKeyEvent shape used there and in the
/// two composers that already had it.
void main() {
  /// Mirrors the Focus wrapper in report_work_log.dart's _composer().
  Widget harness({
    required TextEditingController ctrl,
    required VoidCallback onSend,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Focus(
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.enter &&
                !HardwareKeyboard.instance.isShiftPressed) {
              onSend();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: TextField(
            controller: ctrl,
            autofocus: true,
            minLines: 1,
            maxLines: 4,
            maxLength: 500,
            textInputAction: TextInputAction.newline,
          ),
        ),
      ),
    );
  }

  testWidgets('Enter sends the note and does not insert a line break', (
    tester,
  ) async {
    final ctrl = TextEditingController(text: 'Crew dispatched.');
    var sends = 0;
    await tester.pumpWidget(harness(ctrl: ctrl, onSend: () => sends++));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(sends, 1, reason: 'Enter must post the note');
    expect(
      ctrl.text,
      'Crew dispatched.',
      reason: 'Enter must not leave a stray newline in the field',
    );
  });

  testWidgets('Shift+Enter breaks the line and does not send', (tester) async {
    final ctrl = TextEditingController(text: 'Line one');
    var sends = 0;
    await tester.pumpWidget(harness(ctrl: ctrl, onSend: () => sends++));
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(sends, 0, reason: 'Shift+Enter is the deliberate newline');
  });

  // A single press is one KeyDownEvent and one KeyUpEvent. Sending on both is
  // how a composer posts the same note twice, so the handler is KeyDown-only.
  testWidgets('one press sends exactly once', (tester) async {
    final ctrl = TextEditingController(text: 'Patched and reopened.');
    var sends = 0;
    await tester.pumpWidget(harness(ctrl: ctrl, onSend: () => sends++));
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(sends, 1, reason: 'KeyUp must not post a second note');
  });

  // The real _send() refuses an empty body, so Enter on an empty field posts
  // nothing — but it must also not fall through to inserting the newline it
  // just suppressed, which would leave the field holding whitespace.
  testWidgets('Enter on an empty field inserts nothing', (tester) async {
    final ctrl = TextEditingController();
    await tester.pumpWidget(harness(ctrl: ctrl, onSend: () {}));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(ctrl.text, isEmpty);
  });
}
