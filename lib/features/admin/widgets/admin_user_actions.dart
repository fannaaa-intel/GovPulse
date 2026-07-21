import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../staff/data/staff_departments.dart';
import '../providers/admin_users_provider.dart';
import '../theme/admin_ui.dart';
import 'admin_skeleton.dart';
import 'admin_snackbar.dart';
import '../../../core/widgets/app_dialog.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Shared user-management action flows + modal kit
//
//  Extracted from the old single "Users" page so both the Citizen Management
//  page and the Team (staff/admins) page — plus the Community page's Broadcast —
//  reuse the exact same responsive modals, dropdown-reason forms and snackbars.
//
//  Public entry points:
//    • showUserActionsFlow  — open the "•••" action sheet for a user and run it
//    • showNewStaffFlow     — create a staff account
//    • showBroadcastFlow    — broadcast a notification to every citizen
//
//  Every modal is responsive: a slide-up sheet on phones, a centred card on web.
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

// ════════════════════════════════════════════════════════════════════════════
//  Public flows
// ════════════════════════════════════════════════════════════════════════════

/// Opens the action sheet for [user] and runs whatever the admin chooses,
/// surfacing a success/error snackbar. Reused by the Citizen + Team pages.
Future<void> showUserActionsFlow(
  BuildContext context,
  WidgetRef ref,
  ManagedUser user,
) async {
  final n = ref.read(adminUsersProvider.notifier);
  final selfId = Supabase.instance.client.auth.currentUser?.id;
  final action = await showAdminModal<_UserAction>(
    context,
    _UserActionsSheet(user: user, isSelf: user.id == selfId),
  );
  if (action == null || !context.mounted) return;

  switch (action) {
    case _UserAction.restrict:
    case _UserAction.changeRestriction:
      final r = await showAdminModal<_RestrictResult>(
        context,
        _RestrictForm(user: user),
      );
      if (r == null || !context.mounted) return;
      await _run(
        context,
        () => n.restrict(
          user,
          features: r.features,
          reason: r.reason,
          expiresAt: r.expiresAt,
          notify: r.notify,
        ),
        'Restriction applied.',
      );
    case _UserAction.liftRestriction:
      await _run(context, () => n.liftRestriction(user), 'Restriction lifted.');
    case _UserAction.suspend:
      final r = await showAdminModal<_ReasonResult>(
        context,
        _SuspendForm(user: user),
      );
      if (r == null || !context.mounted) return;
      await _run(
        context,
        () => n.suspend(
          user,
          reason: r.reason,
          expiresAt: r.expiresAt,
          notify: r.notify,
        ),
        'Account suspended.',
      );
    case _UserAction.liftSuspension:
      await _run(context, () => n.liftSuspension(user), 'Suspension lifted.');
    case _UserAction.deactivate:
      final r = await showAdminModal<_ReasonResult>(
        context,
        _DeactivateForm(user: user),
      );
      if (r == null || !context.mounted) return;
      await _run(
        context,
        () => n.setDeactivated(
          user,
          true,
          reason: r.reason,
          expiresAt: r.expiresAt,
          notify: r.notify,
        ),
        'Account deactivated.',
      );
    case _UserAction.reactivate:
      await _run(
        context,
        () => n.setDeactivated(user, false),
        'Account reactivated.',
      );
    case _UserAction.message:
      final r = await showAdminModal<_MessageResult>(
        context,
        _MessageForm(
          title: 'Message ${user.displayName}',
          icon: Icons.mail_outline_rounded,
        ),
      );
      if (r == null || !context.mounted) return;
      await _run(
        context,
        () => n.sendToUser(user, title: r.title, subtitle: r.body),
        'Message sent.',
      );
  }
}

/// Opens the "New staff account" form and creates the account.
Future<void> showNewStaffFlow(BuildContext context, WidgetRef ref) async {
  final n = ref.read(adminUsersProvider.notifier);
  final ok = await showAdminModal<bool>(context, _NewStaffForm(notifier: n));
  if (ok == true && context.mounted) {
    showAdminSnackBar(
      context,
      'Staff account created.',
      type: AdminSnackType.success,
    );
  }
}

/// Opens the broadcast composer and fans a notification out to every citizen.
Future<void> showBroadcastFlow(BuildContext context, WidgetRef ref) async {
  final n = ref.read(adminUsersProvider.notifier);
  final r = await showAdminModal<_MessageResult>(
    context,
    const _MessageForm(
      title: 'Broadcast to all citizens',
      subtitle: 'This notification reaches every citizen.',
      icon: Icons.campaign_rounded,
      broadcast: true,
    ),
  );
  if (r == null || !context.mounted) return;
  try {
    final count = await n.broadcast(title: r.title, subtitle: r.body);
    if (context.mounted) {
      showAdminSnackBar(
        context,
        'Broadcast sent to $count citizen${count == 1 ? '' : 's'}.',
        type: AdminSnackType.success,
      );
    }
  } catch (e) {
    if (context.mounted) {
      showAdminSnackBar(context, '$e', type: AdminSnackType.error);
    }
  }
}

