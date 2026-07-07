import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/Home/Newsfeed/news_feed_helpers.dart';
import '../providers/admin_users_provider.dart';
import '../theme/admin_ui.dart';
import '../widgets/admin_skeleton.dart';
import '../widgets/admin_snackbar.dart';
import '../widgets/admin_submission_ui.dart' show AdminSearchField, FilterButton;

// ════════════════════════════════════════════════════════════════════════════
//  Admin → Users management page (nav slot "Users")
//
//  Responsive: a wide multi-column card grid + summary tiles on web/desktop, a
//  single column on phones. Tabbed (Citizens / Staff); Citizens can be filtered
//  by verification standing. Every management action opens a responsive modal —
//  a slide-up sheet on small screens, a centred card on web — with dropdown
//  reasons, an optional note + end date, and a "notify user" toggle.
// ════════════════════════════════════════════════════════════════════════════

// Preset reasons — admins pick, they don't type (a free-text note is optional).
const List<String> _kSuspendReasons = [
  'Violation of community guidelines',
  'Abusive or harassing behavior',
  'Spam or repeated misuse',
  'Impersonation or fake account',
  'Security concern',
  'Account under investigation',
  'Other',
];
const List<String> _kRestrictReasons = [
  'Misuse of this feature',
  'Spam or low-quality submissions',
  'Inappropriate or offensive content',
  'Pending review of recent activity',
  'Other',
];
const List<String> _kDeactivateReasons = [
  'Account inactive or dormant',
  'Requested by the user',
  'Duplicate account',
  'Repeated policy violations',
  'Other',
];

enum _UserAction {
  restrict,
  changeRestriction,
  liftRestriction,
  suspend,
  liftSuspension,
  deactivate,
  reactivate,
  message,
}

