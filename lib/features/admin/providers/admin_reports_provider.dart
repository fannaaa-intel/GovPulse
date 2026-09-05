import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ── Report domain helpers (shared with the dashboard provider) ───────────────

/// Same category-key → label mapping the citizen app uses, so the admin side
/// labels reports identically.
String reportCategoryLabel(String? key, String? other) {
  switch (key) {
    case 'road':
      return 'Road & Infrastructure';
    case 'waste':
      return 'Waste & Garbage';
    case 'drainage':
      return 'Drainage & Flooding';
    case 'streetlight':
      return 'Streetlight Outage';
    case 'environment':
      return 'Environment & Pollution';
    case 'others':
      return (other != null && other.isNotEmpty) ? other : 'Others';
    default:
      return key ?? 'Others';
  }
}

/// Lifecycle an admin can move a report through.
enum ReportStatus { pending, underReview, inProgress, resolved, rejected }

ReportStatus reportStatusFromDb(String? s) {
  switch (s) {
    case 'under_review':
      return ReportStatus.underReview;
    case 'in_progress':
      return ReportStatus.inProgress;
    case 'resolved':
      return ReportStatus.resolved;
    case 'rejected':
      return ReportStatus.rejected;
    default:
      return ReportStatus.pending;
  }
}

String reportStatusToDb(ReportStatus s) {
  switch (s) {
    case ReportStatus.pending:
      return 'pending';
    case ReportStatus.underReview:
      return 'under_review';
    case ReportStatus.inProgress:
      return 'in_progress';
    case ReportStatus.resolved:
      return 'resolved';
    case ReportStatus.rejected:
      return 'rejected';
  }
}

String reportStatusLabel(ReportStatus s) {
  switch (s) {
    case ReportStatus.pending:
      return 'Pending';
    case ReportStatus.underReview:
      return 'Under review';
    case ReportStatus.inProgress:
      return 'In progress';
    case ReportStatus.resolved:
      return 'Resolved';
    case ReportStatus.rejected:
      return 'Rejected';
  }
}

// ── Model ────────────────────────────────────────────────────────────────────

class AdminReport {
  final String id; // full uuid
  final String shortId; // first 8 chars, upper
  final String categoryKey;
  final String category; // display label
  final String? barangay;
  final String? address;
  final String remarks;
  final ReportStatus status;
  final bool isAnonymous;

  /// Submitter identity — always null for anonymous reports (never fetched).
  final String? submitterName;
  final String? submitterPhotoUrl;
  final String? submitterRole; // 'admin' | 'staff' | 'citizen'

  final int mediaCount;
  final DateTime? createdAt;

  /// Soft-moderation: non-null when an admin dismissed this row as spam/nonsense.
  /// Dismissed rows are hidden from the default list and excluded from analytics.
  final DateTime? dismissedAt;
  final String? dismissedReason;

  /// External entity this report was endorsed to (out-of-LGU scope), e.g.
  /// "DPWH". Non-null means ownership has been handed out of the LGU — these
  /// rows drop out of the active admin queue into the "Endorsed" bucket.
  final String? endorsedToDepartment;
  final DateTime? endorsedAt;

  /// Internal LGU office the admin ACCEPTED this report to (e.g. "Sanitation
  /// Office"). Null while still on the admin's triage desk (pending). Mutually
  /// exclusive with [endorsedToDepartment].
  final String? assignedToDepartment;
  final DateTime? assignedAt;

  /// Display name of the admin who accepted this report at triage, resolved
  /// from `assigned_by`. Null when unaccepted, or when the acceptor's profile
  /// can't be read (the status tracker then just omits the "Accepted by" line).
  final String? assignedByName;

  /// Reason captured when a report is rejected at triage (shown to the citizen).
  final String? rejectionNote;

  /// Non-null when this report confirms another one (report_duplicates.sql).
  /// Duplicates are NOT their own ticket — they're held out of every queue
  /// bucket and surface only as a confirmation count on the canonical report.
  final String? duplicateOf;

  /// On a canonical report: how many OTHER reports confirm it. Maintained by a
  /// DB trigger; see [reporterCount] for the number to actually show a human.
  final int confirmCount;

  const AdminReport({
    required this.id,
    required this.shortId,
    required this.categoryKey,
    required this.category,
    required this.barangay,
    required this.address,
    required this.remarks,
    required this.status,
    required this.isAnonymous,
    required this.submitterName,
    required this.submitterPhotoUrl,
    required this.submitterRole,
    required this.mediaCount,
    required this.createdAt,
    this.dismissedAt,
    this.dismissedReason,
    this.endorsedToDepartment,
    this.endorsedAt,
    this.assignedToDepartment,
    this.assignedAt,
    this.assignedByName,
    this.rejectionNote,
    this.duplicateOf,
    this.confirmCount = 0,
  });

  bool get isDismissed => dismissedAt != null;

  /// This report confirms another — it belongs to that report's ticket, not its
  /// own row in the queue.
  bool get isDuplicate => duplicateOf != null;

  /// Citizens who reported this issue: the original reporter plus every
  /// confirmation. This is the number to show — "1 report" for an unconfirmed
  /// one reads correctly, where a bare confirmCount of 0 would not.
  int get reporterCount => confirmCount + 1;

  /// Independently reported by more than one citizen — corroborated, and worth
  /// surfacing next to AI urgency as a priority signal.
  bool get isCorroborated => confirmCount > 0;

  bool get isEndorsed =>
      endorsedToDepartment != null && endorsedToDepartment!.trim().isNotEmpty;

  bool get isAssigned =>
      assignedToDepartment != null && assignedToDepartment!.trim().isNotEmpty;

  /// Still on the admin's triage desk: not yet accepted, endorsed, or dismissed.
  bool get needsTriage =>
      status == ReportStatus.pending && !isEndorsed && !isAssigned;

