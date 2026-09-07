// Do the four bottom-bar destinations announce themselves the same way?
//
// My Reports, Community Updates, Emergency and Settings each grew their own
// copy of the phone header — logo, page name, supporting line — and the
// copies drifted on nearly every value. The logo height was the only one all
// four agreed on. Four pages a citizen swaps between with a single tap were
// each using a different title size, weight, letter-spacing, padding and
// shadow, which read as different apps rather than as one.
//
// Three of them now share [CitizenPageHeader]. Community Updates cannot —
// its bar is shared with the web arm and carries the filter control — so its
// values are matched by hand, and this test is what keeps that match honest.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:govpulse/core/widgets/Home/citizen_page_header.dart';

const _w = 390.0;

Future<void> _pump(WidgetTester t, Widget child) async {
  t.view.physicalSize = const Size(_w, 844);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(home: Scaffold(body: Column(children: [child]))),
  );
}

TextStyle _styleOf(WidgetTester t, String text) =>
    (t.element(find.text(text)).findRenderObject()! as RenderParagraph)
        .text
        .style!;

void main() {
  testWidgets('the title is the same size, weight and spacing on every page', (
    t,
  ) async {
    for (final title in ['My Reports', 'Emergency', 'Settings']) {
      await _pump(t, CitizenPageHeader(title: title, width: _w));
      final s = _styleOf(t, title);
      expect(s.fontSize, closeTo(_w * .058, 0.01), reason: title);
      expect(s.fontWeight, FontWeight.w700, reason: title);
      expect(s.letterSpacing, closeTo(-0.3, 0.001), reason: title);
    }
  });

  testWidgets('the logo is the same height whether or not there is a subtitle', (
    t,
  ) async {
    await _pump(t, const CitizenPageHeader(title: 'Settings', width: _w));
    final bare = t.getRect(find.byType(Image));
    await _pump(
      t,
      const CitizenPageHeader(
        title: 'Emergency',
        subtitle: 'Aparri, Cagayan — Official Hotlines',
        width: _w,
      ),
    );
    expect(t.getRect(find.byType(Image)).height, closeTo(bare.height, 0.01));
  });

  testWidgets('a subtitle does not shift the title left or right', (t) async {
    await _pump(t, const CitizenPageHeader(title: 'Settings', width: _w));
    final bare = t.getRect(find.text('Settings')).left;
    await _pump(
      t,
      const CitizenPageHeader(
        title: 'Settings',
        subtitle: 'Notifications and app information',
        width: _w,
      ),
    );
    expect(t.getRect(find.text('Settings')).left, closeTo(bare, 0.01));
  });

  testWidgets('the logo and the title share one left edge', (t) async {
    // The misalignment that made an earlier header read as a stray card was
    // exactly this: the mark and the name starting at two different x.
    await _pump(
      t,
      const CitizenPageHeader(
        title: 'My Reports',
        subtitle: 'Track your submitted issues',
        width: _w,
      ),
    );
    final logo = t.getRect(find.byType(Image)).left;
    expect(t.getRect(find.text('My Reports')).left, closeTo(logo, 0.01));
    expect(
      t.getRect(find.text('Track your submitted issues')).left,
      closeTo(logo, 0.01),
    );
  });

  testWidgets('a long title ellipsizes rather than shoving the trailing control off', (
    t,
  ) async {
    await _pump(
      t,
      CitizenPageHeader(
        title: 'An Extremely Long Page Title That Cannot Possibly Fit',
        width: _w,
        trailing: Container(width: 90, height: 30, color: Colors.blue),
      ),
    );
    expect(t.takeException(), isNull);
    final trailing = t.getRect(find.byType(Container).last);
    expect(trailing.right, lessThanOrEqualTo(_w));
    expect(trailing.width, closeTo(90, 0.01));
  });

  testWidgets('rotating a handset does not resize the header', (t) async {
    // width defaults to uiScaleWidth, which measures the shortest side.
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    t.view.physicalSize = const Size(390, 844);
    await t.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Column(children: [CitizenPageHeader(title: 'Settings')])),
      ),
    );
    final portrait = _styleOf(t, 'Settings').fontSize;

    t.view.physicalSize = const Size(844, 390);
    await t.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Column(children: [CitizenPageHeader(title: 'Settings')])),
      ),
    );
    expect(_styleOf(t, 'Settings').fontSize, closeTo(portrait!, 0.01));
  });
}
