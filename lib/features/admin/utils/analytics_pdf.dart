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
Future<void> exportAnalyticsPdf({
  required int rangeDays,
  required DateTime now,
  required List<AdminReport> reports,
  required List<AdminFeedback> feedback,
  required List<AdminSuggestion> suggestions,
  required AdminDashboardData dashboard,
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
        pw.SizedBox(height: 20),
        ..._reportsSection(reports, rangeDays),
        pw.SizedBox(height: 22),
        ..._feedbackSection(feedback),
        pw.SizedBox(height: 22),
        ..._suggestionsSection(suggestions),
        pw.SizedBox(height: 22),
        ..._aiSection(dashboard),
      ],
    ),
  );

  final stamp = DateFormat('yyyyMMdd').format(now);
  // Export/save the file directly — no print dialog. On web this downloads the
  // PDF; on mobile it opens the share sheet (Save to Files, email, etc.).
  await Printing.sharePdf(
    bytes: await doc.save(),
    filename: 'GovPulse-Findings-${rangeDays}d-$stamp.pdf',
  );
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

pw.Widget pdfMetaChip(String label, String value) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: pw.BoxDecoration(
      color: pdfSubtle,
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          pdfSafe(label.toUpperCase()),
          style: pw.TextStyle(
            fontSize: 6.5,
            color: pdfMuted,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 0.4,
          ),
        ),
        pw.SizedBox(height: 1),
        pw.Text(
          pdfSafe(value),
          style: pw.TextStyle(fontSize: 9, color: pdfInk),
        ),
      ],
    ),
  );
}

// ══ Reports ═══════════════════════════════════════════════════════════════════

