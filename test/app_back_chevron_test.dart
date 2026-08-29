// Pins AppBackChevron to the ONE back chevron all three portals now share.
//
// The widget exists because the app had drifted into many answers to one
// question — a bare AppBar arrow, a blue circle, a white IconButton, filled
// chips at 38 and 40px, and screens with no affordance at all. Consolidating
// only helps if the consolidated version stays put, so these are its numbers:
//
//   box     w * 0.09 square
//   fill    none — it is an OUTLINE, not a filled chip
//   radius  w * 0.025
//   border  kBackChevronBorder
//   icon    Icons.arrow_back_ios_new_rounded, w * 0.046, kBackChevronGlyph
//
// The fill and the blue glyph are gone deliberately: back is chrome, shown
// identically on every screen and never the thing you came to press, so it
// recedes and lets the title lead. A filled chip with an accent arrow read as
// a primary action parked in the corner of every page.
//
// If a case here fails, the question is whether the DESIGN moved. If it did,
// update the admin (AdminDialogBack) and staff copies together with this one;
// if it did not, the widget drifted and should be put back. Do not simply
// retune the expectation to whatever the widget now does — that is how the
// variants happened in the first place.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:govpulse/core/widgets/app_back_chevron.dart';

const double _w = 390; // a phone width, below the 480 clamp

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: Center(child: child))),
  );
}

BoxDecoration _decoration(WidgetTester tester) {
  final container = tester.widget<Container>(
    find.descendant(
      of: find.byType(AppBackChevron),
      matching: find.byType(Container),
    ),
  );
  return container.decoration! as BoxDecoration;
}

void main() {
  testWidgets('is an outlined chip with a neutral glyph', (tester) async {
    await _pump(tester, const AppBackChevron(width: _w));

    final box = tester.getSize(find.byType(Container).first);
    expect(box.width, _w * 0.09);
    expect(box.height, _w * 0.09);

    final d = _decoration(tester);
    expect(d.color, isNull,
        reason: 'an OUTLINE, not a filled chip — a fill is what made this read '
            'as a primary action in the corner of every screen');
    expect(d.borderRadius, BorderRadius.circular(_w * 0.025));
    expect((d.border! as Border).top.color, kBackChevronBorder);

    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.icon, Icons.arrow_back_ios_new_rounded);
    expect(icon.size, _w * 0.046);
    expect(icon.color, kBackChevronGlyph,
        reason: 'neutral, not the brand blue: the accent belongs to controls '
            'that actually do something');
  });

  testWidgets('the shared palette is the one the consoles mirror',
      (tester) async {
    // Admin (AdminDialogBack) and staff both read these two constants rather
    // than their own theme tokens. Three lookups that happen to agree today is
    // exactly how the portals drifted apart before.
    expect(kBackChevronBorder, const Color(0xFFCBD3DF));
    expect(kBackChevronGlyph, const Color(0xFF374151));
  });

  testWidgets('the dark variant keeps the shape and inverts the colours',
      (tester) async {
    await _pump(tester, const AppBackChevron(width: _w, onDark: true));

    // Shape and proportions are what make it the same control; only the colours
    // may move, because a light fill is invisible on a camera preview.
    final box = tester.getSize(find.byType(Container).first);
    expect(box.width, _w * 0.09);
    final d = _decoration(tester);
    expect(d.borderRadius, BorderRadius.circular(_w * 0.025));
    expect(d.shape, BoxShape.rectangle,
        reason: 'the old face-scan chevron was a circle — that is the drift '
            'this widget removed, and the dark variant must not reintroduce it');

    expect(d.color, isNotNull,
        reason: 'the dark variant DOES take a scrim — without one the glyph '
            'floats on the camera preview');
    expect(tester.widget<Icon>(find.byType(Icon)).color, Colors.white);
  });

  testWidgets('scales off the screen width when none is given', (tester) async {
    tester.view.physicalSize = const Size(_w, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pump(tester, const AppBackChevron());

    // Same expression the Settings headers use, so an AppBar leading that
    // passes no width still comes out the size of the Settings chip.
    expect(tester.getSize(find.byType(Container).first).width, _w * 0.09);
  });

  testWidgets('pops the route when tapped', (tester) async {
    final nav = GlobalKey<NavigatorState>();
    var pushed = false;

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        home: const Scaffold(body: Text('first')),
      ),
    );

    nav.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(
          body: Center(child: AppBackChevron(width: _w)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    pushed = find.byType(AppBackChevron).evaluate().isNotEmpty;
    expect(pushed, isTrue);

    await tester.tap(find.byType(AppBackChevron));
    await tester.pumpAndSettle();

    expect(find.text('first'), findsOneWidget,
        reason: 'the default action is a back navigation');
  });
}
