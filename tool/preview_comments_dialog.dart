// Dev-only harness for the COMMENTS DIALOG's web proportions.
//
//   flutter run -d web-server --web-port 57813 -t tool/preview_comments_dialog.dart
//
// What it is for: the dialog's width, height and insets are read off
// `MediaQuery.size` inside `showCommentsSheet`, and the dialog is pushed on the
// ROOT navigator — so the only honest way to see a given viewport is to make
// the window that size (CDP `Emulation.setDeviceMetricsOverride`) and shoot it.
// Sizes worth checking:
//
//   • 1512x945 — ordinary desktop browser. 700 wide, ~889 tall (Facebook's
//                proportions: a tall column, not a phone sheet in the middle
//                of the page).
//   • 1024x768 — small laptop / landscape tablet. Still 700 wide; the height
//                clamps to the window so the composer never clips.
//   •  700x900 — narrow window, above the 600 dialog breakpoint. The width cap
//                gives way and the dialog tracks the window minus its insets.
//   • 1200x520 — wide but short: the split layout, post beside thread.
//
// Nothing signs in — the canned post below is not in the provider, so the sheet
// falls back to it (`_livePost`'s orElse) and the thread renders from this map.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:govpulse/core/widgets/Home/Newsfeed/comments_sheet.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://vxvflhjbafqwehuxnmeq.supabase.co',
    anonKey: 'sb_publishable_ZBDaQPQdFyC5kOHGbce9Ig_zdtIi6Mo',
  );
  runApp(const _PreviewApp());
}

Map<String, dynamic> _post() => {
  'id': 'preview-post',
  'author': 'LGU Aparri',
  'authorDept': '',
  'authorPhotoUrl': null,
  'isOfficial': true,
  'tag': 'LGU Aparri',
  'barangay': '',
  'timestamp': DateTime.now().subtract(const Duration(days: 2)),
  'title': 'APPLY NOW!!!',
  'body':
      'HELLO APARRIANOS\nAPPLY NOW!!!\nTechnical Education and Skills '
      'Development Authority - Aparri Polytechnic Institute (TESDA-API)\n'
      'Announcement Courtesy of TESDA-API',
  'imageCount': 0,
  'imageUrls': <String>[],
  'likes': '1',
  'commentCount': 2,
  'comments': <Map<String, dynamic>>[
    {
      'id': 'c1',
      'author': 'Mark Reduca',
      'authorId': 'u1',
      'text': 'Is walk-in application allowed po?',
      'timestamp': DateTime.now().subtract(const Duration(hours: 5)),
      'likes': 0,
      'replies': <Map<String, dynamic>>[],
    },
    {
      'id': 'c2',
      'author': 'Ana Marie Baldos',
      'authorId': 'u2',
      'text': 'Thank you for sharing this — sending it to my nephew.',
      'timestamp': DateTime.now().subtract(const Duration(hours: 9)),
      'likes': 3,
      'replies': <Map<String, dynamic>>[],
    },
  ],
};

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFF3F4F6),
        body: Builder(
          builder: (context) {
            final size = MediaQuery.of(context).size;
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'viewport ${size.width.toStringAsFixed(0)}'
                    'x${size.height.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => showCommentsSheet(
                      context,
                      post: _post(),
                      likedComments: <String>{},
                      onToggleLike: (_) {},
                    ),
                    child: const Text('Open comments'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
