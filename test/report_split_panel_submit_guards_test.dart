// Drives the two ways a Report an Issue split panel can reach the Submit button
// holding an invalid report, and pins that neither gets through.
//
//   1. The citizen attaches a photo, walks to Review, then deletes it from the
//      review grid — leaving zero attachments under an enabled Submit button.
//   2. A photo is still being processed when Submit is pressed.
//
// What makes these worth their weight is that they attach a REAL file through a
// stand-in gallery, so the guards run against genuine `_attachedFiles` and
// `_processingPaths` state rather than against a hand-set flag.
//
// ── Why the plumbing below ────────────────────────────────────────────────
// The attach path crosses the real event loop (`XFile.length()`, then
// `precacheImage` decoding off disk), and `testWidgets` runs inside a FakeAsync
// zone where real I/O futures never complete. So the attach happens inside
// `tester.runAsync`. That in turn lets every OTHER plugin on the page run its
// real async too — the inline location picker's map reaches for path_provider,
// and the form's GPS fetch reaches for geolocator — so both channels are
// stubbed. Neither stub is under test; they just stop an unrelated
// MissingPluginException from failing the run.
//
// Nothing here reaches Supabase: both cases stop at validation, which runs
// before the first network call in `_submitReport`.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/core/widgets/Home/Quick-action/Web/quick_action_split_panel.dart';
import 'package:govpulse/features/home/Quick-action/Report/report_issue_screen.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

/// A 1×1 PNG, written to a real temp file so the attachment tile's `FileImage`
/// has something it can actually decode.
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

/// Stands in for the file picker the panel opens: returns [files] instead of
/// putting a chooser on screen. Everything downstream — the size checks,
/// `_addGalleryImage`, the processing set, the reveal — is the app's own code.
///
/// `getMedia` is the one the panel goes through (the browser's own file dialog,
/// filtered to images AND video); `getMultiImageWithOptions` is kept so the
/// same fake still answers the mobile gallery path if a test drives it.
class _FakeGallery extends ImagePickerPlatform {
  _FakeGallery(this.files);
  final List<XFile> files;

  @override
  Future<List<XFile>> getMedia({required MediaOptions options}) async => files;

  @override
  Future<List<XFile>> getMultiImageWithOptions({
    MultiImagePickerOptions options = const MultiImagePickerOptions(),
  }) async => files;
}

late Directory _tmp;

/// A real on-disk PNG. `length:` is passed explicitly so `XFile.length()`
/// resolves from memory — the form awaits it before accepting the file, and a
/// disk read there would stall under FakeAsync.
XFile _realPng(String name) {
  final f = File('${_tmp.path}/$name')..writeAsBytesSync(_kPngBytes);
  return XFile.fromData(
    _kPngBytes,
    path: f.path,
    name: name,
    length: _kPngBytes.length,
  );
}

void _stubPlugins() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  // The inline picker's map asks for a cache directory on first build.
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => _tmp.path,
  );
  // The form auto-fetches GPS on mount. Denying is the branch the location
  // section already handles, and it is what the other split-panel tests get.
  messenger.setMockMethodCallHandler(
    const MethodChannel('flutter.baseflow.com/geolocator'),
    (call) async => switch (call.method) {
      'checkPermission' || 'requestPermission' => 0, // denied
      'isLocationServiceEnabled' => false,
      _ => null,
    },
  );
}

