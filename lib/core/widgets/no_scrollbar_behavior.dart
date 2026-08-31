import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

// ════════════════════════════════════════════════════════════════════════════
//  The app's one "scrolls, but paints no bar" behaviour.
//
//  On desktop web Material hangs a scrollbar on every scroll view, and this app
//  is made of scroll views INSIDE cards: a report detail, an event form, a staff
//  pane. A track running down the inside edge of a card reads as a seam in the
//  card rather than as a control, and on the detail dialogs it sat directly on
//  the rounded corner — see the Report Details pop-up, where the bar ran the
//  full height of the card and clipped its own corner radius.
//
//  ── WHY THIS FILE, RATHER THAN A FIFTH COPY ───────────────────────────────
//  Four identical private classes had already been written — main.dart,
//  citizen_shell.dart, home_nav_drawer.dart and the two activity pages — each
//  solving this for one subtree because there was nowhere shared to put it.
//  This is that place. New scrolling surfaces get the app-wide default instead
//  of rediscovering the trick.
//
//  ── WHAT IS AND IS NOT OVERRIDDEN ─────────────────────────────────────────
//  [buildScrollbar] returns the child untouched instead of wrapping it in a
//  [Scrollbar]. That is the whole of it. Physics, the overscroll indicator,
//  wheel, trackpad, drag and keyboard scrolling are all inherited unchanged:
//  the BAR goes, the SCROLLING stays. This is deliberately not
//  `NeverScrollableScrollPhysics` or any other way of stopping the scroll.
//
//  [dragDevices] adds the mouse to the default set, because once there is no
//  visible thumb to grab, click-and-drag is the fallback a pointer user reaches
//  for on a surface that no longer advertises that it scrolls.
// ════════════════════════════════════════════════════════════════════════════
class NoScrollbarBehavior extends MaterialScrollBehavior {
  const NoScrollbarBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;

  @override
  Set<PointerDeviceKind> get dragDevices => {
    ...super.dragDevices,
    PointerDeviceKind.mouse,
  };
}
