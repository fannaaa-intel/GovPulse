import 'package:flutter/material.dart';
import '../../../../core/widgets/responsive_page.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/router/legacy_nav.dart';
import '../../../../core/services/events_service.dart';
import '../../../../core/widgets/event_status_pill.dart';
import '../../../../core/widgets/loading/loading_overlay.dart';
import 'package:cached_network_image/cached_network_image.dart';
// ─── UI model (keeps all existing widgets working as-is) ─────────────────────

import '../../shell/citizen_shell_dialogs.dart'
    show kSplitDialogFullscreenBelow;
import '../../../../core/widgets/Home/Quick-action/Web/quick_action_split_panel.dart';
import '../../../../core/theme/citizen_ui.dart';
import '../../../../core/theme/mobile_metrics.dart';

class EventItem {
  final String id;
  final String title;
  final String location;
  final String date;
  final String time;
  final String category;
  final Color categoryColor;
  final bool isFeatured;
  final String? imageUrl;
  final String? description;
  final String? whatToExpect;
  final String? requirements;
  final DateTime eventDate;

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
    this.description,
    this.whatToExpect,
    this.requirements,
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
      description: m.description,
      whatToExpect: m.whatToExpect,
      requirements: m.requirements,
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

/// Height of the split panel's stacked filter row.
///
/// A horizontal [ListView] has no intrinsic height, so the row has to be told
/// one. This is the chip's own measured height — see [_SplitFilterChip]: 12px
/// text (~16), 7 of vertical padding each side, 1 of border each side.
const double _kSplitChipRowHeight = 32;

// ─── Screen ───────────────────────────────────────────────────────────────────

class EventsScreen extends StatefulWidget {
  final String username;
  final bool isVerified;

  /// Open one event. Null — the mobile app and the live web route — keeps the
  /// legacy '/event_detail' push with the object in `arguments`.
  ///
  /// The shell passes a callback instead, so the event opens at an
  /// id-addressable URL that survives a reload. Same shape as
  /// `MyReportsBody.onOpenReport`, and for the same reason: it keeps this screen
  /// from having to know which router it is running under.
  final void Function(EventItem event)? onOpenEvent;

  /// Two-column web layout — the browse list on the left, the selected event's
  /// detail on the right. Default false, and the default is what mobile and the
  /// standalone route get, so their widget tree is unchanged.
  final bool splitPanel;

  /// Dismisses the hosting dialog. Only read in the [splitPanel] branch, whose
  /// rail owns the × and the Close button.
  final VoidCallback? onClose;

  /// Copies a shareable link to [EventItem] without leaving the panel.
  ///
  /// The panel deliberately never navigates to `/home/event/:id` — the whole
  /// point of the split layout is that an event is read INSIDE the modal. But
  /// that route is still what makes an event shareable and reload-proof, so the
  /// panel hands its address out instead of going there. Building the URL needs
  /// the router, which already imports this file, so the shell supplies this
  /// rather than the screen reaching back up. Null hides the control.
  final void Function(EventItem event)? onShareEvent;

