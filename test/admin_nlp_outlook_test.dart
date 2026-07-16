// Predictive-outlook regression tests.
//
// Covers the two defects the AI & NLP insights card shipped with:
//  1. A cached `ai_dashboard_insights` row was used no matter how old it was,
//     so a summary generated before the latest feedback ("no feedback to gauge
//     service quality") rendered directly beneath a real 3.0 average.
//  2. `trend` defaulted to `stable` and the forecast was a flat copy of the
//     recent average, so a single 30-day window reported "Stable / 3.0
//     projected" — a default and a copy presented as findings.

import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/admin/providers/admin_dashboard_provider.dart';

/// `_nlp` never touches `_db`, so a bare notifier is enough to drive it.
final _notifier = AdminDashboardNotifier();

final _now = DateTime(2026, 7, 14, 12);

var _seq = 0;

Map<String, dynamic> _feedback(
  int rating,
  DateTime createdAt, {
  String office = "Mayor's Office",
  int? staff,
  int? wait,
  int? clarity,
  int? facility,
}) =>
    {
      'id': 'fb-${_seq++}',
      'office_label': office,
      'service_name': 'Permits',
      'overall_rating': rating,
      'aspect_staff': staff,
      'aspect_wait': wait,
      'aspect_clarity': clarity,
      'aspect_facility': facility,
      'comment': null,
      'created_at': createdAt.toIso8601String(),
    };

Map<String, dynamic> _suggestion(String category, {String? other}) => {
      'id': 'sg-${_seq++}',
      'category': category,
      'category_other': other,
      'barangay': 'Macanaya (Pescaria)',
      'created_at': _now.subtract(const Duration(hours: 2)).toIso8601String(),
    };

Map<String, dynamic> _report(DateTime createdAt) => {
      'id': 'rp-${createdAt.microsecondsSinceEpoch}',
      'category': 'road',
      'remarks': 'Test',
      'barangay': 'Macanaya (Pescaria)',
      'created_at': createdAt.toIso8601String(),
    };

Map<String, dynamic> _insight(DateTime generatedAt) => {
      'summary': 'No overall average or feedback to gauge service quality.',
      'focus': [
        {
          'title': 'Road Reports',
          'metric': '2 reports',
          'suggestion': 'Assign a team to inspect the reported road issues',
          'severity': 'medium',
        },
      ],
      'generated_at': generatedAt.toIso8601String(),
    };

NlpInsights _run({
  required List<Map<String, dynamic>> feedback,
  List<Map<String, dynamic>> reports = const [],
  List<Map<String, dynamic>> suggestions = const [],
  Map<String, dynamic>? insight,
}) =>
    _notifier.analyseNlp(feedback, reports, suggestions, insight, _now);

/// The focus entry whose title matches, or null — keeps assertions readable
/// without depending on ordering.
OutlookFocus? _focusTitled(NlpInsights nlp, String title) {
  for (final f in nlp.focus) {
    if (f.title == title) return f;
  }
  return null;
}