class AdminUsersPage extends ConsumerStatefulWidget {
  const AdminUsersPage({super.key});
  @override
  ConsumerState<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends ConsumerState<AdminUsersPage> {
  final TextEditingController _search = TextEditingController();

  AdminUsersNotifier get _n => ref.read(adminUsersProvider.notifier);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(adminUsersProvider);
    final notifier = ref.watch(adminUsersProvider.notifier);
    final filters = notifier.filters;

    return LayoutBuilder(
      builder: (context, c) {
        final pad = c.maxWidth < 600 ? 14.0 : 24.0;
        return Container(
          color: AdminUi.pageBg,
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(pad, pad, pad, 0),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _header(notifier),
                        const SizedBox(height: 16),
                        _tabBar(filters.tab, notifier),
                        const SizedBox(height: 12),
                        _toolbar(filters),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => _n.refresh(),
                  color: AppColors.primaryBlue,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1120),
                      child: async.when(
                        loading: () => const _UsersSkeleton(),
                        error: (e, _) => _errorState('$e'),
                        data: (users) => _content(users, filters, notifier, pad),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  String _headerSummary(AdminUsersNotifier n) {
    // Admins and staff are distinct roles — break them out so the count never
    // reads "0 staff" while the Team tab still lists admins.
    final parts = <String>[
      '${n.citizenCount} citizens',
      '${n.adminCount} admin${n.adminCount == 1 ? '' : 's'}',
      '${n.staffCount} staff',
    ];
    if (n.restrictedCount > 0) parts.add('${n.restrictedCount} restricted');
    if (n.suspendedCount > 0) parts.add('${n.suspendedCount} suspended');
    return parts.join(' · ');
  }

  Widget _header(AdminUsersNotifier n) {
    return LayoutBuilder(
      builder: (context, c) {
        final tight = c.maxWidth < 560;
        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Users',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: AdminUi.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _headerSummary(n),
              style: const TextStyle(fontSize: 13, color: AdminUi.textMuted),
            ),
          ],
        );
        final actions = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton.icon(
              onPressed: _openBroadcast,
              icon: const Icon(Icons.campaign_rounded, size: 18),
              label: const Text('Broadcast'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AdminUi.textSecondary,
                side: const BorderSide(color: AdminUi.border),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AdminUi.controlRadius),
                ),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: _openNewStaff,
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
              label: const Text('New staff'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AdminUi.controlRadius),
                ),
              ),
            ),
          ],
        );
        if (tight) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [title, const SizedBox(height: 12), actions],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Expanded(child: title), actions],
        );
      },
    );
  }

  Widget _tabBar(UsersTab tab, AdminUsersNotifier n) {
    Widget seg(String label, UsersTab value) {
      final selected = tab == value;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => n.setTab(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? AppColors.primaryBlue : Colors.transparent,
              borderRadius: BorderRadius.circular(AdminUi.controlRadius),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? Colors.white : AdminUi.textSecondary,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AdminUi.surface,
        borderRadius: BorderRadius.circular(AdminUi.controlRadius + 2),
        border: Border.all(color: AdminUi.border),
      ),
      child: Row(
        children: [
          seg('Citizens', UsersTab.citizens),
          seg('Team', UsersTab.staff),
        ],
      ),
    );
  }

  // Reports-style toolbar: a compact search + a Filters button (verification
  // lives inside it). The Filters button only shows on the Citizens tab.
  Widget _toolbar(UsersFilters filters) {
    return LayoutBuilder(
      builder: (context, c) {
        final searchWidth =
            (c.maxWidth < 480 ? c.maxWidth - 132 : 340.0).clamp(150.0, 380.0);
        return Row(
          children: [
            SizedBox(
              width: searchWidth,
              child: AdminSearchField(
                controller: _search,
                hint: 'Search name, email or barangay…',
                onChanged: _n.setQuery,
                onClear: () {
                  _search.clear();
                  _n.setQuery('');
                },
              ),
            ),
            if (filters.tab == UsersTab.citizens) ...[
              const SizedBox(width: 10),
              FilterButton(
                activeCount: filters.verif != null ? 1 : 0,
                onTap: () => _openVerifFilter(filters.verif),
              ),
            ],
          ],
        );
      },
    );
  }

  void _openVerifFilter(CitizenVerif? current) async {
    final choice = await showAdminModal<_VerifChoice>(
      context,
      _VerifFilterSheet(current: current, n: _n),
    );
    if (choice != null) _n.setVerifFilter(choice.value);
  }

  // ── Content (filters + grid) ──────────────────────────────────────────────
  Widget _content(
    List<ManagedUser> users,
    UsersFilters filters,
    AdminUsersNotifier n,
    double pad,
  ) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 760 ? 2 : 1;
        final gap = 12.0;
        final cardW = cols == 1
            ? c.maxWidth - pad * 2
            : (c.maxWidth - pad * 2 - gap) / 2;
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(pad, 16, pad, pad + 40),
          children: [
            if (filters.tab == UsersTab.citizens && filters.verif != null) ...[
              _activeVerifChip(filters.verif!, n),
              const SizedBox(height: 12),
            ],
            if (users.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 48),
                child: Center(
                  child: Text(
                    'No users match this view.',
                    style: TextStyle(color: AdminUi.textMuted, fontSize: 13),
                  ),
                ),
              )
            else
              Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final u in users)
                    SizedBox(
                      width: cardW,
                      child: _UserCard(user: u, onTap: () => _openActions(u)),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }

  // A single removable chip showing the active verification filter (tap to
  // clear) — not a scattered row of filter chips; the picker is in Filters.
  Widget _activeVerifChip(CitizenVerif v, AdminUsersNotifier n) {
    final (label, color) = switch (v) {
      CitizenVerif.verified => ('Verified', AppColors.green),
      CitizenVerif.pending => ('Pending', AppColors.orange),
      CitizenVerif.unverified => ('Unverified', AppColors.grey),
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => n.setVerifFilter(null),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withValues(alpha: 0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$label · ${_verifCount(v, n)}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(width: 5),
                Icon(Icons.close_rounded, size: 14, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static int _verifCount(CitizenVerif v, AdminUsersNotifier n) => switch (v) {
    CitizenVerif.verified => n.verifiedCount,
    CitizenVerif.pending => n.pendingVerifCount,
    CitizenVerif.unverified => n.unverifiedCount,
  };

  Widget _errorState(String message) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.all(24),
    children: [
      const SizedBox(height: 60),
      const Icon(Icons.cloud_off_rounded, size: 36, color: AdminUi.textMuted),
      const SizedBox(height: 10),
      const Center(
        child: Text(
          "Couldn't load users",
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AdminUi.textPrimary,
          ),
        ),
      ),
      const SizedBox(height: 6),
      Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12.5, color: AdminUi.textMuted),
        ),
      ),
      const SizedBox(height: 14),
      Center(
        child: FilledButton(
          onPressed: () => _n.refresh(),
          style: FilledButton.styleFrom(backgroundColor: AppColors.primaryBlue),
          child: const Text('Retry'),
        ),
      ),
    ],
  );

  // ── Action flow ───────────────────────────────────────────────────────────
  Future<void> _openActions(ManagedUser user) async {
    final selfId = Supabase.instance.client.auth.currentUser?.id;
    final action = await showAdminModal<_UserAction>(
      context,
      _UserActionsSheet(user: user, isSelf: user.id == selfId),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _UserAction.restrict:
      case _UserAction.changeRestriction:
        _openRestrict(user);
      case _UserAction.liftRestriction:
        _run(() => _n.liftRestriction(user), 'Restriction lifted.');
      case _UserAction.suspend:
        _openSuspend(user);
      case _UserAction.liftSuspension:
        _run(() => _n.liftSuspension(user), 'Suspension lifted.');
      case _UserAction.deactivate:
        _openDeactivate(user);
      case _UserAction.reactivate:
        _run(() => _n.setDeactivated(user, false), 'Account reactivated.');
      case _UserAction.message:
        _openMessage(user);
    }
  }

  Future<void> _run(Future<void> Function() action, String ok) async {
    try {
      await action();
      if (mounted) showAdminSnackBar(context, ok, type: AdminSnackType.success);
    } catch (e) {
      if (mounted) showAdminSnackBar(context, '$e', type: AdminSnackType.error);
    }
  }

  void _openRestrict(ManagedUser user) async {
    final r = await showAdminModal<_RestrictResult>(context, _RestrictForm(user: user));
    if (r == null) return;
    await _run(
      () => _n.restrict(
        user,
        features: r.features,
        reason: r.reason,
        expiresAt: r.expiresAt,
        notify: r.notify,
      ),
      'Restriction applied.',
    );
  }

  void _openSuspend(ManagedUser user) async {
    final r = await showAdminModal<_ReasonResult>(context, _SuspendForm(user: user));
    if (r == null) return;
    await _run(
      () => _n.suspend(user, reason: r.reason, expiresAt: r.expiresAt, notify: r.notify),
      'Account suspended.',
    );
  }

  void _openDeactivate(ManagedUser user) async {
    final r = await showAdminModal<_ReasonResult>(context, _DeactivateForm(user: user));
    if (r == null) return;
    await _run(
      () => _n.setDeactivated(user, true,
          reason: r.reason, expiresAt: r.expiresAt, notify: r.notify),
      'Account deactivated.',
    );
  }

  void _openMessage(ManagedUser user) async {
    final r = await showAdminModal<_MessageResult>(
      context,
      _MessageForm(title: 'Message ${user.displayName}', icon: Icons.mail_outline_rounded),
    );
    if (r == null) return;
    await _run(
      () => _n.sendToUser(user, title: r.title, subtitle: r.body),
      'Message sent.',
    );
  }

  void _openBroadcast() async {
    final r = await showAdminModal<_MessageResult>(
      context,
      const _MessageForm(
        title: 'Broadcast to all citizens',
        subtitle: 'This notification reaches every citizen.',
        icon: Icons.campaign_rounded,
        broadcast: true,
      ),
    );
    if (r == null) return;
    try {
      final n = await _n.broadcast(title: r.title, subtitle: r.body);
      if (mounted) {
        showAdminSnackBar(
          context,
          'Broadcast sent to $n citizen${n == 1 ? '' : 's'}.',
          type: AdminSnackType.success,
        );
      }
    } catch (e) {
      if (mounted) showAdminSnackBar(context, '$e', type: AdminSnackType.error);
    }
  }

  void _openNewStaff() async {
    final ok = await showAdminModal<bool>(context, _NewStaffForm(notifier: _n));
    if (ok == true && mounted) {
      showAdminSnackBar(context, 'Staff account created.', type: AdminSnackType.success);
    }
  }
}

