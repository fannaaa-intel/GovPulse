import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_dialog.dart';
import '../providers/admin_dashboard_provider.dart';
import '../theme/admin_ui.dart';
import '../widgets/activity_visuals.dart';
import '../widgets/admin_dialog_back.dart';
import '../widgets/admin_skeleton.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Admin → Dashboard → Recent activity → "View all"
//
//  The dashboard card shows the newest handful of events; this is the full
//  feed. It is a MIXED stream — citizen reports and ID-verification
//  submissions — which is exactly why "View all" must not jump straight to the
//  Reports console: on a quiet week most of the rows on screen are
//  verifications, and the admin lands on a list that does not contain what they
//  were just looking at. The whole feed opens here instead, and each row
//  deep-links to the console that actually owns it.
// ════════════════════════════════════════════════════════════════════════════

/// Nav tab indices owned by the shell (AdminDashboardScreen.navItems), repeated
/// here so the feed can resolve a row to its destination without importing the
/// shell (which imports this file — the cycle would be circular).
const int kActivityTabReports = 3;
const int kActivityTabSuggestions = 4;
const int kActivityTabFeedback = 5;
const int kActivityTabVerification = 6;

/// The nav tab that owns [source]. One mapping, shared by the dashboard card
/// and this sheet, so a row cannot land somewhere different depending on which
/// of the two an admin happened to tap it from.
int activityTabFor(ActivitySource source) => switch (source) {
  ActivitySource.reports => kActivityTabReports,
  ActivitySource.suggestions => kActivityTabSuggestions,
  ActivitySource.feedback => kActivityTabFeedback,
  ActivitySource.verifications => kActivityTabVerification,
};

/// Width at or above which the feed opens as a centred pop-up modal rather than
/// a pushed screen. Below it — a phone-width browser window, and the mobile app
/// at any size — a modal would be a near-full-bleed panel with a useless sliver
/// of scrim, so the feed takes over the screen instead.
///
/// Deliberately the same number the Settings activity log uses: two sheets that
/// switched idiom at different window widths would read as a bug.
const double kRecentActivityModalMinWidth = 760;

/// What a row tap asked for: the nav tab that owns the submission, and the id
/// to scroll to and flash once that tab is open.
typedef ActivityOpenRequest = ({int tabIndex, String highlightId});

/// Opens the full recent-activity feed.
///
/// Medium and large screens (web/desktop) get a centred pop-up modal over a
/// frosted console, matching every other admin pop-up. Small screens and the
/// mobile app get a pushed full screen, using the app-wide sub-screen motion:
/// instant on entry (the content does its own slide-up + fade-in), fade-out on
/// the way back.
///
/// [onOpen] fires after the sheet closes, carrying the tab + highlight target
/// the tapped row resolved to. Closing first matters: the destination flashes
/// the row it lands on, and a flash behind a modal is a flash nobody sees.
void showAdminRecentActivity(
  BuildContext context, {
  required void Function(ActivityOpenRequest request) onOpen,
}) {
  // Decided once, at the tap: an already-open sheet keeps its own layout, and a
  // resize past the breakpoint is not worth tearing the route down for. The
  // mobile app always pushes — a tablet clears the width breakpoint, but a
  // dialog is the wrong idiom for a touch shell.
  final asModal =
      kIsWeb &&
      MediaQuery.of(context).size.width >= kRecentActivityModalMinWidth;

  if (!asModal) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, _, _) => _RecentActivityScreen(onOpen: onOpen),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
    return;
  }

  showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Recent activity',
    barrierColor: Colors.black.withValues(alpha: 0.12),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, _, _) => _RecentActivityModal(onOpen: onOpen),
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
/// no scrollbar — matching the Settings activity log, scoped here so it cannot
/// restyle the rest of the console.
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

/// The modal shell: a rounded, height-capped card holding the same feed the
/// pushed screen shows.
class _RecentActivityModal extends StatelessWidget {
  final void Function(ActivityOpenRequest request) onOpen;
  const _RecentActivityModal({required this.onOpen});

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
            child: _RecentActivityScreen(onOpen: onOpen, inModal: true),
          ),
        ),
      ),
    );
  }
}

/// Which slice of the feed is shown. The feed merges four sources, so the
/// filter is by source rather than by date — "just the verifications" is the
/// question this sheet actually gets asked, and it is also the fastest way to
/// explain why the feed is not simply the Reports list.
///
/// [_Filter.all] aside, these mirror [ActivitySource] one-for-one; the chip bar
/// is generated from that enum so a fifth source cannot be added to the feed
/// and forgotten here.
enum _Filter { all, reports, suggestions, feedback, verifications }

