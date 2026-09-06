import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'admin_pdf.dart';
import '../providers/admin_dashboard_provider.dart';
import '../providers/admin_feedback_provider.dart';
import '../providers/admin_reports_provider.dart';
import '../providers/admin_suggestions_provider.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Analytics → print-ready PDF findings report
//
//  Turns the live admin data (reports, feedback, suggestions, and the AI
//  forecast) into a single, print-ready document. Every section follows the
//  same shape the LGU expects in a written report: a short SUMMARY, the RESULTS
//  as tables, and a bullet-list of FINDINGS derived from those numbers.
//
//  Exported straight to a PDF file (browser download on web, share sheet on
//  mobile) — no print dialog. The document is print-ready if the admin chooses
//  to print the saved file later.
// ════════════════════════════════════════════════════════════════════════════

/// Build and present the print-ready analytics report for the given window.
/// The lists are expected to be already filtered to the last [rangeDays] days;
/// [dashboard] carries the AI forecast (which uses its own rolling windows).
///
/// Layout lives in [buildAnalyticsPdf]; this only presents what that returns.
Future<void> exportAnalyticsPdf({
  required int rangeDays,
  required DateTime now,
  required List<AdminReport> reports,
  required List<AdminFeedback> feedback,
  required List<AdminSuggestion> suggestions,
  required AdminDashboardData dashboard,
  // The equivalent window immediately before this one, used only to say
  // whether each headline number moved. Empty is a valid state (a new LGU, or
  // the first month of use) and simply omits the comparison lines.
  List<AdminReport> priorReports = const [],
  List<AdminFeedback> priorFeedback = const [],
  List<AdminSuggestion> priorSuggestions = const [],
  // True when the underlying queries hit their row cap, so this document covers
  // only the most recent submissions in the period rather than all of them.
  bool truncated = false,
}) async {
  final bytes = await buildAnalyticsPdf(
    rangeDays: rangeDays,
    now: now,
    reports: reports,
    feedback: feedback,
    suggestions: suggestions,
    dashboard: dashboard,
    priorReports: priorReports,
    priorFeedback: priorFeedback,
    priorSuggestions: priorSuggestions,
    truncated: truncated,
  );

  final stamp = DateFormat('yyyyMMdd').format(now);
  // Export/save the file directly — no print dialog. On web this downloads the
  // PDF; on mobile it opens the share sheet (Save to Files, email, etc.).
  await Printing.sharePdf(
    bytes: bytes,
    filename: 'GovPulse-Findings-${rangeDays}d-$stamp.pdf',
  );
}

/// The document itself, as bytes.
///
/// Split from [exportAnalyticsPdf] so the layout can be exercised without a
/// share sheet behind a platform channel — this report prints free-form AI text
/// and font-coverage bugs are only visible in the built document.
Future<Uint8List> buildAnalyticsPdf({
  required int rangeDays,
  required DateTime now,
  required List<AdminReport> reports,
  required List<AdminFeedback> feedback,
  required List<AdminSuggestion> suggestions,
  required AdminDashboardData dashboard,
  List<AdminReport> priorReports = const [],
  List<AdminFeedback> priorFeedback = const [],
  List<AdminSuggestion> priorSuggestions = const [],
  bool truncated = false,
}) async {
  final doc = pw.Document(
    title: 'GovPulse Analytics Findings Report',
    author: 'GovPulse Admin Console',
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 40, 36, 40),
      footer: pdfFooter,
      build: (context) => [
        _titleBlock(rangeDays, now),
        if (truncated) ...[pw.SizedBox(height: 12), _coverageCaveat()],
        pw.SizedBox(height: 20),
        // Each section returns its heading already bound to the block beneath
        // it (see _sectionOpener), so MultiPage can break between rows without
        // ever stranding a numbered heading at the foot of a page.
        ..._reportsSection(reports, priorReports, rangeDays),
        pw.SizedBox(height: 22),
        ..._feedbackSection(feedback, priorFeedback),
        pw.SizedBox(height: 22),
        ..._suggestionsSection(suggestions, priorSuggestions),
        pw.SizedBox(height: 22),
        ..._aiSection(dashboard),
      ],
    ),
  );

  return doc.save();
}

