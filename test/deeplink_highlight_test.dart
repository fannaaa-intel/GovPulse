// Behaviour of the shared deep-link highlight: a target row flashes on arrival,
// then the accent fades so nothing stays visually stuck.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/core/widgets/deeplink_highlight.dart';

/// Minimal list standing in for My Submissions / the admin consoles: same
/// mixin, same key + AnimatedContainer wiring.
class _Host extends StatefulWidget {
  final List<String> ids;
  final String? target;

  /// Mirrors the real pages, which call flashHighlightOnce from build on every
  /// rebuild rather than latching in initState.
  final bool viaBuild;
  const _Host({required this.ids, this.target, this.viaBuild = false});

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with DeepLinkHighlightMixin {
  @override
  void initState() {
    super.initState();
    if (widget.viaBuild) return;
    // Mirrors the real screens: flash once rows exist, not during initState.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => flashHighlight(widget.target));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.viaBuild) flashHighlightOnce(widget.target);
    return MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [
            for (final id in widget.ids)
              AnimatedContainer(
                key: highlightKey(id),
                duration: kHighlightFade,
                height: 80,
                decoration: isHighlighted(id)
                    ? highlightDecoration(radius: 12, accent: Colors.blue)
                    : const BoxDecoration(color: Colors.white),
                child: Text(id),
              ),
          ],
        ),
      ),
    );
  }
}

/// The decoration of the row displaying [id].
BoxDecoration? _decorationOf(WidgetTester tester, String id) {
  final c = tester.widget<AnimatedContainer>(
    find.ancestor(
      of: find.text(id),
      matching: find.byType(AnimatedContainer),
    ),
  );
  return c.decoration as BoxDecoration?;
}

bool _isFlashed(WidgetTester tester, String id) =>
    _decorationOf(tester, id)?.border != null;

