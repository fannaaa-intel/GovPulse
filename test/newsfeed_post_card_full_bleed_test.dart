// Pins the two shapes of a feed post: the floating card, and the full-bleed
// slab the phone feed uses (Facebook's mobile treatment — no side margin, no
// rounded corners, media running to the screen edge).
//
// Worth a test rather than a screenshot because the difference is entirely
// geometry, and because full bleed is NOT "drop the padding": the text rows
// keep their gutter and only the media loses it, so the two shapes share every
// type size and every vertical rhythm. A screenshot cannot tell a 14px gutter
// from a 16px one; these cases can.
//
// The comment block is here for its own reason. Making the media full-bleed
// meant moving the padding off the card and onto the individual rows, and the
// comment preview went from N direct children of the card's column to one
// wrapped Column — so the rows and the hairline above them are exactly what a
// bad regroup would knock out of alignment.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:govpulse/core/widgets/Home/Newsfeed/newsfeed_post_card.dart';

const double _w = 390; // a phone width, below the 480 clamp
const double _gutter = _w * 0.035; // the card's own padding constant

Map<String, dynamic> _post({int comments = 0}) => {
  'id': 'p1',
  'author': 'LGU Aparri',
  'authorPhotoUrl': null,
  'authorPhotoPath': null,
  'blankAvatar': true,
  'isOfficial': true,
  'authorDept': '',
  'barangay': 'Macanaya',
  'tag': 'LGU Aparri',
  'tagColor': const Color(0xFF0D47A1),
  'timestamp': DateTime(2026, 8, 1),
  'title': 'Test Ing',
  'body': 'This is a test',
  'imageCount': 2,
  'imageUrls': const <String>[],
  'likes': '1',
  'commentCount': comments,
  'comments': [
    for (int i = 0; i < comments; i++)
      {
        'id': 'c$i',
        'author': 'Citizen',
        'authorPhotoUrl': null,
        'authorPhotoPath': null,
        'text': 'A comment',
        'likes': 0,
        'timestamp': DateTime(2026, 8, 2),
        'replies': const <dynamic>[],
      },
  ],
};

Future<void> _pump(
  WidgetTester tester, {
  required bool edgeToEdge,
  int comments = 0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: _w,
          child: SingleChildScrollView(
            child: NewsfeedPostCard(
              width: _w,
              post: _post(comments: comments),
              isGuest: false,
              isLiked: false,
              isCommented: false,
              isExpanded: false,
              likedComments: const {},
              onToggleExpanded: () {},
              onToggleLike: () {},
              onToggleCommentLike: (_) {},
              onOpenComments: ({String? initialReplyTo}) {},
              edgeToEdge: edgeToEdge,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Left edge of [finder] in the card's coordinate space.
double _left(WidgetTester tester, Finder finder) =>
    tester.getTopLeft(finder).dx -
    tester.getTopLeft(find.byType(NewsfeedPostCard)).dx;

double _right(WidgetTester tester, Finder finder) =>
    tester.getTopRight(find.byType(NewsfeedPostCard)).dx -
    tester.getTopRight(finder).dx;

BoxDecoration _slab(WidgetTester tester) =>
    tester
            .widget<Container>(
              find
                  .descendant(
                    of: find.byType(NewsfeedPostCard),
                    matching: find.byType(Container),
                  )
                  .first,
            )
            .decoration!
        as BoxDecoration;

void main() {
  group('full-bleed slab', () {
    testWidgets('spans the column and squares its corners', (tester) async {
      await _pump(tester, edgeToEdge: true);

      expect(tester.getSize(find.byType(NewsfeedPostCard)).width, _w);

      final d = _slab(tester);
      expect(d.borderRadius, isNull, reason: 'no rounded corners at the edge');
      expect(d.boxShadow, isNull, reason: 'a shadow on a full-width band');
      // Hairlines top and bottom only — there is no side left to draw.
      final border = d.border! as Border;
      expect(border.left, BorderSide.none);
      expect(border.right, BorderSide.none);
      expect(border.top.width, greaterThan(0));
      expect(border.bottom.width, greaterThan(0));
    });

    testWidgets('media runs edge to edge, text keeps its gutter', (
      tester,
    ) async {
      await _pump(tester, edgeToEdge: true);

      // The two-up image grid: outermost image cell starts at 0.
      final grid = find.byType(AspectRatio).first;
      expect(_left(tester, grid), moreOrLessEquals(0, epsilon: 0.5));

      // ...while the title is still inset by the card's own gutter.
      final title = find.text('Test Ing');
      expect(_left(tester, title), moreOrLessEquals(_gutter, epsilon: 0.5));
      expect(_right(tester, title), greaterThan(0));
    });

    testWidgets('comment rows and their hairline share the text gutter', (
      tester,
    ) async {
      await _pump(tester, edgeToEdge: true, comments: 2);

      expect(
        _left(tester, find.text('A comment').first),
        greaterThanOrEqualTo(_gutter),
      );

      // The divider above the comments is a bare 1px Container: it must still
      // stretch across the gutter box rather than collapse to nothing.
      final rule = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.constraints == BoxConstraints.tightFor(height: 1),
      );
      final ruleSize = tester.getSize(rule.first);
      expect(ruleSize.height, 1);
      expect(ruleSize.width, moreOrLessEquals(_w - 2 * _gutter, epsilon: 0.5));
    });
  });

  group('card (unchanged)', () {
    testWidgets('keeps its radius, shadow and four-sided border', (
      tester,
    ) async {
      await _pump(tester, edgeToEdge: false);

      final d = _slab(tester);
      expect(d.borderRadius, BorderRadius.circular(_w * 0.035));
      expect(d.boxShadow, isNotNull);
      final border = d.border! as Border;
      expect(border.left.width, greaterThan(0));
      expect(border.right.width, greaterThan(0));
    });

    testWidgets('media stays inside the padding', (tester) async {
      await _pump(tester, edgeToEdge: false);

      // +1 for the border the card draws on all four sides, which the
      // full-bleed slab does not have.
      const inset = _gutter + 1;
      final grid = find.byType(AspectRatio).first;
      expect(_left(tester, grid), moreOrLessEquals(inset, epsilon: 0.5));

      final title = find.text('Test Ing');
      expect(_left(tester, title), moreOrLessEquals(inset, epsilon: 0.5));
    });
  });
}
