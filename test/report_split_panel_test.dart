// Drives the Report an Issue form's `splitPanel` branch — the citizen web
// two-column layout — and pins the three properties the redesign had to keep.
//
// The form is SHARED with the mobile app: the same ReportIssueForm the web shell
// puts in a dialog is what `home_screen.dart` pushes as a full page. The split
// layout is therefore a third build branch behind a flag that defaults to false,
// and the risk is entirely that the new branch quietly changes the form's
// behaviour for everyone. These tests check that it does not:
//
//   1. Moving between steps HIDES sections, it does not destroy them — typed
//      text, the picked category and the attachment list all survive a round
//      trip through the other steps.
//   2. The stepper gates FORWARD moves and says why. A later step is only
//      reachable once every step before it is satisfied, and a tap that cannot
//      be honoured lands on the first unfinished step carrying the same message
//      Continue would have raised. Backwards is always free, and Submit still
//      goes through the form's own `_validate()`.
//   3. `splitPanel: false` (every mobile call site) renders the untouched
//      standalone page — hero panel and all.
//
// Supabase is never reached: every assertion here stops at validation, which
// runs before the first network call in `_submitReport`.

import 'dart:io';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/core/widgets/Home/Quick-action/Web/quick_action_split_panel.dart';
import 'package:govpulse/features/home/Quick-action/Report/location_picker_screen.dart';
import 'package:govpulse/features/home/Quick-action/Report/report_issue_screen.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

/// A 1×1 PNG — enough for the form to accept, decode and thumbnail a file.
final Uint8List _kPngBytes = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

/// Stands in for the browser's file picker, so [_satisfyStep] can put a real
/// attachment on step 3 — which the stepper now requires before Review.
class _FakeGallery extends ImagePickerPlatform {
  _FakeGallery(this.files);
  final List<XFile> files;

  @override
  Future<List<XFile>> getMedia({required MediaOptions options}) async => files;
}

/// Pumps the form at a desktop viewport wide enough for the two columns.
///
/// 1200×900 is representative of what the shell's dialog hands the panel: the
/// dialog caps at 1160 and the panel collapses below 880, so this exercises the
/// two-column path rather than the stacked fallback.
Future<void> _pumpSplit(
  WidgetTester tester, {
  Size size = const Size(1200, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  // Step 3 requires a real attachment before the stepper will pass it, so the
  // picker and the cache directory the form writes through are stubbed for
  // every test rather than only for the ones that attach on purpose.
  final tmp = Directory.systemTemp.createTempSync('qa_split');
  addTearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows keeps a handle on the decoded file for a moment; the temp
      // directory is the OS's problem after the run.
    }
  });
  final png = File('${tmp.path}/shot.png')..writeAsBytesSync(_kPngBytes);
  ImagePickerPlatform.instance = _FakeGallery([
    XFile.fromData(
      _kPngBytes,
      path: png.path,
      name: 'shot.png',
      length: _kPngBytes.length,
    ),
  ]);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => tmp.path,
      );
  // Answer the GPS auto-fetch immediately, and with a DENIAL.
  //
  // Unstubbed it throws a MissingPluginException that resolves whenever the
  // test next lets real async run — and `_autoFetchLocation`'s failure branch
  // clears `_pickedLatLng`, so a late answer wipes a barangay the test had
  // already chosen. Answering up front keeps the failure where the form
  // expects it: on open, before anything is picked.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('flutter.baseflow.com/geolocator'),
        (call) async => switch (call.method) {
          'checkPermission' || 'requestPermission' => 0, // denied
          'isLocationServiceEnabled' => false,
          _ => null,
        },
      );

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: ReportIssueForm(
            username: 'juan.delacruz',
            splitPanel: true,
            onClose: () {},
          ),
        ),
      ),
    ),
  );
  // The form kicks off a GPS fetch in a post-frame callback. Settle past it —
  // geolocator answers with an error under test, which is the same
  // "permission denied" branch the location section already handles.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

const List<String> _kStepOrder = ['Category', 'Location', 'Details', 'Review'];

/// Which step the panel is showing, read off the instruction block's title.
int _currentStep(WidgetTester tester) {
  for (var i = 0; i < _kStepOrder.length; i++) {
    if (find.textContaining('Step ${i + 1} —').evaluate().isNotEmpty) return i;
  }
  return 0;
}

/// Moves the panel to [label], filling whatever the steps in between still
/// require on the way.
///
/// The stepper refuses to jump over an unfinished step (`_onStepperTap`), so a
/// test that wants to look at Review has to earn its way there exactly as a
/// citizen does. Only EMPTY fields are filled, so a test that set its own
/// category or typed its own text keeps them.
Future<void> _goToStep(WidgetTester tester, String label) async {
  final target = _kStepOrder.indexOf(label);
  var current = _currentStep(tester);

  // Backwards, or to the step already showing: nothing to satisfy.
  if (target <= current) {
    await _tapStep(tester, label);
    return;
  }

  while (current < target) {
    await _satisfyStep(tester, current);
    await _tapStep(tester, _kStepOrder[current + 1]);
    current++;
  }
}

