import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../../../core/theme/app_colors.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/widgets/Home/nav/responsive_nav_scaffold.dart';
import '../../../../core/widgets/loading/loading_overlay.dart';
import '../../../core/widgets/web/web_card_grid.dart';
import 'report_card.dart';

// The report row, the ReportItem model and the type scale now live in
// report_card.dart so the card can be rendered without this screen. Re-exported
// because four other files import ReportItem *from here* (app_router,
// report_detail_screen, notification_popup, my_submissions_screen) — this keeps
// every one of those imports working unchanged.
export 'report_card.dart' show ReportItem, ReportStatus, ReportUi;

/// The old private name for the type scale, kept so this screen's ~50 existing
/// `_T.xxx` call sites read exactly as they did before the extraction.
typedef _T = ReportUi;

// ─── Filter ───────────────────────────────────────────────────────────────────

enum ReportFilter { all, today, thisWeek, thisMonth, last3Months }

enum StatusFilter { all, pending, resolved, rejected }

// ─────────────────────────────────────────────────────────────────────────────

class MyReportsScreen extends StatefulWidget {
  final String username;
  const MyReportsScreen({super.key, required this.username});

  @override
  State<MyReportsScreen> createState() => _MyReportsScreenState();
}

class _MyReportsScreenState extends State<MyReportsScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entryCtrl;

  ReportFilter _activeFilter = ReportFilter.all;
  StatusFilter _activeKpi = StatusFilter.all;
  List<ReportItem> _allReports = [];
  bool _isLoading = true;
  String? _error;

  // ── Derived lists ──────────────────────────────────────────────────────────

  bool _matchesKpi(ReportItem r) {
    switch (_activeKpi) {
      case StatusFilter.all:
        return true;
      case StatusFilter.pending:
        return r.status == ReportStatus.pending ||
            r.status == ReportStatus.underReview ||
            r.status == ReportStatus.inProgress;
      case StatusFilter.resolved:
        return r.status == ReportStatus.resolved;
      case StatusFilter.rejected:
        return r.status == ReportStatus.rejected;
    }
  }

  void _selectKpi(StatusFilter f) {
    setState(() {
      // tap a selected card again to clear it (back to All)
      _activeKpi = (_activeKpi == f && f != StatusFilter.all)
          ? StatusFilter.all
          : f;
    });
  }

  List<ReportItem> get _filteredReports {
    final now = DateTime.now();
    return _allReports.where((r) {
      if (!_matchesKpi(r)) return false;
      switch (_activeFilter) {
        case ReportFilter.all:
          return true;
        case ReportFilter.today:
          return r.dateReported.year == now.year &&
              r.dateReported.month == now.month &&
              r.dateReported.day == now.day;
        case ReportFilter.thisWeek:
          final start = DateTime(
            now.year,
            now.month,
            now.day,
          ).subtract(Duration(days: now.weekday - 1));
          return r.dateReported.isAfter(
            start.subtract(const Duration(seconds: 1)),
          );
        case ReportFilter.thisMonth:
          return r.dateReported.year == now.year &&
              r.dateReported.month == now.month;
        case ReportFilter.last3Months:
          return r.dateReported.isAfter(
            DateTime(now.year, now.month - 3, now.day),
          );
      }
    }).toList()..sort((a, b) => b.dateReported.compareTo(a.dateReported));
  }

  int get _totalCount => _allReports.length;
  int get _pendingCount => _allReports
      .where(
        (r) =>
            r.status == ReportStatus.pending ||
            r.status == ReportStatus.underReview ||
            r.status == ReportStatus.inProgress,
      )
      .length;
  int get _resolvedCount =>
      _allReports.where((r) => r.status == ReportStatus.resolved).length;
  int get _rejectedCount =>
      _allReports.where((r) => r.status == ReportStatus.rejected).length;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchReports();
    });
    _subscribe();
  }

  @override
  void dispose() {
    if (_channel != null) Supabase.instance.client.removeChannel(_channel!);
    _entryCtrl.dispose();
    super.dispose();
  }

  /// Live-refresh the list when the admin/staff move any of my reports.
  void _subscribe() {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    _channel = supabase
        .channel('my_reports:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'reports',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) => _silentRefresh(),
        )
        .subscribe();
  }

  Future<void> _silentRefresh() async {
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser!.id;
      final response = await supabase
          .from('reports')
          .select('*, report_media(id)')
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _allReports = (response as List<dynamic>)
            .map((e) => ReportItem.fromMap(e as Map<String, dynamic>))
            .toList();
      });
    } catch (_) {
      // Non-fatal — the next event or a manual pull-to-refresh will refresh.
    }
  }

  // ── Fetch ──────────────────────────────────────────────────────────────────

  Future<void> _fetchReports() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser!.id;

      final response = await supabase
          .from('reports')
          .select('*, report_media(id)')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      if (!mounted) return;

      final items = (response as List<dynamic>)
          .map((e) => ReportItem.fromMap(e as Map<String, dynamic>))
          .toList();

      setState(() {
        _allReports = items;
        _isLoading = false;
      });

      // Run entry animation after data loads
      _entryCtrl.forward(from: 0);
    } on PostgrestException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Something went wrong.';
          _isLoading = false;
        });
      }
    }
  }

  // ── Animation helper ───────────────────────────────────────────────────────

  Widget _animated(int i, Widget child) {
    final start = (i * 0.12).clamp(0.0, 1.0);
    final end = (start + 0.50).clamp(0.0, 1.0);
    return FadeTransition(
      opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _entryCtrl,
          curve: Interval(start, end, curve: Curves.easeOut),
        ),
      ),
      child: SlideTransition(
        position:
            Tween<Offset>(
              begin: const Offset(0.0, 0.30),
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

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    // WEB / large screens: a real multi-column dashboard that fills the width
    // instead of a stranded 480px phone column. Phones & narrow web fall through
    // to the original mobile body below, byte-for-byte unchanged.
    final bool wide = kIsWeb && width >= 900;
    final double w = wide ? 460.0 : width.clamp(0.0, 480.0);
    return ResponsiveNavScaffold(
      currentIndex: 1,
      username: widget.username,
      isVerified: true,
      backgroundColor: const Color(0xFFF3F4F6),
      body: SafeArea(
        child: wide
            ? LoadingOverlay.bodyOrSkeleton(
                isLoading: _isLoading,
                layout: SkeletonLayout.myReports,
                child: _buildWebBody(w),
              )
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    children: [
                      _buildTopBar(w),
                      Expanded(
                        child: LoadingOverlay.bodyOrSkeleton(
                          isLoading: _isLoading,
                          layout: SkeletonLayout.myReports,
                          child: _buildBody(w),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  // ── WEB body: header banner + KPI row + report card grid ───────────────────
  Widget _buildWebBody(double w) {
    final ww = w * 1.18;
    final reports = _filteredReports;
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1160),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 56),
            child: _error != null
                ? _buildBody(w)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildTopBar(w),
                      const SizedBox(height: 24),
                      _animated(1, _buildKpiRow(w)),
                      const SizedBox(height: 28),
                      _animated(2, _buildReportsHeaderWeb(w, ww, reports.length)),
                      const SizedBox(height: 16),
                      _animated(
                        3,
                        reports.isEmpty
                            ? _buildEmptyState(w)
                            : WebCardGrid(
                                targetColumnWidth: 520,
                                children: [
                                  for (final r in reports)
                                    _reportGridCard(w, ww, r),
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

  // Toolbar (title + count + filter chips) shown above the web report grid.
  Widget _buildReportsHeaderWeb(double w, double ww, int count) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Report History', style: _T.title(ww, color: _T.textPrimary)),
            const Spacer(),
            Text(
              '$count ${count == 1 ? 'report' : 'reports'}',
              style: _T.caption(ww, color: _T.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _filterChip(w, 'All', ReportFilter.all, Icons.list_rounded),
            _filterChip(w, 'Today', ReportFilter.today, Icons.wb_sunny_outlined),
            _filterChip(
              w,
              'This Week',
              ReportFilter.thisWeek,
              Icons.date_range_rounded,
            ),
            _filterChip(
              w,
              'This Month',
              ReportFilter.thisMonth,
              Icons.calendar_month_rounded,
            ),
            _filterChip(
              w,
              'Last 3 Months',
              ReportFilter.last3Months,
              Icons.calendar_today_rounded,
            ),
          ],
        ),
      ],
    );
  }

  // A single report rendered as a standalone web card (for the grid).
  Widget _reportGridCard(double w, double ww, ReportItem report) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: _buildReportTile(w, ww, report),
    );
  }

  Widget _buildBody(double w) {
    // ── Error ──
    if (_error != null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(w * .08),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_rounded,
                size: w * .18,
                color: _T.textDisabled,
              ),
              SizedBox(height: w * .04),
              Text(
                'Failed to load reports',
                style: _T.title(w, color: _T.textSecondary),
              ),
              SizedBox(height: w * .02),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: _T.body(w, color: _T.textTertiary),
              ),
              SizedBox(height: w * .05),
              ElevatedButton.icon(
                onPressed: _fetchReports,
                icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                label: const Text(
                  'Retry',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: EdgeInsets.symmetric(
                    horizontal: w * .06,
                    vertical: w * .035,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          SizedBox(height: w * .04),
          _animated(1, _buildKpiRow(w)),
          SizedBox(height: w * .04),
          _animated(2, _buildReportsSection(w, w * 1.18)),
          SizedBox(height: w * .06),
        ],
      ),
    );
  }
  // ── Top bar ────────────────────────────────────────────────────────────────

  Widget _buildTopBar(double w) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(w * .04, w * .04, w * .04, w * .04),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/images/newslogo.webp',
            height: w * .075,
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
            errorBuilder: (_, _, _) => Icon(
              Icons.account_balance_rounded,
              size: w * .065,
              color: AppColors.primaryBlue,
            ),
          ),
          SizedBox(height: w * .018),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'My Reports',
                      style: TextStyle(
                        fontSize: w * .058,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryBlue,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Track your submitted issues',
                      style: TextStyle(
                        fontSize: w * .030,
                        color: _T.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── KPI row ────────────────────────────────────────────────────────────────

  Widget _buildKpiRow(double w) {
    final ww = w * 1.18;
    // NOTE: No CrossAxisAlignment.stretch here. All labels are single words now,
    // so the four cards are naturally identical height. Adding `stretch` to a Row
    // inside a vertical SingleChildScrollView gives it unbounded height and throws
    // a layout error (which renders as a blank grey screen in release builds).
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * .04),
      child: Row(
        children: [
          Expanded(
            child: _kpiCard(
              w: w,
              ww: ww,
              icon: Icons.assignment_outlined,
              count: _totalCount,
              label: 'All',
              iconBg: const Color(0xFFEEF2FF),
              iconColor: AppColors.primaryBlue,
              valueColor: AppColors.primaryBlue,
              selected: _activeKpi == StatusFilter.all,
              onTap: () => _selectKpi(StatusFilter.all),
            ),
          ),
          SizedBox(width: w * .03),
          Expanded(
            child: _kpiCard(
              w: w,
              ww: ww,
              icon: Icons.access_time_rounded,
              count: _pendingCount,
              label: 'Pending',
              iconBg: const Color(0xFFFFF7ED),
              iconColor: const Color(0xFFD97706),
              valueColor: const Color(0xFFD97706),
              selected: _activeKpi == StatusFilter.pending,
              onTap: () => _selectKpi(StatusFilter.pending),
            ),
          ),
          SizedBox(width: w * .03),
          Expanded(
            child: _kpiCard(
              w: w,
              ww: ww,
              icon: Icons.check_circle_outline_rounded,
              count: _resolvedCount,
              label: 'Resolved',
              iconBg: const Color(0xFFECFDF5),
              iconColor: const Color(0xFF059669),
              valueColor: const Color(0xFF059669),
              selected: _activeKpi == StatusFilter.resolved,
              onTap: () => _selectKpi(StatusFilter.resolved),
            ),
          ),
          SizedBox(width: w * .03),
          Expanded(
            child: _kpiCard(
              w: w,
              ww: ww,
              icon: Icons.cancel_outlined,
              count: _rejectedCount,
              label: 'Rejected',
              iconBg: const Color(0xFFFEF2F2),
              iconColor: const Color(0xFFDC2626),
              valueColor: const Color(0xFFDC2626),
              selected: _activeKpi == StatusFilter.rejected,
              onTap: () => _selectKpi(StatusFilter.rejected),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpiCard({
    required double w,
    required double ww,
    required IconData icon,
    required int count,
    required String label,
    required Color iconBg,
    required Color iconColor,
    required Color valueColor,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
        padding: EdgeInsets.symmetric(horizontal: w * .025, vertical: w * .035),
        decoration: BoxDecoration(
          color: selected ? iconBg : Colors.white,
          borderRadius: BorderRadius.circular(w * .035),
          border: Border.all(
            color: selected ? iconColor : const Color(0xFFE5E7EB),
            width: selected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: selected
                  ? iconColor.withValues(alpha: .18)
                  : Colors.black.withValues(alpha: .04),
              blurRadius: selected ? 10 : 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: w * .092,
              height: w * .092,
              decoration: BoxDecoration(
                color: selected ? Colors.white : iconBg,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: _T.iconLG(ww), color: iconColor),
            ),
            SizedBox(height: w * .018),
            Text('$count', style: _T.heading(ww, color: valueColor)),
            SizedBox(height: w * .008),
            Text(
              label,
              textAlign: TextAlign.center,
              style: _T.label(
                ww,
                color: selected ? valueColor : _T.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Reports section ────────────────────────────────────────────────────────

  Widget _buildReportsSection(double w, double ww) {
    final reports = _filteredReports;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * .04),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(w * .04),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(w * .04, w * .04, w * .04, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Report History',
                    style: _T.title(ww, color: _T.textPrimary),
                  ),
                  Text(
                    '${reports.length} ${reports.length == 1 ? 'report' : 'reports'}',
                    style: _T.caption(ww, color: _T.textSecondary),
                  ),
                ],
              ),
            ),
            // Filter chips
            SizedBox(
              height: w * .14,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(
                  horizontal: w * .04,
                  vertical: w * .03,
                ),
                children: [
                  _filterChip(w, 'All', ReportFilter.all, Icons.list_rounded),
                  SizedBox(width: w * .02),
                  _filterChip(
                    w,
                    'Today',
                    ReportFilter.today,
                    Icons.wb_sunny_outlined,
                  ),
                  SizedBox(width: w * .02),
                  _filterChip(
                    w,
                    'This Week',
                    ReportFilter.thisWeek,
                    Icons.date_range_rounded,
                  ),
                  SizedBox(width: w * .02),
                  _filterChip(
                    w,
                    'This Month',
                    ReportFilter.thisMonth,
                    Icons.calendar_month_rounded,
                  ),
                  SizedBox(width: w * .02),
                  _filterChip(
                    w,
                    'Last 3 Months',
                    ReportFilter.last3Months,
                    Icons.calendar_today_rounded,
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE5E7EB)),
            // Smoothly animates the card's height when the filtered row count
            // changes, so the container glides instead of snapping/shaking.
            AnimatedSize(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              clipBehavior: Clip.hardEdge,
              child: reports.isEmpty
                  ? SizedBox(width: double.infinity, child: _buildEmptyState(w))
                  : ListView.separated(
                      // Key changes whenever the KPI or date filter changes,
                      // which remounts the rows and replays their slide-up.
                      key: ValueKey(
                        'list_${_activeKpi.index}_${_activeFilter.index}',
                      ),
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: reports.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, color: Color(0xFFE5E7EB)),
                      itemBuilder: (context, i) =>
                          _buildAnimatedTile(w, ww, reports[i], i),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedTile(double w, double ww, ReportItem report, int index) {
    final delaySteps = index.clamp(0, 6); // cap the cascade for long lists
    return TweenAnimationBuilder<double>(
      key: ValueKey(report.id),
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 300 + delaySteps * 45),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - t) * (w * .06)),
            child: child,
          ),
        );
      },
      child: _buildReportTile(w, ww, report),
    );
  }

  Widget _filterChip(
    double w,
    String label,
    ReportFilter filter,
    IconData icon,
  ) {
    final isActive = _activeFilter == filter;
    return GestureDetector(
      onTap: () => setState(() => _activeFilter = filter),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(horizontal: w * .040, vertical: w * .020),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primaryBlue : const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(w * .06),
          border: Border.all(
            color: isActive ? AppColors.primaryBlue : const Color(0xFFE5E7EB),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: _T.iconMD(w),
              color: isActive ? Colors.white : _T.textSecondary,
            ),
            SizedBox(width: w * .016),
            Text(
              label,
              style: _T.caption(
                w,
                color: isActive ? Colors.white : _T.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Report tile ────────────────────────────────────────────────────────────

  /// The row itself is [ReportCard] (report_card.dart). This wrapper stays so
  /// both call sites — the mobile list and the web grid — read as they did, and
  /// so the '/report_detail' push lives with the screen rather than inside a
  /// card the web shell will want to open without a route.
  Widget _buildReportTile(double w, double ww, ReportItem report) {
    return ReportCard(
      w: w,
      ww: ww,
      report: report,
      onTap: () {
        Navigator.pushNamed(
          context,
          '/report_detail',
          arguments: {'report': report, 'username': widget.username},
        );
      },
    );
  }

  // ── Empty state ────────────────────────────────────────────────────────────

  Widget _buildEmptyState(double w) {
    final noFiltersActive =
        _activeFilter == ReportFilter.all && _activeKpi == StatusFilter.all;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: w * .14, horizontal: w * .08),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, size: w * .18, color: _T.textDisabled),
          SizedBox(height: w * .05),
          Text('No Reports Found', style: _T.title(w, color: _T.textSecondary)),
          SizedBox(height: w * .018),
          Text(
            noFiltersActive
                ? 'You haven\'t submitted any reports yet.'
                : 'No reports match the selected filter.',
            textAlign: TextAlign.center,
            style: _T.body(w, color: _T.textTertiary),
          ),
        ],
      ),
    );
  }
}