  /// Accepted and actively being handled — the office has it but hasn't closed
  /// it. (Terminal states, and reports nobody owns yet, are not "working".)
  bool get isWorking =>
      status == ReportStatus.underReview || status == ReportStatus.inProgress;

  /// Working clock: when it was routed to an office (falls back to filing time).
  DateTime? get _clock => assignedAt ?? createdAt;

  /// Aging: a report awaiting triage >2 days, or being worked >7 days, is
  /// flagged so it surfaces instead of quietly rotting.
  bool get isOverdue {
    final now = DateTime.now();
    if (needsTriage) {
      return createdAt != null && now.difference(createdAt!).inDays >= 2;
    }
    if (status == ReportStatus.underReview ||
        status == ReportStatus.inProgress) {
      final c = _clock;
      return c != null && now.difference(c).inDays >= 7;
    }
    return false;
  }

  int get ageDays {
    final c = _clock;
    return c == null ? 0 : DateTime.now().difference(c).inDays;
  }
}

/// What the server hands back when a report is endorsed — everything needed to
/// print the letter and brief the receiving agency.
///
/// ⚠ [pin] is PLAINTEXT and EPHEMERAL. The database stores only a bcrypt hash,
/// so this object holds the only copy in existence. Show it to the admin, let
/// them note it down, and never persist it anywhere — not in a log, not in
/// shared preferences, and not in the PDF (which travels with the QR and would
/// defeat the point of having two factors).
class EndorsementCredentials {
  /// Unguessable per-report token; the QR encodes the scan URL built from it.
  final String token;

  /// 4-digit PIN the agency must key in to advance the report. Sent to them
  /// through a channel separate from the letter.
  final String pin;

  /// Human-facing reference printed on the letter, e.g. `END-1A2B3C4D`.
  final String reference;

  final String agency;

  const EndorsementCredentials({
    required this.token,
    required this.pin,
    required this.reference,
    required this.agency,
  });
}

/// A media item attached to a report, resolved to a public URL for the detail
/// dialog gallery.
class ReportMedia {
  final String url;
  final String? mimeType;

  /// 'camera' = live GPS-stamped capture; 'upload'/null = gallery photo or
  /// video whose location could not be verified.
  final String? source;

  /// AI-generated-image likelihood 0..1 (null until the check completes), and
  /// its lifecycle status ('pending' | 'completed' | 'failed' | null legacy).
  /// Populated by the check-ai-image Edge Function (ai_image_detection.sql).
  final double? aiScore;
  final String? aiStatus;
  const ReportMedia({
    required this.url,
    required this.mimeType,
    this.source,
    this.aiScore,
    this.aiStatus,
  });
  bool get isVideo => (mimeType ?? '').toLowerCase().startsWith('video/');

  /// True when the photo carries a baked-in, live GPS stamp.
  bool get isGpsVerified => source == 'camera';
}

/// One entry of a report's INTERNAL work log (`report_notes`) — the running
/// conversation between the admin and the office handling the report. Never
/// shown to the citizen; RLS enforces that, this is only how the console and
/// the printed dossier read it back.
class ReportNote {
  final String authorRole; // 'admin' | 'staff'
  final String authorName;
  final String body;
  final DateTime? createdAt;

  const ReportNote({
    required this.authorRole,
    required this.authorName,
    required this.body,
    required this.createdAt,
  });
}

/// An open report the DB thinks might be the same real-world issue as the one
/// the admin is looking at (`report_duplicate_candidates`). A SUGGESTION only —
/// nothing merges until an admin says so, because a wrong merge silently buries
/// a real report where a missed one just costs a little triage time.
class DuplicateCandidate {
  final String id;
  final String shortRef;
  final String remarks;
  final String? barangay;
  final ReportStatus status;
  final int confirmCount;
  final int distanceM;
  final DateTime? createdAt;

  const DuplicateCandidate({
    required this.id,
    required this.shortRef,
    required this.remarks,
    required this.barangay,
    required this.status,
    required this.confirmCount,
    required this.distanceM,
    required this.createdAt,
  });

  factory DuplicateCandidate.fromRow(Map<String, dynamic> r) =>
      DuplicateCandidate(
        id: r['id'] as String,
        shortRef: (r['short_ref'] as String?) ?? '',
        remarks: (r['remarks'] as String?) ?? '',
        barangay: r['barangay'] as String?,
        status: reportStatusFromDb(r['status'] as String?),
        confirmCount: (r['confirm_count'] as int?) ?? 0,
        distanceM: (r['distance_m'] as num?)?.round() ?? 0,
        createdAt: _parseTs(r['created_at']),
      );

  int get reporterCount => confirmCount + 1;

  String get distanceLabel => distanceM < 1000
      ? '$distanceM m away'
      : '${(distanceM / 1000).toStringAsFixed(1)} km away';
}

DateTime? _parseTs(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v.toLocal();
  if (v is String) return DateTime.tryParse(v)?.toLocal();
  return null;
}

// ── Filters ──────────────────────────────────────────────────────────────────

/// Mutually-exclusive views of the queue.
///
/// The list is bucketed by where a report sits in the PIPELINE rather than by
/// raw status, because that's the admin's actual job: clear the triage desk,
/// keep an eye on what the offices are working, and park what's left. Each
/// bucket answers one question, so they can never combine into a contradiction.
enum ReportBucket {
  /// Every real report, whoever is holding it — including the ones endorsed out
  /// to an external entity. Excludes only spam and merged duplicates.
  ///
  /// This used to exclude endorsed rows too, on the reasoning that "All" meant
  /// the LGU's own live queue. Two things broke because of it. An admin
  /// counting reports on the All tab was told a number that did not include
  /// work the municipality had endorsed but is still answerable for. And a
  /// progress-update notification deep-links to its report with the page on
  /// All — where an endorsed report was not present, so the highlight found no
  /// row and the tap did nothing at all, silently.
  all,

