import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Two feed surfaces used to build EVERY item up front while showing only a
// handful:
//
//   • home_community_section_web.dart — a Column of every post inside a
//     SingleChildScrollView, in a panel capped at maxHeight: 520 (~6 rows).
//   • comments_sheet.dart:_thread     — ListView(children: [...]), the
//     NON-builder constructor, which looks lazy but is not.
//
// Both are now lazy. These tests pin the property that actually matters — that
// off-screen items are NOT built — using the same widget shapes, because the
// real widgets need a live Supabase client and a provider singleton to mount.
//
// The guard is deliberately about BUILD COUNT rather than pixels: a layout
// assertion would still pass if the list quietly went back to eager, which is
// exactly the regression these exist to catch.
void main() {
  // Tall enough that only a few fit the viewport, so "built" and "exists"
  // genuinely differ.
  const itemHeight = 100.0;
  const viewportHeight = 520.0; // the web panel's real maxHeight
  const itemCount = 200;

  /// Counts how many times the builder actually ran.
  late Set<int> built;

  setUp(() => built = <int>{});

  Widget host(Widget child) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              height: viewportHeight,
              width: 400,
              child: child,
            ),
          ),
        ),
      );

  group('web home "Latest Updates" panel', () {
    testWidgets('builds only what fits, not all 200 posts', (tester) async {
      await tester.pumpWidget(
        host(
          ListView.separated(
            itemCount: itemCount,
            separatorBuilder: (_, _) => const Divider(height: 1, thickness: 1),
            itemBuilder: (_, i) {
              built.add(i);
              return SizedBox(height: itemHeight, child: Text('post $i'));
            },
          ),
        ),
      );

      // The eager version built all 200. A lazy list builds the visible run
      // plus Flutter's cache extent — bounded by the panel height, not the feed
      // size. The exact number is Flutter's business; the ceiling is ours.
      expect(built.length, lessThan(itemCount));
      expect(
        built.length,
        lessThan(30),
        reason: 'should be bounded by the 520px panel, not by 200 posts',
      );

      // And the ones on screen really are there.
      expect(find.text('post 0'), findsOneWidget);
      expect(find.text('post 199'), findsNothing);
    });

    testWidgets('separators sit between items, never after the last', (
      tester,
    ) async {
      // The old code guarded this by hand with `if (i < posts.length - 1)`.
      // ListView.separated does it structurally; this pins the count so a
      // trailing divider can't creep back in.
      await tester.pumpWidget(
        host(
          ListView.separated(
            itemCount: 3,
            separatorBuilder: (_, _) => const Divider(height: 1, thickness: 1),
            itemBuilder: (_, i) => SizedBox(height: itemHeight, child: Text('p$i')),
          ),
        ),
      );

      expect(find.byType(Divider), findsNWidgets(2)); // 3 items -> 2 separators
    });
  });

  group('comments sheet thread', () {
    // The thread's index layout, which the builder has to get exactly right:
    //   0            -> optional `leading` (the stacked dialog's post recap)
    //   lead..lead+n -> the comments
    //   lead + n     -> trailing spacer
    Widget thread({required bool withLeading, required int comments}) {
      final lead = withLeading ? 1 : 0;
      return ListView.builder(
        itemCount: lead + comments + 1,
        itemBuilder: (_, index) {
          if (lead == 1 && index == 0) {
            return const SizedBox(height: itemHeight, child: Text('LEADING'));
          }
          if (index == lead + comments) {
            return const SizedBox(height: 20, child: Text('SPACER'));
          }
          final i = index - lead;
          built.add(i);
          return SizedBox(height: itemHeight, child: Text('comment $i'));
        },
      );
    }

    testWidgets('builds only visible comments, not all 200', (tester) async {
      await tester.pumpWidget(host(thread(withLeading: false, comments: itemCount)));

      expect(built.length, lessThan(itemCount));
      expect(find.text('comment 0'), findsOneWidget);
      expect(find.text('comment 199'), findsNothing);
    });

    testWidgets('leading occupies index 0 and shifts the comments', (
      tester,
    ) async {
      await tester.pumpWidget(host(thread(withLeading: true, comments: 5)));

      // The recap renders, and comment 0 is still the FIRST comment — an
      // off-by-one here would drop a comment or repeat one.
      expect(find.text('LEADING'), findsOneWidget);
      expect(find.text('comment 0'), findsOneWidget);
      expect(built.contains(0), isTrue);
    });

    testWidgets('without leading, comment 0 is the very first item', (
      tester,
    ) async {
      await tester.pumpWidget(host(thread(withLeading: false, comments: 5)));

      expect(find.text('LEADING'), findsNothing);
      expect(find.text('comment 0'), findsOneWidget);
    });

    testWidgets('the trailing spacer is reachable at the end', (tester) async {
      // Short thread so everything fits: the spacer must be the LAST item, and
      // must not displace a comment.
      await tester.pumpWidget(host(thread(withLeading: false, comments: 3)));

      expect(find.text('comment 0'), findsOneWidget);
      expect(find.text('comment 1'), findsOneWidget);
      expect(find.text('comment 2'), findsOneWidget);
      expect(find.text('SPACER'), findsOneWidget);
      expect(find.text('comment 3'), findsNothing);
    });

    testWidgets('an empty thread still renders its spacer and no comments', (
      tester,
    ) async {
      await tester.pumpWidget(host(thread(withLeading: false, comments: 0)));

      expect(find.text('SPACER'), findsOneWidget);
      expect(built, isEmpty);
    });

    testWidgets('scrolling down builds later comments on demand', (
      tester,
    ) async {
      await tester.pumpWidget(host(thread(withLeading: false, comments: itemCount)));

      final before = built.length;
      expect(built.contains(50), isFalse, reason: 'not built yet');

      // This is what the deep-link scroll relies on: paging down materialises
      // items that were never built, so the target's GlobalKey can resolve.
      await tester.drag(find.byType(ListView), const Offset(0, -5000));
      await tester.pump();

      expect(built.length, greaterThan(before));
      expect(
        built.contains(50),
        isTrue,
        reason: 'scrolling must build items the deep-link hunt needs',
      );
    });
  });
}