// ══ Cover / title ═════════════════════════════════════════════════════════════

pw.Widget _titleBlock(int rangeDays, DateTime now) {
  final rangeLabel = _rangeLabel(rangeDays);
  final start = DateTime(
    now.year,
    now.month,
    now.day,
  ).subtract(Duration(days: rangeDays - 1));
  final period =
      '${DateFormat('MMM d, yyyy').format(start)} – '
      '${DateFormat('MMM d, yyyy').format(now)}';

  return pdfTitleBlock(
    title: 'Analytics & Findings Report',
    chips: [
      (label: 'Coverage', value: rangeLabel),
      (label: 'Period', value: period),
      (
        label: 'Generated',
        value: DateFormat('MMM d, yyyy · h:mm a').format(now),
      ),
    ],
  );
}

/// Printed under the masthead when the data behind the document was capped.
///
/// The queries return the most recent 200 rows; past that, the oldest
/// submissions in the window were never fetched. Saying so on the page is the
/// difference between a report that is incomplete and one that is wrong.
pw.Widget _coverageCaveat() {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(8),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: pdfInk, width: 0.8),
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Text(
      pdfSafe(
        'PARTIAL COVERAGE - This period contains more submissions than the '
        'console retrieves in one pass. The figures below cover the most '
        'recent submissions in the period, not all of them, and should be '
        'read as indicative rather than as a complete count.',
      ),
      style: pw.TextStyle(fontSize: 8.5, color: pdfInk, lineSpacing: 1.5),
    ),
  );
}

/// A section heading bound to the block that opens it.
///
/// `MultiPage` breaks between the top-level widgets it is given, so a heading
/// emitted as its own widget can land as the last thing on a page with its
/// content overleaf — which is how "2. Citizen Feedback" ended up alone at the
/// foot of page 1. `pw.Inseparable` is the only thing that prevents this; a
/// `pw.Column` does NOT stop a page break.
pw.Widget _sectionOpener(String heading, pw.Widget opening) {
  return pw.Inseparable(
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [pdfH1(heading), opening],
    ),
  );
}

// ══ Reports ═══════════════════════════════════════════════════════════════════