  /// Filed but not yet accepted, endorsed or rejected — the admin's to-do list.
  needsTriage,

  /// Accepted into an office and actively being handled.
  working,

  /// Completed.
  resolved,

  /// Handed to an external entity; out of the LGU queue.
  endorsed,

  /// Soft-hidden spam, kept out of the list and analytics.
  dismissed,
}

/// Whether [r] belongs in [bucket] — the single definition of the piles, kept
/// pure so the rules are testable without a database behind them.
///
/// [ReportBucket.all] is the whole ledger, so it deliberately OVERLAPS every
/// other pile; what it excludes is only what isn't a ticket — dismissed spam
/// and merged duplicates.
///
/// The narrower piles stay LGU-scoped and keep excluding endorsed rows, which
/// is not an inconsistency: `working` and `resolved` answer "what are OUR
/// offices holding", and an endorsed report has its own tab that answers the
/// same question for the agency. Only `all` promises everything, so only `all`
/// has to deliver it.
bool reportInBucket(AdminReport r, ReportBucket bucket) {
  // A merged duplicate is not a ticket — it's a confirmation on someone else's.
  // Held out of EVERY bucket (including dismissed) so collapsing duplicates
  // actually shortens the admin's queue, which is the whole point. It stays a
  // live row with its own reporter and notifications; it just isn't work.
  if (r.isDuplicate) return false;

  switch (bucket) {
    case ReportBucket.dismissed:
      return r.isDismissed;
    case ReportBucket.endorsed:
      return r.isEndorsed && !r.isDismissed;
    case ReportBucket.needsTriage:
      return r.needsTriage && !r.isDismissed;
    case ReportBucket.working:
      return !r.isDismissed && !r.isEndorsed && r.isWorking;
    case ReportBucket.resolved:
      return !r.isDismissed &&
          !r.isEndorsed &&
          r.status == ReportStatus.resolved;
    case ReportBucket.all:
      return !r.isDismissed;
  }
}

String reportBucketLabel(ReportBucket b) {
  switch (b) {
    case ReportBucket.all:
      return 'All';
    case ReportBucket.needsTriage:
      return 'Needs triage';
    case ReportBucket.working:
      return 'Working';
    case ReportBucket.resolved:
      return 'Resolved';
    case ReportBucket.endorsed:
      return 'Endorsed';
    case ReportBucket.dismissed:
      return 'Dismissed';
  }
}

enum ReportSort { newest, oldest }

class ReportFilters {
  /// Which slice of the queue is on screen. Exactly one at a time — the buckets
  /// are the primary navigation, surfaced as tabs.
  final ReportBucket bucket;

  /// Narrows the current bucket to a single status. Independent of [bucket]:
  /// it's the fine-grained cut (e.g. Rejected) the buckets don't have a tab for.
  final ReportStatus? status; // null = any
  final String query;
  final ReportSort sort;
  final bool anonymousOnly;

  const ReportFilters({
    this.bucket = ReportBucket.all,
    this.status,
    this.query = '',
    this.sort = ReportSort.newest,
    this.anonymousOnly = false,
  });

  ReportFilters copyWith({
    ReportBucket? bucket,
    ReportStatus? status,
    bool clearStatus = false,
    String? query,
    ReportSort? sort,
    bool? anonymousOnly,
  }) {
    return ReportFilters(
      bucket: bucket ?? this.bucket,
      status: clearStatus ? null : (status ?? this.status),
      query: query ?? this.query,
      sort: sort ?? this.sort,
      anonymousOnly: anonymousOnly ?? this.anonymousOnly,
    );
  }

  // Value equality so a caller can ask "did anything actually change?" without
  // comparing five fields by hand. copyWith always returns a NEW instance, so
  // identity comparison answers "yes" every time and would republish the state
  // on every deep-link tap whether or not a filter moved.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReportFilters &&
          other.bucket == bucket &&
          other.status == status &&
          other.query == query &&
          other.sort == sort &&
          other.anonymousOnly == anonymousOnly;

  @override
  int get hashCode => Object.hash(bucket, status, query, sort, anonymousOnly);
}

// ── Notifier ─────────────────────────────────────────────────────────────────

class AdminReportsNotifier extends AsyncNotifier<List<AdminReport>> {
  SupabaseClient get _db => Supabase.instance.client;
  static const String _bucket = 'report-media';

  /// Signed URLs, memoised per report.
  ///
  /// `report-media` is a private bucket, so every photo is served through a
  /// signed URL — and `createSignedUrl` mints a FRESH token per call, so the
  /// url string differs every time. Url is the cache key for both Flutter's
  /// ImageCache and the browser's HTTP cache, so re-signing on each open meant
  /// every image cache-missed and downloaded again, on web and on the app.
  /// Holding the urls makes them stable for the session, which is what lets
  /// anything downstream cache at all.
  final Map<String, ({DateTime at, List<ReportMedia> media})> _mediaCache = {};

  /// Comfortably inside the signed urls' one-hour expiry, so a cached url can
  /// never be handed out already dead.
  static const Duration _mediaCacheTtl = Duration(minutes: 45);
  static const int _signedUrlSeconds = 3600;

  /// Ceiling on [_mediaCache] entries.
  ///
  /// The TTL bounds how STALE an entry may be, but nothing bounded how MANY
  /// there were: an admin working through a long queue accumulated one entry
  /// per report opened and never released any of them for the life of the
  /// session — which on the web build is however long the tab stays open.
  /// 120 keeps a comfortable working set (far more than anyone scrolls back
  /// through) while making the growth finite.
  static const int _mediaCacheMaxEntries = 120;

