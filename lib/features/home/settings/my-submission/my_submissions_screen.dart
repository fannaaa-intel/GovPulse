import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import '../../../../core/widgets/responsive_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/router/legacy_nav.dart';
import '../../../../core/widgets/deeplink_highlight.dart';
import '../../../../core/widgets/loading/loading_overlay.dart';
import '../../my_report/my_reports_screen.dart' show ReportItem;
import '../../../../core/widgets/app_dialog.dart';
import '../../../../core/theme/citizen_ui.dart';
import '../../../../core/widgets/Home/Account/account_web_kit.dart';
import '../../../../core/theme/mobile_metrics.dart';
// ── Private config classes ────────────────────────────────────────────────────

class _CatCfg {
  final String asset;
  final Color color;
  final String label;
  const _CatCfg(this.asset, this.color, this.label);
}

class _OfficeCfg {
  final IconData icon;
  final Color color;
  final String label;
  const _OfficeCfg(this.icon, this.color, this.label);
}

// ── Private data models ───────────────────────────────────────────────────────

class _Report {
  final String id;
  final String category;
  final String? categoryOther;
  final String? barangay;
  final String? remarks;
  final String status;
  final DateTime createdAt;
  final int mediaCount;
  final bool isAnonymous;

  const _Report({
    required this.id,
    required this.category,
    this.categoryOther,
    this.barangay,
    this.remarks,
    required this.status,
    required this.createdAt,
    required this.mediaCount,
    this.isAnonymous = false,
  });

  factory _Report.fromJson(Map<String, dynamic> j) => _Report(
    id: j['id'] as String,
    category: j['category'] as String,
    categoryOther: j['category_other'] as String?,
    barangay: j['barangay'] as String?,
    remarks: j['remarks'] as String?,
    status: (j['status'] as String?) ?? 'pending',
    createdAt: DateTime.parse(j['created_at'] as String),
    mediaCount: (j['report_media'] as List<dynamic>?)?.length ?? 0,
    isAnonymous: (j['is_anonymous'] as bool?) ?? false,
  );
}

class _Suggestion {
  final String id;
  final String category;
  final String? categoryOther;
  final String? details;
  final String? barangay;
  final String? address;
  final double? latitude;
  final double? longitude;
  final DateTime createdAt;
  final bool isAnonymous;
  final String? adminResponse;
  final DateTime? reviewedAt;
  final DateTime? dismissedAt;

  /// Responding admin's avatar, denormalised at reply time (citizens can't read
  /// admin_profiles). Null → the response block falls back to the LGU icon.
  final String? responderPhotoUrl;

  const _Suggestion({
    required this.id,
    required this.category,
    this.categoryOther,
    this.details,
    this.barangay,
    this.address,
    this.latitude,
    this.longitude,
    required this.createdAt,
    this.isAnonymous = false,
    this.adminResponse,
    this.reviewedAt,
    this.dismissedAt,
    this.responderPhotoUrl,
  });

  /// The LGU has replied (used to show the "Replied" pill + response block).
  bool get hasReply =>
      adminResponse != null && adminResponse!.trim().isNotEmpty;

  /// Admin closed this (spam moderation). Surfaced to the citizen as a neutral
  /// "Closed" — never the internal spam reason — so it doesn't read as forever
  /// awaiting a reply.
  bool get isClosed => dismissedAt != null && !hasReply;

  factory _Suggestion.fromJson(Map<String, dynamic> j) => _Suggestion(
    id: j['id'] as String,
    category: j['category'] as String,
    categoryOther: j['category_other'] as String?,
    details: j['details'] as String?,
    barangay: j['barangay'] as String?,
    address: j['address'] as String?,
    latitude: (j['latitude'] as num?)?.toDouble(),
    longitude: (j['longitude'] as num?)?.toDouble(),
    createdAt: DateTime.parse(j['created_at'] as String),
    isAnonymous: (j['is_anonymous'] as bool?) ?? false,
    adminResponse: j['admin_response'] as String?,
    reviewedAt: j['reviewed_at'] == null
        ? null
        : DateTime.tryParse(j['reviewed_at'] as String),
    dismissedAt: j['dismissed_at'] == null
        ? null
        : DateTime.tryParse(j['dismissed_at'] as String),
    responderPhotoUrl: j['responder_photo_url'] as String?,
  );
}

class _Feedback {
  final String id;
  final String officeId;
  final String officeLabel;
  final String serviceName;
  final int rating;
  final DateTime visitDate;

  /// When the feedback was actually submitted (drives the timeline's first
  /// event). Distinct from [visitDate], which is when they visited the office.
  final DateTime? createdAt;
  final String? comment;
  final bool isAnonymous;
  final String? adminResponse;
  final DateTime? reviewedAt;
  final int? aspectStaff;
  final int? aspectWait;
  final int? aspectClarity;
  final int? aspectFacility;
  final List<String> photoUrls;
  final DateTime? dismissedAt;

  /// Responding admin's avatar, denormalised at reply time (citizens can't read
  /// admin_profiles). Null → the response block falls back to the LGU icon.
  final String? responderPhotoUrl;

  const _Feedback({
    required this.id,
    required this.officeId,
    required this.officeLabel,
    required this.serviceName,
    required this.rating,
    required this.visitDate,
    this.createdAt,
    this.comment,
    this.isAnonymous = false,
    this.adminResponse,
    this.reviewedAt,
    this.aspectStaff,
    this.aspectWait,
    this.aspectClarity,
    this.aspectFacility,
    this.photoUrls = const [],
    this.dismissedAt,
    this.responderPhotoUrl,
  });

  /// The LGU has replied (used to show the "Replied" pill + response block).
  bool get hasReply =>
      adminResponse != null && adminResponse!.trim().isNotEmpty;

  /// Admin closed this (spam moderation) — shown to the citizen as a neutral
  /// "Closed", never the internal spam reason.
  bool get isClosed => dismissedAt != null && !hasReply;