List<pw.Widget> _reportsSection(
  List<AdminReport> reports,
  List<AdminReport> prior,
  int rangeDays,
) {
  final total = reports.length;
  final out = <pw.Widget>[];

  if (total == 0) {
    out.add(
      _sectionOpener(
        '1. Citizen Reports',
        pdfEmpty('No reports were submitted in this period.'),
      ),
    );
    return out;
  }

  // Status breakdown.
  final statusCounts = <ReportStatus, int>{};
  for (final s in ReportStatus.values) {
    statusCounts[s] = 0;
  }
  for (final r in reports) {
    statusCounts[r.status] = (statusCounts[r.status] ?? 0) + 1;
  }
  final resolved = statusCounts[ReportStatus.resolved] ?? 0;
  final resolutionRate = resolved / total;

  // Category + barangay tallies.
  final byCategory = _tally(reports.map((r) => r.category));
  final byBarangay = _tally(
    reports.map(
      (r) => (r.barangay?.trim().isNotEmpty ?? false)
          ? r.barangay!.trim()
          : 'Unspecified',
    ),
  );
  final anonymous = reports.where((r) => r.isAnonymous).length;
  final withMedia = reports.where((r) => r.mediaCount > 0).length;
  final perDay = total / rangeDays;

  out.add(
    _sectionOpener(
      '1. Citizen Reports',
      pdfSummaryLine(
        '$total report${total == 1 ? '' : 's'} submitted over $rangeDays days '
        '(avg ${perDay.toStringAsFixed(1)}/day). '
        'Resolution rate ${_pct(resolutionRate)} ($resolved resolved). '
        '$anonymous submitted anonymously; $withMedia included photos/video.',
      ),
    ),
  );

  out.add(pdfH2('Status breakdown'));
  out.add(
    pdfTable(
      ['Status', 'Count', 'Share'],
      [
        for (final s in ReportStatus.values)
          [
            reportStatusLabel(s),
            '${statusCounts[s]}',
            _pct((statusCounts[s] ?? 0) / total),
          ],
      ],
      numeric: const {1, 2},
    ),
  );

  out.add(pdfH2('By category'));
  out.add(
    pdfTable(
      ['Category', 'Count', 'Share'],
      [
        for (final e in byCategory)
          [e.key, '${e.value}', _pct(e.value / total)],
      ],
      numeric: const {1, 2},
    ),
  );

  out.add(pdfH2('Barangay hotspots'));
  out.add(
    pdfTable(
      ['Barangay', 'Reports', 'Share'],
      [
        for (final e in byBarangay.take(8))
          [e.key, '${e.value}', _pct(e.value / total)],
      ],
      numeric: const {1, 2},
    ),
  );

  // Where the volume actually concentrates. The two tables above answer "what"
  // and "where" separately; an LGU dispatches a crew to a *pair*, so the pair
  // is what the report has to name. Only shown once there is more than one of
  // either — with a single category or a single barangay the cross-tab just
  // restates the table above it.
  if (byCategory.length > 1 || byBarangay.length > 1) {
    final pairs = <String, int>{};
    for (final r in reports) {
      final brgy = (r.barangay?.trim().isNotEmpty ?? false)
          ? r.barangay!.trim()
          : 'Unspecified';
      pairs['$brgy|${r.category}'] = (pairs['$brgy|${r.category}'] ?? 0) + 1;
    }
    final ranked = pairs.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    out.add(pdfH2('Concentration (barangay x category)'));
    out.add(
      pdfTable(
        ['Barangay', 'Category', 'Reports', 'Share'],
        [
          for (final e in ranked.take(8))
            [
              e.key.split('|').first,
              e.key.split('|').last,
              '${e.value}',
              _pct(e.value / total),
            ],
        ],
        numeric: const {2, 3},
        flex: const {0: 2.2, 1: 2.6, 2: 1.0, 3: 1.0},
      ),
    );
  }

  // Findings.
  final topCat = byCategory.first;
  final topBrgy = byBarangay.first;
  final pending =
      (statusCounts[ReportStatus.pending] ?? 0) +
      (statusCounts[ReportStatus.underReview] ?? 0) +
      (statusCounts[ReportStatus.inProgress] ?? 0);
  // Movement against the equivalent window before this one.
  final priorResolved = prior
      .where((r) => r.status == ReportStatus.resolved)
      .length;
  final volumeDelta = _deltaPhrase(
    now: total,
    before: prior.length,
    unit: '$rangeDays days',
  );
  final ratePhrase = prior.isEmpty
      ? null
      : _deltaPoints(
          now: resolutionRate * 100,
          before: (priorResolved / prior.length) * 100,
          unit: '$rangeDays days',
        );

  out.add(
    pdfFindings([
      if (volumeDelta != null) 'Report volume is $volumeDelta.',
      '"${topCat.key}" is the most-reported category '
          '(${topCat.value}, ${_pct(topCat.value / total)} of reports).',
      if (topBrgy.key != 'Unspecified')
        '${topBrgy.key} is the leading hotspot with ${topBrgy.value} '
            'report${topBrgy.value == 1 ? '' : 's'}.',
      'Resolution rate stands at ${_pct(resolutionRate)}'
          '${ratePhrase == null ? '' : ' - $ratePhrase'}; '
          '$pending report${pending == 1 ? '' : 's'} remain open.',
      if (anonymous > 0)
        '${_pct(anonymous / total)} of reports were anonymous '
            '($anonymous of $total) - identity-based follow-up is not '
            'possible for these.'
      else
        'Every report carries an identifiable submitter, so all of them are '
            'open to direct follow-up.',
    ]),
  );

  return out;
}