// ── User card ────────────────────────────────────────────────────────────────
class _UserCard extends StatelessWidget {
  final ManagedUser user;
  final VoidCallback onTap;
  const _UserCard({required this.user, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AdminUi.surface,
      borderRadius: BorderRadius.circular(AdminUi.cardRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AdminUi.cardRadius),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AdminUi.cardRadius),
            border: Border.all(color: AdminUi.border),
            boxShadow: AdminUi.cardShadow,
          ),
          child: Row(
            children: [
              buildAvatar(46, user.photoUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            user.displayName,
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
                        if (user.isOfficial)
                          _pill(appUserRoleLabel(user.role),
                              user.role == AppUserRole.admin
                                  ? AppColors.primaryBlue
                                  : const Color(0xFF6366F1))
                        else
                          _verifPill(user.verif),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if ((user.email ?? '').isNotEmpty) user.email!,
                        if ((user.barangay ?? '').isNotEmpty) user.barangay!,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AdminUi.textMuted),
                    ),
                    if (_statusChips(user).isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(spacing: 6, runSpacing: 6, children: _statusChips(user)),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AdminUi.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  static List<Widget> _statusChips(ManagedUser u) => [
    if (u.isSuspended) _pill('Suspended', AppColors.red),
    if (u.isRestricted)
      _pill(
        'Restricted: ${u.restrictedFeatures.map(restrictionFeatureLabel).join(', ')}',
        AppColors.orange,
      ),
    if (u.isDeactivated) _pill('Deactivated', AppColors.grey),
  ];

  static Widget _verifPill(CitizenVerif v) {
    final (color, icon) = switch (v) {
      CitizenVerif.verified => (AppColors.green, Icons.verified_rounded),
      CitizenVerif.pending => (AppColors.orange, Icons.hourglass_top_rounded),
      CitizenVerif.unverified => (AppColors.grey, Icons.help_outline_rounded),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(
            citizenVerifLabel(v),
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}

Widget _pill(String text, Color color) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
  decoration: BoxDecoration(
    color: color.withValues(alpha: 0.12),
    borderRadius: BorderRadius.circular(6),
  ),
  child: Text(
    text,
    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color),
  ),
);

// ════════════════════════════════════════════════════════════════════════════
//  Responsive modal system: slide-up sheet on phones, centred card on web.
// ════════════════════════════════════════════════════════════════════════════
Future<T?> showAdminModal<T>(BuildContext context, Widget child) {
  final narrow = MediaQuery.of(context).size.width < 600;
  if (narrow) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: child,
      ),
    );
  }
  return showDialog<T>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (_) => Center(
      child: Padding(padding: const EdgeInsets.all(24), child: child),
    ),
  );
}