Future<void> _pumpSplit(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

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

/// Moves to [label], satisfying anything the steps in between still need.
///
/// The stepper refuses to jump over an unfinished step (`_onStepperTap`), so
/// reaching Details or Review means walking the form. Only what is still EMPTY
/// is filled, so a test that supplied its own category, location, description
/// or attachment keeps exactly what it set.
Future<void> _goToStep(WidgetTester tester, String label) async {
  final target = _kStepOrder.indexOf(label);
  var current = _currentStep(tester);
  if (target <= current) {
    await tester.tap(find.text(label));
    await tester.pump();
    return;
  }
  while (current < target) {
    await _satisfyStep(tester, current);
    await tester.tap(find.text(_kStepOrder[current + 1]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    current++;
  }
}

Future<void> _satisfyStep(WidgetTester tester, int step) async {
  switch (step) {
    case 0:
      if (_noCategoryPicked(tester)) {
        await tester.tap(find.text('Road & Infrastructure'));
        await tester.pump();
      }
    case 1:
      if (find.text('Select barangay').evaluate().isNotEmpty) {
        await _pickBarangay(tester);
      }
    case 2:
      final remarks = find.byWidgetPredicate(
        (w) => w is TextField && w.maxLength == 1000,
      );
      if (tester.widget<TextField>(remarks).controller!.text.trim().isEmpty) {
        await tester.enterText(remarks, 'A description for the test.');
        await tester.pump();
      }
      if (find.text('0/6').evaluate().isNotEmpty) {
        await _attachOne(tester);
        await _settleProcessing(tester);
      }
  }
}

bool _noCategoryPicked(WidgetTester tester) => tester
    .widgetList<QaChoiceTile>(find.byType(QaChoiceTile))
    .every((t) => !t.selected);

/// Opens the inline barangay list and takes one. The pick saves itself.
Future<void> _pickBarangay(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Select barangay'));
  await tester.pump();
  await tester.tap(find.text('Select barangay'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.text('Bukig').last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Sets a location through the INLINE picker, the way a citizen would.
///
/// Needed because `_validate()` checks location BEFORE attachments — without
/// it, the zero-attachment test would be answered by the location message and
/// would never reach the guard it is actually about. GPS is denied under test,
/// so the barangay list is the path.
///
/// There is no Confirm step in the panel: choosing a barangay SAVES it, which
/// is what this walks.
Future<void> _setLocation(WidgetTester tester) async {
  await _goToStep(tester, 'Location');
  await _pickBarangay(tester);
}

/// Runs the real attach flow: taps the square dropzone tile and lets the
/// stand-in return the file the browser's picker would have.
///
/// No chooser sheet is tapped through, because the panel does not show one —
/// see `_pickMedia`.
///
/// Stops as soon as the file is in `_attachedFiles` — well inside the form's
/// 500ms minimum reveal, so on return the attachment is still PROCESSING.
Future<void> _attachOne(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.tap(find.text('Add file'));
    await Future<void>.delayed(const Duration(milliseconds: 120));
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Lets the minimum reveal elapse and the reveal animation play out, clearing
/// `_processingPaths`.
///
/// Alternates real time with pumped frames on purpose. The form gates the tile
/// on `Future.wait([precacheImage(...), delayed(500ms)])`: the delay needs real
/// time (only `runAsync` provides it) while the decode resolves on a frame
/// (only `pump` provides that), so neither alone ever finishes the wait.
Future<void> _settleProcessing(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  setUpAll(() {
    _tmp = Directory.systemTemp.createTempSync('govpulse_report_guards');
  });
  tearDownAll(() {
    // Best effort: the image cache can still hold a handle on the PNG when the
    // run ends, and failing teardown over a temp file would mask real results.
    try {
      if (_tmp.existsSync()) _tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() {
    _stubPlugins();
    ImagePickerPlatform.instance = _FakeGallery([_realPng('shot.png')]);
  });

  testWidgets('the attach flow really does add a file', (tester) async {
    // Guards the tests below: if attaching silently stopped working they would
    // pass vacuously, having never had an attachment to lose.
    await _pumpSplit(tester);
    await _goToStep(tester, 'Details');
    await _attachOne(tester);
    await _settleProcessing(tester);

    expect(find.text('1/6'), findsOneWidget);
    expect(find.text('1 file attached'), findsWidgets);
  });

  // ── 1. Deleting the last attachment on Review ────────────────────────────

  testWidgets('deleting the last attachment on Review blocks Submit', (
    tester,
  ) async {
    await _pumpSplit(tester);

    // An otherwise complete report: category, location, description, one photo.
    // Location matters — `_validate()` checks it before attachments, so without
    // it this test would be answered by the wrong message.
    await tester.tap(find.text('Road & Infrastructure'));
    await tester.pump();
    await _setLocation(tester);
    await _goToStep(tester, 'Details');
    await tester.enterText(
      find.byType(TextField).first,
      'Pothole outside the market.',
    );
    await tester.pump();
    await _attachOne(tester);
    await _settleProcessing(tester);

    await _goToStep(tester, 'Review');

    // Review shows the real tile, and the rail agrees.
    expect(find.text('1 file attached'), findsWidgets);
    final deleteButton = find.descendant(
      of: find.byType(GridView),
      matching: find.byIcon(Icons.close_rounded),
    );
    expect(deleteButton, findsOneWidget);

    // Delete it — review attachments are deliberately deletable.
    await tester.tap(deleteButton);
    await tester.pump();

    // Both sides immediately reflect zero attachments.
    expect(find.text('No photo or video attached'), findsOneWidget);

    // Review was reached legitimately and the citizen is already standing on
    // it, so no step gate applies to what happens next: the block has to come
    // from the submit path itself.
    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Submit Report'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.onPressed, isNotNull);

    await tester.tap(find.text('Submit Report'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // `_validate()` refused it, with its own unmodified message.
    expect(
      find.textContaining('attach at least one photo or video'),
      findsOneWidget,
      reason:
          'a report with zero attachments must not get past _validate(), '
          'however the citizen arrived at zero',
    );

    // Still on Review, nothing submitted.
    expect(find.byType(QaSplitPanel), findsOneWidget);
    expect(find.text('Summary'), findsOneWidget);
  });

  // ── 2. Submitting mid-processing ─────────────────────────────────────────

  testWidgets('a processing photo pins the panel to Details until it lands', (
    tester,
  ) async {
    // ── What this used to check, and why it changed ─────────────────────────
    // It used to jump to Review mid-processing and assert that Submit was
    // disabled there. That state is no longer reachable: the stepper now runs
    // the same `_processingPaths` gate before it will leave Details, so a
    // half-processed photo can never arrive at Review in the first place. The
    // guarantee is the same one — a report cannot be fired mid-upload — moved
    // to where it is now enforced. (The rail still disables Submit on
    // `waitingOnMedia`; that has become belt-and-braces rather than the only
    // line of defence.)
    await _pumpSplit(tester);

    await tester.tap(find.text('Road & Infrastructure'));
    await tester.pump();
    await _setLocation(tester);
    await _goToStep(tester, 'Details');
    await tester.enterText(
      find.byType(TextField).first,
      'Pothole outside the market.',
    );
    await tester.pump();

    // Attach, but do NOT let the reveal finish — the file stays in
    // `_processingPaths`.
    await _attachOne(tester);

    // Neither way forward is open while it processes.
    await tester.tap(find.text('Review'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text('Step 3 — Describe it and add proof'),
      findsOneWidget,
      reason: 'the stepper must not carry a half-processed photo to Review',
    );
    expect(find.textContaining('wait for your photo'), findsOneWidget);

    // Once processing finishes, the same tap goes through and Submit is live.
    await _settleProcessing(tester);
    await tester.tap(find.text('Review'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Submit Report'), findsOneWidget);
    final ready = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Submit Report'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(ready.onPressed, isNotNull);
  });

  testWidgets('the processing guard is in the form, not only in the button', (
    tester,
  ) async {
    // The disabled button is the first line of defence, but it is a UI
    // decision. Continue runs the same `_processingPaths` check `_validate()`
    // does, so pressing it mid-processing must not advance either.
    await _pumpSplit(tester);

    await tester.tap(find.text('Road & Infrastructure'));
    await tester.pump();
    await _goToStep(tester, 'Details');
    await tester.enterText(
      find.byType(TextField).first,
      'Pothole outside the market.',
    );
    await tester.pump();
    await _attachOne(tester);

    await tester.tap(find.text('Continue'));
    await tester.pump();

    expect(
      find.textContaining('wait for your photo to finish processing'),
      findsOneWidget,
    );
    expect(
      find.text('Step 3 — Describe it and add proof'),
      findsOneWidget,
      reason: 'Continue must not advance while media is processing',
    );

    // Let the reveal finish before the tree is torn down — its 500ms minimum is
    // a real timer, and leaving one pending fails the test on teardown.
    await _settleProcessing(tester);
  });
}
