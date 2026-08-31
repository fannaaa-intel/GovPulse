import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/admin/widgets/admin_skeleton.dart';
import '../theme/app_colors.dart';
import 'app_dialog.dart';
import 'app_snackbar.dart';

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

/// One placeholder update card — an author line, two lines of body, and a
/// thumbnail slot, at the sizes a real card uses.
class _UpdateSkeleton extends StatelessWidget {
  const _UpdateSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black12),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SkeletonBox(width: 110, height: 11),
              SizedBox(width: 8),
              SkeletonBox(width: 54, height: 11),
            ],
          ),
          SizedBox(height: 10),
          SkeletonBox(width: double.infinity, height: 10),
          SizedBox(height: 6),
          SkeletonBox(width: 180, height: 10),
        ],
      ),
    );
  }
}

class ReportProgressUpdates extends StatefulWidget {
  final String reportId;
  final ReportUpdatesMode mode;

  /// Display label stored on anything this instance posts — the office or
  /// agency name, never a person.
  final String authorName;

  /// Whether to draw the bordered card and its own "Progress updates" heading.
  ///
  /// The consoles want it: the panel sits among other bordered panels in a tab
  /// and needs an edge to separate it from them. The CITIZEN screen does not —
  /// every section there is a blue heading OUTSIDE the content ("Processing
  /// timeline", "Report details"), so a self-titled bordered box was the one
  /// element on that page framed differently from everything around it.
  final bool chrome;

  /// Show at most this many updates, with a "View all" opening the rest in a
  /// sheet. Null means show everything.
  ///
  /// The citizen screen sets it to 2: that screen already carries a status
  /// tracker, a details card, attachments and a completion gallery, and an
  /// unbounded timeline turned it into a page nobody reaches the bottom of. The
  /// consoles leave it null — an office reviewing work wants the whole history
  /// in front of it.
  final int? maxVisible;

  /// Padding around the CONTENT, applied inside this widget so a caller that
  /// also supplies [heading] can pad the two differently — the citizen screen
  /// runs its heading's divider to the card edge while insetting the cards
  /// beneath it. Defaults to none.
  final EdgeInsetsGeometry? padding;

  /// Rendered above the content, INSIDE this widget's own build.
  ///
  /// Passed in rather than written by the caller because this widget hides
  /// itself completely when a citizen has no approved updates — a heading
  /// emitted by the parent would be left stranded above nothing. Supplying it
  /// here ties the label's visibility to the content it labels.
  final Widget? heading;

  /// The report is CLOSED — resolved or rejected — so the history stays but
  /// nothing new may be written.
  ///
  /// [mode] answers "who is this person and what are they allowed to do"; this
  /// answers "is there still work to report on". They are different questions
  /// and both have to be true before a composer appears. An office was
  /// previously offered a "what has happened" box on a report that had been
  /// finished weeks earlier — an invitation to file progress against closed
  /// work, which is either a mistake about to happen or a note nobody will
  /// ever read.
  ///
  /// Pending rows are still shown when set, because an admin must be able to
  /// decide an update that was submitted just before the report closed.
  final bool locked;

