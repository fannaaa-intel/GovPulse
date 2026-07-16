import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

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

// ── Palette ─────────────────────────────────────────────────────────────────
final _ink = PdfColor.fromInt(0xFF1F2937);
final _muted = PdfColor.fromInt(0xFF6B7280);
final _line = PdfColor.fromInt(0xFFE5E7EB);
final _subtle = PdfColor.fromInt(0xFFF3F4F6);

/// PDF-safe text. The bundled Helvetica font only covers Latin-1, so any glyph
/// outside it (en/em dashes, bullets, the ★ rating mark, and the smart quotes /
/// ellipses the AI summaries emit) renders as a blank "tofu" box. Map them to
/// safe equivalents before they reach the page.
String _safe(String s) => s
    .replaceAll('★', ' / 5')
    .replaceAll('–', '-')
    .replaceAll('—', '-')
    .replaceAll('•', '-')
    .replaceAll('“', '"')
    .replaceAll('”', '"')
    .replaceAll('‘', "'")
    .replaceAll('’', "'")
    .replaceAll('…', '...')
    .replaceAll('→', '->')
    .replaceAll('≥', '>=')
    .replaceAll('≤', '<=');

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
      footer: _footer,
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

  return pw.Container(
    padding: const pw.EdgeInsets.only(bottom: 14),
    decoration: pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: _ink, width: 2)),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'GovPulse',
          style: pw.TextStyle(
            fontSize: 24,
            fontWeight: pw.FontWeight.bold,
            color: _ink,
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          'Analytics & Findings Report',
          style: pw.TextStyle(fontSize: 14, color: _ink),
        ),
        pw.SizedBox(height: 10),
        pw.Row(
          children: [
            _metaChip('Coverage', rangeLabel),
            pw.SizedBox(width: 10),
            _metaChip('Period', period),
            pw.SizedBox(width: 10),
            _metaChip(
              'Generated',
              DateFormat('MMM d, yyyy · h:mm a').format(now),
            ),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Local Government Unit of Aparri, Cagayan',
          style: pw.TextStyle(fontSize: 9, color: _muted),
        ),
      ],
    ),
  );
}

pw.Widget _metaChip(String label, String value) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: pw.BoxDecoration(
      color: _subtle,
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          _safe(label.toUpperCase()),
          style: pw.TextStyle(
            fontSize: 6.5,
            color: _muted,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 0.4,
          ),
        ),
        pw.SizedBox(height: 1),
        pw.Text(
          _safe(value),
          style: pw.TextStyle(fontSize: 9, color: _ink),
        ),
      ],
    ),
  );
}

// ══ Reports ═══════════════════════════════════════════════════════════════════