// ══ Feedback ══════════════════════════════════════════════════════════════════

List<pw.Widget> _feedbackSection(
  List<AdminFeedback> feedback,
  List<AdminFeedback> prior,
) {
  final out = <pw.Widget>[];

  if (feedback.isEmpty) {
    out.add(
      _sectionOpener(
        '2. Citizen Feedback',
        pdfEmpty('No feedback was submitted in this period.'),
      ),
    );
    return out;
  }

  final rated = feedback.where((f) => f.overallRating > 0).toList();
  final avgOverall = rated.isEmpty
      ? null
      : rated.map((f) => f.overallRating).reduce((a, b) => a + b) /
            rated.length;
  final lowRated = feedback.where((f) => f.isLowRated).length;
  final responded = feedback
      .where((f) => f.status == FeedbackStatus.responded)
      .length;

  // Rating distribution 1..5.
  final dist = <int, int>{for (var i = 1; i <= 5; i++) i: 0};
  for (final f in rated) {
    dist[f.overallRating] = (dist[f.overallRating] ?? 0) + 1;
  }

  // Aspect averages.
  double? aspectAvg(int? Function(AdminFeedback) sel) {
    var s = 0, n = 0;
    for (final f in feedback) {
      final v = sel(f);
      if (v != null && v > 0) {
        s += v;
        n++;
      }
    }
    return n == 0 ? null : s / n;
  }

  final aspects = <String, double?>{
    'Staff attitude': aspectAvg((f) => f.aspectStaff),
    'Wait time': aspectAvg((f) => f.aspectWait),
    'Process clarity': aspectAvg((f) => f.aspectClarity),
    'Facility': aspectAvg((f) => f.aspectFacility),
  };

  // Per-office averages.
  final officeSum = <String, double>{};
  final officeN = <String, int>{};
  for (final f in rated) {
    officeSum[f.officeLabel] =
        (officeSum[f.officeLabel] ?? 0) + f.overallRating;
    officeN[f.officeLabel] = (officeN[f.officeLabel] ?? 0) + 1;
  }
  final offices = officeN.keys.toList()
    ..sort(
      (a, b) =>
          (officeSum[a]! / officeN[a]!).compareTo(officeSum[b]! / officeN[b]!),
    );

  out.add(
    _sectionOpener(
      '2. Citizen Feedback',
      pdfSummaryLine(
        '${feedback.length} response${feedback.length == 1 ? '' : 's'} '
        '(${rated.length} rated). '
        'Average satisfaction ${avgOverall == null ? _blank : '${avgOverall.toStringAsFixed(1)} / 5'}. '
        '$responded responded to · $lowRated low-rated (1–2 / 5).',
      ),
    ),
  );

  out.add(pdfH2('Rating distribution'));
  out.add(
    pdfTable(
      ['Rating', 'Label', 'Count', 'Share'],
      [
        for (var i = 5; i >= 1; i--)
          [
            '$i / 5',
            feedbackRatingLabel(i),
            '${dist[i]}',
            rated.isEmpty ? _blank : _pct((dist[i] ?? 0) / rated.length),
          ],
      ],
      numeric: const {2, 3},
    ),
  );

  out.add(pdfH2('Service dimensions (average)'));
  out.add(
    pdfTable(
      ['Dimension', 'Average', 'Rated by'],
      [
        for (final e in aspects.entries)
          [
            e.key,
            e.value == null ? _blank : '${e.value!.toStringAsFixed(1)} / 5',
            '${feedback.where((f) {
              final v = {'Staff attitude': f.aspectStaff, 'Wait time': f.aspectWait, 'Process clarity': f.aspectClarity, 'Facility': f.aspectFacility}[e.key];
              return v != null && v > 0;
            }).length}',
          ],
      ],
      numeric: const {1, 2},
    ),
  );

  if (offices.isNotEmpty) {
    out.add(pdfH2('By office'));
    out.add(
      pdfTable(
        ['Office', 'Avg rating', 'Responses'],
        [
          for (final o in offices)
            [
              o,
              '${(officeSum[o]! / officeN[o]!).toStringAsFixed(1)} / 5',
              '${officeN[o]}',
            ],
        ],
        numeric: const {1, 2},
      ),
    );
  }

  // Findings — weakest dimension, worst office.
  final ranked = aspects.entries.where((e) => e.value != null).toList()
    ..sort((a, b) => a.value!.compareTo(b.value!));
  // Satisfaction against the previous window of the same length.
  final priorRated = prior.where((f) => f.overallRating > 0).toList();
  final priorAvg = priorRated.isEmpty
      ? null
      : priorRated.map((f) => f.overallRating).reduce((a, b) => a + b) /
            priorRated.length;
  final satisfactionDelta = _deltaPoints(
    now: avgOverall,
    before: priorAvg,
    unit: 'period',
  );

  out.add(
    pdfFindings([
      if (avgOverall != null)
        'Overall satisfaction is ${avgOverall.toStringAsFixed(1)} / 5 '
            'across ${rated.length} rated response${rated.length == 1 ? '' : 's'}'
            '${satisfactionDelta == null ? '' : ' - $satisfactionDelta'}.',
      if (ranked.isNotEmpty)
        'Weakest dimension: "${ranked.first.key}" '
            '(${ranked.first.value!.toStringAsFixed(1)} / 5) — prioritise improvement here.',
      if (offices.isNotEmpty)
        'Lowest-rated office: ${offices.first} '
            '(${(officeSum[offices.first]! / officeN[offices.first]!).toStringAsFixed(1)} / 5).',
      if (lowRated > 0)
        '$lowRated low-rated response${lowRated == 1 ? '' : 's'} warrant a direct reply and follow-up.',
    ]),
  );

  return out;
}

