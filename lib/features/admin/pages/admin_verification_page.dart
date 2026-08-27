import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/deeplink_highlight.dart';
import '../theme/admin_ui.dart';
import '../providers/admin_verification_provider.dart';
import '../widgets/report_detail_kit.dart';
import '../widgets/admin_detail_screen.dart';
import '../widgets/admin_skeleton.dart';
import '../widgets/admin_submission_ui.dart';
import '../widgets/admin_snackbar.dart';
import '../../home/screen/notification_popup.dart';
import '../../../core/widgets/app_dialog.dart';

class AdminVerificationPage extends ConsumerStatefulWidget {
  /// A submission id to scroll to and flash once, when arriving from a
  /// notification. Null for a normal open.
  final String? highlightId;
  const AdminVerificationPage({super.key, this.highlightId});

  @override
  ConsumerState<AdminVerificationPage> createState() =>
      _AdminVerificationPageState();
}

class _AdminVerificationPageState extends ConsumerState<AdminVerificationPage>
    with DeepLinkHighlightMixin {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  // Status is filtered on the client (the provider fetches the whole queue),
  // so switching tabs is instant and the header counts stay accurate.
  VerificationStatus? _statusFilter;

  /// The last target we cleared the filter for. Keyed on the id, not a bool —
  /// this page stays mounted when a second notification arrives while it's
  /// already open, so a latch would swallow it.
  String? _revealedFor;

  /// Makes the deep-link target reachable, then flashes it.
  ///
  /// The status filter is client-side and persists, so a target can be filtered
  /// out of view — an admin sitting on "Approved" tapping a *new* (pending)
  /// submission would flash a row that isn't rendered. Clearing the filter is
  /// the point of the tap: they asked to see this one.
  void _flashOnce(List<AdminVerification> all) {
    final id = widget.highlightId;
    if (id == null || id.isEmpty || _revealedFor == id) return;

    AdminVerification? target;
    for (final v in all) {
      if (v.id == id) {
        target = v;
        break;
      }
    }
    if (target == null) return; // not loaded yet — retry on the next build
    _revealedFor = id;

    final hidden = _statusFilter != null && _statusFilter != target.status;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (hidden) setState(() => _statusFilter = null);
      flashHighlightOnce(id);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(adminVerificationProvider.notifier).setQuery(value);
    });
  }

  Future<void> _openDetail(AdminVerification v) async {
    await showAdminDetail(
      context,
      builder: (_) => _VerificationDetailDialog(verification: v),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(adminVerificationProvider);
    final filters = ref.read(adminVerificationProvider.notifier).filters;
    final pad = MediaQuery.of(context).size.width < 600 ? 16.0 : 24.0;

    // Counts drive the stat cards; derived from whatever the search matched.
    final all = async.valueOrNull ?? const <AdminVerification>[];
    final loading = async.isLoading && async.valueOrNull == null;

    // Rows exist only once the fetch resolves — flash the deep-link target then.
    if (async.hasValue) _flashOnce(all);

    final visible = _statusFilter == null
        ? all
        : all.where((v) => v.status == _statusFilter).toList();

    return RefreshIndicator(
      onRefresh: () => ref.read(adminVerificationProvider.notifier).refresh(),
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
                _buildToolbar(filters),
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
  // The top bar already shows "Verification"; pull-to-refresh replaces the old
  // Refresh button, so the header is just the descriptive subtitle.
  Widget _buildHeader() {
    return const Align(
      alignment: Alignment.centerLeft,
      child: Text(
        'Review resident identity submissions and approve access',
        style: TextStyle(fontSize: 13, color: AdminUi.textMuted),
      ),
    );
  }

  // ── Stat cards (double as the status filter) ────────────────────────────────
  Widget _buildStatRow(List<AdminVerification> all, bool loading) {
    int countOf(VerificationStatus s) =>
        all.where((v) => v.status == s).length;

    final cards = <Widget>[
      _StatCard(
        label: 'All submissions',
        icon: Icons.inbox_rounded,
        accent: AppColors.primaryBlue,
        value: loading ? null : all.length,
        selected: _statusFilter == null,
        onTap: () => setState(() => _statusFilter = null),
      ),
      _StatCard(
        label: 'Pending',
        icon: Icons.hourglass_top_rounded,
        accent: AppColors.orange,
        value: loading ? null : countOf(VerificationStatus.pending),
        selected: _statusFilter == VerificationStatus.pending,
        onTap: () => setState(() => _statusFilter = VerificationStatus.pending),
      ),
      _StatCard(
        label: 'Approved',
        icon: Icons.verified_user_rounded,
        accent: AppColors.green,
        value: loading ? null : countOf(VerificationStatus.approved),
        selected: _statusFilter == VerificationStatus.approved,
        onTap: () =>
            setState(() => _statusFilter = VerificationStatus.approved),
      ),
      _StatCard(
        label: 'Rejected',
        icon: Icons.cancel_rounded,
        accent: AppColors.red,
        value: loading ? null : countOf(VerificationStatus.rejected),
        selected: _statusFilter == VerificationStatus.rejected,
        onTap: () =>
            setState(() => _statusFilter = VerificationStatus.rejected),
      ),
    ];

    // Four across on laptop/desktop where there's room; 2×2 everywhere smaller
    // (phone, tablet, and the app's own narrower shell) — never a single column.
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

  // ── Toolbar: search + sort ──────────────────────────────────────────────────
  Widget _buildToolbar(VerificationFilters filters) {
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
              hintText: 'Search name, ID number, barangay…',
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
                        ref
                            .read(adminVerificationProvider.notifier)
                            .setQuery('');
                        setState(() {});
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
            child: DropdownButton<VerificationSort>(
              value: filters.sort,
              isDense: true,
              icon: const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: AdminUi.textMuted,
              ),
              borderRadius: BorderRadius.circular(AdminUi.controlRadius),
              items: const [
                DropdownMenuItem(
                  value: VerificationSort.newest,
                  child: Text('Newest first', style: _ddStyle),
                ),
                DropdownMenuItem(
                  value: VerificationSort.oldest,
                  child: Text('Oldest first', style: _ddStyle),
                ),
              ],
              onChanged: (s) {
                if (s != null) {
                  ref.read(adminVerificationProvider.notifier).setSort(s);
                }
              },
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
    AsyncValue<List<AdminVerification>> async,
    List<AdminVerification> visible,
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
                _RowSkeleton(),
              ],
            ),
          ),
        ),
        error: (e, _) => _ResultsMessage(
          icon: Icons.cloud_off_rounded,
          color: AppColors.red,
          text: 'Couldn\'t load submissions.',
          action: TextButton(
            onPressed: () =>
                ref.read(adminVerificationProvider.notifier).refresh(),
            child: const Text('Retry'),
          ),
        ),
        data: (_) {
          if (visible.isEmpty) {
            return _ResultsMessage(
              icon: Icons.inbox_rounded,
              color: AdminUi.textMuted,
              text: _statusFilter == null
                  ? 'No submissions match your search.'
                  : 'No ${verificationStatusLabel(_statusFilter!).toLowerCase()} submissions.',
            );
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 760;
              if (wide) {
                return Column(
                  children: [
                    const _TableHeader(),
                    for (final v in visible)
                      _TableRow(
                        key: highlightKey(v.id),
                        verification: v,
                        onTap: () => _openDetail(v),
                        highlighted: isHighlighted(v.id),
                      ),
                  ],
                );
              }
              return Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    for (final v in visible)
                      _VerificationCard(
                        key: highlightKey(v.id),
                        verification: v,
                        onTap: () => _openDetail(v),
                        highlighted: isHighlighted(v.id),
                      ),
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

// ── Status visuals ─────────────────────────────────────────────────────────

Color _statusColor(VerificationStatus s) {
  switch (s) {
    case VerificationStatus.pending:
      return AppColors.orange;
    case VerificationStatus.approved:
      return AppColors.green;
    case VerificationStatus.rejected:
      return AppColors.red;
  }
}

IconData _statusIcon(VerificationStatus s) {
  switch (s) {
    case VerificationStatus.pending:
      return Icons.hourglass_top_rounded;
    case VerificationStatus.approved:
      return Icons.check_circle_rounded;
    case VerificationStatus.rejected:
      return Icons.cancel_rounded;
  }
}

class _StatusPill extends StatelessWidget {
  final VerificationStatus status;
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
            verificationStatusLabel(status),
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

/// Circular monogram from the applicant's name — gives each row a face.
class _Avatar extends StatelessWidget {
  final String name;
  final double size;
  const _Avatar({required this.name, this.size = 34});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withValues(alpha: 0.10),
        shape: BoxShape.circle,
      ),
      child: Text(
        _initials(name),
        style: TextStyle(
          fontSize: size * 0.36,
          fontWeight: FontWeight.w700,
          color: AppColors.primaryBlue,
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }
}

// ── Stat card ──────────────────────────────────────────────────────────────

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

// ── Wide table ───────────────────────────────────────────────────────────────

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
          _HCell('APPLICANT', flex: 3),
          _HCell('ID TYPE', flex: 3),
          _HCell('BARANGAY', flex: 2),
          _HCell('STATUS', flex: 2),
          _HCell('SUBMITTED', flex: 2),
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
  final AdminVerification verification;
  final VoidCallback onTap;

  /// Set when this row is the deep-link target: it flashes, then fades back.
  final bool highlighted;
  const _TableRow({
    super.key,
    required this.verification,
    required this.onTap,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: kHighlightFade,
          decoration: highlighted
              ? highlightRowDecoration(
                  accent: AppColors.primaryBlue,
                  divider: const BorderSide(color: AdminUi.border),
                )
              : const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AdminUi.border)),
                ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    _Avatar(name: verification.fullName),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            verification.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AdminUi.textPrimary,
                            ),
                          ),
                          Text(
                            verification.idNumber.isEmpty
                                ? '—'
                                : verification.idNumber,
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
                flex: 3,
                child: Text(
                  verification.selectedIdType.isEmpty
                      ? '—'
                      : verification.selectedIdType,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AdminUi.textSecondary,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  verification.barangay.isEmpty ? '—' : verification.barangay,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AdminUi.textSecondary,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _StatusPill(verification.status),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  _shortDate(verification.createdAt),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AdminUi.textMuted,
                  ),
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

// ── Narrow card ──────────────────────────────────────────────────────────────

class _VerificationCard extends StatelessWidget {
  final AdminVerification verification;
  final VoidCallback onTap;

  /// Set when this card is the deep-link target: it flashes, then fades back.
  /// Drawn as a ring so the card keeps its own surface + border.
  final bool highlighted;
  const _VerificationCard({
    super.key,
    required this.verification,
    required this.onTap,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: highlightRing(
        highlighted: highlighted,
        radius: AdminUi.controlRadius,
        accent: AppColors.primaryBlue,
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
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _Avatar(name: verification.fullName, size: 30),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        verification.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AdminUi.textPrimary,
                        ),
                      ),
                    ),
                    _StatusPill(verification.status),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  [
                    if (verification.selectedIdType.isNotEmpty)
                      verification.selectedIdType,
                    if (verification.barangay.isNotEmpty) verification.barangay,
                    _shortDate(verification.createdAt),
                  ].join('  ·  '),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AdminUi.textMuted,
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
}

// ── Detail dialog ────────────────────────────────────────────────────────────

class _VerificationDetailDialog extends ConsumerStatefulWidget {
  final AdminVerification verification;
  const _VerificationDetailDialog({required this.verification});

  @override
  ConsumerState<_VerificationDetailDialog> createState() =>
      _VerificationDetailDialogState();
}

class _VerificationDetailDialogState
    extends ConsumerState<_VerificationDetailDialog> {
  bool _busy = false;

  /// Which PANE is showing when the layout is too narrow to seat both side by
  /// side: 0 = Verification Status, 1 = Applicant Details. Status leads here,
  /// unlike the other consoles — the ID photos are what you came to look at.
  int _paneTab = 0;

  Future<void> _approve() async {
    final notesCtrl = TextEditingController();
    final confirmed = await _confirm(
      title: 'Approve verification?',
      message:
          '${widget.verification.fullName} will be marked as a verified resident.',
      confirmLabel: 'Approve',
      confirmColor: AppColors.green,
      extra: TextField(
        controller: notesCtrl,
        maxLines: 3,
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Note (optional, saved with the review)',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AdminUi.border),
          ),
        ),
      ),
    );
    // Dispose the dialog's controller on EVERY exit path, including the cancel
    // one below — it is created per invocation and was previously leaked on all
    // of them. Read `.text` out first: the controller must outlive the dialog
    // (the notes are read after it closes) but not this method.
    if (confirmed != true) {
      notesCtrl.dispose();
      return;
    }
    final notes = notesCtrl.text;
    notesCtrl.dispose();

    setState(() => _busy = true);
    try {
      await ref
          .read(adminVerificationProvider.notifier)
          .approve(
            widget.verification.id,
            userId: widget.verification.userId,
            notes: notes,
          );
      if (!mounted) return;
      Navigator.pop(context);
      showAdminSnackBar(
        context,
        '${widget.verification.fullName} approved.',
        type: AdminSnackType.success,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAdminSnackBar(
        context,
        'Failed to approve: $e',
        type: AdminSnackType.error,
      );
    }
  }

  Future<void> _reject() async {
    final notesCtrl = TextEditingController();
    final confirmed = await _confirm(
      title: 'Reject verification?',
      message:
          '${widget.verification.fullName} will be notified their submission was rejected.',
      confirmLabel: 'Reject',
      confirmColor: AppColors.red,
      extra: TextField(
        controller: notesCtrl,
        maxLines: 3,
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Reason (optional, shown to the applicant)',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AdminUi.border),
          ),
        ),
      ),
    );
    // Same per-invocation controller disposal as _approve(); see the note there.
    if (confirmed != true) {
      notesCtrl.dispose();
      return;
    }
    final notes = notesCtrl.text;
    notesCtrl.dispose();

    setState(() => _busy = true);
    try {
      await ref
          .read(adminVerificationProvider.notifier)
          .reject(widget.verification.id, notes: notes);

      // Deliver the reason to the applicant as an in-app notification. Fail-soft:
      // the rejection is already saved, and adminSend swallows its own errors,
      // so a notification hiccup never turns into a failed rejection.
      final reason = notes.trim();
      await NotificationService.adminSend(
        targetUserId: widget.verification.userId,
        title: 'ID verification not approved',
        subtitle: reason.isEmpty
            ? 'We were unable to approve your ID verification. Please review '
                  'your details and submit again.'
            : reason,
        icon: Icons.gpp_bad_rounded,
        color: AppColors.red,
      );

      if (!mounted) return;
      Navigator.pop(context);
      showAdminSnackBar(
        context,
        '${widget.verification.fullName} rejected.',
        type: AdminSnackType.success,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAdminSnackBar(
        context,
        'Failed to reject: $e',
        type: AdminSnackType.error,
      );
    }
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    required Color confirmColor,
    Widget? extra,
  }) {
    return showAppDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            if (extra != null) ...[const SizedBox(height: 12), extra],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmColor,
              foregroundColor: Colors.white,
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  /// Left pane — where this submission stands, and the evidence you judge it
  /// on. The ID photos live here rather than in the details pane: this is the
  /// wider column, and they're the thing an admin actually has to look at
  /// before deciding.
  ///
  /// Deliberately NOT the report's stepper: a verification has no stages to
  /// walk through. It's waiting on a reviewer, or it's been decided.
  Widget _statusPane() {
    final v = widget.verification;
    final decided = v.status != VerificationStatus.pending;
    final accent = _statusColor(v.status);

    final String headline;
    final String blurb;
    switch (v.status) {
      case VerificationStatus.pending:
        headline = 'This submission is awaiting review.';
        blurb = 'Check the ID documents against the applicant\'s details, then '
            'approve or reject. The applicant is notified either way.';
        break;
      case VerificationStatus.approved:
        headline = 'This applicant is a verified resident.';
        blurb = 'The ID was accepted and the citizen is marked verified across '
            'the app.';
        break;
      case VerificationStatus.rejected:
        headline = 'This submission was rejected.';
        blurb = 'The applicant was notified and can submit again with corrected '
            'details.';
        break;
    }

    return _Pane(
      title: 'Verification Status',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusCard(
            chip: _statusLabel(v.status),
            headline: headline,
            blurb: blurb,
            accent: accent,
            facts: [
              (label: 'Submitted on', value: _shortDate(v.createdAt)),
              if (decided)
                (label: 'Reviewed on', value: _shortDate(v.reviewedAt))
              else
                (label: 'ID type', value: v.selectedIdType),
            ],
          ),
          const SizedBox(height: 18),
          _IconSection(
            icon: Icons.badge_rounded,
            title: 'Submitted Documents',
            isLast: !decided,
            child: LayoutBuilder(
              builder: (context, c) {
                const docs = [
                  ('ID front', 0),
                  ('ID back', 1),
                  ('Selfie', 2),
                ];
                Widget thumbFor(int i) => _DocThumb(
                  label: docs[i].$1,
                  path: switch (i) {
                    0 => v.idFrontPath,
                    1 => v.idBackPath,
                    _ => v.facePhotoPath,
                  },
                );
                // Three across whenever each still gets a readable ~140px;
                // below that they stack so an ID stays legible instead of
                // shrinking into a stamp.
                if (c.maxWidth < 420) {
                  return Column(
                    children: [
                      for (var i = 0; i < 3; i++) ...[
                        if (i > 0) const SizedBox(height: 12),
                        thumbFor(i),
                      ],
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < 3; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(child: thumbFor(i)),
                    ],
                  ],
                );
              },
            ),
          ),
          if (decided)
            _IconSection(
              icon: Icons.sticky_note_2_rounded,
              title: 'Review Notes',
              isLast: true,
              child: Text(
                v.reviewerNotes?.isNotEmpty == true ? v.reviewerNotes! : '—',
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: AdminUi.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Right pane — who the applicant says they are, and the decision buttons.
  /// Mirrors the report details pane, including its Action block at the foot.
  Widget _detailsPane() {
    final v = widget.verification;
    return _Pane(
      title: 'Verification Details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Avatar(name: v.fullName, size: 72),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DetailKvRow(
                      label: 'Status',
                      trailing: _StatusPill(v.status),
                    ),
                    DetailKvRow(label: 'Applicant', value: v.fullName),
                    DetailKvRow(label: 'ID', value: '#IDV-${_shortIdOf(v.id)}'),
                    DetailKvRow(
                      label: 'Date Submitted',
                      value: _shortDate(v.createdAt),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(height: 1, color: AdminUi.border),
          const SizedBox(height: 18),
          _IconSection(
            icon: Icons.badge_rounded,
            title: 'Identification',
            child: _infoCard([
              _InfoTile(
                icon: Icons.badge_rounded,
                label: 'ID type',
                value: v.selectedIdType,
              ),
              _InfoTile(
                icon: Icons.pin_rounded,
                label: 'ID number',
                value: v.idNumber,
              ),
            ]),
          ),
          _IconSection(
            icon: Icons.person_rounded,
            title: 'Personal',
            child: _infoCard([
              _InfoTile(
                icon: Icons.wc_rounded,
                label: 'Gender',
                value: v.gender ?? '—',
              ),
              _InfoTile(
                icon: Icons.cake_rounded,
                label: 'Birthdate',
                value: v.birthdate,
              ),
              _InfoTile(
                icon: Icons.public_rounded,
                label: 'Birthplace',
                value: v.birthplace,
              ),
              _InfoTile(
                icon: Icons.favorite_rounded,
                label: 'Civil status',
                value: v.civilStatus,
              ),
            ]),
          ),
          _IconSection(
            icon: Icons.location_on_rounded,
            title: 'Contact & address',
            child: _infoCard([
              _InfoTile(
                icon: Icons.phone_rounded,
                label: 'Contact number',
                value: v.contactNumber,
              ),
              _InfoTile(
                icon: Icons.location_city_rounded,
                label: 'Barangay',
                value: v.barangay,
              ),
              _InfoTile(
                icon: Icons.signpost_rounded,
                label: 'Street',
                value: v.street,
              ),
            ]),
          ),
          _IconSection(
            icon: Icons.schedule_rounded,
            title: 'Timeline',
            isLast: true,
            child: _infoCard([
              _InfoTile(
                icon: Icons.event_rounded,
                label: 'Submitted',
                value: _shortDate(v.createdAt),
              ),
              if (v.status != VerificationStatus.pending)
                _InfoTile(
                  icon: Icons.event_available_rounded,
                  label: 'Reviewed',
                  value: _shortDate(v.reviewedAt),
                ),
            ]),
          ),
          // Only a submission still on the desk can be decided; a reviewed one
          // shows its outcome in the status pane instead of live buttons.
          if (v.status == VerificationStatus.pending) ...[
            const SizedBox(height: 18),
            const Divider(height: 1, color: AdminUi.border),
            const SizedBox(height: 16),
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
                final approve = _ActionButton(
                  label: 'Approve',
                  icon: Icons.check_rounded,
                  color: AppColors.green,
                  busy: _busy,
                  onTap: _busy ? null : _approve,
                );
                final reject = _ActionButton(
                  label: 'Reject',
                  icon: Icons.close_rounded,
                  color: AppColors.red,
                  outlined: true,
                  onTap: _busy ? null : _reject,
                );
                // Side by side needs room for both labels; below that they
                // stack rather than ellipsing into "Appr…".
                if (c.maxWidth < 300) {
                  return Column(
                    children: [approve, const SizedBox(height: 10), reject],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: approve),
                    const SizedBox(width: 10),
                    Expanded(child: reject),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final narrow = adminDetailIsNarrow(context);

    // One pane at a time on a phone, or in a dialog too narrow for two columns.
    // Status leads here (unlike the other consoles): the ID photos are what the
    // admin opened this to look at.
    Widget paneTabs() => AdminSegmentedTabs(
      labels: const ['Verification Status', 'Applicant Details'],
      selected: _paneTab,
      onSelect: (i) => setState(() => _paneTab = i),
    );

    Widget activePane() => SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: _paneTab == 0 ? _statusPane() : _detailsPane(),
    );

    // Narrow → full-screen page: the chevron header is PINNED, only the body
    // below slides up (mirroring the citizen sub-screens).
    if (narrow) {
      return Scaffold(
        backgroundColor: AdminUi.pageBg,
        body: SafeArea(
          child: Column(
            children: [
              const AdminChevronHeader(title: 'ID verification'),
              const Divider(height: 1, color: AdminUi.border),
              Expanded(
                child: AdminSlideUp(
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
              ),
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
  Widget _infoCard(List<Widget> tiles) {
    return Container(
      decoration: BoxDecoration(
        color: AdminUi.subtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminUi.border),
      ),
      padding: const EdgeInsets.all(4),
      child: LayoutBuilder(
        builder: (context, c) {
          // Two columns when there's room, a single column when the dialog is
          // narrow (phones) — keeps every value readable.
          final twoCol = c.maxWidth >= 440;
          final itemWidth = twoCol ? c.maxWidth / 2 : c.maxWidth;
          return Wrap(
            children: [
              for (final t in tiles) SizedBox(width: itemWidth, child: t),
            ],
          );
        },
      ),
    );
  }

}

/// Width at which the detail splits into two columns. Matches the reports,
/// suggestions and feedback consoles so every detail breaks at the same point.
const double _kTwoPaneFrom = 900;

/// Short, human-readable handle for a submission — the id has no server-side
/// short form, so the first block of the uuid stands in.
String _shortIdOf(String id) {
  final clean = id.replaceAll('-', '');
  return (clean.length >= 8 ? clean.substring(0, 8) : clean).toUpperCase();
}

String _statusLabel(VerificationStatus s) {
  switch (s) {
    case VerificationStatus.pending:
      return 'Awaiting review';
    case VerificationStatus.approved:
      return 'Approved';
    case VerificationStatus.rejected:
      return 'Rejected';
  }
}

/// Test hook for the status card that heads the detail's left pane — the piece
/// with the width-dependent illustration and fact strip.
Widget verificationStatusCardForTesting({
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

/// A titled white card — one of the two panes of the verification detail.
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

/// The status headline card at the top of the left pane — the verification's
/// equivalent of the report's stage card, illustrated with the verified mark.
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
                    'assets/images/verification/verified.webp',
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
/// Side by side when there's room, stacked when there isn't, so a long ID type
/// or date never gets clipped.
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
/// An icon + heading with its content indented beneath — the repeating unit of
/// both panes (Documents, Identification, Personal, Contact, Timeline).
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

// ── Detail: info tiles ───────────────────────────────────────────────────────

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
    final shown = value.trim().isEmpty ? '—' : value;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AdminUi.surface,
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
                const SizedBox(height: 2),
                Text(
                  shown,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AdminUi.textPrimary,
                    height: 1.25,
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

class _DocThumb extends ConsumerWidget {
  final String label;
  final String? path;
  const _DocThumb({required this.label, required this.path});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AdminUi.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              decoration: BoxDecoration(
                color: AdminUi.subtle,
                border: Border.all(color: AdminUi.border),
                borderRadius: BorderRadius.circular(10),
              ),
              child: path == null
                  ? const Icon(
                      Icons.image_not_supported_rounded,
                      color: AdminUi.textMuted,
                      size: 20,
                    )
                  : FutureBuilder<String?>(
                      future: ref
                          .read(adminVerificationProvider.notifier)
                          .signedUrl(path),
                      builder: (context, snap) {
                        if (snap.connectionState != ConnectionState.done) {
                          // Shimmer, not a spinner: the box is already the
                          // document's final size, so the placeholder reads as
                          // the ID arriving rather than as a control in a hole.
                          return const AdminShimmer(
                            child: ColoredBox(
                              color: kSkeletonBase,
                              child: SizedBox.expand(),
                            ),
                          );
                        }
                        final url = snap.data;
                        if (url == null) {
                          return const Icon(
                            Icons.broken_image_rounded,
                            color: AdminUi.textMuted,
                            size: 20,
                          );
                        }
                        return InkWell(
                          onTap: () => _openFullscreen(context, url),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              // Cached: the provider hands back a stable signed
                              // URL per path, so flipping between submissions
                              // doesn't re-download an ID it already has.
                              SkeletonNetworkImage(
                                url: url,
                                fit: BoxFit.cover,
                                errorChild: const ColoredBox(
                                  color: AdminUi.subtle,
                                  child: Icon(
                                    Icons.broken_image_rounded,
                                    color: AdminUi.textMuted,
                                    size: 20,
                                  ),
                                ),
                              ),
                              Positioned(
                                right: 6,
                                bottom: 6,
                                child: Container(
                                  padding: const EdgeInsets.all(5),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.45),
                                    borderRadius: BorderRadius.circular(7),
                                  ),
                                  child: const Icon(
                                    Icons.zoom_in_rounded,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
        ),
      ],
    );
  }

  void _openFullscreen(BuildContext context, String url) {
    showAppDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: InteractiveViewer(
          // Cached: the thumb already warmed this URL, so zooming an ID shows
          // it instead of re-fetching.
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.contain,
            placeholder: (_, _) =>
                const Center(child: CircularProgressIndicator(color: Colors.white)),
            errorWidget: (_, _, _) => const Icon(
              Icons.broken_image_rounded,
              color: Colors.white54,
              size: 40,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Shared bits ──────────────────────────────────────────────────────────────

const TextStyle _ddStyle =
    TextStyle(fontSize: 13, color: AdminUi.textPrimary);

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
          SkeletonCircle(size: 34),
          SizedBox(width: 12),
          Expanded(flex: 3, child: _Bar(width: 100)),
          Expanded(flex: 3, child: _Bar(width: 90)),
          Expanded(flex: 2, child: _Bar(width: 70)),
          Expanded(flex: 2, child: _Bar(width: 70)),
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

String _shortDate(DateTime? t) {
  if (t == null) return '—';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[t.month - 1]} ${t.day}, ${t.year}';
}