  /// Full media list (with signed URLs) for a single report — used by the
  /// detail dialog's gallery. Cached; a report's media is immutable once filed
  /// (completion photos live in their own table), so there's nothing to miss.
  Future<List<ReportMedia>> fetchMedia(String reportId) async {
    final hit = _mediaCache[reportId];
    if (hit != null && DateTime.now().difference(hit.at) < _mediaCacheTtl) {
      return hit.media;
    }

    // `source` (media_source_column.sql) and `ai_score`/`ai_status`
    // (ai_image_detection.sql) are each optional migrations — try the fullest
    // column set first and fall back so media viewing never breaks if a
    // migration hasn't been applied yet.
    const attempts = [
      'storage_path, mime_type, display_order, source, ai_score, ai_status',
      'storage_path, mime_type, display_order, source',
      'storage_path, mime_type, display_order',
    ];
    List<Map<String, dynamic>>? rows;
    for (final cols in attempts) {
      try {
        rows = List<Map<String, dynamic>>.from(
          await _db
              .from('report_media')
              .select(cols)
              .eq('report_id', reportId)
              .order('display_order', ascending: true),
        );
        break;
      } catch (_) {
        // try the next (smaller) column set
      }
    }
    rows ??= const [];

    // `report-media` is a PRIVATE bucket, so a public URL 400s — sign each
    // object instead (mirrors how admin_verification_page views private media).
    //
    // Signed in ONE batch request rather than one per photo. This loop used to
    // await createSignedUrl separately for every image, so opening a report
    // with eight photos cost eight sequential storage round trips before
    // anything could render. createSignedUrlsResult signs the whole list in a
    // single call and reports per-path success or failure, so the existing
    // best-effort fallback survives intact.
    final mediaRows = List<Map<String, dynamic>>.from(rows);
    final paths = [for (final r in mediaRows) r['storage_path'] as String];

    // path -> signed url. Keyed by the path the server echoes back rather than
    // by position: results are matched explicitly so a reordered or partial
    // response can never pair a URL with the wrong photo.
    final signed = <String, String>{};
    if (paths.isNotEmpty) {
      try {
        for (final res in await _db.storage
            .from(_bucket)
            .createSignedUrlsResult(paths, _signedUrlSeconds)) {
          if (res is SignedUrlSuccess) signed[res.path] = res.signedUrl;
        }
      } catch (_) {
        // Whole-batch failure (network, endpoint unavailable). Fall back to the
        // original per-path signing so one bad request cannot cost every photo
        // its signature — the slow path, but only when the fast one is broken.
        for (final path in paths) {
          try {
            signed[path] = await _db.storage
                .from(_bucket)
                .createSignedUrl(path, _signedUrlSeconds);
          } catch (_) {
            // leave unsigned; the getPublicUrl fallback below picks it up
          }
        }
      }
    }

    final out = <ReportMedia>[];
    for (final r in mediaRows) {
      final path = r['storage_path'] as String;
      // best-effort: a public URL 400s on this private bucket, but it is a
      // better broken-image src than an empty string and matches prior behaviour
      final url =
          signed[path] ?? _db.storage.from(_bucket).getPublicUrl(path);
      out.add(
        ReportMedia(
          url: url,
          mimeType: r['mime_type'] as String?,
          source: r['source'] as String?,
          aiScore: (r['ai_score'] as num?)?.toDouble(),
          aiStatus: r['ai_status'] as String?,
        ),
      );
    }
    _mediaCache[reportId] = (at: DateTime.now(), media: out);
    _evictMediaCache();
    return out;
  }

  /// Hold [_mediaCache] at [_mediaCacheMaxEntries] by dropping the oldest
  /// entries first.
  ///
  /// Evicts by the recorded `at` rather than by Map insertion order: a cache
  /// HIT does not re-insert, so insertion order says when an entry was first
  /// fetched, not when it was last useful — and evicting on that would discard
  /// exactly the reports being looked at most. Expired entries go first, since
  /// they would be re-fetched on next access anyway.
  void _evictMediaCache() {
    if (_mediaCache.length <= _mediaCacheMaxEntries) return;

    final now = DateTime.now();
    _mediaCache.removeWhere((_, v) => now.difference(v.at) >= _mediaCacheTtl);
    if (_mediaCache.length <= _mediaCacheMaxEntries) return;

    final byAge = _mediaCache.entries.toList()
      ..sort((a, b) => a.value.at.compareTo(b.value.at));
    for (final e in byAge.take(_mediaCache.length - _mediaCacheMaxEntries)) {
      _mediaCache.remove(e.key);
    }
  }

  /// Full unfiltered set kept in memory so counts stay stable and filter/sort
  /// changes need no re-query (same approach as suggestions/feedback).
  List<AdminReport> _all = const [];

  ReportFilters _filters = const ReportFilters();
  ReportFilters get filters => _filters;

  /// Header stats count TICKETS, so merged confirmations are excluded — the same
  /// rule the buckets use. Otherwise collapsing five reports into one would
  /// shorten the list while the total above it stubbornly still said five.
  ///
  /// Dismissed spam is excluded for the same reason: the header sits directly
  /// above the bucket rail, so "4 reports" over an `All` pill reading 3 is a
  /// contradiction the admin cannot resolve — no tab they can press accounts
  /// for the missing row. The header describes the same ledger `all` does.
  Iterable<AdminReport> get _tickets =>
      _all.where((r) => !r.isDuplicate && !r.isDismissed);

  int get totalCount => _tickets.length;
  int get anonymousCount => _tickets.where((r) => r.isAnonymous).length;

  @override
  Future<List<AdminReport>> build() async {
    _all = await _fetchAll();
    return _view();
  }

  void setStatus(ReportStatus? status) {
    _filters = _filters.copyWith(status: status, clearStatus: status == null);
    _publish();
  }

  void setQuery(String query) {
    if (query == _filters.query) return;
    _filters = _filters.copyWith(query: query);
    _publish();
  }

