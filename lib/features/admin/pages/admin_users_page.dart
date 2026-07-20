import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/Home/Newsfeed/news_feed_helpers.dart';
import '../providers/admin_spam_watch_provider.dart';
import '../providers/admin_users_provider.dart';
import '../theme/admin_ui.dart';
import '../widgets/admin_skeleton.dart';
import '../widgets/admin_submission_ui.dart'
    show
        AdminSearchField,
        AdminResultsCard,
        AdminResultsMessage,
        AdminListSkeleton,
        StatusPill,
        ActiveChip,
        adminShortDate;
import '../widgets/admin_user_actions.dart';
import 'admin_spam_watch_page.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Admin → Citizen Management page (nav slot "Citizens")
//
//  Citizen-only. A row of summary tiles (total / verified / pending / rejected /
//  suspended) sits above a responsive results surface: a data table on
//  web/tablet, a stacked card list on phones. Search + barangay / status / sort
//  dropdowns filter the list; every "•••" opens the shared management modals.
//
//  Staff creation + team management now live on the separate "Team" page, and
//  Broadcast moved to the "Community" page.
// ════════════════════════════════════════════════════════════════════════════

enum _CitizenSort { newest, oldest, nameAz }

String _sortLabel(_CitizenSort s) => switch (s) {
  _CitizenSort.newest => 'Newest',
  _CitizenSort.oldest => 'Oldest',
  _CitizenSort.nameAz => 'Name A–Z',
};

Color _verifColor(CitizenVerif v) => switch (v) {
  CitizenVerif.verified => AppColors.green,
  CitizenVerif.pending => AppColors.orange,
  CitizenVerif.rejected => AppColors.red,
  CitizenVerif.unverified => AppColors.grey,
};

class AdminUsersPage extends ConsumerStatefulWidget {
  const AdminUsersPage({super.key});
  @override
  ConsumerState<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends ConsumerState<AdminUsersPage> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;

