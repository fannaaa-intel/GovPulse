import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../my_report/my_reports_screen.dart';
import '../Quick-action/Report/location_picker_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';

// ─── Timeline step model ──────────────────────────────────────────────────────

enum TimelineStepStatus { completed, active, pending }

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
  late final AnimationController _timelineCtrl;
  late final AnimationController _shimmerCtrl;

  final List<({String url, String path})> _mediaItems = [];
  bool _mediaLoading = true;

  // ── Derived helpers ──────────────────────────────────────────────────────────

  bool get _isResolved => widget.report.status == ReportStatus.resolved;
  bool get _isRejected => widget.report.status == ReportStatus.rejected;
  bool get _isPending => widget.report.status == ReportStatus.pending;
  bool get _isUnderReview => widget.report.status == ReportStatus.underReview;

  // Determine if the report was forwarded to an external department
  // based on the category — roads/drainage/environment often go to DPWH or DENR
  bool get _isForwarded =>
      _isUnderReview &&
      (widget.report.categoryKey == 'road' ||
          widget.report.categoryKey == 'drainage' ||
          widget.report.categoryKey == 'environment');

  String get _forwardedDepartment {
    switch (widget.report.categoryKey) {
      case 'road':
        return 'Department of Public Works and Highways (DPWH)';
      case 'drainage':
        return 'DPWH — Flood Control Division';
      case 'environment':
        return 'DENR — Environmental Management Bureau';
      default:
        return 'Concerned Department';
    }
  }

  Color get _statusColor {
    switch (widget.report.status) {
      case ReportStatus.resolved:
        return AppColors.green;
      case ReportStatus.rejected:
        return AppColors.red;
      case ReportStatus.underReview:
        return const Color(0xFF6366F1);
      default:
        return AppColors.orange;
    }
  }

  String get _statusLabel {
    switch (widget.report.status) {
      case ReportStatus.resolved:
        return 'Resolved';
      case ReportStatus.rejected:
        return 'Rejected';
      case ReportStatus.underReview:
        return 'Under Review';
      default:
        return 'Pending';
    }
  }

  IconData get _statusIcon {
    switch (widget.report.status) {
      case ReportStatus.resolved:
        return Icons.check_circle_rounded;
      case ReportStatus.rejected:
        return Icons.cancel_rounded;
      case ReportStatus.underReview:
        return Icons.manage_search_rounded;
      default:
        return Icons.access_time_rounded;
    }
  }

  // ── Timeline steps ───────────────────────────────────────────────────────────

  List<_TimelineStep> get _timelineSteps {
    final steps = <_TimelineStep>[];
    final date = _formatDateTime(widget.report.dateReported);

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

    if (_isPending) {
      steps.add(
        _TimelineStep(
          title: 'Initial review',
          subtitle: 'Our team is reviewing your report.',
          status: TimelineStepStatus.active,
          icon: Icons.rate_review_rounded,
        ),
      );
      steps.add(
        _TimelineStep(
          title: 'Resolution in progress',
          subtitle: 'The assigned team will work on this.',
          status: TimelineStepStatus.pending,
          icon: Icons.construction_rounded,
        ),
      );
      steps.add(
        _TimelineStep(
          title: 'Closed',
          subtitle: 'Final outcome pending.',
          status: TimelineStepStatus.pending,
          icon: Icons.flag_rounded,
        ),
      );
      return steps;
    }

    // Step 2 — under review or beyond
    steps.add(
      _TimelineStep(
        title: 'Initial review',
        subtitle: 'Your report is being assessed by our team.',
        status: _isUnderReview || _isResolved || _isRejected
            ? TimelineStepStatus.completed
            : TimelineStepStatus.pending,
        icon: Icons.manage_search_rounded,
      ),
    );

    // Step 3 — conditional forwarding
    if (_isForwarded || _isResolved) {
      steps.add(
        _TimelineStep(
          title: 'Forwarded to department',
          subtitle: _forwardedDepartment,
          status: _isResolved
              ? TimelineStepStatus.completed
              : TimelineStepStatus.active,
          icon: Icons.account_balance_rounded,
        ),
      );
    }

    // Step 4 — in progress
    steps.add(
      _TimelineStep(
        title: 'In progress',
        subtitle: 'The assigned team is actively working on this report.',
        status: _isResolved
            ? TimelineStepStatus.completed
            : TimelineStepStatus.pending,
        icon: Icons.construction_rounded,
      ),
    );

    // Step 5 — verification
    if (_isResolved) {
      steps.add(
        _TimelineStep(
          title: 'Verification',
          subtitle: 'The completed work is being verified by our team.',
          status: TimelineStepStatus.completed,
          icon: Icons.verified_rounded,
        ),
      );
    }

    // Step 6 — final
    if (_isResolved) {
      steps.add(
        _TimelineStep(
          title: 'Resolved',
          subtitle:
              'Your report has been resolved. Thank you for helping improve our community!',
          status: TimelineStepStatus.completed,
          icon: Icons.check_circle_rounded,
        ),
      );
    } else if (_isRejected) {
      steps.add(
        _TimelineStep(
          title: 'Report closed',
          subtitle:
              'This report could not be actioned. Please contact our office for more information.',
          status: TimelineStepStatus.completed,
          icon: Icons.cancel_rounded,
        ),
      );
    }

    return steps;
  }

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

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
      duration: const Duration(milliseconds: 5000),
    )..repeat();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _entryCtrl.forward();
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) _timelineCtrl.forward();
    });

    _loadMediaUrls();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _timelineCtrl.dispose();
    _shimmerCtrl.dispose();
    super.dispose();
  }

  // ── Media loading ────────────────────────────────────────────────────────────
  Future<void> _loadMediaUrls() async {
    try {
      final supabase = Supabase.instance.client;

      final rows = await supabase
          .from('report_media')
          .select('storage_path, mime_type, display_order')
          .eq('report_id', widget.report.fullId)
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
    final w = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _buildSliverAppBar(w),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(w * .04, w * .04, w * .04, w * .12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _fadeSlide(0, _buildHeroCard(w)),
                  SizedBox(height: w * .045),
                  _fadeSlide(1, _buildSectionLabel(w, 'Processing timeline')),
                  SizedBox(height: w * .03),
                  _fadeSlide(2, _buildTimeline(w)),
                  SizedBox(height: w * .045),
                  _fadeSlide(3, _buildSectionLabel(w, 'Report details')),
                  SizedBox(height: w * .03),
                  _fadeSlide(4, _buildDetailsCard(w)),
                  if (_isResolved) ...[
                    SizedBox(height: w * .04),
                    _fadeSlide(5, _buildThankYouBanner(w)),
                  ],
                  if (_isRejected) ...[
                    SizedBox(height: w * .04),
                    _fadeSlide(5, _buildRejectedBanner(w)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _fadeSlide(6, _buildBottomBar(w), up: false),
    );
  }

  // ── Sliver app bar ────────────────────────────────────────────────────────────

  Widget _buildSliverAppBar(double w) {
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
            width: MediaQuery.of(context).size.width * 0.09,
            height: MediaQuery.of(context).size.width * 0.09,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(
                MediaQuery.of(context).size.width * 0.025,
              ),
            ),
            child: Icon(
              Icons.arrow_back_ios_new_rounded,
              size: MediaQuery.of(context).size.width * 0.045,
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
                  'RPT-${widget.report.id}',
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
                      widget.report.category,
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
                        if (widget.report.isAnonymous)
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
        border: Border.all(color: const Color(0xFFE5E7EB)),
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
          if (widget.report.mediaCount > 0)
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
                if (widget.report.barangay != null ||
                    widget.report.address != null)
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
                            widget.report.barangay,
                            widget.report.address,
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
                      _formatDateTime(widget.report.dateReported),
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
                    final barangay = widget.report.barangay;
                    if (barangay == null) return;

                    final coords = barangayCoords[barangay];
                    if (coords == null) return;

                    Navigator.push(
                      context,
                      PageRouteBuilder(
                        transitionDuration: const Duration(milliseconds: 400),
                        pageBuilder: (_, _, _) => LocationPickerScreen(
                          initialPosition: coords,
                          initialBarangay: barangay,
                          readOnly: true,
                        ),
                        transitionsBuilder: (_, anim, _, child) =>
                            SlideTransition(
                              position:
                                  Tween<Offset>(
                                    begin: const Offset(0, 1),
                                    end: Offset.zero,
                                  ).animate(
                                    CurvedAnimation(
                                      parent: anim,
                                      curve: Curves.easeOutCubic,
                                    ),
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
    return AnimatedBuilder(
      animation: _shimmerCtrl,
      builder: (context, _) {
        return Container(
          width: width,
          height: height == double.infinity ? w * .45 : height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              stops: [
                (_shimmerCtrl.value - 0.3).clamp(0.0, 1.0),
                _shimmerCtrl.value.clamp(0.0, 1.0),
                (_shimmerCtrl.value + 0.3).clamp(0.0, 1.0),
              ],
              colors: const [
                Color(0xFFEEEEEE),
                Color(0xFFF8F8F8),
                Color(0xFFEEEEEE),
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
        border: Border.all(color: const Color(0xFFE5E7EB)),
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
    if (_isUnderReview) return 'Being processed';
    return 'Awaiting review';
  }

  Color get _progressBadgeColor {
    if (_isResolved) return AppColors.green;
    if (_isRejected) return AppColors.red;
    if (_isUnderReview) return AppColors.primaryBlue;
    return AppColors.orange;
  }

  String get _progressBadgeLabel {
    final steps = _timelineSteps;
    final done = steps
        .where((s) => s.status == TimelineStepStatus.completed)
        .length;
    return '$done/${steps.length}';
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
                                ? const Color(0xFFE5E7EB)
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
        border: Border.all(color: const Color(0xFFE5E7EB)),
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
          if (widget.report.mediaCount > 0) _buildMediaRow(w),

          // 2 — Category
          _detailRow(
            w,
            icon: Icons.category_outlined,
            label: 'Category',
            value: widget.report.category,
            showDivider: true,
          ),

          // 3 — Description
          _detailRow(
            w,
            icon: Icons.notes_rounded,
            label: 'Description',
            value: widget.report.remarks.isEmpty
                ? 'No description provided'
                : widget.report.remarks,
            showDivider: true,
          ),

          // 4 — Reported by
          _detailRow(
            w,
            icon: widget.report.isAnonymous
                ? Icons.lock_outline_rounded
                : Icons.person_outline_rounded,
            label: 'Reported by',
            value: widget.report.isAnonymous ? 'Anonymous' : widget.username,
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
                        ? SizedBox(
                            height: w * .20,
                            child: Center(
                              child: CircularProgressIndicator(
                                color: AppColors.primaryBlue,
                                strokeWidth: 2,
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
                  'This report did not meet the criteria for action. Please contact our office or chat with an agent for more details.',
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
        border: const Border(top: BorderSide(color: Color(0xFFE5E7EB))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
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
            onPressed: _goToChat,
            icon: const Icon(
              Icons.chat_bubble_outline_rounded,
              color: Colors.white,
              size: 16,
            ),
            label: const Text(
              'Chat with agent',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
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
    );
  }

  // ── Actions ───────────────────────────────────────────────────────────────────

  void _copyReportId() {
    Clipboard.setData(ClipboardData(text: 'RPT-${widget.report.id}'));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Report ID copied to clipboard'),
        backgroundColor: AppColors.primaryBlue,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _openMediaViewer(int initialIndex) {
    if (_mediaItems.isEmpty) return;
    Navigator.push(
      context,
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

  void _goToChat() {
    Navigator.pushNamed(context, '/chat', arguments: widget.username);
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
