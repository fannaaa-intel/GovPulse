import 'dart:async';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/aparri_barangays.dart';
import '../../../core/services/events_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/event_status_pill.dart';
import '../../../core/widgets/modal/media_picker_sheet.dart';
import '../providers/admin_events_provider.dart';
import '../theme/admin_ui.dart';
import '../widgets/admin_detail_screen.dart';
import '../widgets/admin_skeleton.dart';
import '../widgets/admin_submission_ui.dart';
import '../widgets/admin_snackbar.dart';
import '../../../core/widgets/app_dialog.dart';

// ── Category presets ──────────────────────────────────────────────────────────
// The citizen app filters by these categories; each carries a signature colour
// stored on the row as a hex string (category_color).
const Map<String, int> kEventCategoryColors = {
  'Health': 0xFF22C55E,
  'Training': 0xFF2563EB,
  'Environment': 0xFF14B8A6,
  'Special': 0xFFF59E0B,
  'Others': 0xFF64748B,
};

Color _hexToColor(String hex) {
  final cleaned = hex.replaceFirst('#', '').trim();
  final full = cleaned.length == 6 ? 'FF$cleaned' : cleaned;
  final value = int.tryParse(full, radix: 16);
  return value == null ? AppColors.primaryBlue : Color(value);
}

String _colorToHex(int argb) =>
    '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

String _statusLabel(EventStatus s) => switch (s) {
  EventStatus.pending => 'Pending',
  EventStatus.approved => 'Published',
  EventStatus.rejected => 'Rejected',
};

Color _statusColor(EventStatus s) => switch (s) {
  EventStatus.pending => AppColors.orange,
  EventStatus.approved => AppColors.green,
  EventStatus.rejected => AppColors.red,
};

IconData _statusIcon(EventStatus s) => switch (s) {
  EventStatus.pending => Icons.hourglass_top_rounded,
  EventStatus.approved => Icons.check_circle_rounded,
  EventStatus.rejected => Icons.cancel_rounded,
};

String _shortDate(DateTime? t) {
  if (t == null) return '—';
  return DateFormat('MMM d, yyyy').format(t);
}

// ══ Page ══════════════════════════════════════════════════════════════════════

class AdminEventsPage extends ConsumerStatefulWidget {
  const AdminEventsPage({super.key});

  @override
  ConsumerState<AdminEventsPage> createState() => _AdminEventsPageState();
}

class _AdminEventsPageState extends ConsumerState<AdminEventsPage> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  String _query = '';
  String _categoryFilter = 'All';
  EventStatus? _statusFilter; // null == all

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _query = value.trim().toLowerCase());
    });
  }

  List<EventModel> _visible(List<EventModel> all) {
    return all.where((e) {
      if (_statusFilter != null && e.status != _statusFilter) return false;
      if (_categoryFilter != 'All' && e.category != _categoryFilter) {
        return false;
      }
      if (_query.isNotEmpty) {
        final hay = '${e.title} ${e.location} ${e.category}'.toLowerCase();
        if (!hay.contains(_query)) return false;
      }
      return true;
    }).toList();
  }

  Future<void> _openDetail(EventModel e) => showAdminDetail(
    context,
    builder: (_) => _EventDetailDialog(event: e),
  );

  void _openForm({EventModel? existing}) =>
      showEventForm(context, existing: existing);

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(adminEventsProvider);
    final pad = MediaQuery.of(context).size.width < 600 ? 16.0 : 24.0;

    final all = async.valueOrNull ?? const <EventModel>[];
    final loading = async.isLoading && async.valueOrNull == null;
    final visible = _visible(all);

    return RefreshIndicator(
      onRefresh: () => ref.read(adminEventsProvider.notifier).refresh(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(pad, pad, pad, pad + 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: 20),
                _buildStatRow(all, loading),
                const SizedBox(height: 16),
                _buildToolbar(),
                const SizedBox(height: 16),
                _buildResults(async, visible),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return LayoutBuilder(
      builder: (context, c) {
        // The top bar already shows "Events", so no in-content page title.
        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Publish community events and review staff submissions',
              style: TextStyle(fontSize: 13, color: AdminUi.textMuted),
            ),
          ],
        );

        // Pull-to-refresh replaces the old Refresh button; just the primary
        // "New event" action remains.
        final actions = _PrimaryButton(
          icon: Icons.add_rounded,
          label: 'New event',
          onTap: () => _openForm(),
        );

        if (c.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [title, const SizedBox(height: 14), actions],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: title),
            actions,
          ],
        );
      },
    );
  }

  // ── Stat cards (double as the status filter) ────────────────────────────────
  Widget _buildStatRow(List<EventModel> all, bool loading) {
    int countOf(EventStatus s) => all.where((e) => e.status == s).length;

    final cards = <Widget>[
      _StatCard(
        label: 'All events',
        icon: Icons.event_rounded,
        accent: AppColors.primaryBlue,
        value: loading ? null : all.length,
        selected: _statusFilter == null,
        onTap: () => setState(() => _statusFilter = null),
      ),
      _StatCard(
        label: 'Pending',
        icon: Icons.hourglass_top_rounded,
        accent: AppColors.orange,
        value: loading ? null : countOf(EventStatus.pending),
        selected: _statusFilter == EventStatus.pending,
        onTap: () => setState(() => _statusFilter = EventStatus.pending),
      ),
      _StatCard(
        label: 'Published',
        icon: Icons.check_circle_rounded,
        accent: AppColors.green,
        value: loading ? null : countOf(EventStatus.approved),
        selected: _statusFilter == EventStatus.approved,
        onTap: () => setState(() => _statusFilter = EventStatus.approved),
      ),
      _StatCard(
        label: 'Rejected',
        icon: Icons.cancel_rounded,
        accent: AppColors.red,
        value: loading ? null : countOf(EventStatus.rejected),
        selected: _statusFilter == EventStatus.rejected,
        onTap: () => setState(() => _statusFilter = EventStatus.rejected),
      ),
    ];

    // Four across on laptop/desktop; 2×2 everywhere smaller.
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth > 820 ? 4 : 2;
        return _grid(cards, cols);
      },
    );
  }

  Widget _grid(List<Widget> cards, int cols) {
    const gap = 12.0;
    final rows = <Widget>[];
    for (var i = 0; i < cards.length; i += cols) {
      final end = (i + cols) > cards.length ? cards.length : i + cols;
      final slice = cards.sublist(i, end);
      final children = <Widget>[];
      for (var j = 0; j < cols; j++) {
        children.add(
          Expanded(child: j < slice.length ? slice[j] : const SizedBox()),
        );
        if (j < cols - 1) children.add(const SizedBox(width: gap));
      }
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      );
      if (end < cards.length) rows.add(const SizedBox(height: gap));
    }
    return Column(children: rows);
  }

  // ── Toolbar: search + category ──────────────────────────────────────────────
  Widget _buildToolbar() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 300,
          child: TextField(
            controller: _searchCtrl,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search title, location, category…',
              hintStyle: const TextStyle(
                fontSize: 13,
                color: AdminUi.textMuted,
              ),
              prefixIcon: const Icon(
                Icons.search_rounded,
                size: 18,
                color: AdminUi.textMuted,
              ),
              suffixIcon: _searchCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                    ),
              contentPadding: const EdgeInsets.symmetric(vertical: 11),
              filled: true,
              fillColor: AdminUi.surface,
              border: _fieldBorder(AdminUi.border),
              enabledBorder: _fieldBorder(AdminUi.border),
              focusedBorder: _fieldBorder(AppColors.primaryBlue),
            ),
          ),
        ),
        _FilterBox(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _categoryFilter,
              isDense: true,
              icon: const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: AdminUi.textMuted,
              ),
              borderRadius: BorderRadius.circular(AdminUi.controlRadius),
              items: [
                const DropdownMenuItem(
                  value: 'All',
                  child: Text('All categories', style: _ddStyle),
                ),
                for (final c in kEventCategoryColors.keys)
                  DropdownMenuItem(
                    value: c,
                    child: Text(c, style: _ddStyle),
                  ),
              ],
              onChanged: (v) => setState(() => _categoryFilter = v ?? 'All'),
            ),
          ),
        ),
      ],
    );
  }

  static OutlineInputBorder _fieldBorder(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(AdminUi.controlRadius),
    borderSide: BorderSide(color: color),
  );

  // ── Results ─────────────────────────────────────────────────────────────────
  Widget _buildResults(
    AsyncValue<List<EventModel>> async,
    List<EventModel> visible,
  ) {
    return _Card(
      padding: EdgeInsets.zero,
      child: async.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(16),
          child: AdminShimmer(
            child: Column(
              children: [
                _RowSkeleton(),
                _RowSkeleton(),
                _RowSkeleton(),
                _RowSkeleton(),
              ],
            ),
          ),
        ),
        error: (e, _) => _ResultsMessage(
          icon: Icons.cloud_off_rounded,
          color: AppColors.red,
          text: "Couldn't load events.",
          action: TextButton(
            onPressed: () => ref.read(adminEventsProvider.notifier).refresh(),
            child: const Text('Retry'),
          ),
        ),
        data: (_) {
          if (visible.isEmpty) {
            return _ResultsMessage(
              icon: Icons.event_busy_rounded,
              color: AdminUi.textMuted,
              text:
                  _statusFilter == null &&
                      _query.isEmpty &&
                      _categoryFilter == 'All'
                  ? 'No events yet. Tap "New event" to publish one.'
                  : 'No events match your filters.',
            );
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 760;
              if (wide) {
                return Column(
                  children: [
                    const _TableHeader(),
                    for (final e in visible)
                      _TableRow(event: e, onTap: () => _openDetail(e)),
                  ],
                );
              }
              return Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    for (final e in visible)
                      _EventCard(event: e, onTap: () => _openDetail(e)),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ══ Status pill ═══════════════════════════════════════════════════════════════

class _StatusPill extends StatelessWidget {
  final EventStatus status;
  const _StatusPill(this.status);

  @override
  Widget build(BuildContext context) {
    final c = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_statusIcon(status), size: 12, color: c),
          const SizedBox(width: 5),
          Text(
            _statusLabel(status),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: c,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String category;
  final String colorHex;
  const _CategoryChip({required this.category, required this.colorHex});

  @override
  Widget build(BuildContext context) {
    final c = _hexToColor(colorHex);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        category,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c),
      ),
    );
  }
}

/// Small rounded event thumbnail (network image or a coloured placeholder).
class _Thumb extends StatelessWidget {
  final String? url;
  final double size;
  const _Thumb({required this.url, this.size = 44});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: size,
        height: size,
        child: url == null || url!.isEmpty
            ? Container(
                color: AdminUi.subtle,
                child: const Icon(
                  Icons.event_rounded,
                  size: 18,
                  color: AdminUi.textMuted,
                ),
              )
            : CachedNetworkImage(
                imageUrl: url!,
                fit: BoxFit.cover,
                placeholder: (_, _) => Container(color: AdminUi.subtle),
                errorWidget: (_, _, _) => Container(
                  color: AdminUi.subtle,
                  child: const Icon(
                    Icons.broken_image_rounded,
                    size: 18,
                    color: AdminUi.textMuted,
                  ),
                ),
              ),
      ),
    );
  }
}

