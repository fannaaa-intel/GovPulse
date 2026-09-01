// The citizen web nav bar must fit the window it is drawn in.
//
// ── The bug ────────────────────────────────────────────────────────────────
// The centre links were a `Center` wrapped around a `MainAxisSize.min` Row.
// Neither can shrink: the Row takes the links' natural width and the Center
// hands it that width whatever is actually available. So once the brand, the
// links, the bell and the profile chip together wanted more than the bar, the
// links simply ran off the right-hand edge.
//
// At a 1024px viewport that was ~9px past the bar at the DEFAULT text size and
// ~220px at Android's largest — far enough that the links sit under the profile
// chip, where they cannot be clicked. 1024 is an ordinary laptop width and a
// very common browser window, not an edge case.
//
// It went unseen because responsive_audit_test sweeps PHONE sizes, where this
// bar is not built at all, and the web layouts had no sweep of their own.
//
// ── What the fix must preserve ─────────────────────────────────────────────
// The links are CENTRED in the bar at ordinary desktop widths, and that is a
// deliberate part of the design — a fix that left them permanently left-aligned
// would trade one visual bug for another. So this pins both halves: nothing
// overflows at any width, AND the links stay centred whenever they fit.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:govpulse/core/widgets/Home/nav/home_top_nav.dart';

/// The shell's real link set: Home · My Reports · Emergency. NewsFeed is gone —
/// Home's centre column is the feed — and Settings is reached from the user
/// chip rather than being a link.
const _shellItems = [
  (label: 'Home', index: 0),
  (label: 'My Reports', index: 1),
  (label: 'Emergency', index: 2),
];

/// [HomeTopNav.defaultItems] — one link longer, and what the two non-shell
/// callers still render. The wider set is the harder case, so it is swept too.
const _defaultItems = [
  (label: 'Home', index: 0),
  (label: 'My Reports', index: 1),
  (label: 'NewsFeed', index: 2),
  (label: 'Emergency', index: 3),
];

Widget _bar(List<({String label, int index})> items) => MaterialApp(
  debugShowCheckedModeBanner: false,
  home: Scaffold(
    body: Column(
      children: [
        HomeTopNav(
          currentIndex: 0,
          onTap: (_) {},
          items: items,
          settingsIndex: 3,
          notificationCount: 2,
          onNotificationTap: () {},
          onLogoutTap: () {},
          username: 'markreduca',
          fullName: 'Mark Reduca',
          verifStatus: 'verified',
        ),
        const Expanded(child: SizedBox.expand()),
      ],
    ),
  ),
);

/// Pumps the bar at [width] and [scale], returning any overflow it reported.
Future<List<String>> _overflowsAt(
  WidgetTester tester,
  double width,
  double scale,
  List<({String label, int index})> items,
) async {
  final errors = <String>[];
  final prev = FlutterError.onError;
  FlutterError.onError = (details) {
    final s = details.exceptionAsString();
    if (s.contains('overflowed') || s.contains('RenderFlex')) {
      errors.add(s.split('\n').first);
    } else {
      prev?.call(details);
    }
  };
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  try {
    await tester.pumpWidget(_bar(items));
    await tester.pump(const Duration(milliseconds: 400));
  } finally {
    FlutterError.onError = prev;
  }
  return errors.toSet().toList();
}

/// Browser windows people actually use, from a narrow split-screen up.
const _widths = <double>[820, 900, 1024, 1100, 1280, 1440, 1600, 1920];

/// 1.0 is the design size; 1.3 is Android's "Largest" and roughly a browser
/// zoom — the setting that breaks a bar that only just fitted.
const _scales = <double>[1.0, 1.15, 1.3];