  String _query = '';
  String? _barangay; // null = all
  CitizenVerif? _status; // null = all
  _CitizenSort _sort = _CitizenSort.newest;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _query = value);
    });
  }

  // Filter the full account list down to citizens matching the active controls,
  // then sort. Runs client-side over the provider's in-memory list.
  List<ManagedUser> _apply(List<ManagedUser> all) {
    final q = _query.trim().toLowerCase();
    final out = all.where((u) {
      if (u.role != AppUserRole.citizen) return false;
      if (_barangay != null && (u.barangay ?? '') != _barangay) return false;
      if (_status != null && u.verif != _status) return false;
      if (q.isNotEmpty) {
        final hit = u.displayName.toLowerCase().contains(q) ||
            (u.username ?? '').toLowerCase().contains(q) ||
            (u.email ?? '').toLowerCase().contains(q) ||
            (u.barangay ?? '').toLowerCase().contains(q);
        if (!hit) return false;
      }
      return true;
    }).toList();

    int byName(ManagedUser a, ManagedUser b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    switch (_sort) {
      case _CitizenSort.nameAz:
        out.sort(byName);
      case _CitizenSort.newest:
        out.sort((a, b) {
          final ad = a.joinedAt, bd = b.joinedAt;
          if (ad == null && bd == null) return byName(a, b);
          if (ad == null) return 1;
          if (bd == null) return -1;
          return bd.compareTo(ad);
        });
      case _CitizenSort.oldest:
        out.sort((a, b) {
          final ad = a.joinedAt, bd = b.joinedAt;
          if (ad == null && bd == null) return byName(a, b);
          if (ad == null) return 1;
          if (bd == null) return -1;
          return ad.compareTo(bd);
        });
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    // The Spam-watch "Manage user" action seeds a search here; consume it once.
    ref.listen<String>(manageUserQueryProvider, (_, next) {
      if (next.isEmpty) return;
      _search.text = next;
      setState(() => _query = next);
      ref.read(manageUserQueryProvider.notifier).state = '';
    });

    final async = ref.watch(adminUsersProvider);
    final notifier = ref.watch(adminUsersProvider.notifier);
    final width = MediaQuery.of(context).size.width;
    final pad = width < 600 ? 14.0 : 24.0;

    return Container(
      color: AdminUi.pageBg,
      child: RefreshIndicator(
        onRefresh: () => notifier.refresh(),
        color: AppColors.primaryBlue,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(pad, pad, pad, pad + 40),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The top bar already shows "Citizens", so no in-content title.
                  _StatTiles(async: async, notifier: notifier),
                  const SizedBox(height: 16),
                  const _SpamWatchBanner(),
                  _Toolbar(
                    searchCtrl: _search,
                    barangay: _barangay,
                    status: _status,
                    sort: _sort,
                    barangays: notifier.barangays,
                    onSearch: _onSearchChanged,
                    onClearSearch: () {
                      _search.clear();
                      setState(() => _query = '');
                    },
                    onBarangay: (v) => setState(() => _barangay = v),
                    onStatus: (v) => setState(() => _status = v),
                    onSort: (v) => setState(() => _sort = v),
                  ),
                  _ActiveChips(
                    barangay: _barangay,
                    status: _status,
                    sort: _sort,
                    onClearBarangay: () => setState(() => _barangay = null),
                    onClearStatus: () => setState(() => _status = null),
                    onClearSort: () =>
                        setState(() => _sort = _CitizenSort.newest),
                  ),
                  const SizedBox(height: 14),
                  _Results(
                    async: async,
                    apply: _apply,
                    onOpen: (u) => showUserActionsFlow(context, ref, u),
                    onRetry: () => notifier.refresh(),
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

// ── Summary tiles ─────────────────────────────────────────────────────────────

class _StatTiles extends StatelessWidget {
  final AsyncValue<List<ManagedUser>> async;
  final AdminUsersNotifier notifier;
  const _StatTiles({required this.async, required this.notifier});

  @override
  Widget build(BuildContext context) {
    final loading = async.isLoading && async.valueOrNull == null;
    final tiles = <({String label, int value, IconData icon, Color color})>[
      (
        label: 'Total Citizens',
        value: notifier.citizenCount,
        icon: Icons.groups_rounded,
        color: AppColors.primaryBlue
      ),
      (
        label: 'Verified',
        value: notifier.verifiedCount,
        icon: Icons.verified_rounded,
        color: AppColors.green
      ),
      (
        label: 'Pending Verification',
        value: notifier.pendingVerifCount,
        icon: Icons.hourglass_top_rounded,
        color: AppColors.orange
      ),
      (
        label: 'Rejected Verification',
        value: notifier.rejectedVerifCount,
        icon: Icons.gpp_bad_rounded,
        color: AppColors.red
      ),
      (
        label: 'Suspended',
        value: notifier.suspendedCount,
        icon: Icons.pause_circle_rounded,
        color: const Color(0xFF8B5CF6)
      ),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        const gap = 12.0;
        final w = c.maxWidth;
        // Phones/small screens always show a 2-up grid (never a single column);
        // only drop to 1 on an extremely narrow width where two tiles can't fit.
        final perRow = w >= 1080
            ? 5
            : w >= 760
                ? 3
                : w >= 280
                    ? 2
                    : 1;
        final tileW = (w - gap * (perRow - 1)) / perRow;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final t in tiles)
              SizedBox(
                width: tileW,
                child: _StatTile(
                  label: t.label,
                  value: t.value,
                  icon: t.icon,
                  color: t.color,
                  loading: loading,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final bool loading;
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AdminUi.surface,
        borderRadius: BorderRadius.circular(AdminUi.cardRadius),
        border: Border.all(color: AdminUi.border),
        boxShadow: AdminUi.cardShadow,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                loading
                    ? const AdminShimmer(child: SkeletonBox(width: 44, height: 24))
                    : Text(
                        '$value',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          color: AdminUi.textPrimary,
                        ),
                      ),
                const SizedBox(height: 4),
                // Reserve two lines so single-line labels ("Verified") and
                // wrapping ones ("Pending Verification") produce equal-height
                // tiles across the Wrap's rows.
                SizedBox(
                  height: 12 * 1.3 * 2,
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.3,
                      fontWeight: FontWeight.w500,
                      color: AdminUi.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 21, color: color),
          ),
        ],
      ),
    );
  }
}

// ── Spam watch banner ─────────────────────────────────────────────────────────

/// Only appears when spam_detection.sql flags noisy citizens; tapping opens the
/// Spam watch report (ranked offenders across every channel).
class _SpamWatchBanner extends ConsumerWidget {
  const _SpamWatchBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(adminSpamWatchProvider).valueOrNull?.length ?? 0;
    if (count == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppColors.orange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AdminUi.controlRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(AdminUi.controlRadius),
          onTap: () => showSpamWatchReview(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AdminUi.controlRadius),
              border:
                  Border.all(color: AppColors.orange.withValues(alpha: 0.45)),
            ),
            child: Row(
              children: [
                const Icon(Icons.report_gmailerrorred_rounded,
                    size: 18, color: AppColors.orange),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$count user${count == 1 ? '' : 's'} with unusual activity — review spam watch',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFB45309),
                    ),
                  ),
                ),
                const Text('Review',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryBlue)),
                const Icon(Icons.chevron_right_rounded,
                    size: 18, color: AppColors.primaryBlue),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Toolbar ─────────────────────────────────────────────────────────────────

class _Toolbar extends StatelessWidget {
  final TextEditingController searchCtrl;
  final String? barangay;
  final CitizenVerif? status;
  final _CitizenSort sort;
  final List<String> barangays;
  final ValueChanged<String> onSearch;
  final VoidCallback onClearSearch;
  final ValueChanged<String?> onBarangay;
  final ValueChanged<CitizenVerif?> onStatus;
  final ValueChanged<_CitizenSort> onSort;
  const _Toolbar({
    required this.searchCtrl,
    required this.barangay,
    required this.status,
    required this.sort,
    required this.barangays,
    required this.onSearch,
    required this.onClearSearch,
    required this.onBarangay,
    required this.onStatus,
    required this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    final search = AdminSearchField(
      controller: searchCtrl,
      hint: 'Search name, email or barangay…',
      onChanged: onSearch,
      onClear: onClearSearch,
    );

    final barangayPill = _FilterDropdown<String?>(
      icon: Icons.location_city_rounded,
      value: barangay ?? 'All Barangays',
      current: barangay,
      options: [
        (null, 'All Barangays'),
        for (final b in barangays) (b, b),
      ],
      onSelected: onBarangay,
    );
    final statusPill = _FilterDropdown<CitizenVerif?>(
      icon: Icons.filter_alt_rounded,
      value: status == null ? 'All Citizens' : citizenVerifLabel(status!),
      current: status,
      options: [
        (null, 'All Citizens'),
        (CitizenVerif.verified, 'Verified'),
        (CitizenVerif.pending, 'Pending'),
        (CitizenVerif.unverified, 'Unverified'),
        (CitizenVerif.rejected, 'Rejected'),
      ],
      onSelected: onStatus,
    );
    final sortPill = _FilterDropdown<_CitizenSort>(
      prefix: 'Sort by:',
      value: _sortLabel(sort),
      current: sort,
      options: [
        for (final s in _CitizenSort.values) (s, _sortLabel(s)),
      ],
      onSelected: onSort,
    );

    return LayoutBuilder(
      builder: (context, c) {
        // Wide: search on the left, filters grouped, sort pushed to the right —
        // matching the design. Narrow: search stacks above a wrapping pill row.
        if (c.maxWidth >= 720) {
          return Row(
            children: [
              SizedBox(width: 320, child: search),
              const Spacer(),
              barangayPill,
              const SizedBox(width: 10),
              statusPill,
              const SizedBox(width: 10),
              sortPill,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            search,
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [barangayPill, statusPill, sortPill],
            ),
          ],
        );
      },
    );
  }
}

/// A pill-shaped dropdown (label + value + chevron) opening a native popup menu.
/// Works identically on web, desktop and mobile.
class _FilterDropdown<T> extends StatelessWidget {
  final IconData? icon;
  final String? prefix;
  final String value;
  final T current;
  final List<(T, String)> options;
  final ValueChanged<T> onSelected;
  const _FilterDropdown({
    this.icon,
    this.prefix,
    required this.value,
    required this.current,
    required this.options,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    // Carry the option INDEX (never null) as the menu value — PopupMenuButton
    // treats a null-valued selection as a cancel, so a nullable "All" option
    // (value == null) would silently never fire onSelected.
    return PopupMenuButton<int>(
      tooltip: '',
      position: PopupMenuPosition.under,
      onSelected: (i) => onSelected(options[i].$1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      constraints: const BoxConstraints(minWidth: 200, maxHeight: 380),
      itemBuilder: (context) => [
        for (int i = 0; i < options.length; i++)
          PopupMenuItem<int>(
            value: i,
            height: 42,
            child: Row(
              children: [
                Icon(
                  options[i].$1 == current
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 18,
                  color: options[i].$1 == current
                      ? AppColors.primaryBlue
                      : AdminUi.textMuted,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    options[i].$2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: options[i].$1 == current
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: AdminUi.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        height: 42,
        constraints: const BoxConstraints(maxWidth: 220),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AdminUi.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AdminUi.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: AdminUi.textSecondary),
              const SizedBox(width: 7),
            ],
            if (prefix != null) ...[
              Text(
                prefix!,
                style: const TextStyle(fontSize: 13, color: AdminUi.textMuted),
              ),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Text(
                value,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AdminUi.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down_rounded,
                size: 18, color: AdminUi.textMuted),
          ],
        ),
      ),
    );
  }
}

// ── Active chips ──────────────────────────────────────────────────────────────

class _ActiveChips extends StatelessWidget {
  final String? barangay;
  final CitizenVerif? status;
  final _CitizenSort sort;
  final VoidCallback onClearBarangay;
  final VoidCallback onClearStatus;
  final VoidCallback onClearSort;
  const _ActiveChips({
    required this.barangay,
    required this.status,
    required this.sort,
    required this.onClearBarangay,
    required this.onClearStatus,
    required this.onClearSort,
  });

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      if (barangay != null)
        ActiveChip(label: barangay!, onRemove: onClearBarangay),
      if (status != null)
        ActiveChip(
            label: citizenVerifLabel(status!), onRemove: onClearStatus),
      if (sort != _CitizenSort.newest)
        ActiveChip(label: _sortLabel(sort), onRemove: onClearSort),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(spacing: 8, runSpacing: 8, children: chips),
    );
  }
}

// ── Results (table / cards) ───────────────────────────────────────────────────

class _Results extends StatelessWidget {
  final AsyncValue<List<ManagedUser>> async;
  final List<ManagedUser> Function(List<ManagedUser>) apply;
  final void Function(ManagedUser) onOpen;
  final VoidCallback onRetry;
  const _Results({
    required this.async,
    required this.apply,
    required this.onOpen,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return AdminResultsCard(
      child: async.when(
        loading: () => const AdminListSkeleton(),
        error: (e, _) => AdminResultsMessage(
          icon: Icons.cloud_off_rounded,
          color: AppColors.red,
          text: "Couldn't load citizens.",
          action: TextButton(onPressed: onRetry, child: const Text('Retry')),
        ),
        data: (all) {
          final items = apply(all);
          if (items.isEmpty) {
            return const AdminResultsMessage(
              icon: Icons.people_outline_rounded,
              color: AdminUi.textMuted,
              text: 'No citizens match this view.',
            );
          }
          return LayoutBuilder(
            builder: (context, c) {
              if (c.maxWidth >= 760) {
                return Column(
                  children: [
                    const _TableHeader(),
                    for (final u in items)
                      _TableRow(user: u, onOpen: () => onOpen(u)),
                  ],
                );
              }
              return Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    for (final u in items)
                      _Card(user: u, onOpen: () => onOpen(u)),
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

// Verification pill + any enforcement badges (suspended / restricted / off).
List<Widget> _statusPills(ManagedUser u) => [
      StatusPill(
        label: citizenVerifLabel(u.verif),
        color: _verifColor(u.verif),
      ),
      if (u.isSuspended)
        const StatusPill(label: 'Suspended', color: AppColors.red),
      if (u.isRestricted)
        const StatusPill(label: 'Restricted', color: AppColors.orange),
      if (u.isDeactivated)
        const StatusPill(label: 'Deactivated', color: AppColors.grey),
    ];

class _TableHeader extends StatelessWidget {
  const _TableHeader();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: AdminUi.subtle,
        border: Border(bottom: BorderSide(color: AdminUi.border)),
      ),
      child: Row(
        children: const [
          _HCell('CITIZEN', flex: 4),
          _HCell('USERNAME', flex: 2),
          _HCell('BARANGAY', flex: 2),
          _HCell('STATUS', flex: 3),
          _HCell('JOINED', flex: 2),
          SizedBox(width: 44),
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
  final ManagedUser user;
  final VoidCallback onOpen;
  const _TableRow({required this.user, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final u = user;
    return InkWell(
      onTap: onOpen,
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
                  AdminAvatar(size: 38, photoUrl: u.photoUrl),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          u.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: AdminUi.textPrimary,
                          ),
                        ),
                        if ((u.email ?? '').isNotEmpty)
                          Text(
                            u.email!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11.5, color: AdminUi.textMuted),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                (u.username ?? '').isEmpty ? '—' : '@${u.username}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 12.5, color: AdminUi.textSecondary),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                (u.barangay ?? '').isEmpty ? '—' : u.barangay!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, color: AdminUi.textMuted),
              ),
            ),
            Expanded(
              flex: 3,
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: _statusPills(u),
              ),
            ),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    adminShortDate(u.joinedAt),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: AdminUi.textSecondary),
                  ),
                  if (u.joinedAt != null)
                    Text(
                      formatTimeAgo(u.joinedAt!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11, color: AdminUi.textMuted),
                    ),
                ],
              ),
            ),
            SizedBox(
              width: 44,
              child: IconButton(
                tooltip: 'Manage',
                icon: const Icon(Icons.more_horiz_rounded,
                    size: 20, color: AdminUi.textMuted),
                onPressed: onOpen,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final ManagedUser user;
  final VoidCallback onOpen;
  const _Card({required this.user, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final u = user;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AdminUi.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminUi.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AdminAvatar(size: 44, photoUrl: u.photoUrl),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            u.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: AdminUi.textPrimary,
                            ),
                          ),
                          if ((u.email ?? '').isNotEmpty)
                            Text(
                              u.email!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12, color: AdminUi.textMuted),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Manage',
                      icon: const Icon(Icons.more_horiz_rounded,
                          color: AdminUi.textMuted),
                      onPressed: onOpen,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: _statusPills(u)),
                const SizedBox(height: 8),
                Text(
                  [
                    if ((u.username ?? '').isNotEmpty) '@${u.username}',
                    if ((u.barangay ?? '').isNotEmpty) u.barangay!,
                    'Joined ${adminShortDate(u.joinedAt)}',
                  ].join('  ·  '),
                  style:
                      const TextStyle(fontSize: 11.5, color: AdminUi.textMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