// ══ Suggestions ═══════════════════════════════════════════════════════════════

List<pw.Widget> _suggestionsSection(
  List<AdminSuggestion> suggestions,
  List<AdminSuggestion> prior,
) {
  final out = <pw.Widget>[];

  if (suggestions.isEmpty) {
    out.add(
      _sectionOpener(
        '3. Citizen Suggestions',
        pdfEmpty('No suggestions were submitted in this period.'),
      ),
    );
    return out;
  }

  final total = suggestions.length;
  final responded = suggestions
      .where((s) => s.status == SuggestionStatus.responded)
      .length;
  final anonymous = suggestions.where((s) => s.isAnonymous).length;
  final byCategory = _tally(suggestions.map((s) => s.category));

  out.add(
    _sectionOpener(
      '3. Citizen Suggestions',
      pdfSummaryLine(
        '$total suggestion${total == 1 ? '' : 's'} submitted. '
        '$responded responded to (${_pct(responded / total)}). '
        '$anonymous anonymous.',
      ),
    ),
  );

  out.add(pdfH2('By category'));
  out.add(
    pdfTable(
      ['Category', 'Count', 'Share'],
      [
        for (final e in byCategory)
          [e.key, '${e.value}', _pct(e.value / total)],
      ],
      numeric: const {1, 2},
    ),
  );

  out.add(pdfH2('Response status'));
  out.add(
    pdfTable(
      ['Status', 'Count', 'Share'],
      [
        ['New', '${total - responded}', _pct((total - responded) / total)],
        ['Responded', '$responded', _pct(responded / total)],
      ],
      numeric: const {1, 2},
    ),
  );

  final topCat = byCategory.first;
  final volumeDelta = _deltaPhrase(
    now: total,
    before: prior.length,
    unit: 'period',
  );
  out.add(
    pdfFindings([
      if (volumeDelta != null) 'Suggestion volume is $volumeDelta.',
      '"${topCat.key}" is the most common suggestion theme '
          '(${topCat.value}, ${_pct(topCat.value / total)}).',
      'The LGU has closed the loop on ${_pct(responded / total)} of suggestions.',
      if (total - responded > 0)
        '${total - responded} suggestion${total - responded == 1 ? '' : 's'} still await a response.',
    ]),
  );

  return out;
}