  void setSort(ReportSort sort) {
    _filters = _filters.copyWith(sort: sort);
    _publish();
  }

  void toggleAnonymousOnly() {
    _filters = _filters.copyWith(anonymousOnly: !_filters.anonymousOnly);
    _publish();
  }

  void setBucket(ReportBucket bucket) {
    if (bucket == _filters.bucket) return;
    _filters = _filters.copyWith(bucket: bucket);
    _publish();
  }

  /// Makes [reportId] visible in the current view, moving the filters if it
  /// isn't. Returns false when the report isn't in the fetched set at all.
  ///
  /// Deep links arrive from OUTSIDE this page — a notification, an insight row
  /// — and land on whatever bucket and search the admin happened to leave
  /// behind. Nothing reconciled the two, so the page would scroll to a row that
  /// was filtered out and simply not flash, which reads as a broken tap rather
  /// than as an active filter. That is exactly how the "post update" ping
  /// looked dead: its report was endorsed, and the admin was sitting on a
  /// bucket that (before this change) excluded endorsed rows.
  ///
  /// Clearing the search and status is deliberate and not overreach. The admin
  /// asked to go and look at ONE row; a filter left over from a previous task
  /// is not a preference worth honouring over the thing they just tapped.
  bool revealReport(String reportId) {
    final target = _all.where((r) => r.id == reportId).firstOrNull;
    if (target == null) return false;

    var next = _filters;
    if (!reportInBucket(target, next.bucket)) {
      // First bucket in tab order that contains it. `all` is checked first and
      // now holds every non-dismissed report, so a dismissed or merged row is
      // the only case that falls through to its own specific pile.
      const order = [
        ReportBucket.all,
        ReportBucket.needsTriage,
        ReportBucket.working,
        ReportBucket.resolved,
        ReportBucket.endorsed,
        ReportBucket.dismissed,
      ];
      final found = order.where((b) => reportInBucket(target, b)).firstOrNull;
      // A merged duplicate is in NO bucket by design (it's a confirmation on
      // someone else's ticket, not a row of its own). Nothing to reveal.
      if (found == null) return false;
      next = next.copyWith(bucket: found);
    }

    if (next.query.isNotEmpty) next = next.copyWith(query: '');
    if (next.status != null && next.status != target.status) {
      next = next.copyWith(clearStatus: true);
    }
    if (next.anonymousOnly && !target.isAnonymous) {
      next = next.copyWith(anonymousOnly: false);
    }

    if (next != _filters) {
      _filters = next;
      _publish();
    }
    return true;
  }

  /// Rows in [bucket], ignoring search / status / anonymous — the tab counts
  /// must describe the bucket itself, not what's left after the other filters.
  Iterable<AdminReport> _inBucket(ReportBucket bucket) =>
      _all.where((r) => reportInBucket(r, bucket));

  int bucketCount(ReportBucket bucket) => _inBucket(bucket).length;

  /// The reports linked to [canonicalId] as confirmations of the same issue.
  ///
  /// Read straight out of the already-fetched set rather than re-queried —
  /// duplicates are held out of the BUCKETS, not out of [_all], precisely so
  /// they stay reachable here. This is the only way into a merged report, since
  /// by design it has no row of its own in any queue.
  List<AdminReport> confirmationsOf(String canonicalId) =>
      _all.where((r) => r.duplicateOf == canonicalId).toList()
        ..sort((a, b) {
          final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
          final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
          return at.compareTo(bt);
        });

  /// Active reports (not spam, not endorsed out) that have aged past their SLA.
  /// [_tickets] already drops dismissed spam, so only the endorsed cut is left.
  int get overdueCount =>
      _tickets.where((r) => !r.isEndorsed && r.isOverdue).length;

