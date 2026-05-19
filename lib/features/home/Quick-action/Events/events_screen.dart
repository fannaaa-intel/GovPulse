import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/services/events_service.dart';
// ─── UI model (keeps all existing widgets working as-is) ─────────────────────

class EventItem {
  final String id;
  final String title;
  final String location;
  final String date;
  final String time;
  final String category;
  final Color categoryColor;
  final bool isFeatured;
  final String? imageUrl; // ← network URL now (was imageAsset)
  final DateTime eventDate; // ← raw date for Today/Upcoming logic

  const EventItem({
    required this.id,
    required this.title,
    required this.location,
    required this.date,
    required this.time,
    required this.category,
    required this.categoryColor,
    required this.eventDate,
    this.isFeatured = false,
    this.imageUrl,
  });

  /// Map EventModel (Supabase) → EventItem (UI)
  factory EventItem.fromModel(EventModel m) {
    return EventItem(
      id: m.id,
      title: m.title,
      location: m.location,
      date: DateFormat('MMM d, yyyy').format(m.eventDate),
      time: m.eventTime,
      category: m.category,
      categoryColor: _hexToColor(m.categoryColor),
      isFeatured: m.isFeatured,
      imageUrl: m.imageUrl,
      eventDate: m.eventDate,
    );
  }

  static Color _hexToColor(String hex) {
    final cleaned = hex.replaceFirst('#', '');
    final full = cleaned.length == 6 ? 'FF$cleaned' : cleaned;
    return Color(int.parse(full, radix: 16));
  }
}

// ─── Filter chips ─────────────────────────────────────────────────────────────

const List<String> _primaryFilters = [
  'All',
  'Today',
  'Upcoming',
  'Recent',
  'Health',
];
const List<String> _moreFilters = [
  'Training',
  'Environment',
  'Special',
  'Others',
];

// ─── Screen ───────────────────────────────────────────────────────────────────

class EventsScreen extends StatefulWidget {
  final String username;
  final bool isVerified;

