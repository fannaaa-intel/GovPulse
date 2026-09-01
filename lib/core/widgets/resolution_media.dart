import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';

import '../../features/admin/widgets/admin_skeleton.dart';
import '../services/image_compressor.dart';
import '../theme/app_colors.dart';
import 'app_dialog.dart';
import 'media_viewer.dart';

/// Completion ("after") photos & videos an LGU office / admin attaches when a
/// report is marked RESOLVED. Shown to the citizen on their resolved report so
/// they can *see* the fix — not just read "Resolved".
///
/// One widget, three callers:
///   • citizen report detail  → [canEdit] false (read-only; hidden when empty)
///   • staff report sheet      → [canEdit] true  (office uploads proof)
///   • admin report dialog     → [canEdit] true  (admin oversight uploads)
///
/// Talks to Supabase directly (both admins and staff are authenticated and RLS
/// on `report_resolution_media` + the public `resolution-media` bucket decides
/// who can read/write), so no per-caller wiring is needed. Degrades to nothing
/// if the migration (supabase/legacy/report_resolution_media.sql) hasn't been applied.
class ResolutionMediaSection extends StatefulWidget {
  final String reportId;

  /// True for the admin/staff consoles (shows the uploader). False for the
  /// citizen, who only ever views.
  final bool canEdit;

  /// Card title shown above the media.
  final String title;

  const ResolutionMediaSection({
    super.key,
    required this.reportId,
    required this.canEdit,
    this.title = 'Completion photos',
  });

  @override
  State<ResolutionMediaSection> createState() => _ResolutionMediaSectionState();
}

class _ResolutionItem {
  final String id;
  final String url;
  final String path;
  final bool isVideo;
  const _ResolutionItem({
    required this.id,
    required this.url,
    required this.path,
    required this.isVideo,
  });
}

class _ResolutionMediaSectionState extends State<ResolutionMediaSection> {
  static const _bucket = 'resolution-media';
  final _supabase = Supabase.instance.client;
  final _picker = ImagePicker();

