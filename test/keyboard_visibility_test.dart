// Does the on-screen keyboard cover a focused input on mobile web?
//
// ── What is actually true here ────────────────────────────────────────────
// Flutter web DOES report the keyboard: the web engine computes `viewInsets`
// from `window.visualViewport`, with a dedicated branch for iOS Safari, so a
// phone browser gives a real `viewInsets.bottom` rather than the zero it is
// often assumed to be.
//
// `Scaffold` then consumes it correctly — `resizeToAvoidBottomInset` shrinks the
// body AND strips the inset from the MediaQuery the body sees, so a nested
// Scaffold does not subtract the same keyboard twice.
//
// So the machinery is sound, and the only question left is the one that
// actually bites a citizen: when the viewport shrinks, does the field they just
// tapped end up somewhere they can see it? That is what these pin, using the
// real inset path (`tester.view.viewInsets`) rather than a hand-built
// MediaQuery, so the Scaffold resize being tested is the genuine one.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:govpulse/core/widgets/Home/Account/account_web_kit.dart';

const Size _kPhone = Size(400, 800);
const double _kKeyboard = 320;

/// A form long enough that its last field sits well below the fold once a
/// keyboard is up — the case that matters.
Widget _form(List<FocusNode> nodes) => MaterialApp(
  home: Scaffold(
    body: AccountPageBody(
      builder: (context, stack) => AccountFieldSection(
        title: 'Details',
        stack: stack,
        rows: [
          for (var i = 0; i < nodes.length; i++)
            [
              AccountTextField(
                controller: TextEditingController(),
                label: 'Field $i',
                hint: 'hint',
                focusNode: nodes[i],
              ),
            ],
        ],
      ),
    ),
  ),
);

void main() {
  testWidgets('a Scaffold body is told the keyboard is already handled', (
    tester,
  ) async {
    tester.view.physicalSize = _kPhone;
    tester.view.devicePixelRatio = 1.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: _kKeyboard);
    addTearDown(tester.view.reset);

    double? insetSeenByBody;
    double? heightGivenToBody;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LayoutBuilder(
            builder: (context, c) {
              insetSeenByBody = MediaQuery.of(context).viewInsets.bottom;
              heightGivenToBody = c.maxHeight;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );

    // The contract the whole thing rests on: the body is made shorter by the
    // keyboard AND told there is no keyboard left to avoid. If this ever flips,
    // every nested Scaffold in the shell starts subtracting it a second time.
    expect(heightGivenToBody, _kPhone.height - _kKeyboard);
    expect(insetSeenByBody, 0);
  });

  testWidgets('a focused field below the fold is scrolled into view', (
    tester,
  ) async {
    final nodes = List.generate(12, (_) => FocusNode());
    addTearDown(() {
      for (final n in nodes) {
        n.dispose();
      }
    });

    tester.view.physicalSize = _kPhone;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_form(nodes));

    // The keyboard comes up, then the citizen taps a field near the bottom.
    tester.view.viewInsets = const FakeViewPadding(bottom: _kKeyboard);
    await tester.pumpAndSettle();

    nodes.last.requestFocus();
    await tester.pumpAndSettle();

    final visibleBottom = _kPhone.height - _kKeyboard;
    final field = tester.getRect(find.byType(AccountTextField).last);

    // The whole point: the field the citizen is typing into has to be above the
    // keyboard, not behind it.
    expect(
      field.bottom,
      lessThanOrEqualTo(visibleBottom),
      reason:
          'focused field bottom ${field.bottom} is under the keyboard, which '
          'starts at $visibleBottom',
    );
    expect(field.top, greaterThanOrEqualTo(0));
  });

  testWidgets('the first field stays put when nothing is focused', (
    tester,
  ) async {
    final nodes = List.generate(12, (_) => FocusNode());
    addTearDown(() {
      for (final n in nodes) {
        n.dispose();
      }
    });

    tester.view.physicalSize = _kPhone;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_form(nodes));
    final before = tester.getRect(find.byType(AccountTextField).first);

    tester.view.viewInsets = const FakeViewPadding(bottom: _kKeyboard);
    await tester.pumpAndSettle();

    // A keyboard opening on its own must not throw the page around; only
    // focusing something should move it.
    expect(
      tester.getRect(find.byType(AccountTextField).first).top,
      closeTo(before.top, 0.5),
    );
  });
}