// ══ Stat card ═════════════════════════════════════════════════════════════════

class _StatCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color accent;
  final int? value;
  final bool selected;
  final VoidCallback onTap;

  const _StatCard({
    required this.label,
    required this.icon,
    required this.accent,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(AdminUi.cardRadius));
    return DecoratedBox(
      decoration: const BoxDecoration(
        borderRadius: radius,
        boxShadow: AdminUi.cardShadow,
      ),
      child: Material(
        color: selected ? accent.withValues(alpha: 0.06) : AdminUi.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: selected ? accent : AdminUi.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(icon, size: 16, color: accent),
                    ),
                    const Spacer(),
                    if (selected)
                      Icon(Icons.check_circle_rounded, size: 16, color: accent),
                  ],
                ),
                const SizedBox(height: 14),
                if (value == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 5),
                    child: AdminShimmer(
                      child: SkeletonBox(width: 40, height: 24, radius: 7),
                    ),
                  )
                else
                  Text(
                    '$value',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      color: AdminUi.textPrimary,
                    ),
                  ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AdminUi.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ══ Wide table ════════════════════════════════════════════════════════════════

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
      decoration: const BoxDecoration(
        color: AdminUi.subtle,
        border: Border(bottom: BorderSide(color: AdminUi.border)),
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AdminUi.cardRadius),
        ),
      ),
      child: Row(
        children: const [
          _HCell('EVENT', flex: 4),
          _HCell('CATEGORY', flex: 2),
          _HCell('DATE', flex: 2),
          _HCell('STATUS', flex: 2),
          SizedBox(width: 40),
        ],
      ),
    );
  }
}

