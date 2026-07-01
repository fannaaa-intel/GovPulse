import 'dart:async';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/services/events_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/modal/media_picker_sheet.dart';
import '../providers/admin_events_provider.dart';
import '../theme/admin_ui.dart';
import '../widgets/admin_skeleton.dart';

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
        final hay =
            '${e.title} ${e.location} ${e.category}'.toLowerCase();
        if (!hay.contains(_query)) return false;
      }
      return true;
    }).toList();
  }

  Future<void> _openDetail(EventModel e) => showDialog(
    context: context,
    barrierColor: Colors.black54,
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
        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Events',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: AdminUi.textPrimary,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Publish community events and review staff submissions',
              style: TextStyle(fontSize: 13, color: AdminUi.textMuted),
            ),
          ],
        );

        final actions = Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _GhostButton(
              icon: Icons.refresh_rounded,
              label: 'Refresh',
              onTap: () => ref.read(adminEventsProvider.notifier).refresh(),
            ),
            _PrimaryButton(
              icon: Icons.add_rounded,
              label: 'New event',
              onTap: () => _openForm(),
            ),
          ],
        );

        if (c.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [title, const SizedBox(height: 14), actions],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Expanded(child: title), actions],
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
              hintStyle:
                  const TextStyle(fontSize: 13, color: AdminUi.textMuted),
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
              onChanged: (v) =>
                  setState(() => _categoryFilter = v ?? 'All'),
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
              text: _statusFilter == null && _query.isEmpty &&
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
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: c,
        ),
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
                      Row(
                        children: [
                          _CategoryChip(
                            category: event.category,
                            colorHex: event.categoryColor,
                          ),
                          const SizedBox(width: 6),
                          _StatusPill(event.status),
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

  EventModel get e => widget.event;

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(done),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (err) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed: $err'),
          backgroundColor: AppColors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
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

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width.clamp(0.0, 620.0);
    final notifier = ref.read(adminEventsProvider.notifier);

    return Dialog(
      backgroundColor: AdminUi.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width, maxHeight: 660),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Cover image + close
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                  child: SizedBox(
                    height: 150,
                    width: double.infinity,
                    child: e.imageUrl == null || e.imageUrl!.isEmpty
                        ? Container(
                            color: AdminUi.subtle,
                            child: const Icon(
                              Icons.event_rounded,
                              size: 40,
                              color: AdminUi.textMuted,
                            ),
                          )
                        : CachedNetworkImage(
                            imageUrl: e.imageUrl!,
                            fit: BoxFit.cover,
                            placeholder: (_, _) =>
                                Container(color: AdminUi.subtle),
                            errorWidget: (_, _, _) => Container(
                              color: AdminUi.subtle,
                              child: const Icon(
                                Icons.broken_image_rounded,
                                size: 30,
                                color: AdminUi.textMuted,
                              ),
                            ),
                          ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.35),
                    shape: const CircleBorder(),
                    child: IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                      iconSize: 18,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  left: 12,
                  child: _StatusPill(e.status),
                ),
              ],
            ),

            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            e.title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AdminUi.textPrimary,
                            ),
                          ),
                        ),
                        _CategoryChip(
                          category: e.category,
                          colorHex: e.categoryColor,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _InfoTile(
                      icon: Icons.location_on_rounded,
                      label: 'Location',
                      value: e.location,
                    ),
                    _InfoTile(
                      icon: Icons.calendar_today_rounded,
                      label: 'Date',
                      value: _shortDate(e.eventDate),
                    ),
                    _InfoTile(
                      icon: Icons.access_time_rounded,
                      label: 'Time',
                      value: e.eventTime,
                    ),
                    if ((e.description ?? '').isNotEmpty)
                      _Section(title: 'Description', body: e.description!),
                    if ((e.whatToExpect ?? '').isNotEmpty)
                      _Section(title: 'What to expect', body: e.whatToExpect!),
                    if ((e.requirements ?? '').isNotEmpty)
                      _Section(title: 'Requirements', body: e.requirements!),
                    const SizedBox(height: 8),
                    // Featured toggle
                    Row(
                      children: [
                        const Icon(
                          Icons.star_rounded,
                          size: 18,
                          color: AppColors.orange,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Featured event',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AdminUi.textPrimary,
                            ),
                          ),
                        ),
                        Switch(
                          value: e.isFeatured,
                          activeThumbColor: AppColors.primaryBlue,
                          onChanged: _busy
                              ? null
                              : (v) => _run(
                                    () => notifier.setFeatured(e.id, v),
                                    v ? 'Marked as featured.' : 'Unfeatured.',
                                  ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const Divider(height: 1, color: AdminUi.border),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  if (e.status == EventStatus.pending) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _run(
                                  () => notifier.reject(e.id),
                                  'Event rejected.',
                                ),
                        icon: const Icon(Icons.close_rounded, size: 18),
                        label: const Text('Reject'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.red,
                          side: const BorderSide(color: AppColors.red),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _run(
                                  () => notifier.approve(e.id),
                                  'Event published.',
                                ),
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text('Publish'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ] else ...[
                    IconButton(
                      onPressed: _busy ? null : _confirmDelete,
                      icon: const Icon(Icons.delete_outline_rounded),
                      color: AppColors.red,
                      tooltip: 'Delete',
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      onPressed: _busy
                          ? null
                          : () {
                              Navigator.pop(context);
                              showEventForm(context, existing: e);
                            },
                      icon: const Icon(Icons.edit_rounded, size: 18),
                      label: const Text('Edit'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String body;
  const _Section({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: AdminUi.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              color: AdminUi.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AdminUi.subtle,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: AdminUi.border),
            ),
            child: Icon(icon, size: 17, color: AppColors.primaryBlue),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                    color: AdminUi.textMuted,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value.isEmpty ? '—' : value,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AdminUi.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ══ Create / edit form ════════════════════════════════════════════════════════
//
// Responsive, mirroring the community composer: a centred modal dialog on wide
// screens (web / desktop / tablet ≥ 900px) and a full-screen page on phones —
// where a floating card feels cramped and the keyboard would cover it.
void showEventForm(BuildContext context, {EventModel? existing}) {
  final wide = MediaQuery.of(context).size.width >= 900;
  if (wide) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
          child: _EventFormDialog(existing: existing),
        ),
      ),
    );
  } else {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => Scaffold(
          backgroundColor: AdminUi.surface,
          body: SafeArea(child: _EventFormDialog(existing: existing)),
        ),
      ),
    );
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
  late final TextEditingController _location;
  late final TextEditingController _time;
  late final TextEditingController _description;
  late final TextEditingController _expect;
  late final TextEditingController _requirements;

  String _category = 'Health';
  DateTime? _date;
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
    _location = TextEditingController(text: e?.location ?? '');
    _time = TextEditingController(text: e?.eventTime ?? '');
    _description = TextEditingController(text: e?.description ?? '');
    _expect = TextEditingController(text: e?.whatToExpect ?? '');
    _requirements = TextEditingController(text: e?.requirements ?? '');
    _category = e != null && kEventCategoryColors.containsKey(e.category)
        ? e.category
        : 'Health';
    _date = e?.eventDate;
    _featured = e?.isFeatured ?? false;
    _imageUrl = e?.imageUrl;
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _time.dispose();
    _description.dispose();
    _expect.dispose();
    _requirements.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    // On a floating dialog (web / desktop) go straight to the file/gallery
    // picker — a slide-up sheet would detach from the card. On the full-screen
    // mobile form, offer the Camera / Gallery sheet (same as the community
    // composer). Camera is hidden implicitly on web since it can't be chosen.
    final floating = MediaQuery.of(context).size.width >= 900;
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
        _pickedExt =
            picked!.name.contains('.') ? picked.name.split('.').last : 'jpg';
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not add photo: $e'),
          backgroundColor: AppColors.red,
          behavior: SnackBarBehavior.floating,
        ),
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
    if (res != null) setState(() => _date = res);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_date == null) {
      setState(() => _error = 'Please choose an event date.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    final notifier = ref.read(adminEventsProvider.notifier);
    try {
      // Upload a freshly picked image first (if any).
      var imageUrl = _imageUrl;
      if (_pickedBytes != null) {
        imageUrl = await notifier.uploadImage(_pickedBytes!, _pickedExt ?? 'jpg');
      }

      final colorHex = _colorToHex(kEventCategoryColors[_category]!);

      if (_isEdit) {
        await notifier.edit(widget.existing!.id, {
          'title': _title.text.trim(),
          'location': _location.text.trim(),
          'event_date': _date!.toIso8601String().substring(0, 10),
          'event_time': _time.text.trim(),
          'category': _category,
          'category_color': colorHex,
          'is_featured': _featured,
          'image_url': imageUrl,
          'description': _description.text.trim().isEmpty
              ? null
              : _description.text.trim(),
          'what_to_expect':
              _expect.text.trim().isEmpty ? null : _expect.text.trim(),
          'requirements': _requirements.text.trim().isEmpty
              ? null
              : _requirements.text.trim(),
        });
      } else {
        await notifier.create(
          title: _title.text.trim(),
          location: _location.text.trim(),
          eventDate: _date!,
          eventTime: _time.text.trim(),
          category: _category,
          categoryColor: colorHex,
          isFeatured: _featured,
          imageUrl: imageUrl,
          description: _description.text.trim(),
          whatToExpect: _expect.text.trim(),
          requirements: _requirements.text.trim(),
        );
      }

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEdit ? 'Event updated.' : 'Event published.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save the event. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AdminUi.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _isEdit ? 'Edit event' : 'New event',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AdminUi.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    color: AdminUi.textMuted,
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AdminUi.border),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildImagePicker(),
                      const SizedBox(height: 16),
                      _field(_title, 'Title', hint: 'Event name', required: true),
                      const SizedBox(height: 12),
                      _buildCategoryPicker(),
                      const SizedBox(height: 12),
                      _field(
                        _location,
                        'Location',
                        hint: 'Venue / barangay',
                        required: true,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildDatePicker()),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _field(
                              _time,
                              'Time',
                              hint: 'e.g. 9:00 AM',
                              required: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _field(
                        _description,
                        'Description',
                        hint: 'What is this event about?',
                        maxLines: 3,
                      ),
                      const SizedBox(height: 12),
                      _field(
                        _expect,
                        'What to expect',
                        hint: 'Optional',
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      _field(
                        _requirements,
                        'Requirements',
                        hint: 'Optional',
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: AdminUi.subtle,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AdminUi.border),
                        ),
                        child: SwitchListTile(
                          value: _featured,
                          activeThumbColor: AppColors.primaryBlue,
                          onChanged: (v) => setState(() => _featured = v),
                          title: const Text(
                            'Feature this event',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AdminUi.textPrimary,
                            ),
                          ),
                          subtitle: const Text(
                            'Highlighted at the top of the citizen feed',
                            style: TextStyle(
                              fontSize: 11,
                              color: AdminUi.textMuted,
                            ),
                          ),
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 12),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.red,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1, color: AdminUi.border),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _saving ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AdminUi.textSecondary,
                        side: const BorderSide(color: AdminUi.border),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              _isEdit
                                  ? Icons.save_rounded
                                  : Icons.publish_rounded,
                              size: 18,
                            ),
                      label: Text(_isEdit ? 'Save changes' : 'Publish'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
  }

  Widget _buildImagePicker() {
    final hasImage = _pickedBytes != null ||
        (_imageUrl != null && _imageUrl!.isNotEmpty);
    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        height: 140,
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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

  Widget _buildDatePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Date',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AdminUi.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: _pickDate,
          borderRadius: BorderRadius.circular(AdminUi.controlRadius),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            decoration: BoxDecoration(
              color: AdminUi.surface,
              borderRadius: BorderRadius.circular(AdminUi.controlRadius),
              border: Border.all(color: AdminUi.border),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.calendar_today_rounded,
                  size: 16,
                  color: AdminUi.textMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _date == null ? 'Choose date' : _shortDate(_date),
                    style: TextStyle(
                      fontSize: 13,
                      color: _date == null
                          ? AdminUi.textMuted
                          : AdminUi.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label, {
    String? hint,
    int maxLines = 1,
    bool required = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AdminUi.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: ctrl,
          maxLines: maxLines,
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
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
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

class _GhostButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _GhostButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AdminUi.surface,
      borderRadius: BorderRadius.circular(AdminUi.controlRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AdminUi.controlRadius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AdminUi.controlRadius),
            border: Border.all(color: AdminUi.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: AdminUi.textSecondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AdminUi.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
