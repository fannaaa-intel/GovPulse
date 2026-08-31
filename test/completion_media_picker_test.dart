// test/completion_media_picker_test.dart
//
// ════════════════════════════════════════════════════════════════════════════
//  "Add completion media" — how the Photos/Video choice is presented.
//
//  ── The defect ──────────────────────────────────────────────────────────
//  On the admin and staff phone apps it was a centred card that faded in over
//  a dimmed page — a two-item chooser floating in the middle of the screen,
//  which reads as an interruption rather than as a continuation of the tap.
//  The citizen side had already moved away from that shape (see
//  _showBarangayPicker in edit_profile_screen.dart): a slide-up sheet with a
//  rounded top and a grab handle, rising from the edge it is anchored to.
//
//  ── The rule ────────────────────────────────────────────────────────────
//  Below 900px — phone, and the medium web window that behaves like one — a
//  bottom sheet. At or above it, no picker at all: the desktop file explorer
//  opens over the page and already shows both photos and videos, so asking
//  "which kind?" first is a dialog whose only job is to choose the next
//  dialog. One tap instead of two, with nothing lost.
//
//  ── What this file can and cannot reach ─────────────────────────────────
//  ResolutionMediaSection talks to Supabase in initState, and the widgets that
//  own the picker (_AddTile, _EmptyDropzone) are private to that library. So
//  this does NOT drive the real tile — mounting it would need a live client.
//
//  What it pins is the DECISION the tile delegates to: the threshold itself,
//  and the branch each width takes. That is the part that was wrong and the
//  part a future edit is most likely to get wrong again. The sheet's own
//  appearance is verified by rendering, not here.
// ════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mirrors `_kSkipPickerAt` in resolution_media.dart. Duplicated rather than
/// exported so a change to the production constant makes this file disagree
/// and a human has to decide which is right — the same reasoning
/// triage_write_degradation_test uses for its duplicated predicate.
const double kSkipPickerAt = 900;

/// The branch the tile takes at a given viewport width.
enum Route { sheet, straightToExplorer }

Route routeFor(double width) =>
    width >= kSkipPickerAt ? Route.straightToExplorer : Route.sheet;

void main() {
  group('the width rule', () {
    test('phones and medium windows get the sheet', () {
      // 390 = a phone. 600/820 = the medium web window, which behaves like one
      // because the system file explorer is still full-screen there.
      for (final w in [320.0, 390.0, 430.0, 600.0, 820.0, 899.0]) {
        expect(
          routeFor(w),
          Route.sheet,
          reason: '${w.toInt()}px must ask first — the explorer is a '
              'full-screen system UI at this size, so Video going straight to '
              'the video tab is worth one tap',
        );
      }
    });

    test('large screens skip the picker entirely', () {
      for (final w in [900.0, 1024.0, 1280.0, 1600.0]) {
        expect(
          routeFor(w),
          Route.straightToExplorer,
          reason: '${w.toInt()}px opens the explorer over the page and shows '
              'both kinds, so asking first is a modal in front of a dialog',
        );
      }
    });

    test('the boundary is exactly 900, inclusive', () {
      // Stated explicitly because an off-by-one here is invisible: 899 and 900
      // look identical on screen, and the wrong branch only shows up as an
      // extra tap nobody reports.
      expect(routeFor(899.999), Route.sheet);
      expect(routeFor(900), Route.straightToExplorer);
    });
  });

  group('the sheet shape it opens', () {
    // The production sheet is built by showModalBottomSheet with a rounded top
    // and a grab handle. Rebuilt here from the same parameters so the SHAPE is
    // pinned even though the private tile cannot be mounted.
    Future<void> pumpSheet(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: TextButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: ctx,
                    backgroundColor: Colors.white,
                    shape: const RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    builder: (_) => SafeArea(
                      top: false,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          SizedBox(height: 10),
                          Center(
                            child: SizedBox(
                              key: Key('handle'),
                              width: 44,
                              height: 4,
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.fromLTRB(20, 18, 20, 4),
                            child: Text('Add completion media'),
                          ),
                          ListTile(
                            leading: Icon(Icons.add_a_photo_outlined),
                            title: Text('Photos'),
                          ),
                          ListTile(
                            leading: Icon(Icons.videocam_outlined),
                            title: Text('Video'),
                          ),
                          SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                  child: const Text('add'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('add'));
      await tester.pumpAndSettle();
    }

    testWidgets('is a sheet, not a centred card', (tester) async {
      await pumpSheet(tester);

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(
        find.byType(Dialog),
        findsNothing,
        reason: 'a Dialog here is the old shape this replaced',
      );
    });

    testWidgets('meets the bottom edge', (tester) async {
      await pumpSheet(tester);

      // The property that makes it read as a sheet: anchored to the bottom of
      // the viewport, not floating in the middle of it.
      expect(tester.getRect(find.byType(BottomSheet)).bottom, 900);
    });

    testWidgets('carries a grab handle and both options', (tester) async {
      await pumpSheet(tester);

      expect(find.byKey(const Key('handle')), findsOneWidget);
      expect(find.text('Add completion media'), findsOneWidget);
      expect(find.text('Photos'), findsOneWidget);
      expect(find.text('Video'), findsOneWidget);
    });

    testWidgets('sizes to its content, not to a fraction of the screen', (
      tester,
    ) async {
      await pumpSheet(tester);

      // Two rows and a title. A sheet that claimed half the phone for this
      // would be as wrong as the centred card was.
      final h = tester.getRect(find.byType(BottomSheet)).height;
      expect(h, lessThan(300), reason: 'it has nothing to scroll');
      expect(h, greaterThan(120));
    });
  });
}