/// Shared modal chrome — adapts its shape to phone (bottom sheet, rounded top,
/// drag handle) vs web (centred rounded card). Body scrolls; footer is pinned.
class _ModalCard extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String title;
  final String? subtitle;
  final Widget body;
  final List<Widget> footer;
  const _ModalCard({
    required this.icon,
    required this.accent,
    required this.title,
    this.subtitle,
    required this.body,
    required this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final narrow = size.width < 600;

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (narrow)
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 2),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AdminUi.borderStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 12, 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 20, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w700,
                        color: AdminUi.textPrimary,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: const TextStyle(fontSize: 12.5, color: AdminUi.textMuted),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: AdminUi.textMuted),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: AdminUi.border),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: body,
          ),
        ),
        const Divider(height: 1, color: AdminUi.border),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: footer,
          ),
        ),
      ],
    );

    // Text buttons in these modals (Cancel / Close / Clear / Change) default to
    // the M3 purple; force the brand blue so they read as the app's accent.
    final themedContent = TextButtonTheme(
      data: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.primaryBlue),
      ),
      child: content,
    );

    return Material(
      color: AdminUi.surface,
      borderRadius: narrow
          ? const BorderRadius.vertical(top: Radius.circular(22))
          : BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: narrow
          ? SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: size.height * 0.88),
                child: themedContent,
              ),
            )
          : ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
              child: themedContent,
            ),
    );
  }
}

// ── Action sheet ─────────────────────────────────────────────────────────────
class _UserActionsSheet extends StatelessWidget {
  final ManagedUser user;
  final bool isSelf;
  const _UserActionsSheet({required this.user, required this.isSelf});