  const EventsScreen({
    super.key,
    required this.username,
    this.isVerified = false,
    this.onOpenEvent,
    this.splitPanel = false,
    this.onClose,
    this.onShareEvent,
  });

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen>
    with TickerProviderStateMixin {
  /// Opens [event]. Delegates to the host when one supplied a callback (the web
  /// shell, which routes to an id-addressable URL); otherwise keeps the legacy
  /// in-memory push that mobile and the live route rely on.
  void _openEvent(EventItem event) {
    final open = widget.onOpenEvent;
    if (open != null) {
      open(event);
      return;
    }
    pushLegacy(
      context,
      '/event_detail',
      arguments: {'event': event, 'username': widget.username},
    );
  }

  // ── State ──────────────────────────────────────────────────────────────────
  List<EventItem> _events = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _error;
  bool _cardsAnimating = false;

  String _selectedFilter = 'All';
  bool _showMoreFilters = false;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  late final AnimationController _entryCtrl;
  late final AnimationController _cardsCtrl;
  bool _entryDone = false;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _cardsCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _searchCtrl.addListener(
      () =>
          setState(() => _searchQuery = _searchCtrl.text.trim().toLowerCase()),
    );
    _loadEvents(isInitialLoad: true);
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _cardsCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Data fetching ──────────────────────────────────────────────────────────
  Future<void> _loadEvents({bool isInitialLoad = false}) async {
    setState(() {
      if (isInitialLoad) _isLoading = true;
      _isRefreshing = !isInitialLoad;
      _error = null;
    });
    try {
      final categoryFilter = _isCategoryFilter(_selectedFilter)
          ? _selectedFilter
          : null;

      final models = await EventsService.instance.fetchEvents(
        category: categoryFilter,
        searchQuery: _searchQuery.isEmpty ? null : _searchQuery,
      );

      if (!mounted) return;
      _cardsCtrl.reset();
      setState(() {
        _events = models.map(EventItem.fromModel).toList();
        _isLoading = false;
        _isRefreshing = false;
        _cardsAnimating = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        if (isInitialLoad) {
          Future.delayed(const Duration(milliseconds: 60), () {
            if (!mounted) return;
            _entryCtrl.forward(from: 0);
            setState(() => _entryDone = true);
            _cardsCtrl.forward(from: 0).then((_) {
              if (mounted) setState(() => _cardsAnimating = false);
            });
          });
        } else {
          _cardsCtrl.forward().then((_) {
            if (mounted) setState(() => _cardsAnimating = false);
          });
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
        _isRefreshing = false;
        _cardsAnimating = false;
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
      // Auto-hide events that ended more than a day ago (mirrors the backend
      // cron that deletes them) so the list never shows stale activities.
      if (isEventExpired(e.eventDate, e.time)) return false;

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

  List<EventItem> get _recentEvents {
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
              ).isBefore(d),
        )
        .toList();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final w = uiScaleWidth(context);

    // The citizen web shell's two-column panel. Checked FIRST because it is the
    // most specific host; the branch below is untouched.
    if (widget.splitPanel) return _splitPanelBody();

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: ResponsivePageBody(
        maxWidth: 900,
        shellTitle: 'Events & Activities',
        shellSubtitle:
            'Stay updated with official LGU events happening in the community.',
        shellIcon: Icons.event_available_rounded,
        shellHighlights: const [
          (Icons.calendar_today_rounded, 'Upcoming events'),
          (Icons.place_outlined, 'Local venues'),
          (Icons.notifications_none_rounded, 'Never miss out'),
        ],
        shellContentWidth: 680,
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(w),
              Expanded(
                child: _isLoading ? const EventsBodySkeleton() : _buildBody(w),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(double w) {
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
                onPressed: () => _loadEvents(isInitialLoad: true),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

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

          if (_isLoading || _isRefreshing)
            const EventsSectionsSkeleton()
          else if (_cardsAnimating)
            FadeTransition(
              opacity: Tween<double>(begin: 0, end: 1).animate(
                CurvedAnimation(parent: _cardsCtrl, curve: Curves.easeOut),
              ),
              child: SlideTransition(
                position:
                    Tween<Offset>(
                      begin: const Offset(0, 0.12),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(
                        parent: _cardsCtrl,
                        curve: Curves.easeOutQuart,
                      ),
                    ),
                child: _buildEventSections(w),
              ),
            )
          else
            _buildEventSections(w),
        ],
      ),
    );
  }

  Widget _buildEventSections(double w) {
    final hasAnySection =
        _featuredEvents.isNotEmpty ||
        _todayEvents.isNotEmpty ||
        _upcomingEvents.isNotEmpty ||
        _recentEvents.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_featuredEvents.isNotEmpty) ...[
          _buildSectionLabel('Featured Event', w),
          _buildFeaturedCard(_featuredEvents.first, w),
        ],
        if (_todayEvents.isNotEmpty) ...[
          _buildSectionLabel("Today's Event", w),
          _buildEventGrid(_todayEvents, w),
        ],
        if (_upcomingEvents.isNotEmpty) ...[
          _buildSectionLabel('Upcoming Events', w),
          _buildEventGrid(_upcomingEvents, w),
        ],
        if (_recentEvents.isNotEmpty) ...[
          _buildSectionLabel('Recent Events', w),
          _buildEventGrid(_recentEvents, w),
        ],
        if (!hasAnySection) Center(child: _buildEmpty(w)),
      ],
    );
  }

  Widget _animated(int i, Widget child) {
    if (_entryDone) return child;

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

  // ══════════════════════════════════════════════════════════════════════════
  //  Split panel (citizen web only)
  // ══════════════════════════════════════════════════════════════════════════
  //
  //  The same two-column panel the three quick-action FORMS draw, on the same
  //  shared chrome (quick_action_split_panel.dart) — but this surface has no
  //  form in it, so the parts that carry a form are the parts that change.
  //
  //  ── What maps onto what ─────────────────────────────────────────────────
  //    • The left panel is the working area, as everywhere else. Here the work
  //      is BROWSING: the search box, the filter chips and the list.
  //    • The right rail is the summary, as everywhere else. Here it summarises
  //      the SELECTED EVENT rather than a half-filled form.
  //    • There is no [QaStepper], because there is no sequence. Nothing here is
  //      earned or refused: every event is one click away at all times, and a
  //      numbered stepper over a list would promise an order that does not
  //      exist. The filter chips take its place in the head — they are what
  //      narrows the list, which is the closest thing this surface has to
  //      "where am I".
  //    • There is no [QaInstructionBlock] either. A step needs telling what it
  //      is for; a list of events does not.
  //
  //  ── Selecting is not opening ────────────────────────────────────────────
  //  A click in the list SELECTS, filling the rail. The rail's own button is
  //  what OPENS the event, at its id-addressable URL, through the unmodified
  //  [_openEvent]. Two different things, so a citizen can read three events
  //  without leaving the panel — which is the whole reason a browse surface
  //  gets a detail rail rather than a bigger list.

  /// Which event the rail is showing, by id.
  ///
  /// By ID rather than by object: the list is re-fetched on refresh and on a
  /// filter change, and holding the [EventItem] itself would leave the rail
  /// rendering a stale copy of an event the server has since edited — or one
  /// that has expired out of the list entirely while still filling the rail.
  /// Resolving through [_splitSelected] on each build makes both cases correct
  /// without any invalidation code.
  String? _splitSelectedId;

  /// The selected event, or null if nothing is selected or the selection is no
  /// longer in the list (expired, filtered out, deleted upstream).
  EventItem? get _splitSelected {
    final id = _splitSelectedId;
    if (id == null) return null;
    for (final e in _filteredEvents) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// Which PANE the stacked panel is showing: 0 = Browse, 1 = Details.
  ///
  /// Side by side there is nothing to switch between — the list and the detail
  /// are both on screen — so this is read only when the panel is stacked.
  int _splitTab = 0;

  static const List<String> _kSplitTabs = ['Browse', 'Details'];

  /// Side by side: whether the LEFT column has been given over to the full
  /// event detail instead of the browse list.
  ///
  /// ── Why the detail moves left rather than growing the rail ──────────────
  /// The complete detail is About plus two bulleted lists, and the rail is
  /// ~375px — enough for four ruled facts, not for three prose sections. The
  /// left column is ~660px and already the panel's working area on every other
  /// quick action, so the detail goes where the room is and the rail keeps
  /// doing what it does everywhere else: the summary and the buttons.
  ///
  /// Read only in the side-by-side layout. Stacked there is no second column to
  /// move anything into, so the Details PANE simply shows the full detail and
  /// this stays false.
  bool _splitDetailFull = false;

  /// The two-column web layout.
  Widget _splitPanelBody() {
    return QaSplitPanel(
      left: (stacked) => _splitLeftPanel(stacked),
      right: (stacked) => _splitRightRail(stacked),
    );
  }

  /// Selects [event] and, on the stacked layout, moves to the pane that shows
  /// it — otherwise a click on a phone appears to do nothing, because the rail
  /// it just filled is on the other tab.
  void _splitSelect(EventItem event, {required bool stacked}) {
    setState(() {
      _splitSelectedId = event.id;
      if (stacked) _splitTab = 1;
      // A click in the LIST is a change of subject, so the left column goes
      // back to being the list. Without this, picking a second event while the
      // first was expanded would silently swap the detail underneath — and the
      // list you clicked in would not be on screen to explain why.
      _splitDetailFull = false;
    });
  }

  // ── Left panel: the browse column ─────────────────────────────────────────

  Widget _splitLeftPanel(bool stacked) {
    // Phone-web, derived LOCALLY and only where it is used: `stacked` short
    // circuits, so the side-by-side path never even reads the size. It is the
    // host's own fullscreen threshold, not a second copy that can drift.
    final bool phone =
        stacked &&
        MediaQuery.sizeOf(context).width < kSplitDialogFullscreenBelow;

    return QaPanelCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        // Fit the card to its content, not to the height on offer — the
        // `Expanded` below still hands the list every pixel left over.
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Zone 1: the fixed head ───────────────────────────────────────
          if (stacked) ...[
            QaRailHeader(
              title: 'Events & Activities',
              onClose: widget.onClose ?? () {},
              useBackArrow: phone,
            ),
            const SizedBox(height: 14),
            QaSegmentedTabs(
              labels: _kSplitTabs,
              selected: _splitTab,
              onSelect: (i) => setState(() => _splitTab = i),
            ),
            const SizedBox(height: 14),
          ] else ...[
            const QaPanelTitle('Events & Activities'),
            const SizedBox(height: 14),
          ],

          // The search box and the chips sit in the FIXED head, not in the
          // scroller. They are what narrows the list, and a control that
          // scrolls away from the thing it controls is a control you have to
          // scroll back to before you can change your mind.
          //
          // Stacked they belong to the Browse pane only: on the Details pane
          // they would be filtering a list that is not on screen. Side by side
          // they go the moment the column becomes the detail, for the same
          // reason.
          if (!stacked && _splitDetailFull)
            _splitDetailBackBar()
          else if (!stacked || _splitTab == 0) ...[
            _splitSearchField(),
            const SizedBox(height: 10),
            _splitFilterChips(stacked),
            SizedBox(height: stacked ? 10 : 14),
          ],

          // ── Zone 2: the working area, the panel's only scroller ──────────
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) => SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: c.maxHeight),
                  child: (stacked && _splitTab == 1)
                      // Stacked, the Details pane takes over the working area.
                      // It gets the FULL detail rather than the rail's compact
                      // block: the pane is the whole panel width, so there is
                      // no reason to show the abbreviated version of something
                      // there is room for.
                      ? _splitFullDetail()
                      : (!stacked && _splitDetailFull)
                      ? _splitFullDetail()
                      : _splitEventList(stacked),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The search box, at panel scale.
  ///
  /// Same `_searchCtrl` the mobile bar uses — its listener already drives
  /// `_searchQuery`, so typing here filters through exactly the same path — and
  /// the same `onSubmitted` re-fetch.
  Widget _splitSearchField() {
    return TextField(
      controller: _searchCtrl,
      onSubmitted: (_) => _loadEvents(),
      style: const TextStyle(fontSize: 13.5),
      decoration: qaInputDecoration(hint: 'Search events by title, venue…')
          .copyWith(
            prefixIcon: const Icon(
              Icons.search_rounded,
              size: 18,
              color: CitizenUi.textFaint,
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 38,
              minHeight: 38,
            ),
            suffixIcon: _searchCtrl.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded, size: 16),
                    color: CitizenUi.textFaint,
                    splashRadius: 16,
                    // The controller's own listener updates `_searchQuery`, so
                    // clearing it is all this has to do.
                    onPressed: _searchCtrl.clear,
                  ),
          ),
    );
  }

