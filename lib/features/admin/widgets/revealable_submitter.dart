import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/admin_identity_reveal_provider.dart';
import '../providers/admin_profile_provider.dart';
import '../theme/admin_ui.dart';
import 'admin_snackbar.dart';
import 'admin_submission_ui.dart';
import '../../../core/widgets/app_dialog.dart';

// ════════════════════════════════════════════════════════════════════════════
//  RevealableSubmitter — SubmitterBlock + guarded de-anonymization
//
//  Drop-in replacement for SubmitterBlock on the Reports / Suggestions /
//  Feedback detail screens. For a NAMED submission it renders exactly like
//  SubmitterBlock. For an ANONYMOUS one it shows the protected-identity block
//  and, ONLY to a full admin (role 1), a "Reveal" affordance that runs the
//  guarded flow (password re-auth + reason → audited RPC). The revealed identity
//  lives in ephemeral state only — leaving/reopening the detail hides it again,
//  so every viewing is a fresh, logged action.
// ════════════════════════════════════════════════════════════════════════════

class RevealableSubmitter extends ConsumerStatefulWidget {
  final RevealSource source;
  final String submissionId;
  final bool isAnonymous;
  final String? name;
  final String? photoUrl;
  final String? role;

  /// Word for the person, used in the reveal button ("Reveal reporter identity").
  final String subject;

  const RevealableSubmitter({
    super.key,
    required this.source,
    required this.submissionId,
    required this.isAnonymous,
    this.name,
    this.photoUrl,
    this.role,
    this.subject = 'submitter',
  });

  @override
  ConsumerState<RevealableSubmitter> createState() =>
      _RevealableSubmitterState();
}

class _RevealableSubmitterState extends ConsumerState<RevealableSubmitter> {
  RevealedIdentity? _revealed;

