// Drives the attachment grid's tile maths, shared by the Reports, Suggestions
// and Feedback detail panes. The galleries used to hardcode a 92px tile, which
// left a ragged gap at the right of the narrow details column and stayed small
// on a phone where there was room to be tappable.

import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/admin/widgets/admin_submission_ui.dart';

/// How many tiles of [tile] fit in [width] with a 10px gutter.
int _colsIn(double width, double tile, {double gap = 10}) =>
    ((width + gap) / (tile + gap)).floor();

void main() {
  group('tiles fill their row', () {
    // The widths the galleries actually run at, inside the pane + section
    // indent: the 38% details column of the 1120px web dialog, a stacked pane,
    // and a phone.
    for (final w in [322.0, 274.0, 640.0, 180.0]) {
      test('a ${w.toInt()}px row ends flush', () {
        final tile = attachmentTileSize(w);
        final cols = _colsIn(w, tile);
        expect(cols, greaterThanOrEqualTo(1));

        // The row it produces never exceeds the space it was given — an
        // overflowing Wrap would just push a tile to the next line, but the
        // maths shouldn't be the thing that puts it there.
        final used = cols * tile + (cols - 1) * 10;
        expect(used, lessThanOrEqualTo(w + 0.01));
      });
    }
  });

  test('a thumb stays tappable and never balloons', () {
    for (var w = 120.0; w <= 1200.0; w += 7) {
      final tile = attachmentTileSize(w);
      expect(tile, greaterThanOrEqualTo(84.0), reason: 'too small at ${w}px');
      expect(tile, lessThanOrEqualTo(116.0), reason: 'too big at ${w}px');
    }
  });

  test('a phone pane gets a bigger tile than the old fixed 92', () {
    // The whole point: on a narrow pane two tiles share the width rather than
    // sitting at 92 with a ragged gap beside them.
    expect(attachmentTileSize(274), greaterThan(92));
  });

  test('a degenerate row falls back rather than dividing by nothing', () {
    // An unbounded or zero-width row has nothing to divide — it must not
    // produce NaN/Infinity and blow up layout.
    expect(attachmentTileSize(double.infinity), 92);
    expect(attachmentTileSize(0), 92);
    expect(attachmentTileSize(-50), 92);
  });
}