  const ReportProgressUpdates({
    super.key,
    required this.reportId,
    required this.mode,
    this.authorName = '',
    this.chrome = true,
    this.heading,
    this.maxVisible,
    this.padding,
    this.locked = false,
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

  /// Both must hold: the right role, AND a report still open to be worked on.
  /// See [ReportProgressUpdates.locked].
  bool get _canPost =>
      widget.mode != ReportUpdatesMode.citizen && !widget.locked;
  bool get _canReview => widget.mode == ReportUpdatesMode.reviewer;

  /// Split for the reviewer's two lists. Order is preserved from the fetch
  /// (newest first) within each half.
  List<_Update> get _pending =>
      _updates.where((u) => u.isPending).toList(growable: false);
  List<_Update> get _decided =>
      _updates.where((u) => !u.isPending).toList(growable: false);

  /// What the inline list actually renders when [maxVisible] caps it.
  List<_Update> get _visible {
    final cap = widget.maxVisible;
    if (cap == null || _updates.length <= cap) return _updates;
    return _updates.take(cap).toList(growable: false);
  }

  int get _hiddenCount {
    final cap = widget.maxVisible;
    if (cap == null) return 0;
    return _updates.length - _visible.length;
  }

  /// Opens the full history. A sheet rather than a route: the citizen is one
  /// tap from where they were, and the report screen behind it keeps its scroll
  /// position — which a push/pop would lose on the way back.
  void _openAll() {
    // ── Bottom sheet on a phone, centred dialog on a wide screen ───────────
    // showModalBottomSheet ALWAYS anchors to the bottom edge, whatever the
    // viewport: on a desktop browser that put a drag-handled sheet across the
    // foot of a 1900px window, which is a phone gesture stranded on a device
    // that has no such gesture. A centred dialog is what a wide screen expects,
    // and the same content fills both.
    // ⚠ view.physicalSize, NOT MediaQuery.size.
    //
    // The citizen web shell REPLACES MediaQuery.size with its content pane's
    // constraints (citizen_shell.dart ~1360), so inside the shell a 1311px
    // browser window reports about 640px — below any sensible desktop
    // threshold. Keying off that gave a bottom sheet on a wide desktop, which
    // is precisely the bug this switch was added to fix.
    //
    // The dialog is routed on the ROOT navigator and covers the whole window,
    // so the window is what should decide its presentation. view.physicalSize
    // is the one measurement no ancestor can override; dividing by the pixel
    // ratio converts it to the logical pixels the 720 threshold is expressed in.
    final view = View.of(context);
    final windowWidth = view.physicalSize.width / view.devicePixelRatio;
    final wide = windowWidth >= 720;

    if (wide) {
      showAppDialog<void>(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(32),
          child: _AllUpdatesSheet(
            updates: _updates,
            tile: _updateTile,
            floating: true,
          ),
        ),
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // Root navigator: the citizen web shell nests a Navigator inside its
      // content pane, and a sheet pushed there is clipped to that pane instead
      // of rising from the bottom of the window.
      useRootNavigator: true,
      builder: (_) => _AllUpdatesSheet(updates: _updates, tile: _updateTile),
    );
  }

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
      if (!missing && mounted) {
        _toast('Could not load updates: $e', type: AppSnackType.error);
      }
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
      _toast('Could not pick photos: $e', type: AppSnackType.error);
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
        _toast(
          _canReview
              ? 'Update posted.'
              : 'Update submitted for admin approval.',
          type: AppSnackType.success,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      _toast('Could not post the update: $e', type: AppSnackType.error);
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
        _toast(
          approve
              ? 'Update approved — the citizen can now see it.'
              : 'Update returned to the author.',
          type: AppSnackType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        _toast('Could not save that decision: $e', type: AppSnackType.error);
      }
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

  /// The app's shared TOP toast, not a Material SnackBar.
  ///
  /// showAppSnackBar renders into the root overlay and is what every other
  /// surface here uses; a bare ScaffoldMessenger call (which this used to make)
  /// puts a differently-shaped, differently-coloured bar at the BOTTOM and
  /// reads as a foreign control.
  void _toast(String msg, {AppSnackType type = AppSnackType.info}) {
    if (!mounted) return;
    showAppSnackBar(context, msg, type: type);
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

    final content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.chrome) ...[
            Row(
              children: [
                const Icon(Icons.timeline_rounded,
                    size: 18, color: AppColors.primaryBlue),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Progress updates',
                    style:
                        TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
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
          ],
          if (_canPost) ...[
            _composer(),
            const SizedBox(height: 14),
          ],
          if (_loading)
            // Shaped placeholders, not a spinner: the list that lands has a
            // known shape, so the layout should not jump when it arrives. Same
            // primitives every other surface in this app loads with.
            const AdminShimmer(
              child: Column(
                children: [
                  _UpdateSkeleton(),
                  SizedBox(height: 10),
                  _UpdateSkeleton(),
                ],
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
          else if (_canReview && _pending.isNotEmpty) ...[
            // -- Why the reviewer's list is split ---------------------------
            // Approve / Return only render on a PENDING card, so a reviewer
            // looking at a report whose updates are all decided sees a list of
            // cards with no controls and no explanation of why -- which is
            // exactly what the admin console showed. Separating the queue from
            // the history makes "there is nothing waiting on you" a statement
            // the page makes, rather than something the reader has to infer.
            _sectionLabel(
              'Waiting for your decision',
              count: _pending.length,
              color: const Color(0xFFB45309),
            ),
            const SizedBox(height: 8),
            for (final u in _pending) _updateTile(u),
            if (_decided.isNotEmpty) ...[
              const SizedBox(height: 6),
              _sectionLabel('Earlier updates', count: _decided.length),
              const SizedBox(height: 8),
              for (final u in _decided) _updateTile(u),
            ],
          ] else ...[
            if (_canReview) ...[
              _allClearBanner(),
              const SizedBox(height: 12),
            ],
            for (final u in _visible) _updateTile(u),
            if (_hiddenCount > 0) _viewAllButton(),
          ],
        ],
      );

    // The heading sits OUTSIDE the padded content on purpose: the citizen
    // screen runs a divider across the full card width and then insets the
    // update cards under it, which one shared padding could not express.
    final body = widget.heading == null && widget.padding == null
        ? content
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.heading != null) widget.heading!,
              if (widget.padding != null)
                Padding(padding: widget.padding!, child: content)
              else
                content,
            ],
          );

    if (!widget.chrome) return body;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primaryBlue.withValues(alpha: 0.2)),
      ),
      child: body,
    );
  }

  // -- Composer ---------------------------------------------------------------
  //
  // The old version put an unlabelled "Completion" chip between two buttons
  // with nothing to say what it did -- a control the user had to click to find
  // out. It is now a labelled either/or with its consequence spelled out, on
  // its own row, above the actions rather than mixed in among them.
  Widget _composer() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _body,
            maxLines: 4,
            minLines: 2,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(fontSize: 13.5, height: 1.45),
            decoration: InputDecoration(
              hintText: 'What has happened since the last update?',
              hintStyle: const TextStyle(fontSize: 13, color: Colors.black38),
              filled: true,
              fillColor: Colors.white,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              border: _inputBorder(Colors.black12),
              enabledBorder: _inputBorder(Colors.black12),
              focusedBorder: _inputBorder(AppColors.primaryBlue, 1.5),
            ),
          ),
          const SizedBox(height: 10),
          _kindPicker(),
          if (_staged.isNotEmpty) ...[
            const SizedBox(height: 10),
            _stagedStrip(),
          ],
          const SizedBox(height: 10),
          // Wrap so the two controls stack rather than overflow on a 320px
          // phone, and at large text scales on any width.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _sending ? null : _pickPhotos,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryBlue,
                  side: BorderSide(
                    color: AppColors.primaryBlue.withValues(alpha: 0.4),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 17),
                label: Text(_staged.isEmpty
                    ? 'Add photos'
                    : 'Add more (${_staged.length})'),
              ),
              FilledButton.icon(
                onPressed: _sending ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  visualDensity: VisualDensity.compact,
                ),
                icon: _sending
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded, size: 16),
                label: Text(_canReview ? 'Post update' : 'Submit for approval'),
              ),
            ],
          ),
          if (!_canReview) ...[
            const SizedBox(height: 8),
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.visibility_off_outlined,
                    size: 14, color: Colors.black45),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'An admin reviews this before the citizen can see it.',
                    style: TextStyle(fontSize: 11.5, color: Colors.black54),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Progress vs completion, as a labelled either/or with its consequence
  /// stated. Two segments rather than a lone toggle: a single unselected chip
  /// gives no hint that an alternative exists, which is exactly how the old
  /// "Completion" chip read.
  Widget _kindPicker() {
    Widget seg(String label, IconData icon, bool completion) {
      final selected = _completion == completion;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _completion = completion),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.primaryBlue.withValues(alpha: 0.10)
                  : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? AppColors.primaryBlue : Colors.black12,
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 15,
                    color: selected ? AppColors.primaryBlue : Colors.black45),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color:
                          selected ? AppColors.primaryBlue : Colors.black54,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            seg('Progress', Icons.timelapse_rounded, false),
            const SizedBox(width: 8),
            seg('Completion', Icons.verified_rounded, true),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _completion
              ? 'Marks the work finished. Completion photos reach the citizen '
                  'once this is approved.'
              : 'A routine update on work in progress.',
          style: const TextStyle(
            fontSize: 11.5,
            height: 1.35,
            color: Colors.black54,
          ),
        ),
      ],
    );
  }

  Widget _stagedStrip() => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (var i = 0; i < _staged.length; i++)
            Chip(
              avatar: const Icon(Icons.image_outlined, size: 15),
              label: Text(
                'Photo ${i + 1}',
                style: const TextStyle(fontSize: 11.5),
              ),
              onDeleted: () => setState(() => _staged.removeAt(i)),
              visualDensity: VisualDensity.compact,
              backgroundColor: Colors.white,
            ),
        ],
      );

  OutlineInputBorder _inputBorder(Color c, [double w = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: BorderSide(color: c, width: w),
      );

  /// "View all" — shown only when the cap actually hid something, and it says
  /// HOW MANY, because "View all" alone gives no sense of whether one update is
  /// hidden or a dozen.
  Widget _viewAllButton() => Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _openAll,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primaryBlue,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: const Icon(Icons.unfold_more_rounded, size: 16),
          label: Text(
            'View all ${_updates.length} updates',
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        ),
      );

  Widget _sectionLabel(String text, {required int count, Color? color}) => Row(
        children: [
          Text(
            text.toUpperCase(),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.7,
              color: color ?? Colors.black45,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: (color ?? Colors.black45).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: color ?? Colors.black54,
              ),
            ),
          ),
        ],
      );

  /// Shown to a reviewer when nothing is waiting — so an all-decided list reads
  /// as "you are up to date" rather than as a broken queue.
  Widget _allClearBanner() => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.green.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: AppColors.green.withValues(alpha: 0.22)),
        ),
        child: const Row(
          children: [
            Icon(Icons.check_circle_outline_rounded,
                size: 16, color: AppColors.green),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Nothing waiting for review.',
                style: TextStyle(fontSize: 12, color: Colors.black87),
              ),
            ),
          ],
        ),
      );

  Widget _updateTile(_Update u) {
    return Container(
      // Fills its parent rather than shrink-wrapping the text. Without this a
      // card is only as wide as its longest line, so on a tablet or a desktop
      // browser the updates sat as narrow slips beside full-width neighbours —
      // invisible on a phone, where every line already runs to the edge.
      width: double.infinity,
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

/// The full update history, over the screen it was opened from.
///
/// ── Responsiveness ────────────────────────────────────────────────────────
/// One sheet serves a 320px phone, a tablet and a desktop browser, and the
/// three want different things from it:
///
///   * phone   — nearly full height, corners only at the top, edge to edge;
///   * medium  — the same, but capped so it does not become a wall of text;
///   * large   — centred and width-capped, because a line of body text running
///     the width of a 1600px monitor is unreadable regardless of how much room
///     there is.
///
/// The height is a FRACTION of the viewport rather than a constant: a fixed
/// 600px sheet is most of a phone and a third of a desktop.
class _AllUpdatesSheet extends StatelessWidget {
  final List<_Update> updates;

  /// The row renderer from the parent, reused verbatim so a card looks
  /// identical inline and in here.
  final Widget Function(_Update) tile;

  /// True when presented as a centred dialog rather than a bottom sheet.
  ///
  /// Changes three things, all of which look wrong in the other mode: the drag
  /// handle (a gesture that only exists on a sheet), whether the bottom corners
  /// are rounded (a sheet meets the screen edge; a dialog floats clear of it),
  /// and whether the card fills the width it is given.
  final bool floating;

  const _AllUpdatesSheet({
    required this.updates,
    required this.tile,
    this.floating = false,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // Same window-vs-pane trap as the opener: MediaQuery.size is overridden by
    // the citizen web shell, so it cannot decide a presentation question about
    // a route that covers the whole window. `floating` already carries the
    // caller's decision; the fallback measures the view, not the pane.
    final view = View.of(context);
    final wide =
        floating || view.physicalSize.width / view.devicePixelRatio >= 720;

    return SafeArea(
      // A sheet meets the bottom edge and must clear only the home indicator;
      // a dialog floats free and needs BOTH insets respected, or it hangs
      // under the browser chrome at the top.
      top: !floating,
      child: Align(
        // ⚠ bottomCenter is a SHEET property. Left unconditional it also
        // applied inside the Dialog, which is why the centred modal rendered
        // sitting low on the page rather than in the middle of it — Dialog
        // gives its child the full screen minus insetPadding, so the child's
        // own alignment decides where it lands.
        alignment: floating ? Alignment.center : Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: wide ? 620 : double.infinity,
            maxHeight: media.size.height * (wide ? 0.8 : 0.88),
          ),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(
                top: const Radius.circular(18),
                // Rounded all round only when it floats clear of the bottom
                // edge; on a phone it meets the edge and a rounded bottom
                // would show the page through the corners.
                bottom: Radius.circular(wide ? 18 : 0),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle only where dragging is possible.
                if (!floating) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
                  child: Row(
                    children: [
                      const Icon(Icons.timeline_rounded,
                          size: 18, color: AppColors.primaryBlue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Progress updates (${updates.length})',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                        color: Colors.black45,
                        splashRadius: 20,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Flexible + shrinkWrap, so a short history sizes to its
                // content and a long one scrolls inside the maxHeight cap.
                //
                // shrinkWrap is what makes the first half true: a ListView
                // without it takes ALL the height its parent offers, so three
                // updates in a centred dialog left an empty half-screen of
                // white below them. The comment here used to claim the sizing
                // the code did not do.
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
                    itemCount: updates.length,
                    itemBuilder: (_, i) => tile(updates[i]),
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