/// The source a chip selects, or null for "All".
ActivitySource? _sourceOf(_Filter f) => switch (f) {
  _Filter.all => null,
  _Filter.reports => ActivitySource.reports,
  _Filter.suggestions => ActivitySource.suggestions,
  _Filter.feedback => ActivitySource.feedback,
  _Filter.verifications => ActivitySource.verifications,
};

String _chipLabel(_Filter f) => switch (f) {
  _Filter.all => 'All',
  _Filter.reports => 'Reports',
  _Filter.suggestions => 'Suggestions',
  _Filter.feedback => 'Feedback',
  _Filter.verifications => 'Verifications',
};

/// Singular form, for prose. The chips are plural because they count rows
/// ("Reports · 4"), but a sentence needs "No report activity", not "No reports
/// activity" — so the two are separate rather than one derived from the other.
String _sourceNoun(_Filter f) => switch (f) {
  _Filter.all => 'activity',
  _Filter.reports => 'report',
  _Filter.suggestions => 'suggestion',
  _Filter.feedback => 'feedback',
  _Filter.verifications => 'verification',
};

class _RecentActivityScreen extends ConsumerStatefulWidget {
  final void Function(ActivityOpenRequest request) onOpen;

  /// True when hosted inside [_RecentActivityModal] — the card already provides
  /// the surface, rounding and inset, so the content drops the Scaffold's page
  /// background and SafeArea and skips the entry slide (the modal's own
  /// transition covers it).
  final bool inModal;

  const _RecentActivityScreen({required this.onOpen, this.inModal = false});

  @override
  ConsumerState<_RecentActivityScreen> createState() =>
      _RecentActivityScreenState();
}

