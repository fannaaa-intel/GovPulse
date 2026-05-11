import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/network/network_wrapper.dart';
import '../screen/home_screen.dart';

// ─── Typography & Icon Scale ──────────────────────────────────────────────────
//
//   FOCUSED SCALE (95% of UI):
//     title     w·.038  w700  — section headers, logo brand
//     subtitle  w·.032  w700  — card titles (category names)
//     body      w·.030  w500  — descriptions, location, remarks
//     caption   w·.028  w500  — filter chips, nav labels, counts
//     label     w·.026  w600  — dates, IDs, KPI labels
//     tiny      w·.022  w600  — status badges, anonymous tag
//
//   ANCHOR SIZE:
//     heading   w·.048  w800  — the KPI numbers
//     (page title now uses inline TextStyle matching Settings/Emergency)
//
//   KPI & REPORT HISTORY use a scaled-up `ww = w * 1.18` for bigger text
//   in just those two sections — everything else uses plain `w`.

class _T {
  // ── Anchors ──────────────────────────────────────────────────────────────
  static TextStyle heading(double w, {Color? color}) => TextStyle(
    fontSize: w * .048,
    fontWeight: FontWeight.w800,
    height: 1.0,
    color: color,
  );

  // ── Focused scale ────────────────────────────────────────────────────────
  static TextStyle title(double w, {Color? color}) => TextStyle(
    fontSize: w * .038,
    fontWeight: FontWeight.w700,
    height: 1.2,
    color: color,
  );

  static TextStyle subtitle(double w, {Color? color}) => TextStyle(
    fontSize: w * .032,
    fontWeight: FontWeight.w700,
    height: 1.3,
    color: color,
  );

  static TextStyle body(double w, {Color? color}) => TextStyle(
    fontSize: w * .030,
    fontWeight: FontWeight.w500,
    height: 1.4,
    color: color,
  );

  static TextStyle caption(double w, {Color? color}) => TextStyle(
    fontSize: w * .028,
    fontWeight: FontWeight.w500,
    height: 1.3,
    color: color,
  );

  static TextStyle label(double w, {Color? color}) => TextStyle(
    fontSize: w * .026,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: color,
  );

  static TextStyle tiny(double w, {Color? color}) => TextStyle(
    fontSize: w * .022,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: color,
  );

  // ── Icon scale ───────────────────────────────────────────────────────────
  static double iconXL(double w) => w * .065; // nav, logo fallback
  static double iconLG(double w) => w * .046; // card icons (KPI, category)
  static double iconMD(double w) => w * .034; // inline icons in body rows
  static double iconSM(double w) => w * .028; // small inline icons (dates)
  static double iconXS(double w) => w * .022; // micro (badges)

  // ── Text colors ──────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF1F2937);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textTertiary = Color(0xFF9CA3AF);
  static const Color textDisabled = Color(0xFFD1D5DB);
}

// ─── Sample data model ────────────────────────────────────────────────────────

enum ReportStatus { pending, underReview, resolved, rejected }

class ReportItem {
  final String id;
  final String category;
  final String categoryKey;
  final String location;
  final String remarks;
  final ReportStatus status;
  final DateTime dateReported;
  final bool isAnonymous;

  const ReportItem({
    required this.id,
    required this.category,
    required this.categoryKey,
    required this.location,
    required this.remarks,
    required this.status,
    required this.dateReported,
    this.isAnonymous = false,
  });
}

// ─── Dummy data (replace with real API data) ──────────────────────────────────

