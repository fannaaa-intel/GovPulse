import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_colors.dart';
import 'app_dialog.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Progress updates — the running account under a report's status
//
//  A report's STATUS is four milestones. This is the commentary underneath:
//  "site inspected, three potholes found", "materials delivered", "patching
//  started". Many per report, each with words and optionally photos.
//
//  ── THE APPROVAL LOOP IS THE POINT ─────────────────────────────────────────
//    office posts -> pending_approval -> admin approves -> citizen sees it
//                                     \-> admin rejects with a reason
//
//  Nothing an office writes reaches the citizen unreviewed. That is enforced in
//  the DATABASE (migration 20260829000001), not here: the citizen's SELECT
//  policy binds owns_report to status = 'approved', and the staff INSERT policy
//  hard-codes 'pending_approval' in its WITH CHECK. This widget renders that
//  contract; it does not implement it. A UI-only gate is not a gate.
//
//  ── ONE WIDGET, THREE ROLES ────────────────────────────────────────────────
//    • citizen → [ReportUpdatesMode.citizen] — read-only, approved rows only
//                (RLS returns nothing else, so this is belt AND braces)
//    • staff   → [ReportUpdatesMode.author]  — compose + see own pending and
//                rejected rows with the admin's reason
//    • admin   → [ReportUpdatesMode.reviewer]— compose (auto-approved) + an
//                Approve / Reject decision on everyone else's
//
//  Degrades to nothing if the migration has not been applied, matching
//  ReportWorkLog and ResolutionMediaSection.
// ════════════════════════════════════════════════════════════════════════════

/// What this instance may do. See the file header.
enum ReportUpdatesMode { citizen, author, reviewer }

/// Photos live in the EXISTING public `resolution-media` bucket under an
/// `updates/` prefix — same content, same write gate, one less bucket policy to
/// keep in step. See section 10 of the migration.
const String _kBucket = 'resolution-media';

class _UpdateMedia {
  final String id;
  final String url;
  const _UpdateMedia({required this.id, required this.url});
}

class _Update {
  final String id;
  final String body;
  final String kind;
  final String status;
  final String? rejectedReason;
  final String authorRole;
  final String authorName;
  final DateTime? createdAt;
  final List<_UpdateMedia> media;

  const _Update({
    required this.id,
    required this.body,
    required this.kind,
    required this.status,
    required this.rejectedReason,
    required this.authorRole,
    required this.authorName,
    required this.createdAt,
    required this.media,
  });

  bool get isPending => status == 'pending_approval';
  bool get isRejected => status == 'rejected';
  bool get isCompletion => kind == 'completion';
}

class ReportProgressUpdates extends StatefulWidget {
  final String reportId;
  final ReportUpdatesMode mode;

  /// Display label stored on anything this instance posts — the office or
  /// agency name, never a person.
  final String authorName;

  const ReportProgressUpdates({
    super.key,
    required this.reportId,
    required this.mode,
    this.authorName = '',
  });

  @override
  State<ReportProgressUpdates> createState() => _ReportProgressUpdatesState();
}

class _ReportProgressUpdatesState extends State<ReportProgressUpdates> {
  final _supabase = Supabase.instance.client;
  final _picker = ImagePicker();
  final _body = TextEditingController();

  List<_Update> _updates = const [];
  final List<XFile> _staged = [];
  bool _loading = true;
  bool _sending = false;
  bool _unavailable = false;
  bool _completion = false;