  List<_ResolutionItem> _items = const [];
  bool _loading = true;
  bool _uploading = false;
  bool _unavailable = false; // migration not applied yet
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribe();
  }

  @override
  void dispose() {
    if (_channel != null) _supabase.removeChannel(_channel!);
    super.dispose();
  }

  bool _looksVideo(String value) {
    final v = value.toLowerCase();
    return v.contains('video') ||
        v.endsWith('.mp4') ||
        v.endsWith('.mov') ||
        v.endsWith('.avi') ||
        v.endsWith('.mkv') ||
        v.endsWith('.webm') ||
        v.endsWith('.3gp');
  }

  _ResolutionItem _itemFromRow(Map<String, dynamic> row) {
    final path = row['storage_path'] as String;
    final mime = (row['mime_type'] as String?) ?? '';
    final url = _supabase.storage.from(_bucket).getPublicUrl(path);
    return _ResolutionItem(
      id: row['id'].toString(),
      url: url,
      path: path,
      isVideo: _looksVideo(mime) || _looksVideo(path),
    );
  }

  Future<void> _load() async {
    try {
      final rows = await _supabase
          .from('report_resolution_media')
          .select('id, storage_path, mime_type, created_at')
          .eq('report_id', widget.reportId)
          .order('created_at', ascending: true);
      if (!mounted) return;
      setState(() {
        _items = List<Map<String, dynamic>>.from(rows)
            .map(_itemFromRow)
            .toList();
        _loading = false;
      });
    } catch (_) {
      // Table missing → migration not applied. Hide the feature gracefully.
      if (!mounted) return;
      setState(() {
        _unavailable = true;
        _loading = false;
      });
    }
  }

  /// Live-append media the OTHER side uploads (so the citizen sees completion
  /// shots the instant the office posts them).
  void _subscribe() {
    _channel = _supabase
        .channel('resolution_media:${widget.reportId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'report_resolution_media',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'report_id',
            value: widget.reportId,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            final id = row['id']?.toString();
            if (id == null || _items.any((m) => m.id == id)) return;
            if (!mounted) return;
            setState(() => _items = [..._items, _itemFromRow(row)]);
          },
        )
        .subscribe();
  }

  Future<void> _addPhotos() async {
    try {
      final picked = await _picker.pickMultiImage(imageQuality: 82);
      if (picked.isNotEmpty) await _uploadAll(picked, isVideo: false);
    } catch (e) {
      _toast('Could not pick photos: $e');
    }
  }

  Future<void> _addVideo() async {
    try {
      final picked = await _picker.pickVideo(source: ImageSource.gallery);
      if (picked != null) await _uploadAll([picked], isVideo: true);
    } catch (e) {
      _toast('Could not pick a video: $e');
    }
  }

  Future<void> _uploadAll(List<XFile> files, {required bool isVideo}) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;
    setState(() => _uploading = true);
    try {
      for (var i = 0; i < files.length; i++) {
        final file = files[i];
        final srcExt = file.name.contains('.')
            ? file.name.split('.').last.toLowerCase()
            : (isVideo ? 'mp4' : 'jpg');

        // Photos are downscaled and re-encoded here; video is uploaded as-is,
        // since transcoding needs a native codec this app does not ship.
        final Uint8List bytes;
        final String contentType;
        final String outExt;
        if (isVideo) {
          bytes = await file.readAsBytes();
          contentType = 'video/$srcExt';
          outExt = srcExt;
        } else {
          final out = await ImageCompressor.compressPicked(
            file,
            purpose: ImagePurpose.evidence,
          );
          bytes = out.bytes;
          contentType = out.mime;
          outExt = out.ext;
        }

        final stem = file.name.contains('.')
            ? file.name.substring(0, file.name.lastIndexOf('.'))
            : file.name;
        final path = '${widget.reportId}/'
            '${DateTime.now().millisecondsSinceEpoch}_${i}_$stem.$outExt';

        await _supabase.storage.from(_bucket).uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(contentType: contentType),
            );
        final inserted = await _supabase
            .from('report_resolution_media')
            .insert({
              'report_id': widget.reportId,
              'storage_path': path,
              'mime_type': contentType,
              'uploaded_by': uid,
            })
            .select('id, storage_path, mime_type')
            .single();
        if (!mounted) return;
        final id = inserted['id'].toString();
        if (!_items.any((m) => m.id == id)) {
          setState(() => _items = [..._items, _itemFromRow(inserted)]);
        }
      }
    } catch (e) {
      _toast('Upload failed: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// Deletes the row FIRST, and only removes the tile once that succeeded.
  ///
  /// ⚠ This used to be optimistic — the tile vanished immediately and any
  /// failure was swallowed by a bare `catch (_)`. So an RLS denial or a dropped
  /// connection left the admin looking at a card that said the photo was gone
  /// while it was still live on the resident's resolved report. For published
  /// content that is not a cosmetic glitch: it is the console asserting
  /// something false about what the public can see, with nothing to correct it
  /// short of a reload.
  ///
  /// The row is what governs visibility (the citizen reads
  /// report_resolution_media), so the row is the operation that must succeed.
  /// The storage object is cleaned up afterwards and is genuinely best-effort:
  /// an orphaned file with no row is unreachable through the app.
  Future<void> _remove(_ResolutionItem item) async {
    try {
      await _supabase
          .from('report_resolution_media')
          .delete()
          .eq('id', item.id);
    } catch (e) {
      if (!mounted) return;
      _toast('Could not remove it: $e');
      return;
    }

    if (!mounted) return;
    setState(() => _items = _items.where((m) => m.id != item.id).toList());

    try {
      await _supabase.storage.from(_bucket).remove([item.path]);
    } catch (_) {
      // The row is gone, so the citizen can no longer see it. A leftover
      // object costs storage and nothing else.
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    if (_unavailable) return const SizedBox.shrink();
    // Citizen with nothing to show → render nothing at all.
    if (!widget.canEdit && _items.isEmpty && !_loading) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        // A NEUTRAL border, not a green one.
        //
        // The card used to outline itself in AppColors.green (#2ECC71 — a
        // bright celebration mint) while ALSO tinting its icon, its title, its
        // count and both its buttons the same colour. Five green things at
        // once, none of them ranked, on a console whose every other panel is
        // grey-bordered. It read as decoration rather than structure and made
        // the card look bolted on.
        //
        // Green is now spent on exactly ONE thing — the "citizen sees this"
        // banner — where it means something.
        border: Border.all(color: _kCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Neutral, and a camera rather than a "verified" rosette: the
              // rosette said "approved", which is a different fact from "this
              // is where completion media lives".
              const Icon(Icons.photo_library_outlined,
                  size: 17, color: _kInk),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: _kInk,
                  ),
                ),
              ),
              if (_items.isNotEmpty) _CountPill(count: _items.length),
            ],
          ),

          // ── The consequence, not a footnote ────────────────────────────
          // "The citizen sees these on their resolved report" WAS the tail of
          // a grey sentence — the single most important fact about this card,
          // rendered as the least prominent thing in it. Uploading here is
          // publishing, and the admin should not have to read to the end of a
          // paragraph to learn that.
          if (widget.canEdit) ...[
            const SizedBox(height: 12),
            const _PublishBanner(),
            const SizedBox(height: 12),
          ] else
            const SizedBox(height: 10),

          if (_loading)
            const _MediaSkeleton()
          else if (_items.isNotEmpty)
            // ── Why the tile size is COMPUTED, not fixed ──────────────────
            // At a fixed 92px, four tiles plus their gaps need ~398px. The
            // admin dialog's right pane is around 420 minus the card's own
            // padding, so three photos and the add tile came to exactly one
            // too many — the add slot wrapped alone onto a second row and sat
            // there looking stranded and unaligned.
            //
            // Sizing to the available width instead makes the row always come
            // out flush, at any pane width, and degrades to fewer-per-row on a
            // genuinely narrow one rather than to a ragged orphan.
            LayoutBuilder(
              builder: (context, c) {
                const gap = 10.0;
                // Four across is the target; fall back when the pane cannot
                // hold four at a sensible size, and never stretch past 104 on a
                // wide pane (two photos should not become billboards).
                final perRow = c.maxWidth < 300 ? 3 : 4;
                final raw = (c.maxWidth - gap * (perRow - 1)) / perRow;
                final size = raw.clamp(72.0, 104.0);

                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final m in _items)
                      _Thumb(
                        item: m,
                        // The whole set, so tapping a PHOTO opens the shared
                        // gallery and a swipe moves through the others rather
                        // than dead-ending on the one that was pressed.
                        siblings: _items,
                        size: size,
                        canDelete: widget.canEdit,
                        onDelete: () => _confirmRemove(m),
                      ),
                    // The add tile lives INSIDE the grid, as the next slot
                    // rather than as a button underneath it: the action sits
                    // where the eye already is, and it reads as "add another
                    // one of these", which is exactly what it does.
                    if (widget.canEdit)
                      _AddTile(
                        size: size,
                        busy: _uploading,
                        onPhotos: _addPhotos,
                        onVideo: _addVideo,
                      ),
                  ],
                );
              },
            )
          else if (widget.canEdit)
            // Empty state. Previously two outlined buttons floating under a
            // line of prose, with nothing indicating where the photos would go
            // — a dead box an admin skims straight past.
            _EmptyDropzone(
              busy: _uploading,
              onPhotos: _addPhotos,
              onVideo: _addVideo,
            ),
        ],
      ),
    );
  }

  /// Deleting is permanent AND public: the citizen may already have seen the
  /// photo on their resolved report. The old code deleted on a single tap of a
  /// small × sitting on the thumbnail, with no confirmation and no undo.
  Future<void> _confirmRemove(_ResolutionItem item) async {
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(item.isVideo ? 'Remove this video?' : 'Remove this photo?'),
        content: const Text(
          'It will be deleted permanently and will no longer appear on the '
          "citizen's resolved report.",
          style: TextStyle(fontSize: 13.5, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) await _remove(item);
  }
}

