// Where the citizen shell's left rail starts, and whether the feed still fits
// beside it once it does.
//
// The band this pins used to be dead space. `kShellRailLabelsMin` was 1024, so
// everything from 900 to 1023 fell through to the drawer — and at a ~1000px
// window that meant a 680px feed column stranded in grey with both sides empty
// and no navigation on screen at all, while Facebook at the same width is
// showing its left sidebar beside the feed.
//
// Two things have to hold together for the lower threshold to be right, and
// they pull in opposite directions, which is exactly why they are pinned rather
// than eyeballed:
//
//   • the TOP NAV has to fit the window (it is full width, above the columns),
//     which is what stops the threshold going lower still; and
//   • the CENTRE COLUMN, which is the window minus the rail, has to stay usable
//     for the feed, which is what would break if the rail ever got wider.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:govpulse/core/widgets/Home/nav/nav_band.dart';
import 'package:govpulse/core/widgets/Home/Newsfeed/newsfeed_post_card.dart';
import 'package:govpulse/features/home/shell/citizen_shell.dart'
    show kCitizenRailWidth;

/// The measured width at which the top nav stops overflowing — brand + links +
/// bell + chip are clean from here, and overflow at exactly 900.
const double _topNavClean = 920;

/// The feed's own side padding inside the centre column (`_kWebFeedGutter`).
const double _feedGutter = 20;

/// A window of [width], tall enough that the shortest-side phone rule in
/// [resolveNavBand] does not claim it.
Size _window(double width) => Size(width, 900);

void main() {
  group('where the rail starts', () {
    test('a ~1000px window gets the rail, not an empty page', () {
      // The reported case, and the whole point of the change.
      expect(resolveShellLayout(_window(1004)), ShellLayout.railLabels);
    });

    test('the threshold is the top nav own clean point', () {
      expect(kShellRailLabelsMin, _topNavClean);
      expect(resolveShellLayout(_window(920)), ShellLayout.railLabels);
    });

    test('below it the shell still falls back, and never to bare icons', () {
      // 900..919 is left to the drawer. railIcons is what resolve() names it,
      // but citizen_shell renders that as the drawer — the icon-only rail was
      // dropped on purpose and this must not bring it back by widening its band
      // downward into territory the labelled rail cannot serve.
      expect(resolveShellLayout(_window(919)), ShellLayout.railIcons);
      expect(resolveShellLayout(_window(899)), ShellLayout.drawer);
    });

    test('the right sidebar is unchanged', () {
      expect(resolveShellLayout(_window(1280)), ShellLayout.threeColumn);
      expect(resolveShellLayout(_window(1279)), ShellLayout.railLabels);
    });

    test('a rotated handset is still a phone, however wide', () {
      // The shortest-side rule: 900+ of width on a short viewport is a phone on
      // its side, not a laptop, and must not get a three-column shell.
      expect(resolveShellLayout(const Size(932, 430)), ShellLayout.drawer);
    });
  });

  group('the feed fits beside it', () {
    /// The room the centre column has for feed content at a [window] wide
    /// enough to show the rail.
    double contentAt(double window) =>
        window - kCitizenRailWidth - _feedGutter * 2;

    test('the narrowest rail windows run the feed edge to edge', () {
      // The centre column, which is what the feed measures itself against —
      // the gutter is inside it and only exists in card mode.
      double columnAt(double window) => window - kCitizenRailWidth;

      // At the floor the column cannot hold the full measure, so the post fills
      // it rather than sitting as a card that cannot reach its own width. That
      // is the same rule a 600px window gets, applied to a column instead of a
      // screen — and it does mean the slab meets the rail with no grey between
      // them across this band, which is deliberate, not an oversight.
      expect(columnAt(kShellRailLabelsMin), lessThan(kPostCardFullBleedBelow));

      // Still a real column, not a sliver.
      expect(columnAt(kShellRailLabelsMin), greaterThan(kFeedMetrics));

      // The band is narrow: by ~970 the column holds the measure and the card
      // is back. Pinned so nobody widens it by accident.
      expect(columnAt(970), greaterThanOrEqualTo(kPostCardFullBleedBelow));
    });

    test('a ~1000px window is within a few px of the full Facebook column', () {
      // 1004 - 288 - 40 = 676 against a 680 cap: the feed is effectively at
      // full width here, which is why this band is worth showing the rail in
      // rather than leaving empty.
      expect(contentAt(1004), closeTo(kFeedColumnMax, 8));
    });

    test('the full column is reached before the third column arrives', () {
      // By the time the right sidebar appears the feed must long since have
      // stopped growing, or the third column would be taking room the feed
      // still wanted.
      expect(contentAt(kShellThreeColumnMin), greaterThan(kFeedColumnMax));
    });
  });
}