  @override
  Widget build(BuildContext context) {
    final isCitizen = user.role == AppUserRole.citizen;
    final canDeactivate = !isSelf && user.role != AppUserRole.admin;

    List<Widget> rows() {
      if (isSelf) {
        return const [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Text(
              "This is your own account — management actions are disabled.",
              style: TextStyle(fontSize: 13, color: AdminUi.textMuted),
            ),
          ),
        ];
      }
      return [
        if (isCitizen) ...[
          if (user.isRestricted) ...[
            _row(context, Icons.tune_rounded, 'Change restriction',
                _UserAction.changeRestriction),
            _row(context, Icons.lock_open_rounded, 'Lift restriction',
                _UserAction.liftRestriction, color: AppColors.green),
          ] else
            _row(context, Icons.block_rounded, 'Restrict features', _UserAction.restrict),
          if (user.isSuspended)
            _row(context, Icons.play_circle_outline_rounded, 'Lift suspension',
                _UserAction.liftSuspension, color: AppColors.green)
          else
            _row(context, Icons.pause_circle_outline_rounded, 'Suspend account',
                _UserAction.suspend, color: AppColors.red),
        ],
        if (canDeactivate)
          user.isDeactivated
              ? _row(context, Icons.person_outline_rounded, 'Reactivate account',
                  _UserAction.reactivate, color: AppColors.green)
              : _row(context, Icons.person_off_rounded, 'Deactivate account',
                  _UserAction.deactivate, color: AppColors.red),
        _row(context, Icons.mail_outline_rounded, 'Send message', _UserAction.message),
      ];
    }