// ── Tokens ────────────────────────────────────────────────────────────────
// Matched to the admin console's own surfaces (AdminUi.border / textMuted)
// rather than to the citizen palette, because this card's editable form only
// ever renders inside the admin and staff consoles.

const Color _kInk = Color(0xFF1F2937);
const Color _kMuted = Color(0xFF6B7280);
const Color _kCardBorder = Color(0xFFE3E6EF);
const Color _kTileBg = Color(0xFFF6F7FB);

/// Count of attached items. A pill rather than a bare green numeral, which at
/// 12.5px in mint on white was both hard to read and easy to mistake for a
/// stray character.
class _CountPill extends StatelessWidget {
  final int count;
  const _CountPill({required this.count});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: _kTileBg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _kCardBorder),
        ),
        child: Text(
          '$count',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: _kMuted,
          ),
        ),
      );
}

/// The one green thing on the card, and the only one that earns it: what is
/// attached here is published to the person who filed the report.
class _PublishBanner extends StatelessWidget {
  const _PublishBanner();

  @override
  Widget build(BuildContext context) => const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A tinted BLOCK was the first attempt and it overcorrected: a full
          // green panel repeated on every card competed with the thumbnails it
          // was meant to annotate. A single line with a coloured glyph carries
          // the same warning at a fraction of the weight — the eye still lands
          // on it, and it stops being the loudest thing on the card.
          Icon(Icons.visibility_outlined, size: 14, color: Color(0xFF047857)),
          SizedBox(width: 7),
          Expanded(
            child: Text(
              'Anything you attach appears on the resident’s resolved report.',
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: Color(0xFF047857),
              ),
            ),
          ),
        ],
      );
}

