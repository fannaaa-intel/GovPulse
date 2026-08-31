// The completion-photos card (ResolutionMediaSection).
//
// Driven through a MOCK HTTP CLIENT handed to Supabase, because every state
// this card can be in is a function of what `report_resolution_media` returns
// and there is no other way to reach those branches offline.
//
// What these pin, and why each one is here rather than left to a screenshot:
//
//  * The card's editable form is ADMIN/STAFF only. The citizen variant must
//    stay read-only and must vanish entirely when there is nothing to show —
//    a stray "Add photos" on a resident's screen would let them publish to
//    their own report.
//  * Deleting is permanent AND public: the resident may already have seen the
//    photo. It used to happen on one tap of a small × with no confirmation and
//    no undo. The dialog is the whole safety property.
//  * The empty state must actually say something. It used to be two outlined
//    buttons floating under a line of grey prose.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/core/widgets/resolution_media.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Serves the one table this widget reads. [rows] is what comes back.
///
/// [failDeletes] makes every DELETE come back 403, standing in for the RLS
/// denial or dropped connection that the optimistic remove used to hide.
class _MockApi extends http.BaseClient {
  final List<Map<String, dynamic>> rows;
  final bool failDeletes;
  _MockApi(this.rows, {this.failDeletes = false});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (failDeletes && request.method == 'DELETE') {
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({
          'message': 'permission denied for table report_resolution_media',
          'code': '42501',
        }))),
        403,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(rows))),
      200,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }
}

const _photo = {
  'id': '1',
  'storage_path': 'demo/after-1.jpg',
  'mime_type': 'image/jpeg',
  'created_at': '2026-08-30T14:03:00Z',
};
const _video = {
  'id': '2',
  'storage_path': 'demo/walkthrough.mp4',
  'mime_type': 'video/mp4',
  'created_at': '2026-08-30T14:05:00Z',
};

/// Supabase is a singleton, so each case disposes and re-initialises it with
/// its own mock rather than trying to swap the client underneath.
Future<void> _boot(
  List<Map<String, dynamic>> rows, {
  bool failDeletes = false,
}) async {
  try {
    await Supabase.instance.dispose();
  } catch (_) {
    // Not initialized yet on the first call.
  }
  await Supabase.initialize(
    url: 'https://preview.invalid',
    anonKey: 'test-not-a-real-key',
    httpClient: _MockApi(rows, failDeletes: failDeletes),
    authOptions: const FlutterAuthClientOptions(
      localStorage: EmptyLocalStorage(),
      detectSessionInUri: false,
      // Off, or the SDK starts a periodic refresh timer inside the test body
      // and the binding fails every test with "Pending timers".
      autoRefreshToken: false,
    ),
    debug: false,
  );
}