    return _ModalCard(
      icon: user.isOfficial ? Icons.badge_rounded : Icons.person_rounded,
      accent: AppColors.primaryBlue,
      title: user.displayName,
      subtitle: '${appUserRoleLabel(user.role)}'
          '${(user.email ?? '').isNotEmpty ? ' · ${user.email}' : ''}',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows(),
      ),
      footer: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _row(
    BuildContext context,
    IconData icon,
    String label,
    _UserAction action, {
    Color color = AdminUi.textPrimary,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.pop(context, action),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 14),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Result types ─────────────────────────────────────────────────────────────
class _RestrictResult {
  final List<String> features;
  final String? reason;
  final DateTime? expiresAt;
  final bool notify;
  const _RestrictResult(this.features, this.reason, this.expiresAt, this.notify);
}

class _ReasonResult {
  final String? reason;
  final DateTime? expiresAt;
  final bool notify;
  const _ReasonResult(this.reason, this.expiresAt, this.notify);
}

class _MessageResult {
  final String title;
  final String body;
  const _MessageResult(this.title, this.body);
}

/// Wraps the chosen verification filter (null = All) so it survives a modal pop
/// where `null` is itself a valid selection.
class _VerifChoice {
  final CitizenVerif? value;
  const _VerifChoice(this.value);
}

// ── Verification filter sheet (opened by the Filters button) ─────────────────
class _VerifFilterSheet extends StatelessWidget {
  final CitizenVerif? current;
  final AdminUsersNotifier n;
  const _VerifFilterSheet({required this.current, required this.n});

  @override
  Widget build(BuildContext context) {
    Widget opt(String label, int count, CitizenVerif? value, Color color) {
      final selected = current == value;
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.pop(context, _VerifChoice(value)),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 20,
                  color: selected ? color : AdminUi.textMuted,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: AdminUi.textPrimary,
                    ),
                  ),
                ),
                Text(
                  '$count',
                  style: const TextStyle(fontSize: 13, color: AdminUi.textMuted),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return _ModalCard(
      icon: Icons.filter_list_rounded,
      accent: AppColors.primaryBlue,
      title: 'Filter citizens',
      subtitle: 'By verification standing',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          opt('All citizens', n.citizenCount, null, AppColors.primaryBlue),
          opt('Verified', n.verifiedCount, CitizenVerif.verified, AppColors.green),
          opt('Pending', n.pendingVerifCount, CitizenVerif.pending, AppColors.orange),
          opt('Unverified', n.unverifiedCount, CitizenVerif.unverified,
              AppColors.grey),
        ],
      ),
      footer: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

// ── Restrict form ────────────────────────────────────────────────────────────
class _RestrictForm extends StatefulWidget {
  final ManagedUser user;
  const _RestrictForm({required this.user});
  @override
  State<_RestrictForm> createState() => _RestrictFormState();
}

class _RestrictFormState extends State<_RestrictForm> {
  late final Set<String> _features = {...widget.user.restrictedFeatures};
  String _reason = _kRestrictReasons.first;
  final _note = TextEditingController();
  DateTime? _expires;
  bool _notify = true;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ModalCard(
      icon: Icons.block_rounded,
      accent: AppColors.orange,
      title: 'Restrict features',
      subtitle: 'For ${widget.user.displayName}',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _FieldLabel('Blocked features'),
          const SizedBox(height: 6),
          for (final e in kRestrictableFeatures.entries)
            _CheckRow(
              label: e.value,
              value: _features.contains(e.key),
              onChanged: (v) => setState(() {
                v ? _features.add(e.key) : _features.remove(e.key);
              }),
            ),
          const SizedBox(height: 14),
          _ReasonDropdown(
            value: _reason,
            items: _kRestrictReasons,
            onChanged: (v) => setState(() => _reason = v),
          ),
          const SizedBox(height: 12),
          _NoteField(controller: _note, reason: _reason),
          const SizedBox(height: 12),
          _ExpiryTile(value: _expires, onChanged: (d) => setState(() => _expires = d)),
          const SizedBox(height: 6),
          _NotifySwitch(value: _notify, onChanged: (v) => setState(() => _notify = v)),
        ],
      ),
      footer: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        const SizedBox(width: 8),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.primaryBlue),
          onPressed: _features.isEmpty
              ? null
              : () => Navigator.pop(
                    context,
                    _RestrictResult(
                      _features.toList(),
                      _composeReason(_reason, _note.text),
                      _expires,
                      _notify,
                    ),
                  ),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

// ── Suspend form ─────────────────────────────────────────────────────────────
class _SuspendForm extends StatefulWidget {
  final ManagedUser user;
  const _SuspendForm({required this.user});
  @override
  State<_SuspendForm> createState() => _SuspendFormState();
}

class _SuspendFormState extends State<_SuspendForm> {
  String _reason = _kSuspendReasons.first;
  final _note = TextEditingController();
  DateTime? _expires;
  bool _notify = true;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ModalCard(
      icon: Icons.pause_circle_outline_rounded,
      accent: AppColors.red,
      title: 'Suspend account',
      subtitle: 'For ${widget.user.displayName}',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Suspending signs the citizen out and blocks login until lifted. They see a notice with the reason below.',
            style: TextStyle(fontSize: 12.5, color: AdminUi.textMuted),
          ),
          const SizedBox(height: 14),
          _ReasonDropdown(
            value: _reason,
            items: _kSuspendReasons,
            onChanged: (v) => setState(() => _reason = v),
          ),
          const SizedBox(height: 12),
          _NoteField(controller: _note, reason: _reason),
          const SizedBox(height: 12),
          _ExpiryTile(value: _expires, onChanged: (d) => setState(() => _expires = d)),
          const SizedBox(height: 6),
          _NotifySwitch(value: _notify, onChanged: (v) => setState(() => _notify = v)),
        ],
      ),
      footer: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        const SizedBox(width: 8),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.red),
          onPressed: () => Navigator.pop(
            context,
            _ReasonResult(_composeReason(_reason, _note.text), _expires, _notify),
          ),
          child: const Text('Suspend'),
        ),
      ],
    );
  }
}

// ── Deactivate form ──────────────────────────────────────────────────────────
class _DeactivateForm extends StatefulWidget {
  final ManagedUser user;
  const _DeactivateForm({required this.user});
  @override
  State<_DeactivateForm> createState() => _DeactivateFormState();
}