  void _publish() => state = AsyncValue.data(_view());

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      _all = await _fetchAll();
      return _view();
    });
  }

  Future<void> _reload() async {
    final next = await AsyncValue.guard(_fetchAll);
    if (next.hasValue) {
      _all = next.value!;
      _publish();
    }
  }

  /// Silent background refetch (no loading flash, keeps current filters) for the
  /// admin shell's auto-refresh. `_reload` already preserves the view, so this
  /// is just its public alias.
  Future<void> silentRefresh() => _reload();

  // NOTE: there is deliberately no raw setStatus here. A report's status is
  // only ever moved by triage (accept / reject / reopen) or by the office that
  // owns it — so the detail's stepper can never show a stage that nothing in
  // the record accounts for.

  /// Endorses an out-of-LGU-scope report to an external entity (e.g. DPWH),
  /// with the admin's written [reason].
  ///
  /// Goes through the `endorse_report_to_agency` RPC rather than an UPDATE
  /// because the write is not just a column change: the server mints a signed
  /// token and a 4-digit PIN, stores only a bcrypt hash of the PIN, records the
  /// transition, and mirrors the routing columns onto the report — all in one
  /// transaction. It also re-checks admin rights and the reason, so neither
  /// depends on this client behaving.
  ///
  /// Returns the credentials for the endorsement letter. **The plaintext PIN in
  /// the result is the only copy that will ever exist** — the server keeps only
  /// its hash, so if it is not shown to the admin now it is unrecoverable and
  /// the report must be re-endorsed.
  ///
  /// Re-endorsing a report that is already endorsed mints a FRESH token and
  /// PIN, which invalidates any letter already printed.
  Future<EndorsementCredentials> endorse(
    String id,
    String department,
    String reason,
  ) async {
    final res = await _db.rpc(
      'endorse_report_to_agency',
      params: {
        'p_report': id,
        'p_agency': department,
        'p_reason': reason,
      },
    );
    final row = Map<String, dynamic>.from(res as Map);
    await _reload();
    return EndorsementCredentials(
      token: row['token'] as String,
      pin: row['pin'] as String,
      reference: row['reference'] as String,
      agency: (row['agency'] as String?) ?? department,
    );
  }

  /// Withdraws an endorsement — the report comes back into the LGU's queue and
  /// the printed letter stops working.
  ///
  /// Goes through the `clear_report_endorsement` RPC rather than an UPDATE
  /// because withdrawing is two writes that must not half-succeed: the routing
  /// columns are cleared AND the endorsement's token + PIN are revoked. Before
  /// migration 20260829000000 only the first half happened, so a withdrawn
  /// letter's QR still resolved and could still drive the citizen's report to
  /// "Resolved" — the zombie-QR defect.
  ///
  /// The `report_endorsements` row itself survives, moved to state 'withdrawn',
  /// so the handoff history stays reconstructable. Re-endorsing later mints a
  /// fresh token and PIN.
  /// [reason] is recorded on the endorsement's event log beside the admin who
  /// withdrew it (migration 20260829000002). Endorsing has always demanded a
  /// written justification; taking one back is the same decision in reverse and
  /// was leaving no trace of who or why.
  Future<void> clearEndorsement(String id, {String? reason}) async {
    await _db.rpc('clear_report_endorsement', params: {
      'p_report': id,
      'p_reason': reason,
    });
    await _reload();
  }

  /// Admin ACCEPTS a pending report INTO an internal LGU office. Sets the owning
  /// department (auto-derived from the category, but the admin may override),
  /// clears any external endorsement, and releases it to that office by moving
  /// the status to Under review. The report is now visible to that dept's staff.
  Future<void> accept(String id, String department) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final update = <String, dynamic>{
      'assigned_to_department': department,
      'assigned_at': now,
      'assigned_by': _db.auth.currentUser?.id,
      // Accepting internally cancels any external endorsement.
      'endorsed_to_department': null,
      'endorsed_at': null,
      'endorsed_by': null,
      'status': reportStatusToDb(ReportStatus.underReview),
    };
    await _tryUpdate(
      id,
      update,
      ['assigned_to_department', 'assigned_at', 'assigned_by'],
    );
  }

  /// Admin REJECTS a report with a citizen-facing reason. Terminal — a DB
  /// trigger notifies the reporter. If the report was already being worked by
  /// an office (assigned/endorsed), also drops an admin work-log note so that
  /// office is pinged the work was closed. Requires a note.
  Future<void> reject(String id, String note) async {
    final matches = _all.where((r) => r.id == id);
    final before = matches.isEmpty ? null : matches.first;

    final update = <String, dynamic>{
      'status': reportStatusToDb(ReportStatus.rejected),
      'rejection_note': note.trim(),
    };
    await _tryUpdate(id, update, ['rejection_note']);

    if (before != null && (before.isAssigned || before.isEndorsed)) {
      try {
        await _db.from('report_notes').insert({
          'report_id': id,
          'author_id': _db.auth.currentUser?.id,
          'author_role': 'admin',
          'author_name': 'LGU Admin',
          'body': 'Report closed by admin — ${note.trim()}',
        });
      } catch (_) {
        // Non-fatal — the rejection already landed; the note is a courtesy ping.
      }
    }
  }

  /// Reopens a rejected report — returns it to the admin's triage desk
  /// (pending) and clears the rejection reason. The citizen is notified it was
  /// reopened (status-change trigger).
  Future<void> reopen(String id) async {
    // Return cleanly to the triage desk: pending AND unowned, so it lands back
    // in Needs-triage. (A report rejected while an office was working it keeps
    // its assignment — clearing it here avoids a pending-but-assigned limbo.)
    final update = <String, dynamic>{
      'status': reportStatusToDb(ReportStatus.pending),
      'rejection_note': null,
      'assigned_to_department': null,
      'assigned_at': null,
      'endorsed_to_department': null,
      'endorsed_at': null,
    };
    await _tryUpdate(id, update, [
      'rejection_note',
      'assigned_to_department',
      'assigned_at',
    ]);
  }

  /// The report as it stands in the store, whatever the current filters happen
  /// to show. The detail dialog stays open across actions that move a report
  /// out of the visible bucket — reject, reopen, dismiss, restore — so it can't
  /// read itself back out of the filtered [state].
  AdminReport? byId(String id) {
    for (final r in _all) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// Writes a triage update, degrading ONLY for a missing column.
  ///
  /// ── ⚠ WHY THE BARE `catch (_)` HAD TO GO ──────────────────────────────────
  /// This retried on ANY failure. The intent was narrow — report_triage_gate
  /// might not be applied, so drop its columns and let the status change land —
  /// but the effect was that an RLS denial, a constraint violation or a dropped
  /// connection also fell into the retry. The narrower payload then often
  /// SUCCEEDED, so `accept()` reported "Accepted — routed to Engineering
  /// Office" while `assigned_to_department` was never written: the report sat
  /// unassigned, the office was never notified, and nothing anywhere said so.
  ///
  /// That migration is applied (it lives in supabase/legacy/, and all six
  /// columns are confirmed present live), so the fallback is dead code for its
  /// stated purpose and was only ever hiding real errors. It is kept — a
  /// deployment restored from an older schema is exactly when you want it — but
  /// it now fires ONLY on PostgREST's undefined-column code, and any other
  /// failure propagates to the caller, which already has the error UI for it.
  Future<void> _tryUpdate(
    String id,
    Map<String, dynamic> update,
    List<String> optionalCols,
  ) async {
    try {
      await _db.from('reports').update(update).eq('id', id);
    } on PostgrestException catch (e) {
      // 42703 = undefined_column. PostgREST also answers PGRST204 when a column
      // named in the payload is absent from its schema cache; both mean "this
      // column does not exist", and nothing else does.
      final missingColumn = e.code == '42703' || e.code == 'PGRST204';
      if (!missingColumn) rethrow;

      final fallback = Map<String, dynamic>.from(update)
        ..removeWhere((k, _) => optionalCols.contains(k));
      // Nothing left to write means the missing column was not an optional one,
      // so the retry would fail identically. Surface the original error rather
      // than reporting a success that never happened.
      if (fallback.isEmpty) rethrow;
      await _db.from('reports').update(fallback).eq('id', id);
    }
    await _reload();
  }

  /// Soft-dismiss a spam / nonsense report: hides it from the list and excludes
  /// it from analytics. Reversible via [restore]. Audited with the current admin.
  Future<void> dismiss(String id, String reason) async {
    await _db
        .from('reports')
        .update({
          'dismissed_at': DateTime.now().toUtc().toIso8601String(),
          'dismissed_by': _db.auth.currentUser?.id,
          'dismissed_reason': reason,
        })
        .eq('id', id);
    await _reload();
  }

  /// A report's internal work log, oldest first — what the office and the admin
  /// said to each other while handling it.
  ///
  /// Returns empty rather than throwing when `report_notes` doesn't exist: the
  /// table ships in an optional migration, and a console (or a printed dossier)
  /// must not break because it hasn't been applied. Same rule [fetchMedia]
  /// follows for its optional columns.
  Future<List<ReportNote>> fetchNotes(String reportId) async {
    try {
      final rows = List<Map<String, dynamic>>.from(
        await _db
            .from('report_notes')
            .select('author_role, author_name, body, created_at')
            .eq('report_id', reportId)
            .order('created_at', ascending: true),
      );
      return [
        for (final r in rows)
          ReportNote(
            authorRole: (r['author_role'] as String?) ?? 'staff',
            authorName: (r['author_name'] as String?) ?? 'Staff',
            body: (r['body'] as String?) ?? '',
            createdAt: DateTime.tryParse(r['created_at'].toString())?.toLocal(),
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Open reports that might be the same real-world issue as [reportId].
  /// Empty when report_duplicates.sql hasn't been applied — the suggestion is
  /// an aid, so its absence must never break the detail view.
  Future<List<DuplicateCandidate>> fetchDuplicateCandidates(
    String reportId,
  ) async {
    try {
      final rows = await _db.rpc(
        'report_duplicate_candidates',
        params: {'p_report_id': reportId},
      );
      return List<Map<String, dynamic>>.from(rows as List)
          .map(DuplicateCandidate.fromRow)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Links [id] to [canonicalId] as a confirmation of the same issue.
  ///
  /// Never deletes or rejects: [id] stays a real report with its own reporter,
  /// who is notified it was linked and keeps receiving status updates from the
  /// canonical ticket's progress. A DB trigger bumps the canonical's
  /// confirm_count. Reversible via [unmerge].
  Future<void> merge(String id, String canonicalId) async {
    await _db
        .from('reports')
        .update({
          'duplicate_of': canonicalId,
          // A confirmation isn't work. Release it from whatever office holds it
          // so it stops sitting in a staff inbox — the canonical report carries
          // the actual job now.
          'assigned_to_department': null,
          'assigned_at': null,
          'endorsed_to_department': null,
          'endorsed_at': null,
        })
        .eq('id', id);
    await _reload();
  }

  /// Undo a merge — the report becomes its own ticket again and returns to the
  /// queue. It comes back UNOWNED (merging released its office), so it lands on
  /// the triage desk to be routed afresh rather than silently re-entering an
  /// inbox nobody is expecting it in.
  Future<void> unmerge(String id) async {
    await _db.from('reports').update({'duplicate_of': null}).eq('id', id);
    await _reload();
  }

  /// Undo a dismissal — the report returns to the active list and analytics.
  Future<void> restore(String id) async {
    await _db
        .from('reports')
        .update({
          'dismissed_at': null,
          'dismissed_by': null,
          'dismissed_reason': null,
        })
        .eq('id', id);
    await _reload();
  }

  List<AdminReport> _view() {
    // The bucket picks the slice; search / status / anonymous then narrow it.
    Iterable<AdminReport> list = _inBucket(_filters.bucket);

    if (_filters.anonymousOnly) list = list.where((r) => r.isAnonymous);

    final status = _filters.status;
    if (status != null) list = list.where((r) => r.status == status);

    final q = _filters.query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((r) {
        return (r.barangay ?? '').toLowerCase().contains(q) ||
            (r.address ?? '').toLowerCase().contains(q) ||
            r.remarks.toLowerCase().contains(q) ||
            r.category.toLowerCase().contains(q);
      });
    }

    final out = list.toList();
    out.sort((a, b) {
      final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
      final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
      return _filters.sort == ReportSort.oldest
          ? at.compareTo(bt)
          : bt.compareTo(at);
    });
    return out;
  }

  Future<List<AdminReport>> _fetchAll() async {
    // NOTE: user_id is deliberately NOT selected here. Anonymous rows must never
    // carry their submitter's id in this response payload; named rows get their
    // user_id via a separate query below. The only path to an anonymous
    // identity is the guarded admin_reveal_submitter RPC (anonymous_reveal.sql).
    const core =
        'id, category, category_other, barangay, address, remarks, '
        'status, is_anonymous, created_at, report_media(id)';
    const endorse = 'endorsed_to_department, endorsed_at';
    const triage =
        'assigned_to_department, assigned_at, assigned_by, rejection_note';
    const moderation = 'dismissed_at, dismissed_reason';
    const dedupe = 'duplicate_of, confirm_count';
    // Optional columns come from separate migrations (spam_moderation,
    // staff_portal, report_triage_gate, report_duplicates). Try the fullest set
    // first and degrade one migration at a time so the list never breaks if one
    // hasn't been run.
    final attempts = [
      '$core, $endorse, $triage, $moderation, $dedupe',
      '$core, $endorse, $triage, $moderation',
      '$core, $endorse, $triage',
      '$core, $endorse, $moderation',
      '$core, $endorse',
      core,
    ];
    List<Map<String, dynamic>>? rows;
    for (final cols in attempts) {
      try {
        rows = List<Map<String, dynamic>>.from(
          await _db
              .from('reports')
              .select(cols)
              .order('created_at', ascending: false)
              .limit(200), // barangay scale; range-based paging is the scale path.
        );
        break;
      } catch (_) {
        // try the next (smaller) column set
      }
    }
    rows ??= const [];

    final list = rows;
    if (list.isEmpty) return const [];

    // Resolve user_ids for NAMED rows only, in a separate query. An anonymous
    // reporter's user_id is never requested, so it never leaves the database to
    // this client — closing the payload gap where an admin could read it off
    // the wire despite the UI hiding it.
    final namedIds = [
      for (final r in list)
        if ((r['is_anonymous'] as bool?) != true) r['id'] as String,
    ];
    final idToUid = await _fetchNamedUserIds(namedIds);
    final identifiedIds = idToUid.values.toSet().toList();

    // The admins who accepted reports at triage. Resolved alongside submitters
    // in one profile query — they're plain user_ids like any other, and are
    // unrelated to the anonymity rules above (an acceptor is never the
    // reporter's identity).
    final acceptorIds = {
      for (final r in list)
        if (r['assigned_by'] is String) r['assigned_by'] as String,
    };

    final profiles = await _fetchProfiles(
      {...identifiedIds, ...acceptorIds}.toList(),
    );
    final roles = await _fetchRoles(identifiedIds);

    return list.map((r) {
      final id = r['id'] as String;
      final key = r['category'] as String? ?? 'others';
      final media = r['report_media'];
      final isAnon = (r['is_anonymous'] as bool?) ?? false;
      final uid = idToUid[id]; // present for named rows only
      final profile = (!isAnon && uid != null) ? profiles[uid] : null;
      final role = (!isAnon && uid != null) ? roles[uid] : null;

      return AdminReport(
        id: id,
        shortId: id.length >= 8
            ? id.substring(0, 8).toUpperCase()
            : id.toUpperCase(),
        categoryKey: key,
        category: reportCategoryLabel(key, r['category_other'] as String?),
        barangay: r['barangay'] as String?,
        address: r['address'] as String?,
        remarks: (r['remarks'] as String?) ?? '',
        status: reportStatusFromDb(r['status'] as String?),
        isAnonymous: isAnon,
        submitterName: profile?['name'] as String?,
        submitterPhotoUrl: profile?['photoUrl'] as String?,
        submitterRole: role,
        mediaCount: media is List ? media.length : 0,
        createdAt: _parseTs(r['created_at']),
        dismissedAt: _parseTs(r['dismissed_at']),
        dismissedReason: r['dismissed_reason'] as String?,
        endorsedToDepartment: _nullIfBlank(r['endorsed_to_department']),
        endorsedAt: _parseTs(r['endorsed_at']),
        assignedToDepartment: _nullIfBlank(r['assigned_to_department']),
        assignedAt: _parseTs(r['assigned_at']),
        assignedByName: profiles[r['assigned_by']]?['name'] as String?,
        rejectionNote: _nullIfBlank(r['rejection_note']),
        duplicateOf: _nullIfBlank(r['duplicate_of']),
        confirmCount: (r['confirm_count'] as int?) ?? 0,
      );
    }).toList();
  }

  /// Maps report id → submitter user_id, for NAMED reports only. Kept in its own
  /// query so an anonymous report's user_id is never selected/transmitted.
  Future<Map<String, String>> _fetchNamedUserIds(List<String> reportIds) async {
    if (reportIds.isEmpty) return const {};
    final rows = await _db
        .from('reports')
        .select('id, user_id')
        .inFilter('id', reportIds);
    final map = <String, String>{};
    for (final r in List<Map<String, dynamic>>.from(rows)) {
      final uid = r['user_id'] as String?;
      if (uid != null) map[r['id'] as String] = uid;
    }
    return map;
  }

  Future<Map<String, Map<String, dynamic>>> _fetchProfiles(
    List<String> userIds,
  ) async {
    if (userIds.isEmpty) return const {};
    final rows = await _db
        .from('public_user_profiles')
        .select('user_id, first_name, last_name, profile_photo_path')
        .inFilter('user_id', userIds);

    final map = <String, Map<String, dynamic>>{};
    for (final r in List<Map<String, dynamic>>.from(rows)) {
      final first = (r['first_name'] as String? ?? '').trim();
      final last = (r['last_name'] as String? ?? '').trim();
      final name = '$first $last'.trim();
      final photoPath = r['profile_photo_path'] as String?;
      String? photoUrl;
      if (photoPath != null && photoPath.isNotEmpty) {
        photoUrl = _db.storage.from('profile-photos').getPublicUrl(photoPath);
      }
      map[r['user_id'] as String] = {
        'name': name.isEmpty ? null : name,
        'photoUrl': photoUrl,
      };
    }
    return map;
  }

  Future<Map<String, String>> _fetchRoles(List<String> userIds) async {
    if (userIds.isEmpty) return const {};
    final rows = await _db
        .from('user_roles')
        .select('user_id, role_id')
        .inFilter('user_id', userIds);

    final map = <String, String>{};
    for (final r in List<Map<String, dynamic>>.from(rows)) {
      final rid = r['role_id'] as int?;
      map[r['user_id'] as String] = switch (rid) {
        1 => 'admin',
        2 => 'staff',
        _ => 'citizen',
      };
    }
    return map;
  }

  static String? _nullIfBlank(dynamic v) {
    if (v is! String) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }
}

final adminReportsProvider =
    AsyncNotifierProvider<AdminReportsNotifier, List<AdminReport>>(
      AdminReportsNotifier.new,
    );