  /// Every filter, wrapped where there is room and scrolled where there is not.
  ///
  /// ── Why the "More" disclosure is gone here ───────────────────────────────
  /// On a phone the nine chips do not fit, so the mobile bar hides four behind
  /// a tune icon. The panel never hides one: a disclosure is a click spent on
  /// nothing when the same width can simply be scrolled. The mobile bar keeps
  /// its own behaviour untouched — this is a second rendering of the same
  /// `_selectedFilter`, not a change to the first.
  ///
  /// ── Why STACKED does not wrap ────────────────────────────────────────────
  /// Wrapping is right in the ~640px column the side-by-side layout gives this:
  /// nine chips make two lines, ~71px, and the list keeps the rest. In the
  /// stacked panel the same [Wrap] made THREE lines (All/Today/Upcoming/Recent,
  /// then Health/Training/Environment/Special, then Others) — ~110px of filter
  /// bar sitting under a header, a tab switcher and a search box, on a viewport
  /// that had ~500px for all of it. What was left showed one and a half events,
  /// which is a browse surface you cannot browse.
  ///
  /// One horizontally scrolling row is ~32px, so ~78px goes back to the list —
  /// about two more event rows. Nothing is hidden and nothing is behind an
  /// extra tap: every chip is in the row, in the same order, and the row
  /// scrolls. It is also the idiom this very screen already uses on mobile
  /// (see [_buildFilterChips]), so the panel is not inventing a third way to
  /// present the same nine filters.
  Widget _splitFilterChips(bool stacked) {
    final chips = [
      for (final f in [..._primaryFilters, ..._moreFilters])
        _SplitFilterChip(
          label: f,
          selected: _selectedFilter == f,
          onTap: () => setState(() => _selectedFilter = f),
        ),
    ];

    if (!stacked) {
      return Wrap(spacing: 7, runSpacing: 7, children: chips);
    }

    // A fixed height, because a horizontal [ListView] has no intrinsic one and
    // this sits in the head's unbounded Column. 32 is what the chip measures:
    // 12px text on a 1.0 height (~16), plus 7 of padding a side, plus the 1px
    // border. `clipBehavior: none` would spill the row over the search box
    // above it, so the default clip stays.
    return SizedBox(
      height: _kSplitChipRowHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 7),
        // Centred, so the chips do not stretch to the row's full height and
        // come out as tall pills.
        itemBuilder: (_, i) => Center(child: chips[i]),
      ),
    );
  }

  /// The list itself — the same four sections the mobile body renders, off the
  /// same getters, drawn as full-width panel rows instead of horizontally
  /// scrolling cards.
  ///
  /// ── Why the cards are not reused ─────────────────────────────────────────
  /// `_buildEventGrid` is a horizontal [ListView] of ~200px cards, which is
  /// right on a phone and wrong in a 660px column: a sideways scroller nested
  /// inside the panel's vertical one, showing two and a half cards with the
  /// rest hidden off the right edge of a card that has room for all of them.
  /// The rows below are the same data and the same tap, laid out for the space
  /// that actually exists.
  Widget _splitEventList(bool stacked) {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.wifi_off_rounded,
              size: 40,
              color: CitizenUi.borderStrong,
            ),
            const SizedBox(height: 12),
            const Text(
              'Could not load events',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: CitizenUi.textMuted,
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () => _loadEvents(isInitialLoad: true),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    // A skeleton, not a spinner. The list has a KNOWN shape — a section label
    // over rows of thumbnail-plus-two-lines — so the wait can show that shape
    // instead of a disc that says only "something is happening". It also holds
    // the column's height steady, where a centred spinner collapses to nothing
    // and lets the panel jump when the rows land.
    if (_isLoading) return const _SplitEventListSkeleton();

    final featured = _featuredEvents;
    final today = _todayEvents;
    final upcoming = _upcomingEvents;
    final recent = _recentEvents;

    if (featured.isEmpty &&
        today.isEmpty &&
        upcoming.isEmpty &&
        recent.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.event_busy_rounded,
              size: 40,
              color: CitizenUi.borderStrong,
            ),
            const SizedBox(height: 12),
            const Text(
              'No events found',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: CitizenUi.textMuted,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Try a different filter or search term.',
              style: TextStyle(fontSize: 12.5, color: CitizenUi.textFaint),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // A refresh in flight is a hairline at the top of the list rather than
        // a spinner replacing it: the events already on screen stay readable
        // and stay clickable while the new ones arrive.
        if (_isRefreshing)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        ..._splitSection('Featured', featured, stacked),
        ..._splitSection('Today', today, stacked),
        ..._splitSection('Upcoming', upcoming, stacked),
        ..._splitSection('Recent', recent, stacked),
      ],
    );
  }

  /// One labelled group of rows, or nothing at all when the group is empty.
  List<Widget> _splitSection(
    String label,
    List<EventItem> events,
    bool stacked,
  ) {
    if (events.isEmpty) return const [];
    final selectedId = _splitSelectedId;
    return [
      Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: CitizenUi.textFaint,
          ),
        ),
      ),
      for (final event in events)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _SplitEventRow(
            key: ValueKey(event.id),
            event: event,
            selected: event.id == selectedId,
            onTap: () => _splitSelect(event, stacked: stacked),
          ),
        ),
      const SizedBox(height: 6),
    ];
  }

  // ── Right rail: the selected event ────────────────────────────────────────

  /// The "back to the list" bar that replaces the search box while the left
  /// column is showing one event.
  ///
  /// It sits in the FIXED head, where the search box was, so the way out of the
  /// detail is in the same place as the way to narrow the list — and never
  /// scrolls away from the thing it undoes.
  Widget _splitDetailBackBar() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() => _splitDetailFull = false),
          icon: const Icon(Icons.arrow_back_rounded, size: 16),
          label: const Text('Back to events'),
          style: TextButton.styleFrom(
            foregroundColor: CitizenUi.accent,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: const Size(0, 36),
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  /// The complete event — everything the standalone `/home/event/:id` page
  /// shows, laid out for the panel instead of for a phone.
  ///
  /// ── Why this exists rather than a link to that page ─────────────────────
  /// Opening the route closed the modal and landed on a 480px-scaled page with
  /// its own dark hero panel: a different surface, a different shape, and the
  /// browsing context gone. The panel is the surface now, so the detail is
  /// rendered here. The route is not deleted — it is still what an event's
  /// shareable, reload-proof address is, and [_splitShare] hands that address
  /// out without going to it.
  ///
  /// Every value is read off [_splitSelected] on each build, so this and the
  /// rail are two renderings of one event rather than two copies of it.
  Widget _splitFullDetail() {
    final event = _splitSelected;
    if (event == null) return _splitDetailEmpty();

    final whatToExpect = _splitBullets(event.whatToExpect);
    final requirements = _splitBullets(event.requirements);
    final description = event.description?.trim() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Poster beside the headline ───────────────────────────────────
        // Side by side rather than stacked: the column is wide enough that a
        // full-bleed image would push every word below the fold, which is the
        // shape the phone page has and the reason it needed scrolling to read
        // a two-line description.
        LayoutBuilder(
          builder: (context, c) {
            final narrow = c.maxWidth < 460;
            final poster = event.imageUrl == null
                ? null
                : ClipRRect(
                    borderRadius: BorderRadius.circular(CitizenUi.cardRadius),
                    child: SizedBox(
                      width: narrow ? double.infinity : 200,
                      height: narrow ? 150 : 132,
                      child: CachedNetworkImage(
                        imageUrl: event.imageUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => const _ShimmerBox(),
                        errorWidget: (_, _, _) => Container(
                          color: CitizenUi.subtle,
                          child: const Icon(
                            Icons.image_not_supported_rounded,
                            color: CitizenUi.textFaint,
                          ),
                        ),
                      ),
                    ),
                  );

            final headline = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    _splitCategoryChip(event),
                    const SizedBox(width: 8),
                    Flexible(child: _splitCountdownChip(event)),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  event.title,
                  style: const TextStyle(
                    fontSize: 20,
                    height: 1.25,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: CitizenUi.textPrimary,
                  ),
                ),
              ],
            );

            if (poster == null) return headline;
            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [poster, const SizedBox(height: 12), headline],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                poster,
                const SizedBox(width: 16),
                Expanded(child: headline),
              ],
            );
          },
        ),

        const SizedBox(height: 18),
        const Divider(height: 1, color: CitizenUi.border),
        const SizedBox(height: 16),

        // ── The three facts, as icon rows ────────────────────────────────
        _splitFactRow(
          Icons.place_rounded,
          event.location,
          sub: 'Aparri, Cagayan',
        ),
        const SizedBox(height: 12),
        _splitFactRow(
          Icons.event_rounded,
          event.date,
          sub: DateFormat('EEEE').format(event.eventDate),
        ),
        const SizedBox(height: 12),
        _splitFactRow(Icons.schedule_rounded, event.time),

        const SizedBox(height: 20),

        // ── About ─────────────────────────────────────────────────────────
        _splitDetailSection(
          'About This Event',
          Text(
            description.isEmpty ? 'No description given.' : description,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.55,
              fontStyle: description.isEmpty
                  ? FontStyle.italic
                  : FontStyle.normal,
              color: description.isEmpty
                  ? CitizenUi.textFaint
                  : CitizenUi.textSecondary,
            ),
          ),
        ),

        // ── What to Expect / Requirements ────────────────────────────────
        // Two columns where the panel is wide enough for them, stacked where it
        // is not. Both are omitted entirely when empty rather than drawn as an
        // empty heading, exactly as the standalone page does.
        if (whatToExpect.isNotEmpty || requirements.isNotEmpty) ...[
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, c) {
              final side = <Widget>[
                if (whatToExpect.isNotEmpty)
                  _splitDetailSection(
                    'What to Expect',
                    _splitBulletList(whatToExpect),
                  ),
                if (requirements.isNotEmpty)
                  _splitDetailSection(
                    'Requirements',
                    _splitBulletList(requirements),
                  ),
              ];
              if (side.length == 1 || c.maxWidth < 460) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < side.length; i++) ...[
                      if (i > 0) const SizedBox(height: 18),
                      side[i],
                    ],
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: side[0]),
                  const SizedBox(width: 20),
                  Expanded(child: side[1]),
                ],
              );
            },
          ),
        ],
      ],
    );
  }

  /// Splits a stored multi-line field into its lines, dropping the blanks.
  ///
  /// Same parsing the standalone page does, so a bullet list reads identically
  /// in both places.
  List<String> _splitBullets(String? raw) => (raw ?? '')
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  Widget _splitBulletList(List<String> items) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final item in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    color: CitizenUi.accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  item,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: CitizenUi.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
  );

  Widget _splitDetailSection(String title, Widget child) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
          color: CitizenUi.textPrimary,
        ),
      ),
      const SizedBox(height: 8),
      child,
    ],
  );

  Widget _splitFactRow(IconData icon, String value, {String? sub}) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 18, color: CitizenUi.accent),
      const SizedBox(width: 11),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: CitizenUi.textPrimary,
              ),
            ),
            if (sub != null) ...[
              const SizedBox(height: 1),
              Text(
                sub,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: CitizenUi.textFaint,
                ),
              ),
            ],
          ],
        ),
      ),
    ],
  );

  Widget _splitCategoryChip(EventItem event) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: event.categoryColor.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      event.category,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.3,
        color: event.categoryColor,
      ),
    ),
  );

  /// "Today" / "Tomorrow" / "In n days" / "n days ago" — the standalone page's
  /// countdown, which is the one thing on it that a date alone does not say.
  Widget _splitCountdownChip(EventItem event) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(
      event.eventDate.year,
      event.eventDate.month,
      event.eventDate.day,
    );
    final days = d.difference(today).inDays;
    final label = switch (days) {
      0 => 'Today',
      1 => 'Tomorrow',
      -1 => 'Yesterday',
      _ => days > 0 ? 'In $days days' : '${-days} days ago',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: CitizenUi.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: CitizenUi.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.schedule_rounded,
            size: 12,
            color: CitizenUi.textMuted,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: CitizenUi.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The "nothing selected" state, shared by the rail and the detail column.
  Widget _splitDetailEmpty() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: const [
      SizedBox(height: 30),
      Icon(Icons.touch_app_rounded, size: 34, color: CitizenUi.borderStrong),
      SizedBox(height: 12),
      Text(
        'Select an event',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: CitizenUi.textMuted,
        ),
      ),
      SizedBox(height: 5),
      Text(
        'Pick one from the list to see its date, venue and details here.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12.5,
          height: 1.5,
          color: CitizenUi.textFaint,
        ),
      ),
    ],
  );

  /// Hands out the event's shareable address without navigating to it.
  void _splitShare() {
    final event = _splitSelected;
    final share = widget.onShareEvent;
    if (event == null || share == null) return;
    share(event);
  }

  /// The detail block.
  ///
  /// One block, two homes: the rail renders it side by side, and the stacked
  /// panel renders THE SAME widget inside its Details pane. It reads the event
  /// live off [_splitSelected] on each build, so the two placements cannot
  /// drift — and a selection that expires out of the list falls back to the
  /// empty state in both at once.
  Widget _splitDetailBlock() {
    final event = _splitSelected;

    // The rail is never blank: with nothing selected it says what to do, in the
    // place the answer will appear. Same words as the detail column's, from one
    // definition.
    if (event == null) return _splitDetailEmpty();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // The poster, at a fixed HEIGHT so a rail full of events keeps one
        // shape whatever the uploads are.
        //
        // ── Why a height and not an aspect ratio ────────────────────────────
        // 16:9 across the rail draws ~207px, and the rail is inside the panel's
        // fixed frame: that much poster pushed VENUE and ABOUT below the fold,
        // so the rail showed a picture and the two lines a citizen is least
        // likely to already know were the ones cut. A picture is worth its
        // place here, but not at the cost of where and what the event is. 130
        // keeps it clearly a poster and buys both rows back.
        if (event.imageUrl != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(CitizenUi.controlRadius),
            child: SizedBox(
              height: 130,
              width: double.infinity,
              child: CachedNetworkImage(
                imageUrl: event.imageUrl!,
                fit: BoxFit.cover,
                placeholder: (_, _) => const _ShimmerBox(),
                errorWidget: (_, _, _) => Container(
                  color: CitizenUi.subtle,
                  child: const Icon(
                    Icons.image_not_supported_rounded,
                    color: CitizenUi.textFaint,
                  ),
                ),
              ),
            ),
          ),
        if (event.imageUrl != null) const SizedBox(height: 14),

        // The category, in the colour the event carries — the one piece of
        // per-event identity in an otherwise uniform rail.
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: event.categoryColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              event.category,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
                color: event.categoryColor,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          event.title,
          style: const TextStyle(
            fontSize: 16,
            height: 1.3,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
            color: CitizenUi.textPrimary,
          ),
        ),
        const SizedBox(height: 16),

        // The same ruled rows the three forms' rails use, so a citizen who has
        // filed a report reads this rail the same way.
        QaSummaryRow(
          icon: Icons.event_rounded,
          label: 'DATE',
          value: event.date,
        ),
        QaSummaryRow(
          icon: Icons.schedule_rounded,
          label: 'TIME',
          value: event.time,
        ),
        QaSummaryRow(
          icon: Icons.place_rounded,
          label: 'VENUE',
          value: event.location,
        ),
        QaSummaryRow(
          icon: Icons.notes_rounded,
          label: 'ABOUT',
          value: event.description,
          placeholder: 'No description given',
          // Deliberately short. The rail is a glance — the full description,
          // what to expect and the requirements are what the event's own page
          // is for, and that page is one button away.
          maxLines: 4,
          divider: false,
        ),
      ],
    );
  }

  /// The actions, which follow whatever is being LOOKED at.
  ///
  /// ── Why this surface keeps its buttons on every pane ────────────────────
  /// The three quick-action FORMS drop their pinned zone on the Summary pane,
  /// because their buttons act on a STEP and a summary is not a step. Here it
  /// is the other way round: the pane is the thing being acted on, so the zone
  /// stays and its contents follow — "View full details" while browsing, and
  /// "Share event" once one is open.
  ///
  /// [detailPane] is what is on screen: the expanded detail (side by side, the
  /// left column has been given over to it; stacked, the Details tab), or the
  /// list. [compact] is the pinned zone's sizing.
  Widget _splitActionStack({bool compact = false, bool detailPane = false}) {
    final event = _splitSelected;

    void handleClose() {
      final close = widget.onClose;
      if (close == null) return;
      close();
    }

    return QaActionStack(
      compact: compact,
      children: [
        if (detailPane)
          // Share, not "open" — the panel never leaves for the standalone page
          // any more, so the only thing that page is still good for is being an
          // address someone else can follow.
          QaActionButton(
            label: 'Share Event',
            icon: Icons.ios_share_rounded,
            compact: compact,
            onTap: (event == null || widget.onShareEvent == null)
                ? null
                : _splitShare,
          )
        else
          QaActionButton(
            label: 'View Full Details',
            icon: Icons.arrow_forward_rounded,
            compact: compact,
            // Null until something is selected: the button stays in place
            // rather than appearing when the rail fills, so the stack does not
            // change height under the pointer.
            onTap: event == null
                ? null
                : () => setState(() {
                    // Stacked has no second column to move the detail into, so
                    // there the Details PANE is the expanded view; side by side
                    // the left column takes it.
                    if (compact) {
                      _splitTab = 1;
                    } else {
                      _splitDetailFull = true;
                    }
                  }),
          ),
        // Only the stacked layout needs a way back: side by side the left
        // column carries its own "Back to events" bar in the head, and the list
        // is one click away there anyway.
        if (compact && detailPane)
          QaActionButton(
            label: 'Back to list',
            icon: Icons.arrow_back_rounded,
            kind: QaActionKind.secondary,
            compact: compact,
            onTap: () => setState(() => _splitTab = 0),
          ),
        QaActionButton(
          label: 'Close',
          kind: QaActionKind.danger,
          compact: compact,
          onTap: handleClose,
        ),
      ],
    );
  }

  /// The right-hand column.
  ///
  /// ── Side by side ─────────────────────────────────────────────────────────
  /// The full rail: header, the selected event, the buttons, inside a
  /// [SingleChildScrollView] — a rail carrying a poster and four rows is the
  /// one most likely to need the fallback the forms' rails rarely reach.
  ///
  /// ── Stacked ──────────────────────────────────────────────────────────────
  /// Reduced to the ACTION ZONE and returned BARE, for the same reason as the
  /// forms: a scroll view here would share an edge with the working area's and
  /// arbitrate drags with it. The header and the detail are not dropped — the
  /// working card takes them over (see [_splitLeftPanel]).
  Widget _splitRightRail(bool stacked) {
    if (stacked) {
      // Tighter chrome than the rail's 20 a side: this card is a bar, and every
      // pixel of padding on it is a pixel the list above loses.
      return QaPanelCard(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: _splitActionStack(compact: true, detailPane: _splitTab == 1),
      );
    }

    return QaPanelCard(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      // ── Head and actions fixed, only the SUMMARY scrolls ────────────────
      // The rail is drawn to the panel's fixed height, so when its contents
      // exceed that something has to give. Scrolling the whole column gave way
      // at the bottom — the buttons — which is the one part that must never be
      // out of reach: a citizen who cannot see Cancel cannot leave, and a
      // Continue below the fold reads as a form with no way forward.
      //
      // `MainAxisSize.min` + `Flexible` is what keeps this free where there is
      // room. Below the frame the column shrink-wraps exactly as it always did
      // and the summary keeps its natural height, so nothing moves; only once
      // the content genuinely overruns does the summary give up the difference
      // and scroll inside itself. The panel's ScrollConfiguration keeps the bar
      // hidden either way.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          QaRailHeader(title: 'Details', onClose: widget.onClose ?? () {}),
          const SizedBox(height: 20),
          Flexible(child: SingleChildScrollView(child: _splitDetailBlock())),
          const SizedBox(height: 34),
          _splitActionStack(detailPane: _splitDetailFull),
        ],
      ),
    );
  }

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
            'assets/images/newslogo.webp',
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
          border: Border.all(color: CitizenUi.sharedBorder),
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
              'assets/images/activity.webp',
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
          border: Border.all(color: CitizenUi.sharedStroke),
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
            Container(
              width: 1,
              height: w * 0.055,
              color: CitizenUi.sharedStroke,
            ),
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
          _loadEvents();
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
              color: isActive ? AppColors.primaryBlue : CitizenUi.sharedStroke,
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
          border: Border.all(color: CitizenUi.sharedStroke),
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
                              ? CachedNetworkImage(
                                  imageUrl: event.imageUrl!,
                                  fit: BoxFit.cover,
                                  fadeInDuration: const Duration(
                                    milliseconds: 300,
                                  ),
                                  fadeOutDuration: const Duration(
                                    milliseconds: 100,
                                  ),
                                  placeholder: (context, url) =>
                                      const _ShimmerBox(),
                                  errorWidget: (context, url, error) =>
                                      Container(
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
                      Align(
                        alignment: Alignment.centerLeft,
                        child: EventStatusPill(
                          eventDate: event.eventDate,
                          eventTime: event.time,
                          fontSize: w * 0.026,
                        ),
                      ),
                      SizedBox(height: w * 0.012),
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
                        'assets/images/report/location.webp',
                        event.location,
                        AppColors.primaryBlue,
                        w,
                      ),
                      SizedBox(height: w * 0.008),
                      _infoRow(
                        'assets/images/calendar.webp',
                        event.date,
                        AppColors.green,
                        w,
                      ),
                      SizedBox(height: w * 0.008),
                      _infoRow(
                        'assets/images/clock.webp',
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
                          onPressed: () => _openEvent(event),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.green,
                            elevation: 0,
                            padding: EdgeInsets.symmetric(vertical: w * 0.036),
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
          border: Border.all(color: CitizenUi.sharedStroke),
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
                        ? CachedNetworkImage(
                            imageUrl: event.imageUrl!,
                            fit: BoxFit.cover,
                            fadeInDuration: const Duration(milliseconds: 300),
                            fadeOutDuration: const Duration(milliseconds: 100),
                            placeholder: (context, url) => const _ShimmerBox(),
                            errorWidget: (context, url, error) => Container(
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
                Positioned(
                  top: w * 0.015,
                  right: w * 0.015,
                  child: EventStatusPill(
                    eventDate: event.eventDate,
                    eventTime: event.time,
                    fontSize: w * 0.024,
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
                    'assets/images/report/location.webp',
                    event.location,
                    AppColors.primaryBlue,
                    w,
                    small: true,
                  ),
                  SizedBox(height: w * 0.005),
                  _infoRow(
                    'assets/images/calendar.webp',
                    event.date,
                    AppColors.green,
                    w,
                    small: true,
                  ),
                  SizedBox(height: w * 0.005),
                  _infoRow(
                    'assets/images/clock.webp',
                    event.time,
                    AppColors.orange,
                    w,
                    small: true,
                  ),
                  SizedBox(height: w * 0.012),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _openEvent(event),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        elevation: 0,
                        padding: EdgeInsets.symmetric(vertical: w * 0.034),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(w * 0.02),
                        ),
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

// ── Per-image shimmer placeholder ─────────────────────────────────────────
// Self-contained animated shimmer shown while a network image is loading.
// Dependency-free: a light band swept across a grey box. Fills its parent,
// so the surrounding SizedBox controls its size.
class _ShimmerBox extends StatefulWidget {
  const _ShimmerBox();

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmerCtrl;

  @override
  void initState() {
    super.initState();
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shimmerCtrl,
      builder: (context, child) {
        final t = _shimmerCtrl.value;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment(-1.0 - 2.0 * (1 - t), 0),
              end: Alignment(1.0 - 2.0 * (1 - t), 0),
              colors: const [
                Color(0xFFE5E7EB),
                Color(0xFFF3F4F6),
                Color(0xFFE5E7EB),
              ],
              stops: const [0.35, 0.5, 0.65],
            ).createShader(bounds);
          },
          child: Container(color: const Color(0xFFE5E7EB)),
        );
      },
    );
  }
}