class _DeactivateFormState extends State<_DeactivateForm> {
  String _reason = _kDeactivateReasons.first;
  final _note = TextEditingController();
  DateTime? _expires;
  bool _notify = true;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ModalCard(
      icon: Icons.person_off_rounded,
      accent: AppColors.red,
      title: 'Deactivate account',
      subtitle: 'For ${widget.user.displayName}',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Deactivating disables the account and blocks login. It is reversible — you can reactivate anytime.',
            style: TextStyle(fontSize: 12.5, color: AdminUi.textMuted),
          ),
          const SizedBox(height: 14),
          _ReasonDropdown(
            value: _reason,
            items: _kDeactivateReasons,
            onChanged: (v) => setState(() => _reason = v),
          ),
          const SizedBox(height: 12),
          _NoteField(controller: _note, reason: _reason),
          const SizedBox(height: 12),
          _ExpiryTile(value: _expires, onChanged: (d) => setState(() => _expires = d)),
          const SizedBox(height: 6),
          _NotifySwitch(value: _notify, onChanged: (v) => setState(() => _notify = v)),
        ],
      ),
      footer: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        const SizedBox(width: 8),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.red),
          onPressed: () => Navigator.pop(
            context,
            _ReasonResult(_composeReason(_reason, _note.text), _expires, _notify),
          ),
          child: const Text('Deactivate'),
        ),
      ],
    );
  }
}

// ── Message / broadcast form ─────────────────────────────────────────────────
class _MessageForm extends StatefulWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final bool broadcast;
  const _MessageForm({
    required this.title,
    this.subtitle,
    required this.icon,
    this.broadcast = false,
  });
  @override
  State<_MessageForm> createState() => _MessageFormState();
}

class _MessageFormState extends State<_MessageForm> {
  final _title = TextEditingController();
  final _body = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ModalCard(
      icon: widget.icon,
      accent: AppColors.primaryBlue,
      title: widget.title,
      subtitle: widget.subtitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _FieldLabel('Title'),
          const SizedBox(height: 6),
          _TextInput(controller: _title, hint: 'Short headline'),
          const SizedBox(height: 14),
          const _FieldLabel('Message'),
          const SizedBox(height: 6),
          _TextInput(controller: _body, hint: 'What do you want to say?', maxLines: 4),
        ],
      ),
      footer: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        const SizedBox(width: 8),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.primaryBlue),
          onPressed: () {
            final t = _title.text.trim();
            final b = _body.text.trim();
            if (t.isEmpty || b.isEmpty) return;
            Navigator.pop(context, _MessageResult(t, b));
          },
          child: Text(widget.broadcast ? 'Broadcast' : 'Send'),
        ),
      ],
    );
  }
}

// ── New staff form ───────────────────────────────────────────────────────────
class _NewStaffForm extends StatefulWidget {
  final AdminUsersNotifier notifier;
  const _NewStaffForm({required this.notifier});
  @override
  State<_NewStaffForm> createState() => _NewStaffFormState();
}

class _NewStaffFormState extends State<_NewStaffForm> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final username = _username.text.trim();
    final password = _password.text;
    if (email.isEmpty || username.isEmpty || password.length < 8) {
      setState(() => _error =
          'Email, username and an 8+ character password are required.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.notifier.createStaff(
        email: email,
        password: password,
        username: username,
        fullName: _name.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _ModalCard(
      icon: Icons.person_add_alt_1_rounded,
      accent: AppColors.primaryBlue,
      title: 'New staff account',
      subtitle: 'They can sign in with these credentials',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _FieldLabel('Full name'),
          const SizedBox(height: 6),
          _TextInput(controller: _name, hint: 'e.g. Juan Dela Cruz'),
          const SizedBox(height: 12),
          const _FieldLabel('Email'),
          const SizedBox(height: 6),
          _TextInput(controller: _email, hint: 'name@example.com', keyboard: TextInputType.emailAddress),
          const SizedBox(height: 12),
          const _FieldLabel('Username'),
          const SizedBox(height: 6),
          _TextInput(controller: _username, hint: 'Public handle'),
          const SizedBox(height: 12),
          const _FieldLabel('Temporary password'),
          const SizedBox(height: 6),
          _TextInput(controller: _password, hint: 'At least 8 characters', obscure: true),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(fontSize: 12.5, color: AppColors.red)),
          ],
        ],
      ),
      footer: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.primaryBlue),
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Create'),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Shared styled form widgets
// ════════════════════════════════════════════════════════════════════════════
String? _composeReason(String preset, String note) {
  final n = note.trim();
  if (preset == 'Other') return n.isEmpty ? 'Other' : n;
  return n.isEmpty ? preset : '$preset — $n';
}

OutlineInputBorder _inputBorder(Color color, [double width = 1]) => OutlineInputBorder(
  borderRadius: BorderRadius.circular(AdminUi.controlRadius),
  borderSide: BorderSide(color: color, width: width),
);

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w700,
      color: AdminUi.textSecondary,
    ),
  );
}