final List<ReportItem> _dummyReports = [
  ReportItem(
    id: 'RPT-001',
    category: 'Road & Infrastructure',
    categoryKey: 'road',
    location: 'Brgy. Aparri Centro, Aparri',
    remarks:
        'Large pothole on the main road causing danger to motorcycles and vehicles passing through.',
    status: ReportStatus.pending,
    dateReported: DateTime.now().subtract(const Duration(hours: 3)),
  ),
  ReportItem(
    id: 'RPT-002',
    category: 'Waste & Garbage',
    categoryKey: 'waste',
    location: 'Brgy. Maura, Aparri',
    remarks:
        'Uncollected garbage pile near the market area. It has been there for 3 days already.',
    status: ReportStatus.resolved,
    dateReported: DateTime.now().subtract(const Duration(days: 2)),
  ),
  ReportItem(
    id: 'RPT-003',
    category: 'Drainage & Flooding',
    categoryKey: 'drainage',
    location: 'Brgy. Punta, Aparri',
    remarks:
        'Clogged drainage causing minor flooding every time it rains heavily.',
    status: ReportStatus.underReview,
    dateReported: DateTime.now().subtract(const Duration(days: 5)),
  ),
  ReportItem(
    id: 'RPT-004',
    category: 'Streetlight Outage',
    categoryKey: 'streetlight',
    location: 'Brgy. San Antonio, Aparri',
    remarks: 'Three consecutive streetlights are not functioning for 2 weeks.',
    status: ReportStatus.resolved,
    dateReported: DateTime.now().subtract(const Duration(days: 10)),
  ),
  ReportItem(
    id: 'RPT-005',
    category: 'Environment & Pollution',
    categoryKey: 'environment',
    location: 'Brgy. Fugu, Aparri',
    remarks:
        'Illegal burning of trash near the residential area causing air pollution.',
    status: ReportStatus.rejected,
    dateReported: DateTime.now().subtract(const Duration(days: 20)),
    isAnonymous: true,
  ),
  ReportItem(
    id: 'RPT-006',
    category: 'Road & Infrastructure',
    categoryKey: 'road',
    location: 'Brgy. Caagaman, Aparri',
    remarks: 'Broken bridge railing on the old bridge near the barangay hall.',
    status: ReportStatus.pending,
    dateReported: DateTime.now().subtract(const Duration(days: 25)),
  ),
  ReportItem(
    id: 'RPT-007',
    category: 'Waste & Garbage',
    categoryKey: 'waste',
    location: 'Brgy. Abagatan, Aparri',
    remarks: 'Open dumpsite near the school is a health hazard for the kids.',
    status: ReportStatus.resolved,
    dateReported: DateTime.now().subtract(const Duration(days: 45)),
    isAnonymous: true,
  ),
  ReportItem(
    id: 'RPT-008',
    category: 'Others',
    categoryKey: 'others',
    location: 'Brgy. Minanga Norte, Aparri',
    remarks: 'Stray dogs near the market are becoming a safety concern.',
    status: ReportStatus.pending,
    dateReported: DateTime.now().subtract(const Duration(days: 60)),
  ),
];

// ─── Filter enum ──────────────────────────────────────────────────────────────

enum ReportFilter { all, today, thisWeek, thisMonth, last3Months }

// ─────────────────────────────────────────────────────────────────────────────

class MyReportsScreen extends StatefulWidget {
  final String username;
  const MyReportsScreen({super.key, required this.username});

  @override
  State<MyReportsScreen> createState() => _MyReportsScreenState();
}

