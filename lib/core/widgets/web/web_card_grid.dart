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
        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: [
            for (final child in children) SizedBox(width: cellW, child: child),
          ],
        );
      },
    );
  }
}