  factory _Feedback.fromJson(Map<String, dynamic> j) => _Feedback(
    id: j['id'] as String,
    officeId: j['office_id'] as String,
    officeLabel: j['office_label'] as String,
    serviceName: j['service_name'] as String,
    rating: j['overall_rating'] as int,
    visitDate: DateTime.parse(j['visit_date'] as String),
    createdAt: j['created_at'] == null
        ? null
        : DateTime.tryParse(j['created_at'] as String)?.toLocal(),
    comment: j['comment'] as String?,
    isAnonymous: (j['is_anonymous'] as bool?) ?? false,
    adminResponse: j['admin_response'] as String?,
    reviewedAt: j['reviewed_at'] == null
        ? null
        : DateTime.tryParse(j['reviewed_at'] as String),
    aspectStaff: j['aspect_staff'] as int?,
    aspectWait: j['aspect_wait'] as int?,
    aspectClarity: j['aspect_clarity'] as int?,
    aspectFacility: j['aspect_facility'] as int?,
    photoUrls:
        (j['photo_urls'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        const [],
    dismissedAt: j['dismissed_at'] == null
        ? null
        : DateTime.tryParse(j['dismissed_at'] as String),
    responderPhotoUrl: j['responder_photo_url'] as String?,
  );
}

// ─────────────────────────────────────────────────────────────────────────────

/// Route arguments for `/my_submissions`. A plain `String` username is still
/// accepted for the common case (Settings entry); this richer form lets a reply
/// notification deep-link straight to the relevant tab and item.
class MySubmissionsArgs {
  final String username;

  /// 0 = Reports, 1 = Suggestions, 2 = Feedback.
  final int initialTab;

  /// Id of the suggestion/feedback to scroll to and briefly highlight.
  final String? highlightId;

  const MySubmissionsArgs({
    required this.username,
    this.initialTab = 0,
    this.highlightId,
  });
}

class MySubmissionsScreen extends StatefulWidget {
  /// True while an instance is mounted. A reply-notification deep-link checks
  /// this and skips navigating when the screen is already open, so it never
  /// stacks a duplicate on top of itself.
  static bool isOpen = false;

  final String username;

  /// Tab to open on first build (0 Reports · 1 Suggestions · 2 Feedback).
  final int initialTab;

  /// A suggestion/feedback id to scroll to and flash once, when arriving from a
  /// reply notification. Null for a normal open.
  final String? highlightId;

  const MySubmissionsScreen({
    super.key,
    required this.username,
    this.initialTab = 0,
    this.highlightId,
  });

  @override
  State<MySubmissionsScreen> createState() => _MySubmissionsScreenState();
}

class _MySubmissionsScreenState extends State<MySubmissionsScreen>
    with TickerProviderStateMixin, DeepLinkHighlightMixin {
  // ── Animation ──────────────────────────────────────────────────────────────
  late final AnimationController _slideCtrl;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;
  late final AnimationController _shimmerCtrl;

  // ── Tab & filter state ─────────────────────────────────────────────────────
  int _tab = 0; // 0 = Reports, 1 = Suggestions, 2 = Feedback
  String _filter = 'all'; // Reports: all | pending | in_progress | resolved
  // Suggestions & Feedback share a lighter filter: all | replied | awaiting.
  String _replyFilter = 'all';

  // ── Data ───────────────────────────────────────────────────────────────────
  List<_Report> _reports = [];
  List<_Suggestion> _suggestions = [];
  List<_Feedback> _feedbacks = [];

  // Full ReportItem per report id — lets a report card open the existing rich
  // ReportDetailScreen (timeline, chat, resolution media) for tab parity.
  final Map<String, ReportItem> _reportItemById = {};

  // ── Realtime ────────────────────────────────────────────────────────────────
  // A single channel watches this user's own reports/suggestions/feedback rows;
  // any change (e.g. an LGU reply landing) triggers a silent refresh so the list
  // + unseen dot update live without a manual pull. Requires realtime to be
  // enabled for these tables in Supabase; if not, pull-to-refresh still works.
  RealtimeChannel? _rtChannel;
  Timer? _rtDebounce;
  bool _rtSubscribed = false;

  // ── Fetch state ────────────────────────────────────────────────────────────
  bool _loading = true;
  bool _hasError = false;

  // ── Deep-link highlight (from a reply notification) ─────────────────────────
  // Scroll-into-view + one-time flash live in DeepLinkHighlightMixin, shared
  // with the admin lists so every deep-link lands the same way. The id to flash
  // arrives as widget.highlightId and is applied once the fetch resolves.

  // ── Unseen-reply indicators (per-tab dot) ───────────────────────────────────
  // Client-side only: we compare each list's newest reply timestamp against the
  // last time the user viewed that tab (persisted in SharedPreferences), and
  // show a dot until they open the tab. No DB column / migration needed.
  bool _unseenSuggestion = false;
  bool _unseenFeedback = false;
  DateTime? _latestSuggestionReplyAt;
  DateTime? _latestFeedbackReplyAt;

  // ── Report categories — matches report_issue_screen.dart assets. Labels are
  // single-line: they render as the card TITLE now (not a caption squeezed
  // under the icon), and they flow into the detail hero unbroken.
  static const Map<String, _CatCfg> _reportCats = {
    'road': _CatCfg(
      'assets/images/report/roadtwo.webp',
      Color(0xFF3B82F6),
      'Road & Infrastructure',
    ),
    'waste': _CatCfg(
      'assets/images/report/bin.webp',
      Color(0xFFEF4444),
      'Waste & Garbage',
    ),
    'drainage': _CatCfg(
      'assets/images/report/road.webp',
      Color(0xFF06B6D4),
      'Drainage & Flooding',
    ),
    'streetlight': _CatCfg(
      'assets/images/report/lamppost.webp',
      Color(0xFFF59E0B),
      'Streetlight Outage',
    ),
    'environment': _CatCfg(
      'assets/images/report/leaf.webp',
      Color(0xFF10B981),
      'Environment & Pollution',
    ),
    'others': _CatCfg(
      'assets/images/report/menu.webp',
      Color(0xFF6B7280),
      'Others',
    ),
  };

  // ── Suggestion categories — matches suggestion_screen.dart assets ───────────
  static const Map<String, _CatCfg> _suggestionCats = {
    'public_service': _CatCfg(
      'assets/images/suggestion/courthouse.webp',
      Color(0xFF1D4ED8),
      'Public Service',
    ),
    'community_program': _CatCfg(
      'assets/images/suggestion/group.webp',
      Color(0xFF8B5CF6),
      'Community Program',
    ),
    'health_safety': _CatCfg(
      'assets/images/suggestion/health.webp',
      Color(0xFFEF4444),
      'Health & Safety',
    ),
    'infrastructure': _CatCfg(
      'assets/images/suggestion/building.webp',
      Color(0xFFF59E0B),
      'Infrastructure',
    ),
    'environment': _CatCfg(
      'assets/images/suggestion/trees.webp',
      Color(0xFF10B981),
      'Environment',
    ),
    'others': _CatCfg(
      'assets/images/report/menu.webp',
      Color(0xFF6B7280),
      'Others',
    ),
  };

  // ── Feedback offices — matches feedback_screen.dart icon config ─────────────
  static const Map<String, _OfficeCfg> _officeCfg = {
    'health': _OfficeCfg(
      Icons.local_hospital_rounded,
      Color(0xFFEF4444),
      'Health Office',
    ),
    'mayor': _OfficeCfg(
      Icons.account_balance_rounded,
      Color(0xFF1D4ED8),
      "Mayor's Office",
    ),
    'mpdo': _OfficeCfg(Icons.map_rounded, Color(0xFF10B981), 'Planning & Dev'),
    'civil': _OfficeCfg(
      Icons.assignment_rounded,
      Color(0xFFF59E0B),
      'Civil Registrar',
    ),
    'cert': _OfficeCfg(
      Icons.task_alt_rounded,
      Color(0xFF8B5CF6),
      'Certificate Verif.',
    ),
  };

  // ── Status badge config ────────────────────────────────────────────────────
  static ({Color bg, Color border, Color dot, Color text, String label})
  _statusCfg(String s) {
    switch (s) {
      case 'in_progress':
        return (
          bg: const Color(0xFFEFF6FF),
          border: const Color(0xFF3B82F6),
          dot: const Color(0xFF3B82F6),
          text: const Color(0xFF1D4ED8),
          label: 'In Progress',
        );
      case 'resolved':
        return (
          bg: const Color(0xFFECFDF5),
          border: AppColors.green,
          dot: AppColors.green,
          text: const Color(0xFF15803D),
          label: 'Resolved',
        );
      case 'rejected':
        return (
          bg: const Color(0xFFFEF2F2),
          border: AppColors.red,
          dot: AppColors.red,
          text: const Color(0xFFDC2626),
          label: 'Rejected',
        );
      default: // pending
        return (
          bg: const Color(0xFFFFF7ED),
          border: AppColors.orange,
          dot: AppColors.orange,
          text: const Color(0xFFB45309),
          label: 'Pending',
        );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LIFECYCLE
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    MySubmissionsScreen.isOpen = true;

    // Deep-link entry (from a reply notification) opens the right tab; the
    // target is flashed by _scrollToHighlight once the fetch resolves and the
    // card actually exists to scroll to.
    _tab = widget.initialTab.clamp(0, 2);

    // Matches ChangePasswordVerifyScreen slide-up pattern
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.10),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));
    _fadeAnim = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut));

    _slideCtrl.forward();

    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    _fetchAll();
  }

  @override
  void dispose() {
    MySubmissionsScreen.isOpen = false;
    _slideCtrl.dispose();
    _shimmerCtrl.dispose();
    _rtDebounce?.cancel();
    if (_rtChannel != null) {
      Supabase.instance.client.removeChannel(_rtChannel!);
    }
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DATA
  // ─────────────────────────────────────────────────────────────────────────

  /// Selects a user's rows, retrying without the optional columns if the fuller
  /// set trips a "column does not exist" error — `dismissed_at` (spam_moderation)
  /// and `responder_photo_url` (submission_responder_avatar) are each optional
  /// migrations. Keeps My Submissions loading on any schema.
  Future<List<Map<String, dynamic>>> _selectRows(
    SupabaseClient db,
    String table,
    String cols,
    String orderCol,
    String userId, {
    String? fallbackCols,
  }) async {
    Future<List<Map<String, dynamic>>> run(String c) async {
      final rows = await db
          .from(table)
          .select(c)
          .eq('user_id', userId)
          .order(orderCol, ascending: false);
      return List<Map<String, dynamic>>.from(rows as List);
    }

    try {
      return await run(cols);
    } on PostgrestException catch (e) {
      final m = e.message.toLowerCase();
      if (fallbackCols != null &&
          (m.contains('dismissed') || m.contains('responder_photo_url'))) {
        return run(fallbackCols);
      }
      rethrow;
    }
  }

  /// Subscribes once to this user's own rows so a change (e.g. an LGU reply)
  /// triggers a debounced silent refresh. No-op if realtime isn't enabled for
  /// the tables — pull-to-refresh remains the fallback.
  void _subscribeRealtime(String userId) {
    if (_rtSubscribed) return;
    _rtSubscribed = true;
    final db = Supabase.instance.client;

    void onChange(PostgresChangePayload _) {
      _rtDebounce?.cancel();
      _rtDebounce = Timer(const Duration(milliseconds: 600), () {
        if (mounted) _fetchAll(showSpinner: false);
      });
    }

    final mine = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'user_id',
      value: userId,
    );

    _rtChannel = db.channel('my_subs_$userId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'reports',
        filter: mine,
        callback: onChange,
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'suggestions',
        filter: mine,
        callback: onChange,
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'feedbacks',
        filter: mine,
        callback: onChange,
      )
      ..subscribe();
  }

  /// [showSpinner] drives the full-screen skeleton (initial load / retry). Pull-
  /// to-refresh passes false so the existing list stays put under the refresh
  /// spinner instead of flashing back to the skeleton.
  Future<void> _fetchAll({bool showSpinner = true}) async {
    if (!mounted) return;
    setState(() {
      if (showSpinner) _loading = true;
      _hasError = false;
    });

    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        if (mounted) {
          setState(() {
            _loading = false;
            _hasError = true;
          });
        }
        return;
      }

      // Reports pull the full column set (`*`) so we can build a ReportItem for
      // the shared detail screen. Suggestions/feedback add `dismissed_at`
      // (spam_moderation migration) with a graceful fallback so an un-migrated
      // DB still loads (the "Closed" state just won't appear).
      final results = await Future.wait([
        _selectRows(
          supabase,
          'reports',
          '*, report_media(id)',
          'created_at',
          userId,
        ),
        _selectRows(
          supabase,
          'suggestions',
          'id, category, category_other, details, barangay, address, '
              'latitude, longitude, created_at, is_anonymous, admin_response, '
              'reviewed_at, dismissed_at, responder_photo_url',
          'created_at',
          userId,
          fallbackCols:
              'id, category, category_other, details, barangay, address, '
              'latitude, longitude, created_at, is_anonymous, admin_response, '
              'reviewed_at',
        ),
        _selectRows(
          supabase,
          'feedbacks',
          'id, office_id, office_label, service_name, overall_rating, '
              'aspect_staff, aspect_wait, aspect_clarity, aspect_facility, '
              'photo_urls, visit_date, created_at, comment, is_anonymous, admin_response, '
              'reviewed_at, dismissed_at, responder_photo_url',
          'visit_date',
          userId,
          fallbackCols:
              'id, office_id, office_label, service_name, overall_rating, '
              'aspect_staff, aspect_wait, aspect_clarity, aspect_facility, '
              'photo_urls, visit_date, created_at, comment, is_anonymous, admin_response, '
              'reviewed_at',
        ),
      ]);

      if (!mounted) return;
      final reportRows = results[0];
      _reportItemById
        ..clear()
        ..addEntries(
          reportRows.map((r) {
            final item = ReportItem.fromMap(r);
            return MapEntry(item.fullId, item);
          }),
        );
      setState(() {
        _reports = reportRows.map((e) => _Report.fromJson(e)).toList();
        _suggestions = results[1].map((e) => _Suggestion.fromJson(e)).toList();
        _feedbacks = results[2].map((e) => _Feedback.fromJson(e)).toList();
        _loading = false;
      });
      _subscribeRealtime(userId);
      await _refreshReplyIndicators();
      _scrollToHighlight();
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _hasError = true;
        });
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UNSEEN-REPLY INDICATORS (client-side, per-user, via SharedPreferences)
  // ─────────────────────────────────────────────────────────────────────────

  DateTime? _latestReplyAmong(Iterable<DateTime?> times) {
    DateTime? best;
    for (final t in times) {
      if (t == null) continue;
      if (best == null || t.isAfter(best)) best = t;
    }
    return best;
  }

  String _seenKey(String kind) {
    final uid = Supabase.instance.client.auth.currentUser?.id ?? 'anon';
    return 'my_sub_seen_${kind}_$uid';
  }

  DateTime? _readTs(SharedPreferences p, String key) {
    final s = p.getString(key);
    return s == null ? null : DateTime.tryParse(s);
  }

  /// Recomputes each tab's newest reply timestamp and compares it against the
  /// last-seen mark to decide whether to show the "unseen" dot. The currently
  /// open Suggestions/Feedback tab is marked seen immediately.
  Future<void> _refreshReplyIndicators() async {
    _latestSuggestionReplyAt = _latestReplyAmong(
      _suggestions.where((s) => s.hasReply).map((s) => s.reviewedAt),
    );
    _latestFeedbackReplyAt = _latestReplyAmong(
      _feedbacks.where((f) => f.hasReply).map((f) => f.reviewedAt),
    );

    final prefs = await SharedPreferences.getInstance();
    final seenSug = _readTs(prefs, _seenKey('suggestion'));
    final seenFb = _readTs(prefs, _seenKey('feedback'));

    if (!mounted) return;
    setState(() {
      _unseenSuggestion =
          _latestSuggestionReplyAt != null &&
          (seenSug == null || _latestSuggestionReplyAt!.isAfter(seenSug));
      _unseenFeedback =
          _latestFeedbackReplyAt != null &&
          (seenFb == null || _latestFeedbackReplyAt!.isAfter(seenFb));
    });

    // Landing straight on a tab (deep-link or normal) clears its dot.
    if (_tab == 1) _markTabSeen(1);
    if (_tab == 2) _markTabSeen(2);
  }

  /// Persists the tab's newest reply timestamp as "seen" and drops its dot.
  Future<void> _markTabSeen(int tab) async {
    if (tab != 1 && tab != 2) return;
    final latest = tab == 1 ? _latestSuggestionReplyAt : _latestFeedbackReplyAt;
    if (latest == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _seenKey(tab == 1 ? 'suggestion' : 'feedback'),
      latest.toIso8601String(),
    );
    if (!mounted) return;
    setState(() {
      if (tab == 1) _unseenSuggestion = false;
      if (tab == 2) _unseenFeedback = false;
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DEEP-LINK HIGHLIGHT — scroll + flash come from DeepLinkHighlightMixin.
  // ─────────────────────────────────────────────────────────────────────────

  void _scrollToHighlight() => flashHighlight(widget.highlightId);

  // ── Filtered reports list ──────────────────────────────────────────────────
  List<_Report> get _filteredReports {
    if (_filter == 'all') return _reports;
    return _reports.where((r) => r.status == _filter).toList();
  }

  // ── Filtered suggestions / feedback (all | replied | awaiting) ─────────────
  List<_Suggestion> get _filteredSuggestions {
    switch (_replyFilter) {
      case 'replied':
        return _suggestions.where((s) => s.hasReply).toList();
      case 'awaiting':
        // Closed (spam-dismissed) items aren't awaiting anything.
        return _suggestions.where((s) => !s.hasReply && !s.isClosed).toList();
      default:
        return _suggestions;
    }
  }

  List<_Feedback> get _filteredFeedbacks {
    switch (_replyFilter) {
      case 'replied':
        return _feedbacks.where((f) => f.hasReply).toList();
      case 'awaiting':
        return _feedbacks.where((f) => !f.hasReply && !f.isClosed).toList();
      default:
        return _feedbacks;
    }
  }

  // ── Date helper ────────────────────────────────────────────────────────────
  String _fmt(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // ── The browser always gets the web layout ──────────────────────────────
    //
    // `kIsWeb` alone, no width test, for the reason spelled out in
    // EditProfileScreen: a width test hands narrow BROWSERS the phone layout,
    // and the phone layout is built for the app — proportional type sized off a
    // 480px clamp, a back chevron for a screen you pushed, a pull-to-refresh
    // gesture a mouse cannot make. The web layout collapses on its own via
    // [AccountPageBody]'s `stack` flag, so it handles a narrow window without
    // borrowing any of that.
    if (kIsWeb) return _buildWebScaffold();

    final w = uiScaleWidth(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: ResponsivePageBody(
        maxWidth: 760,
        shellTitle: 'My Submissions',
        shellSubtitle:
            'Track the status of your reports and verification requests in '
            'one place.',
        shellIcon: Icons.folder_shared_rounded,
        shellHighlights: const [
          (Icons.flag_rounded, 'Reports you have filed'),
          (Icons.verified_user_rounded, 'Verification history'),
          (Icons.filter_list_rounded, 'Filter by status & time'),
        ],
        shellContentWidth: 560,
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(w),
              Expanded(
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: SlideTransition(
                    position: _slideAnim,
                    child: Column(
                      children: [
                        _buildTabBar(w),
                        // Filter chips — Reports get status filters; Suggestions
                        // & Feedback get a lighter replied/awaiting filter.
                        if (!_loading && !_hasError)
                          _tab == 0
                              ? _buildFilterChips(w)
                              : _buildReplyFilterChips(w),
                        Expanded(
                          child: _loading
                              ? const MySubmissionsBodySkeleton()
                              : _hasError
                              ? _buildError(w)
                              : RefreshIndicator(
                                  onRefresh: () =>
                                      _fetchAll(showSpinner: false),
                                  color: AppColors.primaryBlue,
                                  child: _buildContent(w),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HEADER — identical to ChangePasswordVerifyScreen
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildHeader(double w) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(w * 0.04, w * 0.04, w * 0.04, w * 0.035),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: w * 0.09,
              height: w * 0.09,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(w * 0.025),
                border: Border.all(color: CitizenUi.sharedStroke),
              ),
              child: Icon(
                Icons.arrow_back_ios_rounded,
                size: w * 0.04,
                color: AppColors.primaryBlue,
              ),
            ),
          ),
          SizedBox(width: w * 0.035),
          Text(
            'My Submissions',
            style: TextStyle(
              fontSize: w * 0.052,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryBlue,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }

  /// Switches tab and resets both filters.
  ///
  /// Pure extraction of what the mobile tab strip's `onTap` already did, so the
  /// web tab bar cannot drift from it — same three assignments, same
  /// `_markTabSeen` call, same order.
  void _selectTab(int i) {
    setState(() {
      _tab = i;
      _filter = 'all';
      _replyFilter = 'all';
    });
    // Opening Suggestions/Feedback clears its unseen dot.
    if (i == 1 || i == 2) _markTabSeen(i);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAB BAR
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildTabBar(double w) {
    final tabs = [
      ('Reports', _reports.length),
      ('Suggestions', _suggestions.length),
      ('Feedback', _feedbacks.length),
    ];
    return Container(
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: List.generate(tabs.length, (i) {
              final isActive = _tab == i;
              return Expanded(
                child: GestureDetector(
                  onTap: () => _selectTab(i),
                  child: Container(
                    color: Colors.transparent,
                    padding: EdgeInsets.symmetric(vertical: w * 0.03),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          tabs[i].$1,
                          style: TextStyle(
                            fontSize: w * 0.031,
                            fontWeight: isActive
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isActive
                                ? AppColors.primaryBlue
                                : const Color(0xFF6B7280),
                          ),
                        ),
                        if (!_loading) ...[
                          SizedBox(width: w * 0.012),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: w * 0.016,
                              vertical: w * 0.004,
                            ),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? AppColors.primaryBlue.withValues(
                                      alpha: 0.10,
                                    )
                                  : const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(w * 0.04),
                            ),
                            child: Text(
                              '${tabs[i].$2}',
                              style: TextStyle(
                                fontSize: w * 0.026,
                                fontWeight: FontWeight.w600,
                                color: isActive
                                    ? AppColors.primaryBlue
                                    : const Color(0xFF9CA3AF),
                              ),
                            ),
                          ),
                        ],
                        // Unseen-reply dot — a new LGU reply this user hasn't
                        // opened yet (Suggestions / Feedback tabs only).
                        if (!_loading &&
                            ((i == 1 && _unseenSuggestion) ||
                                (i == 2 && _unseenFeedback))) ...[
                          SizedBox(width: w * 0.012),
                          Container(
                            width: w * 0.02,
                            height: w * 0.02,
                            decoration: const BoxDecoration(
                              color: Color(0xFFEF4444),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
          // Active underline indicator
          Row(
            children: List.generate(tabs.length, (i) {
              return Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 2.5,
                  color: _tab == i ? AppColors.primaryBlue : Colors.transparent,
                ),
              );
            }),
          ),
          Divider(height: 1, color: CitizenUi.sharedStroke),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FILTER CHIPS (Reports only)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildFilterChips(double w) {
    const filters = [
      ('all', 'All'),
      ('pending', 'Pending'),
      ('in_progress', 'In Progress'),
      ('resolved', 'Resolved'),
    ];
    return Container(
      color: const Color(0xFFF3F4F6),
      padding: EdgeInsets.fromLTRB(w * 0.04, w * 0.025, w * 0.04, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: filters.map((f) {
            final isActive = _filter == f.$1;
            return Padding(
              padding: EdgeInsets.only(right: w * 0.02),
              child: GestureDetector(
                onTap: () => setState(() => _filter = f.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: EdgeInsets.symmetric(
                    horizontal: w * 0.033,
                    vertical: w * 0.014,
                  ),
                  decoration: BoxDecoration(
                    color: isActive ? AppColors.primaryBlue : Colors.white,
                    borderRadius: BorderRadius.circular(w * 0.05),
                    border: Border.all(
                      color: isActive
                          ? AppColors.primaryBlue
                          : AppColors.stroke,
                    ),
                  ),
                  child: Text(
                    f.$2,
                    style: TextStyle(
                      fontSize: w * 0.028,
                      fontWeight: FontWeight.w600,
                      color: isActive ? Colors.white : const Color(0xFF6B7280),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // REPLY FILTER CHIPS (Suggestions & Feedback) — all | replied | awaiting
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildReplyFilterChips(double w) {
    // Same wording on both tabs. "No reply yet" is neutral and true for either:
    // suggestions await a reply, feedback isn't owed one per rating.
    const filters = [
      ('all', 'All'),
      ('replied', 'Replied'),
      ('awaiting', 'No reply yet'),
    ];
    return Container(
      color: const Color(0xFFF3F4F6),
      padding: EdgeInsets.fromLTRB(w * 0.04, w * 0.025, w * 0.04, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: filters.map((f) {
            final isActive = _replyFilter == f.$1;
            return Padding(
              padding: EdgeInsets.only(right: w * 0.02),
              child: GestureDetector(
                onTap: () => setState(() => _replyFilter = f.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: EdgeInsets.symmetric(
                    horizontal: w * 0.033,
                    vertical: w * 0.014,
                  ),
                  decoration: BoxDecoration(
                    color: isActive ? AppColors.primaryBlue : Colors.white,
                    borderRadius: BorderRadius.circular(w * 0.05),
                    border: Border.all(
                      color: isActive
                          ? AppColors.primaryBlue
                          : AppColors.stroke,
                    ),
                  ),
                  child: Text(
                    f.$2,
                    style: TextStyle(
                      fontSize: w * 0.028,
                      fontWeight: FontWeight.w600,
                      color: isActive ? Colors.white : const Color(0xFF6B7280),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CONTENT SWITCHER
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildContent(double w) {
    return switch (_tab) {
      0 => _buildReportsList(w),
      1 => _buildSuggestionsList(w),
      2 => _buildFeedbackList(w),
      _ => const SizedBox.shrink(),
    };
  }

  /// Wraps non-list content (empty states) so it fills the viewport and still
  /// responds to pull-to-refresh — otherwise a citizen on an empty tab couldn't
  /// pull to check for a newly-arrived LGU reply.
  Widget _scrollableFill(double w, Widget child) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: child,
      ),
    ),
  );

  Widget _buildReportsList(double w) {
    final list = _filteredReports;
    if (list.isEmpty) {
      return _scrollableFill(
        w,
        _buildEmpty(
          w,
          icon: Icons.report_outlined,
          title: 'No reports found',
          subtitle: _filter != 'all'
              ? 'No reports with this status.'
              : 'You have not submitted any reports yet.',
        ),
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(w * 0.04, w * 0.025, w * 0.04, w * 0.08),
      itemCount: list.length,
      itemBuilder: (_, i) => _buildReportCard(w, list[i]),
    );
  }

  Widget _buildSuggestionsList(double w) {
    final list = _filteredSuggestions;
    if (list.isEmpty) {
      return _scrollableFill(
        w,
        _buildEmpty(
          w,
          icon: Icons.lightbulb_outline_rounded,
          title: 'No suggestions found',
          subtitle: _replyFilter != 'all'
              ? 'No suggestions in this filter.'
              : 'You have not submitted any suggestions yet.',
        ),
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(w * 0.04, w * 0.025, w * 0.04, w * 0.08),
      itemCount: list.length,
      itemBuilder: (_, i) => _buildSuggestionCard(w, list[i]),
    );
  }

  Widget _buildFeedbackList(double w) {
    final list = _filteredFeedbacks;
    if (list.isEmpty) {
      return _scrollableFill(
        w,
        _buildEmpty(
          w,
          icon: Icons.star_outline_rounded,
          title: 'No feedback found',
          subtitle: _replyFilter != 'all'
              ? 'No feedback in this filter.'
              : 'You have not submitted any feedback yet.',
        ),
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(w * 0.04, w * 0.025, w * 0.04, w * 0.08),
      itemCount: list.length,
      itemBuilder: (_, i) => _buildFeedbackCard(w, list[i]),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // REPORT CARD
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildReportCard(double w, _Report r) {
    final cat = _reportCats[r.category] ?? _reportCats['others']!;
    final label = r.category == 'others' && r.categoryOther != null
        ? r.categoryOther!
        : cat.label;
    final status = _statusCfg(r.status);

    return GestureDetector(
      onTap: () => _openReportDetail(r),
      child: Container(
        margin: EdgeInsets.only(bottom: w * 0.03),
        padding: EdgeInsets.all(w * 0.038),
        decoration: _cardDecoration(w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildIconChip(w, asset: cat.asset, color: cat.color),
                SizedBox(width: w * 0.03),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title + single status pill — what it is, at a glance.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: w * 0.034,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF1F2937),
                                height: 1.25,
                              ),
                            ),
                          ),
                          SizedBox(width: w * 0.02),
                          _buildStatusBadge(w, status),
                        ],
                      ),
                      SizedBox(height: w * 0.014),
                      // Meta line — wraps, so it can never overflow on narrow
                      // phones or inside the 600px web shell column.
                      Wrap(
                        spacing: w * 0.025,
                        runSpacing: w * 0.012,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _metaId(
                            w,
                            'RPT-${r.id.substring(0, 8).toUpperCase()}',
                          ),
                          if (r.barangay != null && r.barangay!.isNotEmpty)
                            _metaItem(
                              w,
                              Icons.location_on_outlined,
                              r.barangay!,
                              maxWidth: w * 0.42,
                            ),
                          _metaItem(
                            w,
                            Icons.calendar_today_outlined,
                            _fmt(r.createdAt),
                          ),
                          if (r.mediaCount > 0)
                            _metaItem(
                              w,
                              Icons.attach_file_rounded,
                              '${r.mediaCount} ${r.mediaCount == 1 ? 'file' : 'files'}',
                            ),
                          if (r.isAnonymous) _buildAnonBadge(w),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // Remarks — full card width for a readable line length.
            if (r.remarks != null && r.remarks!.isNotEmpty) ...[
              SizedBox(height: w * 0.022),
              Text(
                r.remarks!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                softWrap: true,
                style: TextStyle(
                  fontSize: w * 0.031,
                  color: const Color(0xFF374151),
                  height: 1.45,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Opens the shared, rich report detail (timeline · chat · resolution media),
  /// reusing the same screen as the dedicated "My Reports" list for parity.
  void _openReportDetail(_Report r) {
    final item = _reportItemById[r.id];
    if (item == null) return;
    // Canonical /report_detail route: instant enter, fade-out exit, and the
    // detail's own slide-up body + shimmer skeleton — consistent app-wide.
    pushLegacy(
      context,
      '/report_detail',
      arguments: {'report': item, 'username': widget.username},
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SUGGESTION CARD — no status badge (suggestions have no workflow state)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildSuggestionCard(double w, _Suggestion s) {
    final cat = _suggestionCats[s.category] ?? _suggestionCats['others']!;
    final label = s.category == 'others' && s.categoryOther != null
        ? s.categoryOther!
        : cat.label;
    final key = highlightKey(s.id);
    final highlighted = isHighlighted(s.id);

    return GestureDetector(
      onTap: () => _openSuggestionDetail(context, s, label),
      child: AnimatedContainer(
        key: key,
        duration: const Duration(milliseconds: 450),
        margin: EdgeInsets.only(bottom: w * 0.03),
        padding: EdgeInsets.all(w * 0.038),
        decoration: highlighted ? _highlightDecoration(w) : _cardDecoration(w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildIconChip(w, asset: cat.asset, color: cat.color),
                SizedBox(width: w * 0.03),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title + at most one state pill (Replied/Closed are
                      // mutually exclusive), so this row can't overflow.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: w * 0.034,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF1F2937),
                                height: 1.25,
                              ),
                            ),
                          ),
                          if (s.hasReply || s.isClosed) ...[
                            SizedBox(width: w * 0.02),
                            if (s.hasReply)
                              _buildRepliedBadge(w)
                            else
                              _buildClosedBadge(w),
                          ],
                        ],
                      ),
                      SizedBox(height: w * 0.014),
                      Wrap(
                        spacing: w * 0.025,
                        runSpacing: w * 0.012,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _metaId(
                            w,
                            'SGS-${s.id.substring(0, 8).toUpperCase()}',
                          ),
                          _metaItem(
                            w,
                            Icons.calendar_today_outlined,
                            _fmt(s.createdAt),
                          ),
                          if (s.isAnonymous) _buildAnonBadge(w),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // Details — full card width for a readable line length.
            if (s.details != null && s.details!.isNotEmpty) ...[
              SizedBox(height: w * 0.022),
              Text(
                s.details!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                softWrap: true,
                style: TextStyle(
                  fontSize: w * 0.031,
                  color: const Color(0xFF374151),
                  height: 1.45,
                ),
              ),
            ],
            // Official LGU reply — spans the full card width below the summary.
            if (s.hasReply)
              _buildResponseBlock(
                w,
                s.adminResponse!,
                s.reviewedAt,
                responderPhotoUrl: s.responderPhotoUrl,
              ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FEEDBACK CARD — no status badge; star rating instead
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildFeedbackCard(double w, _Feedback f) {
    final office = _officeCfg[f.officeId];
    final key = highlightKey(f.id);
    final highlighted = isHighlighted(f.id);

    return GestureDetector(
      onTap: () => _openFeedbackDetail(context, f),
      child: AnimatedContainer(
        key: key,
        duration: const Duration(milliseconds: 450),
        margin: EdgeInsets.only(bottom: w * 0.03),
        padding: EdgeInsets.all(w * 0.038),
        decoration: highlighted ? _highlightDecoration(w) : _cardDecoration(w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildIconChip(
                  w,
                  icon: office?.icon ?? Icons.business_rounded,
                  color: office?.color ?? AppColors.primaryBlue,
                ),
                SizedBox(width: w * 0.03),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title + at most one state pill; Anonymous moves to the
                      // wrapping meta line so this row can't overflow.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              f.officeLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: w * 0.034,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF1F2937),
                                height: 1.25,
                              ),
                            ),
                          ),
                          if (f.hasReply || f.isClosed) ...[
                            SizedBox(width: w * 0.02),
                            if (f.hasReply)
                              _buildRepliedBadge(w)
                            else
                              _buildClosedBadge(w),
                          ],
                        ],
                      ),
                      SizedBox(height: w * 0.014),
                      // Stars + visit date + id — wraps on narrow widths.
                      Wrap(
                        spacing: w * 0.025,
                        runSpacing: w * 0.012,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _buildStars(w, f.rating),
                          _metaItem(
                            w,
                            Icons.calendar_today_outlined,
                            _fmt(f.visitDate),
                          ),
                          _metaId(
                            w,
                            'FBK-${f.id.substring(0, 8).toUpperCase()}',
                          ),
                          if (f.isAnonymous) _buildAnonBadge(w),
                        ],
                      ),
                      SizedBox(height: w * 0.012),
                      // Service name — muted, truncated
                      Text(
                        f.serviceName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: w * 0.028,
                          color: const Color(0xFF9CA3AF),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // Comment — full card width for a readable line length.
            if (f.comment != null && f.comment!.isNotEmpty) ...[
              SizedBox(height: w * 0.022),
              Text(
                f.comment!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                softWrap: true,
                style: TextStyle(
                  fontSize: w * 0.031,
                  color: const Color(0xFF374151),
                  height: 1.45,
                ),
              ),
            ],
            // Official LGU reply — spans the full card width below the summary.
            if (f.hasReply)
              _buildResponseBlock(
                w,
                f.adminResponse!,
                f.reviewedAt,
                responderPhotoUrl: f.responderPhotoUrl,
              ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SHARED WIDGETS
  // ─────────────────────────────────────────────────────────────────────────

  // ── Compact leading icon chip — the label lives in the card title now, not
  // squeezed underneath the icon, so every card keeps one visual anchor and the
  // full width for its text. Pass [asset] (report/suggestion art) or [icon]
  // (feedback offices).
  Widget _buildIconChip(
    double w, {
    String? asset,
    IconData? icon,
    required Color color,
  }) {
    final size = w * 0.115;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.18),
            color.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(w * 0.034),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: asset != null
          ? Padding(
              padding: EdgeInsets.all(w * 0.022),
              child: Image.asset(
                asset,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Icon(
                  Icons.category_rounded,
                  size: size * 0.5,
                  color: color,
                ),
              ),
            )
          : Icon(
              icon ?? Icons.business_rounded,
              size: size * 0.5,
              color: color,
            ),
    );
  }

  // ── One muted icon+text item on a card's meta line. [maxWidth] caps long
  // free text (barangay names) so the item ellipsizes instead of pushing the
  // Wrap onto endless rows.
  Widget _metaItem(double w, IconData icon, String text, {double? maxWidth}) {
    final label = Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: w * 0.028,
        fontWeight: FontWeight.w500,
        color: const Color(0xFF9CA3AF),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: w * 0.03, color: const Color(0xFF9CA3AF)),
        SizedBox(width: w * 0.01),
        maxWidth == null
            ? label
            : ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: label,
              ),
      ],
    );
  }

  // ── Short submission id (RPT-/SGS-/FBK-…) — matches the detail hero's id so
  // a citizen can connect a card to a notification or a conversation.
  Widget _metaId(double w, String id) => Text(
    id,
    style: TextStyle(
      fontSize: w * 0.026,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.3,
      color: const Color(0xFF9CA3AF),
    ),
  );

  // ── Anonymous indicator pill ────────────────────────────────────────────────
  Widget _buildAnonBadge(double w) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: w * 0.02, vertical: w * 0.008),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(w * 0.05),
        border: Border.all(color: CitizenUi.sharedBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.person_off_rounded,
            size: w * 0.03,
            color: const Color(0xFF6B7280),
          ),
          SizedBox(width: w * 0.012),
          Text(
            'Anonymous',
            style: TextStyle(
              fontSize: w * 0.025,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF6B7280),
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }

  // ── "Replied" pill — the LGU has responded to this submission ──────────────
  Widget _buildRepliedBadge(double w) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: w * 0.02, vertical: w * 0.008),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(w * 0.05),
        border: Border.all(color: AppColors.green.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.mark_chat_read_rounded,
            size: w * 0.03,
            color: const Color(0xFF15803D),
          ),
          SizedBox(width: w * 0.012),
          Text(
            'Replied',
            style: TextStyle(
              fontSize: w * 0.025,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF15803D),
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }

  // ── Neutral "Closed" pill — admin closed a spam-dismissed submission. Shows a
  // plain status (never the internal spam reason) so it doesn't read as forever
  // awaiting a reply.
  Widget _buildClosedBadge(double w) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: w * 0.02, vertical: w * 0.008),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(w * 0.05),
        border: Border.all(color: const Color(0xFFD1D5DB)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            size: w * 0.03,
            color: const Color(0xFF6B7280),
          ),
          SizedBox(width: w * 0.012),
          Text(
            'Closed',
            style: TextStyle(
              fontSize: w * 0.025,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF6B7280),
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }

  // ── Official LGU response block — shown inline under a replied submission ───
  Widget _buildResponseBlock(
    double w,
    String response,
    DateTime? reviewedAt, {
    String? responderPhotoUrl,
  }) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(top: w * 0.032),
      padding: EdgeInsets.all(w * 0.033),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(w * 0.032),
        border: Border.all(color: const Color(0xFFBAE6FD)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ResponderAvatar(photoUrl: responderPhotoUrl, size: w * 0.052),
              SizedBox(width: w * 0.02),
              Text(
                'LGU Response',
                style: TextStyle(
                  fontSize: w * 0.028,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryBlue,
                ),
              ),
              if (reviewedAt != null) ...[
                const Spacer(),
                Text(
                  _fmt(reviewedAt),
                  style: TextStyle(
                    fontSize: w * 0.025,
                    color: const Color(0xFF9CA3AF),
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: w * 0.018),
          Text(
            response,
            style: TextStyle(
              fontSize: w * 0.03,
              color: const Color(0xFF1F2937),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(
    double w,
    ({Color bg, Color border, Color dot, Color text, String label}) s,
  ) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: w * 0.025, vertical: w * 0.012),
      decoration: BoxDecoration(
        color: s.bg,
        borderRadius: BorderRadius.circular(w * 0.05),
        border: Border.all(color: s.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: w * 0.016,
            height: w * 0.016,
            decoration: BoxDecoration(color: s.dot, shape: BoxShape.circle),
          ),
          SizedBox(width: w * 0.012),
          Text(
            s.label,
            style: TextStyle(
              fontSize: w * 0.026,
              fontWeight: FontWeight.w700,
              color: s.text,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStars(double w, int rating) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        5,
        (i) => Icon(
          i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
          size: w * 0.038,
          color: i < rating ? const Color(0xFFF59E0B) : const Color(0xFFD1D5DB),
        ),
      ),
    );
  }

  BoxDecoration _cardDecoration(double w) => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(w * 0.05),
    border: Border.all(color: const Color(0xFFEEF1F5)),
    boxShadow: [
      BoxShadow(
        color: const Color(0xFF1F2937).withValues(alpha: 0.07),
        blurRadius: 20,
        offset: const Offset(0, 9),
        spreadRadius: -8,
      ),
    ],
  );

  // Accent used to flash the card a reply notification deep-linked to. It fades
  // back to [_cardDecoration] via the AnimatedContainer once the highlight
  // clears (~2.2s after arrival).
  BoxDecoration _highlightDecoration(double w) =>
      highlightDecoration(radius: w * 0.05, accent: AppColors.primaryBlue);

  // ── Error ───────────────────────────────────────────────────────────────────
  Widget _buildError(double w) => Center(
    child: Padding(
      padding: EdgeInsets.all(w * 0.08),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: w * 0.14,
            color: const Color(0xFFD1D5DB),
          ),
          SizedBox(height: w * 0.04),
          Text(
            'Could not load submissions',
            style: TextStyle(
              fontSize: w * 0.038,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF374151),
            ),
          ),
          SizedBox(height: w * 0.02),
          TextButton(
            onPressed: _fetchAll,
            child: Text(
              'Try again',
              style: TextStyle(
                fontSize: w * 0.036,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryBlue,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  // ── Empty state ─────────────────────────────────────────────────────────────
  Widget _buildEmpty(
    double w, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) => Center(
    child: Padding(
      padding: EdgeInsets.all(w * 0.08),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: w * 0.16, color: const Color(0xFFD1D5DB)),
          SizedBox(height: w * 0.04),
          Text(
            title,
            style: TextStyle(
              fontSize: w * 0.038,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF374151),
            ),
          ),
          SizedBox(height: w * 0.015),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: w * 0.032,
              color: const Color(0xFF9CA3AF),
              height: 1.5,
            ),
          ),
        ],
      ),
    ),
  );

  // ═════════════════════════════════════════════════════════════════════════
  //  WEB
  //
  //  Reached only from the `kIsWeb` branch of build(). Everything above this
  //  line is the mobile app's and is untouched: this section adds a second
  //  layout over the SAME state, filters, realtime subscription and deep-link
  //  highlight, and never changes any of them.
  // ═════════════════════════════════════════════════════════════════════════

  /// True while a manual web refresh is in flight, so the Refresh button can
  /// show it. Deliberately separate from `_loading`: a refresh must NOT tear
  /// the list down to a skeleton, because the rows you are looking at are still
  /// valid until the new ones land.
  bool _webRefreshing = false;

  Future<void> _webRefresh() async {
    if (_webRefreshing) return;
    setState(() => _webRefreshing = true);
    await _fetchAll(showSpinner: false);
    if (mounted) setState(() => _webRefreshing = false);
  }

  Widget _buildWebScaffold() {
    // No ResponsivePageBody, and so no `shellTitle` — passing one wraps the
    // page in SettingsWebShell's 600px column beside a decorative brand panel,
    // which is right for a standalone route and wrong inside a pane that
    // already has a top nav and a left rail.
    return Scaffold(
      backgroundColor: CitizenUi.pageBg,
      body: SafeArea(
        // Not MySubmissionsBodySkeleton — that one draws the MOBILE card at
        // `w * 0.05` radii with no page header at all, so it promised a shape
        // this layout never produces. [AccountPageSkeleton] is built from the
        // same AccountPageBody/AccountCard the real page is, and `tabs`,
        // `chips` and `cards` mirror the three things below it one for one.
        child: _loading
            ? const AccountPageSkeleton(tabs: true, chips: true, cards: 4)
            : AccountPageBody(builder: _buildWebBody),
      ),
    );
  }

  Widget _buildWebBody(BuildContext context, bool stack) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AccountPageTitle(
          title: 'My Submissions',
          subtitle:
              'Everything you have filed — reports, suggestions and feedback — '
              'and how the LGU responded.',
        ),
        AccountTabBar(
          index: _tab,
          stack: stack,
          onChanged: _selectTab,
          trailing: _buildWebRefreshButton(),
          tabs: [
            AccountTab('Reports', count: _reports.length),
            AccountTab(
              'Suggestions',
              count: _suggestions.length,
              dot: _unseenSuggestion,
            ),
            AccountTab(
              'Feedback',
              count: _feedbacks.length,
              dot: _unseenFeedback,
            ),
          ],
        ),
        if (_hasError) ...[
          const SizedBox(height: 18),
          AccountEmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Could not load submissions',
            message:
                'Something went wrong reaching the server. Check your '
                'connection and try again.',
            actionLabel: 'Try again',
            onAction: _fetchAll,
          ),
        ] else ...[
          const SizedBox(height: 16),
          AccountChipRow(
            value: _tab == 0 ? _filter : _replyFilter,
            onChanged: (v) => setState(() {
              if (_tab == 0) {
                _filter = v;
              } else {
                _replyFilter = v;
              }
            }),
            chips: _tab == 0
                ? const [
                    AccountChip('all', 'All'),
                    AccountChip('pending', 'Pending'),
                    AccountChip('in_progress', 'In Progress'),
                    AccountChip('resolved', 'Resolved'),
                  ]
                : const [
                    AccountChip('all', 'All'),
                    AccountChip('replied', 'Replied'),
                    AccountChip('awaiting', 'No reply yet'),
                  ],
          ),
          _buildWebContent(stack),
        ],
      ],
    );
  }

  /// Web's replacement for pull-to-refresh, which needs a finger. Realtime
  /// already pushes changes, so this is a reassurance control rather than the
  /// only way to see a new reply — which is why it is quiet and secondary.
  Widget _buildWebRefreshButton() {
    return OutlinedButton.icon(
      onPressed: _webRefreshing ? null : _webRefresh,
      style: accountSecondaryButtonStyle().copyWith(
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
      ),
      icon: _webRefreshing
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh_rounded, size: 16),
      label: const Text('Refresh'),
    );
  }

  // ── Lists ─────────────────────────────────────────────────────────────────
  //
  // A Column, not a ListView. [AccountPageBody] already owns the page's one
  // scroller, and nesting a second one inside it is both an unbounded-height
  // error and the wrong behaviour — a list that scrolls independently of the
  // page it is on. Building every row also FIXES the deep-link highlight: a
  // ListView.builder never builds an off-screen row, so `flashHighlight` could
  // find no context to scroll to; a Column always has one.

  Widget _buildWebContent(bool stack) {
    return switch (_tab) {
      0 => _buildWebReportsList(stack),
      1 => _buildWebSuggestionsList(stack),
      2 => _buildWebFeedbackList(stack),
      _ => const SizedBox.shrink(),
    };
  }

  Widget _buildWebList(List<Widget> cards) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < cards.length; i++) ...[
        SizedBox(height: i == 0 ? 18 : 12),
        cards[i],
      ],
    ],
  );

  Widget _buildWebEmpty({
    required IconData icon,
    required String title,
    required String message,
  }) => Padding(
    padding: const EdgeInsets.only(top: 18),
    child: AccountEmptyState(icon: icon, title: title, message: message),
  );

  Widget _buildWebReportsList(bool stack) {
    final list = _filteredReports;
    if (list.isEmpty) {
      return _buildWebEmpty(
        icon: Icons.flag_outlined,
        title: 'No reports found',
        message: _filter != 'all'
            ? 'No reports with this status. Try a different filter.'
            : 'You have not submitted any reports yet.',
      );
    }
    return _buildWebList([for (final r in list) _buildWebReportCard(r, stack)]);
  }

  Widget _buildWebSuggestionsList(bool stack) {
    final list = _filteredSuggestions;
    if (list.isEmpty) {
      return _buildWebEmpty(
        icon: Icons.lightbulb_outline_rounded,
        title: 'No suggestions found',
        message: _replyFilter != 'all'
            ? 'No suggestions in this filter. Try a different one.'
            : 'You have not submitted any suggestions yet.',
      );
    }
    return _buildWebList([
      for (final s in list) _buildWebSuggestionCard(s, stack),
    ]);
  }

  Widget _buildWebFeedbackList(bool stack) {
    final list = _filteredFeedbacks;
    if (list.isEmpty) {
      return _buildWebEmpty(
        icon: Icons.star_outline_rounded,
        title: 'No feedback found',
        message: _replyFilter != 'all'
            ? 'No feedback in this filter. Try a different one.'
            : 'You have not submitted any feedback yet.',
      );
    }
    return _buildWebList([
      for (final f in list) _buildWebFeedbackCard(f, stack),
    ]);
  }

  // ── Card shell ────────────────────────────────────────────────────────────

  /// The surface every web submission card sits on: [AccountCard]'s colour,
  /// radius and hairline, plus a hover state and the deep-link flash.
  ///
  /// Not [AccountCard] itself, because the highlight has to animate the whole
  /// decoration — border, wash and glow together — which means one
  /// AnimatedContainer owning it rather than a Container that swaps children.
  Widget _buildWebCard({
    Key? cardKey,
    bool highlighted = false,
    required bool stack,
    required VoidCallback onTap,
    required Widget child,
  }) {
    return AnimatedContainer(
      key: cardKey,
      duration: kHighlightFade,
      decoration: highlighted
          ? highlightDecoration(
              radius: kAccountRadius,
              accent: CitizenUi.accent,
            )
          : BoxDecoration(
              color: CitizenUi.surface,
              borderRadius: BorderRadius.circular(kAccountRadius),
              border: Border.all(color: CitizenUi.border),
            ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(kAccountRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(kAccountRadius),
          child: Padding(
            padding: EdgeInsets.all(stack ? 16 : 18),
            child: child,
          ),
        ),
      ),
    );
  }

  // ── Cards ─────────────────────────────────────────────────────────────────

  Widget _buildWebReportCard(_Report r, bool stack) {
    final cat = _reportCats[r.category] ?? _reportCats['others']!;
    final label = r.category == 'others' && r.categoryOther != null
        ? r.categoryOther!
        : cat.label;
    final status = _statusCfg(r.status);

    return _buildWebCard(
      stack: stack,
      onTap: () => _openReportDetail(r),
      child: _webCardLayout(
        stack: stack,
        leading: _webIconChip(asset: cat.asset, color: cat.color),
        title: label,
        badge: _webStatusBadge(status),
        meta: [
          _webMetaId('RPT-${r.id.substring(0, 8).toUpperCase()}'),
          if (r.barangay != null && r.barangay!.isNotEmpty)
            _webMetaItem(
              Icons.location_on_outlined,
              r.barangay!,
              maxWidth: 200,
            ),
          _webMetaItem(Icons.calendar_today_outlined, _fmt(r.createdAt)),
          if (r.mediaCount > 0)
            _webMetaItem(
              Icons.attach_file_rounded,
              '${r.mediaCount} ${r.mediaCount == 1 ? 'file' : 'files'}',
            ),
          if (r.isAnonymous) _webAnonBadge(),
        ],
        body: r.remarks,
      ),
    );
  }

  Widget _buildWebSuggestionCard(_Suggestion s, bool stack) {
    final cat = _suggestionCats[s.category] ?? _suggestionCats['others']!;
    final label = s.category == 'others' && s.categoryOther != null
        ? s.categoryOther!
        : cat.label;

    return _buildWebCard(
      cardKey: highlightKey(s.id),
      highlighted: isHighlighted(s.id),
      stack: stack,
      onTap: () => _openSuggestionDetail(context, s, label),
      child: _webCardLayout(
        stack: stack,
        leading: _webIconChip(asset: cat.asset, color: cat.color),
        title: label,
        badge: s.hasReply
            ? _webRepliedBadge()
            : s.isClosed
            ? _webClosedBadge()
            : null,
        meta: [
          _webMetaId('SGS-${s.id.substring(0, 8).toUpperCase()}'),
          _webMetaItem(Icons.calendar_today_outlined, _fmt(s.createdAt)),
          if (s.isAnonymous) _webAnonBadge(),
        ],
        body: s.details,
        footer: s.hasReply
            ? _webResponseBlock(
                s.adminResponse!,
                s.reviewedAt,
                responderPhotoUrl: s.responderPhotoUrl,
              )
            : null,
      ),
    );
  }

  Widget _buildWebFeedbackCard(_Feedback f, bool stack) {
    final office = _officeCfg[f.officeId];

    return _buildWebCard(
      cardKey: highlightKey(f.id),
      highlighted: isHighlighted(f.id),
      stack: stack,
      onTap: () => _openFeedbackDetail(context, f),
      child: _webCardLayout(
        stack: stack,
        leading: _webIconChip(
          icon: office?.icon ?? Icons.business_rounded,
          color: office?.color ?? CitizenUi.accent,
        ),
        title: f.officeLabel,
        badge: f.hasReply
            ? _webRepliedBadge()
            : f.isClosed
            ? _webClosedBadge()
            : null,
        subtitle: f.serviceName,
        meta: [
          _webStars(f.rating),
          _webMetaItem(Icons.calendar_today_outlined, _fmt(f.visitDate)),
          _webMetaId('FBK-${f.id.substring(0, 8).toUpperCase()}'),
          if (f.isAnonymous) _webAnonBadge(),
        ],
        body: f.comment,
        footer: f.hasReply
            ? _webResponseBlock(
                f.adminResponse!,
                f.reviewedAt,
                responderPhotoUrl: f.responderPhotoUrl,
              )
            : null,
      ),
    );
  }

  /// The one arrangement all three web cards use, so a report, a suggestion and
  /// a feedback row cannot end up three different shapes: glyph, then title
  /// with an optional state pill, an optional service line, a wrapping meta
  /// line, an optional two-line excerpt, and an optional reply block.
  Widget _webCardLayout({
    required bool stack,
    required Widget leading,
    required String title,
    required List<Widget> meta,
    Widget? badge,
    String? subtitle,
    String? body,
    Widget? footer,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            leading,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                            color: CitizenUi.textPrimary,
                          ),
                        ),
                      ),
                      if (badge != null) ...[const SizedBox(width: 10), badge],
                    ],
                  ),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: CitizenUi.textFaint,
                      ),
                    ),
                  ],
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 12,
                    runSpacing: 7,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: meta,
                  ),
                ],
              ),
            ),
          ],
        ),
        if (body != null && body.trim().isNotEmpty) ...[
          SizedBox(height: stack ? 12 : 13),
          Padding(
            // Indented to the title's left edge, so the excerpt reads as part
            // of the row rather than as a caption under the whole card.
            padding: EdgeInsets.only(left: stack ? 0 : 58),
            child: Text(
              body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: CitizenUi.textSecondary,
              ),
            ),
          ),
        ],
        if (footer != null) ...[const SizedBox(height: 14), footer],
      ],
    );
  }

  // ── Web card parts ────────────────────────────────────────────────────────
  //
  // Fixed sizes, not the mobile helpers' `w * 0.0xx`. Those multipliers are
  // read off a width clamped to 480, so on a 880px page every glyph, pill and
  // caption would arrive at phone scale regardless of the room available.

  Widget _webIconChip({String? asset, IconData? icon, required Color color}) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.18),
            color.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: asset != null
          ? Padding(
              padding: const EdgeInsets.all(9),
              child: Image.asset(
                asset,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) =>
                    Icon(Icons.category_rounded, size: 21, color: color),
              ),
            )
          : Icon(icon ?? Icons.business_rounded, size: 21, color: color),
    );
  }

  Widget _webPill({
    IconData? icon,
    Color? dot,
    required String label,
    required Color fg,
    required Color bg,
    required Color border,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot != null) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ] else if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: fg,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _webStatusBadge(
    ({Color bg, Color border, Color dot, Color text, String label}) s,
  ) => _webPill(
    dot: s.dot,
    label: s.label,
    fg: s.text,
    bg: s.bg,
    border: s.border,
  );

  Widget _webRepliedBadge() => _webPill(
    icon: Icons.mark_chat_read_rounded,
    label: 'Replied',
    fg: CitizenUi.success,
    bg: const Color(0xFFECFDF5),
    border: AppColors.green.withValues(alpha: 0.45),
  );

  Widget _webClosedBadge() => _webPill(
    icon: Icons.check_circle_outline_rounded,
    label: 'Closed',
    fg: CitizenUi.textMuted,
    bg: CitizenUi.subtle,
    border: CitizenUi.border,
  );

  Widget _webAnonBadge() => _webPill(
    icon: Icons.person_off_rounded,
    label: 'Anonymous',
    fg: CitizenUi.textMuted,
    bg: CitizenUi.subtle,
    border: CitizenUi.border,
  );

  Widget _webMetaItem(IconData icon, String text, {double? maxWidth}) {
    final label = Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
        color: CitizenUi.textFaint,
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: CitizenUi.textFaint),
        const SizedBox(width: 5),
        maxWidth == null
            ? label
            : ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: label,
              ),
      ],
    );
  }

  Widget _webMetaId(String id) => Text(
    id,
    style: const TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.4,
      color: CitizenUi.textFaint,
    ),
  );

  Widget _webStars(int rating) => Row(
    mainAxisSize: MainAxisSize.min,
    children: List.generate(
      5,
      (i) => Icon(
        i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
        size: 16,
        color: i < rating ? CitizenUi.warn : const Color(0xFFD1D5DB),
      ),
    ),
  );

  Widget _webResponseBlock(
    String response,
    DateTime? reviewedAt, {
    String? responderPhotoUrl,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CitizenUi.accentWash,
        borderRadius: BorderRadius.circular(CitizenUi.controlRadius),
        border: Border.all(color: CitizenUi.accent.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ResponderAvatar(photoUrl: responderPhotoUrl, size: 22),
              const SizedBox(width: 9),
              const Text(
                'LGU Response',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: CitizenUi.accent,
                ),
              ),
              if (reviewedAt != null) ...[
                const Spacer(),
                Text(
                  _fmt(reviewedAt),
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: CitizenUi.textFaint,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 9),
          Text(
            response,
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              color: CitizenUi.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  DETAIL SHEETS
//
//  Tapping a suggestion / feedback card opens a bottom sheet with the full
//  content — untruncated details, location/ratings, all attachments, and the
//  LGU reply (if any). Suggestion media is fetched lazily from suggestion_media;
//  feedback photos come inline on the row.
// ═══════════════════════════════════════════════════════════════════════════

const _kSheetText = Color(0xFF1F2937);
const _kSheetMuted = Color(0xFF6B7280);
const _kSheetHint = Color(0xFF9CA3AF);
const _kSheetBorder = CitizenUi.sharedBorder;

String _sheetDate(DateTime dt) {
  const m = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${m[dt.month - 1]} ${dt.day}, ${dt.year}';
}

// Center + width-cap the sheet on web / tablets / desktop so it doesn't stretch
// edge-to-edge; on phones it fills the width. Shared by both detail sheets.
// Open a detail screen with the app's standard transition: instant enter, a
// fade-out on exit, and the body sliding up under a static header.
void _openSuggestionDetail(BuildContext context, _Suggestion s, String label) {
  Navigator.push(
    context,
    PageRouteBuilder(
      transitionDuration: Duration.zero,
      reverseTransitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, _, _) => _SuggestionDetailScreen(s: s, label: label),
      transitionsBuilder: (_, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
    ),
  );
}

void _openFeedbackDetail(BuildContext context, _Feedback f) {
  Navigator.push(
    context,
    PageRouteBuilder(
      transitionDuration: Duration.zero,
      reverseTransitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, _, _) => _FeedbackDetailScreen(f: f),
      transitionsBuilder: (_, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
    ),
  );
}

/// Formats a timeline event: "Jul 14, 2026 · 5:53 PM" — date AND time, so the
/// citizen can see exactly when each step happened.
String _sheetDateTime(DateTime dt) {
  final d = dt.toLocal();
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  final ampm = d.hour >= 12 ? 'PM' : 'AM';
  return '${_sheetDate(d)} · $h:$m $ampm';
}

/// Shared detail-screen chrome, mirroring ReportDetailScreen: a collapsing blue
/// SliverAppBar carrying the short id, then centred content (max 760) whose
/// sections stagger in with a fade + slide. Sized off a clamped width so it
/// reads the same on phone, tablet and web. No bottom bar / chat agent.
/// The measure both halves of a detail screen sit in.
///
/// It was already the body's cap, written inline as a bare 760; the hero now
/// has to agree with it, so it gets a name.
const double _kDetailMeasure = 760;

class _DetailScaffold extends StatefulWidget {
  /// Small kicker above the title, e.g. 'Suggestion details'.
  final String kicker;

  /// The big header line — the category / office this submission is about.
  final String heroTitle;

  /// Status + anonymity pills, rendered under the title on the blue.
  final List<Widget> pills;
  final String shortId; // e.g. 'SGS-1A2B3C4D'
  final List<Widget> sections;
  const _DetailScaffold({
    required this.kicker,
    required this.heroTitle,
    this.pills = const [],
    required this.shortId,
    required this.sections,
  });

  @override
  State<_DetailScaffold> createState() => _DetailScaffoldState();
}

class _DetailScaffoldState extends State<_DetailScaffold>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryCtrl;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _entryCtrl.forward();
    });
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    super.dispose();
  }

  /// Staggered fade + slide per section — same feel as ReportDetailScreen.
  Widget _fadeSlide(int i, Widget child) {
    final start = (i * 0.10).clamp(0.0, 0.85);
    final end = (start + 0.45).clamp(0.0, 1.0);
    final curve = CurvedAnimation(
      parent: _entryCtrl,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.12),
          end: Offset.zero,
        ).animate(curve),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final w = uiScaleWidthOf(mq.size);
    // There's no bottom bar here, so the last card would otherwise sit under the
    // system navigation. Add the real inset — that's 0 on gesture nav and the
    // bar height on 3-button nav — plus breathing room.
    final bottomInset = mq.padding.bottom;
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── No blue band on web ─────────────────────────────────────────
          //
          // On the phone the hero IS the screen's top: it fills the notch area,
          // carries the back gesture's target and gives a pushed screen its
          // own identity. In a desktop pane none of that holds. It became a
          // 200px slab of saturated colour sitting directly under a top nav
          // that is already blue, and the page under it is white cards on grey
          // — so the band read as chrome that had wandered into the content,
          // not as the header of the thing you opened.
          //
          // The same four facts — where you came from, what kind of record
          // this is, its name, its state — are what [AccountPageTitle] carries
          // on every other page in this section.
          if (kIsWeb)
            SliverToBoxAdapter(child: _webHeader(w))
          else
            _sliverAppBar(w),
          SliverToBoxAdapter(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _kDetailMeasure),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    w * .04,
                    w * .04,
                    w * .04,
                    w * .10 + bottomInset,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < widget.sections.length; i++) ...[
                        if (i > 0) SizedBox(height: w * .04),
                        _fadeSlide(i, widget.sections[i]),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The web header: chevron, name, kind and id, then the state pills.
  ///
  /// Built inside the SAME 760 box the sections below use, rather than through
  /// [AccountPageBody], because this screen's body already owns that measure
  /// and its own padding. Two different measures on one page is exactly the
  /// misalignment the blue band had.
  Widget _webHeader(double w) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _kDetailMeasure),
        child: Padding(
          padding: EdgeInsets.fromLTRB(w * .04, 24, w * .04, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AccountPageTitle(
                title: widget.heroTitle,
                subtitle: '${widget.kicker} · ${widget.shortId}',
                onBack: () => Navigator.pop(context),
                backLabel: 'Back to My Submissions',
              ),
              if (widget.pills.isNotEmpty)
                Padding(
                  // Indented to the title's left edge, past the chevron, so
                  // the header reads as one block rather than as a heading
                  // with a stray row of pills beneath it.
                  padding: const EdgeInsets.only(
                    left: kAccountBackChevron + kAccountBackChevronGap,
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: widget.pills,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Mirrors ReportDetailScreen's hero: gradient + soft circles, with the kicker,
  /// the category/office title and the status pills pinned to the bottom — so it
  /// stays aligned whether expanded or collapsed.
  Widget _sliverAppBar(double w) {
    return SliverAppBar(
      expandedHeight: w * 0.44,
      pinned: true,
      stretch: true,
      elevation: 0,
      backgroundColor: const Color(0xFF0D47A1),
      leading: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Container(
            width: w * 0.09,
            height: w * 0.09,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(w * 0.025),
            ),
            child: Icon(
              Icons.arrow_back_ios_new_rounded,
              size: w * 0.045,
              color: Colors.white,
            ),
          ),
        ),
      ),
      actions: [
        Container(
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            widget.shortId,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(width: 4),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF1565C0),
                    Color(0xFF0D47A1),
                    Color(0xFF0A3070),
                  ],
                ),
              ),
            ),
            // Decorative circles — same soft accents as the report hero.
            Positioned(
              top: -20,
              right: -30,
              child: Container(
                width: w * 0.45,
                height: w * 0.45,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.04),
                ),
              ),
            ),
            Positioned(
              bottom: 20,
              left: -20,
              child: Container(
                width: w * 0.30,
                height: w * 0.30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.04),
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  w * .04,
                  w * .08,
                  w * .04,
                  w * .05,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.kicker,
                      style: TextStyle(
                        fontSize: w * .032,
                        color: Colors.white.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: w * .01),
                    Text(
                      widget.heroTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: w * .054,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.3,
                        height: 1.2,
                      ),
                    ),
                    if (widget.pills.isNotEmpty) ...[
                      SizedBox(height: w * .025),
                      Wrap(
                        spacing: w * .025,
                        runSpacing: w * .015,
                        children: widget.pills,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Translucent pill sitting on the blue hero — status / anonymity.
///
/// On web the blue hero is gone (see [_DetailScaffoldState._buildWeb]), so a
/// white-on-white pill would be invisible. The web pill keeps the mobile one's
/// uniform treatment — every pill the same weight, whatever it says — just
/// inverted onto the light card it now sits on.
/// One detail-view measurement, in whichever system is in play.
///
/// The detail screens size everything off `w`, a width clamped to 480. In the
/// app that is right — it IS roughly the screen. In a browser it is a constant:
/// the clamp pins it at 480 however much room there is, so every glyph, gap and
/// caption arrives at phone scale inside an 880px card, next to kit type set at
/// 13.5. This picks the kit's fixed value there instead.
///
/// `kIsWeb` is a compile-time constant, so the app still computes exactly
/// `w * factor` and the mobile detail screens are unchanged.
double _dm(double w, double factor, double web) => kIsWeb ? web : w * factor;

/// On web there is no blue band for a white pill to sit on, so it inverts.
/// Keeps the mobile treatment's one rule — every pill the same weight,
/// whatever it says — just onto a light ground.
Widget _heroPill(double w, IconData icon, String label) => kIsWeb
    ? Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: CitizenUi.subtle,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: CitizenUi.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: CitizenUi.textMuted),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: CitizenUi.textMuted,
              ),
            ),
          ],
        ),
      )
    : Container(
        padding: EdgeInsets.symmetric(horizontal: w * .028, vertical: w * .014),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(w * .05),
          border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: w * .032, color: Colors.white),
            SizedBox(width: w * .015),
            Text(
              label,
              style: TextStyle(
                fontSize: w * .028,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      );

/// Blue section label above each card — mirrors ReportDetailScreen.
///
/// Grey small-caps on web, for the reason [AccountSectionLabel] documents: a
/// label names the group below it and should not outweigh it. These two
/// functions and [_heroPill] are the only presentation the detail sections
/// share, so branching them converts every section of both detail screens
/// without touching the sections themselves.
Widget _sectionLabel(double w, String label) => kIsWeb
    ? AccountSectionLabel(label)
    : Text(
        label,
        style: TextStyle(
          fontSize: w * .036,
          fontWeight: FontWeight.w700,
          color: AppColors.primaryBlue,
          letterSpacing: 0.2,
        ),
      );

/// The white rounded card every detail section sits in.
Widget _detailCard(double w, {required Widget child}) => kIsWeb
    ? AccountCard(child: child)
    : Container(
        width: double.infinity,
        padding: EdgeInsets.all(w * .04),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(w * .04),
          border: Border.all(color: CitizenUi.sharedBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: child,
      );

/// One real event on the submission timeline.
class _TimelineEvent {
  final IconData icon;
  final String label;

  /// null → the step hasn't happened yet (renders greyed, "Pending").
  final DateTime? at;
  final Color color;
  const _TimelineEvent({
    required this.icon,
    required this.label,
    required this.at,
    required this.color,
  });

  bool get done => at != null;
}

/// Vertical timeline of the submission's real events, each stamped with its
/// actual date AND time — mirrors the report's "Processing timeline".
class _TimelineCard extends StatelessWidget {
  final double w;
  final List<_TimelineEvent> events;
  const _TimelineCard({required this.w, required this.events});

  @override
  Widget build(BuildContext context) {
    return _detailCard(
      w,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < events.length; i++)
            _step(events[i], last: i == events.length - 1),
        ],
      ),
    );
  }

  Widget _step(_TimelineEvent e, {required bool last}) {
    final tint = e.done ? e.color : const Color(0xFFD1D5DB);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: _dm(w, .075, 34),
                height: _dm(w, .075, 34),
                decoration: BoxDecoration(
                  color: e.done
                      ? e.color.withValues(alpha: 0.12)
                      : const Color(0xFFF3F4F6),
                  shape: BoxShape.circle,
                  border: Border.all(color: tint, width: 1.5),
                ),
                child: Icon(e.icon, size: _dm(w, .038, 16), color: tint),
              ),
              if (!last)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: EdgeInsets.symmetric(vertical: _dm(w, .008, 4)),
                    color: const Color(0xFFE5E7EB),
                  ),
                ),
            ],
          ),
          SizedBox(width: _dm(w, .03, 14)),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : _dm(w, .045, 20)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.label,
                    style: TextStyle(
                      fontSize: _dm(w, .033, 14),
                      fontWeight: FontWeight.w700,
                      color: e.done
                          ? const Color(0xFF1F2937)
                          : const Color(0xFF9CA3AF),
                    ),
                  ),
                  SizedBox(height: _dm(w, .006, 3)),
                  Text(
                    e.at == null ? 'Pending' : _sheetDateTime(e.at!),
                    style: TextStyle(
                      fontSize: _dm(w, .028, 12.5),
                      color: const Color(0xFF9CA3AF),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Responsive shimmer placeholder for the attachments grid while media loads.
class _MediaSkeleton extends StatefulWidget {
  const _MediaSkeleton();

  @override
  State<_MediaSkeleton> createState() => _MediaSkeletonState();
}

class _MediaSkeletonState extends State<_MediaSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Fixed 88px tiles that wrap — they match the real thumbnails and reflow to
    // fit any width (phone, tablet, web).
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Opacity(
        opacity: 0.45 + 0.4 * _c.value,
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var i = 0; i < 3; i++)
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: const Color(0xFFE7EBF1),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Neutral "closed" banner for a spam-dismissed submission — no reason shown.
Widget _sheetClosedBanner() => Container(
  width: double.infinity,
  padding: const EdgeInsets.all(12),
  decoration: BoxDecoration(
    color: const Color(0xFFF3F4F6),
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: CitizenUi.sharedBorder),
  ),
  child: const Row(
    children: [
      Icon(Icons.check_circle_outline_rounded, size: 18, color: _kSheetMuted),
      SizedBox(width: 8),
      Expanded(
        child: Text(
          'This submission has been closed by the LGU.',
          style: TextStyle(fontSize: 12.5, height: 1.4, color: _kSheetMuted),
        ),
      ),
    ],
  ),
);

Widget _sheetSectionTitle(String text) => Padding(
  padding: const EdgeInsets.only(bottom: 8),
  child: Text(
    text,
    style: const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.5,
      color: _kSheetHint,
    ),
  ),
);

