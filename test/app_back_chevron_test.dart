// Pins AppBackChevron to the Settings look it was transcribed from.
//
// The widget exists because the Profile Verification wizard had drifted into
// four different back chevrons — a bare AppBar arrow, a 38px blue circle, a
// white IconButton, and nothing at all. Consolidating them only helps if the
// consolidated version keeps matching Settings, so these are the exact numbers
// used by About / Privacy Policy / Terms / Contact Support / Edit Profile /
// My Submissions / the three Change Password steps:
//
//   box     w * 0.09 square
//   fill    0xFFF3F4F6
//   radius  w * 0.025
//   border  AppColors.stroke
//   icon    Icons.arrow_back_ios_rounded, w * 0.04, AppColors.primaryBlue
//
// If a case here fails, the question is whether SETTINGS moved. If it did,
// update both together; if it did not, the widget drifted and should be put
// back. Do not simply retune the expectation to whatever the widget now does —
// that is how the four variants happened in the first place.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:govpulse/core/theme/app_colors.dart';
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
  testWidgets('matches the Settings chevron exactly', (tester) async {
    await _pump(tester, const AppBackChevron(width: _w));

    final box = tester.getSize(find.byType(Container).first);
    expect(box.width, _w * 0.09);
    expect(box.height, _w * 0.09);

    final d = _decoration(tester);
    expect(d.color, const Color(0xFFF3F4F6));
    expect(d.borderRadius, BorderRadius.circular(_w * 0.025));
    expect((d.border! as Border).top.color, AppColors.stroke);

    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.icon, Icons.arrow_back_ios_rounded,
        reason: 'Settings uses the _ios_rounded glyph, not _ios_new_rounded '
            'and not the Material arrow_back');
    expect(icon.size, _w * 0.04);
    expect(icon.color, AppColors.primaryBlue);
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

    expect(d.color, isNot(const Color(0xFFF3F4F6)));
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