class _HCell extends StatelessWidget {
  final String text;
  final int flex;
  const _HCell(this.text, {this.flex = 1});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: AdminUi.textMuted,
        ),
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  final EventModel event;
  final VoidCallback onTap;
  const _TableRow({required this.event, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AdminUi.border)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: Row(
                  children: [
                    _Thumb(url: event.imageUrl),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (event.isFeatured) ...[
                                const Icon(
                                  Icons.star_rounded,
                                  size: 14,
                                  color: AppColors.orange,
                                ),
                                const SizedBox(width: 4),
                              ],
                              Expanded(
                                child: Text(
                                  event.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AdminUi.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            event.location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
              ),
              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _CategoryChip(
                    category: event.category,
                    colorHex: event.categoryColor,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _shortDate(event.eventDate),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AdminUi.textSecondary,
                      ),
                    ),
                    Text(
                      event.eventTime,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AdminUi.textMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    EventStatusPill(
                      eventDate: event.eventDate,
                      eventTime: event.eventTime,
                      fontSize: 10,
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _StatusPill(event.status),
                ),
              ),
              const SizedBox(
                width: 40,
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: AdminUi.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══ Narrow card ═══════════════════════════════════════════════════════════════

class _EventCard extends StatelessWidget {
  final EventModel event;
  final VoidCallback onTap;
  const _EventCard({required this.event, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AdminUi.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AdminUi.controlRadius),
          side: const BorderSide(color: AdminUi.border),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Thumb(url: event.imageUrl, size: 56),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (event.isFeatured) ...[
                            const Icon(
                              Icons.star_rounded,
                              size: 14,
                              color: AppColors.orange,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              event.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AdminUi.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _CategoryChip(
                            category: event.category,
                            colorHex: event.categoryColor,
                          ),
                          _StatusPill(event.status),
                          EventStatusPill(
                            eventDate: event.eventDate,
                            eventTime: event.eventTime,
                            fontSize: 10,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${_shortDate(event.eventDate)}  ·  ${event.eventTime}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AdminUi.textMuted,
                        ),
                      ),
                      Text(
                        event.location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AdminUi.textMuted,
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
}

// ══ Detail dialog ═════════════════════════════════════════════════════════════

class _EventDetailDialog extends ConsumerStatefulWidget {
  final EventModel event;
  const _EventDetailDialog({required this.event});

  @override
  ConsumerState<_EventDetailDialog> createState() => _EventDetailDialogState();
}

class _EventDetailDialogState extends ConsumerState<_EventDetailDialog> {
  bool _busy = false;

  /// Featured is the one control here that isn't a decision about the event —
  /// it's a preference you flip and keep looking. So it's held locally and
  /// driven optimistically: the switch answers instantly, the dialog stays put,
  /// and a failed write rolls the switch back.
  late bool _featured = widget.event.isFeatured;
  bool _featuring = false;

  /// Which PANE is showing when the layout is too narrow to seat both side by
  /// side: 0 = Event Status, 1 = Event Details. Status leads — the cover and
  /// the publish decision are why you opened this.
  int _paneTab = 0;

  EventModel get e => widget.event;

  /// Unlike [_run], this leaves the dialog open — flipping Featured isn't a way
  /// out of the event.
  Future<void> _toggleFeatured(bool v) async {
    setState(() {
      _featured = v;
      _featuring = true;
    });
    try {
      await ref.read(adminEventsProvider.notifier).setFeatured(e.id, v);
      if (!mounted) return;
      setState(() => _featuring = false);
      showAdminSnackBar(
        context,
        v ? 'Marked as featured.' : 'Unfeatured.',
        type: AdminSnackType.success,
      );
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _featured = !v;
        _featuring = false;
      });
      showAdminSnackBar(context, 'Failed: $err', type: AdminSnackType.error);
    }
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      Navigator.pop(context);
      showAdminSnackBar(context, done, type: AdminSnackType.success);
    } catch (err) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAdminSnackBar(context, 'Failed: $err', type: AdminSnackType.error);
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete event?'),
        content: Text('"${e.title}" will be permanently removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(
      () => ref.read(adminEventsProvider.notifier).delete(e.id),
      'Event deleted.',
    );
  }

  /// Opens the event photo full-screen and uncropped (BoxFit.contain) on a dark
  /// backdrop, with pinch / scroll-wheel zoom. Fills the screen responsively on
  /// phone, tablet and web, so the whole image is always visible.
  void _showFullImage(String url) {
    showGeneralDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      barrierDismissible: true,
      barrierLabel: 'Event image',
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (ctx, _, _) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.contain,
                    placeholder: (_, _) => const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                    errorWidget: (_, _, _) => const Icon(
                      Icons.broken_image_rounded,
                      color: Colors.white54,
                      size: 48,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(ctx).padding.top + 8,
            right: 12,
            child: Material(
              color: Colors.black.withValues(alpha: 0.5),
              shape: const CircleBorder(),
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The cover photo, sized to fill whatever box it's given. Tapping opens the
  /// full, uncropped image.
  Widget _cover({required double height, BorderRadius? radius}) {
    final url = e.imageUrl;
    final has = url != null && url.isNotEmpty;
    return ClipRRect(
      borderRadius: radius ?? BorderRadius.circular(10),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: !has
            ? Container(
                color: AdminUi.subtle,
                child: const Icon(
                  Icons.event_rounded,
                  size: 40,
                  color: AdminUi.textMuted,
                ),
              )
            : GestureDetector(
                onTap: () => _showFullImage(url),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Shimmers while it loads and stays cached, so flipping
                      // between events doesn't re-download a cover.
                      SkeletonNetworkImage(
                        url: url,
                        fit: BoxFit.cover,
                        errorChild: Container(
                          color: AdminUi.subtle,
                          child: const Icon(
                            Icons.broken_image_rounded,
                            size: 30,
                            color: AdminUi.textMuted,
                          ),
                        ),
                      ),
                      // The banner is a cropped preview; tapping opens the
                      // complete photo.
                      Positioned(
                        bottom: 8,
                        right: 10,
                        child: IgnorePointer(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.zoom_out_map_rounded,
                                  color: Colors.white,
                                  size: 13,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'View',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
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
      ),
    );
  }

  /// Left pane — where this event stands, and the cover the community will see.
  ///
  /// Deliberately NOT the report's stepper: an event has no stages to walk
  /// through. It's waiting on a reviewer, published, or rejected.
  Widget _statusPane() {
    final accent = _statusColor(e.status);

    final String headline;
    final String blurb;
    switch (e.status) {
      case EventStatus.pending:
        headline = 'This event is awaiting review.';
        blurb = 'Check the details, then publish it to the community feed or '
            'reject it.';
        break;
      case EventStatus.approved:
        headline = 'This event is published.';
        blurb = 'It\'s live on the community feed and citizens can see it.';
        break;
      case EventStatus.rejected:
        headline = 'This event was rejected.';
        blurb = 'It isn\'t visible to the community. You can still edit it and '
            'publish it again.';
        break;
    }

    return _Pane(
      title: 'Event Status',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusCard(
            chip: _statusLabel(e.status),
            headline: headline,
            blurb: blurb,
            accent: accent,
            facts: [
              (label: 'Event date', value: _shortDate(e.eventDate)),
              (label: 'Event time', value: e.eventTime),
            ],
          ),
          const SizedBox(height: 18),
          _IconSection(
            icon: Icons.image_rounded,
            title: 'Cover Photo',
            child: _cover(height: 190),
          ),
          _IconSection(
            icon: Icons.star_rounded,
            title: 'Featured',
            isLast: true,
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Pin this event to the top of the community feed.',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: AdminUi.textSecondary,
                    ),
                  ),
                ),
                Switch(
                  value: _featured,
                  activeThumbColor: AppColors.primaryBlue,
                  onChanged: _busy || _featuring ? null : _toggleFeatured,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Right pane — what the event actually is, and the decision buttons.
  /// Mirrors the report details pane, including its Action block at the foot.
  Widget _detailsPane() {
    return _Pane(
      title: 'Event Details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 88, child: _cover(height: 88)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _KvRow(label: 'Status', trailing: _StatusPill(e.status)),
                    _KvRow(label: 'ID', value: '#EVT-${_shortIdOf(e.id)}'),
                    _KvRow(label: 'Date', value: _shortDate(e.eventDate)),
                    _KvRow(label: 'Time', value: e.eventTime),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(height: 1, color: AdminUi.border),
          const SizedBox(height: 18),
          _IconSection(
            icon: Icons.event_rounded,
            title: 'Event',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.title,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.3,
                    fontWeight: FontWeight.w700,
                    color: AdminUi.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _CategoryChip(
                      category: e.category,
                      colorHex: e.categoryColor,
                    ),
                    EventStatusPill(
                      eventDate: e.eventDate,
                      eventTime: e.eventTime,
                      fontSize: 11,
                    ),
                  ],
                ),
              ],
            ),
          ),
          _IconSection(
            icon: Icons.location_on_rounded,
            title: 'Location',
            child: Text(
              e.location.trim().isEmpty ? '—' : e.location,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AdminUi.textSecondary,
              ),
            ),
          ),
          _IconSection(
            icon: Icons.description_rounded,
            title: 'Description',
            isLast: (e.whatToExpect ?? '').isEmpty &&
                (e.requirements ?? '').isEmpty,
            child: Text(
              (e.description ?? '').trim().isEmpty ? '—' : e.description!,
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: AdminUi.textSecondary,
              ),
            ),
          ),
          if ((e.whatToExpect ?? '').isNotEmpty)
            _IconSection(
              icon: Icons.checklist_rounded,
              title: 'What to expect',
              isLast: (e.requirements ?? '').isEmpty,
              child: Text(
                e.whatToExpect!,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: AdminUi.textSecondary,
                ),
              ),
            ),
          if ((e.requirements ?? '').isNotEmpty)
            _IconSection(
              icon: Icons.rule_rounded,
              title: 'Requirements',
              isLast: true,
              child: Text(
                e.requirements!,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: AdminUi.textSecondary,
                ),
              ),
            ),
          const SizedBox(height: 18),
          const Divider(height: 1, color: AdminUi.border),
          const SizedBox(height: 16),
          _actionSection(),
        ],
      ),
    );
  }

  /// Which buttons appear is driven by where the event actually is: only one
  /// still on the desk can be published or rejected; a decided one can be
  /// edited or removed.
  Widget _actionSection() {
    final notifier = ref.read(adminEventsProvider.notifier);
    final pending = e.status == EventStatus.pending;

    final buttons = <Widget>[
      if (pending) ...[
        _ActionButton(
          label: 'Publish',
          icon: Icons.check_rounded,
          color: AppColors.green,
          busy: _busy,
          onTap: _busy
              ? null
              : () => _run(() => notifier.approve(e.id), 'Event published.'),
        ),
        _ActionButton(
          label: 'Reject',
          icon: Icons.close_rounded,
          color: AppColors.red,
          outlined: true,
          onTap: _busy
              ? null
              : () => _run(() => notifier.reject(e.id), 'Event rejected.'),
        ),
      ] else ...[
        _ActionButton(
          label: 'Edit Event',
          icon: Icons.edit_rounded,
          color: AppColors.primaryBlue,
          onTap: _busy
              ? null
              : () {
                  // The form must open on the event as it stands NOW: flipping
                  // Featured here already wrote to the row, and handing it the
                  // snapshot this dialog opened with would let Save changes put
                  // the old flag back.
                  final fresh =
                      ref
                          .read(adminEventsProvider)
                          .valueOrNull
                          ?.where((x) => x.id == e.id)
                          .firstOrNull ??
                      e;
                  Navigator.pop(context);
                  showEventForm(context, existing: fresh);
                },
        ),
        _ActionButton(
          label: 'Delete Event',
          icon: Icons.delete_outline_rounded,
          color: AppColors.red,
          outlined: true,
          onTap: _busy ? null : _confirmDelete,
        ),
      ],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Action',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AdminUi.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, c) {
            // Side by side needs room for both labels; below that they stack
            // rather than ellipsing into "Delete Ev…".
            if (c.maxWidth < 300) {
              return Column(
                children: [
                  for (var i = 0; i < buttons.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    buttons[i],
                  ],
                ],
              );
            }
            return Row(
              children: [
                for (var i = 0; i < buttons.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(child: buttons[i]),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final narrow = adminDetailIsNarrow(context);

    // One pane at a time on a phone, or in a dialog too narrow for two columns.
    // Status leads: the cover and the publish decision are why you opened this.
    Widget paneTabs() => AdminSegmentedTabs(
      labels: const ['Event Status', 'Event Details'],
      selected: _paneTab,
      onSelect: (i) => setState(() => _paneTab = i),
    );

    Widget activePane() => SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: _paneTab == 0 ? _statusPane() : _detailsPane(),
    );

    if (narrow) {
      return AdminDetailScaffold(
        title: 'Event details',
        child: Container(
          color: AdminUi.pageBg,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                child: paneTabs(),
              ),
              Expanded(child: activePane()),
            ],
          ),
        ),
      );
    }

    return Dialog(
      backgroundColor: AdminUi.pageBg,
      // Tight vertical inset: the panes are long, and every pixel given back
      // here is a pixel the admin doesn't have to scroll.
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120, maxHeight: 900),
        child: LayoutBuilder(
          builder: (context, c) {
            if (c.maxWidth < _kTwoPaneFrom) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                    child: Row(
                      children: [
                        Expanded(child: paneTabs()),
                        const SizedBox(width: 10),
                        const _PaneCloseButton(),
                      ],
                    ),
                  ),
                  Flexible(child: activePane()),
                ],
              );
            }
            return Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: AdminTwoPaneRow(
                    main: _statusPane(),
                    side: _detailsPane(),
                  ),
                ),
                // Pinned rather than scrolled with the pane — the way out stays
                // put however far down you are.
                const Positioned(top: 22, right: 22, child: _PaneCloseButton()),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Width at which the detail splits into two columns. Matches the reports,