void main() {
  group('AI insight freshness', () {
    test('an insight generated before the newest feedback is ignored', () {
      // The screenshot case: feedback landed 5h ago, the cached summary was
      // written a day earlier and never saw it.
      final nlp = _run(
        feedback: [_feedback(3, _now.subtract(const Duration(hours: 5)))],
        reports: [_report(_now.subtract(const Duration(days: 1)))],
        insight: _insight(_now.subtract(const Duration(days: 2))),
      );

      expect(nlp.outlookUsesAi, isFalse);
      expect(nlp.aiSummary, isNull,
          reason: 'a stale summary must not contradict the panel above it');
    });

    test('an insight newer than every submission is used', () {
      final nlp = _run(
        feedback: [_feedback(3, _now.subtract(const Duration(days: 2)))],
        reports: [_report(_now.subtract(const Duration(days: 3)))],
        insight: _insight(_now.subtract(const Duration(hours: 1))),
      );

      expect(nlp.outlookUsesAi, isTrue);
      expect(nlp.aiSummary, isNotNull);
      expect(nlp.focus, isNotEmpty);
    });

    test('an insight with no generated_at is not trusted', () {
      final nlp = _run(
        feedback: [_feedback(3, _now.subtract(const Duration(hours: 5)))],
        insight: {..._insight(_now), 'generated_at': null},
      );

      expect(nlp.outlookUsesAi, isFalse);
    });

    test('a fresh insight is still ignored when there is no feedback', () {
      // Pre-existing guard: the AI outlook is feedback-centric and invents
      // rating metrics when there is nothing to summarise.
      final nlp = _run(
        feedback: const [],
        reports: [_report(_now.subtract(const Duration(days: 1)))],
        insight: _insight(_now),
      );

      expect(nlp.outlookUsesAi, isFalse);
    });
  });

  group('trend + forecast honesty', () {
    test('one window only reports unknown, not stable, and no forecast', () {
      final nlp = _run(
        feedback: [
          _feedback(3, _now.subtract(const Duration(hours: 5))),
          _feedback(3, _now.subtract(const Duration(hours: 5))),
        ],
      );

      expect(nlp.recentAvg, 3.0);
      expect(nlp.priorAvg, isNull);
      expect(nlp.trend, InsightTrend.unknown,
          reason: 'no prior window means the trend was never measured');
      expect(nlp.forecastRating, isNull,
          reason: 'a forecast needs two points to extrapolate from');
      expect(nlp.trendDelta, isNull);
    });

    test('two windows produce a real trend and an extrapolated forecast', () {
      final nlp = _run(
        feedback: [
          _feedback(4, _now.subtract(const Duration(days: 5))), // recent
          _feedback(2, _now.subtract(const Duration(days: 45))), // prior
        ],
      );

      expect(nlp.recentAvg, 4.0);
      expect(nlp.priorAvg, 2.0);
      expect(nlp.trend, InsightTrend.improving);
      expect(nlp.trendDelta, 2.0);
      // recent + delta = 4 + 2 = 6, clamped to the 1..5 rating scale.
      expect(nlp.forecastRating, 5.0);
    });

    test('two flat windows are genuinely stable', () {
      final nlp = _run(
        feedback: [
          _feedback(3, _now.subtract(const Duration(days: 5))),
          _feedback(3, _now.subtract(const Duration(days: 45))),
        ],
      );

      expect(nlp.trend, InsightTrend.stable);
      expect(nlp.forecastRating, 3.0);
    });

    test('reports alone yield no rating outlook', () {
      final nlp = _run(
        feedback: const [],
        reports: [_report(_now.subtract(const Duration(days: 1)))],
      );

      expect(nlp.reportsAnalyzed, 1);
      expect(nlp.recentAvg, isNull);
      expect(nlp.trend, InsightTrend.unknown);
      expect(nlp.forecastRating, isNull);
    });

    test('the empty snapshot claims no trend', () {
      expect(NlpInsights.empty.trend, InsightTrend.unknown);
      expect(NlpInsights.empty.forecastRating, isNull);
    });

    test('window counts are exposed so the forecast can show its basis', () {
      final nlp = _run(
        feedback: [
          _feedback(4, _now.subtract(const Duration(days: 5))),
          _feedback(4, _now.subtract(const Duration(days: 6))),
          _feedback(2, _now.subtract(const Duration(days: 45))),
        ],
      );

      expect(nlp.recentCount, 2);
      expect(nlp.priorCount, 1);
    });

    test('a forecast past the 1..5 scale is flagged as clamped', () {
      final nlp = _run(
        feedback: [
          _feedback(5, _now.subtract(const Duration(days: 5))),
          _feedback(1, _now.subtract(const Duration(days: 45))),
        ],
      );

      // 5 + 4 = 9 → clamped to 5.
      expect(nlp.forecastRating, 5.0);
      expect(nlp.forecastClamped, isTrue);
    });

    test('a forecast inside the scale is not flagged', () {
      final nlp = _run(
        feedback: [
          _feedback(3, _now.subtract(const Duration(days: 5))),
          _feedback(3, _now.subtract(const Duration(days: 45))),
        ],
      );

      expect(nlp.forecastClamped, isFalse);
    });
  });

  group('focus is specific about where', () {
    test('the weakest aspect names the office driving it', () {
      // Health Office clarity is the worst single (office, aspect) pair. A
      // global average would blend it with the Mayor's Office 5s and report
      // "Process clarity 3.0★" — true of nowhere in particular.
      final nlp = _run(
        feedback: [
          _feedback(5, _now.subtract(const Duration(days: 1)),
              office: "Mayor's Office", clarity: 5),
          _feedback(1, _now.subtract(const Duration(days: 1)),
              office: 'Municipal Health Office', clarity: 1),
        ],
      );

      final clarity = _focusTitled(nlp, 'Process clarity');
      expect(clarity, isNotNull);
      expect(clarity!.metric, '1.0★');
      expect(clarity.scope, 'Municipal Health Office · 1 response');
      expect(clarity.suggestion, contains('Municipal Health Office'));
    });

    test('scope carries the sample size so weak evidence reads as weak', () {
      final nlp = _run(
        feedback: [
          for (var i = 0; i < 3; i++)
            _feedback(2, _now.subtract(const Duration(days: 1)),
                office: "Mayor's Office", wait: 2),
        ],
      );

      final wait = _focusTitled(nlp, 'Wait time');
      expect(wait, isNotNull);
      expect(wait!.scope, "Mayor's Office · 3 responses");
    });

    test('feedback with no office label still reports the sample size', () {
      final nlp = _run(
        feedback: [
          _feedback(2, _now.subtract(const Duration(days: 1)),
              office: '', clarity: 2),
        ],
      );

      final clarity = _focusTitled(nlp, 'Process clarity');
      expect(clarity, isNotNull);
      expect(clarity!.scope, '1 response');
      // No office known → no fabricated "at <office>" tail.
      expect(clarity.suggestion, isNot(contains(' at ')));
    });

    test('aspects at or above 3.5 are not surfaced as weak', () {
      final nlp = _run(
        feedback: [
          _feedback(4, _now.subtract(const Duration(days: 1)),
              office: "Mayor's Office", clarity: 4, wait: 5),
        ],
      );

      expect(_focusTitled(nlp, 'Process clarity'), isNull);
      expect(_focusTitled(nlp, 'Wait time'), isNull);
    });
  });

  group('suggestions reach the recommended focus', () {
    test('the most-requested category becomes a focus area', () {
      final nlp = _run(
        feedback: [_feedback(3, _now.subtract(const Duration(hours: 5)))],
        suggestions: [
          _suggestion('infrastructure'),
          _suggestion('infrastructure'),
          _suggestion('environment'),
        ],
      );

      final top = _focusTitled(nlp, 'Infrastructure');
      expect(top, isNotNull, reason: 'suggestions must reach the focus block');
      expect(top!.metric, '2 suggestions');
      expect(top.scope, 'Citizen suggestions');
      expect(top.suggestion, contains('Most-requested'));
    });

    test('a single suggestion is not framed as most-requested', () {
      final nlp = _run(
        feedback: [_feedback(3, _now.subtract(const Duration(hours: 5)))],
        suggestions: [_suggestion('health_safety')],
      );

      final top = _focusTitled(nlp, 'Health & Safety');
      expect(top, isNotNull);
      expect(top!.metric, '1 suggestion');
      expect(top.suggestion, isNot(contains('Most-requested')));
    });

    test('an "others" suggestion uses its free-text label', () {
      final nlp = _run(
        feedback: [_feedback(3, _now.subtract(const Duration(hours: 5)))],
        suggestions: [_suggestion('others', other: 'Bike lanes')],
      );

      expect(_focusTitled(nlp, 'Bike lanes'), isNotNull);
    });

    test('no suggestions adds no suggestion focus', () {
      final nlp = _run(
        feedback: [_feedback(3, _now.subtract(const Duration(hours: 5)))],
        suggestions: const [],
      );

      for (final f in nlp.focus) {
        expect(f.scope, isNot('Citizen suggestions'));
      }
    });

    test('a suggestion newer than the AI insight makes it stale', () {
      // recommend-actions now reads suggestions, so one it never saw means its
      // recommendations are built on incomplete data.
      final nlp = _run(
        feedback: [_feedback(3, _now.subtract(const Duration(days: 3)))],
        suggestions: [_suggestion('infrastructure')], // 2h ago
        insight: _insight(_now.subtract(const Duration(days: 1))),
      );

      expect(nlp.outlookUsesAi, isFalse);
    });
  });
}
