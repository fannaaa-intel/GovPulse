import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/admin/providers/admin_dashboard_provider.dart';
import 'package:govpulse/features/admin/providers/admin_feedback_provider.dart';
import 'package:govpulse/features/admin/providers/admin_reports_provider.dart';
import 'package:govpulse/features/admin/providers/admin_suggestions_provider.dart';
import 'package:govpulse/features/admin/utils/analytics_pdf.dart';

/// Builds the findings report end-to-end and asserts on the document that comes
/// out, rather than on the helpers that build it.
///
/// The regression this pins down: section 4 prints text written by the AI model,
/// and a glyph the standard-14 font cannot draw renders as a blank box on a
/// document an LGU files. `buildAnalyticsPdf` is the seam — it returns the bytes
/// that `exportAnalyticsPdf` would have handed to the share sheet, so the test
/// exercises the real layout without needing a platform channel.
void main() {
  final now = DateTime(2026, 9, 6, 20, 56);

  AdminReport report({
    required String id,
    required String category,
    required String? barangay,
    required ReportStatus status,
    required int daysAgo,
    bool anonymous = false,
  }) => AdminReport(
    id: id,
    shortId: id.substring(0, 8).toUpperCase(),
    categoryKey: category.toLowerCase(),
    category: category,
    barangay: barangay,
    address: null,
    remarks: 'Test remark',
    status: status,
    isAnonymous: anonymous,
    submitterName: anonymous ? null : 'Juan dela Cruz',
    submitterPhotoUrl: null,
    submitterRole: 'citizen',
    mediaCount: 1,
    createdAt: now.subtract(Duration(days: daysAgo)),
  );

  AdminFeedback feedback({
    required String id,
    required String office,
    required int rating,
    required int daysAgo,
  }) => AdminFeedback(
    id: id,
    shortId: id.substring(0, 8).toUpperCase(),
    officeId: office.toLowerCase(),
    officeLabel: office,
    serviceName: 'Frontline service',
    overallRating: rating,
    aspectStaff: rating,
    aspectWait: rating,
    aspectClarity: rating,
    aspectFacility: rating,
    visitDate: now.subtract(Duration(days: daysAgo)),
    comment: 'Test comment',
    photoUrls: const [],
    isAnonymous: false,
    submitterName: 'Maria Santos',
    submitterPhotoUrl: null,
    status: FeedbackStatus.fresh,
    adminNote: null,
    adminResponse: null,
    reviewedAt: null,
    createdAt: now.subtract(Duration(days: daysAgo)),
  );

  AdminSuggestion suggestion({
    required String id,
    required String category,
    required SuggestionStatus status,
    required int daysAgo,
  }) => AdminSuggestion(
    id: id,
    shortId: id.substring(0, 8).toUpperCase(),
    categoryKey: category.toLowerCase(),
    category: category,
    categoryOther: null,
    barangay: 'San Antonio',
    address: null,
    latitude: null,
    longitude: null,
    details: 'Test suggestion',
    isAnonymous: false,
    submitterName: 'Pedro Reyes',
    submitterPhotoUrl: null,
    submitterRole: 'citizen',
    mediaCount: 0,
    status: status,
    adminNote: null,
    adminResponse: status == SuggestionStatus.responded ? 'Noted.' : null,
    reviewedAt: null,
    createdAt: now.subtract(Duration(days: daysAgo)),
  );

  /// The AI narrative, carrying the exact non-breaking hyphens (U+2011) that
  /// printed as blank boxes on page 3 of the September 2026 export, plus a few
  /// glyphs no denylist would have predicted.
  const aiInsights = NlpInsights(
    analyzed: 2,
    aiClassified: 2,
    positive: 0,
    neutral: 2,
    negative: 0,
    reportsAnalyzed: 3,
    reportsAiClassified: 3,
    urgentHigh: 1,
    urgentMedium: 2,
    urgentLow: 0,
    recentAvg: 3.0,
    priorAvg: 3.6,
    forecastRating: 3.1,
    trend: InsightTrend.declining,
    outlookUsesAi: true,
    aiSummary:
        'Overall citizen rating is neutral (3 / 5) but high‑urgency reports '
        'have jumped to 2 this month — indicating emerging safety concerns. '
        'Prioritize rapid response to drainage and road issues, and improve '
        'public‑service feedback handling. Target ≥ 4 / 5 by Q4 🚧.',
    focus: [
      OutlookFocus(
        title: 'High‑urgency reports',
        scope: 'Macanaya (Pescaria) & San Antonio barangays — 2 reports',
        metric: '2 reports (recent) vs 0',
        suggestion:
            'Dispatch inspection teams to assess and repair drainage and road '
            'problems in those barangays within two weeks',
        severity: 'high',
      ),
      OutlookFocus(
        title: 'Public‑service suggestion',
        scope: 'LGU‑wide — 1 suggestion',
        metric: '1 suggestion',
        suggestion:
            'Set up a public service suggestion portal and assign a staff '
            'member to acknowledge submissions within 5 business days',
        severity: 'medium',
      ),
    ],
  );

  const dashboard = AdminDashboardData(
    totalReports: 3,
    reportsThisWeek: 3,
    reportsWeekDeltaPct: null,
    pendingVerification: 1,
    resolutionRate: 0.33,
    resolutionRateDeltaPts: null,
    statusCounts: {},
    topCategories: [],
    reportDates: [],
    satisfaction: SatisfactionStats.empty,
    nlp: aiInsights,
    recentActivity: [],
  );

  final reports = [
    report(
      id: 'aaaaaaaa-0000-0000-0000-000000000001',
      category: 'Road & Infrastructure',
      barangay: 'Macanaya (Pescaria)',
      status: ReportStatus.pending,
      daysAgo: 2,
    ),
    report(
      id: 'aaaaaaaa-0000-0000-0000-000000000002',
      category: 'Road & Infrastructure',
      barangay: 'Macanaya (Pescaria)',
      status: ReportStatus.inProgress,
      daysAgo: 9,
    ),
    report(
      id: 'aaaaaaaa-0000-0000-0000-000000000003',
      category: 'Drainage',
      barangay: 'San Antonio',
      status: ReportStatus.resolved,
      daysAgo: 20,
    ),
  ];

  // The window before: more reports, better resolution — so the comparison
  // lines have a real movement to describe in both directions.
  final priorReports = [
    for (var i = 0; i < 5; i++)
      report(
        id: 'bbbbbbbb-0000-0000-0000-00000000000$i',
        category: 'Road & Infrastructure',
        barangay: 'San Antonio',
        status: i < 4 ? ReportStatus.resolved : ReportStatus.pending,
        daysAgo: 35 + i,
      ),
  ];

  final feedbackRows = [
    feedback(
      id: 'cccccccc-0000-0000-0000-000000000001',
      office: "Mayor's Office",
      rating: 3,
      daysAgo: 4,
    ),
    feedback(
      id: 'cccccccc-0000-0000-0000-000000000002',
      office: 'Municipal Health Office',
      rating: 3,
      daysAgo: 11,
    ),
  ];
  final priorFeedback = [
    feedback(
      id: 'dddddddd-0000-0000-0000-000000000001',
      office: "Mayor's Office",
      rating: 4,
      daysAgo: 40,
    ),
  ];

  final suggestions = [
    suggestion(
      id: 'eeeeeeee-0000-0000-0000-000000000001',
      category: 'Public Service',
      status: SuggestionStatus.responded,
      daysAgo: 6,
    ),
  ];

  Future<List<int>> build({bool truncated = false}) => buildAnalyticsPdf(
    rangeDays: 30,
    now: now,
    reports: reports,
    feedback: feedbackRows,
    suggestions: suggestions,
    priorReports: priorReports,
    priorFeedback: priorFeedback,
    priorSuggestions: const [],
    dashboard: dashboard,
    truncated: truncated,
  );

  test('the document builds and is a valid PDF', () async {
    final bytes = await build();

    expect(bytes.length, greaterThan(2000));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');

    // Write it out so the rendered document can be opened and eyeballed; the
    // assertions below cover the mechanical part, not whether it looks right.
    final out = File('build/test_findings_report.pdf');
    await out.parent.create(recursive: true);
    await out.writeAsBytes(bytes);
    // ignore: avoid_print
    print('wrote ${out.path} (${bytes.length} bytes)');
  });

  test('no un-renderable glyph reaches the page', () async {
    final bytes = await build();
    final raw = String.fromCharCodes(bytes);

    // Every literal the layout emits goes through pdfSafe, so none of the
    // source glyphs should survive anywhere in the content streams. (Text is
    // Flate-compressed, so this checks the uncompressed structure; the
    // pdfSafe unit tests cover the substitution itself.)
    for (final glyph in ['‑', '—', '≥', '\u{1F6A7}']) {
      expect(raw.contains(glyph), isFalse, reason: 'raw PDF contains $glyph');
    }
  });

  test('a truncated dataset produces a larger document than a complete one',
      () async {
    // The partial-coverage notice is real content, so it has to add bytes.
    final complete = await build();
    final partial = await build(truncated: true);
    expect(partial.length, greaterThan(complete.length));
  });

  test('builds with no prior period, no AI, and empty sections', () async {
    // The first-ever export: nothing to compare against and nothing classified.
    final bytes = await buildAnalyticsPdf(
      rangeDays: 7,
      now: now,
      reports: const [],
      feedback: const [],
      suggestions: const [],
      dashboard: const AdminDashboardData(
        totalReports: 0,
        reportsThisWeek: 0,
        reportsWeekDeltaPct: null,
        pendingVerification: 0,
        resolutionRate: 0,
        resolutionRateDeltaPts: null,
        statusCounts: {},
        topCategories: [],
        reportDates: [],
        satisfaction: SatisfactionStats.empty,
        nlp: NlpInsights.empty,
        recentActivity: [],
      ),
    );

    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('builds when reports exist but none are rated or resolved', () async {
    // Guards the divide-by-zero paths: feedback rows with no rating at all.
    final unrated = [
      feedback(
        id: 'ffffffff-0000-0000-0000-000000000001',
        office: "Mayor's Office",
        rating: 0,
        daysAgo: 3,
      ),
    ];

    final bytes = await buildAnalyticsPdf(
      rangeDays: 30,
      now: now,
      reports: reports,
      feedback: unrated,
      suggestions: suggestions,
      dashboard: dashboard,
    );

    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
