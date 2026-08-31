import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// The full-screen photo viewer, shared by every surface that shows report
/// imagery.
///
/// This is the citizen report detail's viewer, lifted here unchanged so the
/// interaction is the SAME one everywhere rather than a second pattern that
/// merely resembles it: pinch/pan zoom, swipe between photos, a counter, dots,
/// and a close chip. Progress updates and completion media used to render bare
/// thumbnails with no tap target at all — a photo of a pothole at 84px tells
/// the officer nothing, and there was no way to get a better look.
///
/// Callers open it with [openMediaViewer] rather than constructing it, because
/// the route matters as much as the widget (see that function).
class MediaViewerScreen extends StatefulWidget {
  final List<String> urls;

  /// Stable per-image cache keys.
  ///
  /// Report media is served by SIGNED url, which carries an expiry in the query
  /// string — so the url changes every time it is minted and is useless as a
  /// cache key. Passing the storage path keeps one cached copy per photo
  /// instead of re-downloading it on each open.
  final List<String> cacheKeys;
  final int initialIndex;

  const MediaViewerScreen({
    super.key,
    required this.urls,
    required this.cacheKeys,
    required this.initialIndex,
  });

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  late final PageController _pageCtrl;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _pageCtrl = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageCtrl,
            itemCount: widget.urls.length,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (_, i) => InteractiveViewer(
              child: Center(
                // ── The plate behind the image ─────────────────────────
                //
                // A PNG or WebP with an alpha channel and dark artwork is
                // INVISIBLE on this black scaffold - it loads, it paints, and
                // there is nothing to see, which reads as a broken viewer
                // rather than as a transparent image. The card behind it does
                // not have the problem because it sits on white.
                //
                // A neutral plate sized to the image fixes that and costs an
                // opaque photo nothing: at BoxFit.contain the photo covers the
                // plate exactly, so it is only ever visible THROUGH the
                // transparent parts of an image that has any.
                child: DecoratedBox(
                  decoration: const BoxDecoration(color: Color(0xFFE5E7EB)),
                  child: CachedNetworkImage(
                    imageUrl: widget.urls[i],
                    cacheKey: widget.cacheKeys[i],
                    fit: BoxFit.contain,
                    placeholder: (context, url) => const Center(
                      child: CircularProgressIndicator(
                        color: Colors.white54,
                        strokeWidth: 2,
                      ),
                    ),
                    errorWidget: (context, url, error) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white54,
                      size: 60,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Top bar
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
                if (widget.urls.length > 1)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_current + 1} / ${widget.urls.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Dots indicator
          if (widget.urls.length > 1)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 24,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (int i = 0; i < widget.urls.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: _current == i ? 20 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: _current == i
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Open the shared viewer on [urls], starting at [initialIndex].
///
/// The ROUTE is the part worth centralising, not just the widget. On WEB these
/// screens render inside the shell's centre column, and a branch navigator
/// bounds the viewer: the barrier stops at the column, leaving the left rail
/// and the sidebar bright either side of a black strip. The root navigator is
/// the whole window.
///
/// `rootNavigator: kIsWeb` rather than a bare `true` so MOBILE takes exactly
/// the path it takes today — there `rootNavigator: false` is what a plain
/// `Navigator.push(context, ...)` already resolves to.
///
/// [cacheKeys] defaults to [urls] for callers whose urls are stable; anything
/// served by a signed url must pass storage paths instead (see
/// [MediaViewerScreen.cacheKeys]).
Future<void> openMediaViewer(
  BuildContext context, {
  required List<String> urls,
  List<String>? cacheKeys,
  int initialIndex = 0,
}) {
  if (urls.isEmpty) return Future<void>.value();
  final keys = cacheKeys ?? urls;
  assert(
    keys.length == urls.length,
    'cacheKeys must line up with urls, one per image',
  );
  return Navigator.of(context, rootNavigator: kIsWeb).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black87,
      pageBuilder: (_, _, _) => MediaViewerScreen(
        urls: urls,
        cacheKeys: keys,
        initialIndex: initialIndex.clamp(0, urls.length - 1),
      ),
      transitionsBuilder: (_, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
    ),
  );
}