// ── Split-panel row widgets (citizen web only) ───────────────────────────────
//
// Both are stateful only because they carry a HOVER state, which exists for a
// pointer and means nothing on touch. They live here rather than in the shared
// chrome because a filter chip and an event row are this surface's shapes; the
// pieces every quick action shares are in quick_action_split_panel.dart.

/// The browse list's loading state: one section label over four placeholder
/// rows, each the exact geometry of a [_SplitEventRow] so nothing shifts when
/// the real events replace them.
class _SplitEventListSkeleton extends StatelessWidget {
  const _SplitEventListSkeleton();

  /// Matches [_SplitEventRowState._thumb].
  static const double _thumb = 54;

  /// A single shimmering bar. [width] null means "fill the row".
  static Widget _bar(double height, {double? width, double radius = 5}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(height: height, width: width, child: const _ShimmerBox()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Stands in for the "UPCOMING" section label.
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: _bar(9, width: 74, radius: 4),
          ),
        ),
        // Four rows: enough to read as a list rather than as one stray card,
        // and few enough that the real result rarely shows fewer.
        for (var i = 0; i < 4; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: CitizenUi.surface,
                borderRadius: BorderRadius.circular(CitizenUi.controlRadius),
                border: Border.all(color: CitizenUi.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: const SizedBox(
                      width: _thumb,
                      height: _thumb,
                      child: _ShimmerBox(),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // The title line, at a width that varies row to row —
                        // four identical bars read as a table, not as titles.
                        _bar(13, width: i.isEven ? 190.0 : 140.0),
                        const SizedBox(height: 9),
                        // The date + venue line.
                        Row(
                          children: [
                            _bar(10, width: 76),
                            const SizedBox(width: 10),
                            Expanded(child: _bar(10)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // The category colour bar.
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: const SizedBox(
                      width: 4,
                      height: _thumb,
                      child: _ShimmerBox(),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// One filter in the panel's wrapping chip row.
class _SplitFilterChip extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SplitFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_SplitFilterChip> createState() => _SplitFilterChipState();
}

class _SplitFilterChipState extends State<_SplitFilterChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? CitizenUi.accent
                : (_hover ? CitizenUi.accentWash : CitizenUi.subtle),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? CitizenUi.accent
                  : (_hover
                        ? CitizenUi.accent.withValues(alpha: 0.35)
                        : CitizenUi.border),
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? Colors.white : CitizenUi.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// One event in the panel's browse list.
///
/// A full-width row rather than the mobile card: a small square thumbnail, the
/// title, and the date/venue underneath. The selected row is outlined in the
/// accent, which is what ties it to the rail currently showing it.
class _SplitEventRow extends StatefulWidget {
  final EventItem event;
  final bool selected;
  final VoidCallback onTap;

  const _SplitEventRow({
    super.key,
    required this.event,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_SplitEventRow> createState() => _SplitEventRowState();
}

class _SplitEventRowState extends State<_SplitEventRow> {
  bool _hover = false;

  static const double _thumb = 54;

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final selected = widget.selected;
    final radius = BorderRadius.circular(CitizenUi.controlRadius);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: selected
                ? CitizenUi.accent.withValues(alpha: 0.07)
                : (_hover ? CitizenUi.accentWash : CitizenUi.surface),
            borderRadius: radius,
            border: Border.all(
              color: selected
                  ? CitizenUi.accent
                  : (_hover
                        ? CitizenUi.accent.withValues(alpha: 0.35)
                        : CitizenUi.border),
              width: selected ? 1.8 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: _thumb,
                  height: _thumb,
                  child: event.imageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: event.imageUrl!,
                          fit: BoxFit.cover,
                          placeholder: (_, _) => const _ShimmerBox(),
                          errorWidget: (_, _, _) => _fallbackThumb(event),
                        )
                      : _fallbackThumb(event),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      event.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? CitizenUi.accent
                            : CitizenUi.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Date and venue on one line, with the venue giving way
                    // first — a long venue must not push the date off the row,
                    // since the date is the reason most people are scanning.
                    Row(
                      children: [
                        const Icon(
                          Icons.event_rounded,
                          size: 12,
                          color: CitizenUi.textFaint,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          event.date,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: CitizenUi.textMuted,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Icon(
                          Icons.place_rounded,
                          size: 12,
                          color: CitizenUi.textFaint,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            event.location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: CitizenUi.textFaint,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // The category as a colour bar rather than a second text label:
              // the row is already carrying a title, a date and a venue, and
              // the rail spells the category out the moment this is selected.
              const SizedBox(width: 8),
              Container(
                width: 4,
                height: _thumb,
                decoration: BoxDecoration(
                  color: event.categoryColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fallbackThumb(EventItem event) => Container(
    color: event.categoryColor.withValues(alpha: 0.12),
    child: Icon(Icons.event_rounded, size: 22, color: event.categoryColor),
  );
}
