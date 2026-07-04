import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../theme/admin_ui.dart';
import 'admin_skeleton.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Shared UI kit for the admin "submission" consoles — Reports, Suggestions and
//  Feedback. One design language across all three: the same anonymous identity
//  treatment, the same Filters-button → sheet → active-chips pattern, the same
//  card/table shells, status pills and empty/skeleton states.
//
//  Anonymous privacy is a first-class visual concept here: an anonymous
//  submission never shows a name/photo (the provider never even fetches one),
//  and it gets a distinct "protected identity" look so it reads as anonymous at
//  a glance — not just a missing name.
// ════════════════════════════════════════════════════════════════════════════

/// The one colour that means "anonymous / protected identity" everywhere.
const Color kAnonColor = Color(0xFF64748B); // slate

// ── Anonymous identity ───────────────────────────────────────────────────────

/// Masked avatar for an anonymous submitter — a hidden-identity glyph on a
/// slate tint, deliberately different from a real person's photo/initial.
class AnonAvatar extends StatelessWidget {
  final double size;
  const AnonAvatar({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: kAnonColor.withValues(alpha: 0.14),
        shape: BoxShape.circle,
        border: Border.all(color: kAnonColor.withValues(alpha: 0.35)),
      ),
      child: Icon(
        Icons.visibility_off_rounded,
        size: size * 0.5,
        color: kAnonColor,
      ),
    );
  }
}

