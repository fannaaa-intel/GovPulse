import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_reports_provider.dart'
    show reportCategoryLabel, reportStatusFromDb, ReportStatus;
import 'admin_suggestions_provider.dart' show suggestionCategoryLabel;

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
  // Suggestions and feedback are two-state — the LGU has replied or it has
  // not (see SuggestionStatus / FeedbackStatus) — so each contributes an
  // arrival event and a replied event rather than a workflow.
  suggestionNew,
  suggestionResponded,
  feedbackNew,
  feedbackResponded,
}

/// Which citizen-facing console an activity row belongs to.
///
/// The feed is a merge of four tables, and "where does a tap go" and "which
/// filter chip is this under" are the same question — so the answer lives here
/// once rather than in a switch at each call site.
enum ActivitySource { reports, suggestions, feedback, verifications }

/// One row in the "Recent activity" feed.
class ActivityItem {
  /// The submission this row is about — a `reports.id` or a
  /// `verification_submissions.id`. Carried so a tap can deep-link to the exact
  /// row in the console that owns it, the same way a notification does. Empty
  /// only if the source row somehow had no id, which makes the row unlinkable
  /// rather than mis-linked.
  final String id;
  final String title;
  final String subtitle;
  final DateTime? timestamp;
  final ActivityKind kind;

  const ActivityItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.timestamp,
    required this.kind,
  });

  /// Which console owns this event. The feed mixes four sources, so every
  /// consumer that has to pick a destination, a filter bucket or a label asks
  /// here instead of re-listing the kinds.
  ActivitySource get source => switch (kind) {
    ActivityKind.reportNew ||
    ActivityKind.reportReviewing ||
    ActivityKind.reportResolved ||
    ActivityKind.reportRejected => ActivitySource.reports,
    ActivityKind.verifPending ||
    ActivityKind.verifApproved ||
    ActivityKind.verifRejected => ActivitySource.verifications,
    ActivityKind.suggestionNew ||
    ActivityKind.suggestionResponded => ActivitySource.suggestions,
    ActivityKind.feedbackNew ||
    ActivityKind.feedbackResponded => ActivitySource.feedback,
  };

  /// True when this row describes an ID-verification submission. Kept as a
  /// named shorthand because the verification console is the one destination
  /// that is neither a submission queue nor reachable from a citizen record.
  bool get isVerification => source == ActivitySource.verifications;
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
///
/// [unknown] is not a neutral reading — it means the trend was never measured
/// (too few dated ratings for either the weekly regression or the two-window
/// comparison). It is distinct from [stable], which is a real finding: the
/// data was fitted/compared and barely moved.
enum InsightTrend { improving, declining, stable, unknown }

/// Which console owns the submissions behind a focus area, so the dashboard can
/// hand the admin straight to the place they can act on it.
///
/// Recorded here rather than inferred from the copy in the UI: this is the only
/// layer that knows whether a finding came from reports, suggestions or
/// feedback, and a title like "Public Service" is indistinguishable from an
/// office name once it reaches the widget.
enum FocusTarget { reports, suggestions, feedback }

/// A single actionable focus area under the predictive outlook: what's weak,
/// the number behind it, and a concrete suggested action.
class OutlookFocus {
  final String title; // e.g. "Wait time" / "High-urgency reports" / a theme

  /// WHERE the finding applies and how much evidence sits behind it — e.g.
  /// "Mayor's Office · 3 responses". Without this a weak score is an average
  /// blended across every office, which tells an admin nothing about what to
  /// actually fix. Null when the signal genuinely has no narrower scope.
  final String? scope;

  final String metric; // e.g. "2.6★" / "3 reports" / "4 mentions"
  final String suggestion; // concrete recommended action
  final String severity; // 'high' | 'medium' | 'low' → colour

  /// The console holding the submissions this finding is about. Null when the
  /// destination isn't known (an AI-written focus that named no source), in
  /// which case the card stays inert rather than guessing a landing page.
  final FocusTarget? target;

  /// The newest submission behind the finding, so opening the card scrolls that
  /// row into view and flashes it — the same deep-link treatment a notification
  /// gets. A focus area covers a *set* of rows, so this is the entry point into
  /// it, not the whole of it. Null when nothing concrete backs it (AI focus).
  final String? highlightId;

