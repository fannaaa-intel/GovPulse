import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_reports_provider.dart'
    show reportCategoryLabel, reportStatusFromDb, ReportStatus;

/// What kind of event an activity-feed row represents. The UI maps this to an
/// icon + colour so the provider stays free of any Flutter/material imports.
enum ActivityKind {
  reportNew,
  reportReviewing,
  reportResolved,
  reportRejected,
  verifPending,
  verifApproved,
  verifRejected,
}

/// One row in the "Recent activity" feed.
class ActivityItem {
  final String title;
  final String subtitle;
  final DateTime? timestamp;
  final ActivityKind kind;

  const ActivityItem({
    required this.title,
    required this.subtitle,
    required this.timestamp,
    required this.kind,
  });
}

/// One bar in the "Top reported categories" panel.
///
/// [isAggregate] marks the synthetic "Other categories" roll-up bar that sums
/// every category beyond the displayed leaders, so the breakdown always totals
/// 100% and no category (including the literal "Others" report category) is
/// silently dropped.
class CategoryStat {
  final String label;
  final int count;
  final double share; // 0..1, count / total categorised
  final bool isAggregate;

  const CategoryStat({
    required this.label,
    required this.count,
    required this.share,
    this.isAggregate = false,
  });
}

/// Real citizen-satisfaction summary, derived from the `feedbacks` table.
/// Maps to the "service quality indicators" described in the GovPulse paper.
/// Any average is null when there are no ratings for that dimension yet.
class SatisfactionStats {
  final double? overall; // 1..5
  final int responses;
  final double? staff;
  final double? wait;
  final double? clarity;
  final double? facility;

  const SatisfactionStats({
    required this.overall,
    required this.responses,
    required this.staff,
    required this.wait,
    required this.clarity,
    required this.facility,
  });

  static const empty = SatisfactionStats(
    overall: null,
    responses: 0,
    staff: null,
    wait: null,
    clarity: null,
    facility: null,
  );
}

/// Direction of the forecasted service-quality trend.
enum InsightTrend { improving, declining, stable }

/// A single actionable focus area under the predictive outlook: what's weak,
/// the number behind it, and a concrete suggested action.
class OutlookFocus {
  final String title; // e.g. "Wait time" / "High-urgency reports" / a theme
  final String metric; // e.g. "2.6★" / "3 reports" / "4 mentions"
  final String suggestion; // concrete recommended action
  final String severity; // 'high' | 'medium' | 'low' → colour

  const OutlookFocus({
    required this.title,
    required this.metric,
    required this.suggestion,
    required this.severity,
  });
}

/// One classified feedback response, carried so the dashboard can drill into
/// *which* responses fall in each urgency/sentiment bucket (not just counts).
class FeedbackInsightItem {
  final String id;
  final String title; // office label
  final String service; // service name (may be empty)
  final String? comment;
  final int rating; // 0 when unrated
  final String sentiment; // positive | neutral | negative
  final String urgency; // high | medium | low
  final bool aiLabeled; // true when the AI model set the labels
  final DateTime? createdAt;

  const FeedbackInsightItem({
    required this.id,
    required this.title,
    required this.service,
    required this.comment,
    required this.rating,
    required this.sentiment,
    required this.urgency,
    required this.aiLabeled,
    required this.createdAt,
  });

  /// Best one-line description: the comment if there is one, else the service.
  String get preview {
    final c = comment?.trim() ?? '';
    if (c.isNotEmpty) return c;
    return service.isNotEmpty ? service : 'No comment';
  }
}

/// On-device NLP-lite analysis of citizen feedback. Until the heavy ML pipeline
/// from the GovPulse paper is deployed server-side, we classify each feedback
/// response here from its 1–5 rating fused with a lightweight sentiment/urgency
/// lexicon over its free-text comment. It's rule-based (not a neural model), but
/// it's computed from real feedback — no placeholders.
class NlpInsights {
  // ── Sentiment — derived from citizen FEEDBACK ──────────────────────────────
  /// How many feedback responses were classified for sentiment.
  final int analyzed;

  /// Of [analyzed], how many carried a real AI label (from the Edge Function)
  /// rather than the on-device rule-based fallback. Drives the "Hybrid AI"
  /// footnote so the admin knows how much is model-classified.
  final int aiClassified;

  // Sentiment split (counts; sum == analyzed).
  final int positive;
  final int neutral;
  final int negative;

  // ── Urgency triage — derived from citizen REPORTS ──────────────────────────
  /// How many reports were triaged for urgency.
  final int reportsAnalyzed;

  /// Of [reportsAnalyzed], how many carried a real AI urgency label (from the
  /// classify-report Edge Function) rather than the on-device rule fallback.
  final int reportsAiClassified;

  // Urgency split (counts; sum == reportsAnalyzed).
  final int urgentHigh;
  final int urgentMedium;
  final int urgentLow;

