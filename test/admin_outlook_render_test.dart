// Renders the real _NlpOutlook / _FocusCard widgets and reads back the copy an
// admin actually sees. The model-level tests prove the numbers; these prove the
// numbers reach the screen as sentences that say something.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/admin/pages/admin_overview_page.dart';
import 'package:govpulse/features/admin/providers/admin_dashboard_provider.dart';

import '_responsive_matrix.dart';

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
Future<String> _render(
  WidgetTester tester,
  NlpInsights nlp, {
  Widget? widget,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: 440,
            child: widget ?? nlpOutlookForTesting(nlp),
          ),
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

  testWidgets('a regression forecast cites its weekly basis', (tester) async {
    // Three populated weeks → the fitted forecast, not the window fallback.
    final nlp = _notifier.analyseNlp(
      [
        _feedback(4, _now.subtract(const Duration(days: 2))),
        _feedback(3, _now.subtract(const Duration(days: 9))),
        _feedback(2, _now.subtract(const Duration(days: 16))),
      ],
      const [],
      const [],
      null,
      _now,
    );

    final text = await _render(tester, nlp);

    expect(text, contains('Improving'));
    expect(text, contains('projected'));
    expect(text, contains('Trend line fitted over 3 weekly averages'));
    expect(text, contains('3 rated responses'));
    expect(text, contains('Small sample'));
    expect(text, isNot(contains('Carries the')),
        reason: 'the fallback wording must not describe a fitted forecast');
  });

  // The recommended-focus block now renders in the "Needs your attention" card
  // at the top of the AI rail, not at the foot of the outlook panel. Same copy,
  // same guarantees — asserted through the card that owns it now.
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

    final text = await _render(tester, nlp, widget: needsAttentionForTesting(nlp));

    expect(text, contains('Needs your attention'));

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

  // ── Long AI metric must not overflow the focus card ────────────────────────
  //
  // `metric` is model output. The edge function clamps it, but rows already
  // cached in ai_dashboard_insights carry the OLD hard `.slice(0, 24)` strings,
  // so the client has to survive them on its own.
  //
  // The reported bug: the metric was a bare Text in a Row - unconstrained, so
  // it took whatever width it asked for and was then clipped by the card edge.
  // No ellipsis, cut mid-word ("1 recent complaint (docu"), which reads as a
  // broken layout rather than a shortened label. It showed on desktop AND on a
  // phone, so every width below has to stay clean.
  group('a long AI metric never overflows the focus card', () {
    // The exact strings from the report: 24 chars, cut mid-word by the server.
    Map<String, dynamic> aiInsight() => {
      'generated_at': _now.toIso8601String(),
      'summary': 'Overall service rating is moderate (3.5 stars).',
      'focus': [
        {
          'title': 'Document handling',
          'scope': 'Municipal Civil Registrar',
          'metric': '1 recent complaint (docu',
          'suggestion':
              'Create a centralized document receipt log and assign a staff '
              'member to verify and confirm each filing.',
          'severity': 'high',
          'target': 'feedback',
        },
        {
          'title': 'High-urgency reports',
          'scope': 'Sanja, Macanaya (Pescaria), Maura - 3 reports',
          'metric': '3 recent high-urgency re',
          'suggestion':
              'Deploy inspection teams to these barangays this week to '
              'address road and drainage hazards.',
          'severity': 'high',
          'target': 'reports',
        },
        {
          // A pathological single token with no space to break on.
          'title': 'Unbreakable token',
          'scope': null,
          'metric': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          'suggestion': 'Should still ellipsise rather than overflow.',
          'severity': 'medium',
          'target': null,
        },
      ],
    };

    // 320 is the tightest phone; 360/393 are the common ones; 440 is the
    // dashboard rail; 700 is the card inside a wide dialog.
    for (final w in [320.0, 360.0, 393.0, 440.0, 700.0]) {
      testWidgets('at ${w.toInt()}px wide', (tester) async {
        final nlp = _notifier.analyseNlp(
          [
            _feedback(2, _now.subtract(const Duration(days: 3))),
            _feedback(4, _now.subtract(const Duration(days: 10))),
          ],
          const [],
          const [],
          aiInsight(),
          _now,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: SizedBox(
                  width: w,
                  child: needsAttentionForTesting(nlp),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        // A RenderFlex overflow throws here. This is the assertion that fails
        // against the bare-Text version of the card.
        expect(
          tester.takeException(),
          isNull,
          reason: 'the focus card overflowed at ${w.toInt()}px',
        );
      });
    }

    testWidgets('the metric still renders and stays on one line', (
      tester,
    ) async {
      final nlp = _notifier.analyseNlp(
        [_feedback(2, _now.subtract(const Duration(days: 3)))],
        const [],
        const [],
        aiInsight(),
        _now,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 360,
                child: needsAttentionForTesting(nlp),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      // Clipping it away entirely would also "not overflow" - the text has to
      // actually be there, ellipsised rather than hidden.
      final metric = tester.widgetList<Text>(find.byType(Text)).firstWhere(
            (t) => (t.data ?? '').startsWith('1 recent complaint'),
            orElse: () => const Text('MISSING'),
          );
      expect(metric.data, isNot('MISSING'));
      expect(metric.maxLines, 1);
      expect(metric.overflow, TextOverflow.ellipsis);
    });
  });

  // ── A SHORT metric must sit flush against the card's right edge ────────────
  //
  // Separate bug from the overflow above, same Row. The title is `Expanded`
  // (flex: 1) and the metric was `Flexible` (ALSO flex: 1, because loose fit
  // still carries a flex). Two flex children split the leftover space 50/50,
  // so the metric got a box far wider than its text and `TextAlign.end`
  // aligned it inside THAT box - leaving a short metric like "2.75★" floating
  // mid-row with a visible gap to the card edge.
  //
  // The overflow tests above cannot catch this: a long metric fills its
  // oversized box, so it looks correct while the bug is still present. Only a
  // metric far shorter than 45% of the row exposes it.
  group('a short AI metric stays pinned to the card edge', () {
    Map<String, dynamic> shortMetricInsight() => {
      'generated_at': _now.toIso8601String(),
      'summary': 'Overall service rating is moderate (3.5★).',
      'focus': [
        {
          'title': 'Wait time',
          'scope': 'Municipal Civil Registrar · 4 responses',
          // The reported string: short enough that the split-slack gap shows.
          'metric': '2.75★',
          'suggestion':
              'Add an extra service window and display real-time queue '
              'estimates to reduce waiting time.',
          'severity': 'medium',
          'target': 'feedback',
        },
      ],
    };

    for (final w in [320.0, 360.0, 393.0, 440.0, 700.0]) {
      testWidgets('at ${w.toInt()}px wide', (tester) async {
        final nlp = _notifier.analyseNlp(
          [_feedback(2, _now.subtract(const Duration(days: 3)))],
          const [],
          const [],
          shortMetricInsight(),
          _now,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: SizedBox(
                  width: w,
                  child: needsAttentionForTesting(nlp),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);

        final metricFinder = find.text('2.75★');
        expect(metricFinder, findsOneWidget);

        // The focus row's tinted container is the metric's nearest ancestor
        // that draws the edge the metric must hug. Its padding is 11px, so a
        // correctly pinned metric ends 11px inside the container's right edge.
        final metricRight = tester.getBottomRight(metricFinder).dx;
        final cardRight = tester
            .getBottomRight(
              find
                  .ancestor(
                    of: metricFinder,
                    matching: find.byType(Container),
                  )
                  .first,
            )
            .dx;

        // Against the split-slack version this gap was ~a quarter of the row
        // (tens of px). Allowing 1px absorbs text-layout rounding only.
        expect(
          cardRight - metricRight,
          lessThanOrEqualTo(12.0),
          reason:
              'the metric floated ${(cardRight - metricRight).toStringAsFixed(1)}px '
              'short of the card edge at ${w.toInt()}px - a second flex child '
              'is splitting the row\'s slack',
        );
      });
    }
  });

  // ── Hostile content at large text, every phone ────────────────────────────
  //
  // The two groups above feed the card the strings from the bug report, which
  // are the GENTLE case: short scopes, no Tagalog, 1.0x text. `scope` and
  // `suggestion` are free text that a model writes from DB rows, so the real
  // worst case is a long barangay list at Android's largest font size.
  //
  // Sweeping realistic-worst content rather than a convenient fixture is what
  // surfaced a bare Column in a Row over in the events detail screen - a row
  // that looked clean at 1.0x could never wrap its text. The gentler fixture
  // never reached it.
  //
  // `pumpAt` is used rather than a hand-rolled pump because it sets the scale
  // on the VIEW: MaterialApp inserts its own MediaQuery.fromView, so a
  // textScaler wrapped around the app is dropped and every scale silently
  // re-tests 1.0. It also tears the tree down between sizes, because a
  // RenderFlex reports an overflow only the first time it paints one.
  group('the focus card survives hostile content at large text', () {
    // Every field at its realistic worst: a long Tagalog-length title, the
    // multi-barangay scope the AI actually emits, a full-length suggestion,
    // and a metric at the server clamp's 24-char ceiling.
    Map<String, dynamic> hostileInsight() => {
      'generated_at': _now.toIso8601String(),
      'summary':
          'Overall service rating is moderate (3.5★); document handling and '
          'wait-time at the Municipal Civil Registrar need immediate '
          'attention, while rising high-urgency reports in three barangays '
          'pose a safety risk to residents and commuters alike.',
      'focus': [
        {
          'title': 'Mabagal na pagproseso ng dokumento',
          'scope':
              'Sanja, Macanaya (Pescaria), Maura, Punta, Toran, '
              'Paruddun Norte, Bisagu · 14 reports',
          'metric': '12 recent high-urgency…',
          'suggestion':
              'Deploy inspection teams to these barangays this week to '
              'address road and drainage hazards before the rainy season '
              'begins, and assign a staff member to confirm each filing.',
          'severity': 'high',
          'target': 'reports',
        },
      ],
    };

    for (final device in kAllPhones) {
      for (final scale in [1.0, 1.3]) {
        testWidgets('${device.name} @ ${scale}x', (tester) async {
          final nlp = _notifier.analyseNlp(
            [_feedback(2, _now.subtract(const Duration(days: 3)))],
            const [],
            const [],
            hostileInsight(),
            _now,
          );

          final errors = await pumpAt(
            tester,
            device,
            () => MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: needsAttentionForTesting(nlp),
                ),
              ),
            ),
            textScale: scale,
          );

          expect(
            errors,
            isEmpty,
            reason: errors.join('\n'),
          );
        });
      }
    }
  });

  // ── Cached rows cut mid-word by the OLD server clamp are repaired ─────────
  //
  // The server clamp is fixed and redeployed, but `ai_dashboard_insights` rows
  // written before that keep the old `.slice(0, 24)` strings, and the dashboard
  // only regenerates them when new submissions arrive. The reported screenshot
  // was one of those rows.
  //
  // The client cannot re-clamp its way out: at the dashboard's real widths a
  // 24-char stub FITS, so nothing ellipsises and it renders as a confident
  // label that is secretly truncated. Hence the repair at parse time.
  //
  // Half these cases are false-positive guards. The repair rewrites model text,
  // so the risk is not that it under-fires (the old string is merely ugly) but
  // that it MANGLES a legitimate metric - destroying a number an admin needs is
  // worse than the bug. Two of these were real false positives caught while
  // writing this: "Permits and licensing 24" and a trailing-rating string.
  group('a metric cut by the old server clamp is repaired', () {
    const cases = <String, String>{
      // Repaired - the exact strings from the report.
      '1 recent complaint (docu': '1 recent complaint…',
      '3 recent high-urgency re': '3 recent high-urgency…',
      'Civil Registrar complain': 'Civil Registrar…',
      // Left alone - shorter than the old ceiling, so never cut.
      '2.75★': '2.75★',
      '4 mentions': '4 mentions',
      // Left alone - already carries an ellipsis (new clamp, or re-parsed).
      '1 recent complaint…': '1 recent complaint…',
      // Left alone - 25 chars, so not the old ceiling.
      '12 reports in 3 barangays': '12 reports in 3 barangays',
      // Left alone - one unbreakable token; backing up would erase it.
      'aaaaaaaaaaaaaaaaaaaaaaaa': 'aaaaaaaaaaaaaaaaaaaaaaaa',
      // Left alone - trailing token is a complete number/rating, not a
      // clipped word. Healing these would destroy the metric's value.
      'Permits and licensing 24': 'Permits and licensing 24',
      '3 reports in Macanaya 12': '3 reports in Macanaya 12',
      // Left alone - a hard cut never lands on whitespace.
      'Average wait time 3.5★  ': 'Average wait time 3.5★  ',
      '12 high-urgency reports ': '12 high-urgency reports ',
    };

    cases.forEach((input, want) {
      test('"$input"', () {
        expect(AdminDashboardNotifier.healHardCut(input), want);
      });
    });
  });

  // The repair has to run on the path the dashboard actually uses, not just as
  // a pure function - wiring it into the wrong branch would leave the reported
  // bug exactly as it was while the unit tests above stayed green.
  testWidgets('the repaired metric is what reaches the card', (tester) async {
    final nlp = _notifier.analyseNlp(
      [_feedback(2, _now.subtract(const Duration(days: 3)))],
      const [],
      const [],
      {
        'generated_at': _now.toIso8601String(),
        'summary': 'Overall service rating is moderate (3.5★).',
        'focus': [
          {
            'title': 'Document handling',
            'scope': 'Municipal Civil Registrar',
            'metric': '1 recent complaint (docu',
            'suggestion': 'Create a centralized document receipt log.',
            'severity': 'high',
            'target': 'feedback',
          },
        ],
      },
      _now,
    );

    final text = await _render(tester, nlp, widget: needsAttentionForTesting(nlp));

    expect(text, contains('1 recent complaint…'));
    expect(
      text,
      isNot(contains('(docu')),
      reason: 'the mid-word cut must not survive to the card',
    );
  });
}