  const OutlookFocus({
    required this.title,
    this.scope,
    required this.metric,
    required this.suggestion,
    required this.severity,
    this.target,
    this.highlightId,
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

  /// Why this report's urgency was bumped above its own label — e.g.
  /// "3 similar open reports in Macanaya this week". Null when the urgency is
  /// the report's own (AI or rule) label. Reports only.
  final String? escalationNote;

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
    this.escalationNote,
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

  /// How many *rated* responses back each window. Drives the forecast's "why"
  /// line, so an admin can weigh a projection built on 2 responses differently
  /// from one built on 40.
  final int recentCount;
  final int priorCount;

  /// Projected next-period rating (1..5). Preferred source: a least-squares
  /// fit over weekly average ratings ([forecastWeeks] ≥ 3 buckets). When the
  /// data is too sparse for that, falls back to the two-window extrapolation
  /// (recent + delta); null when neither method has enough points.
  final double? forecastRating;
  final InsightTrend trend;

  /// Populated weekly rating buckets behind the regression forecast. 0 means
  /// the regression didn't run — [forecastRating] (if any) came from the
  /// two-window fallback. Drives the forecast's "why" line.
  final int forecastWeeks;

  /// Rated responses inside those weekly buckets (regression path only).
  final int forecastResponses;

  /// True when [forecastRating] hit the 1..5 rating scale's edge, i.e. the raw
  /// projection ran past what a star rating can express. The "why" line says
  /// so rather than presenting a clamped number as a clean projection.
  final bool forecastClamped;

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
    this.recentCount = 0,
    this.priorCount = 0,
    required this.forecastRating,
    required this.trend,
    this.forecastWeeks = 0,
    this.forecastResponses = 0,
    this.forecastClamped = false,
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
    trend: InsightTrend.unknown,
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

  /// True once the AI model labelled at least one feedback or report (when AI
  /// is unavailable everything falls back to on-device and this reads false).
  bool get usesAi => aiClassified > 0 || reportsAiClassified > 0;

  /// True when EVERY analysed row carried a model label — nothing fell back to
  /// the on-device rule. The badge then reads "AI" rather than "Hybrid AI":
  /// "hybrid" is a real, meaningful state (some rows model-labelled, some not,
  /// e.g. mid-backfill or after a rate-limit window), and showing it at full
  /// coverage made a perfectly healthy AI pipeline look half-broken.
  bool get fullyAi =>
      usesAi &&
      aiClassified == analyzed &&
      reportsAiClassified == reportsAnalyzed;

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
    // Independent reads run concurrently. The pending-verification count is
    // started here but awaited below so it overlaps the row reads: it is an
    // int, not rows, so it cannot ride in the same Future.wait.
    final pendingVerificationFuture = _countPendingVerifications();
    final results = await Future.wait<List<Map<String, dynamic>>>([
      _selectReports(),
      _selectRecentVerifications(),
      _selectFeedbacks(),
      _selectSuggestions(),
    ]);
    final pendingVerification = await pendingVerificationFuture;

    // Dismissed (spam / nonsense) rows are excluded from every metric and the
    // AI forecast. The selects now ask PostgREST to exclude them, so this is a
    // no-op safety net for the degraded column sets that have no dismissed_at
    // column at all — there, the key is simply absent and every row is active,
    // which is the same answer the filter would give.
    final reportRows =
        results[0].where((r) => r['dismissed_at'] == null).toList();
    final recentVerifRows = results[1];
    final feedbackRows =
        results[2].where((r) => r['dismissed_at'] == null).toList();
    final suggestionRows =
        results[3].where((r) => r['dismissed_at'] == null).toList();

    // AI recommendations are optional (function may not be deployed) and must
    // never break the dashboard — fetched separately and guarded.
    final aiInsight = await _selectAiInsight();

    // Self-heal a stale outlook: _nlp discards an insight older than the newest
    // submission, which would otherwise leave the panel on the on-device
    // fallback until the daily cron. Kick one regeneration in the background;
    // the completion handler (or the next poll) picks up the fresh row.
    _maybeRegenerateOutlook(feedbackRows, reportRows, suggestionRows, aiInsight);

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

    // Each source contributes its newest few, then the merge sorts by time and
    // keeps the newest overall. Taking a slice per source BEFORE the sort is
    // what stops one busy table from starving the others out of the window:
    // reports and suggestions arrive unsorted from PostgREST, so they are
    // ordered here first rather than sliced arbitrarily.
    final activity =
        <ActivityItem>[
          ...reportRows.take(6).map(_reportActivity),
          ...recentVerifRows.map(_verifActivity),
          ..._newestBy(suggestionRows, 6).map(_suggestionActivity),
          ..._newestBy(feedbackRows, 6).map(_feedbackActivity),
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
      pendingVerification: pendingVerification,
      resolutionRate: resolutionRate,
      resolutionRateDeltaPts: resolutionRateDeltaPts,
      statusCounts: statusCounts,
      topCategories: topCategories,
      reportDates: reportDates,
      satisfaction: _satisfaction(feedbackRows),
      nlp: _nlp(feedbackRows, reportRows, suggestionRows, aiInsight, now),
      // Ten, not six: with four sources merged, six rows could be a single
      // busy afternoon on one table and the card would look like it only
      // tracks that one thing — which is exactly the confusion the feed had
      // when it silently mixed two.
      recentActivity: activity.take(10).toList(),
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
    // Prefer the AI-urgency + moderation columns, degrading gracefully when a
    // migration hasn't been applied (classify-report and/or spam_moderation).
    for (final cols in [
      '$baseCols, ai_urgency, dismissed_at',
      '$baseCols, dismissed_at',
      '$baseCols, ai_urgency',
      baseCols,
    ]) {
      try {
        // Drop dismissed (spam / nonsense) rows in PostgREST rather than
        // downloading them and discarding them on the client. Only the column
        // sets that actually have the column can filter on it; the degraded
        // sets have nothing to dismiss, so they are already equivalent.
        var q = _db.from('reports').select(cols);
        if (cols.contains('dismissed_at')) {
          q = q.isFilter('dismissed_at', null);
        }
        final res = await q.order('created_at', ascending: false);
        return List<Map<String, dynamic>>.from(res);
      } catch (_) {
        // Column set unavailable — fall through to the next, smaller one.
      }
    }
    return const [];
  }

  /// How many verification submissions are awaiting review.
  ///
  /// The dashboard only ever showed `.length` of this, but used to download an
  /// id row for every pending submission to get it (audit 2026-08-24, CL-1) —
  /// on a poll tick every 30s, for every open admin tab. `from().count()` is a
  /// HEAD request: PostgREST answers from the Content-Range header and sends no
  /// rows at all, so this is constant-size regardless of the backlog.
  ///
  /// Guarded like the other reads: a failed count degrades the tile to 0 rather
  /// than taking the whole dashboard down.
  Future<int> _countPendingVerifications() async {
    try {
      return await _db
          .from('verification_submissions')
          .count(CountOption.exact)
          .eq('status', 'pending');
    } catch (_) {
      return 0;
    }
  }

  /// Citizen suggestions — what people are *asking for*, as opposed to what
  /// they rated (feedbacks) or what broke (reports). Feeds the recommended
  /// focus: a suggestion is a citizen answering "what should the LGU do next",
  /// which is exactly the question that block exists to answer.
  ///
  /// Guarded like the others: the `dismissed_at` moderation column is optional
  /// (spam_moderation migration), and any hard failure degrades to an empty
  /// list rather than taking the dashboard down.
  Future<List<Map<String, dynamic>>> _selectSuggestions() async {
    // `status` drives the activity feed's New-vs-Responded wording; it is in
    // the base set because every deployment that has the table has the column.
    const baseCols =
        'id, category, category_other, barangay, status, created_at';
    for (final cols in ['$baseCols, dismissed_at', baseCols]) {
      try {
        // Dismissed rows filtered server-side; see _selectReports.
        var q = _db.from('suggestions').select(cols);
        if (cols.contains('dismissed_at')) {
          q = q.isFilter('dismissed_at', null);
        }
        final res = await q;
        return List<Map<String, dynamic>>.from(res);
      } catch (_) {
        // Column set unavailable — fall through to the next, smaller one.
      }
    }
    return const [];
  }

  /// Last time this client kicked recommend-actions, static so tab switches /
  /// provider rebuilds share one debounce window and can't stampede the (paid)
  /// AI function.
  static DateTime? _lastOutlookKick;

  /// Fire-and-forget one recommend-actions run when the cached AI insight is
  /// stale (older than the newest submission, mirroring _nlp's freshness
  /// guard) or missing. Best-effort: any failure is swallowed and the daily
  /// cron remains the backstop.
  ///
  /// Gated on *any* citizen signal, not on feedback specifically. Gating on
  /// feedback alone meant an LGU with reports and suggestions but no ratings
  /// yet — the normal state of a fresh deployment — never kicked the function
  /// at all, so the outlook sat on the on-device fallback permanently even
  /// with a working GROQ_API_KEY. The fabricated-metric risk that motivated
  /// that gate is handled where it belongs: _nlp's rating-claim filter.
  void _maybeRegenerateOutlook(
    List<Map<String, dynamic>> feedbackRows,
    List<Map<String, dynamic>> reportRows,
    List<Map<String, dynamic>> suggestionRows,
    Map<String, dynamic>? aiInsight,
  ) {
    if (feedbackRows.isEmpty && reportRows.isEmpty && suggestionRows.isEmpty) {
      return;
    }

    final generatedAt = _parseTs(aiInsight?['generated_at']);
    DateTime? newest;
    for (final r in [...feedbackRows, ...reportRows, ...suggestionRows]) {
      final ts = _parseTs(r['created_at']);
      if (ts != null && (newest == null || ts.isAfter(newest))) newest = ts;
    }
    final stale = generatedAt == null ||
        (newest != null && generatedAt.isBefore(newest));
    if (!stale) return;

    final now = DateTime.now();
    if (_lastOutlookKick != null &&
        now.difference(_lastOutlookKick!) < const Duration(minutes: 10)) {
      return;
    }
    _lastOutlookKick = now;

    _db.functions
        .invoke('recommend-actions', body: const <String, dynamic>{})
        .then((_) => silentRefresh())
        .catchError((_) {});
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
        // `status` drives the activity feed's New-vs-Responded wording.
        'comment, status, created_at';
    // Prefer the AI sentiment/urgency + moderation columns, degrading gracefully
    // when a migration hasn't been applied (classify-feedback / spam_moderation).
    for (final cols in [
      '$baseCols, ai_sentiment, ai_urgency, dismissed_at',
      '$baseCols, dismissed_at',
      '$baseCols, ai_sentiment, ai_urgency',
      baseCols,
    ]) {
      try {
        // Dismissed rows filtered server-side; see _selectReports.
        var q = _db.from('feedbacks').select(cols);
        if (cols.contains('dismissed_at')) {
          q = q.isFilter('dismissed_at', null);
        }
        final res = await q;
        return List<Map<String, dynamic>>.from(res);
      } catch (_) {
        // Column set unavailable — fall through to the next, smaller one.
      }
    }
    return const [];
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

  /// Test seam for [_nlp]. The analysis is pure — plain rows in, [NlpInsights]
  /// out, never touching `_db` — so tests can drive it on a bare notifier
  /// without Supabase initialised. Do not call from production code.
  @visibleForTesting
  NlpInsights analyseNlp(
    List<Map<String, dynamic>> feedbackRows,
    List<Map<String, dynamic>> reportRows,
    List<Map<String, dynamic>> suggestionRows,
    Map<String, dynamic>? aiInsight,
    DateTime now,
  ) =>
      _nlp(feedbackRows, reportRows, suggestionRows, aiInsight, now);

  NlpInsights _nlp(
    List<Map<String, dynamic>> feedbackRows,
    List<Map<String, dynamic>> reportRows,
    List<Map<String, dynamic>> suggestionRows,
    Map<String, dynamic>? aiInsight,
    DateTime now,
  ) {
    // ── Sentiment + predictive outlook — from citizen FEEDBACK ───────────────
    var analyzed = 0;
    var aiClassified = 0;
    var pos = 0, neu = 0, neg = 0;
    final sentimentItems = <FeedbackInsightItem>[];

    // Predictive-outlook windows: last 30 days vs the prior 30 (drives the
    // Prior/Recent rows and the fallback forecast).
    final recentStart = now.subtract(const Duration(days: 30));
    final priorStart = now.subtract(const Duration(days: 60));
    var recentSum = 0.0, recentN = 0, priorSum = 0.0, priorN = 0;

    // Weekly rating buckets (week 0 = the 7 days ending now, 12 weeks back)
    // for the regression forecast.
    const weekWindow = 12;
    final weekSum = List<double>.filled(weekWindow, 0);
    final weekN = List<int>.filled(weekWindow, 0);

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

      // Outlook windows + weekly buckets (rating-only).
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
          final daysAgo = now.difference(ts).inDays;
          if (daysAgo >= 0 && daysAgo < weekWindow * 7) {
            final w = daysAgo ~/ 7;
            weekSum[w] += rating;
            weekN[w]++;
          }
        }
      }
    }

    // ── Urgency triage — from citizen REPORTS ────────────────────────────────
    // Two passes. The per-report label (AI or on-device rule) judges each
    // report in isolation, but three "medium" drainage reports from the same
    // barangay in a week describe ONE worsening situation — so the first pass
    // labels and counts clusters (same category + barangay, open, last 7 days),
    // and the second bumps every open member of a cluster of 3+ one level.
    var reportsAnalyzed = 0;
    var reportsAiClassified = 0;
    var high = 0, med = 0, low = 0;
    final urgencyItems = <FeedbackInsightItem>[];

    final clusterStart = now.subtract(const Duration(days: 7));
    final clusterCounts = <String, int>{};
    final triaged =
        <({Map<String, dynamic> row, String urgency, bool ai, String? cluster})>[];

    for (final r in reportRows) {
      reportsAnalyzed++;
      final key = (r['category'] as String?)?.trim().toLowerCase();
      final remarks = (r['remarks'] as String?)?.trim() ?? '';
      final barangay = (r['barangay'] as String?)?.trim() ?? '';

      // Prefer the AI urgency label from the classify-report function; fall back
      // to the on-device keyword/category rule when AI hasn't reached this row
      // (e.g. usage exhausted). It re-uses AI automatically once labels appear.
      final aiUrgency = (r['ai_urgency'] as String?)?.trim().toLowerCase();
      final hasAiUrgency = _urgencies.contains(aiUrgency);
      if (hasAiUrgency) reportsAiClassified++;
      final urgency = hasAiUrgency ? aiUrgency! : _reportUrgency(remarks, key);

      // Cluster eligibility: a real category (the "others" catch-all mixes
      // unrelated issues), a named barangay, created this week, still open.
      // Resolved/rejected reports are settled — they neither count nor bump.
      final ts = _parseTs(r['created_at']);
      final status = reportStatusFromDb(r['status'] as String?);
      final open =
          status != ReportStatus.resolved && status != ReportStatus.rejected;
      String? cluster;
      if (open &&
          key != null &&
          key.isNotEmpty &&
          key != 'others' &&
          barangay.isNotEmpty &&
          ts != null &&
          ts.isAfter(clusterStart) &&
          !ts.isAfter(now)) {
        cluster = '$key|${barangay.toLowerCase()}';
        clusterCounts[cluster] = (clusterCounts[cluster] ?? 0) + 1;
      }
      triaged.add((row: r, urgency: urgency, ai: hasAiUrgency, cluster: cluster));
    }

    const bumped = {'low': 'medium', 'medium': 'high'};
    for (final t in triaged) {
      final r = t.row;
      final key = (r['category'] as String?)?.trim().toLowerCase();
      final other = r['category_other'] as String?;
      final remarks = (r['remarks'] as String?)?.trim() ?? '';
      final barangay = (r['barangay'] as String?)?.trim() ?? '';

      var urgency = t.urgency;
      String? escalationNote;
      final clusterSize = t.cluster == null ? 0 : clusterCounts[t.cluster]!;
      if (clusterSize >= 3 && bumped.containsKey(urgency)) {
        urgency = bumped[urgency]!;
        escalationNote = '$clusterSize similar open reports in $barangay this week';
      }

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
          aiLabeled: t.ai,
          escalationNote: escalationNote,
          createdAt: _parseTs(r['created_at']),
        ),
      );
    }

    if (analyzed == 0 && reportsAnalyzed == 0) return NlpInsights.empty;

    // Predictive-outlook focus: prefer AI recommendations (recommend-actions
    // Edge Function) when present; otherwise compute them on-device (hybrid).
    //
    // GUARD: the AI outlook (summary + focus) can fabricate rating metrics
    // (e.g. "3.43 avg", "Wait time 2.57★") when there is little or no real
    // feedback to summarise. That used to be handled by refusing the AI
    // outlook outright unless feedback existed — which threw away the
    // report- and suggestion-backed items too, so an LGU with reports but no
    // ratings yet showed "On-device" forever however healthy the AI was.
    // Instead, take the AI outlook whenever ANY signal was analyzed and drop
    // only the individual items that claim a rating we have no feedback to
    // back (_claimsRating). Same protection, applied per item.
    //
    // FRESHNESS: `hasSignal` only proves submissions exist *now* — not
    // that the AI ever saw it. `_selectAiInsight` returns the newest cached row
    // whatever its age, so a row generated before the latest submissions
    // contradicts the panel it sits under ("no feedback to gauge service
    // quality" printed directly beneath a real 3.0 average). Treat the insight
    // as stale when any submission is newer than it, and fall back on-device.
    //
    // Compared row-timestamp to row-timestamp (never to local `now`), so this
    // holds regardless of device clock skew or timezone; `_parseTs` normalises
    // both sides identically.
    final hasSignal = analyzed > 0 || reportsAnalyzed > 0;
    final aiGeneratedAt = _parseTs(aiInsight?['generated_at']);
    DateTime? newestSubmission;
    for (final r in [...feedbackRows, ...reportRows, ...suggestionRows]) {
      final ts = _parseTs(r['created_at']);
      if (ts != null && (newestSubmission == null || ts.isAfter(newestSubmission))) {
        newestSubmission = ts;
      }
    }
    // An insight with no `generated_at` cannot be proven fresh — don't trust it.
    final aiIsFresh = aiGeneratedAt != null &&
        (newestSubmission == null || !aiGeneratedAt.isBefore(newestSubmission));

    // With no feedback analyzed there is no rating anywhere in the data, so a
    // focus item quoting one was invented. Drop those items; keep the rest.
    final parsedFocus = _parseAiFocus(aiInsight);
    final aiFocus = analyzed > 0
        ? parsedFocus
        : parsedFocus.where((f) => !_claimsRating(f)).toList();
    final rawSummary = (aiInsight?['summary'] as String?)?.trim();
    // The summary is one blob — it can't be filtered item-by-item, so an
    // invented rating in it disqualifies the whole sentence.
    final aiSummary = (analyzed == 0 && _mentionsRating(rawSummary))
        ? null
        : rawSummary;
    final useAiOutlook = hasSignal &&
        aiIsFresh &&
        (aiFocus.isNotEmpty || (aiSummary?.isNotEmpty ?? false));
    final focus = useAiOutlook
        ? aiFocus
        : _buildFocus(feedbackRows, suggestionRows, high, urgencyItems);

    int newestFirst(FeedbackInsightItem a, FeedbackInsightItem b) {
      final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
      final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
      return bt.compareTo(at);
    }

    sentimentItems.sort(newestFirst);
    urgencyItems.sort(newestFirst);

    final recentAvg = recentN == 0 ? null : recentSum / recentN;
    final priorAvg = priorN == 0 ? null : priorSum / priorN;

    // Forecast — preferred: least-squares fit over weekly average ratings.
    // Weekly buckets smooth single-response noise, don't care where a 30-day
    // boundary falls, and work even when every rating sits inside the recent
    // window (where the two-window method has nothing to compare). The fit
    // needs ≥3 populated weeks — two points define a line but can't show it's
    // a trend rather than noise.
    //
    // Fallback: the two-window extrapolation (recent + delta), so thin data
    // (e.g. two lone ratings six weeks apart) still yields a directional
    // forecast — the UI states its weaker basis. With neither, trend stays
    // `unknown` and the forecast stays null: reporting "Stable" from a single
    // point would present a default as a finding.
    InsightTrend trend = InsightTrend.unknown;
    double? forecast;
    var forecastClamped = false;
    var forecastWeeks = 0;
    var forecastResponses = 0;

    final xs = <double>[]; // weeks ago (0 = current week)
    final ys = <double>[]; // average rating that week
    for (var w = 0; w < weekWindow; w++) {
      if (weekN[w] > 0) {
        xs.add(w.toDouble());
        ys.add(weekSum[w] / weekN[w]);
      }
    }

    if (xs.length >= 3) {
      final n = xs.length;
      final meanX = xs.reduce((a, b) => a + b) / n;
      final meanY = ys.reduce((a, b) => a + b) / n;
      var cov = 0.0, varX = 0.0;
      for (var i = 0; i < n; i++) {
        cov += (xs[i] - meanX) * (ys[i] - meanY);
        varX += (xs[i] - meanX) * (xs[i] - meanX);
      }
      // Slope is per week *ago* (positive = the past was better); the forward
      // direction is its negation. x = -1 projects one week ahead.
      final slope = cov / varX;
      final intercept = meanY - slope * meanX;
      final raw = intercept - slope;
      forecast = raw.clamp(1.0, 5.0);
      forecastClamped = raw < 1.0 || raw > 5.0;
      // Same sensitivity as the fallback: judged on the projected 30-day change.
      final change30 = -slope * (30 / 7);
      trend = change30 > 0.15
          ? InsightTrend.improving
          : (change30 < -0.15 ? InsightTrend.declining : InsightTrend.stable);
      forecastWeeks = xs.length;
      forecastResponses = weekN.fold(0, (a, b) => a + b);
    } else if (recentAvg != null && priorAvg != null) {
      final delta = recentAvg - priorAvg;
      trend = delta > 0.15
          ? InsightTrend.improving
          : (delta < -0.15 ? InsightTrend.declining : InsightTrend.stable);
      final raw = recentAvg + delta;
      forecast = raw.clamp(1.0, 5.0);
      forecastClamped = raw < 1.0 || raw > 5.0;
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
      recentCount: recentN,
      priorCount: priorN,
      forecastRating: forecast,
      trend: trend,
      forecastWeeks: forecastWeeks,
      forecastResponses: forecastResponses,
      forecastClamped: forecastClamped,
      sentimentItems: sentimentItems,
      urgencyItems: urgencyItems,
      focus: focus,
      aiSummary: useAiOutlook ? aiSummary : null,
      outlookUsesAi: useAiOutlook,
    );
  }

  /// Any 1–5 star/rating claim in AI-written copy — "2.6★", "3.4/5",
  /// "avg 4.1", "rated 2.0". Deliberately loose: this only ever runs when NO
  /// feedback was analyzed, so there is no legitimate rating for it to catch,
  /// and a false positive costs one focus line while a miss puts an invented
  /// number in front of an admin.
  static final RegExp _ratingClaim = RegExp(
    r'\d(?:\.\d+)?\s*(?:\u2605|\u2606|/\s*5\b|stars?\b|out of 5\b)'
    r'|\b(?:avg|average|mean|rating|rated|score)\b',
    caseSensitive: false,
  );

  static bool _mentionsRating(String? text) =>
      text != null && text.isNotEmpty && _ratingClaim.hasMatch(text);

  /// True when a focus item quotes a rating anywhere an admin would read it.
  static bool _claimsRating(OutlookFocus f) =>
      _mentionsRating(f.metric) ||
      _mentionsRating(f.scope) ||
      _mentionsRating(f.title) ||
      _mentionsRating(f.suggestion);

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
      // `scope` is written by newer deploys of recommend-actions; rows from an
      // older deploy simply lack it, and the card omits the line.
      final scope = (e['scope'] as String?)?.trim();
      final cleanScope =
          (scope == null || scope.isEmpty || scope.toLowerCase() == 'null')
              ? null
              : scope;
      out.add(
        OutlookFocus(
          title: title,
          scope: cleanScope,
          metric: (e['metric'] as String?)?.trim() ?? '',
          suggestion: suggestion,
          severity: severity,
          target: _aiTarget(e['target'], title, cleanScope),
        ),
      );
    }
    return out.take(4).toList();
  }

  /// Resolves an AI focus entry to the console that owns it.
  ///
  /// Prefers an explicit `target` from the function; failing that, reads the
  /// source out of the wording it already writes ("Citizen suggestions",
  /// "3 reports"). Returns null when neither says — the card is then inert,
  /// which is better than sending an admin to a console with nothing on it.
  static FocusTarget? _aiTarget(dynamic raw, String title, String? scope) {
    const byName = {
      'reports': FocusTarget.reports,
      'report': FocusTarget.reports,
      'suggestions': FocusTarget.suggestions,
      'suggestion': FocusTarget.suggestions,
      'feedback': FocusTarget.feedback,
      'feedbacks': FocusTarget.feedback,
    };
    if (raw is String) {
      final explicit = byName[raw.trim().toLowerCase()];
      if (explicit != null) return explicit;
    }
    final text = '$title ${scope ?? ''}'.toLowerCase();
    if (text.contains('suggestion')) return FocusTarget.suggestions;
    if (text.contains('report')) return FocusTarget.reports;
    if (text.contains('feedback') || text.contains('response')) {
      return FocusTarget.feedback;
    }
    return null;
  }

  // Aspect key → (display label, suggested action). The action is stored WITHOUT
  // its final full stop so the office it applies to can be appended, turning
  // generic advice into "…checklists at Mayor's Office."
  static const _aspectActions = <String, (String, String)>{
    'aspect_staff': (
      'Staff attitude',
      'Coach front-desk staff on courtesy and responsiveness',
    ),
    'aspect_wait': (
      'Wait time',
      'Add a window or post queue numbers during peak hours',
    ),
    'aspect_clarity': (
      'Process clarity',
      'Publish clear, step-by-step requirement checklists',
    ),
    'aspect_facility': (
      'Facility',
      'Improve facility comfort — seating, signage, cleanliness',
    ),
  };

  static String _plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';

  /// Builds up to four data-backed focus areas + suggested actions:
  ///  1. outstanding high-urgency reports (most actionable),
  ///  2. the weakest service dimension below 3.5★, scoped to the office that
  ///     actually drives it,
  ///  3. the most-requested citizen suggestion category, and
  ///  4. the most common complaint theme among negative feedback (when AI
  ///     themes are available).
  /// Id of the newest row in [rows], for the deep-link flash. Rows without a
  /// timestamp still qualify (better to flash something than nothing), they
  /// just lose to any dated row.
  static String? _newestId(Iterable<Map<String, dynamic>> rows) {
    String? bestId;
    DateTime? bestTs;
    for (final r in rows) {
      final id = (r['id'] as String?)?.trim();
      if (id == null || id.isEmpty) continue;
      final ts = _parseTs(r['created_at']);
      if (bestId == null ||
          (ts != null && (bestTs == null || ts.isAfter(bestTs)))) {
        bestId = id;
        bestTs = ts;
      }
    }
    return bestId;
  }

  List<OutlookFocus> _buildFocus(
    List<Map<String, dynamic>> feedbackRows,
    List<Map<String, dynamic>> suggestionRows,
    int urgentHigh,
    List<FeedbackInsightItem> urgencyItems,
  ) {
    final out = <OutlookFocus>[];

    if (urgentHigh > 0) {
      // Newest high-urgency report — the one an admin would open first.
      String? newestHigh;
      DateTime? newestHighTs;
      for (final i in urgencyItems) {
        if (i.urgency != 'high' || i.id.isEmpty) continue;
        final ts = i.createdAt;
        if (newestHigh == null ||
            (ts != null && (newestHighTs == null || ts.isAfter(newestHighTs)))) {
          newestHigh = i.id;
          newestHighTs = ts;
        }
      }
      out.add(
        OutlookFocus(
          title: 'High-urgency reports',
          metric: _plural(urgentHigh, 'report'),
          suggestion: 'Triage and dispatch these before routine items.',
          severity: 'high',
          target: FocusTarget.reports,
          highlightId: newestHigh,
        ),
      );
    }

    // Weakest (office, aspect) pair below 3.5★.
    //
    // Deliberately NOT a global per-aspect average: averaging one dimension
    // across every office produces a number no one can act on ("Process
    // clarity 2.5★" — clarity *where*?). Scoring each office separately names
    // the office to fix, and carries the sample size so a 1-response dip reads
    // as the weak evidence it is.
    final byOffice = <String, Map<String, (double, int)>>{};
    for (final r in feedbackRows) {
      final office = (r['office_label'] as String?)?.trim() ?? '';
      for (final key in _aspectActions.keys) {
        final v = r[key];
        if (v is! num || v <= 0) continue;
        final aspects = byOffice.putIfAbsent(office, () => {});
        final (sum, n) = aspects[key] ?? (0.0, 0);
        aspects[key] = (sum + v, n + 1);
      }
    }

    String? weakestKey;
    String weakestOffice = '';
    double weakestAvg = 3.5; // only aspects below this qualify
    var weakestN = 0;
    for (final officeEntry in byOffice.entries) {
      for (final aspectEntry in officeEntry.value.entries) {
        final (sum, n) = aspectEntry.value;
        if (n == 0) continue;
        final avg = sum / n;
        if (avg < weakestAvg) {
          weakestAvg = avg;
          weakestKey = aspectEntry.key;
          weakestOffice = officeEntry.key;
          weakestN = n;
        }
      }
    }
    if (weakestKey != null) {
      final meta = _aspectActions[weakestKey]!;
      final hasOffice = weakestOffice.isNotEmpty;
      final responses = _plural(weakestN, 'response');
      // Flash a response that actually rated this aspect at this office —
      // landing on an unrelated row would not evidence the finding.
      final backing = feedbackRows.where((r) {
        final office = (r['office_label'] as String?)?.trim() ?? '';
        final v = r[weakestKey];
        return office == weakestOffice && v is num && v > 0;
      });
      out.add(
        OutlookFocus(
          title: meta.$1,
          scope: hasOffice ? '$weakestOffice · $responses' : responses,
          metric: '${weakestAvg.toStringAsFixed(1)}★',
          suggestion:
              hasOffice ? '${meta.$2} at $weakestOffice.' : '${meta.$2}.',
          severity: weakestAvg < 2.5 ? 'high' : 'medium',
          target: FocusTarget.feedback,
          highlightId: _newestId(backing),
        ),
      );
    }

    // Most-requested citizen suggestion category. Suggestions are citizens
    // stating what the LGU should do next, which is the exact question this
    // block answers — so they belong here rather than in the rating forecast,
    // which they carry no score to feed.
    final suggestionCounts = <String, int>{};
    for (final s in suggestionRows) {
      final label = suggestionCategoryLabel(
        s['category'] as String?,
        s['category_other'] as String?,
      ).trim();
      if (label.isEmpty) continue;
      suggestionCounts[label] = (suggestionCounts[label] ?? 0) + 1;
    }
    if (suggestionCounts.isNotEmpty) {
      final top = suggestionCounts.entries.reduce(
        (a, b) => a.value >= b.value ? a : b,
      );
      final backing = suggestionRows.where(
        (s) =>
            suggestionCategoryLabel(
              s['category'] as String?,
              s['category_other'] as String?,
            ).trim() ==
            top.key,
      );
      out.add(
        OutlookFocus(
          title: top.key,
          scope: 'Citizen suggestions',
          metric: _plural(top.value, 'suggestion'),
          highlightId: _newestId(backing),
          // Phrased by weight of evidence: one suggestion is not a mandate.
          suggestion: top.value >= 2
              ? 'Most-requested by citizens — review these and reply with a decision.'
              : 'Raised by a citizen — review and reply with a decision.',
          severity: 'low',
          target: FocusTarget.suggestions,
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
        final backing = feedbackRows.where(
          (r) =>
              (r['ai_sentiment'] as String?)?.trim().toLowerCase() ==
                  'negative' &&
              (r['ai_theme'] as String?)?.trim().toLowerCase() == top.key,
        );
        out.add(
          OutlookFocus(
            title: label,
            metric: '${top.value} mentions',
            suggestion: 'Investigate recurring "${top.key}" complaints.',
            severity: 'medium',
            target: FocusTarget.feedback,
            highlightId: _newestId(backing),
          ),
        );
      }
    }

    return out.take(4).toList();
  }

  ActivityItem _reportActivity(Map<String, dynamic> row) {
    final status = reportStatusFromDb(row['status'] as String?);
    final category = reportCategoryLabel(
      row['category'] as String?,
      row['category_other'] as String?,
    );
    final barangay = (row['barangay'] as String?)?.trim();
    final id = (row['id'] ?? '').toString();

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
          id: id,
          title: 'Report resolved',
          subtitle: subtitle,
          timestamp: ts,
          kind: ActivityKind.reportResolved,
        );
      case ReportStatus.rejected:
        return ActivityItem(
          id: id,
          title: 'Report rejected',
          subtitle: subtitle,
          timestamp: ts,
          kind: ActivityKind.reportRejected,
        );
      case ReportStatus.underReview:
      case ReportStatus.inProgress:
        return ActivityItem(
          id: id,
          title: 'Report in review',
          subtitle: subtitle,
          timestamp: ts,
          kind: ActivityKind.reportReviewing,
        );
      case ReportStatus.pending:
        return ActivityItem(
          id: id,
          title: 'New report submitted',
          subtitle: subtitle,
          timestamp: ts,
          kind: ActivityKind.reportNew,
        );
    }
  }

  /// A suggestion event. Two-state (see [SuggestionStatus]): it arrived, or the
  /// LGU has replied to it.
  ActivityItem _suggestionActivity(Map<String, dynamic> row) {
    final id = (row['id'] ?? '').toString();
    final category = suggestionCategoryLabel(
      row['category'] as String?,
      row['category_other'] as String?,
    );
    final barangay = (row['barangay'] as String?)?.trim();
    final parts = <String>[
      if (category.isNotEmpty) category,
      if (barangay != null && barangay.isNotEmpty) barangay,
    ];
    final subtitle = parts.isEmpty ? 'Suggestion' : parts.join(' — ');
    final ts = _parseTs(row['created_at']);
    final responded = (row['status'] as String?) == 'responded';

    return ActivityItem(
      id: id,
      title: responded ? 'Suggestion answered' : 'New suggestion submitted',
      subtitle: subtitle,
      timestamp: ts,
      kind: responded
          ? ActivityKind.suggestionResponded
          : ActivityKind.suggestionNew,
    );
  }

  /// A feedback event. Two-state like a suggestion, and captioned with the
  /// office and the rating — the two things that decide whether a rating needs
  /// looking at, without opening it.
  ActivityItem _feedbackActivity(Map<String, dynamic> row) {
    final id = (row['id'] ?? '').toString();
    final office = (row['office_label'] as String?)?.trim();
    final service = (row['service_name'] as String?)?.trim();
    final rating = (row['overall_rating'] as num?)?.round();

    final parts = <String>[
      if (office != null && office.isNotEmpty)
        office
      else if (service != null && service.isNotEmpty)
        service,
      if (rating != null) '$rating★',
    ];
    final subtitle = parts.isEmpty ? 'Feedback' : parts.join(' — ');
    final ts = _parseTs(row['created_at']);
    final responded = (row['status'] as String?) == 'responded';

    return ActivityItem(
      id: id,
      title: responded ? 'Feedback answered' : 'New feedback received',
      subtitle: subtitle,
      timestamp: ts,
      kind: responded
          ? ActivityKind.feedbackResponded
          : ActivityKind.feedbackNew,
    );
  }

  ActivityItem _verifActivity(Map<String, dynamic> row) {
    final status = (row['status'] as String?) ?? 'pending';
    final id = (row['id'] ?? '').toString();
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
          id: id,
          title: 'User verified',
          subtitle: '$display — Citizen',
          timestamp: ts,
          kind: ActivityKind.verifApproved,
        );
      case 'rejected':
        return ActivityItem(
          id: id,
          title: 'Verification rejected',
          subtitle: display,
          timestamp: ts,
          kind: ActivityKind.verifRejected,
        );
      default:
        return ActivityItem(
          id: id,
          title: 'ID verification submitted',
          subtitle: '$display — awaiting review',
          timestamp: ts,
          kind: ActivityKind.verifPending,
        );
    }
  }

  /// The [n] newest rows of [rows] by `created_at`, newest first.
  ///
  /// PostgREST returns suggestions and feedback unordered (neither select asks
  /// for an order — every other consumer aggregates them), so a bare `.take`
  /// would slice an arbitrary subset rather than the recent one.
  static List<Map<String, dynamic>> _newestBy(
    List<Map<String, dynamic>> rows,
    int n,
  ) {
    final sorted = [...rows]..sort((a, b) {
      final ta = _parseTs(a['created_at']);
      final tb = _parseTs(b['created_at']);
      if (ta == null && tb == null) return 0;
      if (ta == null) return 1;
      if (tb == null) return -1;
      return tb.compareTo(ta);
    });
    return sorted.take(n).toList();
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