class _MyReportsScreenState extends State<MyReportsScreen>
    with TickerProviderStateMixin {
  static const int _navIndex = 1;

  late final AnimationController _entryCtrl;
  ReportFilter _activeFilter = ReportFilter.all;

  List<ReportItem> get _allReports => _dummyReports;

  List<ReportItem> get _filteredReports {
    final now = DateTime.now();
    return _allReports.where((r) {
      switch (_activeFilter) {
        case ReportFilter.all:
          return true;
        case ReportFilter.today:
          return r.dateReported.year == now.year &&
              r.dateReported.month == now.month &&
              r.dateReported.day == now.day;
        case ReportFilter.thisWeek:
          final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
          final start = DateTime(
            startOfWeek.year,
            startOfWeek.month,
            startOfWeek.day,
          );
          return r.dateReported.isAfter(
            start.subtract(const Duration(seconds: 1)),
          );
        case ReportFilter.thisMonth:
          return r.dateReported.year == now.year &&
              r.dateReported.month == now.month;
        case ReportFilter.last3Months:
          final cutoff = DateTime(now.year, now.month - 3, now.day);
          return r.dateReported.isAfter(cutoff);
      }
    }).toList()..sort((a, b) => b.dateReported.compareTo(a.dateReported));
  }

  int get _totalCount => _allReports.length;
  int get _pendingCount => _allReports
      .where(
        (r) =>
            r.status == ReportStatus.pending ||
            r.status == ReportStatus.underReview,
      )
      .length;
  int get _resolvedCount =>
      _allReports.where((r) => r.status == ReportStatus.resolved).length;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 80), () {
        if (mounted) _entryCtrl.forward();
      });
    });
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    super.dispose();
  }

  Widget _animated(int i, Widget child) {
    final start = (i * 0.12).clamp(0.0, 1.0);
    final end = (start + 0.50).clamp(0.0, 1.0);
    final fade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entryCtrl,
        curve: Interval(start, end, curve: Curves.easeOut),
      ),
    );
    final slide =
        Tween<Offset>(begin: const Offset(0.0, 0.30), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _entryCtrl,
            curve: Interval(start, end, curve: Curves.easeOutCubic),
          ),
        );
    return FadeTransition(
      opacity: fade,
      child: SlideTransition(position: slide, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: SafeArea(
        child: Column(
          children: [
            _animated(0, _buildTopBar(w)),
            Expanded(
              child: SingleChildScrollView(
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
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(w),
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
            'assets/images/newslogo.png',
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
            style: TextStyle(fontSize: w * .030, color: _T.textSecondary),
          ),
        ],
      ),
    );
  }

  // ── KPI row ────────────────────────────────────────────────────────────────

  Widget _buildKpiRow(double w) {
    final ww = w * 1.18;
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
              label: 'All Reports',
              iconBg: const Color(0xFFEEF2FF),
              iconColor: AppColors.primaryBlue,
              valueColor: AppColors.primaryBlue,
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
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: w * .025, vertical: w * .035),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(w * .035),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: w * .092,
            height: w * .092,
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(icon, size: _T.iconLG(ww), color: iconColor),
          ),
          SizedBox(height: w * .018),
          Text('$count', style: _T.heading(ww, color: valueColor)),
          SizedBox(height: w * .008),
          Text(
            label,
            textAlign: TextAlign.center,
            style: _T.label(ww, color: _T.textSecondary),
          ),
        ],
      ),
    );
  }

  // ── Reports section (filter + list) ───────────────────────────────────────

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

            reports.isEmpty
                ? _buildEmptyState(w)
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: reports.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, color: Color(0xFFE5E7EB)),
                    itemBuilder: (context, i) =>
                        _buildReportTile(w, ww, reports[i]),
                  ),
          ],
        ),
      ),
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

  // ── Report tile ─────────────────────────────────────────────────────────────

  Widget _buildReportTile(double w, double ww, ReportItem report) {
    // ── icon size shared by both the SizedBox and Image so they stay in sync
    final double iconSize = _T.iconLG(ww);

    return InkWell(
      onTap: () {
        // TODO: navigate to report detail screen
      },
      child: Padding(
        padding: EdgeInsets.all(w * .04),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: category image + name + status badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── CHANGED: plain Image.asset, no background container ──
                SizedBox(
                  width: iconSize,
                  height: iconSize,
                  child: Image.asset(
                    _categoryImagePath(report.categoryKey),
                    width: iconSize,
                    height: iconSize,
                    fit: BoxFit.contain,
                  ),
                ),
                SizedBox(width: w * .03),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        report.category,
                        style: _T.subtitle(ww, color: _T.textPrimary),
                      ),
                      SizedBox(height: w * .007),
                      Row(
                        children: [
                          Text(
                            report.id,
                            style: _T.label(ww, color: _T.textTertiary),
                          ),
                          if (report.isAnonymous) ...[
                            SizedBox(width: w * .018),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: w * .020,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3F4F6),
                                borderRadius: BorderRadius.circular(w * .04),
                                border: Border.all(
                                  color: const Color(0xFFE5E7EB),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.lock_outline_rounded,
                                    size: _T.iconXS(ww),
                                    color: _T.textSecondary,
                                  ),
                                  SizedBox(width: w * .010),
                                  Text(
                                    'Anonymous',
                                    style: _T.tiny(ww, color: _T.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                _buildStatusBadge(w, ww, report.status),
              ],
            ),

            SizedBox(height: w * .025),

            // Row 2: location
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: _T.iconMD(ww),
                  color: _T.textTertiary,
                ),
                SizedBox(width: w * .015),
                Expanded(
                  child: Text(
                    report.location,
                    style: _T.body(ww, color: _T.textSecondary),
                  ),
                ),
              ],
            ),

            SizedBox(height: w * .015),

            // Row 3: remarks preview
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.notes_rounded,
                  size: _T.iconMD(ww),
                  color: _T.textTertiary,
                ),
                SizedBox(width: w * .015),
                Expanded(
                  child: Text(
                    report.remarks,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _T.body(ww, color: _T.textSecondary),
                  ),
                ),
              ],
            ),

            SizedBox(height: w * .02),

            // Row 4: date
            Row(
              children: [
                Icon(
                  Icons.calendar_today_rounded,
                  size: _T.iconSM(ww),
                  color: _T.textDisabled,
                ),
                SizedBox(width: w * .015),
                Text(
                  _formatDate(report.dateReported),
                  style: _T.label(ww, color: _T.textDisabled),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(double w, double ww, ReportStatus status) {
    final cfg = _statusConfig(status);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: w * .025, vertical: w * .010),
      decoration: BoxDecoration(
        color: cfg['bg'] as Color,
        borderRadius: BorderRadius.circular(w * .04),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: w * .016,
            height: w * .016,
            decoration: BoxDecoration(
              color: cfg['dot'] as Color,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: w * .012),
          Text(
            cfg['label'] as String,
            style: _T.tiny(ww, color: cfg['text'] as Color),
          ),
        ],
      ),
    );
  }

  // ── Empty state ────────────────────────────────────────────────────────────

  Widget _buildEmptyState(double w) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: w * .14, horizontal: w * .08),
      child: Column(
        children: [
          Icon(Icons.inbox_outlined, size: w * .18, color: _T.textDisabled),
          SizedBox(height: w * .05),
          Text('No Reports Found', style: _T.title(w, color: _T.textSecondary)),
          SizedBox(height: w * .018),
          Text(
            'No reports match the selected filter.',
            textAlign: TextAlign.center,
            style: _T.body(w, color: _T.textTertiary),
          ),
        ],
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  // Maps categoryKey → asset path
  String _categoryImagePath(String key) {
    switch (key) {
      case 'road':
        return 'assets/images/report/roadtwo.png';
      case 'waste':
        return 'assets/images/report/bin.png';
      case 'drainage':
        return 'assets/images/report/road.png';
      case 'streetlight':
        return 'assets/images/report/lamppost.png';
      case 'environment':
        return 'assets/images/report/leaf.png';
      default:
        return 'assets/images/report/menu.png';
    }
  }

  Map<String, dynamic> _statusConfig(ReportStatus status) {
    switch (status) {
      case ReportStatus.pending:
        return {
          'label': 'Pending',
          'bg': const Color(0xFFFFF7ED),
          'text': const Color(0xFFB45309),
          'dot': const Color(0xFFD97706),
        };
      case ReportStatus.underReview:
        return {
          'label': 'Under Review',
          'bg': const Color(0xFFEEF2FF),
          'text': const Color(0xFF3730A3),
          'dot': const Color(0xFF6366F1),
        };
      case ReportStatus.resolved:
        return {
          'label': 'Resolved',
          'bg': const Color(0xFFECFDF5),
          'text': const Color(0xFF047857),
          'dot': const Color(0xFF059669),
        };
      case ReportStatus.rejected:
        return {
          'label': 'Rejected',
          'bg': const Color(0xFFFEF2F2),
          'text': const Color(0xFFB91C1C),
          'dot': const Color(0xFFEF4444),
        };
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';

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
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  // ── Bottom nav ─────────────────────────────────────────────────────────────

  Widget _buildBottomNav(double w) {
    final sz = _T.iconXL(w);

    Widget ico(String path, bool active) => SizedBox(
      width: sz,
      height: sz,
      child: ColorFiltered(
        colorFilter: ColorFilter.mode(
          active ? AppColors.primaryBlue : _T.textTertiary,
          BlendMode.srcIn,
        ),
        child: Image.asset(path),
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .07),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        elevation: 0,
        currentIndex: _navIndex,
        selectedItemColor: AppColors.primaryBlue,
        unselectedItemColor: _T.textTertiary,
        selectedFontSize: w * .028,
        unselectedFontSize: w * .028,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
        onTap: (i) {
          if (i == _navIndex) return;
          if (i == 0) {
            Navigator.pushAndRemoveUntil(
              context,
              PageRouteBuilder(
                transitionDuration: const Duration(milliseconds: 400),
                pageBuilder: (_, _, _) =>
                    NetworkWrapper(child: HomePage(username: widget.username)),
                transitionsBuilder: (_, anim, _, child) => SlideTransition(
                  position: Tween(begin: const Offset(-1, 0), end: Offset.zero)
                      .animate(
                        CurvedAnimation(parent: anim, curve: Curves.easeInOut),
                      ),
                  child: child,
                ),
              ),
              (r) => false,
            );
          } else if (i == 2) {
            Navigator.pushNamed(
              context,
              '/newsfeed',
              arguments: {'username': widget.username, 'isVerified': true},
            );
          } else if (i == 3) {
            Navigator.pushNamed(
              context,
              '/emergency',
              arguments: {'username': widget.username, 'isVerified': true},
            );
          } else if (i == 4) {
            Navigator.pushNamed(
              context,
              '/settings',
              arguments: widget.username,
            );
          }
        },
        items: [
          BottomNavigationBarItem(
            icon: ico('assets/images/home.png', _navIndex == 0),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: ico('assets/images/my_reports.png', _navIndex == 1),
            label: 'My Reports',
          ),
          BottomNavigationBarItem(
            icon: ico('assets/images/news_feed.png', _navIndex == 2),
            label: 'NewsFeed',
          ),
          BottomNavigationBarItem(
            icon: ico('assets/images/emergency.png', _navIndex == 3),
            label: 'Emergency',
          ),
          BottomNavigationBarItem(
            icon: ico('assets/images/settings.png', _navIndex == 4),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
