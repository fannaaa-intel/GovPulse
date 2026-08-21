// Where does the bottom nav sit when Android draws its own navigation on top?
//
// targetSdk is 36, so the window is edge-to-edge whether the app asks for it
// or not — Android 15 removed the opt-out. The bar is therefore drawn
// UNDERNEATH the system navigation, and `viewPadding` is the only thing that
// says how much of it is covered:
//
//   3-button, portrait   bottom ≈ 48
//   gesture,  portrait   bottom ≈ 24   (just the handle)
//   3-button, landscape  the bar moves to a SIDE: right (or left) ≈ 48, bottom 0
//   gesture,  landscape  bottom ≈ 16
//
// Material handles the vertical cases on its own. The landscape one it does
// not: the bar spanned the full width regardless, so Settings ended 8dp past
// the usable edge with its tap target half-swallowed by the system bar.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:govpulse/core/widgets/Home/nav/home_bottom_nav.dart';

Future<void> _pump(
  WidgetTester tester, {
  required Size size,
  required FakeViewPadding pad,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.view.viewPadding = pad;
  tester.view.padding = pad;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        extendBody: true,
        body: const SizedBox.expand(),
        bottomNavigationBar: HomeBottomNav(currentIndex: 0, onTap: (_) {}),
      ),
    ),
  );
}

void main() {
  testWidgets('3-button portrait: buttons clear the 48dp bar, fill runs behind it', (
    tester,
  ) async {
    await _pump(
      tester,
      size: const Size(390, 844),
      pad: const FakeViewPadding(bottom: 48),
    );
    final bar = tester.getRect(find.byType(BottomNavigationBar));
    // The white fill reaches the physical bottom — no strip of scrolling page
    // showing through behind a translucent system bar.
    expect(bar.bottom, 844);
    // ...but the labels stop above it.
    expect(tester.getRect(find.text('Settings')).bottom, lessThanOrEqualTo(844 - 48));
  });

  testWidgets('gesture portrait: fill runs down behind the handle', (tester) async {
    await _pump(
      tester,
      size: const Size(390, 844),
      pad: const FakeViewPadding(bottom: 24),
    );
    final bar = tester.getRect(find.byType(BottomNavigationBar));
    expect(bar.bottom, 844);
    // 56dp of bar + the 24dp handle inset, not 56 with a gap under it.
    expect(bar.height, moreOrLessEquals(80, epsilon: 1));
  });

  testWidgets('3-button landscape: items stay clear of the side bar', (tester) async {
    await _pump(
      tester,
      size: const Size(844, 390),
      pad: const FakeViewPadding(right: 48),
    );
    // Every item is inside the usable width...
    expect(tester.getRect(find.text('Settings')).right, lessThanOrEqualTo(844 - 48));
    // ...while the fill still spans the whole width, so the strip behind the
    // system bar is app-coloured rather than transparent.
    expect(tester.getRect(find.byType(Container).first).right, 844);
  });

  testWidgets('gesture landscape: nothing is given away', (tester) async {
    await _pump(
      tester,
      size: const Size(844, 390),
      pad: const FakeViewPadding(bottom: 16),
    );
    // No side bar to dodge, so the items keep the full width.
    expect(tester.getRect(find.text('Settings')).right, greaterThan(844 - 60));
  });
}
