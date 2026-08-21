// Pins the SIZE of a post in the feed — the avatar, the author line, the
// "1w Ago" meta, the title and the body.
//
// The feed hands the card a metrics base, not a layout width: the card fills
// whatever column it is given, and every `width * 0.0xx` inside it is a
// proportion of that base. The web feed used to pin the base to the literal
// 480 — `kUiScaleMaxWidth`, the ceiling of the PHONE scale — so a post always
// drew at the largest phone size that exists. On a phone browser, where the
// viewport is ~411, that is ~17% bigger than the same post in the app; on a
// desktop the card sits in a 600px column and grew relative to nothing at all.
//
// `kFeedMetrics` replaces that ceiling with a phone-sized base, so the browser
// renders the app's proportions rather than an inflated copy of them.
//
// Pixels are exactly where a screenshot is useless — it cannot tell 18pt from
// 21.6pt, and it certainly cannot tell you a tablet and a desktop resolved to
// the same number. The web branch is reached by passing `web:` rather than by
// running in a browser: `kIsWeb` is a compile-time constant, so under the VM
// the web arithmetic is absent rather than false.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:govpulse/core/theme/mobile_metrics.dart';
import 'package:govpulse/core/widgets/Home/Newsfeed/news_feed_helpers.dart'
    show formatTimeAgo;
import 'package:govpulse/core/widgets/Home/Newsfeed/newsfeed_post_card.dart';

/// What the feed used to pass on web — `kUiScaleMaxWidth` as a literal.
const double _oldWebBase = 480.0;

/// A week old, relative to whenever the suite runs. The meta line is built by
/// [formatTimeAgo], so the label is derived rather than hardcoded — a literal
/// "1w Ago" would rot the moment the clock moved past the fixture date.
final DateTime _ts = DateTime.now().subtract(const Duration(days: 7));
final String _meta = formatTimeAgo(_ts);

Map<String, dynamic> _post() => {
  'id': 'p1',
  'author': 'LGU Aparri',
  'authorPhotoUrl': null,
  'authorPhotoPath': null,
  'blankAvatar': false,
  'isOfficial': true,
  'authorDept': '',
  'barangay': '',
  'tag': 'LGU Aparri',
  'tagColor': const Color(0xFF0D47A1),
  'timestamp': _ts,
  'title': 'Test Ing',
  'body': 'This is a test',
  'imageCount': 0,
  'imageUrls': const <String>[],
  'likes': '1',
  'commentCount': 0,
  'comments': const <dynamic>[],
};

Future<void> _pump(WidgetTester tester, double base) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          // Deliberately WIDER than the base: the desktop feed column is 600px
          // while the base is a phone number, and the card must not care.
          width: 600,
          child: SingleChildScrollView(
            child: NewsfeedPostCard(
              width: base,
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

/// Resolves [feedMetrics] against a viewport of [size], via a real MediaQuery.
Future<double> _metricsAt(
  WidgetTester tester,
  Size size, {
  required bool web,
}) async {
  late double result;
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: size),
      child: Builder(
        builder: (context) {
          result = feedMetrics(context, web: web);
          return const SizedBox();
        },
      ),
    ),
  );
  return result;
}

void main() {
  group('the rule', () {
    // Portrait viewports, where `uiScaleWidth` reads the same number on both
    // platforms (it takes the shortest side off-web and the width on web), so
    // these cases mean under the VM exactly what they mean in a browser.
    testWidgets('every browser above phone width settles on one base', (
      tester,
    ) async {
      for (final size in const [
        Size(480, 1000), // a roomy phone browser
        Size(768, 1024), // tablet
        Size(1440, 900), // desktop
      ]) {
        expect(
          await _metricsAt(tester, size, web: true),
          kFeedMetrics,
          reason: 'viewport $size did not settle on the phone base',
        );
      }
    });

    testWidgets('a browser narrower than the base stays proportional', (
      tester,
    ) async {
      // Below 400 the app itself is proportional to the screen, so web must be
      // too — clamping UP would make a small phone browser render bigger.
      expect(await _metricsAt(tester, const Size(360, 800), web: true), 360);
    });

    testWidgets('mobile is the untouched phone scale', (tester) async {
      for (final size in const [Size(390, 844), Size(411, 914)]) {
        expect(
          await _metricsAt(tester, size, web: false),
          uiScaleWidthOf(size),
          reason: 'mobile base moved at $size',
        );
      }
    });

    test('the web base is smaller than the ceiling it replaced', () {
      expect(kFeedMetrics, lessThan(kUiScaleMaxWidth));
      expect(kFeedMetrics, lessThan(_oldWebBase));
    });
  });

  group('web post chrome', () {
    // The five things named as too big, each pinned to the ratio the widget
    // applies, so this breaks loudly if a ratio moves rather than tracking it.
    testWidgets('avatar, author, meta, title and body all come down', (
      tester,
    ) async {
      await _pump(tester, kFeedMetrics);

      expect(
        _fontSize(tester, 'LGU Aparri'),
        moreOrLessEquals(kFeedMetrics * 0.038),
      );
      expect(
        _fontSize(tester, _meta),
        moreOrLessEquals(kFeedMetrics * 0.028),
      );
      expect(
        _fontSize(tester, 'Test Ing'),
        moreOrLessEquals(kFeedMetrics * 0.045),
      );
      expect(
        _fontSize(tester, 'This is a test'),
        moreOrLessEquals(kFeedMetrics * 0.034),
      );

      // ...and every one of them is strictly smaller than the old 480 base.
      expect(_fontSize(tester, 'LGU Aparri'), lessThan(_oldWebBase * 0.038));
      expect(_fontSize(tester, _meta), lessThan(_oldWebBase * 0.028));
      expect(_fontSize(tester, 'Test Ing'), lessThan(_oldWebBase * 0.045));
      expect(
        _fontSize(tester, 'This is a test'),
        lessThan(_oldWebBase * 0.034),
      );
    });

    testWidgets('the author logo is sized off the base, not the column', (
      tester,
    ) async {
      await _pump(tester, kFeedMetrics);

      // The header avatar is the first circle in the card.
      final avatar = tester
          .getSize(
            find
                .descendant(
                  of: find.byType(NewsfeedPostCard),
                  matching: find.byWidgetPredicate(
                    (w) =>
                        w is Container &&
                        w.decoration is BoxDecoration &&
                        (w.decoration! as BoxDecoration).shape ==
                            BoxShape.circle,
                  ),
                )
                .first,
          )
          .width;

      expect(avatar, moreOrLessEquals(kFeedMetrics * 0.105, epsilon: 0.5));
      expect(avatar, lessThan(_oldWebBase * 0.105));
    });

    testWidgets('the card still fills its column at the smaller base', (
      tester,
    ) async {
      // The base is proportions only. If it ever became the layout width, a
      // 400-base card would strand 200px of the 600px desktop column.
      await _pump(tester, kFeedMetrics);
      expect(tester.getSize(find.byType(NewsfeedPostCard)).width, 600);
    });
  });

  group('mobile post chrome', () {
    testWidgets('unchanged — still proportional to the phone', (tester) async {
      const phone = 390.0;
      await _pump(tester, phone);

      expect(_fontSize(tester, 'LGU Aparri'), moreOrLessEquals(phone * 0.038));
      expect(_fontSize(tester, _meta), moreOrLessEquals(phone * 0.028));
      expect(_fontSize(tester, 'Test Ing'), moreOrLessEquals(phone * 0.045));
      expect(
        _fontSize(tester, 'This is a test'),
        moreOrLessEquals(phone * 0.034),
      );
    });
  });
}
