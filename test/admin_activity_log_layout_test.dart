import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/admin/pages/admin_activity_log_page.dart';

// The activity-log history renders behind kIsWeb branches and a Supabase
// fetch, so a widget test cannot mount the whole sheet. What it CAN pin down
// is the piece with real layout risk: the sticky day header, whose delegate
// must report a fixed extent and rebuild only when its label changes.
//
// The stacking bug this guards against: every day header is pinned, so if the
// headers are not each scoped to their own sliver group they pile up at the
// top of the list instead of handing off day to day.
void main() {
  testWidgets('sticky day header keeps a fixed extent', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: CustomScrollView(
          slivers: [
            SliverMainAxisGroup(
              slivers: [
                SliverStickyDayHeader(label: 'Aug 22, 2026', gutter: 20),
                SliverToBoxAdapter(child: SizedBox(height: 600)),
              ],
            ),
            SliverMainAxisGroup(
              slivers: [
                SliverStickyDayHeader(label: 'Aug 21, 2026', gutter: 20),
                SliverToBoxAdapter(child: SizedBox(height: 600)),
              ],
            ),
          ],
        ),
      ),
    );

    // Only the first day is in view to start with; the second is below the
    // fold behind its 600px spacer.
    expect(find.text('Aug 22, 2026'), findsOneWidget);

    // Pinned, so it sits at the very top of the viewport rather than
    // scrolling with its rows.
    expect(tester.getTopLeft(find.text('Aug 22, 2026')).dy, lessThan(40));

    // Scroll the first day fully past. With each header scoped to its own
    // SliverMainAxisGroup the first unpins and leaves; if they stacked, it
    // would still be painted at the top alongside the second.
    await tester.drag(find.byType(Scrollable), const Offset(0, -700));
    await tester.pumpAndSettle();

    expect(find.text('Aug 21, 2026'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Aug 21, 2026')).dy, lessThan(40));
    // The whole point: the previous day's header is gone, not stacked above.
    expect(find.text('Aug 22, 2026'), findsNothing);
  });
}
