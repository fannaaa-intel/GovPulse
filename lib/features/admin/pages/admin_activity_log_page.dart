import 'dart:ui' as ui show TextDirection;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_dialog.dart';
import '../providers/admin_activity_provider.dart';
import '../theme/admin_ui.dart';
import '../widgets/admin_dialog_back.dart';
import '../widgets/admin_skeleton.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Admin → Settings → Activity log → "View all"
//
//  Full, scrollable history of every logged admin action (Settings only shows
//  the newest 5 inline). Adds a date-range filter — quick presets plus a
//  custom range — and shows the exact timestamp on each row, grouped by day.
// ════════════════════════════════════════════════════════════════════════════

/// Width at or above which the history opens as a centred pop-up modal rather
/// than a pushed screen. Below it — a phone-width browser window, and the
/// mobile app at any size — a modal would be a near-full-bleed panel with a
/// useless sliver of scrim, so the history takes over the screen instead.
const double _kModalMinWidth = 760;

/// Opens the full activity-log history.
///
/// Medium and large screens (web/desktop) get a centred pop-up modal over a
/// frosted console, matching every other admin pop-up. Small screens and the
/// mobile app get a pushed full screen, using the app-wide sub-screen motion:
/// instant on entry (the content does its own slide-up + fade-in), fade-out on
/// the way back — matching the citizen settings sub-screens.
void showAdminActivityLog(BuildContext context) {
  // Decided once, at the tap: an already-open modal keeps its own layout, and
  // a resize past the breakpoint is not worth tearing the route down for. The
  // mobile app always pushes — a tablet clears the width breakpoint, but a
  // dialog is the wrong idiom for a touch shell.
  final asModal =
      kIsWeb && MediaQuery.of(context).size.width >= _kModalMinWidth;

  if (!asModal) {
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, _, _) => const _ActivityLogScreen(),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
    return;
  }

  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Activity log',
    barrierColor: Colors.black.withValues(alpha: 0.12),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, _, _) => const _ActivityLogModal(),
    transitionBuilder: (_, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      final content = FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, -0.03),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
      // Frost the console behind the panel, ramping with the same animation so
      // it grows on open and clears on close — matching every other pop-up.
      return withDialogBlur(anim, content);
    },
  );
}

/// [MaterialScrollBehavior] that scrolls exactly as the default does but paints
/// no scrollbar — the same trick the citizen shell uses, scoped here to the
/// activity log so it cannot restyle the rest of the console.
///
/// Only [buildScrollbar] is overridden, so wheel, trackpad, drag and keyboard
/// scrolling all still work: the bar goes, the scrolling stays. [dragDevices]
/// adds the mouse so click-and-drag keeps working on the web once there is no
/// visible bar to grab.
class _NoScrollbarBehavior extends MaterialScrollBehavior {
  const _NoScrollbarBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;

  @override
  Set<PointerDeviceKind> get dragDevices => {
    ...super.dragDevices,
    PointerDeviceKind.mouse,
  };
}

/// The modal shell: a rounded, height-capped card holding the same history
/// content the pushed screen shows.
class _ActivityLogModal extends StatelessWidget {
  const _ActivityLogModal();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    // Leave breathing room on every side so the scrim and blur stay visible;
    // the card never outgrows the viewport on a short laptop screen.
    final maxH = (size.height - 112).clamp(400.0, 760.0);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 56),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 680, maxHeight: maxH),
          child: Material(
            color: AdminUi.surface,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            elevation: 24,
            shadowColor: Colors.black.withValues(alpha: 0.28),
            child: const _ActivityLogScreen(inModal: true),
          ),
        ),
      ),
    );
  }
}

// Same visual language as the inline Settings rows.
IconData _activityIcon(String action) => switch (action) {
  'staff_created' => Icons.person_add_alt_1_rounded,
  'user_suspended' => Icons.pause_circle_outline_rounded,
  'suspension_lifted' => Icons.play_circle_outline_rounded,
  'user_restricted' => Icons.block_rounded,
  'restriction_lifted' => Icons.lock_open_rounded,
  'user_deactivated' => Icons.person_off_rounded,
  'user_reactivated' => Icons.person_outline_rounded,
  'broadcast_sent' => Icons.campaign_rounded,
  'identity_revealed' => Icons.visibility_rounded,
  _ => Icons.history_rounded,
};

