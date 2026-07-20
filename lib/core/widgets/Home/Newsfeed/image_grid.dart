import 'package:flutter/material.dart';
import 'news_feed_helpers.dart';
import 'package:cached_network_image/cached_network_image.dart';

Widget buildImageGrid(
  double width,
  int imageCount, {
  List<String> imageUrls = const [],
  ValueChanged<int>? onImageTap,
}) {
  if (imageCount <= 0) return const SizedBox.shrink();
  final extraCount = imageCount - 4;
  final gap = width * 0.015;
  final radius = width * 0.025;

  Widget tappable(Widget child, int index) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onImageTap == null ? null : () => onImageTap(index),
    child: child,
  );

  Widget cell(int index, {bool overlay = false}) {
    final img = imageUrls.length > index
        ? CachedNetworkImage(
            imageUrl: imageUrls[index],
            fit: BoxFit.cover,
            placeholder: (context, url) => buildImagePlaceholder(width),
            errorWidget: (context, url, error) => buildImagePlaceholder(width),
          )
        : buildImagePlaceholder(width);
    return Expanded(
      child: AspectRatio(
        aspectRatio: 1,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: tappable(
            Stack(
              fit: StackFit.expand,
              children: [
                img,
                if (overlay)
                  Container(
                    color: Colors.black.withValues(alpha: 0.55),
                    alignment: Alignment.center,
                    child: Text(
                      '+$extraCount',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: width * 0.075,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
            index,
          ),
        ),
      ),
    );
  }

  if (imageCount == 1) {
    final img = imageUrls.isNotEmpty
        ? CachedNetworkImage(
            imageUrl: imageUrls[0],
            fit: BoxFit.cover,
            placeholder: (context, url) => buildImagePlaceholder(width),
            errorWidget: (context, url, error) => buildImagePlaceholder(width),
          )
        : buildImagePlaceholder(width);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: tappable(AspectRatio(aspectRatio: 16 / 9, child: img), 0),
    );
  }
  if (imageCount == 2) {
    return Row(
      children: [
        cell(0),
        SizedBox(width: gap),
        cell(1),
      ],
    );
  }
  if (imageCount == 3) {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: tappable(
            AspectRatio(
              aspectRatio: 16 / 9,
              child: imageUrls.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: imageUrls[0],
                      fit: BoxFit.cover,
                      placeholder: (context, url) =>
                          buildImagePlaceholder(width),
                      errorWidget: (context, url, error) =>
                          buildImagePlaceholder(width),
                    )
                  : buildImagePlaceholder(width),
            ),
            0,
          ),
        ),
        SizedBox(height: gap),
        Row(
          children: [
            cell(1),
            SizedBox(width: gap),
            cell(2),
          ],
        ),
      ],
    );
  }
  return Column(
    children: [
      Row(
        children: [
          cell(0),
          SizedBox(width: gap),
          cell(1),
        ],
      ),
      SizedBox(height: gap),
      Row(
        children: [
          cell(2),
          SizedBox(width: gap),
          cell(3, overlay: extraCount > 0),
        ],
      ),
    ],
  );
}

void openImageViewer(
  BuildContext context,
  int imageCount,
  int initialIndex, {
  List<String> urls = const [],
}) {
  Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, _, _) => _ImageViewer(
        imageCount: imageCount,
        initialIndex: initialIndex,
        urls: urls,
      ),
      transitionsBuilder: (_, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
    ),
  );
}

class _ImageViewer extends StatefulWidget {
  final int imageCount;
  final int initialIndex;
  final List<String> urls;

  const _ImageViewer({
    required this.imageCount,
    required this.initialIndex,
    this.urls = const [],
  });

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer> {
  late final PageController _pageController;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// One page of the viewer.
  ///
  /// [wide] letterboxes the image at its natural aspect ratio, the way a
  /// desktop viewer should. Narrow keeps the phone treatment — a square frame
  /// filled edge to edge — which is the right trade when the viewport is a
  /// palm-sized rectangle and matches how the grid thumbnails crop.
  Widget _page({
    required double width,
    required bool wide,
    required int index,
  }) {
    final radius = BorderRadius.circular(width * 0.02);
    final missing = widget.urls.length <= index;

    Widget placeholder() => Container(
      color: const Color(0xFF374151),
      child: const Center(
        child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2),
      ),
    );
    Widget glyph(IconData icon) =>
        Icon(icon, size: width * 0.25, color: const Color(0xFF9CA3AF));

    if (wide) {
      return Padding(
        padding: EdgeInsets.all(width * 0.04),
        child: missing
            ? glyph(Icons.image_outlined)
            : ClipRRect(
                borderRadius: radius,
                child: CachedNetworkImage(
                  imageUrl: widget.urls[index],
                  // contain, not cover: no crop, whatever shape the photo is.
                  fit: BoxFit.contain,
                  placeholder: (context, url) => SizedBox(
                    width: width * 0.6,
                    height: width * 0.6,
                    child: placeholder(),
                  ),
                  errorWidget: (context, url, error) =>
                      glyph(Icons.broken_image_outlined),
                ),
              ),
      );
    }

    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        margin: EdgeInsets.all(width * 0.04),
        decoration: BoxDecoration(
          color: const Color(0xFF374151),
          borderRadius: radius,
        ),
        child: missing
            ? glyph(Icons.image_outlined)
            : ClipRRect(
                borderRadius: radius,
                child: CachedNetworkImage(
                  imageUrl: widget.urls[index],
                  fit: BoxFit.cover,
                  placeholder: (context, url) => placeholder(),
                  errorWidget: (context, url, error) =>
                      glyph(Icons.broken_image_outlined),
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // This viewer is fullscreen, so it proportions against the SHORTEST side
    // rather than the width: an icon at 25% of a landscape width (~211dp) would
    // be most of a ~390dp-tall screen, while 25% of the shortest side is the
    // same comfortable size whichever way the phone is held. Portrait is
    // unchanged — there the width IS the shortest side.
    //
    // CLAMPED to 480 (the same ceiling the rest of the app sizes against),
    // because chrome is chrome: a close button should be thumb-sized, not a
    // fraction of the display. Unclamped, a 1291x888 browser window put the
    // counter at 30pt inside a 93px disc — the controls read as the content.
    // Every phone's shortest side is already under 480, so this is a no-op
    // there and only bites on tablets and desktop.
    final size = MediaQuery.of(context).size;
    final width = size.shortestSide.clamp(0.0, 480.0);

    // Desktop/web gets the image at its NATURAL aspect ratio, letterboxed into
    // the viewport. The square-crop below is a phone compromise — on a wide
    // screen there is room to show the whole photo, and cropping a portrait
    // shot to a square is the one thing an image viewer must not do.
    final wide = size.width >= kCommentsDialogBreakpoint;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          PageView.builder(
            controller: _pageController,
            itemCount: widget.imageCount,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (_, index) => InteractiveViewer(
              minScale: 1.0,
              maxScale: 4.0,
              child: Center(
                child: _page(width: width, wide: wide, index: index),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  width * 0.04,
                  width * 0.025,
                  width * 0.025,
                  0,
                ),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: width * 0.035,
                        vertical: width * 0.015,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(width * 0.04),
                      ),
                      child: Text(
                        '${_current + 1} / ${widget.imageCount}',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: width * 0.034,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        padding: EdgeInsets.all(width * 0.022),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: width * 0.06,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