  bool get _canPost => widget.mode != ReportUpdatesMode.citizen;
  bool get _canReview => widget.mode == ReportUpdatesMode.reviewer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await _supabase
          .from('report_updates')
          .select('id, body, kind, status, rejected_reason, author_role, '
              'author_name, created_at, report_update_media(id, storage_path)')
          .eq('report_id', widget.reportId)
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() {
        _updates = List<Map<String, dynamic>>.from(rows).map(_fromRow).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      // "The migration has not been applied" must be distinguished from "the
      // request failed", because the first collapses this widget to nothing and
      // the second must not: a network error that silently renders an empty
      // panel is indistinguishable from a report with no updates, which is the
      // silent-success shape this codebase keeps finding.
      //
      // Postgres reports an unknown relation as SQLSTATE 42P01, and PostgREST
      // passes that through as PostgrestException.code. Matching on the CODE is
      // what makes this precise — an earlier draft matched the table NAME
      // anywhere in the message, which also matched the request URL and so
      // swallowed every network failure.
      final missing = e is PostgrestException && e.code == '42P01';
      setState(() {
        _unavailable = missing;
        _loading = false;
      });
      if (!missing && mounted) _toast('Could not load updates: $e');
    }
  }

  _Update _fromRow(Map<String, dynamic> r) {
    final media = <_UpdateMedia>[];
    for (final m in (r['report_update_media'] as List? ?? const [])) {
      final row = Map<String, dynamic>.from(m as Map);
      final path = row['storage_path'] as String?;
      if (path == null) continue;
      media.add(_UpdateMedia(
        id: row['id'].toString(),
        url: _supabase.storage.from(_kBucket).getPublicUrl(path),
      ));
    }
    return _Update(
      id: r['id'].toString(),
      body: (r['body'] as String?) ?? '',
      kind: (r['kind'] as String?) ?? 'progress',
      status: (r['status'] as String?) ?? 'pending_approval',
      rejectedReason: r['rejected_reason'] as String?,
      authorRole: (r['author_role'] as String?) ?? 'staff',
      authorName: (r['author_name'] as String?) ?? '',
      createdAt: DateTime.tryParse('${r['created_at']}')?.toLocal(),
      media: media,
    );
  }

  // ── Posting ───────────────────────────────────────────────────────────────

  Future<void> _pickPhotos() async {
    try {
      final picked = await _picker.pickMultiImage(imageQuality: 82);
      if (picked.isEmpty || !mounted) return;
      setState(() => _staged.addAll(picked));
    } catch (e) {
      _toast('Could not pick photos: $e');
    }
  }

  /// Inserts the update, then uploads any staged photos against it.
  ///
  /// The update row goes in FIRST and the media follows, because
  /// report_update_media.update_id is NOT NULL — there is no row to attach a
  /// photo to until the update exists. A failed upload therefore leaves a
  /// text-only update rather than an orphaned file, which is the better half of
  /// the trade: the words are the update.
  Future<void> _submit() async {
    final text = _body.text.trim();
    if (text.isEmpty || _sending) return;
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;

    setState(() => _sending = true);
    try {
      final inserted = await _supabase
          .from('report_updates')
          .insert({
            'report_id': widget.reportId,
            'body': text,
            'kind': _completion ? 'completion' : 'progress',
            'author_id': uid,
            'author_role': _canReview ? 'admin' : 'staff',
            'author_name': widget.authorName,
          })
          .select('id')
          .single();

      final updateId = inserted['id'].toString();

      for (var i = 0; i < _staged.length; i++) {
        final file = _staged[i];
        final bytes = await file.readAsBytes();
        final ext = file.name.contains('.')
            ? file.name.split('.').last.toLowerCase()
            : 'jpg';
        final path = 'updates/$updateId/'
            '${DateTime.now().millisecondsSinceEpoch}_$i.$ext';
        await _supabase.storage.from(_kBucket).uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(contentType: 'image/$ext'),
            );
        await _supabase.from('report_update_media').insert({
          'update_id': updateId,
          'storage_path': path,
          'mime_type': 'image/$ext',
          'uploaded_by': uid,
        });
      }

      if (!mounted) return;
      _body.clear();
      setState(() {
        _staged.clear();
        _completion = false;
        _sending = false;
      });
      await _load();
      if (mounted) {
        _toast(_canReview
            ? 'Update posted.'
            : 'Update submitted for admin approval.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      _toast('Could not post the update: $e');
    }
  }

  // ── Reviewing ─────────────────────────────────────────────────────────────

  Future<void> _decide(_Update u, {required bool approve}) async {
    String? reason;
    if (!approve) {
      reason = await _askReason();
      if (reason == null) return;
    }
    try {
      await _supabase.rpc('review_report_update', params: {
        'p_update': u.id,
        'p_approve': approve,
        'p_reason': reason,
      });
      if (!mounted) return;
      await _load();
      if (mounted) {
        _toast(approve
            ? 'Update approved — the citizen can now see it.'
            : 'Update returned to the author.');
      }
    } catch (e) {
      if (mounted) _toast('Could not save that decision: $e');
    }
  }

  Future<String?> _askReason() async {
    final ctrl = TextEditingController();
    final result = await showAppDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Return this update'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tell the office what to fix. They see this and can resubmit.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLines: 3,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'e.g. Please attach a photo of the finished work.',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            // The server also refuses a blank reason — this only saves the
            // round trip.
            onPressed: () {
              final v = ctrl.text.trim();
              if (v.isEmpty) return;
              Navigator.pop(ctx, v);
            },
            child: const Text('Return'),
          ),
        ],
      ),
    );
    // Disposed after the route's exit transition, not the instant `await`
    // returns — showAppDialog resolves when the pop is REQUESTED and the dialog
    // keeps rebuilding on the way out, so an immediate dispose() throws
    // "A TextEditingController was used after being disposed" on the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
    return result;
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_unavailable) return const SizedBox.shrink();
    // A citizen with nothing approved yet sees nothing at all, rather than an
    // empty card implying the office has gone quiet.
    if (widget.mode == ReportUpdatesMode.citizen &&
        _updates.isEmpty &&
        !_loading) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primaryBlue.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.timeline_rounded,
                  size: 18, color: AppColors.primaryBlue),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Progress updates',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                ),
              ),
              if (_updates.isNotEmpty)
                Text(
                  '${_updates.length}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_canPost) ...[
            _composer(),
            const SizedBox(height: 14),
          ],
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_updates.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text(
                'No updates yet.',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
            )
          else
            for (final u in _updates) _updateTile(u),
        ],
      ),
    );
  }

  Widget _composer() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _body,
          maxLines: 3,
          minLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'e.g. We are currently excavating the drainage line.',
            border: OutlineInputBorder(),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        if (_staged.isNotEmpty) ...[
          const SizedBox(height: 8),
          // Wrap, not Row: a staged-photo strip on a 320px phone overflows the
          // moment it holds more than three chips.
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < _staged.length; i++)
                Chip(
                  label: Text(
                    'Photo ${i + 1}',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  onDeleted: () => setState(() => _staged.removeAt(i)),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        // Wrap so the controls stack instead of overflowing on a narrow phone.
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // Colours are pinned rather than inherited. This widget is
            // embedded in three separately-themed surfaces (admin console,
            // staff console, citizen app), so an ambient ColorScheme would
            // render it differently in each — and Flutter's default purple
            // wherever a host has not themed buttons, which is exactly the
            // regression commit 01d9351 went and fixed elsewhere.
            OutlinedButton.icon(
              onPressed: _sending ? null : _pickPhotos,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryBlue,
                side: BorderSide(
                  color: AppColors.primaryBlue.withValues(alpha: 0.4),
                ),
              ),
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 17),
              label: const Text('Add photos'),
            ),
            FilterChip(
              selected: _completion,
              onSelected: (v) => setState(() => _completion = v),
              label: const Text('Completion'),
              selectedColor: AppColors.primaryBlue.withValues(alpha: 0.14),
              checkmarkColor: AppColors.primaryBlue,
              visualDensity: VisualDensity.compact,
            ),
            FilledButton.icon(
              onPressed: _sending ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
              ),
              icon: _sending
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded, size: 16),
              label: Text(_canReview ? 'Post' : 'Submit for approval'),
            ),
          ],
        ),
        if (!_canReview) ...[
          const SizedBox(height: 6),
          const Text(
            'An admin reviews this before the citizen can see it.',
            style: TextStyle(fontSize: 11.5, color: Colors.black54),
          ),
        ],
      ],
    );
  }

  Widget _updateTile(_Update u) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                u.authorName.isEmpty ? 'LGU' : u.authorName,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
              if (u.isCompletion) _pill('Completion', AppColors.green),
              // Review state is shown to whoever can act on it. The citizen
              // only ever receives approved rows, so no badge is needed there.
              if (widget.mode != ReportUpdatesMode.citizen && u.isPending)
                _pill('Pending approval', Colors.orange),
              if (widget.mode != ReportUpdatesMode.citizen && u.isRejected)
                _pill('Returned', AppColors.red),
              if (u.createdAt != null)
                Text(
                  _stamp(u.createdAt!),
                  style: const TextStyle(fontSize: 11, color: Colors.black45),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(u.body, style: const TextStyle(fontSize: 13, height: 1.4)),
          if (u.isRejected && (u.rejectedReason ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: AppColors.red.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Returned: ${u.rejectedReason}',
                style: const TextStyle(fontSize: 12, height: 1.35),
              ),
            ),
          ],
          if (u.media.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final m in u.media)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: m.url,
                      width: 84,
                      height: 84,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => const SizedBox(
                        width: 84,
                        height: 84,
                        child: Icon(Icons.broken_image_outlined, size: 18),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (_canReview && u.isPending) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                FilledButton.icon(
                  onPressed: () => _decide(u, approve: true),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.green,
                  ),
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('Approve'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _decide(u, approve: false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.red,
                    side: BorderSide(
                      color: AppColors.red.withValues(alpha: 0.4),
                    ),
                  ),
                  icon: const Icon(Icons.undo_rounded, size: 16),
                  label: const Text('Return'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _pill(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      );

  String _stamp(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${d.day}/${d.month}/${d.year}';
  }
}
