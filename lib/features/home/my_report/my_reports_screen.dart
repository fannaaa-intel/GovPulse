import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/router/legacy_nav.dart';
import '../../../core/widgets/Home/nav/responsive_nav_scaffold.dart';
import '../../../../core/widgets/loading/loading_overlay.dart';
import '../../../core/widgets/web/web_card_grid.dart';
import '../../../core/providers/user_profile_provider.dart';
import 'report_card.dart';
import '../../../core/theme/citizen_ui.dart';
import '../../../core/widgets/Home/Account/account_web_kit.dart';
import '../../../core/theme/mobile_metrics.dart';

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

/// Standalone My Reports page — the route the mobile app and the live web
/// routes open. Owns the nav chrome; the content is [MyReportsBody].
class MyReportsScreen extends StatelessWidget {
  final String username;
  const MyReportsScreen({super.key, required this.username});

  @override
  Widget build(BuildContext context) {
    return ResponsiveNavScaffold(
      currentIndex: 1,
      username: username,
      isVerified: true,
      backgroundColor: const Color(0xFFF3F4F6),
      body: const SafeArea(child: MyReportsBody()),
    );
  }
}

/// My Reports content, with no chrome of its own — no Scaffold, no nav, no
/// page background. Rendered inside [MyReportsScreen] on mobile and directly
/// as a centre pane by the citizen web shell.
///
/// Takes no `username`: identity comes from [userProfileProvider], which is what
/// lets the shell mount it without first resolving a name to hand down.
class MyReportsBody extends ConsumerStatefulWidget {
  /// Open one report. Null (the standalone screen, and the mobile app) falls
  /// back to the legacy '/report_detail' push.
  ///
  /// The shell passes a callback instead so the detail lands on ITS branch
  /// navigator — stacking over the My Reports pane rather than over the whole
  /// shell, and leaving the other tabs untouched. Keeping it a callback is what
  /// stops the body from having to know which router it is running under.
  final void Function(ReportItem report)? onOpenReport;

  const MyReportsBody({super.key, this.onOpenReport});

  @override
  ConsumerState<MyReportsBody> createState() => _MyReportsBodyState();
}

