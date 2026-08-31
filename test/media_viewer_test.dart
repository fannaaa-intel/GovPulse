import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/core/widgets/media_viewer.dart';

/// The shared full-screen photo viewer.
///
/// It exists because progress-update and completion thumbnails rendered at
/// 84px with no tap target at all — an officer looking at a pothole had no way
/// to see it properly. Rather than write a second viewer, the citizen report
/// detail's was lifted here so every surface opens the SAME one.
///
/// These tests pin the gallery behaviour that makes it worth sharing: the
/// starting index, swiping between photos, and the chrome that only makes
/// sense for more than one image.
///
/// NOTE ON PUMPING: these use bounded `pump`s rather than `pumpAndSettle`.
/// CachedNetworkImage holds a request open against the test HttpClient (which
/// returns 400 for everything), so the tree never reaches a quiet frame and
/// pumpAndSettle times out after 10 minutes. 400ms clears the route
/// transition, which is all these assertions depend on.
void main() {
  // A real network fetch would 400 in a test; the viewer is being checked for
  // its gallery mechanics, not its decoding, and CachedNetworkImage renders its
  // placeholder/error box happily without a server.
  const urls = [
    'https://example.invalid/a.jpg',
    'https://example.invalid/b.jpg',
    'https://example.invalid/c.jpg',
  ];

  Widget host({required List<String> urls, int initialIndex = 0}) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => openMediaViewer(
                context,
                urls: urls,
                initialIndex: initialIndex,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  group('MediaViewerScreen', () {
    testWidgets('opens at the tapped photo, not always the first',
        (tester) async {
      // The bug this prevents: handing the viewer one url instead of the set,
      // or ignoring the index, so every thumbnail opens photo 1.
      await tester.pumpWidget(host(urls: urls, initialIndex: 2));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('3 / 3'), findsOneWidget);
    });

    testWidgets('swiping moves to the next photo', (tester) async {
      await tester.pumpWidget(host(urls: urls));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('1 / 3'), findsOneWidget);

      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('2 / 3'), findsOneWidget,
          reason: 'a swipe must move through the gallery');
    });

    testWidgets('a single photo shows no counter and no dots', (tester) async {
      // Chrome that reads as "1 / 1" is noise — there is nothing to page to.
      await tester.pumpWidget(host(urls: const ['https://example.invalid/a.jpg']));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('/'), findsNothing);
      expect(find.byType(InteractiveViewer), findsOneWidget,
          reason: 'zoom still applies to a lone photo');
    });

    testWidgets('close chip dismisses the viewer', (tester) async {
      await tester.pumpWidget(host(urls: urls));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(MediaViewerScreen), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(MediaViewerScreen), findsNothing);
    });

    testWidgets('an empty list opens nothing at all', (tester) async {
      // Guards the caller that maps over an update with no photos.
      await tester.pumpWidget(host(urls: const []));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(MediaViewerScreen), findsNothing);
    });

    testWidgets('an out-of-range index is clamped rather than throwing',
        (tester) async {
      await tester.pumpWidget(host(urls: urls, initialIndex: 99));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('3 / 3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
