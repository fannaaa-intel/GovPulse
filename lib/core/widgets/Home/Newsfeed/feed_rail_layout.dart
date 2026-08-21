import 'package:flutter/material.dart';

import 'newsfeed_post_card.dart' show kFeedColumnMax;

/// The standalone web feed page's info rail, and the gap that separates it from
/// the feed column.
const double kFeedRailWidth = 300;
const double kFeedRailGap = 32;

/// The narrowest CONTENT box (i.e. after the page's own padding) that can hold
/// the feed column and the rail side by side.
///
/// The two used to be laid out as fixed boxes with nothing checking they fit:
/// 600 + 32 + 300 = 932 in a box that is only `viewport - 48` wide. The page
/// switches to this layout at a 900px viewport, so every window from 900 to
/// 979 overflowed its Row — a horizontal overflow stripe across the whole feed
/// on exactly the laptop widths a citizen is most likely to have.
///
/// [kFeedColumnMax] brings the pair to 812, which clears a 900px window with
/// room to spare, but the arithmetic is no longer left implicit: below this the
/// rail is dropped rather than crushed.
const double kFeedRailBelow = kFeedColumnMax + kFeedRailGap + kFeedRailWidth;

/// The standalone (guest) web feed: a centred feed column, with the info rail
/// beside it when the window can hold both.
///
/// Split out of `news_feed_screen.dart` so the medium-screen behaviour is
/// reachable from a widget test. The page only reaches that layout behind a
/// `kIsWeb && rawWidth >= 900` gate, and `kIsWeb` is a compile-time false under
/// the VM — so as an inline branch the overflow above was untestable, which is
/// a large part of why it survived. As a widget it is just a layout, and a test
/// can pump it at any width.
class FeedRailLayout extends StatelessWidget {
  const FeedRailLayout({super.key, required this.feed, required this.rail});

  final Widget feed;
  final Widget rail;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Never the viewport: this is the room left after the page's padding,
        // which is what the children actually have to fit inside.
        final bool showRail = constraints.maxWidth >= kFeedRailBelow;

        if (!showRail) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kFeedColumnMax),
              child: feed,
            ),
          );
        }

        return Row(
          // Pins the rail to the top; only the feed is tall.
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(width: kFeedColumnMax, child: feed),
            const SizedBox(width: kFeedRailGap),
            SizedBox(width: kFeedRailWidth, child: rail),
          ],
        );
      },
    );
  }
}
