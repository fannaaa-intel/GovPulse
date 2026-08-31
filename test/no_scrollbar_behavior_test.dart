// Guards the app-wide "scrolls, but paints no bar" behaviour.
//
// The bug this closes: every admin and staff DETAIL pop-up — Report Details,
// and the event / feedback / suggestion details beside it — painted a Material
// scrollbar down the inside edge of its rounded card, where it read as a seam
// in the card rather than as a control.
//
// The cause was not any of those dialogs. `GovPulseWebApp`, the root for every
// web launch, simply never set `scrollBehavior`, so the whole web app ran on
// Material's default. The legacy mobile `MaterialApp` in main.dart HAD set it,
// which is why this only ever showed up in the browser.
//
// Two things are therefore worth testing, and the second is the one that would
// actually regress:
//
//   1. NoScrollbarBehavior paints no Scrollbar but still scrolls. If a future
//      edit "simplifies" it into NeverScrollableScrollPhysics, the bar also
//      disappears — and so does the content below the fold.
//
//   2. It reaches a DIALOG ROUTE. A dialog mounts on the Navigator's overlay,
//      ABOVE any ScrollConfiguration a page wraps its own body in. That is
//      exactly why the console's shell-scoped wrapper never fixed these
//      pop-ups, and why the behaviour has to sit at the app root.

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/core/widgets/no_scrollbar_behavior.dart';

/// Desktop, because [MaterialScrollBehavior] only builds a [Scrollbar] on the
/// desktop platforms. The test binding reports Android, where a bare root draws
/// no bar either — so without this every assertion below would pass whether or
/// not the behaviour worked.
///
/// Android is also why the bug was invisible to `flutter test` and to the app:
/// Flutter web reports the HOST OS, so the browser console runs on the desktop
/// branch. This reproduces that branch.
///
/// Set through the theme rather than `debugDefaultTargetPlatformOverride`: a
/// global debug var has to be unset before the binding's post-test invariant
/// check, which `addTearDown` is too late for.
final ThemeData _desktop = ThemeData(platform: TargetPlatform.macOS);

/// A scroll view taller than any frame it is given, so a bar always has cause
/// to appear and there is always somewhere to scroll to.
Widget _longList({Key? key}) => ListView(
  key: key,
  children: [for (var i = 0; i < 60; i++) SizedBox(height: 40, child: Text('$i'))],
);

void main() {
  testWidgets('paints no Scrollbar', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: _desktop,
        scrollBehavior: const NoScrollbarBehavior(),
        home: Scaffold(body: _longList()),
      ),
    );

    expect(find.byType(Scrollbar), findsNothing);
    expect(find.byType(RawScrollbar), findsNothing);
  });

  testWidgets('a bare root DOES paint one — the bug being fixed', (tester) async {
    // Pins the premise. Without this, the test above passes just as happily on
    // a Flutter that stopped drawing scrollbars for its own reasons, and the
    // guard would be silently worthless. See [_desktop].
    await tester.pumpWidget(
      MaterialApp(theme: _desktop, home: Scaffold(body: _longList())),
    );

    expect(find.byType(Scrollbar), findsWidgets);
  });

  testWidgets('still scrolls — the bar goes, the scrolling stays', (tester) async {
    const key = Key('list');
    await tester.pumpWidget(
      MaterialApp(
        theme: _desktop,
        scrollBehavior: const NoScrollbarBehavior(),
        home: Scaffold(body: _longList(key: key)),
      ),
    );

    final before = tester.widget<ListView>(find.byKey(key)).controller;
    expect(before, isNull); // uses the implicit PrimaryScrollController

    final position = tester.state<ScrollableState>(find.byType(Scrollable)).position;
    expect(position.pixels, 0);

    await tester.drag(find.byType(Scrollable), const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(position.pixels, greaterThan(0));
  });

  testWidgets('mouse is a drag device, since there is no thumb to grab', (
    tester,
  ) async {
    const behavior = NoScrollbarBehavior();
    expect(behavior.dragDevices, contains(PointerDeviceKind.mouse));
    expect(behavior.dragDevices, contains(PointerDeviceKind.touch));
  });

  testWidgets('reaches a dialog route, not just the page body', (tester) async {
    // The regression that matters. A ScrollConfiguration wrapped around a
    // page's body does NOT cover a dialog — the dialog is a route on the
    // overlay above it. Only the app root reaches both.
    await tester.pumpWidget(
      MaterialApp(
        theme: _desktop,
        scrollBehavior: const NoScrollbarBehavior(),
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );

    final context = tester.element(find.byType(Scaffold));
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(child: SizedBox(height: 300, child: _longList())),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(Scrollbar), findsNothing);
  });
}
