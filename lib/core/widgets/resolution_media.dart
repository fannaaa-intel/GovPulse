import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';

import '../theme/app_colors.dart';

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
/// if the migration (supabase/report_resolution_media.sql) hasn't been applied.
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
        final bytes = await file.readAsBytes();
        final ext = file.name.contains('.')
            ? file.name.split('.').last.toLowerCase()
            : (isVideo ? 'mp4' : 'jpg');
        final contentType = isVideo ? 'video/$ext' : 'image/$ext';
        final path =
            '${widget.reportId}/${DateTime.now().millisecondsSinceEpoch}_${i}_${file.name}';

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

  Future<void> _remove(_ResolutionItem item) async {
    setState(() => _items = _items.where((m) => m.id != item.id).toList());
    try {
      await _supabase
          .from('report_resolution_media')
          .delete()
          .eq('id', item.id);
      await _supabase.storage.from(_bucket).remove([item.path]);
    } catch (_) {
      // Best-effort; the row is what matters for display.
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.green.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_rounded,
                  size: 18, color: AppColors.green),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2937),
                  ),
                ),
              ),
              if (_items.isNotEmpty)
                Text(
                  '${_items.length}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.green,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            widget.canEdit
                ? 'Attach "after" photos or a short video of the completed work. The citizen sees these on their resolved report.'
                : 'Photos from the team after resolving your report.',
            style: const TextStyle(
                fontSize: 12, color: Color(0xFF6B7280), height: 1.4),
          ),
          if (_loading) ...[
            const SizedBox(height: 14),
            const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ] else if (_items.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final m in _items)
                  _Thumb(
                    item: m,
                    canDelete: widget.canEdit,
                    onDelete: () => _remove(m),
                  ),
              ],
            ),
          ],
          if (widget.canEdit) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _uploading ? null : _addPhotos,
                  icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                  label: const Text('Add photos'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.green,
                    side: BorderSide(
                        color: AppColors.green.withValues(alpha: 0.5)),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _uploading ? null : _addVideo,
                  icon: const Icon(Icons.videocam_outlined, size: 18),
                  label: const Text('Add video'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.green,
                    side: BorderSide(
                        color: AppColors.green.withValues(alpha: 0.5)),
                  ),
                ),
                if (_uploading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── Thumbnail ─────────────────────────────────────────────────────────────────

class _Thumb extends StatelessWidget {
  final _ResolutionItem item;
  final bool canDelete;
  final VoidCallback onDelete;
  const _Thumb({
    required this.item,
    required this.canDelete,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
          onTap: () {
            showDialog(
              context: context,
              barrierColor: Colors.black87,
              builder: (_) => item.isVideo
                  ? _ResolutionVideoDialog(url: item.url)
                  : _ResolutionImageDialog(url: item.url),
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 92,
              height: 92,
              child: item.isVideo
                  ? Container(
                      color: const Color(0xFF1F2937),
                      child: const Center(
                        child: Icon(Icons.play_circle_fill_rounded,
                            color: Colors.white70, size: 34),
                      ),
                    )
                  : CachedNetworkImage(
                      imageUrl: item.url,
                      fit: BoxFit.cover,
                      placeholder: (_, _) =>
                          Container(color: const Color(0xFFF3F4F6)),
                      errorWidget: (_, _, _) => const ColoredBox(
                        color: Color(0xFFF3F4F6),
                        child: Icon(Icons.broken_image_rounded,
                            color: Color(0xFF9CA3AF), size: 22),
                      ),
                    ),
            ),
          ),
        ),
        if (canDelete)
          Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
              onTap: onDelete,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close_rounded,
                    size: 14, color: Colors.white),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Full-screen viewers ───────────────────────────────────────────────────────

class _ResolutionImageDialog extends StatelessWidget {
  final String url;
  const _ResolutionImageDialog({required this.url});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain),
            ),
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
