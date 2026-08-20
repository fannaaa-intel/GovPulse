// Drives the Share a Suggestion form's `splitPanel` branch — the citizen web
// two-column layout — and pins what mirroring Report had to preserve.
//
// The form is SHARED with the mobile app: the same SuggestionForm the web shell
// puts in a dialog is what mobile pushes as a full page. The split layout is a
// third build branch behind a flag that defaults to false, so the risk is
// entirely that the new branch quietly changes the form's behaviour for
// everyone. These tests check that it does not:
//
//   1. The panel is Report's panel — the same chrome, the same four steps, the
//      same collapse at 880 and the same fixed frame.
//   2. The gates are SUGGESTION's, not Report's. Location and attachments are
//      optional here, and Continue must never refuse a step over either; the
//      category and the description are required, and it must.
//   3. Moving between steps HIDES sections, it does not destroy them.
//   4. `splitPanel: false` (every mobile call site) renders the untouched
//      standalone page — hero panel and all.
//
// Supabase is never reached: every assertion stops at validation, which runs
// before the first network call in `_submitSuggestion`.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/core/widgets/Home/Quick-action/Web/quick_action_split_panel.dart';
import 'package:govpulse/features/home/Quick-action/Suggestion/suggestion_screen.dart';
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

/// Stands in for the browser's file picker.
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

  final tmp = Directory.systemTemp.createTempSync('qa_split_suggestion');
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
  // Answer the picker's GPS probe immediately, and with a DENIAL. Unstubbed it
  // throws a MissingPluginException that resolves whenever the test next lets
  // real async run.
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
          child: SuggestionForm(
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

/// Taps a step by its label, scrolling it into view first.
Future<void> _tapStep(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pump();
  await tester.tap(find.text(label));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Presses Continue.
Future<void> _tapContinue(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Picks the first category, which is all step 1 requires.
Future<void> _pickCategory(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Public Service'));
  await tester.pump();
  await tester.tap(find.text('Public Service'));
  await tester.pump();
}

/// Types into the description field — the only one capped at 2500.
Future<void> _typeDescription(WidgetTester tester, String text) async {
  final field = find.byWidgetPredicate(
    (w) => w is TextField && w.maxLength == 2500,
  );
  await tester.ensureVisible(field);
  await tester.pump();
  await tester.enterText(field, text);
  await tester.pump();
}

void main() {
  group('the panel is the same panel Report draws', () {
    testWidgets('side by side, two cards and the four-step stepper', (
      tester,
    ) async {
      await _pumpSplit(tester);

      expect(find.byType(QaSplitPanel), findsOneWidget);
      expect(find.byType(QaPanelCard), findsNWidgets(2));
      expect(find.byType(QaStepper), findsOneWidget);
      for (final label in _kStepOrder) {
        expect(find.text(label), findsOneWidget);
      }
      // The rail's own identity, beside the working card's title.
      expect(find.text('Share a Suggestion'), findsOneWidget);
      expect(find.text('Summary'), findsOneWidget);
    });

    testWidgets('the two panel cards are equal height side by side', (
      tester,
    ) async {
      await _pumpSplit(tester);

      final cards = tester
          .widgetList<QaPanelCard>(find.byType(QaPanelCard))
          .toList();
      expect(cards.length, 2);

      final heights = find
          .byType(QaPanelCard)
          .evaluate()
          .map((e) => tester.getSize(find.byWidget(e.widget)).height)
          .toList();
      expect(heights[0], moreOrLessEquals(heights[1], epsilon: 0.5));
    });

    testWidgets('every step draws the panel at exactly the same size', (
      tester,
    ) async {
      await _pumpSplit(tester);

      Size panelSize() => tester.getSize(find.byType(QaSplitPanel));

      final sizes = <Size>[panelSize()];

      await _pickCategory(tester);
      await _tapContinue(tester);
      sizes.add(panelSize());

      // Location is optional — Continue passes straight through it.
      await _tapContinue(tester);
      sizes.add(panelSize());

      await _typeDescription(tester, 'A description for the test.');
      await _tapContinue(tester);
      sizes.add(panelSize());

      expect(_currentStep(tester), 3);
      for (final s in sizes) {
        expect(s.width, moreOrLessEquals(sizes.first.width, epsilon: 0.5));
        expect(s.height, moreOrLessEquals(sizes.first.height, epsilon: 0.5));
      }
    });

    testWidgets('below the breakpoint the columns stack with no overflow', (
      tester,
    ) async {
      await _pumpSplit(tester, size: const Size(820, 900));
      expect(tester.takeException(), isNull);

      // Stacked, the working card takes over the title and gains the pane
      // switcher; the rail is reduced to the pinned action zone.
      expect(find.byType(QaSegmentedTabs), findsOneWidget);
      expect(find.text('Suggestion'), findsWidgets);
      expect(find.text('Summary'), findsWidgets);
    });

    testWidgets('every step lays out at a phone width', (tester) async {
      await _pumpSplit(tester, size: const Size(390, 844));
      expect(tester.takeException(), isNull);

      await _pickCategory(tester);
      await _tapContinue(tester);
      expect(tester.takeException(), isNull);

      await _tapContinue(tester);
      expect(tester.takeException(), isNull);

      await _typeDescription(tester, 'Phone-width description.');
      await _tapContinue(tester);
      expect(tester.takeException(), isNull);
      expect(_currentStep(tester), 3);
    });
  });

  group('the gates are Suggestion own, not Report copied', () {
    testWidgets('an empty category refuses Continue, and says why', (
      tester,
    ) async {
      await _pumpSplit(tester);

      await _tapContinue(tester);
      expect(_currentStep(tester), 0);
      expect(find.text('Please select a suggestion category.'), findsOneWidget);
    });

    testWidgets('the category error clears the moment one is picked', (
      tester,
    ) async {
      await _pumpSplit(tester);
      await _tapContinue(tester);
      expect(find.text('Please select a suggestion category.'), findsOneWidget);

      await _pickCategory(tester);
      expect(find.text('Please select a suggestion category.'), findsNothing);
    });

    testWidgets('an OPTIONAL location never blocks Continue', (tester) async {
      await _pumpSplit(tester);
      await _pickCategory(tester);
      await _tapContinue(tester);
      expect(_currentStep(tester), 1);

      // Nothing picked, and the step is left anyway — this is the single
      // clearest difference from Report, where the same press is refused.
      await _tapContinue(tester);
      expect(_currentStep(tester), 2);
      expect(find.textContaining('location'), findsNothing);
    });

    testWidgets('an empty description refuses Continue', (tester) async {
      await _pumpSplit(tester);
      await _pickCategory(tester);
      await _tapContinue(tester);
      await _tapContinue(tester);
      expect(_currentStep(tester), 2);

      await _tapContinue(tester);
      expect(_currentStep(tester), 2);
      expect(
        find.text('Please describe your suggestion in detail.'),
        findsOneWidget,
      );
    });

    testWidgets('OPTIONAL attachments never block Continue', (tester) async {
      await _pumpSplit(tester);
      await _pickCategory(tester);
      await _tapContinue(tester);
      await _tapContinue(tester);
      await _typeDescription(tester, 'No photo on this one.');

      // The dropzone still reads 0/6 — nothing is attached, and the step is
      // left anyway.
      expect(find.text('0/6'), findsOneWidget);
      await _tapContinue(tester);
      expect(_currentStep(tester), 3);
    });

    testWidgets('the dropzone opens the file picker with no chooser sheet', (
      tester,
    ) async {
      await _pumpSplit(tester);
      await _pickCategory(tester);
      await _tapContinue(tester);
      await _tapContinue(tester);
      expect(_currentStep(tester), 2);

      // Nothing attached yet.
      expect(find.text('0/6'), findsOneWidget);

      await tester.tap(find.text('Add file'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      // ── One click, not two ────────────────────────────────────────────────
      // On the web both branches of the "Photo from Gallery / Video from
      // Gallery" sheet end in the SAME OS file dialog, so the sheet is a
      // pop-up over a pop-up that only makes the citizen pick the accept
      // filter by hand. The panel goes straight to `pickMultipleMedia`, which
      // is what the fake picker above answers — so the file lands without any
      // sheet being tapped through, exactly as it does on Report.
      expect(find.text('Add attachment'), findsNothing);
      expect(find.text('Photo from Gallery'), findsNothing);
      expect(find.text('Video from Gallery'), findsNothing);
      expect(find.text('1/6'), findsOneWidget);
    });

    testWidgets('the stepper still refuses to skip a REQUIRED step', (
      tester,
    ) async {
      await _pumpSplit(tester);

      // Jump straight at Review with nothing filled in: the tap lands on the
      // first unmet step, carrying the message Continue would have raised.
      await _tapStep(tester, 'Review');
      expect(_currentStep(tester), 0);
      expect(find.text('Please select a suggestion category.'), findsOneWidget);
    });

    testWidgets('the stepper skips straight over the OPTIONAL step', (
      tester,
    ) async {
      await _pumpSplit(tester);
      await _pickCategory(tester);
      await _tapContinue(tester);
      await _tapContinue(tester);
      await _typeDescription(tester, 'Filled in before jumping.');

      // Back to the start, then one tap at Review. Its walk checks step 0
      // (category: set), step 1 (location: nothing to check) and step 2
      // (description: typed) — so it lands, even though no location was ever
      // set. On Report the identical walk stops at step 1.
      await _tapStep(tester, 'Category');
      expect(_currentStep(tester), 0);

      await _tapStep(tester, 'Review');
      expect(_currentStep(tester), 3);
    });

    testWidgets('going back to a completed step is never blocked', (
      tester,
    ) async {
      await _pumpSplit(tester);
      await _pickCategory(tester);
      await _tapContinue(tester);
      expect(_currentStep(tester), 1);

      await _tapStep(tester, 'Category');
      expect(_currentStep(tester), 0);
    });
  });

  group('steps hide sections, they do not destroy them', () {
    testWidgets('the description survives a round trip through other steps', (
      tester,
    ) async {
      await _pumpSplit(tester);
      await _pickCategory(tester);
      await _tapContinue(tester);
      await _tapContinue(tester);
      await _typeDescription(tester, 'Widen the plaza footpath.');

      await _tapStep(tester, 'Category');
      expect(_currentStep(tester), 0);
      await _tapStep(tester, 'Details');
      expect(_currentStep(tester), 2);

      final field = tester.widget<TextField>(
        find.byWidgetPredicate((w) => w is TextField && w.maxLength == 2500),
      );
      expect(field.controller!.text, 'Widen the plaza footpath.');
    });

    testWidgets('the rail summarises live, and marks the optional rows', (
      tester,
    ) async {
      await _pumpSplit(tester);
      await _pickCategory(tester);

      // The chosen category reaches the rail without a second copy of it.
      expect(find.text('Public Service'), findsWidgets);
      // The two optional rows say so rather than reading as unfilled
      // requirements.
      expect(find.text('Optional — not set'), findsOneWidget);
      expect(find.text('Optional — none'), findsOneWidget);
    });

    testWidgets('the review step renders what was actually filled in', (
      tester,
    ) async {
      await _pumpSplit(tester);
      await _pickCategory(tester);
      await _tapContinue(tester);
      await _tapContinue(tester);
      await _typeDescription(tester, 'A specific, checkable sentence.');
      await _tapContinue(tester);
      expect(_currentStep(tester), 3);

      expect(find.text('A specific, checkable sentence.'), findsWidgets);
      // No location was set, and Review says so as a statement of fact rather
      // than as a missing requirement.
      expect(
        find.text('No location — this applies anywhere'),
        findsOneWidget,
      );
      expect(find.text('No photo or video attached'), findsOneWidget);
      // The last step swaps Continue for the submit button.
      expect(find.widgetWithText(FilledButton, 'Send Suggestion'), findsOneWidget);
    });
  });

  group('the other build branches are untouched', () {
    testWidgets('splitPanel: false still renders the standalone page', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(home: SuggestionForm(username: 'juan.delacruz')),
      );
      // The page stages its entry animation from a post-frame `Future.delayed`;
      // pump past it so no timer is left pending when the tree is torn down.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(seconds: 1));

      // None of the panel's chrome, and the numbered mobile sections instead.
      expect(find.byType(QaSplitPanel), findsNothing);
      expect(find.byType(QaStepper), findsNothing);
      expect(find.text('1. Select Suggestion Category'), findsOneWidget);
    });
  });
}