/// suggestions, feedback and verification consoles so every detail breaks at
/// the same point.
const double _kTwoPaneFrom = 900;

/// Short, human-readable handle for an event — the id has no server-side short
/// form, so the first block of the uuid stands in.
String _shortIdOf(String id) {
  final clean = id.replaceAll('-', '');
  return (clean.length >= 8 ? clean.substring(0, 8) : clean).toUpperCase();
}

/// Test hook for the status card that heads the detail's left pane — the piece
/// with the width-dependent illustration and fact strip.
Widget eventStatusCardForTesting({
  required String chip,
  required String headline,
  required String blurb,
  required Color accent,
  List<({String label, String value})> facts = const [],
}) => _StatusCard(
  chip: chip,
  headline: headline,
  blurb: blurb,
  accent: accent,
  facts: facts,
);

// ── Detail building blocks ───────────────────────────────────────────────────

/// A titled white card — one of the two panes of the event detail.
class _Pane extends StatelessWidget {
  final String title;
  final Widget child;
  const _Pane({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AdminUi.surface,
        borderRadius: BorderRadius.circular(AdminUi.cardRadius),
        border: Border.all(color: AdminUi.border),
        boxShadow: AdminUi.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AdminUi.textPrimary,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

/// The status headline card at the top of the left pane — the event's
/// equivalent of the report's stage card, illustrated with the activity mark.
class _StatusCard extends StatelessWidget {
  final String chip;
  final String headline;
  final String blurb;
  final Color accent;
  final List<({String label, String value})> facts;
  const _StatusCard({
    required this.chip,
    required this.headline,
    required this.blurb,
    required this.accent,
    this.facts = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AdminUi.cardRadius),
        border: Border.all(color: accent.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                chip,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, c) {
              final copy = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    headline,
                    style: const TextStyle(
                      fontSize: 18,
                      height: 1.25,
                      fontWeight: FontWeight.w800,
                      color: AdminUi.textPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    blurb,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: AdminUi.textSecondary,
                    ),
                  ),
                ],
              );

              // Below ~380px the illustration would squeeze the headline into a
              // ragged column, so it drops out and the copy takes the full row.
              if (c.maxWidth < 380) return copy;
              return Row(
                children: [
                  Expanded(child: copy),
                  const SizedBox(width: 12),
                  Image.asset(
                    'assets/images/activity.webp',
                    width: (c.maxWidth * 0.22).clamp(72.0, 116.0),
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ],
              );
            },
          ),
          if (facts.isNotEmpty) ...[
            const SizedBox(height: 14),
            _FactStrip(facts: facts, accent: accent),
          ],
        ],
      ),
    );
  }
}

