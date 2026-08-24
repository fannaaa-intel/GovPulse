import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/resolution_media.dart';
import '../my_report/my_reports_screen.dart';
import '../Quick-action/Report/location_picker_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/services/chat_service.dart';
import '../Quick-action/Chat-with-Agent/chat_agent_screen.dart';
import '../../../core/theme/citizen_ui.dart';
import '../../../core/widgets/Home/Account/account_web_kit.dart';
import '../../../core/theme/mobile_metrics.dart';
// ─── Timeline step model ──────────────────────────────────────────────────────

enum TimelineStepStatus { completed, active, pending }

/// The content band this page lays out inside, and the gutter it keeps either
/// side of it.
///
/// ── Why the web number is the ACCOUNT kit's ───────────────────────────────
/// A record detail is opened from a list, and until now it was measured
/// differently from every list that opens it: My Reports gave its cards a 1112
/// content column and My Submissions gave its rows 816, and then both landed
/// here on 722. Tapping a card visibly shrank the page around the record you
/// had just asked to see.
///
/// [kAccountMaxWidth] less two [kAccountPageGutter]s is 816, which is what My
/// Submissions already used and what My Reports now uses too, so the three
/// pages share one measure and the transition between them moves nothing.
///
/// The APP keeps the 760 it has always had — `kIsWeb` is a compile-time
/// constant, so this resolves at build time and the phone layout is byte for
/// byte what it was.
const double _kBand = kIsWeb ? kAccountMaxWidth : 760;

/// Page gutter. Web takes the shared [kAccountPageGutter]; the app keeps its
/// viewport-proportional one.
double _gutter(double w) => kIsWeb ? kAccountPageGutter : w * .04;

class _TimelineStep {
  final String title;
  final String subtitle;
  final String? date;
  final TimelineStepStatus status;
  final IconData icon;

  const _TimelineStep({
    required this.title,
    required this.subtitle,
    this.date,
    required this.status,
    required this.icon,
  });
}

// ─── Report detail screen ─────────────────────────────────────────────────────

class ReportDetailScreen extends StatefulWidget {
  final ReportItem report;
  final String username;

  const ReportDetailScreen({
    super.key,
    required this.report,
    required this.username,
  });

  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entryCtrl;
  late final ChatService _chatService;
  late final AnimationController _timelineCtrl;
  late final AnimationController _shimmerCtrl;

  final List<({String url, String path})> _mediaItems = [];
  bool _mediaLoading = true;

  /// Live copy of the report — starts from the pushed-in value and is refreshed
  /// in place whenever the admin/staff move it (status, endorsement, note).
  late ReportItem _report;
  RealtimeChannel? _reportChannel;

  // ── Derived helpers ──────────────────────────────────────────────────────────

  bool get _isResolved => _report.status == ReportStatus.resolved;
  bool get _isRejected => _report.status == ReportStatus.rejected;
  bool get _isPending => _report.status == ReportStatus.pending;
  bool get _isUnderReview => _report.status == ReportStatus.underReview;
  bool get _isInProgress => _report.status == ReportStatus.inProgress;
  bool _openingChat = false;

  // Whether the report was actually endorsed to an external entity by an admin
  // (out-of-LGU scope). Driven by real data (endorsed_to_department), never
  // guessed from the category.
  bool get _isEndorsed =>
      (_report.endorsedToDepartment != null &&
      _report.endorsedToDepartment!.trim().isNotEmpty);

  String get _forwardedDepartment =>
      _report.endorsedToDepartment?.trim().isNotEmpty == true
      ? _report.endorsedToDepartment!.trim()
      : 'External entity';

  String _departmentFromCategory(String category) {
    switch (category.toLowerCase()) {
      case 'road & infrastructure':
        return 'Engineering Office';
      case 'waste & garbage':
        return 'Sanitation Office';
      case 'drainage & flooding':
        return 'Engineering Office';
      case 'streetlight outage':
        return 'Engineering Office';
      case 'environment & pollution':
        return 'Environment Office';
      default:
        return "Mayor's Office";
    }
  }

  Color get _statusColor {
    switch (_report.status) {
      case ReportStatus.resolved:
        return AppColors.green;
      case ReportStatus.rejected:
        return AppColors.red;
      case ReportStatus.underReview:
        return const Color(0xFF6366F1);
      case ReportStatus.inProgress:
        return const Color(0xFF2563EB);
      default:
        return AppColors.orange;
    }
  }

  String get _statusLabel {
    switch (_report.status) {
      case ReportStatus.resolved:
        return 'Resolved';
      case ReportStatus.rejected:
        return 'Rejected';
      case ReportStatus.underReview:
        return 'Under Review';
      case ReportStatus.inProgress:
        return 'In Progress';
      default:
        return 'Pending';
    }
  }

  IconData get _statusIcon {
    switch (_report.status) {
      case ReportStatus.resolved:
        return Icons.check_circle_rounded;
      case ReportStatus.rejected:
        return Icons.cancel_rounded;
      case ReportStatus.underReview:
        return Icons.manage_search_rounded;
      case ReportStatus.inProgress:
        return Icons.construction_rounded;
      default:
        return Icons.access_time_rounded;
    }
  }

  // ── Timeline steps ───────────────────────────────────────────────────────────

  // Progress rank of the current status along the normal happy path.
  // (rejected is handled as a separate branch below.)
  int get _statusRank {
    switch (_report.status) {
      case ReportStatus.pending:
        return 0;
      case ReportStatus.underReview:
        return 1;
      case ReportStatus.inProgress:
        return 2;
      case ReportStatus.resolved:
        return 3;
      case ReportStatus.rejected:
        return 0;
    }
  }