  // ── Predictive outlook — from feedback rating trend ────────────────────────
  final double? recentAvg; // avg overall rating, recent window
  final double? priorAvg; // avg overall rating, prior window
  final double? forecastRating; // projected next-period rating (1..5)
  final InsightTrend trend;

  /// Classified feedback responses (for the sentiment drill-down), newest-first.
  final List<FeedbackInsightItem> sentimentItems;

  /// Triaged reports (for the urgency drill-down), newest-first.
  final List<FeedbackInsightItem> urgencyItems;

  /// Data-backed focus areas + suggested actions shown under the forecast.
  /// Sourced from the Groq recommend-actions function when available, else
  /// computed on-device (hybrid).
  final List<OutlookFocus> focus;

  /// A short AI-written narrative for the outlook (null when running on-device).
  final String? aiSummary;

  /// True when [focus]/[aiSummary] came from the AI recommendations function.
  final bool outlookUsesAi;

  const NlpInsights({
    required this.analyzed,
    required this.aiClassified,
    required this.positive,
    required this.neutral,
    required this.negative,
    required this.reportsAnalyzed,
    required this.reportsAiClassified,
    required this.urgentHigh,
    required this.urgentMedium,
    required this.urgentLow,
    required this.recentAvg,
    required this.priorAvg,
    required this.forecastRating,
    required this.trend,
    this.sentimentItems = const [],
    this.urgencyItems = const [],
    this.focus = const [],
    this.aiSummary,
    this.outlookUsesAi = false,
  });

  static const empty = NlpInsights(
    analyzed: 0,
    aiClassified: 0,
    positive: 0,
    neutral: 0,
    negative: 0,
    reportsAnalyzed: 0,
    reportsAiClassified: 0,
    urgentHigh: 0,
    urgentMedium: 0,
    urgentLow: 0,
    recentAvg: null,
    priorAvg: null,
    forecastRating: null,
    trend: InsightTrend.stable,
    sentimentItems: [],
    urgencyItems: [],
    focus: [],
  );

  /// Reports in a given urgency bucket, e.g. 'high'.
  List<FeedbackInsightItem> byUrgency(String urgency) =>
      urgencyItems.where((i) => i.urgency == urgency).toList();

  /// Feedback in a given sentiment bucket, e.g. 'negative'.
  List<FeedbackInsightItem> bySentiment(String sentiment) =>
      sentimentItems.where((i) => i.sentiment == sentiment).toList();

  /// The card shows if there's either feedback (sentiment) or reports (urgency).
  bool get hasData => analyzed > 0 || reportsAnalyzed > 0;

  /// True once the AI model labelled at least one feedback or report (so the
  /// card shows the "Hybrid AI" badge; when AI is unavailable everything falls
  /// back to on-device and this reads false).
  bool get usesAi => aiClassified > 0 || reportsAiClassified > 0;

  double _fShare(int n) => analyzed == 0 ? 0 : n / analyzed;
  double get positiveShare => _fShare(positive);
  double get neutralShare => _fShare(neutral);
  double get negativeShare => _fShare(negative);

  double _rShare(int n) => reportsAnalyzed == 0 ? 0 : n / reportsAnalyzed;
  double get highShare => _rShare(urgentHigh);
  double get mediumShare => _rShare(urgentMedium);
  double get lowShare => _rShare(urgentLow);

  /// Signed delta (recent − prior) in rating points; null when either window is
  /// empty.
  double? get trendDelta =>
      (recentAvg != null && priorAvg != null) ? recentAvg! - priorAvg! : null;
}

/// Aggregated, ready-to-render dashboard data. Every field here is backed by a
/// real Supabase table, including [nlp], the on-device NLP-lite classification
/// of citizen feedback (sentiment, urgency, predictive outlook).
class AdminDashboardData {
  final int totalReports;
  final int reportsThisWeek;

  /// Week-over-week change in new reports, as a percentage. Null when last
  /// week had zero reports (so we never divide by zero or show a fake +∞).
  final double? reportsWeekDeltaPct;

  final int pendingVerification;

  /// Resolved / total across all reports (0..1).
  final double resolutionRate;

  /// This-week resolution rate minus last-week's, in percentage *points*.
  /// Null when either window has no reports.
  final double? resolutionRateDeltaPts;

  /// Current count per lifecycle status (drives the donut).
  final Map<ReportStatus, int> statusCounts;

  /// Leaders + a trailing "Other categories" roll-up.
  final List<CategoryStat> topCategories;

  /// Every report's (non-null) creation timestamp, newest-first. The page
  /// buckets these client-side for the 7/30/90-day trend so the range toggle
  /// works without a refetch.
  final List<DateTime> reportDates;

  final SatisfactionStats satisfaction;
  final NlpInsights nlp;
  final List<ActivityItem> recentActivity;