/// The responding admin's avatar, shown beside "LGU Response". When no photo is
/// available (older replies, or before submission_responder_avatar.sql is
/// applied) it renders NOTHING rather than a stand-in icon — the label stands on
/// its own. Carries its own trailing gap so the row collapses cleanly.
class _ResponderAvatar extends StatelessWidget {
  final String? photoUrl;
  final double size;
  const _ResponderAvatar({required this.photoUrl, this.size = 20});

  @override
  Widget build(BuildContext context) {
    final url = photoUrl;
    if (url == null || url.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ClipOval(
        child: SizedBox.square(
          dimension: size,
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            errorWidget: (_, _, _) => const SizedBox.shrink(),
            placeholder: (_, _) => Container(color: const Color(0xFFE7EBF1)),
          ),
        ),
      ),
    );
  }
}

/// The LGU reply block, reused inside both detail screens.
class _SheetReplyBlock extends StatelessWidget {
  final String response;
  final DateTime? reviewedAt;
  final String? responderPhotoUrl;
  const _SheetReplyBlock({
    required this.response,
    this.reviewedAt,
    this.responderPhotoUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBAE6FD)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ResponderAvatar(photoUrl: responderPhotoUrl, size: 22),
              const SizedBox(width: 8),
              const Text(
                'LGU Response',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryBlue,
                ),
              ),
              if (reviewedAt != null) ...[
                const Spacer(),
                Text(
                  _sheetDate(reviewedAt!),
                  style: const TextStyle(fontSize: 11.5, color: _kSheetHint),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            response,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: _kSheetText,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Suggestion detail screen (fetches its media, shows a skeleton) ───────────
class _SuggestionDetailScreen extends StatefulWidget {
  final _Suggestion s;

  /// Human-readable category label shown as the hero title.
  final String label;
  const _SuggestionDetailScreen({required this.s, required this.label});

  @override
  State<_SuggestionDetailScreen> createState() =>
      _SuggestionDetailScreenState();
}

class _SuggestionDetailScreenState extends State<_SuggestionDetailScreen> {
  late final Future<List<_SheetMedia>> _media;

  @override
  void initState() {
    super.initState();
    _media = _fetchMedia();
  }

  /// `suggestion-media` is a PRIVATE bucket, so a public URL 403s and the
  /// thumbnail renders broken. Sign each path (1h) like the report detail does,
  /// falling back to the public URL in case the bucket is ever made public.
  Future<List<_SheetMedia>> _fetchMedia() async {
    final db = Supabase.instance.client;
    try {
      final rows = await db
          .from('suggestion_media')
          .select('storage_path, mime_type')
          .eq('suggestion_id', widget.s.id)
          .order('display_order', ascending: true);

      final futures = (rows as List).map<Future<_SheetMedia?>>((r) async {
        final path = r['storage_path'] as String;
        final isVideo = ((r['mime_type'] as String?) ?? '')
            .toLowerCase()
            .startsWith('video/');
        try {
          final url = await db.storage
              .from('suggestion-media')
              .createSignedUrl(path, 3600);
          return _SheetMedia(url: url, isVideo: isVideo);
        } catch (_) {
          try {
            final url = db.storage.from('suggestion-media').getPublicUrl(path);
            return _SheetMedia(url: url, isVideo: isVideo);
          } catch (_) {
            return null;
          }
        }
      });

      final results = await Future.wait(futures, eagerError: false);
      return results.whereType<_SheetMedia>().toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final w = uiScaleWidth(context);
    final hasLocation =
        (s.barangay != null && s.barangay!.isNotEmpty) ||
        (s.address != null && s.address!.isNotEmpty) ||
        (s.latitude != null && s.longitude != null);

    return _DetailScaffold(
      kicker: 'Suggestion details',
      heroTitle: widget.label.replaceAll('\n', ' '),
      shortId: 'SGS-${s.id.substring(0, 8).toUpperCase()}',
      pills: [
        if (s.hasReply)
          _heroPill(w, Icons.mark_chat_read_rounded, 'Replied')
        else if (s.isClosed)
          _heroPill(w, Icons.check_circle_outline_rounded, 'Closed')
        else
          _heroPill(w, Icons.schedule_rounded, 'No reply yet'),
        if (s.isAnonymous)
          _heroPill(w, Icons.lock_outline_rounded, 'Anonymous'),
      ],
      sections: [
        // ── Timeline of real events ──
        _sectionLabel(w, 'Status timeline'),
        _TimelineCard(
          w: w,
          events: [
            _TimelineEvent(
              icon: Icons.edit_note_rounded,
              label: 'Suggestion submitted',
              at: s.createdAt,
              color: AppColors.primaryBlue,
            ),
            if (s.isClosed)
              _TimelineEvent(
                icon: Icons.check_circle_outline_rounded,
                label: 'Closed by the LGU',
                at: s.dismissedAt,
                color: const Color(0xFF6B7280),
              )
            else
              _TimelineEvent(
                icon: Icons.mark_chat_read_rounded,
                label: s.hasReply ? 'LGU responded' : 'No reply yet',
                at: s.hasReply ? s.reviewedAt : null,
                color: AppColors.green,
              ),
          ],
        ),

        // ── Details ──
        _sectionLabel(w, 'Suggestion details'),
        _detailCard(
          w,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sheetSectionTitle('DETAILS'),
              Text(
                (s.details == null || s.details!.trim().isEmpty)
                    ? '—'
                    : s.details!,
                style: TextStyle(
                  fontSize: _dm(w, .033, 13.5),
                  height: 1.55,
                  color: _kSheetText,
                ),
              ),
              if (hasLocation) ...[
                SizedBox(height: _dm(w, .045, 20)),
                _sheetSectionTitle('LOCATION'),
                _SheetLocation(
                  barangay: s.barangay,
                  address: s.address,
                  latitude: s.latitude,
                  longitude: s.longitude,
                ),
              ],
              SizedBox(height: _dm(w, .045, 20)),
              _sheetSectionTitle('ATTACHMENTS'),
              FutureBuilder<List<_SheetMedia>>(
                future: _media,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const _MediaSkeleton();
                  }
                  final media = snap.data ?? const <_SheetMedia>[];
                  if (media.isEmpty) {
                    return const Text(
                      'No attachments.',
                      style: TextStyle(fontSize: 13, color: _kSheetHint),
                    );
                  }
                  return _MediaStrip(media: media);
                },
              ),
            ],
          ),
        ),

        // ── LGU reply ──
        if (s.hasReply) ...[
          _sectionLabel(w, 'LGU response'),
          _SheetReplyBlock(
            response: s.adminResponse!,
            reviewedAt: s.reviewedAt,
            responderPhotoUrl: s.responderPhotoUrl,
          ),
        ],
        if (s.isClosed) _sheetClosedBanner(),
      ],
    );
  }
}