Widget _host({required bool canEdit}) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: 420,
            child: ResolutionMediaSection(reportId: 'r1', canEdit: canEdit),
          ),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  tearDown(() async {
    try {
      await Supabase.instance.dispose();
    } catch (_) {
      // Already disposed, or never initialized.
    }
  });

  group('the empty state says something', () {
    testWidgets('an admin is told what the card is for and given one action',
        (tester) async {
      await _boot(const []);
      await tester.pumpWidget(_host(canEdit: true));
      await tester.pumpAndSettle();

      expect(find.text('No completion media yet'), findsOneWidget);
      expect(find.textContaining('Show the resident'), findsOneWidget);

      // ONE primary action, with video offered as a quieter secondary. Two
      // equal-weight outlined buttons gave the admin a choice before giving
      // them a reason.
      expect(find.widgetWithText(FilledButton, 'Add photos'), findsOneWidget);
      expect(find.textContaining('or add a short video'), findsOneWidget);
    });

    testWidgets('a citizen with nothing to see renders NOTHING at all',
        (tester) async {
      await _boot(const []);
      await tester.pumpWidget(_host(canEdit: false));
      await tester.pumpAndSettle();

      // Not an empty card, not a heading with a blank space under it — the
      // whole section is absent. A resolved report with no photos should not
      // grow a section apologising for it.
      expect(find.byType(ResolutionMediaSection), findsOneWidget);
      expect(find.text('Completion photos'), findsNothing);
      expect(find.text('No completion media yet'), findsNothing);
    });
  });

  group('the resident never gets an uploader', () {
    testWidgets('no add affordance on the read-only variant', (tester) async {
      await _boot(const [_photo]);
      await tester.pumpWidget(_host(canEdit: false));
      await tester.pumpAndSettle();

      expect(find.text('Completion photos'), findsOneWidget);
      expect(find.text('Add'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Add photos'), findsNothing);
      expect(find.text('No completion media yet'), findsNothing);
    });

    testWidgets('and no publish banner — it is not addressed to them',
        (tester) async {
      await _boot(const [_photo]);
      await tester.pumpWidget(_host(canEdit: false));
      await tester.pumpAndSettle();

      // The banner warns the uploader that what they attach goes public. Shown
      // to the resident it would be nonsense — they are the audience, not the
      // publisher.
      expect(find.textContaining('appears on the resident'), findsNothing);
    });
  });

  testWidgets('an admin is warned that attaching here publishes',
      (tester) async {
    await _boot(const [_photo]);
    await tester.pumpWidget(_host(canEdit: true));
    await tester.pumpAndSettle();

    // This was the tail of a grey sentence — the most consequential fact about
    // the card, rendered as its least prominent text.
    expect(find.textContaining('appears on the resident'), findsOneWidget);
  });

  testWidgets('the add tile sits in the grid beside existing media',
      (tester) async {
    await _boot(const [_photo, _video]);
    await tester.pumpWidget(_host(canEdit: true));
    await tester.pumpAndSettle();

    // The action belongs where the eye already is, not stranded below the
    // content it acts on.
    expect(find.text('Add'), findsOneWidget);
    expect(find.text('VIDEO'), findsOneWidget);
  });

  group('deleting is guarded', () {
    testWidgets('the × asks before destroying anything', (tester) async {
      await _boot(const [_photo]);
      await tester.pumpWidget(_host(canEdit: true));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close_rounded).first);
      await tester.pumpAndSettle();

      expect(find.text('Remove this photo?'), findsOneWidget);
      // The consequence is spelled out: permanent, and the resident loses it.
      expect(find.textContaining('permanently'), findsOneWidget);
      expect(find.textContaining("citizen's resolved report"), findsOneWidget);
    });

    testWidgets('cancelling keeps the media', (tester) async {
      await _boot(const [_photo]);
      await tester.pumpWidget(_host(canEdit: true));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close_rounded).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Still one item, so the count pill is still there and the add tile has
      // not become the only thing in the grid.
      expect(find.text('Remove this photo?'), findsNothing);
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('a FAILED delete keeps the media on screen', (tester) async {
      // ⚠ The regression this exists for. _remove used to drop the tile FIRST
      // and swallow every error in a bare `catch (_)`. An RLS denial or a
      // dropped connection therefore left the admin looking at a card that
      // said the photo was gone while it was still live on the resident's
      // resolved report — the console asserting something false about what the
      // public can see, with nothing short of a reload to correct it.
      await _boot(const [_photo], failDeletes: true);
      await tester.pumpWidget(_host(canEdit: true));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close_rounded).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      // Still there, because the server refused. The count pill is the tell:
      // it is driven by the same list the grid renders.
      expect(find.text('1'), findsOneWidget);
      expect(find.textContaining('Could not remove it'), findsOneWidget);
    });

    testWidgets('a video is named as a video in the prompt', (tester) async {
      await _boot(const [_video]);
      await tester.pumpWidget(_host(canEdit: true));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close_rounded).first);
      await tester.pumpAndSettle();

      expect(find.text('Remove this video?'), findsOneWidget);
      expect(find.text('Remove this photo?'), findsNothing);
    });
  });

  testWidgets('the card lays out without overflow at a narrow pane width',
      (tester) async {
    await _boot(const [_photo, _video]);

    final errors = <String>[];
    final prev = FlutterError.onError;
    FlutterError.onError = (details) {
      final s = details.exceptionAsString();
      if (s.contains('overflowed') || s.contains('RenderFlex')) {
        errors.add(s.split('\n').first);
      } else {
        prev?.call(details);
      }
    };
    // 320px stands in for the admin dialog collapsed to one column on a small
    // laptop, which is the tightest this card is ever asked to render.
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    try {
      await tester.pumpWidget(_host(canEdit: true));
      await tester.pumpAndSettle();
    } finally {
      FlutterError.onError = prev;
    }
    expect(errors, isEmpty, reason: errors.join('\n'));
  });
}
