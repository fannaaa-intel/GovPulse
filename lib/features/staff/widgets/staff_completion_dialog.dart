import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../admin/widgets/admin_responsive_dialog.dart';
import '../theme/staff_ui.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Resolving a report, and accounting for it, in one step
//
//  ── WHY THIS DIALOG EXISTS ─────────────────────────────────────────────────
//  "Resolved" used to be a chip like any other: one press, status written, done.
//  The account of what was actually done was a SEPARATE, OPTIONAL thing the
//  officer might or might not type into the updates composer, tagged with a
//  "Completion" picker that wrote a label and nothing else. So the two halves
//  drifted routinely — a resolved report with no explanation, or a completion
//  note on a report still reading in_progress.
//
//  The resident feels the first one. §11 of migration 20260829000001 keys their
//  completion GALLERY on an approved completion update existing, so an office
//  that resolved without writing one left them a closed report, no account of
//  the work, and no photographs of it.
//
//  The agency scan page settled this first and its reasoning holds here:
//  "conflating them would let an agency close a report by writing a sentence."
//  So completing is TWO presses — this dialog is the second one — and the note
//  is required. Photographs are not: an office with a flat battery or no camera
//  must still be able to close work it has genuinely finished.
//
//  ── WHAT THIS DIALOG DOES NOT DO ───────────────────────────────────────────
//  It collects; it does not decide. staff_resolve_report re-checks the note,
//  the role, the department and the report's current status inside the
//  transaction that writes both rows. A UI-only gate is not a gate.
// ════════════════════════════════════════════════════════════════════════════

/// What the officer wrote and attached.
class StaffCompletionResult {
  final String body;
  final List<XFile> photos;
  const StaffCompletionResult({required this.body, required this.photos});
}

/// Photos live in the EXISTING `resolution-media` bucket under `updates/`, the
/// same prefix ReportProgressUpdates writes to — same content, same write gate.
const String _kBucket = 'resolution-media';

/// Attach photos to a completion update that already exists.
///
/// Returns null on success, or a sentence to show the officer. Deliberately
/// does NOT throw: by the time this runs the report is resolved and its account
/// is filed, and failing the whole act over a photo would undo work that
/// genuinely happened. The same trade the scan page makes.
Future<String?> uploadCompletionPhotos(
  String updateId,
  List<XFile> photos,
) async {
  final db = Supabase.instance.client;
  final uid = db.auth.currentUser?.id;
  var failed = 0;

  for (var i = 0; i < photos.length; i++) {
    try {
      final file = photos[i];
      final bytes = await file.readAsBytes();
      final ext = file.name.contains('.')
          ? file.name.split('.').last.toLowerCase()
          : 'jpg';
      final path = 'updates/$updateId/'
          '${DateTime.now().millisecondsSinceEpoch}_$i.$ext';
      await db.storage.from(_kBucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: 'image/$ext'),
          );
      await db.from('report_update_media').insert({
        'update_id': updateId,
        'storage_path': path,
        'mime_type': 'image/$ext',
        'uploaded_by': uid,
      });
    } catch (_) {
      failed++;
    }
  }

  if (failed == 0) return null;
  return failed == photos.length
      ? 'Report resolved, but the photos could not be uploaded. '
          'Add them from the Updates tab.'
      : 'Report resolved. $failed of ${photos.length} photos could not be '
          'uploaded — add them from the Updates tab.';
}

/// Ask for the completion account. Null means the officer backed out.
Future<StaffCompletionResult?> showStaffCompletionDialog(
  BuildContext context, {
  required String office,
}) {
  return showDialog<StaffCompletionResult>(
    context: context,
    builder: (_) => _StaffCompletionDialog(office: office),
  );
}

class _StaffCompletionDialog extends StatefulWidget {
  final String office;
  const _StaffCompletionDialog({required this.office});

  @override
  State<_StaffCompletionDialog> createState() => _StaffCompletionDialogState();
}