/// The white inset strip of label/value pairs at the foot of the status card.
/// Side by side when there's room, stacked when there isn't, so a long date or
/// time range never gets clipped.
class _FactStrip extends StatelessWidget {
  final List<({String label, String value})> facts;
  final Color accent;
  const _FactStrip({required this.facts, required this.accent});

  @override
  Widget build(BuildContext context) {
    Widget fact(({String label, String value}) f) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          f.label,
          style: const TextStyle(fontSize: 11, color: AdminUi.textMuted),
        ),
        const SizedBox(height: 3),
        Text(
          f.value,
          style: const TextStyle(
            fontSize: 12.5,
            height: 1.35,
            fontWeight: FontWeight.w700,
            color: AdminUi.textPrimary,
          ),
        ),
      ],
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AdminUi.surface,
        borderRadius: BorderRadius.circular(AdminUi.controlRadius),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          // Each fact needs ~150px to seat a date on two lines; under that the
          // row becomes a stack.
          if (c.maxWidth >= facts.length * 150) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < facts.length; i++) ...[
                  if (i > 0) const SizedBox(width: 14),
                  Expanded(child: fact(facts[i])),
                ],
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < facts.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                fact(facts[i]),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// "Label: value" line in the details pane's id block. Pass [value] for plain
/// text or [trailing] for a widget (the status pill).
class _KvRow extends StatelessWidget {
  final String label;
  final String? value;
  final Widget? trailing;
  const _KvRow({required this.label, this.value, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AdminUi.textPrimary,
            ),
          ),
          Expanded(
            child:
                trailing ??
                Text(
                  value ?? '—',
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: AdminUi.textSecondary,
                  ),
                ),
          ),
        ],
      ),
    );
  }
}

/// An icon + heading with its content indented beneath — the repeating unit of
/// both panes (Cover Photo, Featured, Event, Location, Description).
class _IconSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;
  final bool isLast;
  const _IconSection({
    required this.icon,
    required this.title,
    required this.child,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: AppColors.primaryBlue),
              const SizedBox(width: 7),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AdminUi.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(padding: const EdgeInsets.only(left: 22), child: child),
        ],
      ),
    );
  }
}

/// A full-width decision button for the details pane's Action block.
class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool outlined;
  final bool busy;
  final VoidCallback? onTap;
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    this.onTap,
    this.outlined = false,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 10, vertical: 13),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AdminUi.controlRadius),
        ),
      ),
    );
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (busy && !outlined)
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          )
        else
          Icon(icon, size: 17),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );

    return SizedBox(
      width: double.infinity,
      child: outlined
          ? OutlinedButton(
              onPressed: onTap,
              style: style.merge(
                OutlinedButton.styleFrom(
                  foregroundColor: color,
                  side: BorderSide(color: color.withValues(alpha: 0.45)),
                ),
              ),
              child: content,
            )
          : FilledButton(
              onPressed: onTap,
              style: style.merge(
                FilledButton.styleFrom(backgroundColor: color),
              ),
              child: content,
            ),
    );
  }
}

/// The dialog's way out, styled to sit on a pane's top-right corner.
class _PaneCloseButton extends StatelessWidget {
  const _PaneCloseButton();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AdminUi.subtle,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.pop(context),
        child: Tooltip(
          message: 'Close',
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              border: Border.fromBorderSide(BorderSide(color: AdminUi.border)),
            ),
            child: const Icon(
              Icons.close_rounded,
              size: 18,
              color: AdminUi.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Presented exactly like the event detail — same shell, same breakpoint, same
/// pane — so editing an event looks like the event you tapped to get here,
/// rather than a second, unrelated kind of card.
void showEventForm(BuildContext context, {EventModel? existing}) {
  showAdminDetail(
    context,
    // The form holds unsaved input; only Cancel / the X may close it.
    barrierDismissible: false,
    builder: (_) => _EventFormDialog(existing: existing),
  );
}

Future<void> _reportEventSave(Future<void> op, BuildContext ctx) async {
  try {
    await op;
    if (ctx.mounted) {
      showAdminSnackBar(ctx, 'Event published.', type: AdminSnackType.success);
    }
  } catch (_) {
    if (ctx.mounted) {
      showAdminSnackBar(ctx, 'Could not publish the event. Please try again.',
          type: AdminSnackType.error);
    }
  }
}

class _EventFormDialog extends ConsumerStatefulWidget {
  final EventModel? existing;
  const _EventFormDialog({this.existing});

  @override
  ConsumerState<_EventFormDialog> createState() => _EventFormDialogState();
}

class _EventFormDialogState extends ConsumerState<_EventFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _time;
  late final TextEditingController _description;
  late final TextEditingController _expect;
  late final TextEditingController _requirements;

  // Date / location are chosen through pickers, but they render as read-only
  // fields so they share the exact metrics and error styling of every other
  // field — hence the display controllers.
  late final TextEditingController _dateText;
  late final TextEditingController _locationText;

  String _category = 'Health';
  String? _barangay;
  DateTime? _date;
  TimeOfDay? _timeOfDay;
  bool _featured = false;
  bool _saving = false;
  String? _error;

  // Image: either an existing URL, or a freshly picked file (bytes + ext).
  String? _imageUrl;
  Uint8List? _pickedBytes;
  String? _pickedExt;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _time = TextEditingController(text: e?.eventTime ?? '');
    _description = TextEditingController(text: e?.description ?? '');
    _expect = TextEditingController(text: e?.whatToExpect ?? '');
    _requirements = TextEditingController(text: e?.requirements ?? '');
    _category = e != null && kEventCategoryColors.containsKey(e.category)
        ? e.category
        : 'Health';
    // Older events were saved with free-text venues that predate the canonical
    // barangay list — keep whatever is stored so editing never silently blanks
    // or rewrites the location.
    _barangay = (e?.location.trim().isNotEmpty ?? false) ? e!.location.trim() : null;
    _date = e?.eventDate;
    // Times were free text before this form had a picker, so an unparseable
    // legacy value stays in the field verbatim and only the picker's starting
    // hour falls back.
    _timeOfDay = _parseTime(e?.eventTime);
    _featured = e?.isFeatured ?? false;
    _imageUrl = e?.imageUrl;
    _dateText = TextEditingController(
      text: _date == null ? '' : _shortDate(_date),
    );
    _locationText = TextEditingController(text: _barangay ?? '');
  }