class _MyReportsBodyState extends ConsumerState<MyReportsBody>
    with TickerProviderStateMixin {
  /// Account handle, from the shared profile. Used only to hand the report
  /// detail route the name it still expects.
  String get _username =>
      ref.read(userProfileProvider).valueOrNull?.username ?? '';

  /// Opacity the staggered entrance starts from ON WEB, so the first painted
  /// frame already shows content. Mobile still fades from zero. Same value the
  /// auth screens and the feed use — same problem, same floor.
  ///
  /// This body is a shell BRANCH, which is why it needs one. Branches are built
  /// lazily (StatefulShellBranch.preload is false by default) and the shell
  /// swaps them with a plain IndexedStack — no page transition — so on the first
  /// visit there is no outgoing page for the web cross-fade to hold underneath.
  /// An entrance starting at zero therefore leaves the pane empty until the
  /// controller runs. Page-to-page navigation is already covered and needs no
  /// floor; only the first build of a branch is exposed.
  static const double _kWebFadeFloor = 0.35;

  /// Widest the web page's content band ever gets, gutters included.
  ///
  /// It was 1160 — a 1112 content column, against the 816 My Submissions gives
  /// the same records and the 722 the detail page gave them. Opening a card
  /// therefore shrank the page by 390px. [kAccountMaxWidth] with a
  /// [kAccountPageGutter] each side is 816, which every one of those pages now
  /// lands on, so moving between them moves nothing.
  ///
  /// The card grid's target column width came down with it — see the grid
  /// itself. At 816 a 520 target would have floored to ONE column.
  static const double _kWebMaxBand = kAccountMaxWidth;

  /// Content band at or below which the web page renders the MOBILE app's
  /// arrangement instead of the desktop one.
  ///
  /// 620 is where the desktop layout stops paying for itself, measured rather
  /// than guessed. The five date chips need ~600px to sit on one `Wrap` line at
  /// the desktop type size, so below that they start stacking — three rows deep
  /// by the time the pane is phone width, which is the "filters eat the screen"
  /// this was raised for. The card grid gives up at almost the same place:
  /// `targetColumnWidth: 380` means one column below 760, so from 620 down the
  /// grid is already a single stack of cards and the mobile card's
  /// hairline-separated rows say the same thing in far less height.
  ///
  /// It is deliberately NOT a viewport test. The shell hands this body its
  /// centre column, so a 1000px browser with the rail out can arrive here with
  /// ~620 of usable width — that page should read as compact even though the
  /// window is not.
  static const double _kWebCompactPane = 620.0;

  /// The phone width that would have produced a content column of [pane].
  ///
  /// The mobile body sizes every dimension off the viewport (`w * .0xx`) and
  /// then lays the stat row out inside a `w * .04` gutter on each side, so a
  /// phone of width `x` gives its cards `x * .92` to share. Inverting that is
  /// what makes the web cards land at the size the handset shows rather than at
  /// a desktop size scaled down.
  ///
  /// Clamped at both ends. The 460 ceiling is the width the desktop layout
  /// already sizes itself off, so a roomy pane can never scale the cards UP
  /// past what desktop shows — between ~423px of content and the compact
  /// breakpoint this returns exactly the old fixed 460 and nothing moves. The
  /// 320 floor is the narrowest phone the app supports.
  static double _compactBase(double pane) => (pane / .92).clamp(320.0, 460.0);

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
      // Floored on web only; mobile keeps its fade from zero.
      opacity: Tween<double>(begin: kIsWeb ? _kWebFadeFloor : 0.0, end: 1.0)
          .animate(
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
    // ── The browser always gets the web layout ──────────────────────────
    //
    // `kIsWeb` alone, no width test, matching every other citizen-web screen.
    // The old `>= 900` was measured against a MediaQuery the shell has already
    // overridden to describe the centre column, so a browser narrower than
    // about 1500 — the rail and the right sidebar take their cut before this
    // page sees anything — dropped to the PHONE body: a stranded 480px column
    // with a logo bar, inside a pane that has a nav and a rail of its own.
    //
    // The web body handles a narrow pane on its own now: below
    // [_kWebCompactPane] it mirrors the MOBILE app's layout rather than
    // squeezing the desktop one — the stat row stays four across but is sized
    // off the real pane, and the date filters go back to one scrolling row
    // inside the Report History card. See [_buildKpiRow] and [_buildWebBody].
    final bool wide = kIsWeb;
    final double w = wide ? 460.0 : uiScaleWidth(context);
    return wide
        ? LoadingOverlay.bodyOrSkeleton(
            isLoading: _isLoading,
            layout: SkeletonLayout.myReports,
            // Same `wide` that chose _buildWebBody, so the skeleton and the body
            // it stands in for can never disagree.
            webWide: wide,
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
          );
  }

  // ── WEB body: header banner + KPI row + report card grid ───────────────────
  //
  // Two arrangements, one page. Above [_kWebCompactPane] this is the desktop
  // layout it has always been: a wide stat row, the date filters wrapped under
  // a "Report History" heading, and the reports in a multi-column card grid.
  //
  // At or below it — a phone browser, and a tablet in portrait — the page
  // renders the MOBILE app's arrangement instead, because at that width the
  // desktop one spends the screen on chrome: five filter chips in a `Wrap`
  // become three stacked rows, and every report card pays for its own border,
  // shadow and 16px of gap. See [_kWebCompactPane].
  Widget _buildWebBody(double w) {
    return LayoutBuilder(
      builder: (context, outer) {
        // Measured against the CONTENT BAND, not the viewport: the pane handed
        // to this body is already the shell's centre column, and the page's own
        // gutter comes off it before the stat row or the chips see anything.
        final double band = outer.maxWidth > _kWebMaxBand
            ? _kWebMaxBand
            : outer.maxWidth;
        final bool compact = band <= _kWebCompactPane;
        // Desktop takes the shared page gutter, so band minus gutters is the
        // same 816 the account pages and the detail page resolve to. Compact
        // keeps 16: it is drawing the phone's arrangement, at phone widths.
        final double gutter = compact ? 16.0 : kAccountPageGutter;
        // On the compact path everything is sized off the phone width that
        // would have produced this content column, so the page inherits the
        // mobile app's proportions rather than a desktop measure shrunk down.
        final double base = compact ? _compactBase(band - gutter * 2) : w;
        return _buildWebColumn(w, base, compact: compact, gutter: gutter);
      },
    );
  }

  Widget _buildWebColumn(
    double w,
    double base, {
    required bool compact,
    required double gutter,
  }) {
    final ww = base * 1.18;
    final reports = _filteredReports;
    return SingleChildScrollView(
      // Clamping, not bouncing. The rubber-band is an iOS gesture idiom, and in
      // a browser its only visible effect here was on FILTERING: picking a
      // status shortens the page, and the scroll view sprang back off the new
      // bottom — the "bounce" the whole page appeared to do. The phone body
      // keeps BouncingScrollPhysics, where it is the platform's own behaviour.
      physics: const ClampingScrollPhysics(),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kWebMaxBand),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              gutter,
              compact ? 16 : kAccountPageGutter,
              gutter,
              compact ? 32 : 56,
            ),
            child: _error != null
                ? _buildBody(w)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Not _buildTopBar ───────────────────────────────
                      //
                      // That one is the phone's: a full-bleed white slab with
                      // a drop shadow, carrying the GovPulse mark. On a phone
                      // the mark belongs there — the screen IS the app, and
                      // nothing else on it says so. In the shell the top nav
                      // shows that same mark about 60px higher, so the bar was
                      // printing it twice.
                      //
                      // It also had its own `w * .04` padding INSIDE the page's
                      // 24, so the slab and everything under it started at two
                      // different x — the misalignment that made the header
                      // read as a stray card rather than as this page's title.
                      const AccountPageTitle(
                        title: 'My Reports',
                        subtitle:
                            'Track the issues you have submitted and '
                            'where each one has got to.',
                      ),
                      // ── Not _animated ──────────────────────────────────
                      //
                      // The entrance used to fade-and-slide the whole page in
                      // three staggered steps — stat row, then heading, then
                      // cards. The stat row and the heading are the page's
                      // furniture: they are in the same place before and after
                      // any filter, so animating them on the way in only makes
                      // the page look like it is settling into position. The
                      // motion belongs on the thing that actually changes,
                      // which is the cards.
                      _buildKpiRow(base),
                      SizedBox(height: compact ? 18 : 28),
                      // ── Compact reuses the phone's section verbatim ──────
                      //
                      // Not a web copy of it: [_buildReportsSection] IS the
                      // widget the Android and iOS app builds — one white card
                      // holding the heading, the chips on a single horizontally
                      // scrolling row, and the reports separated by hairlines.
                      // Sharing it is the whole point; a parallel web version
                      // is how the two drift apart again.
                      if (compact)
                        _animated(
                          2,
                          _buildReportsSection(base, ww, gutter: false),
                        )
                      else ...[
                        _buildReportsHeaderWeb(base, ww, reports.length),
                        const SizedBox(height: 16),
                        // The one animated block, and the one that changes: a
                        // filter swaps which cards are here. AnimatedSize glides
                        // the height instead of snapping it, matching what the
                        // compact arrangement already does with its list.
                        AnimatedSize(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.topCenter,
                          // Index 0: with the furniture no longer animating
                          // there is nothing left to stagger behind, so the
                          // cards start with the page instead of after it.
                          child: _animated(
                            0,
                            reports.isEmpty
                                ? _buildEmptyState(base)
                                : WebCardGrid(
                                    // 380, not 520: the band is 816 wide now and
                                    // the grid fits floor(width / target)
                                    // columns, so 520 would have collapsed two
                                    // columns into one. 380 keeps the pair, at
                                    // ~398 a card — and still drops to a single
                                    // column below a 760 content width, which is
                                    // where a two-up grid stops being readable.
                                    targetColumnWidth: 380,
                                    children: [
                                      for (final r in reports)
                                        _reportGridCard(base, ww, r),
                                    ],
                                  ),
                          ),
                        ),
                      ],
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
            _filterChip(
              w,
              'Today',
              ReportFilter.today,
              Icons.wb_sunny_outlined,
            ),
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
        border: Border.all(color: CitizenUi.sharedBorder),
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
      // Scrollable, unlike the Center it used to be. The happy path below has
      // always scrolled; this branch did not, and it is the branch that has to
      // survive the least room. Turned sideways a phone leaves ~114dp of body
      // here, and the icon, the two lines and the Retry button want 168 — so
      // the retry the citizen is being asked to tap was under a striped
      // overflow bar, off-screen, with no way to reach it. Nothing moves in
      // portrait: the Center still centres whenever the content fits.
      return LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
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
                      icon: const Icon(
                        Icons.refresh_rounded,
                        color: Colors.white,
                      ),
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
            ),
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
    // The four cards, built at whatever base width the caller's layout resolves
    // to. Both arrangements below place these SAME widgets in the same order
    // with the same gap — the phone gets the row it always had, wrapped in the
    // padding it always had.
    List<Widget> cardsAt(double cw) {
      final cww = cw * 1.18;
      return <Widget>[
        _kpiCard(
          w: cw,
          ww: cww,
          icon: Icons.assignment_outlined,
          count: _totalCount,
          label: 'All',
          iconBg: const Color(0xFFEEF2FF),
          iconColor: AppColors.primaryBlue,
          valueColor: AppColors.primaryBlue,
          selected: _activeKpi == StatusFilter.all,
          onTap: () => _selectKpi(StatusFilter.all),
        ),
        _kpiCard(
          w: cw,
          ww: cww,
          icon: Icons.access_time_rounded,
          count: _pendingCount,
          label: 'Pending',
          iconBg: const Color(0xFFFFF7ED),
          iconColor: const Color(0xFFD97706),
          valueColor: const Color(0xFFD97706),
          selected: _activeKpi == StatusFilter.pending,
          onTap: () => _selectKpi(StatusFilter.pending),
        ),
        _kpiCard(
          w: cw,
          ww: cww,
          icon: Icons.check_circle_outline_rounded,
          count: _resolvedCount,
          label: 'Resolved',
          iconBg: const Color(0xFFECFDF5),
          iconColor: const Color(0xFF059669),
          valueColor: const Color(0xFF059669),
          selected: _activeKpi == StatusFilter.resolved,
          onTap: () => _selectKpi(StatusFilter.resolved),
        ),
        _kpiCard(
          w: cw,
          ww: cww,
          icon: Icons.cancel_outlined,
          count: _rejectedCount,
          label: 'Rejected',
          iconBg: const Color(0xFFFEF2F2),
          iconColor: const Color(0xFFDC2626),
          valueColor: const Color(0xFFDC2626),
          selected: _activeKpi == StatusFilter.rejected,
          onTap: () => _selectKpi(StatusFilter.rejected),
        ),
      ];
    }

    // NOTE: No CrossAxisAlignment.stretch here. All labels are single words now,
    // so the four cards are naturally identical height. Adding `stretch` to a Row
    // inside a vertical SingleChildScrollView gives it unbounded height and throws
    // a layout error (which renders as a blank grey screen in release builds).
    Widget rowOf(double cw) {
      final cards = cardsAt(cw);
      return Row(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) SizedBox(width: cw * .03),
            Expanded(child: cards[i]),
          ],
        ],
      );
    }

    if (kIsWeb) {
      // ── One row at every width, like the phone ────────────────────────────
      //
      // This used to fall to a 2x2 block below 560px of pane, which cost a
      // whole extra row of vertical space on exactly the screens with the least
      // of it — and it did that because the cards were sized off a hardcoded
      // 460 no matter how little room they actually had, so four of them really
      // did stop fitting. Sizing them off the pane instead removes the reason:
      // the ratios are the mobile app's, and four across is what the mobile app
      // shows on a 320px handset.
      //
      // Above ~423px of pane [_compactBase] returns the same 460 the old code
      // hardcoded, so nothing about the desktop row changes.
      return LayoutBuilder(
        builder: (context, c) => rowOf(_compactBase(c.maxWidth)),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * .04),
      child: rowOf(w),
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
          // ── The hairline is CONSTANT; the selection ring is painted in
          //    front ────────────────────────────────────────────────────────
          //
          // A border inside `decoration` insets the child, so widening it to 2
          // on selection made the card 2px taller. Four of these sit in a Row
          // whose height is its tallest child, so selecting a filter grew the
          // row — and every pixel of the page below it moved. Worse during a
          // SWITCH: one card is shrinking while the other grows, both on a
          // 320ms curve, so the row's height wobbles and the whole screen
          // shakes for the length of the animation. That is the shake you see
          // when tapping between All / Pending / Resolved / Rejected.
          //
          // `foregroundDecoration` paints over the child and takes no part in
          // layout, so the ring can appear and vanish without the card ever
          // changing size.
          border: Border.all(color: CitizenUi.sharedBorder),
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
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(w * .035),
          border: Border.all(
            color: selected ? iconColor : Colors.transparent,
            width: 2,
          ),
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

  /// The Report History card: heading, the date chips on one horizontally
  /// scrolling row, and the reports separated by hairlines.
  ///
  /// [gutter] is the phone's `w * .04` page margin. The mobile body has no
  /// padding of its own, so it needs it; the compact web page has already
  /// applied its own gutter to the whole column, and a second one here would
  /// inset this card from the stat row directly above it.
  Widget _buildReportsSection(double w, double ww, {bool gutter = true}) {
    final reports = _filteredReports;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: gutter ? w * .04 : 0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(w * .04),
          border: Border.all(color: CitizenUi.sharedBorder),
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
            const Divider(height: 1, color: CitizenUi.sharedBorder),
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
                      separatorBuilder: (_, _) => const Divider(
                        height: 1,
                        color: CitizenUi.sharedBorder,
                      ),
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
            color: isActive ? AppColors.primaryBlue : CitizenUi.sharedBorder,
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
        final open = widget.onOpenReport;
        if (open != null) {
          open(report);
          return;
        }
        pushLegacy(
          context,
          '/report_detail',
          arguments: {
            'report': report,
            'username': _username,
            'backLabel': 'Back to My Reports',
          },
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