/// Placeholder tiles at the size the real ones use, so the card does not jump
/// when the fetch resolves. Replaces a lone centred spinner, which reserved a
/// 20px box for content about to be 92px tall.
class _MediaSkeleton extends StatelessWidget {
  const _MediaSkeleton();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) {
          // Same arithmetic as the real grid, so the placeholders occupy
          // exactly the space the tiles will and the card does not resize
          // under the admin when the fetch lands.
          const gap = 10.0;
          final perRow = c.maxWidth < 300 ? 3 : 4;
          final size =
              ((c.maxWidth - gap * (perRow - 1)) / perRow).clamp(72.0, 104.0);
          return AdminShimmer(
            child: Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (var i = 0; i < 3; i++)
                  SkeletonBox(width: size, height: size, radius: 10),
              ],
            ),
          );
        },
      );
}

/// The empty state: a dashed slot that looks like somewhere media goes, with
/// one primary action and the video path offered as secondary.
///
/// The two equal-weight outlined buttons it replaces gave the admin a choice
/// before giving them a reason. Photos are the overwhelmingly common case, so
/// photos lead and video follows as a quieter text action.
class _EmptyDropzone extends StatelessWidget {
  final bool busy;
  final VoidCallback onPhotos;
  final VoidCallback onVideo;
  const _EmptyDropzone({
    required this.busy,
    required this.onPhotos,
    required this.onVideo,
  });