  @override
  void dispose() {
    _title.dispose();
    _time.dispose();
    _description.dispose();
    _expect.dispose();
    _requirements.dispose();
    _dateText.dispose();
    _locationText.dispose();
    super.dispose();
  }

  static final _timeRe = RegExp(r'^(\d{1,2}):(\d{2})\s*([AaPp])\.?[Mm]\.?$');

  static TimeOfDay? _parseTime(String? raw) {
    final m = _timeRe.firstMatch((raw ?? '').trim());
    if (m == null) return null;
    var hour = int.parse(m.group(1)!);
    final minute = int.parse(m.group(2)!);
    if (hour < 1 || hour > 12 || minute > 59) return null;
    if (hour == 12) hour = 0;
    if (m.group(3)!.toLowerCase() == 'p') hour += 12;
    return TimeOfDay(hour: hour, minute: minute);
  }

  /// Formatted here rather than through MaterialLocalizations because the string
  /// is stored and shown verbatim in the citizen feed — it must not drift with
  /// the viewer's locale or 24-hour setting.
  static String _formatTime(TimeOfDay t) {
    final hour = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final minute = t.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${t.period == DayPeriod.am ? 'AM' : 'PM'}';
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    // On a floating dialog (web / desktop) go straight to the file/gallery
    // picker — a slide-up sheet would detach from the card. On the full-screen
    // mobile form, offer the Camera / Gallery sheet (same as the community
    // composer). Camera is hidden implicitly on web since it can't be chosen.
    final floating = !adminDetailIsNarrow(context);
    try {
      XFile? picked;
      if (floating) {
        picked = await picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 82,
          maxWidth: 1400,
        );
      } else {
        final mode = await showMediaPickerSheet(context, allowVideo: false);
        if (mode == null) return;
        picked = await picker.pickImage(
          source: mode == 'camera' ? ImageSource.camera : ImageSource.gallery,
          imageQuality: 82,
          maxWidth: 1400,
        );
      }
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _pickedBytes = bytes;
        _pickedExt = picked!.name.contains('.')
            ? picked.name.split('.').last
            : 'jpg';
      });
    } catch (e) {
      if (!mounted) return;
      showAdminSnackBar(
        context,
        'Could not add photo: $e',
        type: AdminSnackType.error,
      );
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final res = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (res == null || !mounted) return;
    setState(() {
      _date = res;
      _dateText.text = _shortDate(res);
    });
  }

  Future<void> _pickTime() async {
    final res = await showTimePicker(
      context: context,
      initialTime: _timeOfDay ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (res == null || !mounted) return;
    setState(() {
      _timeOfDay = res;
      _time.text = _formatTime(res);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final notifier = ref.read(adminEventsProvider.notifier);
    final colorHex = _colorToHex(kEventCategoryColors[_category]!);

    // ── EDIT: keep the await-based flow (upload → save → close). ──────────────
    if (_isEdit) {
      setState(() {
        _saving = true;
        _error = null;
      });
      try {
        var imageUrl = _imageUrl;
        if (_pickedBytes != null) {
          imageUrl = await notifier.uploadImage(_pickedBytes!, _pickedExt ?? 'jpg');
        }
        await notifier.edit(widget.existing!.id, {
          'title': _title.text.trim(),
          'location': _barangay!,
          'event_date': _date!.toIso8601String().substring(0, 10),
          'event_time': _time.text.trim(),
          'category': _category,
          'category_color': colorHex,
          'is_featured': _featured,
          'image_url': imageUrl,
          'description':
              _description.text.trim().isEmpty ? null : _description.text.trim(),
          'what_to_expect':
              _expect.text.trim().isEmpty ? null : _expect.text.trim(),
          'requirements': _requirements.text.trim().isEmpty
              ? null
              : _requirements.text.trim(),
        });
        if (!mounted) return;
        Navigator.pop(context);
        showAdminSnackBar(context, 'Event updated.', type: AdminSnackType.success);
      } catch (err) {
        if (!mounted) return;
        setState(() {
          _saving = false;
          _error = 'Could not save the event. Please try again.';
        });
      }
      return;
    }

    // ── CREATE: instant/optimistic — show the event + close immediately, then
    //    upload the cover + insert in the background (like the newsfeed post). ─
    final temp = EventModel(
      id: 'temp_${DateTime.now().microsecondsSinceEpoch}',
      title: _title.text.trim(),
      location: _barangay!,
      eventDate: _date!,
      eventTime: _time.text.trim(),
      category: _category,
      categoryColor: colorHex,
      isFeatured: _featured,
      imageUrl: null,
      description:
          _description.text.trim().isEmpty ? null : _description.text.trim(),
      whatToExpect: _expect.text.trim().isEmpty ? null : _expect.text.trim(),
      requirements:
          _requirements.text.trim().isEmpty ? null : _requirements.text.trim(),
      status: EventStatus.approved,
      createdBy: '',
      reviewedBy: null,
      createdAt: DateTime.now(),
    );
    final rootContext = Navigator.of(context, rootNavigator: true).context;

    unawaited(
      _reportEventSave(
        notifier.create(
          title: _title.text.trim(),
          location: _barangay!,
          eventDate: _date!,
          eventTime: _time.text.trim(),
          category: _category,
          categoryColor: colorHex,
          isFeatured: _featured,
          imageBytes: _pickedBytes,
          imageExt: _pickedExt,
          description: _description.text.trim(),
          whatToExpect: _expect.text.trim(),
          requirements: _requirements.text.trim(),
          optimistic: temp,
        ),
        rootContext,
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final narrow = adminDetailIsNarrow(context);

    if (narrow) {
      return AdminDetailScaffold(
        title: _isEdit ? 'Edit event' : 'New event',
        child: Container(
          color: AdminUi.pageBg,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: _formPane(),
          ),
        ),
      );
    }

    return Dialog(
      backgroundColor: AdminUi.pageBg,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        // One column, so it stops well short of the detail's two-pane width —
        // a form read across 1120px would be a tiring line length.
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 900),
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: _formPane(),
            ),
            // Pinned, like the detail's — the way out stays put however far
            // down the form you are.
            const Positioned(top: 22, right: 22, child: _PaneCloseButton()),
          ],
        ),
      ),
    );
  }

  /// The form as ONE pane, built from the same pieces as the detail's panes
  /// (_Pane, _IconSection, _ActionButton) and under the same section headings —
  /// Cover Photo / Event / Location / Description / Featured — so the editor
  /// reads as the detail with its values made editable.
  Widget _formPane() {
    return _Pane(
      title: _isEdit ? 'Edit Event' : 'New Event',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _IconSection(
              icon: Icons.image_rounded,
              title: 'Cover Photo',
              child: _buildImagePicker(),
            ),
            _IconSection(
              icon: Icons.event_rounded,
              title: 'Event',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _field(_title, hint: 'Event name', required: true),
                  const SizedBox(height: 10),
                  _buildCategoryPicker(),
                ],
              ),
            ),
            _IconSection(
              icon: Icons.location_on_rounded,
              title: 'Location',
              child: _buildBarangayPicker(),
            ),
            _IconSection(
              icon: Icons.schedule_rounded,
              title: 'Date & Time',
              child: _buildDateTimeRow(),
            ),
            _IconSection(
              icon: Icons.description_rounded,
              title: 'Description',
              child: _field(
                _description,
                hint: 'What is this event about?',
                maxLines: 3,
              ),
            ),
            _IconSection(
              icon: Icons.checklist_rounded,
              title: 'What to expect',
              child: _field(_expect, hint: 'Optional', maxLines: 2),
            ),
            _IconSection(
              icon: Icons.rule_rounded,
              title: 'Requirements',
              child: _field(_requirements, hint: 'Optional', maxLines: 2),
            ),
            _IconSection(
              icon: Icons.star_rounded,
              title: 'Featured',
              isLast: true,
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Pin this event to the top of the community feed.',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: AdminUi.textSecondary,
                      ),
                    ),
                  ),
                  Switch(
                    value: _featured,
                    activeThumbColor: AppColors.primaryBlue,
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _featured = v),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(
                _error!,
                style: const TextStyle(fontSize: 12, color: AppColors.red),
              ),
            ],
            const SizedBox(height: 18),
            const Divider(height: 1, color: AdminUi.border),
            const SizedBox(height: 16),
            _actionSection(),
          ],
        ),
      ),
    );
  }

  /// Mirrors the detail pane's Action block, down to the stack-when-cramped
  /// rule, so the buttons you leave the detail by and the buttons you leave the
  /// form by are the same buttons.
  Widget _actionSection() {
    final buttons = <Widget>[
      _ActionButton(
        label: _isEdit ? 'Save changes' : 'Publish',
        icon: _isEdit ? Icons.save_rounded : Icons.publish_rounded,
        color: AppColors.primaryBlue,
        busy: _saving,
        onTap: _saving ? null : _save,
      ),
      _ActionButton(
        label: 'Cancel',
        icon: Icons.close_rounded,
        color: AdminUi.textSecondary,
        outlined: true,
        onTap: _saving ? null : () => Navigator.pop(context),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Action',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AdminUi.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, c) {
            if (c.maxWidth < 300) {
              return Column(
                children: [
                  for (var i = 0; i < buttons.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    buttons[i],
                  ],
                ],
              );
            }
            return Row(
              children: [
                for (var i = 0; i < buttons.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(child: buttons[i]),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildImagePicker() {
    final hasImage =
        _pickedBytes != null || (_imageUrl != null && _imageUrl!.isNotEmpty);
    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        // Same height as the detail's Cover Photo, so the picture doesn't
        // resize when you move between viewing and editing.
        height: 190,
        width: double.infinity,
        decoration: BoxDecoration(
          color: AdminUi.subtle,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AdminUi.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: hasImage
            ? Stack(
                fit: StackFit.expand,
                children: [
                  if (_pickedBytes != null)
                    Image.memory(_pickedBytes!, fit: BoxFit.cover)
                  else
                    CachedNetworkImage(
                      imageUrl: _imageUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => const _ImageHint(),
                    ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.photo_camera_rounded,
                            size: 14,
                            color: Colors.white,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Change',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : const _ImageHint(),
      ),
    );
  }

  Widget _buildCategoryPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Category',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AdminUi.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in kEventCategoryColors.entries)
              GestureDetector(
                onTap: () => setState(() => _category = entry.key),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: _category == entry.key
                        ? Color(entry.value).withValues(alpha: 0.14)
                        : AdminUi.subtle,
                    borderRadius: BorderRadius.circular(AdminUi.controlRadius),
                    border: Border.all(
                      color: _category == entry.key
                          ? Color(entry.value)
                          : AdminUi.border,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: Color(entry.value),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        entry.key,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _category == entry.key
                              ? Color(entry.value)
                              : AdminUi.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// Date and time sit side by side when there is room, but below ~380dp of
  /// form width the two boxes squeeze their labels, so they stack instead.
  Widget _buildDateTimeRow() {
    final date = _pickerField(
      _dateText,
      label: 'Date',
      hint: 'Choose date',
      icon: Icons.calendar_today_rounded,
      onTap: _pickDate,
    );
    final time = _pickerField(
      _time,
      label: 'Time',
      hint: 'Choose time',
      icon: Icons.access_time_rounded,
      onTap: _pickTime,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 380) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [date, const SizedBox(height: 12), time],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: date),
            const SizedBox(width: 12),
            Expanded(child: time),
          ],
        );
      },
    );
  }

  /// Location is constrained to Aparri's canonical barangays so events line up
  /// with the barangay filters citizens and staff already browse by.
  Widget _buildBarangayPicker() => _pickerField(
    _locationText,
    hint: 'Select barangay',
    icon: Icons.location_on_rounded,
    onTap: _pickBarangay,
    trailing: Icons.expand_more_rounded,
  );

  Future<void> _pickBarangay() async {
    // Same rule as the cover-image picker: the wide layout floats this form in
    // a dialog, where a slide-up sheet would detach from the card.
    final wide = !adminDetailIsNarrow(context);
    final String? selected;
    if (wide) {
      selected = await showAppDialog<String>(
        context: context,
        builder: (_) => _BarangayPickerDialog(current: _barangay),
      );
    } else {
      selected = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _BarangayPickerSheet(current: _barangay),
      );
    }
    if (selected == null || !mounted) return;
    setState(() {
      _barangay = selected;
      _locationText.text = selected!;
    });
  }

  /// A field whose value comes from a picker rather than the keyboard. It is a
  /// read-only [TextFormField] rather than a tappable box so that its height,
  /// border and error styling are the ones [_field] already produces — the two
  /// cannot drift apart.
  Widget _pickerField(
    TextEditingController ctrl, {
    String? label,
    required String hint,
    required IconData icon,
    required VoidCallback onTap,
    IconData? trailing,
  }) => _field(
    ctrl,
    label: label,
    hint: hint,
    required: true,
    readOnly: true,
    onTap: onTap,
    icon: icon,
    trailing: trailing,
  );

  /// [label] is omitted when the enclosing [_IconSection] heading already names
  /// the field — only Date and Time, which share a row, still caption
  /// themselves.
  Widget _field(
    TextEditingController ctrl, {
    String? label,
    String? hint,
    int maxLines = 1,
    bool required = false,
    bool readOnly = false,
    VoidCallback? onTap,
    IconData? icon,
    IconData? trailing,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AdminUi.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
        ],
        TextFormField(
          controller: ctrl,
          maxLines: maxLines,
          readOnly: readOnly,
          onTap: onTap,
          // A picker field never takes keyboard input, so it should not steal
          // focus (and pop the soft keyboard) on tap.
          canRequestFocus: !readOnly,
          mouseCursor: readOnly ? SystemMouseCursors.click : null,
          style: const TextStyle(fontSize: 13, color: AdminUi.textPrimary),
          validator: required
              ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
              : null,
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 13, color: AdminUi.textMuted),
            filled: true,
            fillColor: AdminUi.surface,
            // The icons carry their own padding, and contentPadding drops its
            // matching side: InputDecorator measures contentPadding from the
            // icon's edge, not the field's, so leaving both on would double it.
            prefixIcon: icon == null
                ? null
                : Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
                    child: Icon(icon, size: 16, color: AdminUi.textMuted),
                  ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 0,
              minHeight: 0,
            ),
            suffixIcon: trailing == null
                ? null
                : Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 12, 0),
                    child: Icon(trailing, size: 16, color: AdminUi.textMuted),
                  ),
            suffixIconConstraints: const BoxConstraints(
              minWidth: 0,
              minHeight: 0,
            ),
            contentPadding: EdgeInsets.only(
              left: icon == null ? 12 : 0,
              right: trailing == null ? 12 : 0,
              top: 11,
              bottom: 11,
            ),
            border: _border(AdminUi.border),
            enabledBorder: _border(AdminUi.border),
            focusedBorder: _border(AppColors.primaryBlue),
            errorBorder: _border(AppColors.red),
            focusedErrorBorder: _border(AppColors.red),
          ),
        ),
      ],
    );
  }

  static OutlineInputBorder _border(Color c) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(AdminUi.controlRadius),
    borderSide: BorderSide(color: c),
  );
}