Color _activityColor(String action) => switch (action) {
  'user_suspended' || 'user_restricted' || 'user_deactivated' ||
        'identity_revealed' =>
    AppColors.red,
  'suspension_lifted' || 'restriction_lifted' || 'user_reactivated' =>
    AppColors.green,
  'staff_created' || 'broadcast_sent' => AppColors.primaryBlue,
  _ => AdminUi.textMuted,
};

/// Quick date-range presets for the filter bar. [custom] is driven by the
/// date-range picker; the rest are rolling windows.
enum _Range { all, today, days7, days30, custom }

class _ActivityLogScreen extends ConsumerStatefulWidget {
  /// True when hosted inside [_ActivityLogModal] — the card already provides
  /// the surface, rounding and inset, so the content drops the Scaffold's
  /// page background and SafeArea and skips the entry slide (the modal's own
  /// transition covers it).
  final bool inModal;
  const _ActivityLogScreen({this.inModal = false});

  @override
  ConsumerState<_ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends ConsumerState<_ActivityLogScreen>
    with SingleTickerProviderStateMixin {
  _Range _range = _Range.all;
  DateTimeRange? _custom; // set only when _range == custom
  late Future<List<AdminActivity>> _future;

  // Content slide-up + fade-in on entry (the route itself opens instantly).
  late final AnimationController _entryCtrl;
  late final Animation<double> _entryFade;
  late final Animation<Offset> _entrySlide;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _entryFade = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _entrySlide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));
    if (!widget.inModal) _entryCtrl.forward();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    super.dispose();
  }

  /// Resolves the active preset to an inclusive-start / exclusive-end window.
  ({DateTime? from, DateTime? to}) _bounds() {
    final now = DateTime.now();
    final startToday = DateTime(now.year, now.month, now.day);
    switch (_range) {
      case _Range.all:
        return (from: null, to: null);
      case _Range.today:
        return (from: startToday, to: startToday.add(const Duration(days: 1)));
      case _Range.days7:
        return (from: startToday.subtract(const Duration(days: 6)), to: null);
      case _Range.days30:
        return (from: startToday.subtract(const Duration(days: 29)), to: null);
      case _Range.custom:
        if (_custom == null) return (from: null, to: null);
        return (
          from: _custom!.start,
          // Include the whole end day.
          to: DateTime(
            _custom!.end.year,
            _custom!.end.month,
            _custom!.end.day,
          ).add(const Duration(days: 1)),
        );
    }
  }

  Future<List<AdminActivity>> _load() {
    final b = _bounds();
    return ref
        .read(adminActivityProvider.notifier)
        .fetchHistory(from: b.from, to: b.to);
  }

  void _select(_Range r) {
    if (r == _range && r != _Range.custom) return;
    setState(() {
      _range = r;
      _future = _load();
    });
  }

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    // In calendar mode the framework's range picker hardcodes its own size to
    // MediaQuery.sizeOf(context) with zero inset padding (date_picker.dart
    // ~1663), so it takes over the whole viewport no matter how wide the
    // window is — which on a desktop browser left a full-screen sheet with a
    // narrow calendar stranded in the middle of it. There is no flag for this,
    // so the size it reads is what gets shrunk: on the same screens that get
    // the modal history, the picker is handed a modal-sized MediaQuery and
    // centred, and it lays itself out to fit that box instead.
    final asModal =
        kIsWeb && MediaQuery.of(context).size.width >= _kModalMinWidth;

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialDateRange:
          _custom ??
          DateTimeRange(
            start: now.subtract(const Duration(days: 7)),
            end: now,
          ),
      builder: (ctx, child) {
        final base = Theme.of(ctx);
        final theme = base.copyWith(
          colorScheme: base.colorScheme.copyWith(
            primary: AppColors.primaryBlue,
          ),
          // Full-screen mode paints square corners by design; once the picker
          // is a card (desktop) or a bottom sheet (phone), it needs rounding.
          // Rounding the dialog is not enough on its own: the inner
          // _CalendarRangePickerDialog paints an opaque square canvas over the
          // whole box, so that surface has to go transparent for the rounded
          // shape underneath to be the thing you see. Both branches are
          // rounded now, so both need it.
          datePickerTheme: base.datePickerTheme.copyWith(
            rangePickerShape: asModal
                ? RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  )
                : const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(22),
                    ),
                  ),
            rangePickerBackgroundColor: Colors.transparent,
          ),
        );
        final themed = Theme(data: theme, child: child!);

        if (!asModal) {
          // Phones and the mobile app: the picker is pinned to the BOTTOM and
          // sized to its content rather than stretched to the viewport.
          // Full-screen left a tall band of dead space under the last week row
          // and put Save at the far top corner — the hardest place to reach
          // one-handed.
          final mq = MediaQuery.of(ctx);
          final screen = mq.size;
          // 520 is what the calendar actually needs: ~190 for the header and
          // action bar plus six 50px week rows. Anything taller is the dead
          // space this is fixing; anything shorter clips the last week.
          final sheetH = (screen.height * 0.78).clamp(430.0, 520.0);
          // The sheet sits ON the system navigation bar, so it carries that
          // inset itself — otherwise the last week row hides behind it.
          final bottomInset = mq.padding.bottom;

          return Align(
            alignment: Alignment.bottomCenter,
            child: MediaQuery(
              // The picker measures itself against this, so it must be the
              // calendar's own box — the inset is added outside it.
              data: mq.copyWith(
                size: Size(screen.width, sheetH),
                padding: mq.padding.copyWith(bottom: 0),
              ),
              child: Material(
                color: AdminUi.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: EdgeInsets.only(bottom: bottomInset),
                  child: SizedBox(
                    width: screen.width,
                    height: sheetH,
                    child: themed,
                  ),
                ),
              ),
            ),
          );
        }

        final screen = MediaQuery.of(ctx).size;
        // Sized to the calendar itself — six week rows under the header and
        // action bar — rather than to the viewport, and capped so a short
        // laptop screen still shows the whole card.
        // 560 is measured, not guessed: the header and action bar take ~200px
        // and six week rows at 50px each need ~300 more, so a shorter card
        // clips the last week of a five- or six-row month.
        final w = screen.width.clamp(0.0, 440.0);
        final h = (screen.height - 140).clamp(360.0, 560.0);
        return Center(
          child: MediaQuery(
            data: MediaQuery.of(ctx).copyWith(size: Size(w, h)),
            child: SizedBox(
              width: w,
              height: h,
              // A shadow of its own so the picker reads as sitting ON the
              // history modal rather than punched into it.
              child: DecoratedBox(
                decoration: BoxDecoration(
                  // Opaque ground: the picker's own surface is transparent
                  // (see the theme above), and the shadow must not show
                  // through the card it belongs to.
                  color: AdminUi.surface,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.26),
                      blurRadius: 34,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: themed,
                ),
              ),
            ),
          ),
        );
      },
    );
    if (picked == null) return;
    setState(() {
      _custom = picked;
      _range = _Range.custom;
      _future = _load();
    });
  }

  Future<void> _refresh() async {
    final f = _load();
    setState(() => _future = f);
    await f;
  }

  @override
  Widget build(BuildContext context) {
    // One breakpoint drives the whole layout, so the pushed screen at phone
    // width and the modal at desktop width never disagree about spacing.
    final compact = MediaQuery.of(context).size.width < 600;
    final gutter = compact ? 16.0 : 20.0;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(gutter),
        _filterBar(gutter, compact),
        const Divider(height: 1, color: AdminUi.border),
        Expanded(
          child: ColoredBox(
            color: AdminUi.pageBg,
            child: RefreshIndicator(
              onRefresh: _refresh,
              color: AppColors.primaryBlue,
              child: FutureBuilder<List<AdminActivity>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return _HistorySkeleton(gutter: gutter);
                  }
                  if (snap.hasError) {
                    return _message(
                      'Could not load the activity log.',
                      icon: Icons.cloud_off_rounded,
                      action: TextButton.icon(
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Try again'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.primaryBlue,
                        ),
                      ),
                    );
                  }
                  final items = snap.data ?? const <AdminActivity>[];
                  if (items.isEmpty) {
                    return _message(
                      _range == _Range.all
                          ? 'No admin actions recorded yet.'
                          : 'Nothing in this date range.',
                      icon: Icons.history_rounded,
                      hint: _range == _Range.all
                          ? 'Actions you take in the console show up here.'
                          : 'Try a wider range, or pick "All".',
                    );
                  }
                  return _list(items, gutter);
                },
              ),
            ),
          ),
        ),
      ],
    );

    // The bar is hidden across the whole sheet — the list, the skeleton and
    // the empty state all scroll — so the wrapper sits above every branch.
    final unbarred = ScrollConfiguration(
      behavior: const _NoScrollbarBehavior(),
      child: content,
    );

    if (widget.inModal) return unbarred;

    return Scaffold(
      backgroundColor: AdminUi.pageBg,
      // SafeArea on every edge. `bottom: false` let the list run under the
      // Android gesture/navigation bar, which is the grey band that showed up
      // beneath the last row with a half-hidden action under it. The list's
      // own trailing padding then reads as real breathing room instead of
      // content trapped behind the system bar.
      body: SafeArea(
        child: FadeTransition(
          opacity: _entryFade,
          child: SlideTransition(position: _entrySlide, child: unbarred),
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────
  /// Title block with a live count subtitle, so the sheet says what it is
  /// holding before you have read a single row.
  Widget _header(double gutter) {
    return Container(
      color: AdminUi.surface,
      // The modal keeps a tighter right inset for its close button; the pushed
      // screen has no trailing control now, so it uses the full gutter.
      padding: EdgeInsets.fromLTRB(
        gutter,
        14,
        widget.inModal ? gutter - 6 : gutter,
        12,
      ),
      child: Row(
        children: [
          // Pushed screen → chevron back at the left, like the citizen
          // settings sub-screens. Modal → a top-right X, the convention the
          // other admin dialogs already use.
          if (!widget.inModal) ...[
            AdminDialogBack(onTap: () => Navigator.pop(context)),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Activity log',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: AdminUi.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                // Reads off the same future the list renders, so the count and
                // the rows can never disagree.
                FutureBuilder<List<AdminActivity>>(
                  future: _future,
                  builder: (context, snap) {
                    final n = snap.data?.length;
                    final label = switch (n) {
                      null => 'Loading…',
                      0 => 'No actions',
                      1 => '1 action',
                      _ => '$n actions',
                    };
                    return Text(
                      '$label · ${_rangeLabel()}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AdminUi.textMuted,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          // No refresh button: pull-to-refresh covers it on touch, and the
          // list refetches on every filter change anyway.
          if (widget.inModal)
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded, size: 20),
              color: AdminUi.textMuted,
              tooltip: 'Close',
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }

  /// Plain-language name for the active filter, used in the header subtitle.
  String _rangeLabel() => switch (_range) {
    _Range.all => 'All time',
    _Range.today => 'Today',
    _Range.days7 => 'Last 7 days',
    _Range.days30 => 'Last 30 days',
    _Range.custom => _custom == null ? 'Custom range' : _customLabel(),
  };

  /// Compact label for a chosen custom range, e.g. "Aug 4 – Aug 13".
  String _customLabel() {
    final r = _custom!;
    String d(DateTime t) => DateFormat('MMM d').format(t);
    return '${d(r.start)} – ${d(r.end)}';
  }

  // ── Filter bar ───────────────────────────────────────────────────────────
  /// The four presets on one row, with the custom-range control pinned to the
  /// right of it.
  ///
  /// Two earlier attempts were both wrong in the same way — they treated
  /// "Custom" as a fifth preset. A scrolling Row clipped it mid-word, and a
  /// Wrap dropped it onto a second line where it sat orphaned under "All",
  /// looking misplaced rather than deliberate. It is not a fifth preset: the
  /// other four toggle instantly, this one opens a picker. Giving it its own
  /// fixed slot at the end makes the layout read the same at every width, and
  /// the presets — which are short, and shorten further when compact — always
  /// fit the remaining space on a single line.
  Widget _filterBar(double gutter, bool compact) {
    return Container(
      color: AdminUi.surface,
      padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 14),
      // The presets must fit the space LEFT OVER after the custom control and
      // its divider, so the width is measured rather than assumed: labels step
      // down through three tiers until the row fits, and only if even the
      // shortest tier overflows does it scroll. That is what stops "30 days"
      // being sliced by the divider on a 360px phone.
      child: LayoutBuilder(
        builder: (context, c) {
          // Space the custom control and its divider will take. When a range
          // IS chosen the pill carries its dates and is much wider, so it is
          // measured rather than assumed.
          final customW = (_custom != null && _range == _Range.custom)
              ? _presetsWidth([_customLabel()]) + 23 // + icon and its gap
              : 42.0; // icon-only pill
          const dividerBlock = 21.0; // 10 + 1 + 10
          final presetSpace = c.maxWidth - customW - dividerBlock;

          final tiers = <List<String>>[
            ['All', 'Today', 'Last 7 days', 'Last 30 days'],
            ['All', 'Today', '7 days', '30 days'],
            ['All', 'Today', '7d', '30d'],
          ];
          final ranges = [
            _Range.all,
            _Range.today,
            _Range.days7,
            _Range.days30,
          ];

          List<String> labels = tiers.last;
          for (final tier in tiers) {
            if (_presetsWidth(tier) <= presetSpace) {
              labels = tier;
              break;
            }
          }

          final row = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < labels.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                _filterChip(
                  labels[i],
                  _range == ranges[i],
                  () => _select(ranges[i]),
                ),
              ],
            ],
          );

          return Row(
            children: [
              Expanded(
                child: _presetsWidth(labels) <= presetSpace
                    ? Align(alignment: Alignment.centerLeft, child: row)
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: row,
                      ),
              ),
              const SizedBox(width: 10),
              // A hairline keeps the picker visibly separate from the toggles,
              // so its different behaviour is legible before you tap it.
              Container(width: 1, height: 22, color: AdminUi.border),
              const SizedBox(width: 10),
              _customChip(compact),
            ],
          );
        },
      ),
    );
  }

  /// Laid-out width of a row of preset pills, measured with the same text
  /// style the pills paint so the fit test matches what renders.
  double _presetsWidth(List<String> labels) {
    const style = TextStyle(fontSize: 13, fontWeight: FontWeight.w600);
    var total = 8.0 * (labels.length - 1); // gaps
    for (final l in labels) {
      final tp = TextPainter(
        text: TextSpan(text: l, style: style),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      // 14px padding each side + 1px border each side.
      total += tp.width + 30;
    }
    return total;
  }

  /// The custom-range control. Collapses to an icon-only button when there is
  /// no range chosen and space is tight, and widens to show the chosen dates
  /// once there is something to say.
  Widget _customChip(bool compact) {
    final hasRange = _custom != null && _range == _Range.custom;
    return _filterChip(
      hasRange
          ? _customLabel()
          : compact
          ? null
          : 'Custom',
      hasRange,
      _pickCustom,
      icon: Icons.date_range_rounded,
      tooltip: 'Pick a date range',
    );
  }

  /// One pill. [label] may be null for an icon-only control, which is how the
  /// custom-range button collapses on a narrow phone.
  Widget _filterChip(
    String? label,
    bool selected,
    VoidCallback onTap, {
    IconData? icon,
    String? tooltip,
  }) {
    final iconOnly = label == null;
    // Material + InkWell rather than a bare GestureDetector so the chips get a
    // hover and press response on the web, which a console this dense needs.
    Widget chip = Material(
      color: selected ? AppColors.primaryBlue : AdminUi.subtle,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        hoverColor: selected
            ? Colors.white.withValues(alpha: 0.08)
            : AppColors.primaryBlue.withValues(alpha: 0.06),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          // An icon-only pill gets equal padding so it comes out round rather
          // than a stubby oval, and keeps a 38px tap target either way.
          padding: EdgeInsets.symmetric(
            horizontal: iconOnly ? 10 : 14,
            vertical: 9,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? AppColors.primaryBlue : AdminUi.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: iconOnly ? 18 : 15,
                  color: selected ? Colors.white : AdminUi.textMuted,
                ),
                if (!iconOnly) const SizedBox(width: 6),
              ],
              if (label != null)
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : AdminUi.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    if (tooltip != null) chip = Tooltip(message: tooltip, child: chip);
    return chip;
  }

  // ── History list (grouped by day) ────────────────────────────────────────
  /// One card per day rather than one card per action.
  ///
  /// The old list gave every row its own bordered box, so twenty actions read
  /// as twenty competing objects with no sense of the days they belong to.
  /// Grouping the rows into a single card per day — with the date as a sticky
  /// header — turns the same data into a timeline you can skim.
  Widget _list(List<AdminActivity> items, double gutter) {
    // Preserve the newest-first order the query returns while collecting each
    // day's rows together.
    final days = <String, List<AdminActivity>>{};
    for (final a in items) {
      days.putIfAbsent(a.dayLabel, () => []).add(a);
    }

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        for (final entry in days.entries)
          // Each day is its own SliverMainAxisGroup so its pinned header is
          // scoped to that group: it sticks while its own rows scroll past,
          // then slides away as the next day arrives. A bare pinned header
          // per day would instead stack them all at the top of the sheet.
          SliverMainAxisGroup(
            slivers: [
              SliverStickyDayHeader(label: entry.key, gutter: gutter),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 14),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AdminUi.surface,
                      borderRadius: BorderRadius.circular(AdminUi.cardRadius),
                      border: Border.all(color: AdminUi.border),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (int i = 0; i < entry.value.length; i++) ...[
                          if (i > 0)
                            const Divider(
                              height: 1,
                              thickness: 1,
                              color: AdminUi.subtle,
                              indent: 56,
                            ),
                          _row(entry.value[i]),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 28)),
      ],
    );
  }

  Widget _row(AdminActivity a) {
    final color = _activityColor(a.action);
    final detail = a.detail ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Icon(_activityIcon(a.action), size: 16, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                    color: AdminUi.textPrimary,
                  ),
                ),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    detail,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: AdminUi.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                // Actor and time were one run-on muted line; the actor is now
                // a small chip so "who" and "when" separate at a glance.
                Row(
                  children: [
                    if ((a.actorName ?? '').isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AdminUi.subtle,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: AdminUi.border),
                        ),
                        child: Text(
                          a.actorName!,
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: AdminUi.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        a.timeOnly,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AdminUi.textMuted,
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
    );
  }

  /// Empty and error states: an icon, a headline and an optional hint, centred
  /// in the viewport rather than pinned 80px from the top of a blank sheet.
  Widget _message(
    String text, {
    IconData? icon,
    String? hint,
    Widget? action,
  }) {
    // Kept scrollable so pull-to-refresh works from the empty/error state.
    return LayoutBuilder(
      builder: (context, c) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 40, 32, 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: AdminUi.subtle,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: AdminUi.border),
                        ),
                        child: Icon(icon, size: 24, color: AdminUi.textMuted),
                      ),
                      const SizedBox(height: 14),
                    ],
                    Text(
                      text,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AdminUi.textSecondary,
                      ),
                    ),
                    if (hint != null) ...[
                      const SizedBox(height: 5),
                      Text(
                        hint,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          color: AdminUi.textMuted,
                        ),
                      ),
                    ],
                    if (action != null) ...[const SizedBox(height: 10), action],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The day label, pinned to the top of the viewport while its own rows scroll
