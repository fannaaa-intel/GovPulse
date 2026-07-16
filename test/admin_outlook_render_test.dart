// Renders the real _NlpOutlook / _FocusCard widgets and reads back the copy an
// admin actually sees. The model-level tests prove the numbers; these prove the
// numbers reach the screen as sentences that say something.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/admin/pages/admin_overview_page.dart';
import 'package:govpulse/features/admin/providers/admin_dashboard_provider.dart';

final _notifier = AdminDashboardNotifier();
final _now = DateTime(2026, 7, 14, 12);
var _seq = 0;

Map<String, dynamic> _feedback(
  int rating,
  DateTime createdAt, {
  String office = "Mayor's Office",
  int? clarity,
}) =>
    {
      'id': 'fb-${_seq++}',
      'office_label': office,
      'service_name': 'Permits',
      'overall_rating': rating,
      'aspect_clarity': clarity,
      'comment': null,
      'created_at': createdAt.toIso8601String(),
    };

/// Pumps the predictive-outlook panel and returns every string on screen
/// joined, so tests assert on the copy rather than on widget structure.
///
/// Rendered at the width the panel gets inside the dashboard's three-column
/// card. (The sibling sentiment/urgency panels are deliberately out of scope:
/// their fixed-width count/percent boxes overflow under the Ahem test font,
/// which is a test-environment artifact, not a real layout bug.)
Future<String> _render(WidgetTester tester, NlpInsights nlp) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(width: 440, child: nlpOutlookForTesting(nlp)),
        ),
      ),
    ),
  );
  await tester.pump();
  return tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? '')
      .join(' | ');
}

void main() {
  testWidgets('a single window explains itself instead of faking a forecast',
      (tester) async {
    final nlp = _notifier.analyseNlp(
      [
        _feedback(3, _now.subtract(const Duration(hours: 5))),
        _feedback(3, _now.subtract(const Duration(hours: 5))),
      ],
      const [],
      const [],
      null,
      _now,
    );

    final text = await _render(tester, nlp);

    expect(text, contains('Not enough data'));
    expect(text, contains('No forecast yet'));
    expect(text, isNot(contains('projected')),
        reason: 'nothing was projected, so nothing may claim to be');
  });

  testWidgets('a real forecast shows its basis', (tester) async {
    final nlp = _notifier.analyseNlp(
      [
        _feedback(4, _now.subtract(const Duration(days: 5))),
        _feedback(2, _now.subtract(const Duration(days: 45))),
      ],
      const [],
      const [],
      null,
      _now,
    );

    final text = await _render(tester, nlp);

    expect(text, contains('Improving'));
    expect(text, contains('projected'));
    // The "why" line: the arithmetic, the evidence, and the caveats.
    expect(text, contains('Carries the +2.0★ change'));
    expect(text, contains('1 recent and 1 prior rated response'));
    expect(text, contains('Capped at the 1–5★ scale'), reason: '4+2=6 → 5.0');
    expect(text, contains('Small sample'));
  });

  testWidgets('focus names the office and the citizen suggestion',
      (tester) async {
    final nlp = _notifier.analyseNlp(
      [
        _feedback(5, _now.subtract(const Duration(days: 1)),
            office: "Mayor's Office", clarity: 5),
        _feedback(1, _now.subtract(const Duration(days: 1)),
            office: 'Municipal Health Office', clarity: 1),
      ],
      const [],
      [
        {
          'id': 's1',
          'category': 'infrastructure',
          'category_other': null,
          'created_at': _now.toIso8601String(),
        },
        {
          'id': 's2',
          'category': 'infrastructure',
          'category_other': null,
          'created_at': _now.toIso8601String(),
        },
      ],
      null,
      _now,
    );

    final text = await _render(tester, nlp);

    // Was "Process clarity · 2.5★" with no office. Now it says where.
    expect(text, contains('Process clarity'));
    expect(text, contains('Municipal Health Office · 1 response'));
    expect(text, contains('checklists at Municipal Health Office'));

    // Suggestions now reach the panel at all.
    expect(text, contains('Infrastructure'));
    expect(text, contains('2 suggestions'));
    expect(text, contains('On-device'));
  });

  // The panel sits in a Row under IntrinsicHeight, which can hand it marginally
  // less height than it measured. It must absorb that rather than throw.
  //
  // Worth pinning because the first attempt at this was a ClipRect, which looks
  // like a fix and is not: it clips the PAINT, while the Column underneath is
  // still laid out against the short constraint and still throws. Only giving
  // the Column unbounded height actually prevents the overflow, so this test
  // fails against a ClipRect and passes against the scroll view.
  // Heights are chosen to actually BIND: this panel's content runs ~200–250px
  // at 440 wide, so anything above that constrains nothing and would pass
  // against the broken code too.
  group('survives a height constraint shorter than its content', () {
    for (final h in [200.0, 150.0, 100.0]) {
      testWidgets('at ${h.toInt()}px tall', (tester) async {
        final nlp = _notifier.analyseNlp(
          [
            _feedback(2, _now.subtract(const Duration(days: 3))),
            _feedback(3, _now.subtract(const Duration(days: 40))),
          ],
          const [],
          const [],
          null,
          _now,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 440,
                  height: h,
                  child: nlpOutlookForTesting(nlp),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
      });
    }
  });
}
