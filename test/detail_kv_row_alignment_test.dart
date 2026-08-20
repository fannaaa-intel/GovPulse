// The id block at the top of every submission detail — "Status: <pill>", then
// ID / Date / Time. Twice now it has shipped with the two halves of a row out
// of line by a couple of pixels, which is small enough to pass every build and
// still be the first thing anyone notices. These tests measure the baselines
// the layout actually produces, so a regression fails here instead of in a
// screenshot.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/core/theme/app_colors.dart';
import 'package:govpulse/features/admin/widgets/admin_submission_ui.dart';
import 'package:govpulse/features/admin/widgets/report_detail_kit.dart';

/// Where [finder]'s text sits its alphabetic baseline, in screen coordinates.
double _baselineOf(WidgetTester tester, Finder finder) {
  // RenderBox.getDistanceToBaseline may only be called mid-layout, so re-lay
  // the paragraph's own span out at the width it was given and ask that.
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  final painter = TextPainter(
    text: paragraph.text,
    textDirection: paragraph.textDirection,
    textScaler: paragraph.textScaler,
    textAlign: paragraph.textAlign,
    maxLines: paragraph.maxLines,
  )..layout(maxWidth: paragraph.size.width);
  final within = painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
  return tester.getTopLeft(finder).dy + within;
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(child: SizedBox(width: 320, child: child)),
      ),
    ),
  );
}

void main() {
  testWidgets('label sits on the same baseline as a status pill', (
    tester,
  ) async {
    await _pump(
      tester,
      const DetailKvRow(
        label: 'Status',
        trailing: StatusPill(label: 'Resolved', color: AppColors.green),
      ),
    );

    expect(
      _baselineOf(tester, find.text('Status: ')),
      moreOrLessEquals(_baselineOf(tester, find.text('Resolved')), epsilon: 0.01),
    );
  });

  testWidgets('label sits on the same baseline as a plain value', (
    tester,
  ) async {
    await _pump(
      tester,
      const DetailKvRow(label: 'Date Reported', value: 'Jul 21, 2026'),
    );

    expect(
      _baselineOf(tester, find.text('Date Reported: ')),
      moreOrLessEquals(
        _baselineOf(tester, find.text('Jul 21, 2026')),
        epsilon: 0.01,
      ),
    );
  });

  testWidgets('label holds the first line when chips wrap', (tester) async {
    await _pump(
      tester,
      const DetailKvRow(
        label: 'Status',
        trailing: Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            StatusPill(label: 'In Progress', color: AppColors.orange),
            DetailOverdueChip(28),
          ],
        ),
      ),
    );

    expect(
      _baselineOf(tester, find.text('Status: ')),
      moreOrLessEquals(
        _baselineOf(tester, find.text('In Progress')),
        epsilon: 0.01,
      ),
    );
  });

  testWidgets('a pill keeps its own width instead of filling the row', (
    tester,
  ) async {
    await _pump(
      tester,
      const DetailKvRow(
        label: 'Status',
        trailing: StatusPill(label: 'New', color: AppColors.orange),
      ),
    );

    final pill = tester.getSize(
      find.ancestor(of: find.text('New'), matching: find.byType(Container)).first,
    );
    expect(pill.width, lessThan(120));
  });
}
