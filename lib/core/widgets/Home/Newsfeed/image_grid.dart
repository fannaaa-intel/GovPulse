import 'package:flutter/material.dart';
import 'news_feed_helpers.dart';

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
        ? Image.network(
            imageUrls[index],
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => buildImagePlaceholder(width),
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
        ? Image.network(
            imageUrls[0],
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => buildImagePlaceholder(width),
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
                  ? Image.network(
                      imageUrls[0],
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => buildImagePlaceholder(width),
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

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
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
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Container(
                    margin: EdgeInsets.all(width * 0.04),
                    decoration: BoxDecoration(
                      color: const Color(0xFF374151),
                      borderRadius: BorderRadius.circular(width * 0.02),
                    ),
                    child: widget.urls.length > index
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(width * 0.02),
                            child: Image.network(
                              widget.urls[index],
                              fit: BoxFit.cover,
                            ),
                          )
                        : Icon(
                            Icons.image_outlined,
                            size: width * 0.25,
                            color: const Color(0xFF9CA3AF),
                          ),
                  ),
                ),
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