// ── Feedback detail screen ───────────────────────────────────────────────────
class _FeedbackDetailScreen extends StatelessWidget {
  final _Feedback f;
  const _FeedbackDetailScreen({required this.f});

  static const _ratingLabels = [
    '',
    'Very Poor',
    'Poor',
    'Okay',
    'Good',
    'Excellent',
  ];

  @override
  Widget build(BuildContext context) {
    final w = uiScaleWidth(context);
    final aspects = <MapEntry<String, int>>[
      if (f.aspectStaff != null) MapEntry('Staff attitude', f.aspectStaff!),
      if (f.aspectWait != null) MapEntry('Wait time', f.aspectWait!),
      if (f.aspectClarity != null)
        MapEntry('Process clarity', f.aspectClarity!),
      if (f.aspectFacility != null) MapEntry('Facility', f.aspectFacility!),
    ];
    final media = [
      for (final u in f.photoUrls) _SheetMedia(url: u, isVideo: false),
    ];

    return _DetailScaffold(
      kicker: 'Feedback details',
      heroTitle: f.officeLabel.replaceAll('\n', ' '),
      shortId: 'FBK-${f.id.substring(0, 8).toUpperCase()}',
      pills: [
        if (f.hasReply)
          _heroPill(w, Icons.mark_chat_read_rounded, 'Replied')
        else if (f.isClosed)
          _heroPill(w, Icons.check_circle_outline_rounded, 'Closed')
        else
          _heroPill(w, Icons.schedule_rounded, 'No reply yet'),
        if (f.isAnonymous)
          _heroPill(w, Icons.lock_outline_rounded, 'Anonymous'),
      ],
      sections: [
        // ── Timeline of real events ──
        _sectionLabel(w, 'Status timeline'),
        _TimelineCard(
          w: w,
          events: [
            _TimelineEvent(
              icon: Icons.rate_review_rounded,
              label: 'Feedback submitted',
              at: f.createdAt,
              color: AppColors.primaryBlue,
            ),
            if (f.isClosed)
              _TimelineEvent(
                icon: Icons.check_circle_outline_rounded,
                label: 'Closed by the LGU',
                at: f.dismissedAt,
                color: const Color(0xFF6B7280),
              )
            else
              _TimelineEvent(
                icon: Icons.mark_chat_read_rounded,
                label: f.hasReply ? 'LGU responded' : 'No reply yet',
                at: f.hasReply ? f.reviewedAt : null,
                color: AppColors.green,
              ),
          ],
        ),

        // ── Ratings ──
        _sectionLabel(w, 'Your rating'),
        _detailCard(
          w,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sheetSectionTitle('SERVICE'),
              Text(
                f.serviceName.isEmpty ? '—' : f.serviceName,
                style: TextStyle(
                  fontSize: _dm(w, .033, 13.5),
                  height: 1.4,
                  color: _kSheetText,
                ),
              ),
              SizedBox(height: _dm(w, .045, 20)),
              _sheetSectionTitle('OVERALL RATING'),
              Row(
                children: [
                  _SheetStars(rating: f.rating, size: _dm(w, .05, 20)),
                  SizedBox(width: _dm(w, .025, 10)),
                  Text(
                    _ratingLabels[f.rating.clamp(0, 5)],
                    style: TextStyle(
                      fontSize: _dm(w, .032, 13),
                      fontWeight: FontWeight.w600,
                      color: _kSheetMuted,
                    ),
                  ),
                ],
              ),
              if (aspects.isNotEmpty) ...[
                SizedBox(height: _dm(w, .045, 20)),
                _sheetSectionTitle('ASPECT RATINGS'),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(_dm(w, .03, 10)),
                    border: Border.all(color: _kSheetBorder),
                  ),
                  padding: EdgeInsets.all(_dm(w, .01, 4)),
                  child: Column(
                    children: [
                      for (final a in aspects)
                        Padding(
                          padding: EdgeInsets.all(_dm(w, .02, 8)),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  a.key,
                                  style: TextStyle(
                                    fontSize: _dm(w, .031, 13),
                                    color: _kSheetMuted,
                                  ),
                                ),
                              ),
                              _SheetStars(
                                rating: a.value,
                                size: _dm(w, .036, 15),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),

        // ── Comment + photos ──
        _sectionLabel(w, 'What you told us'),
        _detailCard(
          w,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sheetSectionTitle('COMMENT'),
              Text(
                (f.comment == null || f.comment!.trim().isEmpty)
                    ? 'No comment provided.'
                    : f.comment!,
                style: TextStyle(
                  fontSize: _dm(w, .033, 13.5),
                  height: 1.5,
                  color: (f.comment == null || f.comment!.trim().isEmpty)
                      ? _kSheetHint
                      : _kSheetText,
                ),
              ),
              SizedBox(height: _dm(w, .045, 20)),
              _sheetSectionTitle('PHOTOS'),
              if (media.isEmpty)
                const Text(
                  'No photos attached.',
                  style: TextStyle(fontSize: 13, color: _kSheetHint),
                )
              else
                _MediaStrip(media: media),
            ],
          ),
        ),

        // ── LGU reply ──
        if (f.hasReply) ...[
          _sectionLabel(w, 'LGU response'),
          _SheetReplyBlock(
            response: f.adminResponse!,
            reviewedAt: f.reviewedAt,
            responderPhotoUrl: f.responderPhotoUrl,
          ),
        ],
        if (f.isClosed) _sheetClosedBanner(),
      ],
    );
  }
}

