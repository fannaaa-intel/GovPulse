// lib/core/widgets/responsive_page.dart
//
// Wraps a standalone (non-nav) page body — detail screens, settings sub-pages,
// info/legal pages — so it centres into a readable fixed-width column on wide
// (tablet / desktop) viewports instead of stretching edge-to-edge.
//
// On any viewport at or below [maxWidth] it returns the child untouched, so
// phones and narrow tablets render exactly as before. On wider viewports it
// centres the body and clamps the MediaQuery width the child sees, which keeps
// each page's internal `width * 0.xx` sizing self-consistent and prevents
// horizontal overflow inside the narrower column.
//
//   return Scaffold(
//     body: ResponsivePageBody(
//       child: SafeArea(child: <existing column>),
//     ),
//   );

import 'package:flutter/widgets.dart';

class ResponsivePageBody extends StatelessWidget {
  final Widget child;

  /// Readable column width on wide screens. Defaults to a comfortable reading
  /// measure for text-heavy pages; forms can pass something narrower.
  final double maxWidth;

  const ResponsivePageBody({
    super.key,
    required this.child,
    this.maxWidth = 820,
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    if (mq.size.width <= maxWidth) return child;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        SizedBox(
          width: maxWidth,
          child: MediaQuery(
            data: mq.copyWith(size: Size(maxWidth, mq.size.height)),
            child: child,
          ),
        ),
        const Spacer(),
      ],
    );
  }
}