  List<_TimelineStep> get _timelineSteps {
    final steps = <_TimelineStep>[];
    final date = _formatDateTime(_report.dateReported);

    // Step 1 — always completed
    steps.add(
      _TimelineStep(
        title: 'Report submitted',
        subtitle: 'Your report has been received and logged.',
        date: date,
        status: TimelineStepStatus.completed,
        icon: Icons.assignment_turned_in_rounded,
      ),
    );

    // ── Rejected branch: submitted → reviewed → closed ──
    if (_isRejected) {
      steps.add(
        _TimelineStep(
          title: 'Initial review',
          subtitle: 'Your report was assessed by our team.',
          status: TimelineStepStatus.completed,
          icon: Icons.manage_search_rounded,
        ),
      );
      steps.add(
        _TimelineStep(
          title: 'Report closed',
          subtitle: _report.rejectionNote?.trim().isNotEmpty == true
              ? _report.rejectionNote!.trim()
              : 'This report could not be actioned. Please contact our office for more information.',
          status: TimelineStepStatus.completed,
          icon: Icons.cancel_rounded,
        ),
      );
      return steps;
    }

    // Step 2 — Initial review (rank 1)
    steps.add(
      _TimelineStep(
        title: 'Initial review',
        subtitle: _statusRank >= 1
            ? 'Your report has been assessed by our team.'
            : 'Our team is reviewing your report.',
        status: _statusRank >= 1
            ? TimelineStepStatus.completed
            : TimelineStepStatus.active,
        icon: Icons.manage_search_rounded,
      ),
    );

    // Step 3 — Endorsed to an external entity (REAL data, only when endorsed).
    if (_isEndorsed) {
      steps.add(
        _TimelineStep(
          title: 'Endorsed to $_forwardedDepartment',
          subtitle:
              'This concern is outside the LGU\'s direct scope. It has been '
              'endorsed to $_forwardedDepartment, who are now handling it.',
          date: _report.endorsedAt != null
              ? _formatDateTime(_report.endorsedAt!)
              : null,
          status: _isResolved
              ? TimelineStepStatus.completed
              : TimelineStepStatus.active,
          icon: Icons.forward_to_inbox_rounded,
        ),
      );
    }

    // Step 4 — In progress (rank 2)
    steps.add(
      _TimelineStep(
        title: 'In progress',
        subtitle: _isEndorsed
            ? '$_forwardedDepartment is actively working on this report.'
            : 'The assigned team is actively working on this report.',
        status: _statusRank >= 3
            ? TimelineStepStatus.completed
            : _statusRank == 2
            ? TimelineStepStatus.active
            : TimelineStepStatus.pending,
        icon: Icons.construction_rounded,
      ),
    );

    // Step 5 — Verification (only once resolved)
    if (_isResolved) {
      steps.add(
        _TimelineStep(
          title: 'Verification',
          subtitle: 'The completed work has been verified by our team.',
          status: TimelineStepStatus.completed,
          icon: Icons.verified_rounded,
        ),
      );
    }

    // Step 6 — Resolved
    steps.add(
      _TimelineStep(
        title: 'Resolved',
        subtitle: _isResolved
            ? 'Your report has been resolved. Thank you for helping improve our community!'
            : 'Final outcome pending.',
        status: _isResolved
            ? TimelineStepStatus.completed
            : TimelineStepStatus.pending,
        icon: Icons.check_circle_rounded,
      ),
    );

    return steps;
  }

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _report = widget.report;
    _subscribeReport();

    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _timelineCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 100)); // ← add this
      if (!mounted) return;
      _entryCtrl.forward();
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) _timelineCtrl.forward();
    });

    _loadMediaUrls();
    _chatService = ChatService.forReport('RPT-${_report.id}');
  }

  /// Live-refresh the report row so the timeline reflects admin/staff moves
  /// (status, endorsement, rejection note) the moment they happen.
  void _subscribeReport() {
    final supabase = Supabase.instance.client;
    _reportChannel = supabase
        .channel('report:${_report.fullId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'reports',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: _report.fullId,
          ),
          callback: (_) => _refreshReport(),
        )
        .subscribe();
  }

  Future<void> _refreshReport() async {
    try {
      final row = await Supabase.instance.client
          .from('reports')
          .select('*, report_media(id)')
          .eq('id', _report.fullId)
          .single();
      if (!mounted) return;
      setState(() => _report = ReportItem.fromMap(row));
      // Replay the timeline animation so the newly-reached step animates in.
      _timelineCtrl
        ..reset()
        ..forward();
    } catch (_) {
      // Transient — the next event or a manual reopen will refresh.
    }
  }

  @override
  void dispose() {
    if (_reportChannel != null) {
      Supabase.instance.client.removeChannel(_reportChannel!);
    }
    _entryCtrl.dispose();
    _timelineCtrl.dispose();
    _shimmerCtrl.dispose();
    _chatService.onChatClosed();
    _chatService.dispose();
    super.dispose();
  }

  // ── Media loading ────────────────────────────────────────────────────────────
  Future<void> _loadMediaUrls() async {
    try {
      final supabase = Supabase.instance.client;

      final rows = await supabase
          .from('report_media')
          .select('storage_path, mime_type, display_order')
          .eq('report_id', _report.fullId)
          .order('display_order', ascending: true);

      final futures = rows.map<Future<({String url, String path})?>>((
        row,
      ) async {
        final path = row['storage_path'] as String;
        try {
          final url = await supabase.storage
              .from('report-media')
              .createSignedUrl(path, 3600);
          return (url: url, path: path);
        } catch (_) {
          try {
            final url = supabase.storage
                .from('report-media')
                .getPublicUrl(path);
            return (url: url, path: path);
          } catch (_) {
            return null;
          }
        }
      });

      final results = await Future.wait(futures, eagerError: false);

      if (mounted) {
        setState(() {
          _mediaItems.addAll(results.whereType<({String url, String path})>());
          _mediaLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _mediaLoading = false);
    }
  }

  // ── Animation helpers ────────────────────────────────────────────────────────

  Widget _fadeSlide(int i, Widget child, {bool up = true}) {
    final start = (i * 0.10).clamp(0.0, 0.85);
    final end = (start + 0.45).clamp(0.0, 1.0);
    return FadeTransition(
      opacity: Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(
          parent: _entryCtrl,
          curve: Interval(start, end, curve: Curves.easeOut),
        ),
      ),
      child: SlideTransition(
        position:
            Tween<Offset>(
              begin: up ? const Offset(0, 0.2) : Offset.zero,
              end: Offset.zero,
            ).animate(
              CurvedAnimation(
                parent: _entryCtrl,
                curve: Interval(start, end, curve: Curves.easeOutCubic),
              ),
            ),
        child: child,
      ),
    );
  }

  // ── Formatters ───────────────────────────────────────────────────────────────

  String _formatDateTime(DateTime dt) {
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
    final h = dt.hour > 12
        ? dt.hour - 12
        : dt.hour == 0
        ? 12
        : dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} · $h:$m $ampm';
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final w = uiScaleWidth(context);
    // `kIsWeb` alone, no width test. The old `>= 900` left a dead zone: a pane
    // between 760 and 900 wide fell back to the PHONE hero, whose content
    // starts 19px from the pane's left edge, while the body below it was
    // already centred at 760. The web header shares that 760 box at every
    // width, so it needs no guard — and the guard was actively causing the
    // misalignment it looked like it was preventing.
    final bool wide = kIsWeb;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _buildSliverAppBar(w, wide: wide),
          SliverToBoxAdapter(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _kBand),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    _gutter(w),
                    w * .04,
                    _gutter(w),
                    w * .12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _fadeSlide(0, _buildHeroCard(w)),
                      SizedBox(height: w * .045),
                      _fadeSlide(
                        1,
                        _buildSectionLabel(w, 'Processing timeline'),
                      ),
                      SizedBox(height: w * .03),
                      _fadeSlide(2, _buildTimeline(w)),
                      SizedBox(height: w * .045),
                      _fadeSlide(3, _buildSectionLabel(w, 'Report details')),
                      SizedBox(height: w * .03),
                      _fadeSlide(4, _buildDetailsCard(w)),
                      if (_isResolved) ...[
                        SizedBox(height: w * .04),
                        _fadeSlide(
                          5,
                          ResolutionMediaSection(
                            reportId: _report.fullId,
                            canEdit: false,
                          ),
                        ),
                        SizedBox(height: w * .04),
                        _fadeSlide(6, _buildThankYouBanner(w)),
                      ],
                      if (_isRejected) ...[
                        SizedBox(height: w * .04),
                        _fadeSlide(5, _buildRejectedBanner(w)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(w),
    );
  }

  // ── Sliver app bar ────────────────────────────────────────────────────────────

  Widget _buildSliverAppBar(double w, {bool wide = false}) {
    if (wide) return _buildSliverAppBarWeb(w);
    return SliverAppBar(
      expandedHeight: w * 0.40,
      pinned: true,
      stretch: true,
      backgroundColor: AppColors.primaryBlue,
      leading: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Container(
            width: uiScaleWidth(context) * 0.09,
            height: uiScaleWidth(context) * 0.09,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(
                uiScaleWidth(context) * 0.025,
              ),
            ),
            child: Icon(
              Icons.arrow_back_ios_new_rounded,
              size: uiScaleWidth(context) * 0.045,
              color: Colors.white,
            ),
          ),
        ),
      ),
      actions: [
        GestureDetector(
          onTap: _copyReportId,
          child: Container(
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.copy_rounded, color: Colors.white, size: 14),
                const SizedBox(width: 5),
                Text(
                  'RPT-${_report.id}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 4),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Background gradient
            Container(
              decoration: const BoxDecoration(
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
            // Decorative circles
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
            // Content
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
                    SizedBox(height: w * .10),
                    Text(
                      'Report details',
                      style: TextStyle(
                        fontSize: w * .032,
                        color: Colors.white.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: w * .01),
                    Text(
                      _report.category,
                      style: TextStyle(
                        fontSize: w * .054,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.3,
                        height: 1.2,
                      ),
                    ),
                    SizedBox(height: w * .025),
                    Row(
                      children: [
                        _statusPill(w),
                        SizedBox(width: w * .025),
                        if (_report.isAnonymous)
                          _pillWidget(
                            w,
                            icon: Icons.lock_outline_rounded,
                            label: 'Anonymous',
                            bg: Colors.white.withValues(alpha: 0.15),
                            textColor: Colors.white,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── WEB header: full-bleed blue, content aligned to the 760 content band ────
  /// The web header: chevron, name, kind and id, then the state pills.
  ///
  /// ── Why the blue band is gone here too ──────────────────────────────────
  /// On the phone the hero is the top of the screen — it fills the status-bar
  /// area, holds the back target and gives a pushed screen its identity. In a
  /// desktop pane it is a 200px slab of saturated colour directly under a top
  /// nav that is already blue, above a page of white cards on grey. It stopped
  /// reading as this record's header and started reading as chrome.
  ///
  /// Everything it carried is still here, in the shape the rest of the account
  /// section uses: where you came from, what kind of record this is, its name,
  /// its id, its state. Built inside the same 760 box as the body below, so the
  /// two provably share a left edge.
  Widget _buildSliverAppBarWeb(double w) {
    final anonymous = _report.isAnonymous;

    return SliverToBoxAdapter(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kBand),
          child: Padding(
            padding: EdgeInsets.fromLTRB(_gutter(w), 24, _gutter(w), 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AccountPageTitle(
                  title: _report.category,
                  subtitle: 'Report details · RPT-${_report.id}',
                  onBack: () => Navigator.pop(context),
                  backLabel: 'Back',
                ),
                AccountHeaderIndent(
                  // Lines up with the title's left edge, so the header reads as
                  // one block — whether the back control is sitting beside the
                  // title or on its own line above it.
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      // The status pill keeps its colour — it is the one thing
                      // on this header carrying meaning rather than labelling.
                      _statusPill(w),
                      if (anonymous)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: CitizenUi.subtle,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: CitizenUi.border),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.lock_outline_rounded,
                                size: 13,
                                color: CitizenUi.textMuted,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Anonymous',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: CitizenUi.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      // The id is in the subtitle now, but copying it was a
                      // real affordance on the old chip, so it survives.
                      _WebCopyIdChip(label: 'Copy ID', onTap: _copyReportId),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusPill(double w) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: w * .030, vertical: w * .010),
      decoration: BoxDecoration(
        color: _statusColor,
        borderRadius: BorderRadius.circular(w * .05),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_statusIcon, color: Colors.white, size: w * .034),
          SizedBox(width: w * .012),
          Text(
            _statusLabel,
            style: TextStyle(
              color: Colors.white,
              fontSize: w * .028,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pillWidget(
    double w, {
    required IconData icon,
    required String label,
    required Color bg,
    required Color textColor,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: w * .025, vertical: w * .010),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(w * .05),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: textColor, size: w * .030),
          SizedBox(width: w * .010),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: w * .026,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ── Hero card ────────────────────────────────────────────────────────────────

  Widget _buildHeroCard(double w) {
    return Container(
      width: double.infinity,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Media thumbnail strip
          if (_report.mediaCount > 0)
            ClipRRect(
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(w * .04),
              ),
              child: _buildMediaStrip(w),
            ),

          Padding(
            padding: EdgeInsets.all(w * .04),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Location row
                if (_report.barangay != null || _report.address != null)
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_rounded,
                        size: w * .038,
                        color: AppColors.primaryBlue,
                      ),
                      SizedBox(width: w * .012),
                      Expanded(
                        child: Text(
                          [
                            _report.barangay,
                            _report.address,
                            'Aparri, Cagayan',
                          ].where((s) => s != null && s.isNotEmpty).join(', '),
                          style: TextStyle(
                            fontSize: w * .030,
                            color: const Color(0xFF374151),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),

                SizedBox(height: w * .015),

                // Date row
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today_rounded,
                      size: w * .034,
                      color: const Color(0xFF9CA3AF),
                    ),
                    SizedBox(width: w * .012),
                    Text(
                      _formatDateTime(_report.dateReported),
                      style: TextStyle(
                        fontSize: w * .028,
                        color: const Color(0xFF9CA3AF),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),

                SizedBox(height: w * .02),

                // View on map button
                GestureDetector(
                  onTap: () {
                    final barangay = _report.barangay;
                    if (barangay == null) return;

                    final coords = barangayCoords[barangay];
                    if (coords == null) return;

                    Navigator.push(
                      context,
                      PageRouteBuilder(
                        transitionDuration: const Duration(milliseconds: 380),
                        reverseTransitionDuration: const Duration(
                          milliseconds: 300,
                        ),
                        pageBuilder: (_, _, _) => LocationPickerScreen(
                          initialPosition: coords,
                          initialBarangay: barangay,
                          readOnly: true,
                        ),
                        transitionsBuilder: (_, animation, _, child) =>
                            FadeTransition(
                              opacity: CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOut,
                              ),
                              child: child,
                            ),
                      ),
                    );
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.map_outlined,
                        size: w * .034,
                        color: AppColors.primaryBlue,
                      ),
                      SizedBox(width: w * .010),
                      Text(
                        'View on map',
                        style: TextStyle(
                          fontSize: w * .030,
                          color: AppColors.primaryBlue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaStrip(double w) {
    if (_mediaLoading) {
      return SizedBox(
        height: w * .45,
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: _shimmerBox(w, double.infinity, double.infinity),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: _shimmerBox(w, double.infinity, double.infinity),
                  ),
                  const SizedBox(height: 2),
                  Expanded(
                    child: _shimmerBox(w, double.infinity, double.infinity),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (_mediaItems.isEmpty) {
      return Container(
        height: w * .40,
        color: const Color(0xFFF3F4F6),
        child: Center(
          child: Icon(
            Icons.image_not_supported_outlined,
            size: w * .10,
            color: const Color(0xFFD1D5DB),
          ),
        ),
      );
    }

    if (_mediaItems.length == 1) {
      return GestureDetector(
        onTap: () => _openMediaViewer(0),
        child: _mediaThumb(
          w,
          _mediaItems[0].url,
          _mediaItems[0].path,
          0,
          height: w * .50,
        ),
      );
    }

    // 2+ media — grid layout
    return SizedBox(
      height: w * .45,
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: () => _openMediaViewer(0),
              child: _mediaThumb(
                w,
                _mediaItems[0].url,
                _mediaItems[0].path,
                0,
                height: double.infinity,
              ),
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Column(
              children: [
                for (int i = 1; i < _mediaItems.length.clamp(1, 3); i++) ...[
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _openMediaViewer(i),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _mediaThumb(
                            w,
                            _mediaItems[i].url,
                            _mediaItems[i].path,
                            i,
                            height: double.infinity,
                          ),
                          if (i == 2 && _mediaItems.length > 3)
                            Container(
                              color: Colors.black.withValues(alpha: 0.55),
                              child: Center(
                                child: Text(
                                  '+${_mediaItems.length - 3}',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: w * .040,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (i < _mediaItems.length.clamp(1, 3) - 1)
                    const SizedBox(height: 2),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Media thumbnail — handles image AND video ─────────────────────────────────
  Widget _mediaThumb(
    double w,
    String url,
    String cacheKey,
    int index, {
    required double height,
  }) {
    final isVideo = _isVideoUrl(url);

    if (isVideo) {
      return Stack(
        fit: StackFit.expand,
        children: [
          // Video placeholder background with shimmer while no preview
          _shimmerBox(w, double.infinity, height),
          // Play button overlay
          Center(
            child: Container(
              padding: EdgeInsets.all(w * .030),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: w * .08,
              ),
            ),
          ),
          // Video label badge
          Positioned(
            bottom: 8,
            left: 8,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.60),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.videocam_rounded,
                    color: Colors.white,
                    size: w * .028,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'Video',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: w * .022,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // Image
    return CachedNetworkImage(
      imageUrl: url,
      cacheKey: cacheKey,
      memCacheWidth: 400,
      height: height == double.infinity ? w * .45 : height,
      width: double.infinity,
      fit: BoxFit.cover,
      placeholder: (context, url) => _shimmerBox(
        w,
        double.infinity,
        height == double.infinity ? w * .45 : height,
      ),
      errorWidget: (context, url, error) => Container(
        color: const Color(0xFFF3F4F6),
        child: Center(
          child: Icon(
            Icons.broken_image_outlined,
            color: const Color(0xFFD1D5DB),
            size: w * .08,
          ),
        ),
      ),
    );
  }

  // ── Shimmer box ───────────────────────────────────────────────────────────────

  Widget _shimmerBox(double w, double width, double height) {
    final resolvedH = height == double.infinity ? w * .45 : height;
    return AnimatedBuilder(
      animation: _shimmerCtrl,
      builder: (context, _) {
        return Container(
          width: width,
          height: resolvedH,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-1.5 + _shimmerCtrl.value * 3, 0),
              end: Alignment(-0.5 + _shimmerCtrl.value * 3, 0),
              colors: const [
                Color(0xFFE5E7EB),
                Color(0xFFF3F4F6),
                Color(0xFFE5E7EB),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  bool _isVideoUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.mp4') ||
        lower.contains('.mov') ||
        lower.contains('.avi') ||
        lower.contains('.mkv') ||
        lower.contains('.webm') ||
        lower.contains('.3gp');
  }

  // ── Timeline ─────────────────────────────────────────────────────────────────

  Widget _buildTimeline(double w) {
    final steps = _timelineSteps;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(w * .04),
        border: Border.all(color: CitizenUi.sharedBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──
          Padding(
            padding: EdgeInsets.fromLTRB(w * .04, w * .04, w * .04, w * .02),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(w * .022),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(w * .025),
                  ),
                  child: Icon(
                    Icons.track_changes_rounded,
                    size: w * .038,
                    color: AppColors.primaryBlue,
                  ),
                ),
                SizedBox(width: w * .025),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Processing Timeline',
                      style: TextStyle(
                        fontSize: w * .034,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1F2937),
                        letterSpacing: -0.2,
                      ),
                    ),
                    Text(
                      _timelineStatusSummary,
                      style: TextStyle(
                        fontSize: w * .026,
                        color: const Color(0xFF9CA3AF),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                // Progress badge
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: w * .025,
                    vertical: w * .010,
                  ),
                  decoration: BoxDecoration(
                    color: _progressBadgeColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(w * .04),
                    border: Border.all(
                      color: _progressBadgeColor.withValues(alpha: 0.30),
                    ),
                  ),
                  child: Text(
                    _progressBadgeLabel,
                    style: TextStyle(
                      fontSize: w * .024,
                      fontWeight: FontWeight.w700,
                      color: _progressBadgeColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Progress bar ──
          Padding(
            padding: EdgeInsets.fromLTRB(w * .04, 0, w * .04, w * .04),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: w * .008),
                ClipRRect(
                  borderRadius: BorderRadius.circular(w * .02),
                  child: Stack(
                    children: [
                      // Track
                      Container(
                        height: w * .018,
                        width: double.infinity,
                        color: const Color(0xFFF3F4F6),
                      ),
                      // Fill + shimmer clipped together
                      AnimatedBuilder(
                        animation: _timelineCtrl,
                        builder: (_, _) {
                          final progress =
                              (_timelineProgress * _timelineCtrl.value).clamp(
                                0.0,
                                1.0,
                              );
                          return FractionallySizedBox(
                            widthFactor: progress,
                            child: ClipRect(
                              child: Stack(
                                children: [
                                  // Base fill
                                  Container(
                                    height: w * .018,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: _isRejected
                                            ? [
                                                AppColors.red.withValues(
                                                  alpha: 0.7,
                                                ),
                                                AppColors.red,
                                              ]
                                            : _isResolved
                                            ? [
                                                AppColors.green.withValues(
                                                  alpha: 0.7,
                                                ),
                                                AppColors.green,
                                              ]
                                            : [
                                                AppColors.primaryBlue
                                                    .withValues(alpha: 0.6),
                                                AppColors.primaryBlue,
                                              ],
                                      ),
                                    ),
                                  ),
                                  // Shimmer sweep — only on pending/underReview
                                  if (!_isResolved && !_isRejected)
                                    LayoutBuilder(
                                      builder: (_, constraints) {
                                        final fillWidth = constraints.maxWidth;
                                        return AnimatedBuilder(
                                          animation: _shimmerCtrl,
                                          builder: (_, _) {
                                            return Transform.translate(
                                              offset: Offset(
                                                (_shimmerCtrl.value * 2 - 0.5) *
                                                    fillWidth,
                                                0,
                                              ),
                                              child: FractionallySizedBox(
                                                widthFactor: 0.45,
                                                child: Container(
                                                  height: w * .018,
                                                  decoration: BoxDecoration(
                                                    gradient: LinearGradient(
                                                      colors: [
                                                        Colors.white.withValues(
                                                          alpha: 0.0,
                                                        ),
                                                        Colors.white.withValues(
                                                          alpha: 0.55,
                                                        ),
                                                        Colors.white.withValues(
                                                          alpha: 0.0,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        );
                                      },
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                SizedBox(height: w * .012),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Submitted',
                      style: TextStyle(
                        fontSize: w * .022,
                        color: const Color(0xFF9CA3AF),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      _isResolved
                          ? 'Resolved'
                          : _isRejected
                          ? 'Closed'
                          : 'Resolution',
                      style: TextStyle(
                        fontSize: w * .022,
                        color: const Color(0xFF9CA3AF),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          Padding(
            padding: EdgeInsets.symmetric(horizontal: w * .04),
            child: const Divider(height: 1, color: Color(0xFFF3F4F6)),
          ),
          SizedBox(height: w * .03),

          // ── Steps ──
          Padding(
            padding: EdgeInsets.fromLTRB(w * .04, 0, w * .04, w * .04),
            child: Column(
              children: [
                for (int i = 0; i < steps.length; i++)
                  _buildTimelineStep(w, steps[i], i, steps.length, i),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Timeline computed helpers ─────────────────────────────────────────────────

  String get _timelineStatusSummary {
    if (_isResolved) return 'All steps completed';
    if (_isRejected) return 'Report closed';
    if (_isInProgress) return 'Being worked on';
    if (_isEndorsed) return 'Endorsed to $_forwardedDepartment';
    if (_isUnderReview) return 'Being processed';
    if (_isPending) return 'Awaiting review';
    return 'Awaiting review';
  }

  Color get _progressBadgeColor {
    if (_isResolved) return AppColors.green;
    if (_isRejected) return AppColors.red;
    if (_isUnderReview || _isInProgress) return AppColors.primaryBlue;
    return AppColors.orange;
  }

  String get _progressBadgeLabel {
    final steps = _timelineSteps;
    // Count the step the report has *reached* — completed steps plus the one
    // currently active — so an "In progress" report reads 3/4, matching the
    // highlighted step, instead of 2/4 (which looked like it was a step behind).
    final reached = steps
        .where((s) => s.status != TimelineStepStatus.pending)
        .length;
    return '$reached/${steps.length}';
  }

  double get _timelineProgress {
    final steps = _timelineSteps;
    if (steps.isEmpty) return 0;
    final done = steps
        .where((s) => s.status == TimelineStepStatus.completed)
        .length;
    // count active as half a step
    final active = steps
        .where((s) => s.status == TimelineStepStatus.active)
        .length;
    return (done + active * 0.5) / steps.length;
  }

  Widget _buildTimelineStep(
    double w,
    _TimelineStep step,
    int index,
    int total,
    int animationIndex,
  ) {
    final isLast = index == total - 1;
    final isCompleted = step.status == TimelineStepStatus.completed;
    final isActive = step.status == TimelineStepStatus.active;
    final isPending = step.status == TimelineStepStatus.pending;

    final bool isFinalRejected = isLast && _isRejected && isCompleted;

    final Color dotColor = isFinalRejected
        ? AppColors.red
        : isCompleted
        ? AppColors.green
        : isActive
        ? AppColors.primaryBlue
        : const Color(0xFFD1D5DB);

    final Color lineColor = isCompleted
        ? AppColors.green.withValues(alpha: 0.35)
        : const Color(0xFFEEF0F2);

    final delay = (animationIndex * 0.12).clamp(0.0, 0.85);
    final end = (delay + 0.40).clamp(0.0, 1.0);

    return AnimatedBuilder(
      animation: _timelineCtrl,
      builder: (_, child) {
        final t = CurvedAnimation(
          parent: _timelineCtrl,
          curve: Interval(delay, end, curve: Curves.easeOut),
        ).value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 14),
            child: child,
          ),
        );
      },
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Left: dot + line ──
            SizedBox(
              width: w * .11,
              child: Column(
                children: [
                  // Outer ring (active pulse effect)
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      // Pulse ring for active
                      if (isActive)
                        Container(
                          width: w * .105,
                          height: w * .105,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.primaryBlue.withValues(
                              alpha: 0.12,
                            ),
                            border: Border.all(
                              color: AppColors.primaryBlue.withValues(
                                alpha: 0.25,
                              ),
                              width: 1.5,
                            ),
                          ),
                        ),
                      // Main dot
                      Container(
                        width: w * .082,
                        height: w * .082,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isFinalRejected
                              ? AppColors.red.withValues(alpha: 0.10)
                              : isCompleted
                              ? AppColors.green.withValues(alpha: 0.10)
                              : isActive
                              ? AppColors.primaryBlue.withValues(alpha: 0.08)
                              : const Color(0xFFF9FAFB),
                          border: Border.all(
                            color: isPending
                                ? CitizenUi.sharedBorder
                                : dotColor,
                            width: isActive ? 2.0 : 1.5,
                          ),
                        ),
                        child: Icon(
                          // Use checkmark for completed non-rejected steps
                          isCompleted && !isFinalRejected
                              ? Icons.check_rounded
                              : step.icon,
                          size: w * .036,
                          color: isPending ? const Color(0xFFD1D5DB) : dotColor,
                        ),
                      ),
                    ],
                  ),
                  // Connector line
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 2,
                        margin: EdgeInsets.symmetric(vertical: w * .008),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: isCompleted
                                ? [
                                    AppColors.green.withValues(alpha: 0.5),
                                    lineColor,
                                  ]
                                : [lineColor, lineColor],
                          ),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            SizedBox(width: w * .025),

            // ── Right: content ──
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : w * .038),
                child: Container(
                  padding: EdgeInsets.all(w * .030),
                  decoration: BoxDecoration(
                    color: isFinalRejected
                        ? AppColors.red.withValues(alpha: 0.04)
                        : isActive
                        ? AppColors.primaryBlue.withValues(alpha: 0.04)
                        : isCompleted
                        ? AppColors.green.withValues(alpha: 0.03)
                        : const Color(0xFFFAFAFA),
                    borderRadius: BorderRadius.circular(w * .028),
                    border: Border.all(
                      color: isFinalRejected
                          ? AppColors.red.withValues(alpha: 0.15)
                          : isActive
                          ? AppColors.primaryBlue.withValues(alpha: 0.18)
                          : isCompleted
                          ? AppColors.green.withValues(alpha: 0.15)
                          : const Color(0xFFEEF0F2),
                      width: isActive ? 1.5 : 1.0,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title row
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              step.title,
                              style: TextStyle(
                                fontSize: w * .032,
                                fontWeight: FontWeight.w700,
                                color: isPending
                                    ? const Color(0xFFCBD5E1)
                                    : isFinalRejected
                                    ? AppColors.red
                                    : isActive
                                    ? AppColors.primaryBlue
                                    : const Color(0xFF1F2937),
                                letterSpacing: -0.1,
                              ),
                            ),
                          ),
                          // Status chip
                          if (isCompleted && !isPending)
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: w * .018,
                                vertical: w * .005,
                              ),
                              decoration: BoxDecoration(
                                color: isFinalRejected
                                    ? AppColors.red.withValues(alpha: 0.10)
                                    : AppColors.green.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(w * .03),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isFinalRejected
                                        ? Icons.close_rounded
                                        : Icons.check_rounded,
                                    size: w * .022,
                                    color: isFinalRejected
                                        ? AppColors.red
                                        : AppColors.green,
                                  ),
                                  SizedBox(width: w * .006),
                                  Text(
                                    isFinalRejected ? 'Closed' : 'Done',
                                    style: TextStyle(
                                      fontSize: w * .020,
                                      fontWeight: FontWeight.w700,
                                      color: isFinalRejected
                                          ? AppColors.red
                                          : AppColors.green,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (isActive)
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: w * .018,
                                vertical: w * .005,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primaryBlue.withValues(
                                  alpha: 0.10,
                                ),
                                borderRadius: BorderRadius.circular(w * .03),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: w * .014,
                                    height: w * .014,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: AppColors.primaryBlue,
                                    ),
                                  ),
                                  SizedBox(width: w * .008),
                                  Text(
                                    'Active',
                                    style: TextStyle(
                                      fontSize: w * .020,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primaryBlue,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      SizedBox(height: w * .006),
                      // Subtitle
                      Text(
                        step.subtitle,
                        style: TextStyle(
                          fontSize: w * .026,
                          color: isPending
                              ? const Color(0xFFCBD5E1)
                              : const Color(0xFF6B7280),
                          height: 1.5,
                        ),
                      ),
                      // Date if present
                      if (step.date != null) ...[
                        SizedBox(height: w * .010),
                        Row(
                          children: [
                            Icon(
                              Icons.schedule_rounded,
                              size: w * .026,
                              color: const Color(0xFFB0B8C4),
                            ),
                            SizedBox(width: w * .008),
                            Text(
                              step.date!,
                              style: TextStyle(
                                fontSize: w * .022,
                                color: const Color(0xFFB0B8C4),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Details card ─────────────────────────────────────────────────────────────

  Widget _buildDetailsCard(double w) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(w * .04),
        border: Border.all(color: CitizenUi.sharedBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // 1 — Attachments first
          if (_report.mediaCount > 0) _buildMediaRow(w),

          // 2 — Category
          _detailRow(
            w,
            icon: Icons.category_outlined,
            label: 'Category',
            value: _report.category,
            showDivider: true,
          ),

          // 3 — Description
          _detailRow(
            w,
            icon: Icons.notes_rounded,
            label: 'Description',
            value: _report.remarks.isEmpty
                ? 'No description provided'
                : _report.remarks,
            showDivider: true,
          ),

          // 4 — Reported by
          _detailRow(
            w,
            icon: _report.isAnonymous
                ? Icons.lock_outline_rounded
                : Icons.person_outline_rounded,
            label: 'Reported by',
            value: _report.isAnonymous ? 'Anonymous' : widget.username,
            showDivider: false,
          ),
        ],
      ),
    );
  }

  Widget _detailRow(
    double w, {
    required IconData icon,
    required String label,
    required String value,
    required bool showDivider,
  }) {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: w * .04,
            vertical: w * .034,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: w * .042, color: const Color(0xFF9CA3AF)),
              SizedBox(width: w * .03),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: w * .026,
                        color: const Color(0xFF9CA3AF),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: w * .005),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: w * .032,
                        color: const Color(0xFF1F2937),
                        fontWeight: FontWeight.w500,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        if (showDivider)
          const Divider(height: 1, thickness: 1, color: Color(0xFFF3F4F6)),
      ],
    );
  }

  Widget _buildMediaRow(double w) {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: w * .04,
            vertical: w * .034,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.attach_file_rounded,
                size: w * .042,
                color: const Color(0xFF9CA3AF),
              ),
              SizedBox(width: w * .03),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Attachments',
                      style: TextStyle(
                        fontSize: w * .026,
                        color: const Color(0xFF9CA3AF),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: w * .015),
                    _mediaLoading
                        ? Wrap(
                            spacing: w * .025,
                            runSpacing: w * .025,
                            children: List.generate(
                              _report.mediaCount.clamp(1, 6),
                              (_) => ClipRRect(
                                borderRadius: BorderRadius.circular(w * .025),
                                child: _shimmerBox(w, w * .20, w * .20),
                              ),
                            ),
                          )
                        : Wrap(
                            spacing: w * .025,
                            runSpacing: w * .025,
                            children: [
                              for (int i = 0; i < _mediaItems.length; i++)
                                GestureDetector(
                                  onTap: () => _openMediaViewer(i),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(
                                      w * .025,
                                    ),
                                    child: Stack(
                                      children: [
                                        CachedNetworkImage(
                                          imageUrl: _mediaItems[i].url,
                                          cacheKey: _mediaItems[i].path,
                                          memCacheWidth: 200,
                                          width: w * .20,
                                          height: w * .20,
                                          fit: BoxFit.cover,
                                          placeholder: (context, url) =>
                                              _shimmerBox(w, w * .20, w * .20),
                                          errorWidget: (context, url, error) =>
                                              Container(
                                                width: w * .20,
                                                height: w * .20,
                                                color: const Color(0xFFF3F4F6),
                                                child: const Icon(
                                                  Icons.broken_image_outlined,
                                                  color: Color(0xFFD1D5DB),
                                                ),
                                              ),
                                        ),
                                        // Badge
                                        Positioned(
                                          top: 4,
                                          right: 4,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 5,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.black.withValues(
                                                alpha: 0.55,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              '${i + 1}',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: w * .022,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 1, color: Color(0xFFF3F4F6)),
      ],
    );
  }

  // ── Banners ───────────────────────────────────────────────────────────────────

  Widget _buildThankYouBanner(double w) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(w * .04),
      decoration: BoxDecoration(
        color: AppColors.green.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(w * .04),
        border: Border.all(color: AppColors.green.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(w * .025),
            decoration: BoxDecoration(
              color: AppColors.green.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.celebration_rounded,
              color: AppColors.green,
              size: w * .055,
            ),
          ),
          SizedBox(width: w * .03),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Thank you for your report!',
                  style: TextStyle(
                    fontSize: w * .034,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1F2937),
                  ),
                ),
                SizedBox(height: w * .005),
                Text(
                  'Your effort helps make Aparri a better place to live.',
                  style: TextStyle(
                    fontSize: w * .028,
                    color: const Color(0xFF6B7280),
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRejectedBanner(double w) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(w * .04),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(w * .04),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(w * .025),
            decoration: BoxDecoration(
              color: AppColors.red.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.info_outline_rounded,
              color: AppColors.red,
              size: w * .050,
            ),
          ),
          SizedBox(width: w * .03),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Report could not be actioned',
                  style: TextStyle(
                    fontSize: w * .034,
                    fontWeight: FontWeight.w700,
                    color: AppColors.red,
                  ),
                ),
                SizedBox(height: w * .005),
                Text(
                  _report.rejectionNote?.trim().isNotEmpty == true
                      ? _report.rejectionNote!.trim()
                      : 'This report did not meet the criteria for action. Please contact our office or chat with an agent for more details.',
                  style: TextStyle(
                    fontSize: w * .028,
                    color: const Color(0xFF6B7280),
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Section label ────────────────────────────────────────────────────────────

  Widget _buildSectionLabel(double w, String label) {
    return Text(
      label,
      style: TextStyle(
        fontSize: w * .036,
        fontWeight: FontWeight.w700,
        color: AppColors.primaryBlue,
        letterSpacing: 0.2,
      ),
    );
  }

  // ── Bottom bar ────────────────────────────────────────────────────────────────

  Widget _buildBottomBar(double w) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(
        w * .04,
        w * .025,
        w * .04,
        // If system nav is visible (bottomPadding > 0), use it;
        // otherwise fall back to a comfortable fixed padding
        bottomPadding > 0 ? bottomPadding + w * .01 : w * .04,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: CitizenUi.sharedBorder)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kBand),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Need help with this report?',
                      style: TextStyle(
                        fontSize: w * .030,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1F2937),
                      ),
                    ),
                    Text(
                      'Chat with an agent for follow-up.',
                      style: TextStyle(
                        fontSize: w * .026,
                        color: const Color(0xFF9CA3AF),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: w * .03),
              ElevatedButton.icon(
                onPressed: _openingChat ? null : _goToChat,
                icon: _openingChat
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.chat_bubble_outline_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                label: Text(
                  _openingChat ? 'Opening…' : 'Chat with agent',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  disabledBackgroundColor: AppColors.primaryBlue.withValues(
                    alpha: 0.6,
                  ),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: EdgeInsets.symmetric(
                    horizontal: w * .04,
                    vertical: w * .030,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Actions ───────────────────────────────────────────────────────────────────

  void _copyReportId() {
    Clipboard.setData(ClipboardData(text: 'RPT-${_report.id}'));
    showAppSnackBar(
      context,
      'Report ID copied to clipboard',
      type: AppSnackType.info,
    );
  }

  void _openMediaViewer(int initialIndex) {
    if (_mediaItems.isEmpty) return;
    // On WEB this screen renders inside the shell's centre column, and its
    // BRANCH navigator bounds the viewer: the barrier stopped at the column,
    // so the left rail and the quick-actions sidebar stayed bright either side
    // of a black strip. The root navigator is the whole window.
    //
    // Same fix, same reason, as the news feed card's [openImageViewer] call.
    // kIsWeb rather than a bare `true` so MOBILE takes exactly the path it
    // takes today - there `Navigator.of(context, rootNavigator: false)` is
    // what the bare `Navigator.push(context, ...)` already resolved to.
    Navigator.of(context, rootNavigator: kIsWeb).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (_, _, _) => _MediaViewerScreen(
          urls: _mediaItems.map((e) => e.url).toList(),
          cacheKeys: _mediaItems.map((e) => e.path).toList(),
          initialIndex: initialIndex,
        ),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  Future<void> _goToChat() async {
    if (_openingChat) return; // re-entry guard
    setState(() => _openingChat = true); // disable button immediately
    try {
      await _chatService.openFollowUp(
        reportRef: 'RPT-${_report.id}',
        reportCategory: _report.category,
        reportStatus: _statusLabel,
        reportId: _report.fullId,
        reportDepartment: _departmentFromCategory(_report.category),
      );
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              ChatAgentScreen(username: widget.username, service: _chatService),
        ),
      );
    } finally {
      if (mounted) setState(() => _openingChat = false);
    }
  }
}

// ─── Media viewer ─────────────────────────────────────────────────────────────

class _MediaViewerScreen extends StatefulWidget {
  final List<String> urls;
  final List<String> cacheKeys;
  final int initialIndex;

  const _MediaViewerScreen({
    required this.urls,
    required this.cacheKeys,
    required this.initialIndex,
  });
  @override
  State<_MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<_MediaViewerScreen> {
  late final PageController _pageCtrl;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _pageCtrl = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageCtrl,
            itemCount: widget.urls.length,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (_, i) => InteractiveViewer(
              child: Center(
                // ── The plate behind the image ─────────────────────────
                //
                // A PNG or WebP with an alpha channel and dark artwork is
                // INVISIBLE on this black scaffold - it loads, it paints, and
                // there is nothing to see, which reads as a broken viewer
                // rather than as a transparent image. The card behind it does
                // not have the problem because it sits on white.
                //
                // A neutral plate sized to the image fixes that and costs an
                // opaque photo nothing: at BoxFit.contain the photo covers the
                // plate exactly, so it is only ever visible THROUGH the
                // transparent parts of an image that has any.
                child: DecoratedBox(
                  decoration: const BoxDecoration(color: Color(0xFFE5E7EB)),
                  child: CachedNetworkImage(
                    imageUrl: widget.urls[i],
                    cacheKey: widget.cacheKeys[i],
                    fit: BoxFit.contain,
                    placeholder: (context, url) => const Center(
                      child: CircularProgressIndicator(
                        color: Colors.white54,
                        strokeWidth: 2,
                      ),
                    ),
                    errorWidget: (context, url, error) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white54,
                      size: 60,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Top bar
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_current + 1} / ${widget.urls.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Dots indicator
          if (widget.urls.length > 1)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 24,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (int i = 0; i < widget.urls.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: _current == i ? 20 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: _current == i
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Quiet "Copy ID" pill for the web header, replacing the translucent chip that
/// used to ride on the blue band.
class _WebCopyIdChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _WebCopyIdChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: CitizenUi.subtle,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: CitizenUi.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.copy_rounded,
                size: 13,
                color: CitizenUi.textMuted,
              ),
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
        ),
      ),
    );
  }
}
