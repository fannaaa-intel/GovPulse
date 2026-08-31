// Preview target: the update/completion photo thumbnail and the shared
// full-screen viewer it opens.
//
//   flutter build web --release -t tool/preview_update_thumbs.dart
//   (serve build/web, then drive with CDP)
//
// The real widgets fetch from Supabase, and the thing being checked here is the
// TAP — thumbnail affordance, then the gallery's zoom/swipe/counter chrome. So
// this mounts the shared viewer against local asset images and reproduces the
// thumbnail's geometry, which is what a screenshot can actually answer.
//
// ?open=1 opens the viewer immediately, so the gallery can be captured without
// synthesising a click over CDP.
import 'dart:convert';


import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'package:govpulse/core/widgets/media_viewer.dart';

// Bundled assets rather than network urls: a preview that depends on the
// network shows broken-image boxes exactly when it is least convenient.
const _assets = [
  'assets/images/report/roadtwo.webp',
  'assets/images/report/bin.webp',
  'assets/images/report/lamppost.webp',
];

/// The assets re-served as data: URIs.
///
/// The shared viewer draws through CachedNetworkImage, which takes a URL and
/// cannot read an `assets/` path — pointing it at one renders the error box,
/// which would make this preview show a failure that the real widget does not
/// have. Encoding the same bytes as data: URIs exercises the viewer's actual
/// image path with no network.
late final List<String> _urls;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _urls = [
    for (final a in _assets)
      'data:image/webp;base64,'
          '${base64Encode((await rootBundle.load(a)).buffer.asUint8List())}',
  ];
  final open = Uri.base.queryParameters['open'] == '1';
  runApp(_App(autoOpen: open));
}

class _App extends StatelessWidget {
  final bool autoOpen;
  const _App({required this.autoOpen});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _Page(autoOpen: autoOpen),
    );
  }
}

class _Page extends StatefulWidget {
  final bool autoOpen;
  const _Page({required this.autoOpen});

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  @override
  void initState() {
    super.initState();
    if (widget.autoOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        openMediaViewer(
          context,
          urls: _urls,
          initialIndex: 1,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEEF1F6),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Update photos — thumbnail affordance',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              const Text(
                'Each thumb carries a zoom glyph and opens the shared gallery '
                'at its own index. Add ?open=1 to capture the viewer.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 18),
              for (final w in const [520.0, 340.0])
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${w.toInt()}px',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.black54)),
                      const SizedBox(height: 6),
                      Container(
                        width: w,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE3E8EF)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Patching started on the eastbound lane.',
                              style: TextStyle(fontSize: 13.5, height: 1.45),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (var i = 0; i < _assets.length; i++)
                                  _Thumb(index: i),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mirrors _UpdateThumb's geometry and chrome, against a local asset.
class _Thumb extends StatelessWidget {
  final int index;
  const _Thumb({required this.index});

  @override
  Widget build(BuildContext context) {
    const size = 84.0;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openMediaViewer(
          context,
          urls: _urls,
          initialIndex: index,
        ),
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                color: const Color(0xFFEEF1F6),
                child: Image.asset(_assets[index], fit: BoxFit.cover),
              ),
              const Positioned(
                right: 3,
                bottom: 3,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0x8A000000),
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(3),
                    child: Icon(
                      Icons.zoom_out_map_rounded,
                      size: 11,
                      color: Colors.white,
                    ),
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
