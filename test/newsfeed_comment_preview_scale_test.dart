// Pins the SIZE of the comment rows previewed under a feed post.
//
// A comment is the same object wherever it is drawn, so it should be the same
// size wherever it is drawn — and on the web it was not. The card's own layout
// base is 480 in the citizen shell at every breakpoint, while the thread those
// rows open into is pinned to `kThreadMetrics` (400). Feeding the preview rows
// the card width therefore drew every comment ~20% larger than the identical
// row in the comments sheet, and larger than the phone app draws it: the
// comment competed with the post above it instead of reading as a footnote.
//
// This is measured in pixels, which is exactly where a screenshot is useless —
// it cannot tell 12.8pt from 15.4pt, and it certainly cannot tell you that a
// tablet card and a desktop card resolved to the same number.
//
// The web branch is reached by passing `commentMetrics` rather than by running
// the suite in a browser: `kIsWeb` is a compile-time constant, so under the VM
// the web arithmetic is not merely false but absent. The rule itself is checked
// separately, as plain arithmetic, in the first group.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:govpulse/core/widgets/Home/Newsfeed/comment_item.dart';
import 'package:govpulse/core/widgets/Home/Newsfeed/newsfeed_post_card.dart';

Map<String, dynamic> _post() => {
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
  'imageCount': 0,
  'imageUrls': const <String>[],
  'likes': '1',
  'commentCount': 1,
  'comments': [
    {
      'id': 'c0',
      'author': 'Mark Reduca',
      'authorPhotoUrl': null,
      'authorPhotoPath': null,
      'text': 'Hello',
      'likes': 0,
      'timestamp': DateTime(2026, 8, 2),
      'replies': const <dynamic>[],
    },
  ],
};

/// Pumps the card at card-base [width]. [web] selects the branch of
/// [commentMetricsFor] under test, standing in for the platform constant.
Future<void> _pump(
  WidgetTester tester,
  double width, {
  required bool web,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          child: SingleChildScrollView(
            child: NewsfeedPostCard(
              width: width,
              commentMetrics: commentMetricsFor(width, web: web),
              post: _post(),
              isGuest: false,
              isLiked: false,
              isCommented: false,
              isExpanded: false,
              likedComments: const {},
              onToggleExpanded: () {},
              onToggleLike: () {},
              onToggleCommentLike: (_) {},
              onOpenComments: ({String? initialReplyTo}) {},
            ),
          ),
        ),
      ),
    ),
  );
}

double _fontSize(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style!.fontSize!;

/// The commenter's avatar. `buildAvatar` draws a plain [Container] with a
/// circular [BoxDecoration] — not a [CircleAvatar] — and the comment block is
/// the last thing in the card, so the last such circle is the one we want.
double _commentAvatar(WidgetTester tester) => tester
    .getSize(
      find
          .descendant(
            of: find.byType(NewsfeedPostCard),
            matching: find.byWidgetPredicate(
              (w) =>
                  w is Container &&
                  w.decoration is BoxDecoration &&
                  (w.decoration! as BoxDecoration).shape == BoxShape.circle,
            ),
          )
          .last,
    )
    .width;

void main() {
  // The sizes comment_item.dart derives from the fixed thread base. Spelled out
  // as the same `k * base` arithmetic the widget uses, so this breaks loudly if
  // the ratios move rather than silently tracking them.
  const nameSize = kThreadMetrics * 0.032;
  const bodySize = kThreadMetrics * 0.033;
  const avatarSize = kThreadMetrics * 0.085;

  group('the rule', () {
    test('web pins to the thread base, whatever the card is', () {
      expect(commentMetricsFor(360, web: true), kThreadMetrics);
      expect(commentMetricsFor(480, web: true), kThreadMetrics);
      expect(commentMetricsFor(600, web: true), kThreadMetrics);
    });

    test('mobile is left exactly as it was — the card width, untouched', () {
      expect(commentMetricsFor(390, web: false), 390);
      expect(commentMetricsFor(480, web: false), 480);
    });
  });

  group('web', () {
    testWidgets('preview comment is drawn at the thread base, not the card', (
      tester,
    ) async {
      // 480: what the citizen web shell hands the card at every breakpoint.
      await _pump(tester, 480, web: true);

      expect(_fontSize(tester, 'Mark Reduca'), moreOrLessEquals(nameSize));
      expect(_fontSize(tester, 'Hello'), moreOrLessEquals(bodySize));
      expect(
        _commentAvatar(tester),
        moreOrLessEquals(avatarSize, epsilon: 0.5),
      );

      // ...while the POST keeps scaling with the card it is drawn in. If this
      // ever collapses onto the comment base, the fix has leaked past the
      // comment block and shrunk the post with it.
      expect(_fontSize(tester, 'Test Ing'), moreOrLessEquals(480 * 0.045));
    });

    testWidgets('identical on a phone browser, a tablet and a desktop', (
      tester,
    ) async {
      // Nothing about the viewport may reach the comment rows, so a narrow
      // phone-browser column and a roomy desktop card must agree exactly.
      for (final width in <double>[360, 480, 600]) {
        await _pump(tester, width, web: true);
        expect(
          _fontSize(tester, 'Mark Reduca'),
          moreOrLessEquals(nameSize),
          reason: 'comment name moved at card width $width',
        );
        expect(
          _commentAvatar(tester),
          moreOrLessEquals(avatarSize, epsilon: 0.5),
          reason: 'comment avatar moved at card width $width',
        );
      }
    });

    testWidgets('the comment is smaller than it was before the fix', (
      tester,
    ) async {
      // The regression itself, stated as the inequality the screenshots showed:
      // at the shell's 480 the comment used to be sized off the card.
      await _pump(tester, 480, web: true);
      expect(_fontSize(tester, 'Mark Reduca'), lessThan(480 * 0.032));
    });
  });

  group('mobile', () {
    testWidgets('still sizes the comment off the card, as it always did', (
      tester,
    ) async {
      const phone = 390.0; // below the 480 clamp
      await _pump(tester, phone, web: false);

      expect(
        _fontSize(tester, 'Mark Reduca'),
        moreOrLessEquals(phone * 0.032),
      );
      expect(_fontSize(tester, 'Hello'), moreOrLessEquals(phone * 0.033));
      expect(
        _commentAvatar(tester),
        moreOrLessEquals(phone * 0.085, epsilon: 0.5),
      );
    });
  });
}