class _TextInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final bool obscure;
  final TextInputType? keyboard;
  const _TextInput({
    required this.controller,
    required this.hint,
    this.maxLines = 1,
    this.obscure = false,
    this.keyboard,
  });
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: obscure ? 1 : maxLines,
      obscureText: obscure,
      keyboardType: keyboard,
      style: const TextStyle(fontSize: 14, color: AdminUi.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AdminUi.textMuted, fontSize: 13.5),
        isDense: true,
        filled: true,
        fillColor: AdminUi.subtle,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: _inputBorder(AdminUi.border),
        enabledBorder: _inputBorder(AdminUi.border),
        focusedBorder: _inputBorder(AppColors.primaryBlue, 1.4),
      ),
    );
  }
}

class _NoteField extends StatelessWidget {
  final TextEditingController controller;
  final String reason;
  const _NoteField({required this.controller, required this.reason});
  @override
  Widget build(BuildContext context) {
    final other = reason == 'Other';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(other ? 'Details (required for "Other")' : 'Add a note (optional)'),
        const SizedBox(height: 6),
        _TextInput(
          controller: controller,
          hint: other ? 'Explain the reason…' : 'Extra context for the citizen…',
          maxLines: 2,
        ),
      ],
    );
  }
}

class _ReasonDropdown extends StatelessWidget {
  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;
  const _ReasonDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldLabel('Reason'),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AdminUi.subtle,
            borderRadius: BorderRadius.circular(AdminUi.controlRadius),
            border: Border.all(color: AdminUi.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AdminUi.textMuted),
              borderRadius: BorderRadius.circular(12),
              style: const TextStyle(fontSize: 14, color: AdminUi.textPrimary),
              items: [
                for (final it in items)
                  DropdownMenuItem(value: it, child: Text(it)),
              ],
              onChanged: (v) => v == null ? null : onChanged(v),
            ),
          ),
        ),
      ],
    );
  }
}

class _CheckRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _CheckRow({required this.label, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
                activeColor: AppColors.primaryBlue,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 10),
            Text(label, style: const TextStyle(fontSize: 14, color: AdminUi.textPrimary)),
          ],
        ),
      ),
    );
  }
}

class _ExpiryTile extends StatelessWidget {
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  const _ExpiryTile({required this.value, required this.onChanged});

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: AdminUi.subtle,
        borderRadius: BorderRadius.circular(AdminUi.controlRadius),
        border: Border.all(color: AdminUi.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.event_rounded, size: 18, color: AdminUi.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value == null
                  ? 'No end date (until lifted)'
                  : 'Ends ${value!.day} ${_months[value!.month - 1]} ${value!.year}',
              style: const TextStyle(fontSize: 13, color: AdminUi.textSecondary),
            ),
          ),
          if (value != null)
            TextButton(onPressed: () => onChanged(null), child: const Text('Clear')),
          TextButton(
            onPressed: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: value ?? now.add(const Duration(days: 7)),
                firstDate: now,
                lastDate: now.add(const Duration(days: 730)),
              );
              if (picked != null) onChanged(picked);
            },
            child: Text(value == null ? 'Set date' : 'Change'),
          ),
        ],
      ),
    );
  }
}

class _NotifySwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _NotifySwitch({required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
      dense: true,
      activeColor: AppColors.primaryBlue,
      title: const Text('Notify the user', style: TextStyle(fontSize: 14)),
      subtitle: const Text(
        'Send a notification explaining this action',
        style: TextStyle(fontSize: 11.5, color: AdminUi.textMuted),
      ),
    );
  }
}

// ── Skeleton ─────────────────────────────────────────────────────────────────
class _UsersSkeleton extends StatelessWidget {
  const _UsersSkeleton();
  @override
  Widget build(BuildContext context) {
    return AdminShimmer(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        children: [
          for (int i = 0; i < 7; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AdminUi.surface,
                  borderRadius: BorderRadius.circular(AdminUi.cardRadius),
                  border: Border.all(color: AdminUi.border),
                ),
                child: const Row(
                  children: [
                    SkeletonCircle(size: 46),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox(width: 150, height: 13),
                          SizedBox(height: 8),
                          SkeletonBox(width: 100, height: 11),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