  const AdminDashboardData({
    required this.totalReports,
    required this.reportsThisWeek,
    required this.reportsWeekDeltaPct,
    required this.pendingVerification,
    required this.resolutionRate,
    required this.resolutionRateDeltaPts,
    required this.statusCounts,
    required this.topCategories,
    required this.reportDates,
    required this.satisfaction,
    required this.nlp,
    required this.recentActivity,
  });
}

class AdminDashboardNotifier extends AsyncNotifier<AdminDashboardData> {
  SupabaseClient get _db => Supabase.instance.client;

  @override
  Future<AdminDashboardData> build() => _fetch();

  /// Re-runs every query and surfaces loading → data/error transitions.
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_fetch);
  }

  /// Background refetch that keeps the current data on screen — no loading
  /// flash. Drives the dashboard's silent auto-refresh (poll + on tab focus).
  /// A failed refetch is swallowed so a transient network blip never wipes the
  /// last-good data or shows an error banner over live numbers.
  Future<void> silentRefresh() async {
    final next = await AsyncValue.guard(_fetch);
    if (next.hasValue) state = next;
  }

  Future<AdminDashboardData> _fetch() async {
    // Independent reads run concurrently.
    final results = await Future.wait<List<Map<String, dynamic>>>([
      _selectReports(),
      _selectPendingVerifications(),
      _selectRecentVerifications(),
      _selectFeedbacks(),
    ]);

    final reportRows = results[0];
    final pendingRows = results[1];
    final recentVerifRows = results[2];
    final feedbackRows = results[3];

    // AI recommendations are optional (function may not be deployed) and must
    // never break the dashboard — fetched separately and guarded.
    final aiInsight = await _selectAiInsight();

    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    final twoWeeksAgo = now.subtract(const Duration(days: 14));

    final totalReports = reportRows.length;
    final reportsThisWeek = _countIn(reportRows, weekAgo, now);
    final reportsLastWeek = _countIn(reportRows, twoWeeksAgo, weekAgo);
    final reportsWeekDeltaPct = reportsLastWeek == 0
        ? null
        : (reportsThisWeek - reportsLastWeek) / reportsLastWeek * 100;

    final statusCounts = _statusCounts(reportRows);
    final resolved = statusCounts[ReportStatus.resolved] ?? 0;
    final resolutionRate = totalReports == 0 ? 0.0 : resolved / totalReports;
    final resolutionRateDeltaPts = _resolutionDelta(
      reportRows,
      thisStart: weekAgo,
      lastStart: twoWeeksAgo,
      now: now,
    );

    final topCategories = _topCategories(reportRows);

    final reportDates = <DateTime>[
      for (final r in reportRows)
        if (_parseTs(r['created_at']) != null) _parseTs(r['created_at'])!,
    ];

    final activity =
        <ActivityItem>[
          ...reportRows.take(6).map(_reportActivity),
          ...recentVerifRows.map(_verifActivity),
        ]..sort((a, b) {
          final ta = a.timestamp;
          final tb = b.timestamp;
          if (ta == null && tb == null) return 0;
          if (ta == null) return 1;
          if (tb == null) return -1;
          return tb.compareTo(ta); // newest first
        });

    return AdminDashboardData(
      totalReports: totalReports,
      reportsThisWeek: reportsThisWeek,
      reportsWeekDeltaPct: reportsWeekDeltaPct,
      pendingVerification: pendingRows.length,
      resolutionRate: resolutionRate,
      resolutionRateDeltaPts: resolutionRateDeltaPts,
      statusCounts: statusCounts,
      topCategories: topCategories,
      reportDates: reportDates,
      satisfaction: _satisfaction(feedbackRows),
      nlp: _nlp(feedbackRows, reportRows, aiInsight, now),
      recentActivity: activity.take(6).toList(),
    );
  }

  // ── Queries ────────────────────────────────────────────────────────────────

  /// All citizen reports, newest first. (`reports` is the issue-report table
  /// the citizen app writes to — distinct from `concern_tickets`, which is the
  /// chat-agent flow.) At barangay scale this fetch is small; for very large
  /// datasets switch the count to a `.count(CountOption.exact)` head request.
  Future<List<Map<String, dynamic>>> _selectReports() async {
    const baseCols =
        'id, category, category_other, barangay, remarks, status, created_at';
    // Try WITH the AI urgency column; if the classify-report migration hasn't
    // been applied yet the query errors, so retry without it (on-device only).
    try {
      final res = await _db
          .from('reports')
          .select('$baseCols, ai_urgency')
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(res);
    } catch (_) {
      final res = await _db
          .from('reports')
          .select(baseCols)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(res);
    }
  }

  Future<List<Map<String, dynamic>>> _selectPendingVerifications() async {
    final res = await _db
        .from('verification_submissions')
        .select('id')
        .eq('status', 'pending');
    return List<Map<String, dynamic>>.from(res);
  }

  /// The latest AI recommendation row written by the recommend-actions Edge
  /// Function. Guarded: a missing table (function not deployed yet) or any read
  /// error just returns null → the outlook falls back to on-device focus areas.
  Future<Map<String, dynamic>?> _selectAiInsight() async {
    try {
      return await _db
          .from('ai_dashboard_insights')
          .select('summary, focus, generated_at')
          .order('generated_at', ascending: false)
          .limit(1)
          .maybeSingle();
    } catch (_) {
      return null;
    }
  }

  /// Verification rows for the activity feed. We merge two windows so the feed
  /// reflects what actually happened *recently*:
  ///  • the latest submissions (drives "ID verification submitted" rows), and
  ///  • the latest reviews (drives "User verified"/"rejected" rows — whose event
  ///    time is `reviewed_at`, which can be far newer than the original
  ///    `created_at`).
  /// Without the second window, approving a long-pending submission would keep
  /// it buried by its old `created_at` and it would never surface here.
  Future<List<Map<String, dynamic>>> _selectRecentVerifications() async {
    const cols = 'id, status, first_name, last_name, created_at, reviewed_at';
    final windows = await Future.wait<List<Map<String, dynamic>>>([
      _db
          .from('verification_submissions')
          .select(cols)
          .order('created_at', ascending: false)
          .limit(6)
          .then(List<Map<String, dynamic>>.from),
      _db
          .from('verification_submissions')
          .select(cols)
          .not('reviewed_at', 'is', null)
          .order('reviewed_at', ascending: false)
          .limit(6)
          .then(List<Map<String, dynamic>>.from),
    ]);

    // Dedupe by id (a row can appear in both windows).
    final byId = <String, Map<String, dynamic>>{};
    for (final row in [...windows[0], ...windows[1]]) {
      byId[row['id'] as String] = row;
    }
    return byId.values.toList();
  }

  /// Citizen service-quality ratings (1..5 overall + four aspects) plus the
  /// optional AI classification columns (`ai_sentiment`/`ai_urgency`) written by
  /// the classify-feedback Edge Function. Guarded twice: first we try the query
  /// WITH the AI columns; if they don't exist yet (function not deployed) the
  /// query errors, so we retry WITHOUT them. Either way a hard failure degrades
  /// to an empty list rather than breaking the whole dashboard fetch.
  Future<List<Map<String, dynamic>>> _selectFeedbacks() async {
    const baseCols =
        'id, office_label, service_name, overall_rating, '
        'aspect_staff, aspect_wait, aspect_clarity, aspect_facility, '
        'comment, created_at';
    try {
      final res = await _db
          .from('feedbacks')
          .select('$baseCols, ai_sentiment, ai_urgency');
      return List<Map<String, dynamic>>.from(res);
    } catch (_) {
      // AI columns not present yet — fall back to the base columns.
      try {
        final res = await _db.from('feedbacks').select(baseCols);
        return List<Map<String, dynamic>>.from(res);
      } catch (_) {
        return const [];
      }
    }
  }

  // ── Derivations ──────────────────────────────────────────────────────────

  int _countIn(List<Map<String, dynamic>> rows, DateTime start, DateTime end) {
    var n = 0;
    for (final r in rows) {
      final ts = _parseTs(r['created_at']);
      if (ts != null && ts.isAfter(start) && !ts.isAfter(end)) n++;
    }
    return n;
  }

  Map<ReportStatus, int> _statusCounts(List<Map<String, dynamic>> rows) {
    final counts = <ReportStatus, int>{
      ReportStatus.pending: 0,
      ReportStatus.underReview: 0,
      ReportStatus.inProgress: 0,
      ReportStatus.resolved: 0,
      ReportStatus.rejected: 0,
    };
    for (final r in rows) {
      final s = reportStatusFromDb(r['status'] as String?);
      counts[s] = (counts[s] ?? 0) + 1;
    }
    return counts;
  }

  /// Resolution rate for reports *created* this week vs last week, returned as
  /// a difference in percentage points. Null when either window is empty.
  double? _resolutionDelta(
    List<Map<String, dynamic>> rows, {
    required DateTime thisStart,
    required DateTime lastStart,
    required DateTime now,
  }) {
    var thisTotal = 0, thisResolved = 0, lastTotal = 0, lastResolved = 0;
    for (final r in rows) {
      final ts = _parseTs(r['created_at']);
      if (ts == null) continue;
      final isResolved =
          reportStatusFromDb(r['status'] as String?) == ReportStatus.resolved;
      if (ts.isAfter(thisStart) && !ts.isAfter(now)) {
        thisTotal++;
        if (isResolved) thisResolved++;
      } else if (ts.isAfter(lastStart) && !ts.isAfter(thisStart)) {
        lastTotal++;
        if (isResolved) lastResolved++;
      }
    }
    if (thisTotal == 0 || lastTotal == 0) return null;
    final thisRate = thisResolved / thisTotal;
    final lastRate = lastResolved / lastTotal;
    return (thisRate - lastRate) * 100;
  }

  /// Counts every report against the full GovPulse service taxonomy, so the
  /// admin always sees the complete picture — including categories with zero
  /// reports — with an **Others** catch-all pinned last (it absorbs the
  /// free-text "others" submissions and any unknown keys). Shares are over the
  /// total categorised reports, so the visible bars sum to 100%.
  List<CategoryStat> _topCategories(List<Map<String, dynamic>> rows) {
    // Canonical category keys → display labels, in their natural order.
    const known = <String, String>{
      'road': 'Road & Infrastructure',
      'waste': 'Waste & Garbage',
      'drainage': 'Drainage & Flooding',
      'streetlight': 'Streetlight Outage',
      'environment': 'Environment & Pollution',
    };
    const otherLabel = 'Others';

    final counts = <String, int>{for (final l in known.values) l: 0};
    counts[otherLabel] = 0;

    for (final r in rows) {
      final key = (r['category'] as String?)?.trim().toLowerCase();
      // Anything that isn't a known service category — the 'others' selection
      // (with or without free text) and any stray/unknown key — folds into the
      // single Others bucket.
      final label = known[key] ?? otherLabel;
      counts[label] = (counts[label] ?? 0) + 1;
    }

    final total = counts.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) return const [];

    // Real categories ranked by volume; Others always trails as the catch-all.
    final real = counts.entries.where((e) => e.key != otherLabel).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final out = <CategoryStat>[
      for (final e in real)
        CategoryStat(label: e.key, count: e.value, share: e.value / total),
      CategoryStat(
        label: otherLabel,
        count: counts[otherLabel] ?? 0,
        share: (counts[otherLabel] ?? 0) / total,
        isAggregate: true,
      ),
    ];
    return out;
  }

  SatisfactionStats _satisfaction(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return SatisfactionStats.empty;
    double? avg(String key) {
      var sum = 0.0;
      var n = 0;
      for (final r in rows) {
        final v = r[key];
        final d = v is num ? v.toDouble() : null;
        if (d != null && d > 0) {
          sum += d;
          n++;
        }
      }
      return n == 0 ? null : sum / n;
    }

    final overallResponses = rows.where((r) {
      final v = r['overall_rating'];
      return v is num && v > 0;
    }).length;

    return SatisfactionStats(
      overall: avg('overall_rating'),
      responses: overallResponses,
      staff: avg('aspect_staff'),
      wait: avg('aspect_wait'),
      clarity: avg('aspect_clarity'),
      facility: avg('aspect_facility'),
    );
  }

  // ── NLP-lite classification ─────────────────────────────────────────────
  //
  // Lexicons kept deliberately small and high-signal. Sentiment fuses the 1–5
  // rating (strong prior) with keyword polarity from the comment; urgency is
  // driven by low ratings and explicit urgency words.
  static const _positiveWords = {
    'good',
    'great',
    'excellent',
    'helpful',
    'fast',
    'friendly',
    'satisfied',
    'thank',
    'thanks',
    'nice',
    'smooth',
    'efficient',
    'accommodating',
    'kind',
    'wonderful',
    'appreciate',
    'clean',
    'quick',
    'polite',
    'love',
    'best',
  };
  static const _negativeWords = {
    'slow',
    'rude',
    'bad',
    'poor',
    'terrible',
    'worst',
    'delay',
    'delayed',
    'waiting',
    'long',
    'dirty',
    'unhelpful',
    'confusing',
    'difficult',
    'disappointed',
    'complaint',
    'problem',
    'issue',
    'angry',
    'frustrating',
    'unacceptable',
    'never',
    'horrible',
    'lacking',
  };
  // Report-urgency lexicon — safety / time-critical words that push a report to
  // "high" regardless of its category.
  static const _urgentWords = {
    'urgent',
    'immediately',
    'emergency',
    'dangerous',
    'danger',
    'unsafe',
    'broken',
    'hazard',
    'asap',
    'critical',
    'serious',
    'flood',
    'flooding',
    'accident',
    'injury',
    'fire',
    'collapse',
    'sinkhole',
    'leak',
    'overflow',
    'exposed',
    'risk',
    'deep',
  };

  // Categories with an inherent safety / infrastructure dimension → at least
  // "medium" urgency even without alarming words in the remarks.
  static const _safetyCategories = {'road', 'drainage', 'streetlight'};

  static int _countMatches(List<String> tokens, Set<String> lexicon) {
    var n = 0;
    for (final t in tokens) {
      if (lexicon.contains(t)) n++;
    }
    return n;
  }

  static const _sentiments = {'positive', 'neutral', 'negative'};
  static const _urgencies = {'high', 'medium', 'low'};

  /// Rule-based urgency for a citizen report: alarming words in the remarks →
  /// high; a safety/infrastructure category → medium; everything else → low.
  String _reportUrgency(String remarks, String? categoryKey) {
    final tokens = remarks
        .toLowerCase()
        .split(RegExp(r'[^a-z]+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (_countMatches(tokens, _urgentWords) > 0) return 'high';
    if (_safetyCategories.contains(categoryKey)) return 'medium';
    return 'low';
  }

  NlpInsights _nlp(
    List<Map<String, dynamic>> feedbackRows,
    List<Map<String, dynamic>> reportRows,
    Map<String, dynamic>? aiInsight,
    DateTime now,
  ) {
    // ── Sentiment + predictive outlook — from citizen FEEDBACK ───────────────
    var analyzed = 0;
    var aiClassified = 0;
    var pos = 0, neu = 0, neg = 0;
    final sentimentItems = <FeedbackInsightItem>[];

    // Predictive-outlook windows: last 30 days vs the prior 30.
    final recentStart = now.subtract(const Duration(days: 30));
    final priorStart = now.subtract(const Duration(days: 60));
    var recentSum = 0.0, recentN = 0, priorSum = 0.0, priorN = 0;

    for (final r in feedbackRows) {
      final ratingRaw = r['overall_rating'];
      final rating = ratingRaw is num ? ratingRaw.toInt() : 0;
      final commentLower =
          (r['comment'] as String?)?.trim().toLowerCase() ?? '';
      final hasRating = rating > 0;
      final hasComment = commentLower.isNotEmpty;
      if (!hasRating && !hasComment) continue; // nothing to classify

      analyzed++;

      // Prefer the AI sentiment label from the Edge Function; else on-device.
      final aiSentiment = (r['ai_sentiment'] as String?)?.trim().toLowerCase();
      final hasAiSentiment = _sentiments.contains(aiSentiment);
      if (hasAiSentiment) aiClassified++;

      final tokens = hasComment
          ? commentLower
                .split(RegExp(r'[^a-z]+'))
                .where((t) => t.isNotEmpty)
                .toList()
          : const <String>[];
      final posHits = _countMatches(tokens, _positiveWords);
      final negHits = _countMatches(tokens, _negativeWords);

      final String sentiment;
      if (hasAiSentiment) {
        sentiment = aiSentiment!;
      } else {
        var score = 0;
        if (hasRating) score += rating >= 4 ? 1 : (rating <= 2 ? -1 : 0);
        if (hasComment) {
          score += posHits > negHits ? 1 : (negHits > posHits ? -1 : 0);
        }
        sentiment = score > 0
            ? 'positive'
            : (score < 0 ? 'negative' : 'neutral');
      }
      switch (sentiment) {
        case 'positive':
          pos++;
        case 'negative':
          neg++;
        default:
          neu++;
      }

      final rawComment = (r['comment'] as String?)?.trim();
      sentimentItems.add(
        FeedbackInsightItem(
          id: (r['id'] as String?) ?? '',
          title: (r['office_label'] as String?)?.trim().isNotEmpty == true
              ? (r['office_label'] as String).trim()
              : 'Feedback',
          service: (r['service_name'] as String?)?.trim() ?? '',
          comment: (rawComment != null && rawComment.isNotEmpty)
              ? rawComment
              : null,
          rating: rating,
          sentiment: sentiment,
          urgency: '', // n/a for feedback
          aiLabeled: hasAiSentiment,
          createdAt: _parseTs(r['created_at']),
        ),
      );

      // Outlook windows (rating-only).
      if (hasRating) {
        final ts = _parseTs(r['created_at']);
        if (ts != null) {
          if (ts.isAfter(recentStart) && !ts.isAfter(now)) {
            recentSum += rating;
            recentN++;
          } else if (ts.isAfter(priorStart) && !ts.isAfter(recentStart)) {
            priorSum += rating;
            priorN++;
          }
        }
      }
    }

    // ── Urgency triage — from citizen REPORTS ────────────────────────────────
    var reportsAnalyzed = 0;
    var reportsAiClassified = 0;
    var high = 0, med = 0, low = 0;
    final urgencyItems = <FeedbackInsightItem>[];

    for (final r in reportRows) {
      reportsAnalyzed++;
      final key = (r['category'] as String?)?.trim().toLowerCase();
      final other = r['category_other'] as String?;
      final remarks = (r['remarks'] as String?)?.trim() ?? '';
      final barangay = (r['barangay'] as String?)?.trim() ?? '';

      // Prefer the AI urgency label from the classify-report function; fall back
      // to the on-device keyword/category rule when AI hasn't reached this row
      // (e.g. usage exhausted). It re-uses AI automatically once labels appear.
      final aiUrgency = (r['ai_urgency'] as String?)?.trim().toLowerCase();
      final hasAiUrgency = _urgencies.contains(aiUrgency);
      if (hasAiUrgency) reportsAiClassified++;
      final urgency = hasAiUrgency ? aiUrgency! : _reportUrgency(remarks, key);

      switch (urgency) {
        case 'high':
          high++;
        case 'medium':
          med++;
        default:
          low++;
      }
      urgencyItems.add(
        FeedbackInsightItem(
          id: (r['id'] as String?) ?? '',
          title: reportCategoryLabel(key, other),
          service: barangay,
          comment: remarks.isNotEmpty ? remarks : null,
          rating: 0,
          sentiment: '', // n/a for reports
          urgency: urgency,
          aiLabeled: hasAiUrgency,
          createdAt: _parseTs(r['created_at']),
        ),
      );
    }

    if (analyzed == 0 && reportsAnalyzed == 0) return NlpInsights.empty;

    // Predictive-outlook focus: prefer AI recommendations (recommend-actions
    // Edge Function) when present; otherwise compute them on-device (hybrid).
    final aiFocus = _parseAiFocus(aiInsight);
    final aiSummary = (aiInsight?['summary'] as String?)?.trim();
    final useAiOutlook = aiFocus.isNotEmpty || (aiSummary?.isNotEmpty ?? false);
    final focus = aiFocus.isNotEmpty
        ? aiFocus
        : _buildFocus(feedbackRows, high);

    int newestFirst(FeedbackInsightItem a, FeedbackInsightItem b) {
      final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
      final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
      return bt.compareTo(at);
    }

    sentimentItems.sort(newestFirst);
    urgencyItems.sort(newestFirst);

    final recentAvg = recentN == 0 ? null : recentSum / recentN;
    final priorAvg = priorN == 0 ? null : priorSum / priorN;

    InsightTrend trend = InsightTrend.stable;
    double? forecast;
    if (recentAvg != null && priorAvg != null) {
      final delta = recentAvg - priorAvg;
      trend = delta > 0.15
          ? InsightTrend.improving
          : (delta < -0.15 ? InsightTrend.declining : InsightTrend.stable);
      forecast = (recentAvg + delta).clamp(1.0, 5.0);
    } else if (recentAvg != null) {
      forecast = recentAvg; // one window only — project it flat.
    }

    return NlpInsights(
      analyzed: analyzed,
      aiClassified: aiClassified,
      positive: pos,
      neutral: neu,
      negative: neg,
      reportsAnalyzed: reportsAnalyzed,
      reportsAiClassified: reportsAiClassified,
      urgentHigh: high,
      urgentMedium: med,
      urgentLow: low,
      recentAvg: recentAvg,
      priorAvg: priorAvg,
      forecastRating: forecast,
      trend: trend,
      sentimentItems: sentimentItems,
      urgencyItems: urgencyItems,
      focus: focus,
      aiSummary: useAiOutlook ? aiSummary : null,
      outlookUsesAi: useAiOutlook,
    );
  }

  /// Parses the `focus` jsonb from the AI insight row into [OutlookFocus]es.
  /// Tolerant: anything malformed is skipped, so a bad row never breaks the UI.
  List<OutlookFocus> _parseAiFocus(Map<String, dynamic>? aiInsight) {
    final raw = aiInsight?['focus'];
    if (raw is! List) return const [];
    const severities = {'high', 'medium', 'low'};
    final out = <OutlookFocus>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final title = (e['title'] as String?)?.trim() ?? '';
      final suggestion = (e['suggestion'] as String?)?.trim() ?? '';
      if (title.isEmpty || suggestion.isEmpty) continue;
      var severity =
          (e['severity'] as String?)?.trim().toLowerCase() ?? 'medium';
      if (!severities.contains(severity)) severity = 'medium';
      out.add(
        OutlookFocus(
          title: title,
          metric: (e['metric'] as String?)?.trim() ?? '',
          suggestion: suggestion,
          severity: severity,
        ),
      );
    }
    return out.take(4).toList();
  }

  // Aspect key → (display label, suggested action) for the outlook's focus areas.
  static const _aspectActions = <String, (String, String)>{
    'aspect_staff': (
      'Staff attitude',
      'Coach front-desk staff on courtesy and responsiveness.',
    ),
    'aspect_wait': (
      'Wait time',
      'Add a window or post queue numbers during peak hours.',
    ),
    'aspect_clarity': (
      'Process clarity',
      'Publish clear, step-by-step requirement checklists.',
    ),
    'aspect_facility': (
      'Facility',
      'Improve facility comfort — seating, signage, cleanliness.',
    ),
  };

  /// Builds up to three data-backed focus areas + suggested actions:
  ///  1. outstanding high-urgency reports (most actionable),
  ///  2. the weakest service dimension below 3.5★, and
  ///  3. the most common complaint theme among negative feedback (when AI
  ///     themes are available).
  List<OutlookFocus> _buildFocus(
    List<Map<String, dynamic>> feedbackRows,
    int urgentHigh,
  ) {
    final out = <OutlookFocus>[];

    if (urgentHigh > 0) {
      out.add(
        OutlookFocus(
          title: 'High-urgency reports',
          metric: '$urgentHigh report${urgentHigh == 1 ? '' : 's'}',
          suggestion: 'Triage and dispatch these before routine items.',
          severity: 'high',
        ),
      );
    }

    // Weakest aspect below 3.5★.
    String? weakestKey;
    double weakestAvg = 3.5; // only aspects below this qualify
    for (final entry in _aspectActions.entries) {
      var sum = 0.0, n = 0;
      for (final r in feedbackRows) {
        final v = r[entry.key];
        if (v is num && v > 0) {
          sum += v;
          n++;
        }
      }
      if (n == 0) continue;
      final avg = sum / n;
      if (avg < weakestAvg) {
        weakestAvg = avg;
        weakestKey = entry.key;
      }
    }
    if (weakestKey != null) {
      final meta = _aspectActions[weakestKey]!;
      out.add(
        OutlookFocus(
          title: meta.$1,
          metric: '${weakestAvg.toStringAsFixed(1)}★',
          suggestion: meta.$2,
          severity: weakestAvg < 2.5 ? 'high' : 'medium',
        ),
      );
    }

    // Top complaint theme among negative feedback (AI themes only).
    const skipThemes = {'', 'rating', 'general', 'none', 'n/a'};
    final themeCounts = <String, int>{};
    for (final r in feedbackRows) {
      final sentiment = (r['ai_sentiment'] as String?)?.trim().toLowerCase();
      if (sentiment != 'negative') continue;
      final theme = (r['ai_theme'] as String?)?.trim().toLowerCase() ?? '';
      if (skipThemes.contains(theme)) continue;
      themeCounts[theme] = (themeCounts[theme] ?? 0) + 1;
    }
    if (themeCounts.isNotEmpty) {
      final top = themeCounts.entries.reduce(
        (a, b) => a.value >= b.value ? a : b,
      );
      if (top.value >= 2) {
        final label = top.key[0].toUpperCase() + top.key.substring(1);
        out.add(
          OutlookFocus(
            title: label,
            metric: '${top.value} mentions',
            suggestion: 'Investigate recurring "${top.key}" complaints.',
            severity: 'medium',
          ),
        );
      }
    }

    return out.take(3).toList();
  }

  ActivityItem _reportActivity(Map<String, dynamic> row) {
    final status = reportStatusFromDb(row['status'] as String?);
    final category = reportCategoryLabel(
      row['category'] as String?,
      row['category_other'] as String?,
    );
    final barangay = (row['barangay'] as String?)?.trim();

    final subtitleParts = <String>[
      if (category.isNotEmpty) category,
      if (barangay != null && barangay.isNotEmpty) barangay,
    ];
    final subtitle = subtitleParts.isEmpty
        ? 'Report'
        : subtitleParts.join(' — ');
    final ts = _parseTs(row['created_at']);

    switch (status) {
      case ReportStatus.resolved:
        return ActivityItem(
          title: 'Report resolved',
          subtitle: subtitle,
          timestamp: ts,
          kind: ActivityKind.reportResolved,
        );
      case ReportStatus.rejected:
        return ActivityItem(
          title: 'Report rejected',
          subtitle: subtitle,
          timestamp: ts,
          kind: ActivityKind.reportRejected,
        );
      case ReportStatus.underReview:
      case ReportStatus.inProgress:
        return ActivityItem(
          title: 'Report in review',
          subtitle: subtitle,
          timestamp: ts,
          kind: ActivityKind.reportReviewing,
        );
      case ReportStatus.pending:
        return ActivityItem(
          title: 'New report submitted',
          subtitle: subtitle,
          timestamp: ts,
          kind: ActivityKind.reportNew,
        );
    }
  }

  ActivityItem _verifActivity(Map<String, dynamic> row) {
    final status = (row['status'] as String?) ?? 'pending';
    final name = '${row['first_name'] ?? ''} ${row['last_name'] ?? ''}'.trim();
    final display = name.isEmpty ? 'Citizen' : name;
    // Reviewed rows are events at `reviewed_at`; a pending row's event is its
    // submission (`created_at`). Falling back to created_at keeps the row from
    // ever losing its timestamp.
    final ts = status == 'pending'
        ? _parseTs(row['created_at'])
        : (_parseTs(row['reviewed_at']) ?? _parseTs(row['created_at']));

    switch (status) {
      case 'approved':
        return ActivityItem(
          title: 'User verified',
          subtitle: '$display — Citizen',
          timestamp: ts,
          kind: ActivityKind.verifApproved,
        );
      case 'rejected':
        return ActivityItem(
          title: 'Verification rejected',
          subtitle: display,
          timestamp: ts,
          kind: ActivityKind.verifRejected,
        );
      default:
        return ActivityItem(
          title: 'ID verification submitted',
          subtitle: '$display — awaiting review',
          timestamp: ts,
          kind: ActivityKind.verifPending,
        );
    }
  }

  static DateTime? _parseTs(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v.toLocal();
    if (v is String) return DateTime.tryParse(v)?.toLocal();
    return null;
  }
}

final adminDashboardProvider =
    AsyncNotifierProvider<AdminDashboardNotifier, AdminDashboardData>(
      AdminDashboardNotifier.new,
    );
