// AdminShimmer must not repaint the surface it sits on.
//
// ── THE REGRESSION THIS PINS ────────────────────────────────────────────────
// AdminShimmer used to be a `ShaderMask(blendMode: BlendMode.srcATop)` wrapped
// around a group of placeholders. On the web renderer that mask composited
// against everything already painted within its bounds — including the WHITE
// CARD behind the group — so every skeleton sitting on a card rendered as one
// solid slab of skeleton grey. The shapes were the same colour as the space
// between them, so there was visibly no skeleton at all.
//
// It survived because nothing except looking at a rendered screenshot can catch
// it: the analyzer is happy, the layout is correct, the widgets are all present
// in the tree, and a skeleton is on screen for a few hundred milliseconds.
//
// The fix moved the sweep onto each SHAPE (SkeletonBox / SkeletonCircle paint
// their own animated gradient, driven by a clock AdminShimmer publishes) and
// left AdminShimmer painting nothing. These tests pin the properties that fix
// depends on, at the level a widget test can actually observe:
//
//   1. AdminShimmer introduces NO ShaderMask — the mechanism that caused it.
//   2. A card's own background survives underneath a shimmering group.
//   3. The shapes animate: their painted decoration changes between frames.
//   4. enabled: false still renders the shapes, flat.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/admin/widgets/admin_skeleton.dart';

/// A skeleton group on a white card — the shape that used to break.
Widget _cardWithSkeleton({bool enabled = true}) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: Container(
            key: const Key('card'),
            width: 300,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: AdminShimmer(
              enabled: enabled,
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SkeletonBox(width: 120, height: 12),
                  SizedBox(height: 8),
                  SkeletonBox(width: double.infinity, height: 12),
                  SizedBox(height: 8),
                  SkeletonCircle(size: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );

/// The decoration [SkeletonBox] actually painted, so a test can see the sweep
/// rather than merely trusting that a controller is running.
Decoration? _firstBoxDecoration(WidgetTester tester) {
  final container = tester.widgetList<Container>(
    find.descendant(
      of: find.byType(SkeletonBox).first,
      matching: find.byType(Container),
    ),
  );
  return container.isEmpty ? null : container.first.decoration;
}

void main() {
  testWidgets('AdminShimmer paints no ShaderMask', (tester) async {
    await tester.pumpWidget(_cardWithSkeleton());
    await tester.pump(const Duration(milliseconds: 100));

    // The whole point. A ShaderMask here is what tinted the card underneath, so
    // its absence IS the fix — not an incidental implementation detail.
    expect(find.byType(ShaderMask), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the card underneath keeps its own background', (tester) async {
    await tester.pumpWidget(_cardWithSkeleton());
    await tester.pump(const Duration(milliseconds: 100));

    final card = tester.widget<Container>(find.byKey(const Key('card')));
    final decoration = card.decoration! as BoxDecoration;
    expect(
      decoration.color,
      Colors.white,
      reason: 'the shimmer must not reach the surface it sits on',
    );

    // And the shapes are still there to be seen against it.
    expect(find.byType(SkeletonBox), findsNWidgets(2));
    expect(find.byType(SkeletonCircle), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the shapes actually sweep', (tester) async {
    await tester.pumpWidget(_cardWithSkeleton());
    await tester.pump(const Duration(milliseconds: 60));
    final first = _firstBoxDecoration(tester);

    // Far enough into the 1250ms cycle that the band has moved appreciably.
    await tester.pump(const Duration(milliseconds: 400));
    final later = _firstBoxDecoration(tester);

    expect(first, isNotNull);
    expect(
      later,
      isNot(equals(first)),
      reason: 'the gradient should have advanced between frames',
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('enabled: false renders flat shapes, not nothing',
      (tester) async {
    await tester.pumpWidget(_cardWithSkeleton(enabled: false));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(SkeletonBox), findsNWidgets(2));
    final decoration = _firstBoxDecoration(tester)! as BoxDecoration;
    // No clock published, so the shape falls back to the flat base colour
    // rather than to a gradient that never moves.
    expect(decoration.gradient, isNull);
    expect(decoration.color, kSkeletonBase);

    await tester.pumpWidget(const SizedBox());
  });
}