void main() {
  group('flush rows vs floating cards', () {
    // A table row sits edge-to-edge inside AdminResultsCard, which is rounded
    // AND Clip.antiAlias. Giving it a radius/shadow makes the parent round its
    // corners and swallow the shadow — the highlight visibly fights the card.
    test('row decoration is flush: no radius, no shadow', () {
      final d = highlightRowDecoration(
        accent: Colors.blue,
        divider: const BorderSide(color: Colors.grey),
      );

      expect(d.borderRadius, isNull, reason: 'a flush row must not round');
      expect(d.boxShadow, isNull, reason: 'a flush row must not float');
      expect(d.color, kHighlightFill);
      // Left accent bar identifies the row; the divider keeps the table's line.
      expect((d.border as Border).left.color, Colors.blue);
      expect((d.border as Border).bottom.color, Colors.grey);
    });

    test('card decoration floats: keeps its radius and shadow', () {
      final d = highlightDecoration(radius: 12, accent: Colors.blue);

      expect(d.borderRadius, BorderRadius.circular(12));
      expect(d.boxShadow, isNotNull);
      expect(d.color, kHighlightFill);
    });
  });

  testWidgets('the target flashes, then the accent fades away', (tester) async {
    await tester.pumpWidget(const _Host(ids: ['a', 'b', 'c'], target: 'b'));
    await tester.pump(); // run the post-frame flash

    expect(_isFlashed(tester, 'b'), isTrue);
    expect(_isFlashed(tester, 'a'), isFalse,
        reason: 'only the target may flash');

    // Hold, then the accent clears on its own — the "disappear" half.
    await tester.pump(kHighlightHold);
    await tester.pumpAndSettle();
    expect(_isFlashed(tester, 'b'), isFalse);
  });

  testWidgets('no target means nothing flashes', (tester) async {
    await tester.pumpWidget(const _Host(ids: ['a', 'b']));
    await tester.pump();

    expect(_isFlashed(tester, 'a'), isFalse);
    expect(_isFlashed(tester, 'b'), isFalse);
  });

  testWidgets('an unknown target flashes nothing and still settles',
      (tester) async {
    await tester.pumpWidget(const _Host(ids: ['a'], target: 'nope'));
    await tester.pump();

    expect(_isFlashed(tester, 'a'), isFalse);
    // The hold timer must still resolve — a dangling id is "no row to flash",
    // never a stuck highlight or a pending timer.
    await tester.pump(kHighlightHold);
    await tester.pumpAndSettle();
  });

  group('flashHighlightOnce', () {
    testWidgets('rebuilds with the same target do not re-flash', (tester) async {
      await tester.pumpWidget(
        const _Host(ids: ['a', 'b'], target: 'a', viaBuild: true),
      );
      await tester.pump();
      expect(_isFlashed(tester, 'a'), isTrue);

      // Let the hold expire so the accent clears on its own.
      await tester.pump(kHighlightHold);
      await tester.pumpAndSettle();
      expect(_isFlashed(tester, 'a'), isFalse);

      // A plain rebuild (filter change, poll, refresh) must not flash again.
      await tester.pumpWidget(
        const _Host(ids: ['a', 'b'], target: 'a', viaBuild: true),
      );
      await tester.pump();
      expect(_isFlashed(tester, 'a'), isFalse,
          reason: 'the same target must flash only once');
    });

    testWidgets('a NEW target on an already-mounted page still flashes',
        (tester) async {
      // The regression: tapping a second notification while its destination is
      // already open. The page is updated, not remounted — initState never
      // re-runs — so a bool latch would swallow this forever.
      await tester.pumpWidget(
        const _Host(ids: ['a', 'b'], target: 'a', viaBuild: true),
      );
      await tester.pump();
      expect(_isFlashed(tester, 'a'), isTrue);

      await tester.pump(kHighlightHold);
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        const _Host(ids: ['a', 'b'], target: 'b', viaBuild: true),
      );
      await tester.pump();
      expect(_isFlashed(tester, 'b'), isTrue,
          reason: 'a different target must re-arm the one-shot');

      await tester.pump(kHighlightHold);
      await tester.pumpAndSettle();
    });
  });

  testWidgets('KNOWN LIMIT: re-requesting the SAME target does not re-flash',
      (tester) async {
    // Documents a real edge: tapping the same notification twice while its
    // destination tab is already open. The page can't distinguish "rebuilt with
    // the same id" (must not re-flash) from "asked again for the same id"
    // (arguably should) — both look identical as widget.highlightId.
    //
    // Accepted: the row is already on screen and was just flashed, so the cost
    // is a missing repeat animation, not lost information. Fixing it means
    // threading a per-request token through the shells; not worth it yet.
    await tester.pumpWidget(
      const _Host(ids: ['a', 'b'], target: 'a', viaBuild: true),
    );
    await tester.pump();
    expect(_isFlashed(tester, 'a'), isTrue);

    await tester.pump(kHighlightHold);
    await tester.pumpAndSettle();

    // Simulate a second tap on the same notification: same id requested again.
    tester.state<_HostState>(find.byType(_Host)).flashHighlightOnce('a');
    await tester.pump();
    expect(_isFlashed(tester, 'a'), isFalse,
        reason: 'documents current behaviour — change this test if fixed');
  });

  testWidgets('a second flash takes over and the first timer does not cancel it',
      (tester) async {
    await tester.pumpWidget(const _Host(ids: ['a', 'b'], target: 'a'));
    await tester.pump();
    expect(_isFlashed(tester, 'a'), isTrue);

    // Re-flash a different row midway through the first hold.
    await tester.pump(const Duration(milliseconds: 1000));
    final state = tester.state<_HostState>(find.byType(_Host));
    state.flashHighlight('b');
    await tester.pump();
    expect(_isFlashed(tester, 'b'), isTrue);
    expect(_isFlashed(tester, 'a'), isFalse);

    // The first row's stale timer fires here; 'b' must survive it.
    await tester.pump(const Duration(milliseconds: 1400));
    expect(_isFlashed(tester, 'b'), isTrue,
        reason: "the older row's timer must not clear the newer highlight");

    await tester.pump(kHighlightHold);
    await tester.pumpAndSettle();
    expect(_isFlashed(tester, 'b'), isFalse);
  });
}
