// The web top nav's bell and profile chip are BARE controls, and the control
// itself is what responds to a hover.
//
// What this replaces: a 44px grey circle behind the bell and a grey pill behind
// the chip. A filled shape behind an icon reads as a button whether or not the
// pointer is near it, so at rest the bar showed two grey blobs; and on hover
// what lit up was the blob — the circle went blue, the pill went blue — rather
// than the bell or the name. Flat, the bell tints and lifts, and the chip's
// name and chevron tint.
//
// `flatChrome` is passed rather than the suite being run in a browser: the
// production value is `kIsWeb`, a compile-time constant, so under the VM the
// flat branch is not merely false but absent. It is also why the native branch
// is worth a case of its own — this bar is NOT web-only. resolveNavBand hands
// `topNav` to any viewport at least 900 wide that is not a handset, so a native
// tablet in landscape renders it, and that is the mobile app.
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:govpulse/core/widgets/Home/nav/home_top_nav.dart';

const _grey = Color(0xFFF3F4F6); // the bell's old circle
const _greyPill = Color(0xFFF9FAFB); // the chip's old pill
const _hoverBlue = Color(0xFFEFF6FF); // what used to fill on hover
const _active = Color(0xFF1A4DB8);

Future<void> _pump(WidgetTester tester, {required bool flat}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  // The bar only exists at >= 900 (resolveNavBand's topNav band), and the test
  // surface defaults to 800x600 — narrower than the layout is ever asked to be,
  // so every case would fail on an overflow that cannot happen in production.
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: HomeTopNav(
          currentIndex: 0,
          onTap: (_) {},
          onNotificationTap: () {},
          onLogoutTap: () {},
          notificationCount: 0,
          username: 'markreduca',
          fullName: 'Mark Reduca',
          verifStatus: 'approved',
          flatChrome: flat,
        ),
      ),
    ),
  );
}

/// The bell's OWN 44x44 box — the circle that used to be grey.
///
/// Identified by its shape rather than by taking the nearest ancestor: every
/// Container above the icon is an "ancestor", including the bar's background
/// and the scaffold's, and asserting on those was asserting that the whole nav
/// is transparent. The circle is the only round one.
BoxDecoration _bellBox(WidgetTester tester) => tester
    .widgetList<Container>(
      find.ancestor(
        of: find.byIcon(Icons.notifications_rounded),
        matching: find.byType(Container),
      ),
    )
    .map((c) => c.decoration)
    .whereType<BoxDecoration>()
    .firstWhere((d) => d.shape == BoxShape.circle);

/// The chip's OWN box — the pill that used to be grey. Same reasoning as
/// [_bellBox]; the pill is the only fully-rounded one.
BoxDecoration _chipBox(WidgetTester tester) => tester
    .widgetList<Container>(
      find.ancestor(of: _chipName, matching: find.byType(Container)),
    )
    .map((c) => c.decoration)
    .whereType<BoxDecoration>()
    .firstWhere((d) => d.borderRadius == BorderRadius.circular(999));

Color? _iconColour(WidgetTester tester, IconData icon) =>
    tester.widget<Icon>(find.byIcon(icon)).color;

/// The name IN THE BAR.
///
/// Scoped, because hovering the chip opens the dropdown and the dropdown header
/// repeats the same name — an unscoped `find.text` matches two widgets the
/// moment the thing under test starts working. The overlay is inserted into the
/// app's Overlay, which is not inside [HomeTopNav], so this cleanly excludes it.
final _chipName = find.descendant(
  of: find.byType(HomeTopNav),
  matching: find.text('Mark Reduca'),
);

Color? _nameColour(WidgetTester tester) =>
    tester.widget<Text>(_chipName).style?.color;

/// Moves a real pointer onto [finder] and settles the hover animations.
Future<TestGesture> _hover(WidgetTester tester, Finder finder) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  addTearDown(gesture.removePointer);
  await tester.pump();
  await gesture.moveTo(tester.getCenter(finder));
  await tester.pumpAndSettle();
  return gesture;
}

/// A colour that paints nothing.
Matcher get _paintsNothing => anyOf(isNull, Colors.transparent);

void main() {
  group('at rest', () {
    testWidgets('nothing is painted behind the bell', (tester) async {
      await _pump(tester, flat: true);

      final box = _bellBox(tester);
      expect(
        box.color,
        _paintsNothing,
        reason: 'a filled shape is back behind the bell',
      );
      expect(box.color, isNot(_grey));
      expect(box.border?.top.color, _paintsNothing);
    });

    testWidgets('nothing is painted behind the profile chip', (tester) async {
      await _pump(tester, flat: true);

      final box = _chipBox(tester);
      expect(box.color, _paintsNothing, reason: 'the grey pill is back');
      expect(box.color, isNot(_greyPill));
      expect(box.border?.top.color, _paintsNothing);
    });
  });

  group('on hover', () {
    testWidgets('the BELL responds, and no shape appears behind it', (
      tester,
    ) async {
      await _pump(tester, flat: true);
      expect(_iconColour(tester, Icons.notifications_rounded), isNot(_active));

      await _hover(tester, find.byIcon(Icons.notifications_rounded));

      // The glyph itself is what changed...
      expect(_iconColour(tester, Icons.notifications_rounded), _active);
      // ...and it moved, because colour alone is a weak signal on a bare 24px
      // icon with nothing around it.
      final scale = tester.widget<AnimatedScale>(
        find
            .ancestor(
              of: find.byIcon(Icons.notifications_rounded),
              matching: find.byType(AnimatedScale),
            )
            .first,
      );
      expect(scale.scale, greaterThan(1.0));

      // The whole point: the old circle must NOT come back on hover either.
      final box = _bellBox(tester);
      expect(
        box.color,
        _paintsNothing,
        reason: 'hover refilled the circle instead of the bell',
      );
      expect(box.color, isNot(_hoverBlue));
    });

    testWidgets('the profile NAME responds', (tester) async {
      await _pump(tester, flat: true);
      expect(_nameColour(tester), isNot(_active));

      await _hover(tester, _chipName);

      expect(
        _nameColour(tester),
        _active,
        reason: 'with the pill gone the name is the affordance',
      );
    });
  });

  group('native is left alone', () {
    testWidgets('the tablet bar keeps its filled chrome', (tester) async {
      // A native tablet in landscape renders this same bar. Nothing above is
      // meant to reach it, so the grey circle and pill must still be there.
      await _pump(tester, flat: false);

      expect(
        _bellBox(tester).color,
        _grey,
        reason: 'the native bell lost its circle',
      );
      expect(
        _chipBox(tester).color,
        _greyPill,
        reason: 'the native chip lost its pill',
      );

      // Same WIDGETS, not merely the same pixels. The flat path adds a lift to
      // the bell; native must not carry an inert copy of it, or "no mobile
      // change" quietly becomes "no visible mobile change".
      expect(
        find.ancestor(
          of: find.byIcon(Icons.notifications_rounded),
          matching: find.byType(AnimatedScale),
        ),
        findsNothing,
        reason: 'the flat-only lift leaked into the native tree',
      );
    });
  });
}