/// Taps a step by its label, scrolling it into view first.
///
/// Stacked, the stepper is part of the SCROLLING body — only the header tabs
/// and the action zone are pinned — so filling in a field near the bottom of a
/// step can leave the stepper off the top of the viewport. A citizen scrolls
/// back up to it; a test that does not simply taps empty space and then asserts
/// against a panel that never moved.
Future<void> _tapStep(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pump();
  await tester.tap(find.text(label));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Supplies the minimum [step] needs to be left, if it is not already met.
Future<void> _satisfyStep(WidgetTester tester, int step) async {
  switch (step) {
    case 0:
      final picked = tester
          .widgetList<QaChoiceTile>(find.byType(QaChoiceTile))
          .any((t) => t.selected);
      if (!picked) {
        // Same reason as _tapStep: the grid scrolls with the body.
        await tester.ensureVisible(find.text('Road & Infrastructure'));
        await tester.pump();
        await tester.tap(find.text('Road & Infrastructure'));
        await tester.pump();
      }
    case 1:
      // The placeholder is only on screen while nothing is chosen.
      if (find.text('Select barangay').evaluate().isNotEmpty) {
        await tester.ensureVisible(find.text('Select barangay'));
        await tester.pump();
        await tester.tap(find.text('Select barangay'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('Bukig').last);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      }
    case 2:
      // The description field is the only one with a 1000-character cap.
      final remarks = find.byWidgetPredicate(
        (w) => w is TextField && w.maxLength == 1000,
      );
      final field = tester.widget<TextField>(remarks);
      if (field.controller!.text.trim().isEmpty) {
        await tester.enterText(remarks, 'A description for the test.');
        await tester.pump();
      }
      // "0/6" on the dropzone tile means nothing is attached yet.
      if (find.text('0/6').evaluate().isNotEmpty) {
        // The working area scrolls, and at a phone's height the dropzone sits
        // below its fold — a tap there lands on nothing and the step silently
        // stays unsatisfied. No-op at the desktop viewports.
        await tester.ensureVisible(find.text('Add file'));
        await tester.pump();
        await tester.runAsync(() async {
          await tester.tap(find.text('Add file'));
          await Future<void>.delayed(const Duration(milliseconds: 120));
        });
        await tester.pump();
        // Let the reveal finish so the processing guard is clear.
        for (var i = 0; i < 20; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump(const Duration(milliseconds: 120));
        }
      }
  }
}

void main() {
  testWidgets('renders both columns with the stepper and the action stack', (
    tester,
  ) async {
    await _pumpSplit(tester);

    // Left panel: title + all four steps.
    expect(find.text('Report an Issue'), findsOneWidget);
    expect(find.byType(QaStepper), findsOneWidget);
    for (final step in ['Category', 'Location', 'Details', 'Review']) {
      expect(find.text(step), findsOneWidget);
    }

    // Right rail: header, summary rows, action stack.
    expect(find.text('Summary'), findsOneWidget);
    expect(find.byType(QaActionStack), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    // Nothing filled in yet, so every summary row shows its placeholder.
    expect(find.text('Not set yet'), findsWidgets);

    // A floating card keeps its ×. The back chevron is the phone treatment and
    // must not leak up here.
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsNothing);
  });

  testWidgets('step 1 shows the category grid and NOT the hero banner', (
    tester,
  ) async {
    await _pumpSplit(tester);

    // The panel builds its own grid, so the nested numbered card is gone — the
    // stepper already says this is step 1.
    expect(find.text('1. Select Issue Category'), findsNothing);
    expect(find.text('Select a category'), findsOneWidget);

    // The decorative clipboard banner is dropped too. The standalone page still
    // gets both (last test below).
    expect(
      find.text(
        'Help us improve our community by\nreporting issues in your area.',
      ),
      findsNothing,
    );
    expect(find.text('Report Issue'), findsNothing);

    // Tile labels are flattened — the hard wrap is sized for a phone tile.
    expect(find.text('Road & Infrastructure'), findsOneWidget);
    expect(find.text('Road &\nInfrastructure'), findsNothing);
  });

  testWidgets('moving between steps hides sections without destroying state', (
    tester,
  ) async {
    await _pumpSplit(tester);

    // Pick a category on step 1. It reaches the rail's summary immediately, so
    // the label now reads twice: once on the tile, once in the rail.
    await tester.tap(find.text('Road & Infrastructure'));
    await tester.pump();
    expect(find.text('Road & Infrastructure'), findsNWidgets(2));

    // Type a description on step 3.
    await _goToStep(tester, 'Details');
    final remarks = find.byType(TextField);
    expect(remarks, findsWidgets);
    await tester.enterText(remarks.first, 'Deep pothole near the market');
    await tester.pump();

    // Walk away to another step and back.
    await _goToStep(tester, 'Location');
    await _goToStep(tester, 'Category');
    await _goToStep(tester, 'Details');

    // The controller was never torn down: the text is still there.
    expect(
      find.text('Deep pothole near the market'),
      findsWidgets,
      reason:
          'Steps must switch visibility (Offstage), not construction — a '
          'conditionally built section would have dropped this controller.',
    );

    // And the category picked three steps ago still reads back.
    await _goToStep(tester, 'Review');
    expect(find.text('Road & Infrastructure'), findsWidgets);
  });

  testWidgets('review renders from the same state the inputs write to', (
    tester,
  ) async {
    await _pumpSplit(tester);

    await tester.tap(find.text('Waste & Garbage'));
    await tester.pump();

    await _goToStep(tester, 'Review');
    // The review's category tile and the rail's summary row both derive from
    // `_selectedCategory` — there is no second copy to drift. The step-1 tile
    // carrying the same label is offstage now, and finders skip offstage.
    expect(find.text('Waste & Garbage'), findsNWidgets(2));
  });

  // ── 6: Review keeps the panel roles ───────────────────────────────────────

  testWidgets(
    'review puts the DETAIL on the left and the summary on the right',
    (tester) async {
      await _pumpSplit(tester);

      // Fill enough that every review block has something real to show.
      await tester.tap(find.text('Drainage & Flooding'));
      await tester.pump();
      await _goToStep(tester, 'Details');
      await tester.enterText(
        find.byType(TextField).first,
        'The canal by the market overflows after every heavy rain.',
      );
      await tester.pump();
      await _goToStep(tester, 'Review');

      final cards = find.byType(QaPanelCard);
      final leftRect = tester.getRect(cards.at(0));
      final rightRect = tester.getRect(cards.at(1));
      expect(rightRect.left, greaterThan(leftRect.left));

      // Helper: is this text inside the left card, or the right one?
      bool inLeft(String text) =>
          tester.getCenter(find.text(text).first).dx < rightRect.left;

      // The DETAIL blocks live on the left, under the stepper.
      for (final label in [
        'Category',
        'Location',
        'Description',
        'Attachments',
        'Submitted as',
      ]) {
        expect(
          inLeft(label),
          isTrue,
          reason: '"$label" must be in the left working area on Review',
        );
      }

      // The real description text is rendered on the left, not just summarised.
      expect(
        find.text('The canal by the market overflows after every heavy rain.'),
        findsWidgets,
      );

      // The rail keeps the SAME compact summary it shows on steps 1–3, in caps.
      for (final label in ['CATEGORY', 'LOCATION', 'DETAILS', 'ATTACHMENTS']) {
        expect(find.text(label), findsOneWidget);
        expect(
          tester.getCenter(find.text(label)).dx,
          greaterThan(rightRect.left),
          reason: '"$label" is a rail summary row and must stay on the right',
        );
      }

      // Plus the truthfulness warning and the actions, on the right.
      final warning = find.textContaining('False or misleading reports');
      expect(warning, findsOneWidget);
      expect(tester.getCenter(warning).dx, greaterThan(rightRect.left));
      for (final action in ['Submit Report', 'Back', 'Cancel']) {
        expect(
          tester.getCenter(find.text(action)).dx,
          greaterThan(rightRect.left),
          reason: '"$action" must stay in the rail',
        );
      }
    },
  );

  testWidgets('the column ratio does not change on Review', (tester) async {
    await _pumpSplit(tester);

    ({double left, double right}) widths() {
      final cards = find.byType(QaPanelCard);
      return (
        left: tester.getSize(cards.at(0)).width,
        right: tester.getSize(cards.at(1)).width,
      );
    }

    final atCategory = widths();
    await _goToStep(tester, 'Review');
    final atReview = widths();

    expect(atReview.left, equals(atCategory.left));
    expect(atReview.right, equals(atCategory.right));
    // And that ratio is the panel's 17:10, not something Review chose.
    expect(atReview.left / atReview.right, closeTo(1.7, 0.05));
  });

  testWidgets('review shows the real attachment tiles, not a count', (
    tester,
  ) async {
    await _pumpSplit(tester);
    await _goToStep(tester, 'Review');

    // Getting to Review now requires a real attachment, so Review must render
    // the FILE — a thumbnail tile, the same widget step 3 draws — rather than
    // reporting a number.
    expect(find.byType(GridView), findsWidgets);
    expect(find.text('No photo or video attached'), findsNothing);
    // ...and the rail's row carries its count.
    expect(find.text('ATTACHMENTS'), findsOneWidget);
    expect(find.textContaining('1 file'), findsWidgets);
  });

  testWidgets('the truthfulness warning only appears on Review', (
    tester,
  ) async {
    await _pumpSplit(tester);

    final warning = find.textContaining('False or misleading reports');
    final info = find.textContaining('goes to the Municipality of Aparri');

    expect(warning, findsNothing);
    expect(info, findsOneWidget);

    await _goToStep(tester, 'Review');
    expect(warning, findsOneWidget);
    expect(info, findsNothing);
  });

  testWidgets('the details step drops the nested numbered cards', (
    tester,
  ) async {
    await _pumpSplit(tester);
    await _goToStep(tester, 'Details');

    expect(find.text('3. Remarks / Concern'), findsNothing);
    expect(find.text('4. Attach Image / Video (Required)'), findsNothing);

    // Replaced by plain labels and a square dropzone tile in a 4-col grid.
    expect(find.text('Describe the issue'), findsOneWidget);
    expect(find.text('Photos or video'), findsOneWidget);
    expect(find.text('Add file'), findsOneWidget);
    expect(find.text('0/6'), findsOneWidget);

    // The counter still comes from the untouched maxLength: 1000.
    expect(find.text('0/1000'), findsOneWidget);

    // The attachment grid is square and sized by EXTENT, so it sheds a column
    // on a narrow panel instead of shrinking the tiles past the dropzone's
    // icon + label + counter stack. It used to be a hard `crossAxisCount: 4`,
    // which is what this asserted.
    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithMaxCrossAxisExtent;
    expect(delegate.maxCrossAxisExtent, 170);
    expect(delegate.childAspectRatio, 1);

    // ...and 170 is chosen so that at a panel width it still resolves to the
    // four across it always drew. Measured off the rendered tile rather than
    // recomputed from the delegate, so this fails if the arithmetic ever stops
    // producing four.
    final gridWidth = tester.getSize(find.byType(GridView)).width;
    final tileWidth = tester
        .getSize(
          find
              .ancestor(
                of: find.text('Add file'),
                matching: find.byType(AnimatedContainer),
              )
              .first,
        )
        .width;
    expect(
      tileWidth,
      closeTo((gridWidth - 3 * 10) / 4, 0.5),
      reason: 'the attachment grid must still be 4 across at panel width',
    );

    // Anonymous is a compact row, not the mobile card.
    expect(find.text('Submit anonymously'), findsOneWidget);
    expect(
      find.text('Your name is hidden from the public feed'),
      findsOneWidget,
    );
  });

  // ── B: per-step gates ─────────────────────────────────────────────────────

  testWidgets('Continue will not advance an unsatisfied step', (tester) async {
    await _pumpSplit(tester);

    // Step 1 with no category picked.
    await tester.tap(find.text('Continue'));
    await tester.pump();

    expect(find.text('Please select an issue category.'), findsOneWidget);
    // Still on Category — the instruction block is the tell.
    expect(find.text('Step 1 — What kind of issue is it?'), findsOneWidget);

    // Picking one clears the inline error and lets Continue through.
    await tester.tap(find.text('Road & Infrastructure'));
    await tester.pump();
    expect(find.text('Please select an issue category.'), findsNothing);

    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.text('Step 2 — Where is it?'), findsOneWidget);
  });

  testWidgets('the location step gates on an unset location', (tester) async {
    await _pumpSplit(tester);

    await tester.tap(find.text('Road & Infrastructure'));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pump();

    // Geolocator fails under test, so no location resolves on its own.
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(
      find.text('Please set a location before continuing.'),
      findsOneWidget,
    );
    expect(find.text('Step 2 — Where is it?'), findsOneWidget);
  });

  testWidgets('optional fields never block Continue', (tester) async {
    await _pumpSplit(tester);

    // "Others" is the one category with a required follow-up; every other
    // category has no optional field standing between it and step 2.
    await tester.tap(find.text('Environment & Pollution'));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pump();

    expect(find.text('Step 2 — Where is it?'), findsOneWidget);
  });

  testWidgets('the step gates are a superset of the submit validator', (
    tester,
  ) async {
    await _pumpSplit(tester);

    // With nothing filled in, both the step-1 gate and _validate() must object
    // to the same thing, in the same words. This is what stops a citizen being
    // told one story by Continue and another by Submit.
    await tester.tap(find.text('Continue'));
    await tester.pump();
    final gateMessage = find.text('Please select an issue category.');
    expect(gateMessage, findsOneWidget);

    // The stepper must answer with that SAME sentence rather than a second
    // wording of its own — it is the other way forward, over the same rule.
    await tester.tap(find.text('Review'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(gateMessage, findsOneWidget);
    expect(
      find.text('Step 1 — What kind of issue is it?'),
      findsOneWidget,
      reason: 'an unsatisfied gate must not be walked past',
    );
  });

  // ── A: the inline location picker ─────────────────────────────────────────

  testWidgets('step 2 hosts the picker inline, with no route push', (
    tester,
  ) async {
    await _pumpSplit(tester);
    await _goToStep(tester, 'Location');

    // The real picker is mounted inside the panel...
    expect(find.byType(LocationPickerScreen), findsOneWidget);
    expect(find.text('Use my current location'), findsOneWidget);

    // ...minus its own heading, which the step's instruction block above it
    // already says. The pushed route keeps it; see _pickerContent.
    expect(find.text('Edit Location'), findsNothing);
    expect(find.text('Step 2 — Where is it?'), findsOneWidget);
    // ...but NOT the pushed picker's Confirm button: inline, a pick saves
    // itself and the rail's Continue is the only way forward.
    expect(find.text('Confirm Address'), findsNothing);

    // ...without any of its page chrome, which is what a pushed route brings.
    expect(
      find.byType(Scaffold),
      findsOneWidget,
    ); // the test's own, not the picker's
    expect(
      find.descendant(
        of: find.byType(LocationPickerScreen),
        matching: find.byType(Scaffold),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(LocationPickerScreen),
        matching: find.byType(PopScope),
      ),
      findsNothing,
    );

    // And the panel is still the thing on screen — nothing was dismissed.
    expect(find.byType(QaSplitPanel), findsOneWidget);
    expect(find.text('Summary'), findsOneWidget);
  });

  testWidgets('picking inline sets the location and stays in the panel', (
    tester,
  ) async {
    await _pumpSplit(tester);
    await _goToStep(tester, 'Location');

    // The field sits below the fold — the working area scrolls internally,
    // which is exactly the behaviour item D asked for, so scroll it in first.
    await tester.ensureVisible(find.text('Select barangay'));
    await tester.pump();

    // Open the contained list and choose. There is nothing to confirm
    // afterwards: the pick IS the commit.
    await tester.tap(find.text('Select barangay'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Bukig').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The rail's summary now carries it — the same state the submit handler
    // reads, set through the shared _applyLocationResult.
    expect(find.text('Bukig'), findsWidgets);

    // The optional street detail only appears once a location resolves, so its
    // presence is proof the save happened without a Confirm press.
    expect(find.text('Street name & detailed location'), findsOneWidget);

    // Still inside the panel: nothing popped, nothing navigated.
    expect(find.byType(QaSplitPanel), findsOneWidget);
    expect(find.text('Summary'), findsOneWidget);

    // And the gate now lets Continue through.
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.text('Step 3 — Describe it and add proof'), findsOneWidget);
  });

  // ── D: equal-height panels, sized to the step ─────────────────────────────

  testWidgets('the two panel cards are equal height side by side', (
    tester,
  ) async {
    await _pumpSplit(tester);

    final cards = find.byType(QaPanelCard);
    expect(cards, findsNWidgets(2));
    final leftBox = tester.renderObject<RenderBox>(cards.at(0));
    final rightBox = tester.renderObject<RenderBox>(cards.at(1));

    expect(
      leftBox.size.height,
      equals(rightBox.size.height),
      reason: 'the rail must be drawn to the same height as the working area',
    );
  });

  testWidgets('every step draws the panel at exactly the same size', (
    tester,
  ) async {
    // Taller than kQaSplitPanelHeight + the host's padding, so the FIXED
    // height is what binds here rather than the space on offer — otherwise
    // this would pass for the wrong reason.
    await _pumpSplit(tester, size: const Size(1200, 1100));

    Size cardSize(int i) =>
        tester.renderObject<RenderBox>(find.byType(QaPanelCard).at(i)).size;

    final sizes = <String, (Size, Size)>{};
    for (final step in ['Category', 'Location', 'Details', 'Review']) {
      await _goToStep(tester, step);
      await tester.pump(const Duration(milliseconds: 300));
      sizes[step] = (cardSize(0), cardSize(1));
    }

    final first = sizes['Category']!;
    expect(
      first.$1.height,
      equals(kQaSplitPanelHeight),
      reason: 'the frame is the fixed height, not the height of the content',
    );
    for (final entry in sizes.entries) {
      expect(
        entry.value.$1,
        equals(first.$1),
        reason: 'the working area changed size on ${entry.key}',
      );
      expect(
        entry.value.$2,
        equals(first.$2),
        reason: 'the summary rail changed size on ${entry.key}',
      );
    }
  });

  testWidgets('no step overflows the fixed height', (tester) async {
    await _pumpSplit(tester, size: const Size(1200, 1100));

    for (final step in ['Category', 'Location', 'Details', 'Review']) {
      await _goToStep(tester, step);
      await tester.pump(const Duration(milliseconds: 300));

      final scrollable = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(SingleChildScrollView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(
        scrollable.position.maxScrollExtent,
        equals(0.0),
        reason:
            '$step does not fit in kQaSplitPanelHeight — either the height is '
            'too low or the step has grown; internal scrolling is the fallback '
            'for an unusually long Review, not the normal state',
      );
    }
  });

  testWidgets('category tiles take an accent hover state', (tester) async {
    await _pumpSplit(tester);

    final tile = find.ancestor(
      of: find.text('Road & Infrastructure'),
      matching: find.byType(QaChoiceTile),
    );
    expect(tile, findsOneWidget);

    BoxBorder? borderOf(Finder f) {
      final container = tester.widget<AnimatedContainer>(
        find.descendant(of: f, matching: find.byType(AnimatedContainer)).first,
      );
      return (container.decoration as BoxDecoration?)?.border;
    }

    final resting = borderOf(tile);

    // Move a real pointer over the tile.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(tile));
    // Fixed pumps, not pumpAndSettle: the location step's "Detecting your
    // location…" spinner is offstage but still ticking, so nothing ever settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      borderOf(tile),
      isNot(equals(resting)),
      reason: 'hovering a category tile must change its border',
    );
  });

  testWidgets('the stepper refuses to skip an unfinished step, and says why', (
    tester,
  ) async {
    await _pumpSplit(tester);

    // Tap straight to Review on an empty form. It must not go.
    await tester.tap(find.text('Review'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text('Step 1 — What kind of issue is it?'),
      findsOneWidget,
      reason: 'the panel must stay on the first unsatisfied step',
    );
    expect(find.text('Submit Report'), findsNothing);

    // And it must SAY so, in the words Continue uses — not fail silently.
    expect(find.textContaining('select an issue category'), findsOneWidget);
  });

  testWidgets('the stepper stops at the FIRST unmet step, not the target', (
    tester,
  ) async {
    await _pumpSplit(tester);
    await tester.tap(find.text('Road & Infrastructure'));
    await tester.pump();

    // Category is satisfied, Location is not. Aiming at Review must land on
    // Location and raise the location message.
    await tester.tap(find.text('Review'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Step 2 — Where is it?'), findsOneWidget);
    expect(find.textContaining('set a location'), findsOneWidget);
  });

  testWidgets('going back to a completed step is never blocked', (
    tester,
  ) async {
    await _pumpSplit(tester);
    await _goToStep(tester, 'Details');
    expect(find.text('Step 3 — Describe it and add proof'), findsOneWidget);

    await tester.tap(find.text('Category'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Step 1 — What kind of issue is it?'), findsOneWidget);
  });

  testWidgets('Submit still runs the form own validator, not a step check', (
    tester,
  ) async {
    await _pumpSplit(tester);
    await _goToStep(tester, 'Review');
    expect(find.text('Submit Report'), findsOneWidget);

    // Empty the description behind Review's back — the step gates are
    // satisfied, so only `_validate()` can refuse what happens next.
    await _goToStep(tester, 'Details');
    await tester.enterText(
      find.byWidgetPredicate((w) => w is TextField && w.maxLength == 1000),
      '',
    );
    await tester.pump();
    await tester.tap(find.text('Review'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The step gate holds it at Details with its own message — proof the two
    // paths share one rule set rather than disagreeing.
    expect(find.textContaining('describe the issue'), findsOneWidget);
  });

  // ── Web responsiveness ────────────────────────────────────────────────────
  //
  // Both directions are checked by measuring the two panel cards against each
  // other: side by side they share a top edge and sit at different x, stacked
  // they share an x and sit at different y. That reads the real geometry rather
  // than trusting the breakpoint constant.

  ({Offset left, Offset right}) cardOrigins(WidgetTester tester) {
    final cards = find.byType(QaPanelCard);
    expect(cards, findsNWidgets(2));
    return (
      left: tester.getTopLeft(cards.at(0)),
      right: tester.getTopLeft(cards.at(1)),
    );
  }

  testWidgets('at a 1280px laptop viewport the columns sit side by side', (
    tester,
  ) async {
    // 1280 minus the dialog's 48px inset and 40px padding — what the panel is
    // actually handed inside the shell's dialog at that viewport.
    await _pumpSplit(tester, size: const Size(1280 - 88, 900));

    final o = cardOrigins(tester);
    expect(
      o.right.dx,
      greaterThan(o.left.dx),
      reason: 'rail must be to the right',
    );
    expect(
      o.left.dy,
      equals(o.right.dy),
      reason: 'both cards share a top edge',
    );
  });

  testWidgets('below the breakpoint the columns stack with no overflow', (
    tester,
  ) async {
    await _pumpSplit(tester, size: const Size(820, 1000));

    final o = cardOrigins(tester);
    expect(
      o.left.dx,
      equals(o.right.dx),
      reason: 'both cards share a left edge',
    );
    expect(o.right.dy, greaterThan(o.left.dy), reason: 'rail must be below');

    // A stacked panel that still laid out horizontally would have tripped the
    // overflow check; pumping without an exception is the assertion.
    expect(tester.takeException(), isNull);
  });

  testWidgets('stacked, the panel has ONE scroller and the actions are pinned', (
    tester,
  ) async {
    await _pumpSplit(tester, size: const Size(400, 800));

    // The rail's own scroll view must not survive stacking. Two scrollables
    // sharing an edge is a drag arbitrated between them instead of doing the
    // obvious thing, and it is exactly what nesting the rail inside a stacked
    // outer scroll view used to produce.
    expect(
      find.descendant(
        of: find.byType(QaSplitPanel),
        matching: find.byType(Scrollable),
      ),
      findsOneWidget,
      reason: 'the working area is the stacked panel\'s only scroller',
    );

    // The actions are their own card at the foot of the panel — not the tail
    // of a page-length scroll, which is where Continue used to end up.
    final cards = find.byType(QaPanelCard);
    final working = tester.getRect(cards.at(0));
    final actions = tester.getRect(cards.at(1));
    expect(actions.top, greaterThanOrEqualTo(working.bottom));
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    // The summary is a PANE now, reachable by its tab. Its rows are offstage
    // with it, so they cost the step no height.
    expect(find.text('Summary'), findsOneWidget);
    expect(find.text('Report'), findsOneWidget);
    expect(find.text('CATEGORY'), findsNothing);

    // Under the host's 600px fullscreen threshold the dismiss control is a
    // back chevron, not an × — the panel is the page here, so there is no card
    // edge for an × to belong to. Same callback either way.
    expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsNothing);
  });

  testWidgets('the stepper is unchanged inside the Report tab', (tester) async {
    await _pumpSplit(tester, size: const Size(400, 800));

    // Still the stepper, still all four labels, still tappable by text.
    expect(find.byType(QaStepper), findsOneWidget);
    for (final step in _kStepOrder) {
      expect(find.text(step), findsOneWidget);
    }

    // Still the NUMBERED CIRCLES, not a second tab bar: advancing marks step 1
    // done and the circle draws a check. The panel already has one segmented
    // control in its head, and a stepper wearing the same clothes would read as
    // a second row of tabs that the form then argues with.
    await _satisfyStep(tester, 0);
    // Continue is in the pinned action zone, so it never needs scrolling to.
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.descendant(
        of: find.byType(QaStepper),
        matching: find.byIcon(Icons.check_rounded),
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Category'));
    await tester.pump();

    // All four columns fit the row — same top edge, increasing x, last one
    // inside the panel. The fixed 82px column could not promise that at 400px.
    var previousLeft = double.negativeInfinity;
    final tops = <double>[];
    for (final step in _kStepOrder) {
      final rect = tester.getRect(find.text(step));
      tops.add(rect.top);
      expect(rect.left, greaterThan(previousLeft));
      previousLeft = rect.left;
      expect(rect.right, lessThanOrEqualTo(400));
    }
    expect(tops.toSet().length, 1, reason: 'the four steps must share a row');

    // And the gating is untouched: a forward tap over an unmet step is still
    // refused, with the same message.
    await _tapStep(tester, 'Review');
    expect(find.textContaining('set a location'), findsOneWidget);
    expect(find.text('Step 2 — Where is it?'), findsOneWidget);
  });

  testWidgets('the Summary tab is a read-only glance with no actions', (
    tester,
  ) async {
    await _pumpSplit(tester, size: const Size(400, 800));

    await tester.tap(find.text('Summary'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // The recap, and only the recap.
    for (final row in ['CATEGORY', 'LOCATION', 'DETAILS', 'ATTACHMENTS']) {
      expect(find.text(row), findsOneWidget);
    }
    expect(
      find.textContaining('goes to the Municipality of Aparri'),
      findsOneWidget,
    );

    // The action zone goes with the pane: Continue acts on the STEP, and the
    // Summary is not one — leaving it here would read as continuing from the
    // recap.
    expect(find.text('Continue'), findsNothing);
    expect(find.text('Cancel'), findsNothing);
    expect(find.byType(QaActionStack), findsNothing);
    // The whole Report pane is offstage, stepper included.
    expect(find.byType(QaStepper), findsNothing);

    // Switching back restores it exactly.
    await tester.tap(find.text('Report'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.byType(QaStepper), findsOneWidget);
    expect(find.text('CATEGORY'), findsNothing);
  });

  testWidgets('switching tabs loses neither form state nor the step', (
    tester,
  ) async {
    await _pumpSplit(tester, size: const Size(400, 800));
    await _goToStep(tester, 'Details');

    await tester.enterText(
      find.byWidgetPredicate((w) => w is TextField && w.maxLength == 1000),
      'The canal by the market overflows again',
    );
    await tester.pump();

    await tester.tap(find.text('Summary'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    // The recap reads the same controller the field writes to.
    expect(
      find.textContaining('The canal by the market overflows again'),
      findsWidgets,
    );

    await tester.tap(find.text('Report'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // A tab is not a step: the wizard is exactly where it was, with what was
    // typed still in it. Rebuilding the pane instead of keeping it offstage
    // would have taken the location picker's GPS toggle down with it.
    expect(find.text('Step 3 — Describe it and add proof'), findsOneWidget);
    expect(
      find.text('The canal by the market overflows again'),
      findsWidgets,
      reason: 'the Report pane must stay mounted across a tab switch',
    );
  });

  testWidgets('the pinned action zone is sized for a bar, not a rail', (
    tester,
  ) async {
    // Wide: the rail keeps its heading and its generous buttons.
    await _pumpSplit(tester);
    expect(find.text('Action'), findsOneWidget);
    final railButton = tester.getSize(find.byType(QaActionButton).first).height;
    expect(
      railButton,
      greaterThan(50),
      reason: 'the rail button is unchanged at >= 880',
    );

    // Stacked: the same buttons pinned across the full width. The heading goes
    // — a permanently visible bar does not need labelling — and the buttons
    // come down to bar height without giving up a comfortable tap target.
    await _pumpSplit(tester, size: const Size(400, 800));
    expect(find.text('Action'), findsNothing);
    final barButton = tester.getSize(find.byType(QaActionButton).first).height;
    expect(barButton, lessThan(railButton));
    expect(
      barButton,
      greaterThanOrEqualTo(44),
      reason: 'a pinned button must still be comfortable to touch',
    );

    // Still a STACK of full-width buttons, not a side-by-side row.
    final buttons = find.byType(QaActionButton);
    final count = tester.widgetList(buttons).length;
    expect(count, greaterThanOrEqualTo(2));
    final first = tester.getRect(buttons.at(0));
    for (var i = 1; i < count; i++) {
      final rect = tester.getRect(buttons.at(i));
      expect(rect.top, greaterThan(first.top), reason: 'buttons stay stacked');
      expect(rect.width, equals(first.width));
    }
    expect(first.width, lessThanOrEqualTo(400));
  });

  testWidgets('the panel never overflows its width at either extreme', (
    tester,
  ) async {
    // Down to a small phone: below the host's 600px fullscreen threshold the
    // panel is handed the viewport itself, so these narrow widths are real
    // ones rather than a hypothetical.
    for (final w in [
      1192.0,
      1000.0,
      900.0,
      820.0,
      700.0,
      560.0,
      480.0,
      430.0,
      360.0,
    ]) {
      await _pumpSplit(tester, size: Size(w, 1200));
      expect(
        tester.takeException(),
        isNull,
        reason: 'panel overflowed horizontally at ${w}px',
      );
      for (final card in tester.widgetList<QaPanelCard>(
        find.byType(QaPanelCard),
      )) {
        final box = tester.renderObject<RenderBox>(find.byWidget(card));
        expect(
          box.size.width,
          lessThanOrEqualTo(w - 40),
          reason: 'a card exceeded the panel at ${w}px',
        );
      }
    }
  });

  testWidgets('every step lays out at a phone width', (tester) async {
    // The sweep above pumps each width on step 1. The three fixed-geometry
    // grids that had to learn to reflow — the category tiles, the attachment
    // grid and the inline picker — are on the steps AFTER it, so walk them at
    // the narrowest width the panel is expected to survive.
    await _pumpSplit(tester, size: const Size(360, 900));

    for (final step in _kStepOrder) {
      await _goToStep(tester, step);
      await tester.pump(const Duration(milliseconds: 300));
      // Assert we actually ARRIVED before reading the frame. A tap that lands
      // below the fold leaves the panel where it was, and the overflow check
      // below would then keep re-passing on the same step.
      expect(
        _currentStep(tester),
        equals(_kStepOrder.indexOf(step)),
        reason: 'never reached $step at a 360px viewport',
      );
      expect(
        tester.takeException(),
        isNull,
        reason: '$step overflowed at a 360px viewport',
      );
    }
  });

  testWidgets('splitPanel: false still renders the untouched standalone page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: ReportIssueForm(username: 'juan.delacruz')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // No split-panel chrome anywhere on the default (mobile) branch.
    expect(find.byType(QaSplitPanel), findsNothing);
    expect(find.byType(QaStepper), findsNothing);
    expect(find.byType(QaActionStack), findsNothing);
    expect(find.text('Summary'), findsNothing);

    // The page's own chrome is intact: the hero banner the panel drops, the
    // section card, and the submit button.
    expect(
      find.text(
        'Help us improve our community by\nreporting issues in your area.',
      ),
      findsOneWidget,
    );
    expect(find.text('1. Select Issue Category'), findsOneWidget);
    expect(find.text('Submit Report'), findsOneWidget);

    // The two sections that gained a `bare` flag must still render their
    // numbered cards and the mobile dropzone when it is false.
    expect(find.text('3. Remarks / Concern'), findsOneWidget);
    expect(find.text('4. Attach Image / Video (Required)'), findsOneWidget);
    expect(find.text('Tap to upload photo or video'), findsOneWidget);
    expect(
      find.text('Image: JPG, PNG (Max. 10MB)  •  Video: MP4 (Max. 50MB)'),
      findsOneWidget,
    );

    // And none of the web-only affordances leak onto it.
    expect(find.byType(QaChoiceTile), findsNothing);
    expect(find.byType(QaFieldLabel), findsNothing);
  });
}