  Future<void> _startReveal() async {
    final actorName =
        ref.read(adminProfileProvider).valueOrNull?.displayName;
    final form = _RevealForm(
      source: widget.source,
      submissionId: widget.submissionId,
      subject: widget.subject,
      actorName: actorName,
    );

    // Match the app's presentation language: a slide-up bottom sheet on phones
    // (keyboard-aware, thumb-reachable — like the filter sheets) and a centered
    // dialog on wide/desktop. Same form either way.
    final RevealedIdentity? identity;
    if (MediaQuery.of(context).size.width < 640) {
      identity = await showModalBottomSheet<RevealedIdentity>(
        context: context,
        backgroundColor: AdminUi.surface,
        isScrollControlled: true,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: form,
        ),
      );
    } else {
      identity = await showAppDialog<RevealedIdentity>(
        context: context,
        barrierDismissible: false,
        builder: (_) => Dialog(
          backgroundColor: AdminUi.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: form,
          ),
        ),
      );
    }
    if (identity != null && mounted) {
      setState(() => _revealed = identity);
      showAdminSnackBar(
        context,
        'Identity revealed and logged.',
        type: AdminSnackType.success,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Named submission — nothing to reveal.
    if (!widget.isAnonymous) {
      return SubmitterBlock(
        isAnonymous: false,
        name: widget.name,
        photoUrl: widget.photoUrl,
        role: widget.role,
      );
    }

    // Anonymous + already revealed this session → show the audited identity.
    if (_revealed != null) {
      return _RevealedBlock(identity: _revealed!);
    }

    // Anonymous, not yet revealed. Show the protected block; add the reveal
    // affordance only for a full admin (role 1).
    final isFullAdmin =
        ref.watch(currentAdminIsFullAdminProvider).valueOrNull ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SubmitterBlock(isAnonymous: true),
        if (isFullAdmin) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _startReveal,
              icon: const Icon(Icons.lock_open_rounded, size: 16),
              label: Text('Reveal ${widget.subject} identity'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.red,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                textStyle: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The identity panel shown after a successful reveal — deliberately distinct
/// (amber "audited action" framing) so it never looks like an ordinary named
/// submitter, and reminds the admin the reveal was recorded.
class _RevealedBlock extends StatelessWidget {
  final RevealedIdentity identity;
  const _RevealedBlock({required this.identity});

  static const Color _amber = Color(0xFFB45309);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.orange.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.orange.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IdentityAvatar(
                name: identity.name,
                photoUrl: identity.photoUrl,
                size: 42,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      identity.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AdminUi.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Submitted anonymously',
                      style: TextStyle(fontSize: 11.5, color: AdminUi.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (identity.phone != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.phone_rounded,
                    size: 15, color: AdminUi.textSecondary),
                const SizedBox(width: 8),
                SelectableText(
                  identity.phone!,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AdminUi.textPrimary,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: const [
              Icon(Icons.gpp_maybe_rounded, size: 15, color: _amber),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Identity revealed for this view only — this action was logged '
                  'to the activity log.',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: _amber,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Password + reason form. Presented as a bottom sheet on phones and inside a
/// dialog on wide screens (see `_startReveal`), so its build produces a
/// self-contained panel rather than an AlertDialog. Runs the reveal itself so it
/// owns the busy state and shows an inline error (e.g. wrong password) without
/// closing; pops with the [RevealedIdentity] only on success.
class _RevealForm extends StatefulWidget {
  final RevealSource source;
  final String submissionId;
  final String subject;
  final String? actorName;
  const _RevealForm({
    required this.source,
    required this.submissionId,
    required this.subject,
    required this.actorName,
  });

  @override
  State<_RevealForm> createState() => _RevealFormState();
}

class _RevealFormState extends State<_RevealForm> {
  final _passwordCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _passwordCtrl.text;
    final reason = _reasonCtrl.text.trim();
    if (password.isEmpty) {
      setState(() => _error = 'Enter your account password.');
      return;
    }
    if (reason.length < 3) {
      setState(() => _error = 'Give a reason for revealing this identity.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final identity = await revealSubmitterIdentity(
        source: widget.source,
        submissionId: widget.submissionId,
        password: password,
        reason: reason,
        actorName: widget.actorName,
      );
      if (mounted) Navigator.of(context).pop(identity);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _friendly(e);
      });
    }
  }

  String _friendly(Object e) {
    final s = e.toString();
    if (s.contains('28P01') || s.toLowerCase().contains('incorrect password')) {
      return 'Incorrect password. Please try again.';
    }
    if (s.contains('42501') || s.toLowerCase().contains('full admin')) {
      return 'Only a full admin can reveal an identity.';
    }
    if (s.toLowerCase().contains('reason')) {
      return 'A reason is required.';
    }
    return 'Could not reveal identity. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Scrollable field area so, when the keyboard is up on a phone, the
            // focused input scrolls into view while the action buttons below
            // stay pinned and reachable.
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(Icons.lock_open_rounded,
                      size: 18, color: AppColors.red),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Reveal identity',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AdminUi.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'This ${widget.subject} chose to stay anonymous. Revealing their '
              'identity is a logged action — use it only for genuine abuse, '
              'safety, or legal cases. Confirm your password to continue.',
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: AdminUi.textMuted,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordCtrl,
              enabled: !_busy,
              obscureText: _obscure,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                labelText: 'Your account password',
                labelStyle: const TextStyle(fontSize: 13),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                    size: 18,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reasonCtrl,
              enabled: !_busy,
              minLines: 2,
              maxLines: 3,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _busy ? null : _submit(),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                labelText: 'Reason (recorded in the log)',
                labelStyle: const TextStyle(fontSize: 13),
                alignLabelWithHint: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline_rounded,
                      size: 15, color: AppColors.red),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.red,
                      ),
                    ),
                  ),
                ],
              ),
            ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  style:
                      TextButton.styleFrom(foregroundColor: AdminUi.textMuted),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _busy ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 11),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Reveal'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