/// past underneath — so you always know which day you are looking at.
///
/// [SliverPersistentHeader] is the only way to get this: a header inside the
/// list scrolls away with the content, which is exactly the thing that made
/// the flat list hard to read once it ran past a screenful.
class SliverStickyDayHeader extends StatelessWidget {
  final String label;
  final double gutter;
  const SliverStickyDayHeader({
    super.key,
    required this.label,
    required this.gutter,
  });

  @override
  Widget build(BuildContext context) => SliverPersistentHeader(
    pinned: true,
    delegate: _DayHeaderDelegate(label: label, gutter: gutter),
  );
}

class _DayHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String label;
  final double gutter;
  const _DayHeaderDelegate({required this.label, required this.gutter});

  static const double _height = 40;

  @override
  double get minExtent => _height;
  @override
  double get maxExtent => _height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    return Container(
      height: _height,
      // Opaque: rows scrolling underneath must not show through the label.
      color: AdminUi.pageBg,
      padding: EdgeInsets.fromLTRB(gutter, 12, gutter, 6),
      alignment: Alignment.centerLeft,
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: AdminUi.textMuted,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_DayHeaderDelegate old) =>
      old.label != label || old.gutter != gutter;
}

class _HistorySkeleton extends StatelessWidget {
  final double gutter;
  const _HistorySkeleton({required this.gutter});

