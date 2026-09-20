// The breakdown modal's close button must sit in the card's corner, the way
// Recent activity's does - not float in the middle of the header.
//
// Four rounds of screenshot review called this fixed while the X was still
// ~220px inside the card's right edge. Measured in a real browser: Recent
// activity puts its X 27px from the edge, the breakdown sheet put its own at
// 222px. By eye "somewhere over on the right" reads as placed, which is why
// this needs a number rather than another look.
//
// The cause was a flex split, and that is what this test pins. The header was
// `Flexible(title), pill, Spacer()`. A Flexible with the default loose fit
// still carries flex: 1, so it and the Spacer each took HALF the free space -
// the title kept its half and the close button was pushed inward by it. Only
// one flex child may own the slack.
//
// The modal branch needs kIsWeb and cannot be reached from a widget test, so
// this reproduces the header's flex arrangement directly. That is the part
// that broke, and it breaks the same way wherever it is hosted.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Builds a header Row in a fixed-width card and reports how far the close
  /// button's right edge sits from the card's.
  Future<double> gap(
    WidgetTester tester, {
    required bool groupTitleAndPill,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final title = Flexible(
      child: Text(
        'All reports',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
      ),
    );
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text('9'),
    );
    final close = IconButton(
      key: const ValueKey('close'),
      onPressed: () {},
      icon: const Icon(Icons.close_rounded, size: 20),
      visualDensity: VisualDensity.compact,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 680,
            child: Material(
              key: const ValueKey('card'),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 14, 14, 12),
                child: Row(
                  children: groupTitleAndPill
                      // The fix: title + pill are ONE flex child, no Spacer.
                      ? [
                          Expanded(
                            child: Row(
                              children: [
                                title,
                                const SizedBox(width: 8),
                                pill,
                              ],
                            ),
                          ),
                          close,
                        ]
                      // The bug: two flex children split the free space.
                      : [
                          title,
                          const SizedBox(width: 8),
                          pill,
                          const Spacer(),
                          close,
                        ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final card = tester.getRect(find.byKey(const ValueKey('card')));
    final x = tester.getRect(find.byKey(const ValueKey('close')));
    return card.right - x.right;
  }

  testWidgets('a Flexible title beside a Spacer pushes the X inward', (
    tester,
  ) async {
    // Documents the defect this test exists for: without the grouping, the X
    // lands far from the edge. If Flutter ever changes how loose Flexible and
    // Spacer share free space, this is the canary.
    expect(await gap(tester, groupTitleAndPill: false), greaterThan(80));
  });

  testWidgets('grouping the title and pill pins the X to the card corner', (
    tester,
  ) async {
    // Recent activity measures 27px in the browser; the IconButton's own
    // padding accounts for most of it. Anything under ~40 is in the corner.
    expect(await gap(tester, groupTitleAndPill: true), lessThan(40));
  });
}
