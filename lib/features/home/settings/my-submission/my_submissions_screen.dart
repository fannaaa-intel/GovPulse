import 'package:flutter/material.dart';
import '../../../../core/widgets/responsive_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/loading/loading_overlay.dart';
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
  final DateTime createdAt;
  final bool isAnonymous;

  const _Suggestion({
    required this.id,
    required this.category,
    this.categoryOther,
    this.details,
    required this.createdAt,
    this.isAnonymous = false,
  });

  factory _Suggestion.fromJson(Map<String, dynamic> j) => _Suggestion(
    id: j['id'] as String,
    category: j['category'] as String,
    categoryOther: j['category_other'] as String?,
    details: j['details'] as String?,
    createdAt: DateTime.parse(j['created_at'] as String),
    isAnonymous: (j['is_anonymous'] as bool?) ?? false,
  );
}

class _Feedback {
  final String id;
  final String officeId;
  final String officeLabel;
  final String serviceName;
  final int rating;
  final DateTime visitDate;
  final String? comment;
  final bool isAnonymous;

  const _Feedback({
    required this.id,
    required this.officeId,
    required this.officeLabel,
    required this.serviceName,
    required this.rating,
    required this.visitDate,
    this.comment,
    this.isAnonymous = false,
  });

  factory _Feedback.fromJson(Map<String, dynamic> j) => _Feedback(
    id: j['id'] as String,
    officeId: j['office_id'] as String,
    officeLabel: j['office_label'] as String,
    serviceName: j['service_name'] as String,
    rating: j['overall_rating'] as int,
    visitDate: DateTime.parse(j['visit_date'] as String),
    comment: j['comment'] as String?,
    isAnonymous: (j['is_anonymous'] as bool?) ?? false,
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class MySubmissionsScreen extends StatefulWidget {
  final String username;
  const MySubmissionsScreen({super.key, required this.username});

  @override
  State<MySubmissionsScreen> createState() => _MySubmissionsScreenState();
}

class _MySubmissionsScreenState extends State<MySubmissionsScreen>
    with TickerProviderStateMixin {
  // ── Animation ──────────────────────────────────────────────────────────────
  late final AnimationController _slideCtrl;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;
  late final AnimationController _shimmerCtrl;

  // ── Tab & filter state ─────────────────────────────────────────────────────
  int _tab = 0; // 0 = Reports, 1 = Suggestions, 2 = Feedback
  String _filter = 'all'; // all | pending | in_progress | resolved

  // ── Data ───────────────────────────────────────────────────────────────────
  List<_Report> _reports = [];
  List<_Suggestion> _suggestions = [];
  List<_Feedback> _feedbacks = [];

  // ── Fetch state ────────────────────────────────────────────────────────────
  bool _loading = true;
  bool _hasError = false;

  // ── Report categories — matches report_issue_screen.dart assets ─────────────
  static const Map<String, _CatCfg> _reportCats = {
    'road': _CatCfg(
      'assets/images/report/roadtwo.webp',
      Color(0xFF3B82F6),
      'Road &\nInfra',
    ),
    'waste': _CatCfg(
      'assets/images/report/bin.webp',
      Color(0xFFEF4444),
      'Waste &\nGarbage',
    ),
    'drainage': _CatCfg(
      'assets/images/report/road.webp',
      Color(0xFF06B6D4),
      'Drainage &\nFlooding',
    ),
    'streetlight': _CatCfg(
      'assets/images/report/lamppost.webp',
      Color(0xFFF59E0B),
      'Streetlight\nOutage',
    ),
    'environment': _CatCfg(
      'assets/images/report/leaf.webp',
      Color(0xFF10B981),
      'Environment\n& Pollution',
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
      'Public\nService',
    ),
    'community_program': _CatCfg(
      'assets/images/suggestion/group.webp',
      Color(0xFF8B5CF6),
      'Community\nProgram',
    ),
    'health_safety': _CatCfg(
      'assets/images/suggestion/health.webp',
      Color(0xFFEF4444),
      'Health &\nSafety',
    ),
    'infrastructure': _CatCfg(
      'assets/images/suggestion/building.webp',
      Color(0xFFF59E0B),
      'Infra-\nstructure',
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
      'Health\nOffice',
    ),
    'mayor': _OfficeCfg(
      Icons.account_balance_rounded,
      Color(0xFF1D4ED8),
      "Mayor's\nOffice",
    ),
    'mpdo': _OfficeCfg(Icons.map_rounded, Color(0xFF10B981), 'Planning &\nDev'),
    'civil': _OfficeCfg(
      Icons.assignment_rounded,
      Color(0xFFF59E0B),
      'Civil\nRegistrar',
    ),
    'cert': _OfficeCfg(
      Icons.task_alt_rounded,
      Color(0xFF8B5CF6),
      'Certificate\nVerif.',
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
    _slideCtrl.dispose();
    _shimmerCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DATA
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _fetchAll() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
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

      final results = await Future.wait([
        supabase
            .from('reports')
            .select(
              'id, category, category_other, barangay, remarks, status, created_at, is_anonymous, report_media(id)',
            )
            .eq('user_id', userId)
            .order('created_at', ascending: false),
        supabase
            .from('suggestions')
            .select(
              'id, category, category_other, details, created_at, is_anonymous',
            )
            .eq('user_id', userId)
            .order('created_at', ascending: false),
        supabase
            .from('feedbacks')
            .select(
              'id, office_id, office_label, service_name, overall_rating, visit_date, comment, is_anonymous',
            )
            .eq('user_id', userId)
            .order('visit_date', ascending: false),
      ]);

      if (!mounted) return;
      setState(() {
        _reports = (results[0] as List<dynamic>)
            .map((e) => _Report.fromJson(e as Map<String, dynamic>))
            .toList();
        _suggestions = (results[1] as List<dynamic>)
            .map((e) => _Suggestion.fromJson(e as Map<String, dynamic>))
            .toList();
        _feedbacks = (results[2] as List<dynamic>)
            .map((e) => _Feedback.fromJson(e as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _hasError = true;
        });
      }
    }
  }

  // ── Filtered reports list ──────────────────────────────────────────────────
  List<_Report> get _filteredReports {
    if (_filter == 'all') return _reports;
    return _reports.where((r) => r.status == _filter).toList();
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
    final w = MediaQuery.of(context).size.width.clamp(0.0, 480.0);
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: ResponsivePageBody(
        maxWidth: 760,
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
                        // Filter chips — Reports tab only
                        if (_tab == 0 && !_loading && !_hasError)
                          _buildFilterChips(w),
                        Expanded(
                          child: _loading
                              ? const MySubmissionsBodySkeleton()
                              : _hasError
                              ? _buildError(w)
                              : _buildContent(w),
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
                border: Border.all(color: AppColors.stroke),
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
                  onTap: () => setState(() {
                    _tab = i;
                    if (i != 0) _filter = 'all';
                  }),
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
          Divider(height: 1, color: AppColors.stroke),
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

  Widget _buildReportsList(double w) {
    final list = _filteredReports;
    if (list.isEmpty) {
      return _buildEmpty(
        w,
        icon: Icons.report_outlined,
        title: 'No reports found',
        subtitle: _filter != 'all'
            ? 'No reports with this status.'
            : 'You have not submitted any reports yet.',
      );
    }
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(w * 0.04, w * 0.025, w * 0.04, w * 0.08),
      itemCount: list.length,
      itemBuilder: (_, i) => _buildReportCard(w, list[i]),
    );
  }

  Widget _buildSuggestionsList(double w) {
    if (_suggestions.isEmpty) {
      return _buildEmpty(
        w,
        icon: Icons.lightbulb_outline_rounded,
        title: 'No suggestions found',
        subtitle: 'You have not submitted any suggestions yet.',
      );
    }
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(w * 0.04, w * 0.025, w * 0.04, w * 0.08),
      itemCount: _suggestions.length,
      itemBuilder: (_, i) => _buildSuggestionCard(w, _suggestions[i]),
    );
  }

  Widget _buildFeedbackList(double w) {
    if (_feedbacks.isEmpty) {
      return _buildEmpty(
        w,
        icon: Icons.star_outline_rounded,
        title: 'No feedback found',
        subtitle: 'You have not submitted any feedback yet.',
      );
    }
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(w * 0.04, w * 0.025, w * 0.04, w * 0.08),
      itemCount: _feedbacks.length,
      itemBuilder: (_, i) => _buildFeedbackCard(w, _feedbacks[i]),
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

    return Container(
      margin: EdgeInsets.only(bottom: w * 0.03),
      padding: EdgeInsets.all(w * 0.035),
      decoration: _cardDecoration(w),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Category icon tile — Section 1 grid-cell style
          _buildCatTile(w, asset: cat.asset, color: cat.color, label: label),
          SizedBox(width: w * 0.03),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Location row + status badge
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (r.barangay != null && r.barangay!.isNotEmpty) ...[
                      Icon(
                        Icons.location_on_outlined,
                        size: w * 0.033,
                        color: const Color(0xFF9CA3AF),
                      ),
                      SizedBox(width: w * 0.01),
                      Expanded(
                        child: Text(
                          r.barangay!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: w * 0.03,
                            color: const Color(0xFF6B7280),
                          ),
                        ),
                      ),
                    ] else
                      const Spacer(),
                    SizedBox(width: w * 0.015),
                    _buildStatusBadge(w, status),
                  ],
                ),
                // Remarks
                if (r.remarks != null && r.remarks!.isNotEmpty) ...[
                  SizedBox(height: w * 0.015),
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
                SizedBox(height: w * 0.015),
                // Date + attachment count — wraps so it never overflows
                Wrap(
                  spacing: w * 0.02,
                  runSpacing: w * 0.012,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.calendar_today_outlined,
                          size: w * 0.03,
                          color: const Color(0xFF9CA3AF),
                        ),
                        SizedBox(width: w * 0.01),
                        Text(
                          _fmt(r.createdAt),
                          style: TextStyle(
                            fontSize: w * 0.028,
                            color: const Color(0xFF9CA3AF),
                          ),
                        ),
                      ],
                    ),
                    if (r.mediaCount > 0)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.attach_file_rounded,
                            size: w * 0.03,
                            color: const Color(0xFF9CA3AF),
                          ),
                          SizedBox(width: w * 0.008),
                          Text(
                            '${r.mediaCount} ${r.mediaCount == 1 ? 'file' : 'files'}',
                            style: TextStyle(
                              fontSize: w * 0.028,
                              color: const Color(0xFF9CA3AF),
                            ),
                          ),
                        ],
                      ),
                    // Anonymous indicator sits inline and wraps if needed
                    if (r.isAnonymous) _buildAnonBadge(w),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
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

    return Container(
      margin: EdgeInsets.only(bottom: w * 0.03),
      padding: EdgeInsets.all(w * 0.035),
      decoration: _cardDecoration(w),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCatTile(w, asset: cat.asset, color: cat.color, label: label),
          SizedBox(width: w * 0.03),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Date row + anonymous indicator — wraps so it never overflows
                Wrap(
                  spacing: w * 0.02,
                  runSpacing: w * 0.012,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.calendar_today_outlined,
                          size: w * 0.03,
                          color: const Color(0xFF9CA3AF),
                        ),
                        SizedBox(width: w * 0.01),
                        Text(
                          _fmt(s.createdAt),
                          style: TextStyle(
                            fontSize: w * 0.028,
                            color: const Color(0xFF9CA3AF),
                          ),
                        ),
                      ],
                    ),
                    if (s.isAnonymous) _buildAnonBadge(w),
                  ],
                ),
                // Details
                if (s.details != null && s.details!.isNotEmpty) ...[
                  SizedBox(height: w * 0.015),
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FEEDBACK CARD — no status badge; star rating instead
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildFeedbackCard(double w, _Feedback f) {
    final office = _officeCfg[f.officeId];

    return Container(
      margin: EdgeInsets.only(bottom: w * 0.03),
      padding: EdgeInsets.all(w * 0.035),
      decoration: _cardDecoration(w),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildOfficeTile(w, f, office),
          SizedBox(width: w * 0.03),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title row: office name + anonymous badge top-right.
                // Identity info (name + anon status) is grouped together so the
                // badge never crowds the rating row below.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        f.officeLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: w * 0.033,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1F2937),
                          height: 1.2,
                        ),
                      ),
                    ),
                    if (f.isAnonymous) ...[
                      SizedBox(width: w * 0.02),
                      _buildAnonBadge(w),
                    ],
                  ],
                ),
                SizedBox(height: w * 0.014),
                // Stars + date — single clean row, no badge crowding
                Row(
                  children: [
                    _buildStars(w, f.rating),
                    SizedBox(width: w * 0.022),
                    Icon(
                      Icons.calendar_today_outlined,
                      size: w * 0.03,
                      color: const Color(0xFF9CA3AF),
                    ),
                    SizedBox(width: w * 0.01),
                    Expanded(
                      child: Text(
                        _fmt(f.visitDate),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: w * 0.028,
                          color: const Color(0xFF9CA3AF),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: w * 0.01),
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
                // Comment
                if (f.comment != null && f.comment!.isNotEmpty) ...[
                  SizedBox(height: w * 0.012),
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CATEGORY ICON TILE — mirrors Section 1 grid-cell style exactly
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildCatTile(
    double w, {
    required String asset,
    required Color color,
    required String label,
  }) {
    final size = w * 0.12;
    // Caption box is a bit wider than the icon so long words (e.g. custom
    // "Others" text) break/ellipsis cleanly instead of snapping mid-word.
    final labelWidth = size + w * 0.05;
    return SizedBox(
      width: labelWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
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
              borderRadius: BorderRadius.circular(w * 0.038),
              border: Border.all(color: color.withValues(alpha: 0.22)),
            ),
            child: Padding(
              padding: EdgeInsets.all(w * 0.025),
              // Icons display with their natural colors, on a soft tint of the
              // category color so each card reads vibrant but stays legible.
              child: Image.asset(
                asset,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Icon(
                  Icons.category_rounded,
                  size: size * 0.48,
                  color: color,
                ),
              ),
            ),
          ),
          SizedBox(height: w * 0.012),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            softWrap: true,
            style: TextStyle(
              fontSize: w * 0.021,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF374151),
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }

  // ── Office icon tile (icon-based, same dimensions as _buildCatTile) ─────────
  Widget _buildOfficeTile(double w, _Feedback f, _OfficeCfg? office) {
    final size = w * 0.12;
    final labelWidth = size + w * 0.05;
    final color = office?.color ?? AppColors.primaryBlue;
    final icon = office?.icon ?? Icons.business_rounded;
    final label = office?.label ?? f.officeId;

    return SizedBox(
      width: labelWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
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
              borderRadius: BorderRadius.circular(w * 0.038),
              border: Border.all(color: color.withValues(alpha: 0.22)),
            ),
            child: Icon(icon, size: size * 0.48, color: color),
          ),
          SizedBox(height: w * 0.012),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            softWrap: true,
            style: TextStyle(
              fontSize: w * 0.021,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF374151),
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SHARED WIDGETS
  // ─────────────────────────────────────────────────────────────────────────

  // ── Anonymous indicator pill ────────────────────────────────────────────────
  Widget _buildAnonBadge(double w) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: w * 0.02, vertical: w * 0.008),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(w * 0.05),
        border: Border.all(color: const Color(0xFFE5E7EB)),
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
}
