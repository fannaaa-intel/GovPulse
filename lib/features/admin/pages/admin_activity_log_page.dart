import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/admin_activity_provider.dart';
import '../theme/admin_ui.dart';
import '../widgets/admin_dialog_back.dart';
import '../widgets/admin_skeleton.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Admin → Settings → Activity log → "View all"
//
//  Full, scrollable history of every logged admin action (Settings only shows
//  the newest 15 inline). Adds a date-range filter — quick presets plus a
//  custom range — and shows the exact timestamp on each row, grouped by day.
// ════════════════════════════════════════════════════════════════════════════

/// Opens the full activity-log history as a pushed page (full-screen on phones,
/// a centred column on web/desktop). Uses the app-wide sub-screen motion:
/// instant on entry (the content does its own slide-up + fade-in), fade-out on
/// the way back — matching the citizen settings sub-screens.
void showAdminActivityLog(BuildContext context) {
  Navigator.of(context).push(
    PageRouteBuilder(
      transitionDuration: Duration.zero,
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, _, _) => const _ActivityLogScreen(),
      transitionsBuilder: (_, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
    ),
  );
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
  const _ActivityLogScreen();

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
    _entryCtrl.forward();
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
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(
            primary: AppColors.primaryBlue,
          ),
        ),
        child: child!,
      ),
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
    return Scaffold(
      backgroundColor: AdminUi.pageBg,
      body: SafeArea(
        child: FadeTransition(
          opacity: _entryFade,
          child: SlideTransition(
            position: _entrySlide,
            child: Column(
          children: [
            _header(),
            _filterBar(),
            const Divider(height: 1, color: AdminUi.border),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: FutureBuilder<List<AdminActivity>>(
                      future: _future,
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const _HistorySkeleton();
                        }
                        if (snap.hasError) {
                          return _message(
                            'Could not load the activity log.',
                            action: TextButton(
                              onPressed: _refresh,
                              child: const Text('Retry'),
                            ),
                          );
                        }
                        final items = snap.data ?? const <AdminActivity>[];
                        if (items.isEmpty) {
                          return _message(
                            _range == _Range.all
                                ? 'No admin actions recorded yet.'
                                : 'No actions in this date range.',
                          );
                        }
                        return _list(items);
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────
  Widget _header() {
    return Container(
      color: AdminUi.surface,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          AdminDialogBack(onTap: () => Navigator.pop(context)),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Activity log',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryBlue,
                letterSpacing: -0.3,
              ),
            ),
          ),
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded, size: 20),
            color: AdminUi.textMuted,
            tooltip: 'Refresh',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  // ── Filter bar ───────────────────────────────────────────────────────────
  Widget _filterBar() {
    final customLabel = _custom == null
        ? 'Custom range'
        : '${_custom!.start.month}/${_custom!.start.day} – '
              '${_custom!.end.month}/${_custom!.end.day}';
    return Container(
      color: AdminUi.surface,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _filterChip('All', _range == _Range.all, () => _select(_Range.all)),
            const SizedBox(width: 8),
            _filterChip(
              'Today',
              _range == _Range.today,
              () => _select(_Range.today),
            ),
            const SizedBox(width: 8),
            _filterChip(
              'Last 7 days',
              _range == _Range.days7,
              () => _select(_Range.days7),
            ),
            const SizedBox(width: 8),
            _filterChip(
              'Last 30 days',
              _range == _Range.days30,
              () => _select(_Range.days30),
            ),
            const SizedBox(width: 8),
            _filterChip(
              customLabel,
              _range == _Range.custom,
              _pickCustom,
              icon: Icons.date_range_rounded,
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(
    String label,
    bool selected,
    VoidCallback onTap, {
    IconData? icon,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryBlue : AdminUi.subtle,
          borderRadius: BorderRadius.circular(AdminUi.controlRadius),
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
                size: 15,
                color: selected ? Colors.white : AdminUi.textMuted,
              ),
              const SizedBox(width: 6),
            ],
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
    );
  }

  // ── History list (grouped by day) ────────────────────────────────────────
  Widget _list(List<AdminActivity> items) {
    // Flatten into [day header, rows…] preserving the newest-first order.
    final children = <Widget>[];
    String? lastDay;
    for (final a in items) {
      if (a.dayLabel != lastDay) {
        lastDay = a.dayLabel;
        children.add(_dayHeader(a.dayLabel));
      }
      children.add(_row(a));
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 40),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 10),
          child: Text(
            '${items.length} action${items.length == 1 ? '' : 's'}',
            style: const TextStyle(fontSize: 12.5, color: AdminUi.textMuted),
          ),
        ),
        ...children,
      ],
    );
  }

  Widget _dayHeader(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
        color: AdminUi.textSecondary,
      ),
    ),
  );

  Widget _row(AdminActivity a) {
    final color = _activityColor(a.action);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AdminUi.surface,
        borderRadius: BorderRadius.circular(AdminUi.controlRadius),
        border: Border.all(color: AdminUi.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(_activityIcon(a.action), size: 17, color: color),
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
                    color: AdminUi.textPrimary,
                  ),
                ),
                if ((a.detail ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    a.detail!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AdminUi.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  [
                    if ((a.actorName ?? '').isNotEmpty) a.actorName!,
                    a.exactTime,
                  ].join('  ·  '),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AdminUi.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _message(String text, {Widget? action}) {
    // Kept scrollable so pull-to-refresh works from the empty/error state.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
          child: Column(
            children: [
              Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: AdminUi.textMuted,
                ),
              ),
              if (action != null) ...[const SizedBox(height: 8), action],
            ],
          ),
        ),
      ],
    );
  }
}

class _HistorySkeleton extends StatelessWidget {
  const _HistorySkeleton();
  @override
  Widget build(BuildContext context) => AdminShimmer(
    child: ListView(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      children: const [
        SkeletonBox(width: 120, height: 12),
        SizedBox(height: 14),
        _SkeletonRow(),
        _SkeletonRow(),
        _SkeletonRow(),
        _SkeletonRow(),
        _SkeletonRow(),
      ],
    ),
  );
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AdminUi.surface,
      borderRadius: BorderRadius.circular(AdminUi.controlRadius),
      border: Border.all(color: AdminUi.border),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SkeletonBox(width: 32, height: 32, radius: 9),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 180, height: 12),
              SizedBox(height: 7),
              SkeletonBox(width: 100, height: 10),
            ],
          ),
        ),
      ],
    ),
  );
}