List<pw.Widget> _reportsSection(List<AdminReport> reports, int rangeDays) {
  final total = reports.length;
  final out = <pw.Widget>[_h1('1. Citizen Reports')];

  if (total == 0) {
    out.add(_empty('No reports were submitted in this period.'));
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
    _summaryLine(
      '$total report${total == 1 ? '' : 's'} submitted over $rangeDays days '
      '(avg ${perDay.toStringAsFixed(1)}/day). '
      'Resolution rate ${_pct(resolutionRate)} ($resolved resolved). '
      '$anonymous submitted anonymously; $withMedia included photos/video.',
    ),
  );

  out.add(_h2('Status breakdown'));
  out.add(
    _table(
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

  out.add(_h2('By category'));
  out.add(
    _table(
      ['Category', 'Count', 'Share'],
      [
        for (final e in byCategory)
          [e.key, '${e.value}', _pct(e.value / total)],
      ],
      numeric: const {1, 2},
    ),
  );

  out.add(_h2('Barangay hotspots'));
  out.add(
    _table(
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
    _findings([
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
  final out = <pw.Widget>[_h1('2. Citizen Feedback')];

  if (feedback.isEmpty) {
    out.add(_empty('No feedback was submitted in this period.'));
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
    _summaryLine(
      '${feedback.length} response${feedback.length == 1 ? '' : 's'} '
      '(${rated.length} rated). '
      'Average satisfaction ${avgOverall == null ? '—' : '${avgOverall.toStringAsFixed(1)} / 5'}. '
      '$responded responded to · $lowRated low-rated (1–2 / 5).',
    ),
  );

  out.add(_h2('Rating distribution'));
  out.add(
    _table(
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

  out.add(_h2('Service dimensions (average)'));
  out.add(
    _table(
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
    out.add(_h2('By office'));
    out.add(
      _table(
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
    _findings([
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
  final out = <pw.Widget>[_h1('3. Citizen Suggestions')];

  if (suggestions.isEmpty) {
    out.add(_empty('No suggestions were submitted in this period.'));
    return out;
  }

  final total = suggestions.length;
  final responded =
      suggestions.where((s) => s.status == SuggestionStatus.responded).length;
  final anonymous = suggestions.where((s) => s.isAnonymous).length;
  final byCategory = _tally(suggestions.map((s) => s.category));

  out.add(
    _summaryLine(
      '$total suggestion${total == 1 ? '' : 's'} submitted. '
      '$responded responded to (${_pct(responded / total)}). '
      '$anonymous anonymous.',
    ),
  );

  out.add(_h2('By category'));
  out.add(
    _table(
      ['Category', 'Count', 'Share'],
      [
        for (final e in byCategory)
          [e.key, '${e.value}', _pct(e.value / total)],
      ],
      numeric: const {1, 2},
    ),
  );

  out.add(_h2('Response status'));
  out.add(
    _table(
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
    _findings([
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
  final out = <pw.Widget>[_h1('4. AI Forecast & Insights')];

  if (!nlp.hasData) {
    out.add(
      _empty('Not enough classified feedback or reports to generate insights yet.'),
    );
    return out;
  }

  out.add(
    _summaryLine(
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
  out.add(_h2('Predictive satisfaction outlook'));
  out.add(
    _table(
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
    out.add(_h2('Feedback sentiment'));
    out.add(
      _table(
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
    out.add(_h2('Report urgency triage'));
    out.add(
      _table(
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
    out.add(_h2('Recommended focus areas'));
    out.add(
      _table(
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
    out.add(_h2('AI outlook summary'));
    out.add(_para(nlp.aiSummary!.trim()));
  }

  return out;
}

// ══ Shared building blocks ════════════════════════════════════════════════════

pw.Widget _h1(String text) => pw.Padding(
  padding: const pw.EdgeInsets.only(bottom: 8),
  child: pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.only(bottom: 4),
    decoration: pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: _line, width: 1)),
    ),
    child: pw.Text(
      _safe(text),
      style: pw.TextStyle(
        fontSize: 15,
        fontWeight: pw.FontWeight.bold,
        color: _ink,
      ),
    ),
  ),
);

pw.Widget _h2(String text) => pw.Padding(
  padding: const pw.EdgeInsets.only(top: 12, bottom: 5),
  child: pw.Text(
    _safe(text.toUpperCase()),
    style: pw.TextStyle(
      fontSize: 9,
      fontWeight: pw.FontWeight.bold,
      color: _muted,
      letterSpacing: 0.5,
    ),
  ),
);

pw.Widget _summaryLine(String text) => pw.Container(
  width: double.infinity,
  padding: const pw.EdgeInsets.all(9),
  decoration: pw.BoxDecoration(
    color: _subtle,
    borderRadius: pw.BorderRadius.circular(5),
  ),
  child: pw.Text(
    _safe(text),
    style: pw.TextStyle(fontSize: 10, color: _ink, lineSpacing: 2),
  ),
);

pw.Widget _para(String text) => pw.Padding(
  padding: const pw.EdgeInsets.only(top: 2),
  child: pw.Text(
    _safe(text),
    style: pw.TextStyle(fontSize: 10, color: _ink, lineSpacing: 2.5),
  ),
);

pw.Widget _findings(List<String> items) {
  final visible = items.where((s) => s.trim().isNotEmpty).toList();
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _h2('Findings'),
      ...visible.map(
        (s) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // A drawn dot rather than a "•" glyph — the built-in font has no
              // bullet, so the character alone would render as a blank box.
              pw.Container(
                width: 10,
                padding: const pw.EdgeInsets.only(top: 4),
                child: pw.Container(
                  width: 3,
                  height: 3,
                  decoration: pw.BoxDecoration(
                    color: _muted,
                    shape: pw.BoxShape.circle,
                  ),
                ),
              ),
              pw.Expanded(
                child: pw.Text(
                  _safe(s),
                  style: pw.TextStyle(fontSize: 10, color: _ink, lineSpacing: 2),
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

pw.Widget _empty(String text) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(vertical: 6),
  child: pw.Text(
    _safe(text),
    style: pw.TextStyle(
      fontSize: 10,
      color: _muted,
      fontStyle: pw.FontStyle.italic,
    ),
  ),
);

/// A bordered table. [numeric] right-aligns those column indices; [flex] gives
/// custom column widths (index → flex weight).
pw.Widget _table(
  List<String> headers,
  List<List<String>> rows, {
  Set<int> numeric = const {},
  Map<int, double> flex = const {},
}) {
  final alignments = <int, pw.Alignment>{
    for (var i = 0; i < headers.length; i++)
      i: numeric.contains(i) ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
  };
  final widths = <int, pw.TableColumnWidth>{
    for (final e in flex.entries) e.key: pw.FlexColumnWidth(e.value),
  };

  return pw.TableHelper.fromTextArray(
    headers: [for (final h in headers) _safe(h)],
    data: [
      for (final row in rows) [for (final cell in row) _safe(cell)],
    ],
    border: pw.TableBorder.all(color: _line, width: 0.5),
    headerStyle: pw.TextStyle(
      fontSize: 8.5,
      fontWeight: pw.FontWeight.bold,
      color: _ink,
    ),
    headerDecoration: pw.BoxDecoration(color: _subtle),
    cellStyle: pw.TextStyle(fontSize: 9, color: _ink),
    cellHeight: 16,
    headerAlignments: alignments,
    cellAlignments: alignments,
    columnWidths: widths.isEmpty ? null : widths,
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
  );
}

pw.Widget _footer(pw.Context context) => pw.Container(
  alignment: pw.Alignment.centerRight,
  margin: const pw.EdgeInsets.only(top: 8),
  padding: const pw.EdgeInsets.only(top: 4),
  decoration: pw.BoxDecoration(
    border: pw.Border(top: pw.BorderSide(color: _line, width: 0.5)),
  ),
  child: pw.Text(
    _safe(
      'GovPulse · Aparri, Cagayan   —   '
      'Page ${context.pageNumber} of ${context.pagesCount}',
    ),
    style: pw.TextStyle(fontSize: 8, color: _muted),
  ),
);

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
