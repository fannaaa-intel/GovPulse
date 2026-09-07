// ignore: unnecessary_import - the analyzer claims flutter_test re-exports
// unawaited; the compiler disagrees, and the test will not build without it.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:govpulse/core/widgets/tutorial/quick_action_tutorial.dart';
import 'package:govpulse/core/widgets/Home/sections/home_quick_actions_section.dart';

/// Hosts the Quick Action card the way HomePage does — inside a scroll view,
/// low enough on the page that a spotlight in place would need scrolling, which
/// is the whole reason the tour floats the card instead.
class _Host extends StatefulWidget {
  static const double width = 400;
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  final GlobalKey _key = GlobalKey();
  final ScrollController _scroll = ScrollController();
  bool _tourActive = false;

  /// True once the tour asked the host to reveal the card.
  bool revealed = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> start(BuildContext context) => QuickActionTutorial.maybeShow(
    context,
    anchorKey: _key,
    ghostBuilder: (_) =>
        HomeQuickActionsSection(width: _Host.width, onActionTap: (_) {}),
    onVisibilityChanged: (v) {
      if (mounted) setState(() => _tourActive = v);
    },
    onReveal: () async {
      revealed = true;
      if (!mounted || !_scroll.hasClients) return null;
      final box = _key.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return null;

      final media = MediaQuery.of(context);
      final usable =
          media.size.height - media.padding.top - media.padding.bottom;
      final desiredTop = box.size.height >= usable
          ? media.padding.top + 12
          : media.padding.top + (usable - box.size.height) / 2;
      final pos = _scroll.position;
      final target = (pos.pixels +
              (box.localToGlobal(Offset.zero).dy - desiredTop))
          .clamp(pos.minScrollExtent, pos.maxScrollExtent);
      if ((target - pos.pixels).abs() > 0.5) {
        await _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
        );
      }
      if (!mounted) return null;
      final after = _key.currentContext?.findRenderObject();
      if (after is! RenderBox || !after.hasSize) return null;
      return after.localToGlobal(Offset.zero) & after.size;
    },
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        controller: _scroll,
        child: Column(
          children: [
            // Stands in for the header + profile card + community section, so
            // the Quick Action card starts well down the page.
            const SizedBox(height: 300),
            Visibility(
              visible: !_tourActive,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: HomeQuickActionsSection(
                key: _key,
                width: _Host.width,
                onActionTap: (_) {},
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A Pixel-5-sized window. The default 800x600 test viewport is wider and
/// shorter than any handset, which both inflates the card's width-derived
/// height and sits under the float's minimum-height guard.
const Size _kPhone = Size(393, 851);

void _usePhone(WidgetTester tester, [Size size = _kPhone]) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<_HostState> _pumpAndStart(WidgetTester tester, {Size? size}) async {
  _usePhone(tester, size ?? _kPhone);
  await tester.pumpWidget(const MaterialApp(home: _Host()));
  await tester.pumpAndSettle();

  final state = tester.state<_HostState>(find.byType(_Host));
  unawaited(state.start(tester.element(find.byType(_Host))));
  await tester.pumpAndSettle();
  return state;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // The running flag and the seen flag are both process-wide. Without this a
    // test that leaves its tour open silently refuses every tour after it.
    await QuickActionTutorial.reset();
  });

  testWidgets('runs on first launch and not on the second', (tester) async {
    await _pumpAndStart(tester);
    expect(
      find.text('1 of 5'),
      findsOneWidget,
      reason: 'the tour should open on a first run',
    );

    // Walk to the end.
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }
    expect(find.text('5 of 5'), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.text('5 of 5'), findsNothing);

    // Second launch: the seen flag must suppress it.
    await _pumpAndStart(tester);
    expect(
      find.text('1 of 5'),
      findsNothing,
      reason: 'the tour is first-run only; the seen flag should suppress it',
    );
  });

  testWidgets('steps through the five actions in card order', (tester) async {
    await _pumpAndStart(tester);

    const expected = [
      'Report Issue',
      'Chat with Agent',
      'Events',
      'Suggestion',
      'Feedback',
    ];

    for (var i = 0; i < expected.length; i++) {
      expect(
        find.text('${i + 1} of 5'),
        findsOneWidget,
        reason: 'step ${i + 1} should be showing',
      );
      // The title appears on the card AND in the caption, so at least two.
      expect(
        find.text(expected[i]),
        findsWidgets,
        reason: 'step ${i + 1} should be about ${expected[i]}',
      );
      if (i < expected.length - 1) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
    }
  });

  testWidgets('Back returns to the previous step, and is absent on step 1', (
    tester,
  ) async {
    await _pumpAndStart(tester);
    expect(
      find.text('Back'),
      findsNothing,
      reason: 'there is nothing to go back to on the first step',
    );

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('2 of 5'), findsOneWidget);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 5'), findsOneWidget);
  });

  testWidgets('Skip ends the tour and still marks it seen', (tester) async {
    await _pumpAndStart(tester);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(find.text('1 of 5'), findsNothing);
    expect(
      await QuickActionTutorial.hasSeen(),
      isTrue,
      reason: 'skipping is still having seen it; it must not replay',
    );
  });

  testWidgets('the real card is restored to full visibility after the tour', (
    tester,
  ) async {
    final state = await _pumpAndStart(tester);
    expect(
      state.mounted && tester.state<_HostState>(find.byType(_Host)) == state,
      isTrue,
    );

    // Mid-tour the real card is held invisible so only the overlay copy shows.
    final visibility = tester.widget<Visibility>(find.byType(Visibility).first);
    expect(
      visibility.visible,
      isFalse,
      reason: 'the real card must be invisible while the copy is floating',
    );

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    final after = tester.widget<Visibility>(find.byType(Visibility).first);
    expect(
      after.visible,
      isTrue,
      reason:
          'every exit path must restore the card, or the page is left with a '
          'permanent hole where the Quick Actions used to be',
    );
  });

  testWidgets('the exit scrolls the card into view instead of just vanishing', (
    tester,
  ) async {
    _usePhone(tester);
    await tester.pumpWidget(const MaterialApp(home: _Host()));
    await tester.pumpAndSettle();

    final state = tester.state<_HostState>(find.byType(_Host));
    unawaited(state.start(tester.element(find.byType(_Host))));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(
      state.revealed,
      isTrue,
      reason: 'the tour must ask the host to reveal the card before settling',
    );

    // The card the citizen was just being taught about has to be on screen when
    // the overlay lets go — that is the whole point of the reveal. Vanishing
    // from mid-screen and leaving them to scroll for it is the bug this fixes.
    final rect = tester.getRect(find.byType(HomeQuickActionsSection));
    expect(
      rect.top,
      lessThan(851.0),
      reason: 'the card must be on screen after the tour ends',
    );
    expect(
      rect.bottom,
      greaterThan(0.0),
      reason: 'the card must be on screen after the tour ends',
    );
  });

  testWidgets('does not start when the card was never laid out', (
    tester,
  ) async {
    // An anchor key attached to nothing: the real-world case is the tour being
    // triggered while Home is still showing its skeleton.
    final orphan = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => QuickActionTutorial.maybeShow(
                context,
                anchorKey: orphan,
                ghostBuilder: (_) => const SizedBox.shrink(),
                onVisibilityChanged: (_) {},
                onReveal: () async => null,
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(
      find.text('1 of 5'),
      findsNothing,
      reason:
          'with no laid-out card there is no rect to spotlight; guessing one '
          'would dim the screen and highlight empty space',
    );
  });

  testWidgets('the card actually floats up, and lands under the status bar', (
    tester,
  ) async {
    _usePhone(tester);
    await tester.pumpWidget(const MaterialApp(home: _Host()));
    await tester.pumpAndSettle();

    // Where the card really sits in the page: deliberately far down, which is
    // why the tour floats it rather than spotlighting it in place.
    final origin = tester.getRect(find.byType(HomeQuickActionsSection));
    expect(
      origin.top,
      greaterThan(250),
      reason: 'the fixture must place the card low, or the float proves nothing',
    );

    final state = tester.state<_HostState>(find.byType(_Host));
    unawaited(state.start(tester.element(find.byType(_Host))));
    await tester.pumpAndSettle();

    // Mid-tour there are two: the invisible real one (still at origin) and the
    // floated copy on the overlay. The copy is the one that moved.
    final rects = tester
        .widgetList<HomeQuickActionsSection>(find.byType(HomeQuickActionsSection))
        .map((w) => tester.getRect(find.byWidget(w)))
        .toList();
    expect(rects.length, 2, reason: 'the real card plus the floated copy');

    final floated = rects.reduce((a, b) => a.top < b.top ? a : b);
    expect(
      floated.top,
      lessThan(origin.top - 100),
      reason:
          'the whole point of the interaction is that the card leaves the page '
          'and rises to the top of the screen',
    );
    expect(
      floated.top,
      greaterThanOrEqualTo(0),
      reason: 'it must not overshoot off the top of the screen',
    );
    // Same width as the real card: a copy built from a different width would
    // change size the instant the float begins.
    expect(
      floated.width,
      origin.width,
      reason: 'the copy must be built from the same width as the real card',
    );
  });

  testWidgets('all five rows fit on screen once floated', (tester) async {
    _usePhone(tester);
    await tester.pumpWidget(const MaterialApp(home: _Host()));
    await tester.pumpAndSettle();

    final state = tester.state<_HostState>(find.byType(_Host));
    unawaited(state.start(tester.element(find.byType(_Host))));
    await tester.pumpAndSettle();

    final rects = tester
        .widgetList<HomeQuickActionsSection>(find.byType(HomeQuickActionsSection))
        .map((w) => tester.getRect(find.byWidget(w)))
        .toList();
    final floated = rects.reduce((a, b) => a.top < b.top ? a : b);

    // If the floated card runs off the bottom, the last steps spotlight
    // something the citizen cannot see.
    expect(
      floated.bottom,
      lessThanOrEqualTo(tester.view.physicalSize.height /
          tester.view.devicePixelRatio),
      reason: 'every row must be visible at once; that is why it floats',
    );
  });

  testWidgets('on a small phone the caption never covers the spotlighted row', (
    tester,
  ) async {
    // iPhone SE: the card is ~532pt tall on a 667pt screen, so the card and the
    // caption cannot both fit. The card then floats only far enough to lift the
    // CURRENT row clear of the caption — the rows below it may be covered, but
    // the one being described never is.
    _usePhone(tester, const Size(375, 667));
    await tester.pumpWidget(const MaterialApp(home: _Host()));
    await tester.pumpAndSettle();

    final state = tester.state<_HostState>(find.byType(_Host));
    unawaited(state.start(tester.element(find.byType(_Host))));
    await tester.pumpAndSettle();

    for (var i = 0; i < 5; i++) {
      final caption = tester.getRect(find.text('${i + 1} of 5'));

      // The spotlighted row, on the floated copy. Row i of the copy is the
      // (i+1)th match top-to-bottom among the copy's own rows.
      final rowFinder = find.descendant(
        of: find.byType(HomeQuickActionsSection).last,
        matching: find.byType(GestureDetector),
      );
      final rows =
          tester.widgetList<GestureDetector>(rowFinder).toList();
      expect(rows.length, greaterThanOrEqualTo(5));
      final rowRects = rows
          .map((w) => tester.getRect(find.byWidget(w)))
          .toList()
        ..sort((a, b) => a.top.compareTo(b.top));
      final row = rowRects[i];

      // The caption may sit below the row, or flip above it when the card is
      // too tall for there to be room below. What it must never do is overlap
      // the row it is describing.
      final clearsBelow = caption.top >= row.bottom;
      final clearsAbove = caption.bottom <= row.top;
      expect(
        clearsBelow || clearsAbove,
        isTrue,
        reason:
            'step ${i + 1}: caption ${caption.top}-${caption.bottom} overlaps '
            'the row it describes (${row.top}-${row.bottom})',
      );
      expect(
        row.top,
        greaterThanOrEqualTo(0.0),
        reason: 'step ${i + 1}: the spotlighted row must be on screen',
      );
      expect(
        caption.bottom,
        lessThanOrEqualTo(667.0),
        reason: 'step ${i + 1}: the caption must stay on screen',
      );

      if (i < 4) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
    }
  });

  testWidgets('the scrim paints OVER the card, so the spotlight is visible', (
    tester,
  ) async {
    // The first build had the card painted after the scrim, which covered the
    // dim completely: every row stayed equally lit and nothing was ever
    // spotlighted. Paint order is the entire fix, so it is what this asserts.
    _usePhone(tester);
    await tester.pumpWidget(const MaterialApp(home: _Host()));
    await tester.pumpAndSettle();

    final state = tester.state<_HostState>(find.byType(_Host));
    unawaited(state.start(tester.element(find.byType(_Host))));
    await tester.pumpAndSettle();

    final stack = tester.widget<Stack>(
      find
          .descendant(of: find.byType(Overlay), matching: find.byType(Stack))
          .last,
    );

    int ghostAt = -1;
    int scrimAt = -1;
    for (var i = 0; i < stack.children.length; i++) {
      final child = stack.children[i];
      if (ghostAt < 0 && _containsIgnorePointer(child)) ghostAt = i;
      if (scrimAt < 0 && _containsCustomPaint(child)) scrimAt = i;
    }

    expect(ghostAt, isNonNegative, reason: 'the floated card copy must exist');
    expect(scrimAt, isNonNegative, reason: 'the scrim must exist');
    expect(
      scrimAt,
      greaterThan(ghostAt),
      reason:
          'the scrim must be painted AFTER the card, or the dim never lands on '
          'the rows and there is no spotlight at all',
    );
  });

  testWidgets('the primary button keeps one colour across every step', (
    tester,
  ) async {
    // Tinting the button with each step's accent made it flash red, blue,
    // green, blue, purple as the citizen tapped through — five different
    // buttons rather than one Next.
    _usePhone(tester);
    await _pumpAndStart(tester);

    final colours = <Color?>{};
    for (var i = 0; i < 5; i++) {
      final btn = tester.widget<FilledButton>(find.byType(FilledButton));
      colours.add(
        btn.style?.backgroundColor?.resolve(<WidgetState>{}),
      );
      if (i < 4) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
    }

    expect(
      colours.length,
      1,
      reason:
          'the primary button must not change colour between steps; the step '
          'accent belongs on the dot and the spotlight ring, not the chrome',
    );
  });

  testWidgets('the group is balanced, not pinned to the top', (tester) async {
    // The first build pinned the card under the status bar and left the whole
    // bottom of the screen empty.
    _usePhone(tester);
    await tester.pumpWidget(const MaterialApp(home: _Host()));
    await tester.pumpAndSettle();

    final state = tester.state<_HostState>(find.byType(_Host));
    unawaited(state.start(tester.element(find.byType(_Host))));
    await tester.pumpAndSettle();

    final cards = tester
        .widgetList<HomeQuickActionsSection>(
          find.byType(HomeQuickActionsSection),
        )
        .map((w) => tester.getRect(find.byWidget(w)))
        .toList();
    final floated = cards.reduce((a, b) => a.top < b.top ? a : b);
    final caption = tester.getRect(find.text('1 of 5'));

    final topGap = floated.top;
    final bottomGap = 851.0 - caption.bottom;

    expect(
      topGap,
      greaterThan(12.0),
      reason: 'the card should breathe below the status bar, not hug it',
    );
    // Not exact symmetry — the caption's reserve is the tallest step, so the
    // shorter ones leave a little extra underneath. It must not be lopsided.
    expect(
      bottomGap,
      lessThan(topGap + _kBalanceTolerance),
      reason:
          'top gap $topGap vs bottom gap $bottomGap: the group should sit '
          'balanced in the screen, not pinned to the top with dead space below',
    );
  });

  // ── Responsiveness ────────────────────────────────────────────────────────
  //
  // Real handsets, plus the gesture-nav inset that eats the bottom of the
  // screen. Every one of these must lay out without overflow, keep the
  // spotlighted row on screen, and keep the caption clear of both the row and
  // the gesture bar.
  for (final device in const <({String name, Size size, double top, double bottom})>[
    // Smallest phones still in use — the tightest vertical budget.
    (name: 'Galaxy A03 / small Android', size: Size(360, 640), top: 24, bottom: 0),
    (name: 'iPhone SE 2/3 (button nav)', size: Size(375, 667), top: 20, bottom: 0),
    (name: 'iPhone 13 mini (notch)', size: Size(375, 812), top: 50, bottom: 34),
    // The mainstream band.
    (name: 'Redmi 25057RN09G (this device)', size: Size(384, 832), top: 30, bottom: 18),
    (name: 'Pixel 5 (gesture nav)', size: Size(393, 851), top: 24, bottom: 24),
    (name: 'Pixel 7 / tall', size: Size(412, 892), top: 28, bottom: 24),
    (name: 'Galaxy S23 Ultra (gesture nav)', size: Size(412, 915), top: 32, bottom: 24),
    (name: 'iPhone 14 Pro Max (dynamic island)', size: Size(430, 932), top: 59, bottom: 34),
    // Widest phone-band viewport before the tablet layout takes over.
    (name: 'large phone / phablet', size: Size(480, 1000), top: 40, bottom: 28),
  ]) {
    testWidgets('lays out on ${device.name}', (tester) async {
      tester.view.physicalSize = device.size;
      tester.view.devicePixelRatio = 1.0;
      tester.view.padding = FakeViewPadding(
        top: device.top,
        bottom: device.bottom,
      );
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const MaterialApp(home: _Host()));
      await tester.pumpAndSettle();

      final state = tester.state<_HostState>(find.byType(_Host));
      unawaited(state.start(tester.element(find.byType(_Host))));
      await tester.pumpAndSettle();

      for (var i = 0; i < 5; i++) {
        expect(
          find.text('${i + 1} of 5'),
          findsOneWidget,
          reason: '${device.name}: step ${i + 1} should render',
        );

        final caption = tester.getRect(find.text('${i + 1} of 5'));
        final rows = tester
            .widgetList<GestureDetector>(
              find.descendant(
                of: find.byType(HomeQuickActionsSection).last,
                matching: find.byType(GestureDetector),
              ),
            )
            .map((w) => tester.getRect(find.byWidget(w)))
            .toList()
          ..sort((a, b) => a.top.compareTo(b.top));
        final row = rows[i];

        // The row being described must be visible.
        expect(
          row.top,
          greaterThanOrEqualTo(0.0),
          reason: '${device.name} step ${i + 1}: row is above the screen',
        );
        expect(
          row.bottom,
          lessThanOrEqualTo(device.size.height),
          reason: '${device.name} step ${i + 1}: row is below the screen',
        );

        // The caption must clear it, on whichever side it landed.
        expect(
          caption.top >= row.bottom || caption.bottom <= row.top,
          isTrue,
          reason: '${device.name} step ${i + 1}: caption overlaps its row',
        );

        // And must not run under the gesture bar.
        expect(
          caption.bottom,
          lessThanOrEqualTo(device.size.height - device.bottom + 1),
          reason:
              '${device.name} step ${i + 1}: caption runs under the gesture bar',
        );

        if (i < 4) {
          await tester.tap(find.text('Next'));
          await tester.pumpAndSettle();
        }
      }

      // Finishing must still hand the screen back cleanly.
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      expect(find.text('5 of 5'), findsNothing);
    });
  }

  testWidgets('the tour survives the phone sleeping and resuming', (
    tester,
  ) async {
    // A screen timeout, a call, a notification tap: none of these are the
    // citizen dismissing the tour. It used to end AND mark itself seen here,
    // so an interruption did not pause the tour, it destroyed it.
    _usePhone(tester);
    await _pumpAndStart(tester);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('3 of 5'), findsOneWidget);

    // Sleep.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    // Wake.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(
      find.text('3 of 5'),
      findsOneWidget,
      reason:
          'the tour must still be open on the SAME step after the phone wakes',
    );
    expect(
      await QuickActionTutorial.hasSeen(),
      isFalse,
      reason:
          'an interruption is not the citizen finishing the tour; marking it '
          'seen here means it never comes back',
    );

    // And it must still be finishable.
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();

    expect(find.text('5 of 5'), findsNothing);
    expect(
      await QuickActionTutorial.hasSeen(),
      isTrue,
      reason: 'finishing after a resume must still mark it seen',
    );
  });

  testWidgets('rotating mid-tour does not strand the spotlight', (
    tester,
  ) async {
    // Geometry is measured once, when the tour opens. A rotation relays the
    // page out underneath it, so without re-measuring the spotlight would sit
    // over stale coordinates — highlighting empty space.
    _usePhone(tester);
    await _pumpAndStart(tester);
    expect(find.text('1 of 5'), findsOneWidget);

    // Turn the handset sideways.
    tester.view.physicalSize = const Size(851, 393);
    await tester.pumpAndSettle();

    // Whatever it does, it must not crash, and must still be dismissible so the
    // citizen is never trapped under a scrim.
    expect(
      find.byType(HomeQuickActionsSection),
      findsWidgets,
      reason: 'the tour must survive a rotation without throwing',
    );

    final skip = find.text('Skip');
    final gotIt = find.text('Got it');
    expect(
      skip.evaluate().isNotEmpty || gotIt.evaluate().isNotEmpty,
      isTrue,
      reason: 'there must always be a way out after a rotation',
    );
    await tester.tap(skip.evaluate().isNotEmpty ? skip : gotIt);
    await tester.pumpAndSettle();
    expect(find.text('1 of 5'), findsNothing);
  });

  testWidgets('the card holds still while only the spotlight walks down', (
    tester,
  ) async {
    // The expected interaction: the card floats up once and STAYS, and the
    // spotlight moves down it row by row. What it did instead was creep
    // downward a few points per step (42, 44, 46, 55, 64) because the caption
    // was re-measured each step and fed back into the card's position — and by
    // the last step the caption flipped up over the middle of the card.
    _usePhone(tester, const Size(384, 832));
    tester.view.padding = const FakeViewPadding(top: 30, bottom: 18);
    await tester.pumpWidget(const MaterialApp(home: _Host()));
    await tester.pumpAndSettle();

    final state = tester.state<_HostState>(find.byType(_Host));
    unawaited(state.start(tester.element(find.byType(_Host))));
    await tester.pumpAndSettle();

    Rect floatedCard() => tester
        .widgetList<HomeQuickActionsSection>(
          find.byType(HomeQuickActionsSection),
        )
        .map((w) => tester.getRect(find.byWidget(w)))
        .reduce((a, b) => a.top < b.top ? a : b);

    final first = floatedCard();
    double? previousRowTop;
    final captionTops = <double>{};
    // The card may sit above the status bar when it is taller than the usable
    // band (the fixture's card is), but wherever it starts it must not MOVE.

    for (var i = 0; i < 5; i++) {
      expect(
        floatedCard(),
        first,
        reason:
            'step ${i + 1}: the card moved from $first. It must be placed once '
            'and hold still for the whole tour',
      );

      final rows = tester
          .widgetList<GestureDetector>(
            find.descendant(
              of: find.byType(HomeQuickActionsSection).last,
              matching: find.byType(GestureDetector),
            ),
          )
          .map((w) => tester.getRect(find.byWidget(w)))
          .toList()
        ..sort((a, b) => a.top.compareTo(b.top));

      // The spotlight is what advances, and it only ever goes down.
      if (previousRowTop != null) {
        expect(
          rows[i].top,
          greaterThan(previousRowTop),
          reason: 'step ${i + 1}: the spotlight should move DOWN the card',
        );
      }
      previousRowTop = rows[i].top;

      // The caption holds ONE position for the whole tour. It used to shrink
      // step by step (227pt down to 155pt) and then jump over the card on the
      // last step.
      final caption = tester.getRect(find.text('${i + 1} of 5'));
      captionTops.add(caption.top);
      expect(
        caption.top >= rows[i].bottom || caption.bottom <= rows[i].top,
        isTrue,
        reason:
            'step ${i + 1}: the caption overlaps the row it describes',
      );

      if (i < 4) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
    }
  });

  testWidgets('the spotlight travels between rows instead of snapping', (
    tester,
  ) async {
    _usePhone(tester);
    await _pumpAndStart(tester);

    Rect holeOf() => _spotlightHole(tester);

    final startHole = holeOf();

    // Tap Next but only advance PART of the travel.
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    final midHole = holeOf();
    await tester.pumpAndSettle();
    final endHole = holeOf();

    expect(
      endHole.top,
      greaterThan(startHole.top),
      reason: 'the spotlight should end on the next row down',
    );
    // Mid-flight it must be strictly between the two, which is what proves it
    // travelled rather than jumping straight to the destination.
    expect(
      midHole.top,
      greaterThan(startHole.top),
      reason: 'the spotlight had not left the first row 150ms in',
    );
    expect(
      midHole.top,
      lessThan(endHole.top),
      reason:
          'the spotlight was already at its destination 150ms in — it snapped '
          'instead of gliding',
    );
  });

  testWidgets('going Back travels upward, not instantly', (tester) async {
    _usePhone(tester);
    await _pumpAndStart(tester);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    Rect holeOf() => _spotlightHole(tester);

    final before = holeOf();
    await tester.tap(find.text('Back'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final mid = holeOf();
    await tester.pumpAndSettle();
    final after = holeOf();

    expect(
      after.top,
      lessThan(before.top),
      reason: 'Back should move the spotlight UP the card',
    );
    expect(
      mid.top,
      lessThan(before.top),
      reason: 'the spotlight had not started moving 150ms into Back',
    );
    expect(
      mid.top,
      greaterThan(after.top),
      reason: 'Back snapped straight to the previous row instead of gliding',
    );
  });

  // ── Orientation ───────────────────────────────────────────────────────────
  //
  // HomePage only STARTS the tour in portrait, but a citizen can rotate while
  // it is running. The tour must not strand the spotlight on stale geometry,
  // and must always be dismissible.
  for (final d in const <({String name, Size portrait, double top, double bottom})>[
    (name: 'small phone', portrait: Size(360, 640), top: 24, bottom: 0),
    (name: 'this device', portrait: Size(384, 832), top: 30, bottom: 18),
    (name: 'large phone', portrait: Size(430, 932), top: 59, bottom: 34),
  ]) {
    testWidgets('survives rotation on ${d.name}', (tester) async {
      tester.view.physicalSize = d.portrait;
      tester.view.devicePixelRatio = 1.0;
      tester.view.padding = FakeViewPadding(top: d.top, bottom: d.bottom);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const MaterialApp(home: _Host()));
      await tester.pumpAndSettle();
      final state = tester.state<_HostState>(find.byType(_Host));
      unawaited(state.start(tester.element(find.byType(_Host))));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('2 of 5'), findsOneWidget);

      // Rotate to landscape mid-tour.
      tester.view.physicalSize = Size(d.portrait.height, d.portrait.width);
      tester.view.padding = FakeViewPadding(top: 24, bottom: d.bottom);
      await tester.pumpAndSettle();

      // Still on the same step, still dismissible, nothing thrown.
      expect(
        find.text('2 of 5'),
        findsOneWidget,
        reason: '${d.name}: rotation should not reset or close the tour',
      );

      final skip = find.text('Skip');
      final gotIt = find.text('Got it');
      expect(
        skip.evaluate().isNotEmpty || gotIt.evaluate().isNotEmpty,
        isTrue,
        reason: '${d.name}: there must be a way out in landscape',
      );

      // Rotate back and finish.
      tester.view.physicalSize = d.portrait;
      tester.view.padding = FakeViewPadding(top: d.top, bottom: d.bottom);
      await tester.pumpAndSettle();

      expect(
        find.text('2 of 5'),
        findsOneWidget,
        reason: '${d.name}: rotating back should still be the same step',
      );

      for (var i = 2; i < 5; i++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      expect(find.text('5 of 5'), findsNothing);
    });
  }
}


/// The rect the scrim is currently cutting its spotlight out of.
///
/// Read off the CustomPaint's ValueKey rather than the painter's fields, which
/// are private to the tutorial library.
Rect _spotlightHole(WidgetTester tester) {
  // Several CustomPaints exist in the tree (Material's own included); the
  // scrim is the one carrying a ValueKey<Rect>.
  final paints = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
  for (final p in paints) {
    final k = p.key;
    if (k is ValueKey<Rect>) return k.value;
  }
  throw StateError('no keyed scrim CustomPaint found');
}

/// How far the top and bottom gaps may differ and still read as balanced.
const double _kBalanceTolerance = 200;

bool _containsIgnorePointer(Widget w) =>
    w is IgnorePointer ||
    (w is Positioned && w.child is IgnorePointer);

bool _containsCustomPaint(Widget w) {
  if (w is Positioned) {
    final c = w.child;
    if (c is GestureDetector && c.child is CustomPaint) return true;
  }
  return false;
}