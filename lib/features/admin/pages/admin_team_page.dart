import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
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
        adminShortDate;
import '../widgets/admin_user_actions.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Admin → Team page (nav slot "Team")
//
//  The console's own accounts — admins + staff. Create staff here, and manage
//  each member (message / deactivate / reactivate) via the shared "•••" flow.
//  Citizens live on the separate "Citizen Management" page.
//
//  Responsive: a data table on web/tablet, stacked cards on phones, with a
//  skeleton while the shared users provider loads.
// ════════════════════════════════════════════════════════════════════════════

Color _roleColor(AppUserRole r) => switch (r) {
  AppUserRole.admin => AppColors.primaryBlue,
  AppUserRole.staff => const Color(0xFF6366F1),
  AppUserRole.citizen => AdminUi.textMuted,
};

class AdminTeamPage extends ConsumerStatefulWidget {
  const AdminTeamPage({super.key});
  @override
  ConsumerState<AdminTeamPage> createState() => _AdminTeamPageState();
}

class _AdminTeamPageState extends ConsumerState<AdminTeamPage> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  String _query = '';

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

  List<ManagedUser> _apply(List<ManagedUser> all) {
    final q = _query.trim().toLowerCase();
    final out = all.where((u) {
      if (!u.isOfficial) return false;
      if (q.isEmpty) return true;
      return u.displayName.toLowerCase().contains(q) ||
          (u.username ?? '').toLowerCase().contains(q) ||
          (u.email ?? '').toLowerCase().contains(q);
    }).toList();
    // Admins first, then staff; alphabetical within each role.
    out.sort((a, b) {
      if (a.role != b.role) return a.role.index.compareTo(b.role.index);
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    return out;
  }

  @override
  Widget build(BuildContext context) {
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
              constraints: const BoxConstraints(maxWidth: 1120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Header(notifier: notifier),
                  const SizedBox(height: 14),
                  AdminSearchField(
                    controller: _search,
                    hint: 'Search team by name, email or username…',
                    onChanged: _onSearchChanged,
                    onClear: () {
                      _search.clear();
                      setState(() => _query = '');
                    },
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

// ── Header (title + summary + New staff) ──────────────────────────────────────

class _Header extends ConsumerWidget {
  final AdminUsersNotifier notifier;
  const _Header({required this.notifier});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.of(context).size.width;

    final summary =
        '${notifier.adminCount} admin${notifier.adminCount == 1 ? '' : 's'} · '
        '${notifier.staffCount} staff';

    // The top bar already shows "Team", so no in-content page title.
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          summary,
          style: const TextStyle(fontSize: 13, color: AdminUi.textMuted),
        ),
      ],
    );

    final newStaff = FilledButton.icon(
      onPressed: () => showNewStaffFlow(context, ref),
      icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
      label: const Text('New staff'),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primaryBlue,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AdminUi.controlRadius),
        ),
      ),
    );

    if (width < 480) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          title,
          const SizedBox(height: 12),
          SizedBox(height: 48, child: newStaff),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Expanded(child: title), newStaff],
    );
  }
}

// ── Results ───────────────────────────────────────────────────────────────────

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
          text: "Couldn't load the team.",
          action: TextButton(onPressed: onRetry, child: const Text('Retry')),
        ),
        data: (all) {
          final items = apply(all);
          if (items.isEmpty) {
            return const AdminResultsMessage(
              icon: Icons.badge_outlined,
              color: AdminUi.textMuted,
              text: 'No team members match this view.',
            );
          }
          return LayoutBuilder(
            builder: (context, c) {
              if (c.maxWidth >= 720) {
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

List<Widget> _statusPills(ManagedUser u) => [
      if (u.isSuspended)
        const StatusPill(label: 'Suspended', color: AppColors.red)
      else if (u.isDeactivated)
        const StatusPill(label: 'Deactivated', color: AppColors.grey)
      else
        const StatusPill(label: 'Active', color: AppColors.green),
    ];

class _RolePill extends StatelessWidget {
  final AppUserRole role;
  const _RolePill(this.role);
  @override
  Widget build(BuildContext context) {
    final c = _roleColor(role);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        appUserRoleLabel(role),
        style:
            TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: c),
      ),
    );
  }
}

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
          _HCell('MEMBER', flex: 4),
          _HCell('ROLE', flex: 2),
          _HCell('STATUS', flex: 2),
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
              child: Align(
                alignment: Alignment.centerLeft,
                child: _RolePill(u.role),
              ),
            ),
            Expanded(
              flex: 2,
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: _statusPills(u),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                adminShortDate(u.joinedAt),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 12, color: AdminUi.textSecondary),
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
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  u.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w700,
                                    color: AdminUi.textPrimary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              _RolePill(u.role),
                            ],
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
