// Filters and search, driven through the REAL widgets.
//
// The filter predicate is private, so a unit test would have to duplicate it —
// and a duplicate can agree with itself while the page does something else.
// These tap the actual chips and type into the actual search field, so a
// filter that stops being wired up fails here.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:govpulse/features/staff/data/staff_engagement_repository.dart';
import 'package:govpulse/features/staff/pages/staff_feedback_page.dart';
import 'package:govpulse/features/staff/pages/staff_suggestions_page.dart';
import 'package:govpulse/features/staff/providers/staff_engagement_providers.dart';

StaffSuggestion _s(
  String id,
  String details,
  ReplyState reply, {
  String category = 'infrastructure',
  String? barangay,
}) =>
    StaffSuggestion(
      id: id,
      userId: null,
      category: category,
      categoryOther: null,
      barangay: barangay,
      address: null,
      details: details,
      isAnonymous: true,
      status: StaffSuggestionStatus.fresh,
      createdAt: DateTime.now(),
      department: 'Engineering Office',
      aiCategory: null,
      aiCategoryReason: null,
      adminResponse: null,
      replyState: reply,
      replyId: reply == ReplyState.none ? null : 'r$id',
      replyBody: null,
      replyRejectedReason: reply == ReplyState.rejected ? 'too vague' : null,
      replyAuthorId: 'me',
    );

final _suggestions = [
  _s('1', 'drainage on rizal street', ReplyState.none, barangay: 'Macanaya'),
  _s('2', 'streetlight near school', ReplyState.pending),
  _s('3', 'bike lane please', ReplyState.approved),
  _s('4', 'covered walkway', ReplyState.rejected),
];

StaffFeedback _f(String id, int rating, String service, String? comment) =>
    StaffFeedback(
      id: id,
      username: 'u',
      officeId: 'mpdo',
      officeLabel: 'Municipal Planning and Development Office',
      serviceName: service,
      overallRating: rating,
      aspectStaff: null,
      aspectWait: null,
      aspectClarity: null,
      aspectFacility: null,
      comment: comment,
      visitDate: null,
      isAnonymous: false,
      createdAt: DateTime.now(),
      adminResponse: null,
      aiSentiment: null,
    );

final _feedback = [
  _f('a', 1, 'Building Permit', 'ang tagal ng proseso'),
  _f('b', 5, 'Zoning Clearance', 'mabilis salamat'),
  _f('c', 3, 'Subdivision Review', null),
  _f('d', 4, 'Locational Clearance', null),
];

class _FakeSug extends StaffSuggestionsNotifier {
  @override
  Future<List<StaffSuggestion>> build() async => _suggestions;
}

class _FakeFb extends StaffFeedbackNotifier {
  @override
  Future<List<StaffFeedback>> build() async => _feedback;
}

Future<void> _pump(WidgetTester t, Widget page) async {
  // Tall enough that every row is laid out; a short viewport would let a
  // present-but-offscreen row read as filtered out.
  t.view.physicalSize = const Size(1200, 2000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [
      staffSuggestionsProvider.overrideWith(_FakeSug.new),
      staffFeedbackProvider.overrideWith(_FakeFb.new),
      staffHasFeedbackProvider.overrideWithValue(true),
    ],
    child: MaterialApp(home: Scaffold(body: page)),
  ));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

/// Taps the FILTER CHIP with this label.
///
/// Several chip labels ("Needs reply", "Published") are also used by the status
/// pill on each card, so a bare find.text is ambiguous. The chips live inside
/// the horizontally-scrolling filter row, which is the first SingleChildScroll-
/// View on the page, so scoping to it picks the control rather than a row.
Future<void> _tapChip(WidgetTester t, String label) async {
  final chip = find.descendant(
    of: find.byType(SingleChildScrollView).first,
    matching: find.text(label),
  );
  await t.tap(chip.first);
  await t.pump(const Duration(milliseconds: 300));
}