  @override
  Widget build(BuildContext context) => AdminShimmer(
    child: ListView(
      padding: EdgeInsets.fromLTRB(gutter, 18, gutter, 12),
      children: [
        const SkeletonBox(width: 90, height: 11),
        const SizedBox(height: 12),
        // Mirrors the real layout: one grouped card holding several rows, so
        // nothing jumps when the data lands.
        _skeletonCard(3),
        const SizedBox(height: 20),
        const SkeletonBox(width: 90, height: 11),
        const SizedBox(height: 12),
        _skeletonCard(2),
      ],
    ),
  );

  Widget _skeletonCard(int rows) => Container(
    decoration: BoxDecoration(
      color: AdminUi.surface,
      borderRadius: BorderRadius.circular(AdminUi.cardRadius),
      border: Border.all(color: AdminUi.border),
    ),
    child: Column(
      children: [
        for (int i = 0; i < rows; i++) ...[
          if (i > 0)
            const Divider(
              height: 1,
              thickness: 1,
              color: AdminUi.subtle,
              indent: 56,
            ),
          const _SkeletonRow(),
        ],
      ],
    ),
  );
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.fromLTRB(14, 12, 14, 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SkeletonBox(width: 30, height: 30, radius: 999),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 180, height: 12),
              SizedBox(height: 8),
              SkeletonBox(width: 100, height: 10),
            ],
          ),
        ),
      ],
    ),
  );
}