class _SheetStars extends StatelessWidget {
  final int rating;
  final double size;
  const _SheetStars({required this.rating, this.size = 16});

  @override
  Widget build(BuildContext context) {
    final c = rating <= 1
        ? AppColors.red
        : rating == 2
        ? AppColors.orange
        : const Color(0xFFF59E0B);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            i <= rating ? Icons.star_rounded : Icons.star_outline_rounded,
            size: size,
            color: i <= rating ? c : const Color(0xFFD1D5DB),
          ),
      ],
    );
  }
}

class _SheetLocation extends StatelessWidget {
  final String? barangay;
  final String? address;
  final double? latitude;
  final double? longitude;
  const _SheetLocation({
    this.barangay,
    this.address,
    this.latitude,
    this.longitude,
  });

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    void add(IconData icon, String value) => rows.add(
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: AppColors.primaryBlue),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(fontSize: 13, color: _kSheetText),
              ),
            ),
          ],
        ),
      ),
    );
    if (barangay != null && barangay!.isNotEmpty) {
      add(Icons.location_city_rounded, barangay!);
    }
    if (address != null && address!.isNotEmpty) {
      add(Icons.signpost_rounded, address!);
    }
    if (latitude != null && longitude != null) {
      add(
        Icons.my_location_rounded,
        '${latitude!.toStringAsFixed(6)}, ${longitude!.toStringAsFixed(6)}',
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kSheetBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows,
      ),
    );
  }
}