Future<void> _search(WidgetTester t, String q) async {
  await t.enterText(find.byType(TextFormField).first, q);
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  group('suggestions filters', () {
    testWidgets('All shows every row', (t) async {
      await _pump(t, const StaffSuggestionsPage());
      expect(find.text('drainage on rizal street'), findsWidgets);
      expect(find.text('streetlight near school'), findsWidgets);
      expect(find.text('bike lane please'), findsWidgets);
      expect(find.text('covered walkway'), findsWidgets);
    });

    testWidgets('Needs reply hides answered rows', (t) async {
      await _pump(t, const StaffSuggestionsPage());
      await _tapChip(t, 'Needs reply');
      expect(find.text('drainage on rizal street'), findsWidgets);
      // A pending or published reply counts as answered — the composer is
      // closed on both, so neither still "needs" one.
      expect(find.text('streetlight near school'), findsNothing);
      expect(find.text('bike lane please'), findsNothing);
    });

    testWidgets('Awaiting approval shows only pending', (t) async {
      await _pump(t, const StaffSuggestionsPage());
      await _tapChip(t, 'Awaiting approval');
      expect(find.text('streetlight near school'), findsWidgets);
      expect(find.text('drainage on rizal street'), findsNothing);
      expect(find.text('bike lane please'), findsNothing);
    });

    testWidgets('Published shows only approved', (t) async {
      await _pump(t, const StaffSuggestionsPage());
      await _tapChip(t, 'Published');
      expect(find.text('bike lane please'), findsWidgets);
      expect(find.text('streetlight near school'), findsNothing);
    });

    testWidgets('Returned shows only rejected', (t) async {
      await _pump(t, const StaffSuggestionsPage());
      await _tapChip(t, 'Returned');
      expect(find.text('covered walkway'), findsWidgets);
      expect(find.text('bike lane please'), findsNothing);
    });

    testWidgets('search matches the body text', (t) async {
      await _pump(t, const StaffSuggestionsPage());
      await _search(t, 'streetlight');
      expect(find.text('streetlight near school'), findsWidgets);
      expect(find.text('bike lane please'), findsNothing);
    });

    testWidgets('search matches the barangay', (t) async {
      await _pump(t, const StaffSuggestionsPage());
      await _search(t, 'macanaya');
      expect(find.text('drainage on rizal street'), findsWidgets);
      expect(find.text('bike lane please'), findsNothing);
    });

    testWidgets('search ignores case', (t) async {
      await _pump(t, const StaffSuggestionsPage());
      await _search(t, 'BIKE LANE');
      expect(find.text('bike lane please'), findsWidgets);
    });

    testWidgets('a search matching nothing says so', (t) async {
      await _pump(t, const StaffSuggestionsPage());
      await _search(t, 'zzzzz');
      expect(find.textContaining('Nothing matches'), findsOneWidget);
    });

    testWidgets('filter AND search combine, they do not fall back to either',
        (t) async {
      await _pump(t, const StaffSuggestionsPage());
      await _tapChip(t, 'Published');
      await _search(t, 'drainage');
      // "drainage" exists, and a published row exists, but no row is both.
      expect(find.textContaining('Nothing matches'), findsOneWidget);
    });
  });

  group('feedback filters', () {
    testWidgets('Low shows only 1-2 stars', (t) async {
      await _pump(t, const StaffFeedbackPage());
      await _tapChip(t, 'Low 1-2 stars');
      expect(find.text('Building Permit'), findsWidgets);
      expect(find.text('Zoning Clearance'), findsNothing);
      expect(find.text('Subdivision Review'), findsNothing);
    });

    testWidgets('High shows only 4-5 stars', (t) async {
      await _pump(t, const StaffFeedbackPage());
      await _tapChip(t, 'High 4-5 stars');
      expect(find.text('Zoning Clearance'), findsWidgets);
      expect(find.text('Locational Clearance'), findsWidgets);
      // 3 stars belongs to neither band and must not leak into either.
      expect(find.text('Subdivision Review'), findsNothing);
      expect(find.text('Building Permit'), findsNothing);
    });

    testWidgets('search matches the service name', (t) async {
      await _pump(t, const StaffFeedbackPage());
      await _search(t, 'zoning');
      expect(find.text('Zoning Clearance'), findsWidgets);
      expect(find.text('Building Permit'), findsNothing);
    });

    testWidgets('search matches the comment', (t) async {
      await _pump(t, const StaffFeedbackPage());
      await _search(t, 'tagal');
      expect(find.text('Building Permit'), findsWidgets);
      expect(find.text('Zoning Clearance'), findsNothing);
    });

    testWidgets('a rating with no comment is still searchable by service',
        (t) async {
      await _pump(t, const StaffFeedbackPage());
      await _search(t, 'subdivision');
      // A null comment must not throw, nor exclude the row from a service
      // search — the comment field is optional for the citizen.
      expect(find.text('Subdivision Review'), findsWidgets);
    });

    testWidgets('band AND search combine', (t) async {
      await _pump(t, const StaffFeedbackPage());
      await _tapChip(t, 'High 4-5 stars');
      await _search(t, 'building');
      expect(find.textContaining('Nothing matches'), findsOneWidget);
    });

    testWidgets('All clears the band', (t) async {
      await _pump(t, const StaffFeedbackPage());
      await _tapChip(t, 'Low 1-2 stars');
      await _tapChip(t, 'All');
      expect(find.text('Zoning Clearance'), findsWidgets);
      expect(find.text('Building Permit'), findsWidgets);
    });
  });
}
