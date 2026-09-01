// Cards sitting side by side in the web grid must share a row's height.
//
// ── The bug ────────────────────────────────────────────────────────────────
// [WebCardGrid] tiled its cards with a `Wrap`, which gives every child its own
// height. So a report card with a one-line address finished well above its
// neighbour with a two-line one, and the row's bottom edge came out ragged —
// it read as cards that were not quite aligned rather than as a grid.
//
// A short last row was the other half of it: three cards in a two-column grid
// have to leave the fourth slot empty and keep the third card the same width as
// the rest, not let it stretch across the whole band.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:govpulse/core/widgets/web/web_card_grid.dart';

/// A card whose natural height depends on its content, like a real report card
/// with a one- or two-line address.
class _Card extends StatelessWidget {
  final String label;
  final int lines;
  const _Card({required this.label, required this.lines});

  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey(label),
    color: const Color(0xFFEEEEEE),
    padding: const EdgeInsets.all(12),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        for (var i = 0; i < lines; i++) const Text('address line'),
      ],
    ),
  );
}

Future<void> _pump(WidgetTester tester, double width, List<Widget> cards) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: WebCardGrid(targetColumnWidth: 380, children: cards),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Size _sizeOf(WidgetTester tester, String label) =>
    tester.getSize(find.byKey(ValueKey(label)));

void main() {
  testWidgets('cards in the same row end at the same height', (tester) async {
    // 816 wide at a 380 target gives two columns — the real band.
    await _pump(tester, 816, const [
      _Card(label: 'short', lines: 1),
      _Card(label: 'tall', lines: 3),
    ]);

    expect(
      _sizeOf(tester, 'short').height,
      _sizeOf(tester, 'tall').height,
      reason:
          'a Wrap gave each card its own height, so the row ended ragged — the '
          'thing that read as misaligned cards',
    );
  });

  testWidgets('a short last row keeps its cards at column width', (
    tester,
  ) async {
    // Three cards in two columns: the third sits alone on the second row and
    // must stay one column wide, with the empty slot beside it.
    await _pump(tester, 816, const [
      _Card(label: 'a', lines: 1),
      _Card(label: 'b', lines: 2),
      _Card(label: 'c', lines: 1),
    ]);

    final first = _sizeOf(tester, 'a').width;
    expect(
      _sizeOf(tester, 'c').width,
      first,
      reason:
          'the lone last card must not stretch across the band — it is one '
          'card in a grid, not a full-width row',
    );
    expect(
      first,
      lessThan(816 / 2 + 1),
      reason: 'two columns, so a card is about half the band',
    );
  });

  testWidgets('rows are independent — a tall row does not inflate a short one', (
    tester,
  ) async {
    await _pump(tester, 816, const [
      _Card(label: 'r1a', lines: 1),
      _Card(label: 'r1b', lines: 6),
      _Card(label: 'r2a', lines: 1),
      _Card(label: 'r2b', lines: 1),
    ]);

    // Row 1 is dragged up to its tall card; row 2 stays compact.
    expect(_sizeOf(tester, 'r1a').height, _sizeOf(tester, 'r1b').height);
    expect(_sizeOf(tester, 'r2a').height, _sizeOf(tester, 'r2b').height);
    expect(
      _sizeOf(tester, 'r2a').height,
      lessThan(_sizeOf(tester, 'r1a').height),
      reason:
          'equalising is per ROW; one long card must not pad out the whole grid',
    );
  });

  testWidgets('a single column still just stacks', (tester) async {
    // Below the two-column threshold the grid stacks full width, and there is
    // no row to equalise — a card is its own height, as it should be.
    await _pump(tester, 500, const [
      _Card(label: 'only1', lines: 1),
      _Card(label: 'only2', lines: 4),
    ]);

    expect(_sizeOf(tester, 'only1').width, 500);
    expect(
      _sizeOf(tester, 'only1').height,
      lessThan(_sizeOf(tester, 'only2').height),
    );
  });

  testWidgets('nothing overflows at any of the real band widths', (
    tester,
  ) async {
    for (final width in const [500.0, 760.0, 816.0, 1100.0]) {
      await _pump(tester, width, const [
        _Card(label: 'x1', lines: 1),
        _Card(label: 'x2', lines: 3),
        _Card(label: 'x3', lines: 2),
      ]);
      expect(
        tester.takeException(),
        isNull,
        reason: 'the grid must lay out cleanly at ${width.toInt()}px',
      );
    }
  });
}