// ── Media strip + viewers ────────────────────────────────────────────────────
class _SheetMedia {
  final String url;
  final bool isVideo;
  const _SheetMedia({required this.url, required this.isVideo});
}

class _MediaStrip extends StatelessWidget {
  final List<_SheetMedia> media;
  const _MediaStrip({required this.media});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final m in media)
          GestureDetector(
            onTap: () => showAppDialog(
              context: context,
              barrierColor: Colors.black87,
              builder: (_) => m.isVideo
                  ? _SheetVideoDialog(url: m.url)
                  : _SheetImageDialog(url: m.url),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 88,
                height: 88,
                color: const Color(0xFFF3F4F6),
                child: m.isVideo
                    ? const Stack(
                        fit: StackFit.expand,
                        children: [
                          ColoredBox(color: Color(0xFF1F2937)),
                          Center(
                            child: Icon(
                              Icons.play_circle_fill_rounded,
                              color: Colors.white70,
                              size: 32,
                            ),
                          ),
                        ],
                      )
                    : Image.network(
                        m.url,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.broken_image_rounded,
                          color: _kSheetHint,
                        ),
                      ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SheetImageDialog extends StatelessWidget {
  final String url;
  const _SheetImageDialog({required this.url});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              child: Image.network(url, fit: BoxFit.contain),
            ),
          ),
          Positioned(
            top: 40,
            right: 16,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetVideoDialog extends StatefulWidget {
  final String url;
  const _SheetVideoDialog({required this.url});

  @override
  State<_SheetVideoDialog> createState() => _SheetVideoDialogState();
}

class _SheetVideoDialogState extends State<_SheetVideoDialog> {
  late final VideoPlayerController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller
        .initialize()
        .then((_) {
          if (!mounted) return;
          setState(() => _ready = true);
          _controller.play();
        })
        .catchError((Object e) {
          debugPrint('Sheet video init error: $e');
          return null;
        });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        children: [
          Center(
            child: _ready
                ? AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: VideoPlayer(_controller),
                  )
                : const CircularProgressIndicator(color: Colors.white),
          ),
          if (_ready)
            Center(
              child: GestureDetector(
                onTap: () => setState(() {
                  _controller.value.isPlaying
                      ? _controller.pause()
                      : _controller.play();
                }),
                child: Container(
                  color: Colors.transparent,
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
            ),
          Positioned(
            top: 40,
            right: 16,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