// ── Barangay picker ───────────────────────────────────────────────────────────
// Two shells over one searchable list: a centred dialog for web/tablet (where
// the event form itself floats) and a draggable sheet for phones.

class _BarangayPickerDialog extends StatelessWidget {
  final String? current;
  const _BarangayPickerDialog({this.current});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Dialog(
      backgroundColor: AdminUi.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 420,
          maxHeight: size.height * 0.7,
        ),
        child: _BarangayPickerBody(current: current),
      ),
    );
  }
}

class _BarangayPickerSheet extends StatelessWidget {
  final String? current;
  const _BarangayPickerSheet({this.current});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (ctx, scrollCtrl) => Material(
          color: AdminUi.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          clipBehavior: Clip.antiAlias,
          child: _BarangayPickerBody(
            current: current,
            scrollController: scrollCtrl,
            showGrabber: true,
          ),
        ),
      ),
    );
  }
}

class _BarangayPickerBody extends StatefulWidget {
  final String? current;
  final ScrollController? scrollController;
  final bool showGrabber;
  const _BarangayPickerBody({
    this.current,
    this.scrollController,
    this.showGrabber = false,
  });

  @override
  State<_BarangayPickerBody> createState() => _BarangayPickerBodyState();
}

class _BarangayPickerBodyState extends State<_BarangayPickerBody> {
  final _search = TextEditingController();
  late List<String> _results = List<String>.from(kAparriBarangays);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _filter(String q) {
    final query = q.trim().toLowerCase();
    setState(() {
      _results = query.isEmpty
          ? List<String>.from(kAparriBarangays)
          : kAparriBarangays
                .where((b) => b.toLowerCase().contains(query))
                .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showGrabber)
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 10),
            decoration: BoxDecoration(
              color: AdminUi.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Select barangay',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AdminUi.textPrimary,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: AdminUi.textMuted),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _search,
            onChanged: _filter,
            style: const TextStyle(fontSize: 13, color: AdminUi.textPrimary),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search barangay…',
              hintStyle: const TextStyle(fontSize: 13, color: AdminUi.textMuted),
              prefixIcon: const Icon(
                Icons.search_rounded,
                size: 18,
                color: AdminUi.textMuted,
              ),
              filled: true,
              fillColor: AdminUi.subtle,
              contentPadding: const EdgeInsets.symmetric(vertical: 11),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AdminUi.controlRadius),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Flexible(
          child: _results.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    'No barangay matches that search.',
                    style: TextStyle(fontSize: 13, color: AdminUi.textMuted),
                  ),
                )
              : ListView.builder(
                  controller: widget.scrollController,
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: _results.length,
                  itemBuilder: (_, i) {
                    final name = _results[i];
                    final selected = name == widget.current;
                    return ListTile(
                      dense: true,
                      title: Text(
                        name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: selected
                              ? AppColors.primaryBlue
                              : AdminUi.textPrimary,
                        ),
                      ),
                      trailing: selected
                          ? const Icon(
                              Icons.check_rounded,
                              size: 18,
                              color: AppColors.primaryBlue,
                            )
                          : null,
                      onTap: () => Navigator.pop(context, name),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ImageHint extends StatelessWidget {
  const _ImageHint();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.add_photo_alternate_rounded,
            size: 30,
            color: AdminUi.textMuted,
          ),
          SizedBox(height: 6),
          Text(
            'Add a cover image',
            style: TextStyle(fontSize: 12, color: AdminUi.textMuted),
          ),
        ],
      ),
    );
  }
}