List<pw.Widget> _reportsSection(List<AdminReport> reports, int rangeDays) {
  final total = reports.length;
  final out = <pw.Widget>[pdfH1('1. Citizen Reports')];

  if (total == 0) {
    out.add(pdfEmpty('No reports were submitted in this period.'));
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
    reports.map((r) => (r.barangay?.trim().isNotEmpty ?? false)
        ? r.barangay!.trim()
        : 'Unspecified'),
  );
  final anonymous = reports.where((r) => r.isAnonymous).length;
  final withMedia = reports.where((r) => r.mediaCount > 0).length;
  final perDay = total / rangeDays;

  out.add(
    pdfSummaryLine(
      '$total report${total == 1 ? '' : 's'} submitted over $rangeDays days '
      '(avg ${perDay.toStringAsFixed(1)}/day). '
      'Resolution rate ${_pct(resolutionRate)} ($resolved resolved). '
      '$anonymous submitted anonymously; $withMedia included photos/video.',
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

  // Findings.
  final topCat = byCategory.first;
  final topBrgy = byBarangay.first;
  final pending =
      (statusCounts[ReportStatus.pending] ?? 0) +
      (statusCounts[ReportStatus.underReview] ?? 0) +
      (statusCounts[ReportStatus.inProgress] ?? 0);
  out.add(
    pdfFindings([
      '"${topCat.key}" is the most-reported category '
          '(${topCat.value}, ${_pct(topCat.value / total)} of reports).',
      if (topBrgy.key != 'Unspecified')
        '${topBrgy.key} is the leading hotspot with ${topBrgy.value} '
            'report${topBrgy.value == 1 ? '' : 's'}.',
      'Resolution rate stands at ${_pct(resolutionRate)}; '
          '$pending report${pending == 1 ? '' : 's'} remain open.',
      '${_pct(anonymous / total)} of reports were anonymous — '
          'identity-based follow-up is not possible for these.',
    ]),
  );

  return out;
}

// ══ Feedback ══════════════════════════════════════════════════════════════════

List<pw.Widget> _feedbackSection(List<AdminFeedback> feedback) {
  final out = <pw.Widget>[pdfH1('2. Citizen Feedback')];

  if (feedback.isEmpty) {
    out.add(pdfEmpty('No feedback was submitted in this period.'));
    return out;
  }

  final rated = feedback.where((f) => f.overallRating > 0).toList();
  final avgOverall = rated.isEmpty
      ? null
      : rated.map((f) => f.overallRating).reduce((a, b) => a + b) /
            rated.length;
  final lowRated = feedback.where((f) => f.isLowRated).length;
  final responded =
      feedback.where((f) => f.status == FeedbackStatus.responded).length;

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
    officeSum[f.officeLabel] = (officeSum[f.officeLabel] ?? 0) + f.overallRating;
    officeN[f.officeLabel] = (officeN[f.officeLabel] ?? 0) + 1;
  }
  final offices = officeN.keys.toList()
    ..sort((a, b) => (officeSum[a]! / officeN[a]!)
        .compareTo(officeSum[b]! / officeN[b]!));

  out.add(
    pdfSummaryLine(
      '${feedback.length} response${feedback.length == 1 ? '' : 's'} '
      '(${rated.length} rated). '
      'Average satisfaction ${avgOverall == null ? '—' : '${avgOverall.toStringAsFixed(1)} / 5'}. '
      '$responded responded to · $lowRated low-rated (1–2 / 5).',
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
            rated.isEmpty ? '—' : _pct((dist[i] ?? 0) / rated.length),
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
            e.value == null ? '—' : '${e.value!.toStringAsFixed(1)} / 5',
            '${feedback.where((f) {
              final v = {
                'Staff attitude': f.aspectStaff,
                'Wait time': f.aspectWait,
                'Process clarity': f.aspectClarity,
                'Facility': f.aspectFacility,
              }[e.key];
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
            [o, '${(officeSum[o]! / officeN[o]!).toStringAsFixed(1)} / 5', '${officeN[o]}'],
        ],
        numeric: const {1, 2},
      ),
    );
  }

  // Findings — weakest dimension, worst office.
  final ranked = aspects.entries.where((e) => e.value != null).toList()
    ..sort((a, b) => a.value!.compareTo(b.value!));
  out.add(
    pdfFindings([
      if (avgOverall != null)
        'Overall satisfaction is ${avgOverall.toStringAsFixed(1)} / 5 '
            'across ${rated.length} rated response${rated.length == 1 ? '' : 's'}.',
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

List<pw.Widget> _suggestionsSection(List<AdminSuggestion> suggestions) {
  final out = <pw.Widget>[pdfH1('3. Citizen Suggestions')];

  if (suggestions.isEmpty) {
    out.add(pdfEmpty('No suggestions were submitted in this period.'));
    return out;
  }

  final total = suggestions.length;
  final responded =
      suggestions.where((s) => s.status == SuggestionStatus.responded).length;
  final anonymous = suggestions.where((s) => s.isAnonymous).length;
  final byCategory = _tally(suggestions.map((s) => s.category));

  out.add(
    pdfSummaryLine(
      '$total suggestion${total == 1 ? '' : 's'} submitted. '
      '$responded responded to (${_pct(responded / total)}). '
      '$anonymous anonymous.',
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
  out.add(
    pdfFindings([
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
  final out = <pw.Widget>[pdfH1('4. AI Forecast & Insights')];

  if (!nlp.hasData) {
    out.add(
      pdfEmpty('Not enough classified feedback or reports to generate insights yet.'),
    );
    return out;
  }

  out.add(
    pdfSummaryLine(
      nlp.usesAi
          ? 'Hybrid AI analysis: ${nlp.aiClassified} feedback and '
                '${nlp.reportsAiClassified} reports were model-classified; the rest '
                'use the on-device rule-based fallback.'
          : 'On-device rule-based analysis (the AI classifier is not deployed or '
                'was unavailable for this window).',
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
        ['Prior 30-day average', nlp.priorAvg == null ? '—' : '${nlp.priorAvg!.toStringAsFixed(2)} / 5'],
        ['Recent 30-day average', nlp.recentAvg == null ? '—' : '${nlp.recentAvg!.toStringAsFixed(2)} / 5'],
        [
          'Change',
          nlp.trendDelta == null
              ? '—'
              : '${nlp.trendDelta! >= 0 ? '+' : ''}${nlp.trendDelta!.toStringAsFixed(2)} pts',
        ],
        ['Forecast (next period)', nlp.forecastRating == null ? '—' : '${nlp.forecastRating!.toStringAsFixed(2)} / 5'],
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
        flex: const {0: 1.4, 1: 2.4, 2: 1.6, 3: 4.5},
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

String _rangeLabel(int days) => switch (days) {
  7 => 'Last 7 days',
  30 => 'Last 30 days',
  90 => 'Last 90 days',
  _ => 'Last $days days',
};

String _pct(double share) => '${(share * 100).toStringAsFixed(0)}%';

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
