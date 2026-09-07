// How big is a bottom-bar icon allowed to get?
//
// The bar sized its icons as a straight fraction of the scale width
// (`width * 0.065`), which ran up to a 28px glyph on a 430dp handset. A tab
// icon reads as a control up to about 24dp; past that it reads as artwork,
// and the bar stops looking like navigation and starts looking heavy.
//
// The rule now caps the icon and floors the label, so the bar keeps its
// proportional behaviour BETWEEN handset sizes without running away at
// either end. These tests pin the ends, because that is where the old rule
// broke and where a future "just make it scale" change would break it again.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:govpulse/core/widgets/Home/nav/home_bottom_nav.dart';

Future<Rect> _iconAt(WidgetTester t, Size size) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  t.view.viewPadding = const FakeViewPadding(bottom: 24);
  t.view.padding = const FakeViewPadding(bottom: 24);
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: const SizedBox.expand(),
        bottomNavigationBar: HomeBottomNav(currentIndex: 0, onTap: (_) {}),
      ),
    ),
  );
  return t.getRect(find.byType(ColorFiltered).first);
}

void main() {
  testWidgets('a large handset does not get an oversized icon', (t) async {
    // 430x932 used to draw a 27.9px icon.
    final icon = await _iconAt(t, const Size(430, 932));
    expect(icon.width, lessThanOrEqualTo(24.0));
  });

  testWidgets('a small handset still gets a tappable icon', (t) async {
    final icon = await _iconAt(t, const Size(320, 640));
    expect(icon.width, greaterThanOrEqualTo(18.0));
  });

  testWidgets('a tablet is capped at the same ceiling as a large phone', (
    t,
  ) async {
    // uiScaleWidth clamps at 480, so this must not exceed the phone ceiling.
    final icon = await _iconAt(t, const Size(768, 1024));
    expect(icon.width, lessThanOrEqualTo(24.0));
  });

  testWidgets('rotating a handset does not resize its icon', (t) async {
    final portrait = await _iconAt(t, const Size(390, 844));
    final landscape = await _iconAt(t, const Size(844, 390));
    expect(landscape.width, closeTo(portrait.width, 0.01));
  });

  testWidgets('the label keeps a legible floor on a narrow phone', (t) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: HomeBottomNav(currentIndex: 0, onTap: (_) {}),
        ),
      ),
    );
    // The size is applied by the bar, not carried on the Text widget, so it
    // has to be read off the laid-out paragraph.
    final rp = t.element(find.text('Home')).findRenderObject()! as RenderParagraph;
    expect(rp.text.style?.fontSize, greaterThanOrEqualTo(10.0));
  });
}