// ══ AI forecast & insights ════════════════════════════════════════════════════

List<pw.Widget> _aiSection(AdminDashboardData d) {
  final nlp = d.nlp;
  final out = <pw.Widget>[];

  if (!nlp.hasData) {
    out.add(
      _sectionOpener(
        '4. AI Forecast & Insights',
        pdfEmpty(
          'Not enough classified feedback or reports to generate insights yet.',
        ),
      ),
    );
    return out;
  }

  out.add(
    _sectionOpener(
      '4. AI Forecast & Insights',
      pdfSummaryLine(
        nlp.usesAi
            ? 'Hybrid AI analysis: ${nlp.aiClassified} feedback and '
                  '${nlp.reportsAiClassified} reports were model-classified; the rest '
                  'use the on-device rule-based fallback.'
            : 'On-device rule-based analysis (the AI classifier is not deployed or '
                  'was unavailable for this window).',
      ),
    ),
  );

  // Predictive outlook.
  final trendLabel = switch (nlp.trend) {
    InsightTrend.improving => 'Improving',
    InsightTrend.declining => 'Declining',
    InsightTrend.stable => 'Stable',
    InsightTrend.unknown => 'Not enough data',
  };
  out.add(pdfH2('Predictive satisfaction outlook'));
  out.add(
    pdfTable(
      ['Metric', 'Value'],
      [
        [
          'Prior 30-day average',
          nlp.priorAvg == null
              ? _blank
              : '${nlp.priorAvg!.toStringAsFixed(2)} / 5',
        ],
        [
          'Recent 30-day average',
          nlp.recentAvg == null
              ? _blank
              : '${nlp.recentAvg!.toStringAsFixed(2)} / 5',
        ],
        [
          'Change',
          nlp.trendDelta == null
              ? _blank
              : '${nlp.trendDelta! >= 0 ? '+' : ''}${nlp.trendDelta!.toStringAsFixed(2)} pts',
        ],
        [
          'Forecast (next period)',
          nlp.forecastRating == null
              ? _blank
              : '${nlp.forecastRating!.toStringAsFixed(2)} / 5',
        ],
        ['Trend', trendLabel],
      ],
      numeric: const {1},
    ),
  );

  // Sentiment.
  if (nlp.analyzed > 0) {
    out.add(pdfH2('Feedback sentiment'));
    out.add(
      pdfTable(
        ['Sentiment', 'Count', 'Share'],
        [
          ['Positive', '${nlp.positive}', _pct(nlp.positiveShare)],
          ['Neutral', '${nlp.neutral}', _pct(nlp.neutralShare)],
          ['Negative', '${nlp.negative}', _pct(nlp.negativeShare)],
        ],
        numeric: const {1, 2},
      ),
    );
  }

  // Urgency triage.
  if (nlp.reportsAnalyzed > 0) {
    out.add(pdfH2('Report urgency triage'));
    out.add(
      pdfTable(
        ['Urgency', 'Count', 'Share'],
        [
          ['High', '${nlp.urgentHigh}', _pct(nlp.highShare)],
          ['Medium', '${nlp.urgentMedium}', _pct(nlp.mediumShare)],
          ['Low', '${nlp.urgentLow}', _pct(nlp.lowShare)],
        ],
        numeric: const {1, 2},
      ),
    );
  }

  // Recommended focus areas.
  if (nlp.focus.isNotEmpty) {
    out.add(pdfH2('Recommended focus areas'));
    out.add(
      pdfTable(
        ['Priority', 'Focus', 'Metric', 'Suggested action'],
        [
          for (final f in nlp.focus)
            [
              _severityLabel(f.severity),
              // Scope carries the office + sample size; without it the printed
              // report repeats the vague, un-actionable "Process clarity".
              (f.scope == null || f.scope!.trim().isEmpty)
                  ? f.title
                  : '${f.title}\n${f.scope}',
              f.metric,
              f.suggestion,
            ],
        ],
        // Focus carries two stacked lines (title + scope), so it needs more
        // room than the metric beside it; the action is prose and keeps the
        // most. Priority is one short word and needs the least.
        flex: const {0: 1.0, 1: 2.9, 2: 1.5, 3: 4.0},
      ),
    );
  }

  // AI narrative, if any.
  if ((nlp.aiSummary ?? '').isNotEmpty) {
    out.add(pdfH2('AI outlook summary'));
    out.add(pdfPara(nlp.aiSummary!.trim()));
  }

  return out;
}