// ══ Shared bits ═══════════════════════════════════════════════════════════════

const TextStyle _ddStyle = TextStyle(fontSize: 13, color: AdminUi.textPrimary);


class _PrimaryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _PrimaryButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primaryBlue,
      borderRadius: BorderRadius.circular(AdminUi.controlRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AdminUi.controlRadius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterBox extends StatelessWidget {
  final Widget child;
  const _FilterBox({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: AdminUi.surface,
        borderRadius: BorderRadius.circular(AdminUi.controlRadius),
        border: Border.all(color: AdminUi.border),
      ),
      child: child,
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _Card({required this.child, this.padding = const EdgeInsets.all(20)});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AdminUi.surface,
        borderRadius: BorderRadius.circular(AdminUi.cardRadius),
        border: Border.all(color: AdminUi.border),
        boxShadow: AdminUi.cardShadow,
      ),
      child: child,
    );
  }
}

class _ResultsMessage extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  final Widget? action;
  const _ResultsMessage({
    required this.icon,
    required this.color,
    required this.text,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: color),
            const SizedBox(height: 10),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AdminUi.textMuted),
            ),
            if (action != null) ...[const SizedBox(height: 8), action!],
          ],
        ),
      ),
    );
  }
}

class _RowSkeleton extends StatelessWidget {
  const _RowSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SkeletonBox(width: 44, height: 44, radius: 10),
          SizedBox(width: 12),
          Expanded(flex: 4, child: _Bar(width: 140)),
          Expanded(flex: 2, child: _Bar(width: 80)),
          Expanded(flex: 2, child: _Bar(width: 80)),
          Expanded(flex: 2, child: _Bar(width: 70)),
          SizedBox(width: 40),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final double width;
  const _Bar({required this.width});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SkeletonBox(width: width, height: 11),
    );
  }
}