class _StaffCompletionDialogState extends State<_StaffCompletionDialog> {
  final _body = TextEditingController();
  final _picker = ImagePicker();
  final List<XFile> _photos = [];

  /// Set only once the officer has tried to submit.
  ///
  /// Showing "this is required" against an empty box the moment the dialog
  /// opens scolds someone who has not done anything wrong yet. The button
  /// carries the state until they press it.
  bool _touched = false;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  bool get _valid => _body.text.trim().isNotEmpty;

  Future<void> _pick() async {
    try {
      final picked = await _picker.pickMultiImage(imageQuality: 82);
      if (picked.isEmpty || !mounted) return;
      setState(() => _photos.addAll(picked));
    } catch (_) {
      if (!mounted) return;
      setState(() {});
    }
  }

  void _submit() {
    if (!_valid) {
      setState(() => _touched = true);
      return;
    }
    Navigator.pop(
      context,
      StaffCompletionResult(
        body: _body.text.trim(),
        photos: List.unmodifiable(_photos),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showError = _touched && !_valid;

    return AdminResponsiveDialog(
      title: 'Mark this report resolved',
      subtitle:
          'Tell the Municipality what ${widget.office} did. They review this '
          'before the citizen sees it.',
      leading: const Icon(
        Icons.task_alt_rounded,
        size: 20,
        color: AppColors.green,
      ),
      maxWidth: 520,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            foregroundColor: StaffUi.textMuted,
            minimumSize: const Size(0, 44),
          ),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: _submit,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.green,
            minimumSize: const Size(0, 44),
          ),
          icon: const Icon(Icons.task_alt_rounded, size: 17),
          label: const Text('Resolve report'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'What was done',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: StaffUi.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _body,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            maxLength: 600,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) {
              // Clear the error the moment they start fixing it, rather than
              // making them press submit again to find out it is satisfied.
              if (_touched) setState(() {});
            },
            style: const TextStyle(fontSize: 13.5, height: 1.45),
            decoration: InputDecoration(
              hintText:
                  'e.g. Culvert cleared and the shoulder re-graded. Two crew, '
                  'one day.',
              hintStyle: const TextStyle(fontSize: 13, color: Colors.black38),
              filled: true,
              fillColor: const Color(0xFFF7F9FC),
              isDense: true,
              counterText: '',
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 11,
              ),
              border: _border(Colors.black12),
              enabledBorder: _border(showError ? AppColors.red : Colors.black12),
              focusedBorder: _border(
                showError ? AppColors.red : AppColors.primaryBlue,
                1.5,
              ),
            ),
          ),
          if (showError) ...[
            const SizedBox(height: 6),
            const Row(
              children: [
                Icon(Icons.error_outline_rounded,
                    size: 14, color: AppColors.red),
                SizedBox(width: 5),
                Expanded(
                  child: Text(
                    'Describe what was done before marking this resolved.',
                    style: TextStyle(fontSize: 11.5, color: AppColors.red),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          const Text(
            'Photos of the finished work',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: StaffUi.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Optional. The citizen sees these once the Municipality approves '
            'your note.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.4,
              color: StaffUi.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          if (_photos.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < _photos.length; i++)
                  Chip(
                    label: Text(
                      _photos[i].name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    onDeleted: () => setState(() => _photos.removeAt(i)),
                    deleteIcon: const Icon(Icons.close_rounded, size: 15),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          // Wrap, so the control stacks rather than overflows at 320px and at
          // large text scales.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _pick,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryBlue,
                  side: BorderSide(
                    color: AppColors.primaryBlue.withValues(alpha: 0.4),
                  ),
                  // 44 floor: this is a control an officer uses standing in a
                  // road on a phone.
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 17),
                label: Text(
                  _photos.isEmpty
                      ? 'Add photos'
                      : 'Add more (${_photos.length})',
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  static OutlineInputBorder _border(Color c, [double w = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c, width: w),
      );
}