void main() {
  testWidgets('the shell nav fits every window width and text size', (
    tester,
  ) async {
    final failures = <String>[];
    for (final width in _widths) {
      for (final scale in _scales) {
        for (final e in await _overflowsAt(tester, width, scale, _shellItems)) {
          failures.add('${width.toInt()}px @ ${scale}x — $e');
        }
      }
    }
    expect(failures, isEmpty, reason: '\n${failures.join('\n')}');
  });

  testWidgets('the four-link default set fits too', (tester) async {
    // The other two callers still render defaultItems, which is one link wider
    // and therefore the first to run out of room.
    final failures = <String>[];
    for (final width in _widths) {
      for (final scale in _scales) {
        for (final e in await _overflowsAt(
          tester,
          width,
          scale,
          _defaultItems,
        )) {
          failures.add('${width.toInt()}px @ ${scale}x — $e');
        }
      }
    }
    expect(failures, isEmpty, reason: '\n${failures.join('\n')}');
  });

  testWidgets('the links sit on the CONTENT midpoint and never move', (
    tester,
  ) async {
    // ── Two bugs, one assertion ─────────────────────────────────────────────
    //
    // 1. MOVEMENT. The bar used to be a single Row — brand, links in an
    //    `Expanded`, then the bell and profile chip — so the links were centred
    //    in the space LEFT OVER. That space changes after first paint: the chip
    //    renders the citizen's full name, which arrives asynchronously after
    //    login, so the chip grows and the links jump. Measured at 1920 before
    //    the fix: x=790.5 while loading, x=717.7 once the name landed. A 73px
    //    lurch on every page open.
    //
    // 2. ALIGNMENT. Centring them on the WINDOW then looked wrong for a
    //    different reason: the shell's rails are 288 and 340, so the centre
    //    column's midpoint is 26px left of the window's. Links centred on the
    //    viewport are 26px off from the feed they head, and at a glance the nav
    //    reads as crooked. `linksOffset` moves them onto the content.
    //
    // Both halves are asserted, since either alone is satisfiable by a wrong
    // layout: ON the content midpoint, and the SAME across every state the bar
    // passes through on the way to loaded.
    const leftRail = 288.0;
    const rightRail = 340.0;
    const offset = (leftRail - rightRail) / 2;

    for (final width in const [1024.0, 1280.0, 1440.0, 1920.0]) {
      final positions = <String, double>{};

      // The states in the order a citizen meets them, plus a long name as the
      // stress case — a chip wide enough to have shoved the links hardest.
      const states = <(String, String?, int)>[
        ('loading', null, 0),
        ('named', 'Mark Reduca', 0),
        ('named + badge', 'Mark Reduca', 2),
        ('long name', 'Bartolome Villanueva-Maglalang', 12),
      ];

      for (final (label, fullName, count) in states) {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: Column(
                children: [
                  HomeTopNav(
                    currentIndex: 0,
                    onTap: (_) {},
                    items: _shellItems,
                    settingsIndex: 3,
                    notificationCount: count,
                    onNotificationTap: () {},
                    onLogoutTap: () {},
                    username: fullName == null ? '' : 'markreduca',
                    fullName: fullName,
                    verifStatus: fullName == null ? '' : 'verified',
                    linksOffset: offset,
                  ),
                  // The shell's real shape below the bar, so "the content
                  // midpoint" is a thing this test can actually measure rather
                  // than a number copied from the layout.
                  const Expanded(
                    child: Row(
                      children: [
                        SizedBox(width: leftRail),
                        Expanded(child: SizedBox.expand()),
                        SizedBox(width: rightRail),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));

        final home = tester.getRect(find.text('Home'));
        final emergency = tester.getRect(find.text('Emergency'));
        positions[label] = (home.left + emergency.right) / 2;
      }

      final contentMid = (leftRail + (width - rightRail)) / 2;
      for (final entry in positions.entries) {
        expect(
          entry.value,
          closeTo(contentMid, 1.0),
          reason:
              'at ${width.toInt()}px in the "${entry.key}" state the links must '
              'sit over the CENTRE COLUMN, not over the middle of the window — '
              'the rails are not the same width, so those are 26px apart',
        );
      }

      final distinct = positions.values
          .map((v) => v.toStringAsFixed(1))
          .toSet();
      expect(
        distinct,
        hasLength(1),
        reason:
            'at ${width.toInt()}px the links must land in the SAME place in '
            'every state — the profile name arriving after login is what used '
            'to shove them: $positions',
      );
    }
  });

  testWidgets('with no rails the links centre on the window', (tester) async {
    // linksOffset defaults to 0, and that default is load-bearing: this widget
    // is NOT web-only. `resolveNavBand` returns topNav for any device at least
    // 900 wide with a shortest side of at least 600, so the MOBILE app builds
    // it on a tablet — an iPad in landscape lands here. There are no rails
    // there, so the content IS the window and the links must not be nudged.
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_bar(_shellItems));
    await tester.pump(const Duration(milliseconds: 400));

    final home = tester.getRect(find.text('Home'));
    final emergency = tester.getRect(find.text('Emergency'));
    expect(
      (home.left + emergency.right) / 2,
      closeTo(1024 / 2, 1.0),
      reason: 'no rails means no offset — the tablet layout must not move',
    );
  });

  testWidgets('the offset tracks the layout across every shell band', (
    tester,
  ) async {
    // ── The half a constant would get wrong ─────────────────────────────────
    // The nudge is not a fixed 26px. The shell drops the RIGHT SIDEBAR below
    // 1280 (kShellThreeColumnMin) while keeping the left rail, and with only
    // one rail the centre column's midpoint moves the other way — the offset
    // swings from -26 to +144. A hard-coded value would line the nav up on a
    // desktop and leave it 170px out in the 920–1280 band, which is an ordinary
    // laptop window.
    //
    // The shell derives it from the rails it actually rendered, so this sweeps
    // both bands and both text scales and asserts the links land over the
    // centre column in all of them.
    const leftRail = 288.0;
    const rightRail = 340.0;

    for (final width in const [920.0, 960.0, 1024.0, 1279.0, 1280.0, 1920.0]) {
      // Mirrors shellHasRightSidebar: three columns only at/above 1280.
      final rw = width >= 1280 ? rightRail : 0.0;
      final offset = (leftRail - rw) / 2;
      final contentMid = (leftRail + (width - rw)) / 2;

      for (final scale in const [1.0, 1.3]) {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1.0;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: Column(
                children: [
                  HomeTopNav(
                    currentIndex: 0,
                    onTap: (_) {},
                    items: _shellItems,
                    settingsIndex: 3,
                    notificationCount: 2,
                    onNotificationTap: () {},
                    onLogoutTap: () {},
                    username: 'markreduca',
                    fullName: 'Mark Reduca',
                    verifStatus: 'verified',
                    linksOffset: offset,
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        const SizedBox(width: leftRail),
                        const Expanded(child: SizedBox.expand()),
                        SizedBox(width: rw),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));

        final home = tester.getRect(find.text('Home'));
        final emergency = tester.getRect(find.text('Emergency'));

        expect(
          (home.left + emergency.right) / 2,
          closeTo(contentMid, 1.0),
          reason:
              'at ${width.toInt()}px @ ${scale}x the links must sit over the '
              'centre column — the offset is ${offset.toStringAsFixed(0)} in '
              'this band, not a constant',
        );
        // And the nudge must never push a link off the bar.
        expect(
          home.left,
          greaterThan(0),
          reason: 'the first link stays on the bar at ${width.toInt()}px',
        );
        expect(
          emergency.right,
          lessThan(width),
          reason: 'the last link stays on the bar at ${width.toInt()}px',
        );
      }
    }
  });

  testWidgets('every link is still reachable at 1024', (tester) async {
    // The width the bug was reported at. Overflowing is not just cosmetic
    // there: the links were pushed under the profile chip, so the LAST one —
    // Emergency, the one that matters most — could not be clicked.
    tester.view.physicalSize = const Size(1024, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var tapped = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              HomeTopNav(
                currentIndex: 0,
                onTap: (i) => tapped = i,
                items: _shellItems,
                settingsIndex: 3,
                notificationCount: 2,
                onNotificationTap: () {},
                onLogoutTap: () {},
                username: 'markreduca',
                fullName: 'Mark Reduca',
                verifStatus: 'verified',
              ),
              const Expanded(child: SizedBox.expand()),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('Emergency'), warnIfMissed: false);
    await tester.pump();

    expect(
      tapped,
      2,
      reason:
          'Emergency is the last link and the first to be pushed off — it has '
          'to be hittable at the width the bug was reported at',
    );
  });
}