class _RecentActivityScreenState extends ConsumerState<_RecentActivityScreen>
    with SingleTickerProviderStateMixin {
  _Filter _filter = _Filter.all;

  // Content slide-up + fade-in on entry (the route itself opens instantly).
  late final AnimationController _entryCtrl;
  late final Animation<double> _entryFade;
  late final Animation<Offset> _entrySlide;

  @override
  void initState() {
    super.initState();
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

  List<ActivityItem> _visible(List<ActivityItem> all) {
    final want = _sourceOf(_filter);
    if (want == null) return all;
    return [
      for (final a in all)
        if (a.source == want) a,
    ];
  }

  /// Closes the sheet, then hands the target to the shell.
  void _open(ActivityItem item) {
    if (item.id.isEmpty) return; // nothing to deep-link to
    final request = (
      tabIndex: activityTabFor(item.source),
      highlightId: item.id,
    );
    Navigator.of(context).pop();
    widget.onOpen(request);
  }

  @override
  Widget build(BuildContext context) {
    final gutter = MediaQuery.of(context).size.width < 480 ? 16.0 : 20.0;
    final async = ref.watch(adminDashboardProvider);
    final all = async.valueOrNull?.recentActivity ?? const <ActivityItem>[];
    final items = _visible(all);

    Widget list;
    if (async.isLoading && async.valueOrNull == null) {
      list = AdminShimmer(
        child: ListView(
          padding: EdgeInsets.fromLTRB(gutter, 4, gutter, gutter),
          children: List.generate(6, (_) => const _FeedSkeletonRow()),
        ),
      );
    } else if (items.isEmpty) {
      list = _Empty(
        label: _filter == _Filter.all
            ? 'No recent activity yet.'
            : 'No ${_sourceNoun(_filter)} activity in this feed.',
      );
    } else {
      list = ListView.builder(
        padding: EdgeInsets.fromLTRB(gutter, 4, gutter, gutter),
        itemCount: items.length,
        itemBuilder: (context, i) => _FeedRow(
          item: items[i],
          onTap: items[i].id.isEmpty ? null : () => _open(items[i]),
        ),
      );
    }

    final unbarred = Column(
      children: [
        _header(gutter, all),
        _filterBar(gutter, all),
        const Divider(height: 1, thickness: 1, color: AdminUi.border),
        Expanded(
          child: ScrollConfiguration(
            behavior: const _NoScrollbarBehavior(),
            child: RefreshIndicator(
              onRefresh: () =>
                  ref.read(adminDashboardProvider.notifier).refresh(),
              child: list,
            ),
          ),
        ),
      ],
    );

    if (widget.inModal) return unbarred;

    return Scaffold(
      backgroundColor: AdminUi.pageBg,
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
  Widget _header(double gutter, List<ActivityItem> all) {
    final n = _visible(all).length;
    final label = switch (n) {
      0 => 'No events',
      1 => '1 event',
      _ => '$n events',
    };

    return Container(
      color: AdminUi.surface,
      // The modal keeps a tighter right inset for its close button; the pushed
      // screen has no trailing control, so it uses the full gutter.
      padding: EdgeInsets.fromLTRB(
        gutter,
        14,
        widget.inModal ? gutter - 6 : gutter,
        12,
      ),
      child: Row(
        children: [
          // Pushed screen → chevron back at the left, like the citizen settings
          // sub-screens and the Settings activity log. Modal → a top-right X,
          // the convention the other admin dialogs already use.
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
                  'Recent activity',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: AdminUi.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$label · ${_filterLabel()}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AdminUi.textMuted,
                  ),
                ),
              ],
            ),
          ),
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

  String _filterLabel() =>
      _filter == _Filter.all ? 'All activity' : '${_chipLabel(_filter)} only';

  /// Source filter. Counts sit on the chips so the split between the two
  /// sources is visible without switching.
  Widget _filterBar(double gutter, List<ActivityItem> all) {
    final counts = <ActivitySource, int>{};
    for (final a in all) {
      counts[a.source] = (counts[a.source] ?? 0) + 1;
    }

    int countFor(_Filter f) {
      final src = _sourceOf(f);
      return src == null ? all.length : (counts[src] ?? 0);
    }

    // Scrolls horizontally rather than laying the three chips out flush. With
    // counts appended, "Verifications · 12" is a long label, and three of them
    // side by side are wider than a 390px phone — a plain Row overflowed by
    // 165px there. Scrolling keeps every chip reachable and full-width-legible
    // instead of ellipsised, and does nothing at all on a desktop window where
    // they already fit.
    return Container(
      color: AdminUi.surface,
      padding: const EdgeInsets.only(bottom: 12),
      // ScrollConfiguration, not just physics: on the web a horizontal strip has
      // no wheel axis of its own, so click-and-drag is the ONLY way to pan it —
      // and Flutter excludes the mouse from dragDevices by default, which left
      // the trailing chips unreachable on a narrow browser window.
      child: ScrollConfiguration(
        behavior: const _NoScrollbarBehavior(),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: gutter),
          physics: const ClampingScrollPhysics(),
          child: Row(
            children: [
              for (final f in _Filter.values) ...[
                if (f != _Filter.values.first) const SizedBox(width: 8),
                _chip(_chipLabel(f), countFor(f), f),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, int count, _Filter value) {
    final selected = _filter == value;
    return Material(
      color: selected ? AppColors.primaryBlue : AdminUi.subtle,
      borderRadius: BorderRadius.circular(AdminUi.controlRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AdminUi.controlRadius),
        onTap: () => setState(() => _filter = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AdminUi.controlRadius),
            border: Border.all(
              color: selected ? AppColors.primaryBlue : AdminUi.border,
            ),
          ),
          child: Text(
            count == 0 ? label : '$label · $count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : AdminUi.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// One row of the full feed. Richer than the dashboard card's row — it carries
/// an exact timestamp and a trailing chevron, because here the row is a
/// navigation target rather than a glance.
class _FeedRow extends StatelessWidget {
  final ActivityItem item;
  final VoidCallback? onTap;
  const _FeedRow({required this.item, this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = activityKindColor(item.kind);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: AdminUi.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AdminUi.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    activityKindIcon(item.kind),
                    size: 17,
                    color: color,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AdminUi.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AdminUi.textMuted,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _exactTime(item.timestamp),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                // Consistent with every other "this opens something" row in the
                // console: the chevron is the affordance, not a bare tap target.
                if (onTap != null)
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: AdminUi.textMuted,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _exactTime(DateTime? t) {
    if (t == null) return '';
    return DateFormat('MMM d, yyyy · h:mm a').format(t);
  }
}

class _Empty extends StatelessWidget {
  final String label;
  const _Empty({required this.label});

  @override
  Widget build(BuildContext context) {
    // A scrollable, so pull-to-refresh still works on an empty feed.
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
      children: [
        const Icon(Icons.history_rounded, size: 34, color: AdminUi.textMuted),
        const SizedBox(height: 10),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: AdminUi.textMuted),
        ),
      ],
    );
  }
}

class _FeedSkeletonRow extends StatelessWidget {
  const _FeedSkeletonRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AdminUi.border),
        ),
        child: const Row(
          children: [
            SkeletonCircle(size: 38),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 150, height: 11),
                  SizedBox(height: 7),
                  SkeletonBox(width: 210, height: 10),
                  SizedBox(height: 7),
                  SkeletonBox(width: 110, height: 9),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