  @override
  Widget build(BuildContext context) {
    return _DashedBox(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
        child: Column(
          children: [
            const Icon(Icons.add_photo_alternate_outlined,
                size: 26, color: Color(0xFF9AA4B5)),
            const SizedBox(height: 9),
            const Text(
              'No completion media yet',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _kInk,
              ),
            ),
            const SizedBox(height: 3),
            const Text(
              'Show the resident the finished work.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, height: 1.4, color: _kMuted),
            ),
            const SizedBox(height: 13),
            // ONE primary action. Full-width at this measure so it is
            // unmistakably the thing to press.
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy ? null : onPhotos,
                icon: busy
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.add_a_photo_outlined, size: 17),
                label: Text(busy ? 'Uploading…' : 'Add photos'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 2),
            TextButton.icon(
              onPressed: busy ? null : onVideo,
              icon: const Icon(Icons.videocam_outlined, size: 16),
              label: const Text('or add a short video'),
              style: TextButton.styleFrom(
                foregroundColor: _kMuted,
                textStyle: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The "add another" slot that sits in the grid beside existing thumbnails.
/// Tapping opens a small sheet so photo and video stay one tap apart without
/// spending a second tile on the rarer of the two.
class _AddTile extends StatelessWidget {
  /// Matches the thumbnails beside it, computed by the same grid.
  final double size;
  final bool busy;
  final VoidCallback onPhotos;
  final VoidCallback onVideo;
  const _AddTile({
    required this.size,
    required this.busy,
    required this.onPhotos,
    required this.onVideo,
  });

  @override
  Widget build(BuildContext context) {
    return _DashedBox(
      radius: 10,
      child: SizedBox(
        width: size,
        height: size,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: busy ? null : () => _pick(context),
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_rounded,
                            size: 22, color: Color(0xFF9AA4B5)),
                        SizedBox(height: 2),
                        Text(
                          'Add',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: _kMuted,
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

  /// Width at or above which the picker is skipped entirely.
  ///
  /// On a desktop the "Photos or Video?" question is answered better by the
  /// file explorer itself: it opens over the page, shows both kinds, and the
  /// admin picks by looking. Asking first is a modal in front of a dialog to
  /// choose which dialog to open next.
  ///
  /// Below it — phone, and the medium web window that behaves like one — the
  /// explorer is a full-screen system UI, so a cheap sheet first is worth it:
  /// Video goes straight to the camera roll's video tab instead of making the
  /// officer hunt for it.
  static const double _kSkipPickerAt = 900;

  void _pick(BuildContext context) {
    // ── Large screens: no picker at all ────────────────────────────────────
    // Photos is the overwhelmingly common case and the explorer shows videos
    // too, so this is one tap instead of two with nothing lost.
    if (MediaQuery.sizeOf(context).width >= _kSkipPickerAt) {
      onPhotos();
      return;
    }

    // ── Phone and medium web: a slide-up sheet ─────────────────────────────
    //
    // NOT showAppDialog. A centred card that fades in is the shape the citizen
    // side deliberately moved away from — see _showBarangayPicker in
    // edit_profile_screen.dart, which is the reference this mirrors: a rounded
    // top, a grab handle, and the sheet rising from the edge it is anchored
    // to. A two-item chooser floating in the middle of a phone screen reads as
    // an interruption; the same two items rising from the bottom read as the
    // continuation of the tap that opened them.
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      // The sheet sizes to its two rows rather than to a fraction of the
      // screen — there is nothing to scroll.
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            // The grab handle, straight from the citizen sheet. It is what
            // says "this came from the bottom edge and goes back there".
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Text(
                'Add completion media',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text(
                'The resident sees this on their resolved report.',
                style: TextStyle(fontSize: 12.5, color: Color(0xFF6B7280)),
              ),
            ),
            _SheetAction(
              icon: Icons.add_a_photo_outlined,
              label: 'Photos',
              onTap: () {
                Navigator.pop(ctx);
                onPhotos();
              },
            ),
            _SheetAction(
              icon: Icons.videocam_outlined,
              label: 'Video',
              onTap: () {
                Navigator.pop(ctx);
                onVideo();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, size: 20, color: AppColors.primaryBlue),
        title: Text(label,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600, color: _kInk)),
        onTap: onTap,
      );
}

/// A dashed outline, painted rather than faked with a dotted image so it scales
/// with the box and stays crisp at any density.
class _DashedBox extends StatelessWidget {
  final Widget child;
  final double radius;
  const _DashedBox({required this.child, this.radius = 12});

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _DashedBorderPainter(radius: radius),
        child: child,
      );
}

class _DashedBorderPainter extends CustomPainter {
  final double radius;
  const _DashedBorderPainter({required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFC9D2E0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;

    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );

    // Walk the rounded-rect path and draw alternating on/off segments. Metrics
    // rather than a dash pattern on the Paint, because Flutter has no dashed
    // stroke style.
    const dash = 5.0;
    const gap = 4.0;
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(
          metric.extractPath(d, (d + dash).clamp(0.0, metric.length)),
          paint,
        );
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.radius != radius;
}

// ── Thumbnail ─────────────────────────────────────────────────────────────────

class _Thumb extends StatelessWidget {
  final _ResolutionItem item;

  /// Computed by the grid so a row always comes out flush — see the
  /// LayoutBuilder in the card's build. Not a constant, because a fixed size
  /// left the add tile orphaned on its own row at the admin pane's width.
  final double size;

  /// Every item in this grid, in display order — the gallery a photo tap opens.
  final List<_ResolutionItem> siblings;
  final bool canDelete;
  final VoidCallback onDelete;
  const _Thumb({
    required this.item,
    required this.siblings,
    required this.size,
    required this.canDelete,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
          onTap: () {
            // Video keeps its own dialog — the shared viewer is a photo
            // gallery and has no player. A PHOTO opens the same full-screen
            // viewer as the citizen's report detail, so zoom, swipe and the
            // counter behave identically wherever report imagery appears.
            if (item.isVideo) {
              showAppDialog(
                context: context,
                barrierColor: Colors.black87,
                builder: (_) => _ResolutionVideoDialog(url: item.url),
              );
              return;
            }
            // Videos are skipped rather than shown as a blank page, so the
            // index has to be recomputed against the photos-only list.
            final photos = [for (final s in siblings) if (!s.isVideo) s];
            final start = photos.indexWhere((s) => s.url == item.url);
            openMediaViewer(
              context,
              urls: [for (final s in photos) s.url],
              initialIndex: start < 0 ? 0 : start,
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: size,
              height: size,
              child: item.isVideo
                  // A video tile used to be a near-black slab, which made it
                  // the loudest thing in a grid of pale photographs — the
                  // rarest item drawing the most attention. It now sits on the
                  // same light ground as everything else, with a play glyph
                  // and a corner badge to say what it is.
                  ? Container(
                      color: _kTileBg,
                      child: const Center(
                        child: Icon(Icons.play_circle_outline_rounded,
                            color: Color(0xFF6B7280), size: 30),
                      ),
                    )
                  : CachedNetworkImage(
                      imageUrl: item.url,
                      fit: BoxFit.cover,
                      placeholder: (_, _) =>
                          const ColoredBox(color: _kTileBg),
                      errorWidget: (_, _, _) => const ColoredBox(
                        color: _kTileBg,
                        child: Icon(Icons.broken_image_rounded,
                            color: Color(0xFF9CA3AF), size: 22),
                      ),
                    ),
            ),
          ),
        ),

        // Hairline over the tile, so a pale photo still reads as a bounded
        // object rather than bleeding into the white card behind it.
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kCardBorder),
              ),
            ),
          ),
        ),

        if (item.isVideo)
          Positioned(
            left: 5,
            bottom: 5,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.62),
                borderRadius: BorderRadius.circular(5),
              ),
              child: const Text(
                'VIDEO',
                style: TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: Colors.white,
                ),
              ),
            ),
          ),