Future<void> _run(
  BuildContext context,
  Future<void> Function() action,
  String ok,
) async {
  try {
    await action();
    if (context.mounted) {
      showAdminSnackBar(context, ok, type: AdminSnackType.success);
    }
  } catch (e) {
    if (context.mounted) {
      showAdminSnackBar(context, '$e', type: AdminSnackType.error);
    }
  }
}

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
      // Use the sheet's OWN context (ctx) for viewInsets so the sheet rises with
      // the keyboard — reading the outer context here leaves the input hidden.
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: child,
      ),
    );
  }
  return showAppDialog<T>(
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

  /// Optional header leading widget. When supplied (e.g. a user's profile
  /// avatar) it replaces the default tinted [icon] square.
  final Widget? leading;
  const _ModalCard({
    required this.icon,
    required this.accent,
    required this.title,
    this.subtitle,
    required this.body,
    required this.footer,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final narrow = size.width < 600;
    // Height available above the keyboard — the card is capped to this so its
    // header stays on-screen and its scrolling body reaches the focused input.
    final availableH = size.height - media.viewInsets.bottom;

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
              leading ??
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
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AdminUi.textMuted,
                        ),
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
                constraints: BoxConstraints(maxHeight: availableH * 0.92),
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
            _row(
              context,
              Icons.tune_rounded,
              'Change restriction',
              _UserAction.changeRestriction,
            ),
            _row(
              context,
              Icons.lock_open_rounded,
              'Lift restriction',
              _UserAction.liftRestriction,
              color: AppColors.green,
            ),
          ] else
            _row(
              context,
              Icons.block_rounded,
              'Restrict features',
              _UserAction.restrict,
            ),
          if (user.isSuspended)
            _row(
              context,
              Icons.play_circle_outline_rounded,
              'Lift suspension',
              _UserAction.liftSuspension,
              color: AppColors.green,
            )
          else
            _row(
              context,
              Icons.pause_circle_outline_rounded,
              'Suspend account',
              _UserAction.suspend,
              color: AppColors.red,
            ),
        ],
        if (canDeactivate)
          user.isDeactivated
              ? _row(
                  context,
                  Icons.person_outline_rounded,
                  'Reactivate account',
                  _UserAction.reactivate,
                  color: AppColors.green,
                )
              : _row(
                  context,
                  Icons.person_off_rounded,
                  'Deactivate account',
                  _UserAction.deactivate,
                  color: AppColors.red,
                ),
        _row(
          context,
          Icons.mail_outline_rounded,
          'Send message',
          _UserAction.message,
        ),
      ];
    }

    return _ModalCard(
      icon: user.isOfficial ? Icons.badge_rounded : Icons.person_rounded,
      accent: AppColors.primaryBlue,
      leading: AdminAvatar(size: 42, photoUrl: user.photoUrl),
      // The roster lists staff by department, so this card is where an admin
      // confirms WHO holds that office — keep the person's name as the title.
      title: user.displayName,
      subtitle:
          '${appUserRoleLabel(user.role)}'
          '${(user.department ?? '').isNotEmpty ? ' · ${user.department}' : ''}'
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
  const _RestrictResult(
    this.features,
    this.reason,
    this.expiresAt,
    this.notify,
  );
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
          _ExpiryTile(
            value: _expires,
            onChanged: (d) => setState(() => _expires = d),
          ),
          const SizedBox(height: 6),
          _NotifySwitch(
            value: _notify,
            onChanged: (v) => setState(() => _notify = v),
          ),
        ],
      ),
      footer: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
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
          _ExpiryTile(
            value: _expires,
            onChanged: (d) => setState(() => _expires = d),
          ),
          const SizedBox(height: 6),
          _NotifySwitch(
            value: _notify,
            onChanged: (v) => setState(() => _notify = v),
          ),
        ],
      ),
      footer: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.red),
          onPressed: () => Navigator.pop(
            context,
            _ReasonResult(
              _composeReason(_reason, _note.text),
              _expires,
              _notify,
            ),
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
          _ExpiryTile(
            value: _expires,
            onChanged: (d) => setState(() => _expires = d),
          ),
          const SizedBox(height: 6),
          _NotifySwitch(
            value: _notify,
            onChanged: (v) => setState(() => _notify = v),
          ),
        ],
      ),
      footer: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.red),
          onPressed: () => Navigator.pop(
            context,
            _ReasonResult(
              _composeReason(_reason, _note.text),
              _expires,
              _notify,
            ),
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
          _TextInput(
            controller: _body,
            hint: 'What do you want to say?',
            maxLines: 4,
          ),
        ],
      ),
      footer: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
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
  bool _isExternal = false;
  String _department = StaffDepartments.internal.first.name;
  bool _showPassword = false;
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
      setState(
        () => _error =
            'Email, username and an 8+ character password are required.',
      );
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
        department: _department,
        isExternal: _isExternal,
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
          const _FieldLabel('Staff type'),
          const SizedBox(height: 6),
          _StaffTypeToggle(
            isExternal: _isExternal,
            onChanged: (ext) => setState(() {
              _isExternal = ext;
              // Reset the selection to a valid option for the chosen type.
              _department =
                  (ext ? StaffDepartments.external : StaffDepartments.internal)
                      .first
                      .name;
            }),
          ),
          const SizedBox(height: 12),
          _FieldLabel(_isExternal ? 'Agency' : 'Department / category'),
          const SizedBox(height: 6),
          _DepartmentDropdown(
            isExternal: _isExternal,
            value: _department,
            onChanged: (v) => setState(() => _department = v),
          ),
          const SizedBox(height: 12),
          const _FieldLabel('Email'),
          const SizedBox(height: 6),
          _TextInput(
            controller: _email,
            hint: 'name@example.com',
            keyboard: TextInputType.emailAddress,
          ),
          const SizedBox(height: 12),
          const _FieldLabel('Username'),
          const SizedBox(height: 6),
          _TextInput(controller: _username, hint: 'Public handle'),
          const SizedBox(height: 12),
          const _FieldLabel('Temporary password'),
          const SizedBox(height: 6),
          _TextInput(
            controller: _password,
            hint: 'At least 8 characters',
            obscure: !_showPassword,
            suffix: GestureDetector(
              onTap: () => setState(() => _showPassword = !_showPassword),
              child: Padding(
                padding: const EdgeInsets.all(11),
                child: Image.asset(
                  _showPassword
                      ? 'assets/images/eye.webp'
                      : 'assets/images/closed_eye.webp',
                  height: 18,
                  width: 18,
                ),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(fontSize: 12.5, color: AppColors.red),
            ),
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
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
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

OutlineInputBorder _inputBorder(Color color, [double width = 1]) =>
    OutlineInputBorder(
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

  /// Optional trailing widget (e.g. a password visibility toggle).
  final Widget? suffix;
  const _TextInput({
    required this.controller,
    required this.hint,
    this.maxLines = 1,
    this.obscure = false,
    this.keyboard,
    this.suffix,
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        suffixIcon: suffix,
        suffixIconConstraints: const BoxConstraints(
          minWidth: 40,
          minHeight: 40,
        ),
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
        _FieldLabel(
          other ? 'Details (required for "Other")' : 'Add a note (optional)',
        ),
        const SizedBox(height: 6),
        _TextInput(
          controller: controller,
          hint: other
              ? 'Explain the reason…'
              : 'Extra context for the citizen…',
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
              icon: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: AdminUi.textMuted,
              ),
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

/// Two-way selector letting the admin decide up-front whether they're creating
/// an internal LGU staff member or an external-entity account. The dept/agency
/// list below adapts to this choice.
class _StaffTypeToggle extends StatelessWidget {
  final bool isExternal;
  final ValueChanged<bool> onChanged;
  const _StaffTypeToggle({required this.isExternal, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget seg(String label, IconData icon, bool ext) {
      final selected = isExternal == ext;
      return Expanded(
        child: InkWell(
          onTap: () => onChanged(ext),
          borderRadius: BorderRadius.circular(AdminUi.controlRadius),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.primaryBlue.withValues(alpha: 0.10)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AdminUi.controlRadius),
              border: Border.all(
                color: selected ? AppColors.primaryBlue : AdminUi.border,
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 17,
                  color: selected ? AppColors.primaryBlue : AdminUi.textMuted,
                ),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? AppColors.primaryBlue
                        : AdminUi.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        seg('LGU office', Icons.account_balance_rounded, false),
        const SizedBox(width: 8),
        seg('External entity', Icons.apartment_rounded, true),
      ],
    );
  }
}

class _DepartmentDropdown extends StatelessWidget {
  final bool isExternal;
  final String value;
  final ValueChanged<String> onChanged;
  const _DepartmentDropdown({
    required this.isExternal,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final options = isExternal
        ? StaffDepartments.external
        : StaffDepartments.internal;
    return Container(
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
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: AdminUi.textMuted,
          ),
          borderRadius: BorderRadius.circular(12),
          style: const TextStyle(fontSize: 14, color: AdminUi.textPrimary),
          hint: Text(isExternal ? 'Select agency' : 'Select department'),
          items: [
            for (final d in options)
              DropdownMenuItem(value: d.name, child: Text(d.name)),
          ],
          onChanged: (v) => v == null ? null : onChanged(v),
        ),
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _CheckRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });
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
            Text(
              label,
              style: const TextStyle(fontSize: 14, color: AdminUi.textPrimary),
            ),
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
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
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
              style: const TextStyle(
                fontSize: 13,
                color: AdminUi.textSecondary,
              ),
            ),
          ),
          if (value != null)
            TextButton(
              onPressed: () => onChanged(null),
              child: const Text('Clear'),
            ),
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