/// Compact "Anonymous" pill used in dense rows (table cells, card meta).
class AnonPill extends StatelessWidget {
  const AnonPill({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: kAnonColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kAnonColor.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.visibility_off_rounded, size: 12, color: kAnonColor),
          SizedBox(width: 5),
          Text(
            'Anonymous',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: kAnonColor,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Real submitter avatar: profile photo, or a coloured initial fallback.
class IdentityAvatar extends StatelessWidget {
  final String name;
  final String? photoUrl;
  final double size;
  const IdentityAvatar({
    super.key,
    required this.name,
    this.photoUrl,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Text(
        initial,
        style: TextStyle(
          fontSize: size * 0.4,
          fontWeight: FontWeight.w700,
          color: AppColors.primaryBlue,
        ),
      ),
    );
    if (photoUrl == null || photoUrl!.isEmpty) return fallback;
    return ClipOval(
      child: Image.network(
        photoUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

String roleLabel(String? role) {
  switch (role) {
    case 'admin':
      return 'Admin';
    case 'staff':
      return 'Staff';
    default:
      return 'Citizen';
  }
}

class RoleChip extends StatelessWidget {
  final String? role;
  const RoleChip(this.role, {super.key});

  @override
  Widget build(BuildContext context) {
    final isOfficial = role == 'admin' || role == 'staff';
    final c = isOfficial ? AppColors.primaryBlue : AdminUi.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        roleLabel(role),
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: c),
      ),
    );
  }
}

/// Inline submitter for list rows/cards: the anonymous pill, or name + role
/// chip. Never renders a name for anonymous submissions.
class SubmitterInline extends StatelessWidget {
  final bool isAnonymous;
  final String? name;
  final String? role;
  const SubmitterInline({
    super.key,
    required this.isAnonymous,
    this.name,
    this.role,
  });

  @override
  Widget build(BuildContext context) {
    if (isAnonymous) {
      return const Align(alignment: Alignment.centerLeft, child: AnonPill());
    }
    return Row(
      children: [
        Flexible(
          child: Text(
            (name == null || name!.isEmpty) ? 'Resident' : name!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AdminUi.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 6),
        RoleChip(role),
      ],
    );
  }
}

/// The larger submitter block for detail dialogs — avatar + name + role, or a
/// clear "Anonymous submission" panel. Same hard rule: no name/photo for anon.
class SubmitterBlock extends StatelessWidget {
  final bool isAnonymous;
  final String? name;
  final String? photoUrl;
  final String? role;
  const SubmitterBlock({
    super.key,
    required this.isAnonymous,
    this.name,
    this.photoUrl,
    this.role,
  });

  @override
  Widget build(BuildContext context) {
    if (isAnonymous) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kAnonColor.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kAnonColor.withValues(alpha: 0.30)),
        ),
        child: Row(
          children: [
            const AnonAvatar(size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Anonymous submission',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: kAnonColor,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Identity withheld and never retrieved',
                    style: TextStyle(fontSize: 11.5, color: AdminUi.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final display = (name == null || name!.isEmpty) ? 'Resident' : name!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AdminUi.subtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminUi.border),
      ),
      child: Row(
        children: [
          IdentityAvatar(name: display, photoUrl: photoUrl, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  display,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AdminUi.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                RoleChip(role),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Status pill ──────────────────────────────────────────────────────────────

class StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  const StatusPill({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// ── Cards / shells ───────────────────────────────────────────────────────────

/// The white results card that wraps a table or a card list.
class AdminResultsCard extends StatelessWidget {
  final Widget child;
  const AdminResultsCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AdminUi.surface,
        borderRadius: BorderRadius.circular(AdminUi.cardRadius),
        border: Border.all(color: AdminUi.border),
        boxShadow: AdminUi.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// A single stacked list card. Anonymous submissions get a slate left-accent +
/// faint tint so they're distinguishable from named ones at a glance.
class SubmissionListCard extends StatelessWidget {
  final bool isAnonymous;
  final VoidCallback onTap;
  final Widget child;
  const SubmissionListCard({
    super.key,
    required this.isAnonymous,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isAnonymous ? kAnonColor.withValues(alpha: 0.04) : AdminUi.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isAnonymous
              ? kAnonColor.withValues(alpha: 0.28)
              : AdminUi.border,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left accent — slate for anonymous, invisible otherwise.
                Container(
                  width: 4,
                  color: isAnonymous ? kAnonColor : Colors.transparent,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: child,
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

// ── Toolbar: search + filters button + active chips ──────────────────────────

class AdminSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  const AdminSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 13, color: AdminUi.textMuted),
        prefixIcon: const Icon(Icons.search_rounded, size: 18),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded, size: 16),
                onPressed: onClear,
              ),
        contentPadding: const EdgeInsets.symmetric(vertical: 11),
        filled: true,
        fillColor: AdminUi.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AdminUi.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AdminUi.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primaryBlue),
        ),
      ),
    );
  }
}

/// Button that opens the filter sheet; shows a count badge when filters are on.
class FilterButton extends StatelessWidget {
  final int activeCount;
  final VoidCallback onTap;
  const FilterButton({super.key, required this.activeCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final active = activeCount > 0;
    final c = AppColors.primaryBlue;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: active ? c.withValues(alpha: 0.10) : AdminUi.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active ? c.withValues(alpha: 0.45) : AdminUi.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.tune_rounded,
                size: 17,
                color: active ? c : AdminUi.textSecondary,
              ),
              const SizedBox(width: 7),
              Text(
                'Filters',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: active ? c : AdminUi.textSecondary,
                ),
              ),
              if (active) ...[
                const SizedBox(width: 7),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$activeCount',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A single removable active-filter chip shown above the results.
class ActiveChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;
  final bool emphasize; // anonymous / high-signal chips
  const ActiveChip({
    super.key,
    required this.label,
    required this.onRemove,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = emphasize ? kAnonColor : AppColors.primaryBlue;
    return Container(
      padding: const EdgeInsets.only(left: 10, right: 4, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: c,
            ),
          ),
          const SizedBox(width: 2),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(20),
            child: Icon(Icons.close_rounded, size: 15, color: c),
          ),
        ],
      ),
    );
  }
}

/// A labelled row of single-select choice chips, used inside the filter sheet
/// (replaces cramped dropdowns). [value] == null selects the "All" chip.
class FilterChoiceRow<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<({T? value, String text})> options;
  final ValueChanged<T?> onSelected;
  const FilterChoiceRow({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: AdminUi.textMuted,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final o in options)
              _ChoiceChip(
                text: o.text,
                selected: o.value == value,
                onTap: () => onSelected(o.value),
              ),
          ],
        ),
      ],
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  final String text;
  final bool selected;
  final VoidCallback onTap;
  const _ChoiceChip({
    required this.text,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.primaryBlue;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? c.withValues(alpha: 0.12) : AdminUi.subtle,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? c.withValues(alpha: 0.5) : AdminUi.border,
            ),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? c : AdminUi.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// A full-width toggle row for a boolean filter (e.g. "Anonymous only").
class FilterSwitchRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const FilterSwitchRow({
    super.key,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: value ? kAnonColor.withValues(alpha: 0.06) : AdminUi.subtle,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: value ? kAnonColor.withValues(alpha: 0.35) : AdminUi.border,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: value ? kAnonColor : AdminUi.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AdminUi.textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11.5, color: AdminUi.textMuted),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: Colors.white,
              activeTrackColor: kAnonColor,
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows [content] as a bottom sheet on phones and a centered dialog on wider
/// screens — responsive across devices/platforms. [onReset] adds a Reset action.
Future<void> openAdminFilterSheet(
  BuildContext context, {
  required String title,
  required Widget content,
  VoidCallback? onReset,
}) {
  final narrow = MediaQuery.of(context).size.width < 720;
  final shell = _FilterSheetShell(
    title: title,
    onReset: onReset,
    child: content,
  );
  if (narrow) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: AdminUi.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: shell,
      ),
    );
  }
  return showDialog(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: AdminUi.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: shell,
      ),
    ),
  );
}

class _FilterSheetShell extends StatelessWidget {
  final String title;
  final Widget child;
  final VoidCallback? onReset;
  const _FilterSheetShell({
    required this.title,
    required this.child,
    this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AdminUi.textPrimary,
                  ),
                ),
                const Spacer(),
                if (onReset != null)
                  TextButton(
                    onPressed: onReset,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primaryBlue,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                    ),
                    child: const Text(
                      'Reset',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
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
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: child,
            ),
          ),
          const Divider(height: 1, color: AdminUi.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'Show results',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Respond-to-citizen panel (suggestions & feedback) ───────────────────────

/// The primary admin action for suggestions/feedback: reply to the submitter
/// (sent as a push + bell notification) and keep an internal note. For an
/// anonymous submission there is no one to notify, so the reply composer is
/// replaced by a clear notice and only the internal note remains.
class RespondPanel extends StatefulWidget {
  final bool isAnonymous;
  final DateTime? respondedAt;
  final String? existingResponse;

  /// Quick-fill reply suggestions.
  final List<String> templates;

  /// Pre-populated internal note controller (owned by the caller).
  final TextEditingController noteController;

  final Future<void> Function(String message) onSendResponse;
  final Future<void> Function() onSaveNote;

  const RespondPanel({
    super.key,
    required this.isAnonymous,
    required this.respondedAt,
    required this.existingResponse,
    required this.templates,
    required this.noteController,
    required this.onSendResponse,
    required this.onSaveNote,
  });

  @override
  State<RespondPanel> createState() => _RespondPanelState();
}

class _RespondPanelState extends State<RespondPanel> {
  final _replyCtrl = TextEditingController();
  bool _sending = false;
  bool _savingNote = false;

  @override
  void dispose() {
    _replyCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_replyCtrl.text.trim().isEmpty) return;
    setState(() => _sending = true);
    try {
      await widget.onSendResponse(_replyCtrl.text.trim());
      _replyCtrl.clear(); // only on success
    } catch (_) {
      // The caller surfaces the error (snackbar); keep the text so it's not lost.
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _saveNote() async {
    setState(() => _savingNote = true);
    try {
      await widget.onSaveNote();
    } finally {
      if (mounted) setState(() => _savingNote = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('RESPOND TO CITIZEN'),
        const SizedBox(height: 10),
        if (widget.isAnonymous)
          _anonNotice()
        else ...[
          if (widget.respondedAt != null) _sentBanner(),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in widget.templates)
                _TemplateChip(
                  text: t,
                  onTap: () {
                    _replyCtrl.text = t;
                    _replyCtrl.selection = TextSelection.collapsed(
                      offset: t.length,
                    );
                    setState(() {});
                  },
                ),
            ],
          ),
          const SizedBox(height: 10),
          _field(
            _replyCtrl,
            widget.respondedAt == null
                ? 'Write a reply the citizen will receive…'
                : 'Send another reply…',
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded, size: 16),
              label: Text(widget.respondedAt == null
                  ? 'Send response'
                  : 'Send again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              ),
            ),
          ),
        ],
        const SizedBox(height: 22),
        _title('INTERNAL NOTE'),
        const SizedBox(height: 4),
        const Text(
          'Only visible to admins — never sent to the citizen.',
          style: TextStyle(fontSize: 11.5, color: AdminUi.textMuted),
        ),
        const SizedBox(height: 8),
        _field(widget.noteController, 'Add an internal note…'),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: _savingNote ? null : _saveNote,
            icon: _savingNote
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sticky_note_2_outlined, size: 16),
            label: const Text('Save note'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryBlue,
              side: const BorderSide(color: AdminUi.border),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            ),
          ),
        ),
      ],
    );
  }

  Widget _anonNotice() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kAnonColor.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kAnonColor.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: const [
          Icon(Icons.visibility_off_rounded, size: 20, color: kAnonColor),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Anonymous submission — there\'s no recipient to reply to. '
              'You can still leave an internal note below.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: kAnonColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sentBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.green.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  size: 16, color: AppColors.green),
              const SizedBox(width: 6),
              Text(
                'Replied · ${adminShortDate(widget.respondedAt)}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.green,
                ),
              ),
            ],
          ),
          if (widget.existingResponse != null &&
              widget.existingResponse!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              widget.existingResponse!,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AdminUi.textPrimary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _title(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: AdminUi.textMuted,
        ),
      );

  Widget _field(TextEditingController c, String hint) {
    return TextField(
      controller: c,
      maxLines: 4,
      minLines: 3,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 13, color: AdminUi.textMuted),
        filled: true,
        fillColor: AdminUi.subtle,
        contentPadding: const EdgeInsets.all(12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AdminUi.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AdminUi.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primaryBlue),
        ),
      ),
    );
  }
}

class _TemplateChip extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _TemplateChip({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.primaryBlue.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.primaryBlue.withValues(alpha: 0.30),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_rounded,
                  size: 14, color: AppColors.primaryBlue),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.primaryBlue,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── States & helpers ─────────────────────────────────────────────────────────

class AdminResultsMessage extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  final Widget? action;
  const AdminResultsMessage({
    super.key,
    required this.icon,
    required this.color,
    required this.text,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 52, horizontal: 16),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30, color: color),
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

class AdminListSkeleton extends StatelessWidget {
  const AdminListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: AdminShimmer(
        child: Column(
          children: [
            _SkeletonRow(),
            _SkeletonRow(),
            _SkeletonRow(),
            _SkeletonRow(),
            _SkeletonRow(),
          ],
        ),
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonCircle(size: 34),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 140, height: 12),
                SizedBox(height: 8),
                SkeletonBox(width: 90, height: 10),
              ],
            ),
          ),
          SizedBox(width: 60, child: SkeletonBox(width: 60, height: 20, radius: 20)),
        ],
      ),
    );
  }
}

const List<String> _kMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String adminShortDate(DateTime? t) {
  if (t == null) return '—';
  return '${_kMonths[t.month - 1]} ${t.day}, ${t.year}';
}