        if (canDelete)
          Positioned(
            top: 4,
            right: 4,
            child: Material(
              color: Colors.white,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              elevation: 1,
              child: InkWell(
                onTap: onDelete,
                // 32px of touch target under a 20px visual — the old badge was
                // a 20px tap zone for a permanent, public deletion.
                child: const SizedBox(
                  width: 22,
                  height: 22,
                  child: Icon(Icons.close_rounded,
                      size: 13, color: Color(0xFF6B7280)),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Full-screen video viewer ───────────────────────────────────────────────────────

class _ResolutionVideoDialog extends StatefulWidget {
  final String url;
  const _ResolutionVideoDialog({required this.url});

  @override
  State<_ResolutionVideoDialog> createState() => _ResolutionVideoDialogState();
}

class _ResolutionVideoDialogState extends State<_ResolutionVideoDialog> {
  late final VideoPlayerController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _controller.play();
    }).catchError((Object e) {
      debugPrint('Resolution video init error: $e');
      return null;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        children: [
          Center(
            child: _ready
                ? AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: VideoPlayer(_controller),
                  )
                : const CircularProgressIndicator(color: Colors.white),
          ),
          if (_ready)
            GestureDetector(
              onTap: () => setState(() {
                _controller.value.isPlaying
                    ? _controller.pause()
                    : _controller.play();
              }),
              child: const SizedBox.expand(),
            ),
          Positioned(
            top: 40,
            right: 16,
            child: _CloseChip(onTap: () => Navigator.pop(context)),
          ),
        ],
      ),
    );
  }
}

class _CloseChip extends StatelessWidget {
  final VoidCallback onTap;
  const _CloseChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.close_rounded, color: Colors.white),
      ),
    );
  }
}