// ── helpers ──────────────────────────────────────────────────────────────────

/// A period-over-period movement, phrased for a written report.
///
/// Returns null when there is nothing to compare against — the prior window is
/// empty (a new deployment) or both numbers are zero. Callers drop a null
/// rather than printing "no change from 0", which reads as a finding when it is
/// really an absence of data.
String? _deltaPhrase({
  required num now,
  required num before,
  required String unit,
}) {
  if (now == before) {
    return before == 0 ? null : 'unchanged from the previous $unit';
  }
  if (before == 0) return 'up from none in the previous $unit';
  if (now == 0) return 'down from $before in the previous $unit';

  final diff = now - before;
  final pct = (diff.abs() / before) * 100;
  final direction = diff > 0 ? 'up' : 'down';
  // Reads as "up 50% (2 -> 3)": the proportion for scale, the raw counts so a
  // small base cannot dress a single extra report up as a crisis.
  return '$direction ${pct.toStringAsFixed(0)}% ($before -> $now) '
      'vs the previous $unit';
}

/// The same, for an average that is already a rate/score rather than a count.
String? _deltaPoints({
  required double? now,
  required double? before,
  required String unit,
}) {
  if (now == null || before == null) return null;
  final diff = now - before;
  if (diff.abs() < 0.05) return 'level with the previous $unit';
  final direction = diff > 0 ? 'up' : 'down';
  return '$direction ${diff.abs().toStringAsFixed(1)} points '
      'from ${before.toStringAsFixed(1)} in the previous $unit';
}

String _rangeLabel(int days) => switch (days) {
  7 => 'Last 7 days',
  30 => 'Last 30 days',
  90 => 'Last 90 days',
  _ => 'Last $days days',
};

/// A share as a whole-number percentage.
///
/// Returns the em-dash placeholder for a non-finite input rather than printing
/// "NaN%" or "Infinity%". Several callers divide by a denominator that is
/// non-zero only because the section early-returns on an empty list — this
/// keeps a future caller from putting arithmetic garbage in a filed document.
String _pct(double share) =>
    share.isFinite ? '${(share * 100).toStringAsFixed(0)}%' : _blank;

/// The placeholder for "no value". One constant so every table agrees.
const _blank = '\u2014'; // em dash, mapped to "-" by pdfSafe on the page.

String _severityLabel(String severity) => switch (severity) {
  'high' => 'HIGH',
  'medium' => 'MEDIUM',
  _ => 'LOW',
};

/// Count occurrences of each label, returned high-to-low.
List<MapEntry<String, int>> _tally(Iterable<String> values) {
  final counts = <String, int>{};
  for (final v in values) {
    final key = v.trim().isEmpty ? 'Others' : v.trim();
    counts[key] = (counts[key] ?? 0) + 1;
  }
  final entries = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return entries;
}
