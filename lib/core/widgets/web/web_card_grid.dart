// lib/core/widgets/web/web_card_grid.dart
//
// A responsive card grid for the citizen WEB layouts. It tiles a list of
// cards into as many equal-width columns as fit the available width, so
// content fills a wide desktop band instead of stranding a single phone-width
// column in the middle of an empty page.
//
// It is only ever used inside the `wide` branch of a screen's body — phones and
// the mobile app never see it, so mobile rendering is unaffected.
//
//   WebCardGrid(
//     targetColumnWidth: 520,   // preferred per-card width
//     children: [ for (r in reports) _reportCard(r) ],
//   )

import 'package:flutter/widgets.dart';

class WebCardGrid extends StatelessWidget {
  final List<Widget> children;

  /// Preferred width of a single card. The grid fits `floor(width /
  /// targetColumnWidth)` columns (min 1, max [maxColumns]) then stretches each
  /// cell to divide the row evenly.
  final double targetColumnWidth;
  final double spacing;
  final double runSpacing;
  final int maxColumns;

  const WebCardGrid({
    super.key,
    required this.children,
    this.targetColumnWidth = 520,
    this.spacing = 20,
    this.runSpacing = 20,
    this.maxColumns = 3,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = (c.maxWidth / targetColumnWidth).floor().clamp(
          1,
          maxColumns,
        );
        if (cols <= 1) {
          // Single column — just stack, full width (no wasted Wrap math).
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1) SizedBox(height: runSpacing),
              ],
            ],
          );
        }
        final cellW = (c.maxWidth - spacing * (cols - 1)) / cols;

        // ── Explicit rows, not a Wrap ────────────────────────────────────────
        //
        // A `Wrap` gives every child its own height, so two cards side by side
        // ended wherever their own content ended: a card with a one-line
        // address finished well above its neighbour with a two-line one, and
        // the row's baseline came out ragged. It reads as cards that are not
        // quite aligned rather than as a grid.
        //
        // Rows built by hand fix that. [IntrinsicHeight] measures the tallest
        // card in the row and `CrossAxisAlignment.stretch` gives every card in
        // it that height, so a row's cards start and end together whatever is
        // inside them.
        //
        // The last row is PADDED to a full set of cells rather than centred or
        // stretched: three cards in a two-column grid must leave the fourth
        // slot empty and keep the third card the same width as the others.
        // Letting it stretch to the full band — which is what a bare Row would
        // do — is the other half of what looked wrong.
        final rows = <Widget>[];
        for (var start = 0; start < children.length; start += cols) {
          final end = (start + cols) < children.length
              ? start + cols
              : children.length;
          final row = children.sublist(start, end);
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < cols; i++) ...[
                    if (i > 0) SizedBox(width: spacing),
                    SizedBox(
                      width: cellW,
                      // The empty cells of a short last row hold the layout
                      // open; nothing is drawn in them.
                      child: i < row.length ? row[i] : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              rows[i],
              if (i < rows.length - 1) SizedBox(height: runSpacing),
            ],
          ],
        );
      },
    );
  }
}