  const EventsScreen({
    super.key,
    required this.username,
    this.isVerified = false,
  });

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen>
    with TickerProviderStateMixin {
  // ── State ──────────────────────────────────────────────────────────────────
  List<EventItem> _events = [];
  bool _isLoading = true;
  String? _error;

  String _selectedFilter = 'All';
  bool _showMoreFilters = false;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  late final AnimationController _entryCtrl;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _searchCtrl.addListener(
      () =>
          setState(() => _searchQuery = _searchCtrl.text.trim().toLowerCase()),
    );
    _loadEvents();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Data fetching ──────────────────────────────────────────────────────────
  Future<void> _loadEvents() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      // Pass category filter to the service when it's a real category
      final categoryFilter = _isCategoryFilter(_selectedFilter)
          ? _selectedFilter
          : null;

      final models = await EventsService.instance.fetchEvents(
        category: categoryFilter,
        searchQuery: _searchQuery.isEmpty ? null : _searchQuery,
      );

      if (!mounted) return;
      setState(() {
        _events = models.map(EventItem.fromModel).toList();
        _isLoading = false;
      });

      // Run entry animation after data loads
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 60), () {
          if (mounted) _entryCtrl.forward(from: 0);
        });
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  bool _isCategoryFilter(String f) =>
      !['All', 'Today', 'Upcoming', 'Recent'].contains(f);

  // ── Client-side filters (Today / Upcoming / Recent + search) ──────────────
  List<EventItem> get _filteredEvents {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    return _events.where((e) {
      final eDate = DateTime(
        e.eventDate.year,
        e.eventDate.month,
        e.eventDate.day,
      );

      final matchesFilter = switch (_selectedFilter) {
        'All' => true,
        'Today' => eDate == todayDate,
        'Upcoming' => eDate.isAfter(todayDate),
        'Recent' => eDate.isBefore(todayDate),
        _ => e.category == _selectedFilter, // Health, Training, etc.
      };

      final matchesSearch =
          _searchQuery.isEmpty ||
          e.title.toLowerCase().contains(_searchQuery) ||
          e.location.toLowerCase().contains(_searchQuery) ||
          e.category.toLowerCase().contains(_searchQuery);

      return matchesFilter && matchesSearch;
    }).toList();
  }

  List<EventItem> get _featuredEvents =>
      _filteredEvents.where((e) => e.isFeatured).toList();

  List<EventItem> get _todayEvents {
    final todayDate = DateTime.now();
    final d = DateTime(todayDate.year, todayDate.month, todayDate.day);
    return _filteredEvents
        .where(
          (e) =>
              !e.isFeatured &&
              DateTime(e.eventDate.year, e.eventDate.month, e.eventDate.day) ==
                  d,
        )
        .toList();
  }

  List<EventItem> get _upcomingEvents {
    final todayDate = DateTime.now();
    final d = DateTime(todayDate.year, todayDate.month, todayDate.day);
    return _filteredEvents
        .where(
          (e) =>
              !e.isFeatured &&
              DateTime(
                e.eventDate.year,
                e.eventDate.month,
                e.eventDate.day,
              ).isAfter(d),
        )
        .toList();
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(w),
            Expanded(child: _buildBody(w)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(double w) {
    // Loading state
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Error state
    if (_error != null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(w * 0.08),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.wifi_off_rounded,
                size: w * 0.15,
                color: const Color(0xFFD1D5DB),
              ),
              SizedBox(height: w * 0.04),
              Text(
                'Could not load events',
                style: TextStyle(
                  fontSize: w * 0.042,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF6B7280),
                ),
              ),
              SizedBox(height: w * 0.02),
              ElevatedButton.icon(
                onPressed: _loadEvents,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // Normal content — identical structure to original
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.only(bottom: w * 0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: w * 0.04),
          _animated(0, _buildHeroBanner(w)),
          _animated(1, _buildSearchBar(w)),
          _animated(2, _buildFilterChips(w)),
          if (_showMoreFilters) _animated(3, _buildMoreFilterChips(w)),
          if (_featuredEvents.isNotEmpty) ...[
            _animated(4, _buildSectionLabel('Featured Event', w)),
            _animated(5, _buildFeaturedCard(_featuredEvents.first, w)),
          ],
          if (_todayEvents.isNotEmpty) ...[
            _animated(6, _buildSectionLabel("Today's Event", w)),
            _animated(7, _buildEventGrid(_todayEvents, w)),
          ],
          if (_upcomingEvents.isNotEmpty) ...[
            _animated(8, _buildSectionLabel('Upcoming Events', w)),
            _animated(9, _buildEventGrid(_upcomingEvents, w)),
          ],
          if (_filteredEvents.isEmpty)
            _animated(4, Center(child: _buildEmpty(w))),
        ],
      ),
    );
  }

  Widget _animated(int i, Widget child) {
    final start = (i * 0.10).clamp(0.0, 1.0);
    final end = (start + 0.50).clamp(0.0, 1.0);
    return FadeTransition(
      opacity: Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(
          parent: _entryCtrl,
          curve: Interval(start, end, curve: Curves.easeOut),
        ),
      ),
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.18), end: Offset.zero)
            .animate(
              CurvedAnimation(
                parent: _entryCtrl,
                curve: Interval(start, end, curve: Curves.easeOutCubic),
              ),
            ),
        child: child,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // All widget builders below are IDENTICAL to original — only imageAsset
  // references replaced with _eventImage(..., imageUrl: event.imageUrl)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildHeader(double w) {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.symmetric(horizontal: w * 0.04, vertical: w * 0.03),
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
              ),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: w * 0.045,
                color: AppColors.primaryBlue,
              ),
            ),
          ),
          SizedBox(width: w * 0.03),
          Image.asset(
            'assets/images/newslogo.png',
            height: w * 0.085,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => Row(
              children: [
                Icon(
                  Icons.account_balance_rounded,
                  size: w * 0.07,
                  color: AppColors.primaryBlue,
                ),
                SizedBox(width: w * 0.02),
                Text(
                  'GovPulse',
                  style: TextStyle(
                    fontSize: w * 0.048,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryBlue,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroBanner(double w) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.04),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: w * 0.045,
          vertical: w * 0.045,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(w * 0.04),
          border: Border.all(color: const Color(0xFFE5E7EB)),
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Events & Activities',
                    style: TextStyle(
                      fontSize: w * 0.058,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1F2937),
                    ),
                  ),
                  SizedBox(height: w * 0.015),
                  Text(
                    'Stay updated with official LGU events\nhappening in our community.',
                    style: TextStyle(
                      fontSize: w * 0.031,
                      color: const Color(0xFF6B7280),
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            Image.asset(
              'assets/images/activity.png',
              width: w * 0.22,
              height: w * 0.22,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => Icon(
                Icons.event_rounded,
                size: w * 0.20,
                color: const Color(0xFF6B7280),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(double w) {
    return Padding(
      padding: EdgeInsets.fromLTRB(w * 0.04, w * 0.035, w * 0.04, 0),
      child: Container(
        height: w * 0.115,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(w * 0.03),
          border: Border.all(color: AppColors.stroke),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            SizedBox(width: w * 0.04),
            Icon(Icons.search_rounded, size: w * 0.05, color: AppColors.hint),
            SizedBox(width: w * 0.025),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                onSubmitted: (_) => _loadEvents(), // re-fetch on submit
                style: TextStyle(
                  fontSize: w * 0.036,
                  color: const Color(0xFF1F2937),
                ),
                decoration: InputDecoration(
                  hintText: 'Search events...',
                  hintStyle: TextStyle(
                    fontSize: w * 0.036,
                    color: AppColors.hint,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            Container(width: 1, height: w * 0.055, color: AppColors.stroke),
            GestureDetector(
              onTap: () => setState(() => _showMoreFilters = !_showMoreFilters),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: w * 0.035),
                child: Icon(
                  Icons.tune_rounded,
                  size: w * 0.05,
                  color: _showMoreFilters
                      ? AppColors.primaryBlue
                      : AppColors.hint,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChips(double w) {
    return Padding(
      padding: EdgeInsets.fromLTRB(w * 0.04, w * 0.025, w * 0.04, 0),
      child: SizedBox(
        height: w * 0.088,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.zero,
          children: [
            ..._primaryFilters.map((f) => _filterChip(f, w)),
            GestureDetector(
              onTap: () => setState(() => _showMoreFilters = !_showMoreFilters),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: EdgeInsets.symmetric(
                  horizontal: w * 0.04,
                  vertical: w * 0.018,
                ),
                decoration: BoxDecoration(
                  color: _showMoreFilters
                      ? AppColors.primaryBlue
                      : Colors.white,
                  borderRadius: BorderRadius.circular(w * 0.05),
                  border: Border.all(
                    color: _showMoreFilters
                        ? AppColors.primaryBlue
                        : AppColors.stroke,
                  ),
                ),
                child: Text(
                  'More...',
                  style: TextStyle(
                    fontSize: w * 0.032,
                    fontWeight: FontWeight.w600,
                    color: _showMoreFilters
                        ? Colors.white
                        : const Color(0xFF374151),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label, double w) {
    final isActive = _selectedFilter == label;
    return Padding(
      padding: EdgeInsets.only(right: w * 0.02),
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedFilter = label);
          _loadEvents(); // re-fetch when filter changes
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(
            horizontal: w * 0.04,
            vertical: w * 0.018,
          ),
          decoration: BoxDecoration(
            color: isActive ? AppColors.primaryBlue : Colors.white,
            borderRadius: BorderRadius.circular(w * 0.05),
            border: Border.all(
              color: isActive ? AppColors.primaryBlue : AppColors.stroke,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: AppColors.primaryBlue.withValues(alpha: 0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: w * 0.032,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              color: isActive ? Colors.white : const Color(0xFF374151),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMoreFilterChips(double w) {
    return Padding(
      padding: EdgeInsets.fromLTRB(w * 0.04, w * 0.015, w * 0.04, 0),
      child: SizedBox(
        height: w * 0.088,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.zero,
          children: _moreFilters.map((f) => _filterChip(f, w)).toList(),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String title, double w) {
    return Padding(
      padding: EdgeInsets.fromLTRB(w * 0.04, w * 0.045, w * 0.04, w * 0.02),
      child: Text(
        title,
        style: TextStyle(
          fontSize: w * 0.046,
          fontWeight: FontWeight.w800,
          color: const Color(0xFF1F2937),
          letterSpacing: -0.2,
        ),
      ),
    );
  }

  Widget _buildFeaturedCard(EventItem event, double w) {
    final imageW = w * 0.32;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.04),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(w * 0.035),
          border: Border.all(color: AppColors.stroke),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.all(w * 0.035),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: imageW,
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(w * 0.025),
                        child: SizedBox(
                          width: imageW,
                          height: double.infinity,
                          child: event.imageUrl != null
                              ? Image.network(
                                  event.imageUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Container(
                                    color: const Color(0xFFE5E7EB),
                                    child: Center(
                                      child: Icon(
                                        Icons.image_rounded,
                                        size: imageW * 0.38,
                                        color: const Color(0xFF9CA3AF),
                                      ),
                                    ),
                                  ),
                                )
                              : Container(
                                  color: const Color(0xFFE5E7EB),
                                  child: Center(
                                    child: Icon(
                                      Icons.image_rounded,
                                      size: imageW * 0.38,
                                      color: const Color(0xFF9CA3AF),
                                    ),
                                  ),
                                ),
                        ),
                      ),
                      Positioned(
                        top: w * 0.018,
                        left: w * 0.018,
                        child: _categoryBadge(
                          event.category,
                          event.categoryColor,
                          w,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: w * 0.035),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: w * 0.042,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF1F2937),
                        ),
                      ),
                      SizedBox(height: w * 0.014),
                      _infoRow(
                        'assets/images/report/location.png',
                        event.location,
                        AppColors.primaryBlue,
                        w,
                      ),
                      SizedBox(height: w * 0.008),
                      _infoRow(
                        'assets/images/calendar.png',
                        event.date,
                        AppColors.green,
                        w,
                      ),
                      SizedBox(height: w * 0.008),
                      _infoRow(
                        'assets/images/clock.png',
                        event.time,
                        AppColors.orange,
                        w,
                      ),
                      SizedBox(height: w * 0.014),
                      Text(
                        'Celebrate the vibrant spirit of our community. Join us for a day of fun, culture, and tradition!',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: w * 0.028,
                          color: AppColors.hint,
                          height: 1.4,
                        ),
                      ),
                      SizedBox(height: w * 0.018),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {},
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.green,
                            elevation: 0,
                            padding: EdgeInsets.symmetric(vertical: w * 0.026),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(w * 0.022),
                            ),
                          ),
                          child: Text(
                            'View Details',
                            style: TextStyle(
                              fontSize: w * 0.032,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
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

  Widget _buildEventGrid(List<EventItem> events, double w) {
    final cardW = w * 0.42;
    final cardH = cardW * 1.42;
    return SizedBox(
      height: cardH,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: w * 0.04),
        itemCount: events.length,
        itemBuilder: (context, index) => Padding(
          padding: EdgeInsets.only(
            right: index < events.length - 1 ? w * 0.03 : 0,
          ),
          child: _buildSmallCard(events[index], cardW, w),
        ),
      ),
    );
  }

  Widget _buildSmallCard(EventItem event, double cardW, double w) {
    final imageH = cardW * 0.62;
    return SizedBox(
      width: cardW,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(w * 0.03),
          border: Border.all(color: AppColors.stroke),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(w * 0.03),
                  ),
                  child: SizedBox(
                    width: cardW,
                    height: imageH,
                    child: event.imageUrl != null
                        ? Image.network(
                            event.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              color: const Color(0xFFE5E7EB),
                              child: Center(
                                child: Icon(
                                  Icons.image_rounded,
                                  size: cardW * 0.28,
                                  color: const Color(0xFF9CA3AF),
                                ),
                              ),
                            ),
                          )
                        : Container(
                            color: const Color(0xFFE5E7EB),
                            child: Center(
                              child: Icon(
                                Icons.image_rounded,
                                size: cardW * 0.28,
                                color: const Color(0xFF9CA3AF),
                              ),
                            ),
                          ),
                  ),
                ),
                Positioned(
                  top: w * 0.015,
                  left: w * 0.015,
                  child: _categoryBadge(
                    event.category,
                    event.categoryColor,
                    w,
                    small: true,
                  ),
                ),
              ],
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                w * 0.025,
                w * 0.020,
                w * 0.025,
                w * 0.020,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    event.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: w * 0.033,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1F2937),
                      height: 1.2,
                    ),
                  ),
                  SizedBox(height: w * 0.008),
                  _infoRow(
                    'assets/images/report/location.png',
                    event.location,
                    AppColors.primaryBlue,
                    w,
                    small: true,
                  ),
                  SizedBox(height: w * 0.005),
                  _infoRow(
                    'assets/images/calendar.png',
                    event.date,
                    AppColors.green,
                    w,
                    small: true,
                  ),
                  SizedBox(height: w * 0.005),
                  _infoRow(
                    'assets/images/clock.png',
                    event.time,
                    AppColors.orange,
                    w,
                    small: true,
                  ),
                  SizedBox(height: w * 0.012),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {},
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        elevation: 0,
                        padding: EdgeInsets.symmetric(vertical: w * 0.018),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(w * 0.02),
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'View Details',
                        style: TextStyle(
                          fontSize: w * 0.028,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryBadge(
    String label,
    Color color,
    double w, {
    bool small = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: w * (small ? 0.018 : 0.022),
        vertical: w * (small ? 0.008 : 0.010),
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(w * 0.015),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: w * (small ? 0.022 : 0.026),
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _infoRow(
    String iconPath,
    String text,
    Color iconColor,
    double w, {
    bool small = false,
  }) {
    final iconSize = w * (small ? 0.028 : 0.036);
    final fontSize = w * (small ? 0.025 : 0.032);
    return Row(
      children: [
        SizedBox(
          width: iconSize,
          height: iconSize,
          child: ColorFiltered(
            colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
            child: Image.asset(
              iconPath,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => Icon(
                iconPath.contains('location')
                    ? Icons.location_on_rounded
                    : iconPath.contains('calendar')
                    ? Icons.calendar_today_rounded
                    : Icons.access_time_rounded,
                size: iconSize,
                color: iconColor,
              ),
            ),
          ),
        ),
        SizedBox(width: w * 0.012),
        Flexible(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: TextStyle(
              fontSize: fontSize,
              color: const Color(0xFF374151),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty(double w) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: w * 0.12, horizontal: w * 0.08),
      child: Column(
        children: [
          Icon(
            Icons.event_busy_rounded,
            size: w * 0.18,
            color: const Color(0xFFD1D5DB),
          ),
          SizedBox(height: w * 0.04),
          Text(
            'No events found',
            style: TextStyle(
              fontSize: w * 0.042,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF6B7280),
            ),
          ),
          SizedBox(height: w * 0.012),
          Text(
            'Try a different filter or search term.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: w * 0.032, color: AppColors.hint),
          ),
        ],
      ),
    );
  }
}
