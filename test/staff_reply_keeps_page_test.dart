// A refetch must not throw the page away.
//
// Sending a reply calls refresh() on the suggestions notifier. That used to set
// `state = const AsyncLoading()`, which DISCARDS the current value, so
// `when(loading:)` fired and the whole inbox — header, KPI tiles, filters, the
// list, and the open detail pane — was replaced by the skeleton for the length
// of a round trip. A staff member who had just pressed Send watched their work
// vanish and come back.
//
// These tests drive the REAL `refresh()` against a fake repository whose fetch
// can be held open, so the frame DURING the refetch is observable. An earlier
// draft of this file overrode `refresh()` itself in the fake notifier — which
// tested the page against a reimplementation of the very method under test, and
// passed just as happily with the fix removed. The gate belongs in the repo.
//
// A test that only checks the settled state proves nothing either: the old code
// also ended up correct, it just got there through a skeleton nobody wanted.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:govpulse/features/staff/data/staff_engagement_repository.dart';
import 'package:govpulse/features/staff/data/staff_repository.dart';
import 'package:govpulse/features/staff/pages/staff_feedback_page.dart';
import 'package:govpulse/features/staff/pages/staff_suggestions_page.dart';
import 'package:govpulse/features/staff/providers/staff_engagement_providers.dart';
import 'package:govpulse/features/staff/providers/staff_providers.dart';
import 'package:govpulse/features/staff/widgets/staff_common.dart';

const _kDept = 'Engineering Office';

StaffSuggestion _s(String id, String details, ReplyState reply) =>
    StaffSuggestion(
      id: id,
      userId: null,
      category: 'infrastructure',
      categoryOther: null,
      barangay: 'Macanaya',
      address: null,
      details: details,
      isAnonymous: true,
      status: StaffSuggestionStatus.fresh,
      createdAt: DateTime.now(),
      department: _kDept,
      aiCategory: null,
      aiCategoryReason: null,
      adminResponse: null,
      replyState: reply,
      replyId: reply == ReplyState.none ? null : 'r$id',
      replyBody: null,
      replyRejectedReason: null,
      replyAuthorId: 'me',
    );

StaffFeedback _f(String id, int rating, String service) => StaffFeedback(
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
      comment: 'ang tagal ng proseso',
      visitDate: null,
      isAnonymous: false,
      createdAt: DateTime.now(),
      adminResponse: null,
      aiSentiment: null,
    );

/// A repository whose fetches can be held open mid-flight.
///
/// The first fetch of each kind resolves immediately so the page reaches its
/// loaded state; every later one waits on [gate], which is what makes the
/// in-flight frame observable. `super(...)` takes a client it never uses —
/// nothing here touches the network.
class _GatedRepo extends StaffEngagementRepository {
  // The inherited client is never reached: both fetches are overridden below,
  // and nothing else on either page calls into the repo. A cast of null keeps
  // this test free of a Supabase.initialize(), which would make it an
  // integration test for no gain.
  _GatedRepo() : super(_unusedClient);

  Completer<void>? gate;
  bool fail = false;
  List<StaffSuggestion> suggestions = const [];
  List<StaffFeedback> feedback = const [];

  Future<void> _maybeWait() async {
    final g = gate;
    if (g != null) await g.future;
    if (fail) throw Exception('offline');
  }

  @override
  Future<List<StaffSuggestion>> fetchSuggestions(String department) async {
    await _maybeWait();
    return suggestions;
  }

  @override
  Future<List<StaffFeedback>> fetchFeedback(String department) async {
    await _maybeWait();
    return feedback;
  }
}

const _kIdentity = StaffIdentity(
  userId: 'me',
  email: 'staff@example.gov',
  fullName: 'Test Officer',
  title: 'Officer',
  department: _kDept,
  isExternal: false,
  isOnline: true,
  photoUrl: null,
);

class _FakeIdentity extends StaffIdentityNotifier {
  @override
  Future<StaffIdentity> build() async => _kIdentity;
}

/// The real notifiers, with ONLY the 30-second poll timer disarmed.
///
/// `build()` and `refresh()` are inherited untouched — `refresh()` is the
/// method under test, so a fake that reimplements it would be testing the
/// test. The timer has to go because a `Timer.periodic` still pending at
/// teardown fails the widget binding, and it contributes nothing here.
class _NoPollSug extends StaffSuggestionsNotifier {
  @override
  void startPolling() {}
}

class _NoPollFb extends StaffFeedbackNotifier {
  @override
  void startPolling() {}
}

/// A real client pointed at nothing. Constructing one issues no request — only
/// a query would — and both queries are overridden away, so this never leaves
/// the process. It exists solely to satisfy the repo's constructor without
/// dragging Supabase.initialize() into a widget test.
final SupabaseClient _unusedClient =
    SupabaseClient('http://localhost:1', 'test-anon-key');

late _GatedRepo _repo;

Future<ProviderContainer> _pump(WidgetTester t, Widget page) async {
  t.view.physicalSize = const Size(1200, 2000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final container = ProviderContainer(
    overrides: [
      staffEngagementRepoProvider.overrideWithValue(_repo),
      staffIdentityProvider.overrideWith(_FakeIdentity.new),
      staffSuggestionsProvider.overrideWith(_NoPollSug.new),
      staffFeedbackProvider.overrideWith(_NoPollFb.new),
      staffHasFeedbackProvider.overrideWithValue(true),
    ],
  );
  addTearDown(container.dispose);
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Scaffold(body: page)),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
  return container;
}

void main() {
  setUp(() {
    _repo = _GatedRepo()
      ..suggestions = [
        _s('1', 'drainage on rizal street', ReplyState.none),
        _s('2', 'streetlight near school', ReplyState.pending),
      ]
      ..feedback = [_f('a', 1, 'Building Permit')];
  });

  testWidgets('suggestions: an in-flight refetch keeps the rows on screen',
      (t) async {
    final c = await _pump(t, const StaffSuggestionsPage());
    expect(find.text('drainage on rizal street'), findsWidgets);

    // Hold the NEXT fetch open, then start the real refresh() and pump without
    // letting it finish — this is the frame that used to be a skeleton.
    _repo.gate = Completer<void>();
    unawaited(c.read(staffSuggestionsProvider.notifier).refresh());
    await t.pump();

    expect(
      find.byType(StaffListPageSkeleton),
      findsNothing,
      reason: 'a refetch over existing rows must not show the skeleton',
    );
    expect(find.text('drainage on rizal street'), findsWidgets);
    expect(find.text('streetlight near school'), findsWidgets);

    _repo.gate!.complete();
    await t.pumpAndSettle();
    expect(find.text('drainage on rizal street'), findsWidgets);
  });

  testWidgets('suggestions: a FAILED refetch keeps the rows, not an error page',
      (t) async {
    final c = await _pump(t, const StaffSuggestionsPage());

    _repo
      ..gate = Completer<void>()
      ..fail = true;
    unawaited(c.read(staffSuggestionsProvider.notifier).refresh());
    await t.pump();
    _repo.gate!.complete();
    await t.pumpAndSettle();

    expect(
      find.byType(StaffErrorState),
      findsNothing,
      reason: 'a failed refresh must not discard a page that already has rows',
    );
    expect(find.text('drainage on rizal street'), findsWidgets);
  });

  testWidgets('suggestions: the FIRST load still shows the skeleton', (t) async {
    // The fix must not cost the genuine loading state. With no previous value
    // there is nothing to hold, so the skeleton is still correct.
    _repo.gate = Completer<void>();
    t.view.physicalSize = const Size(1200, 2000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final container = ProviderContainer(overrides: [
      staffEngagementRepoProvider.overrideWithValue(_repo),
      staffIdentityProvider.overrideWith(_FakeIdentity.new),
      staffSuggestionsProvider.overrideWith(_NoPollSug.new),
      staffFeedbackProvider.overrideWith(_NoPollFb.new),
      staffHasFeedbackProvider.overrideWithValue(true),
    ]);
    addTearDown(container.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: StaffSuggestionsPage())),
    ));
    await t.pump();
    expect(find.byType(StaffListPageSkeleton), findsOneWidget);
    _repo.gate!.complete();
    await t.pumpAndSettle();
  });

  testWidgets('feedback: an in-flight refetch keeps the rows on screen',
      (t) async {
    final c = await _pump(t, const StaffFeedbackPage());
    expect(find.text('Building Permit'), findsWidgets);

    _repo.gate = Completer<void>();
    unawaited(c.read(staffFeedbackProvider.notifier).refresh());
    await t.pump();

    expect(find.byType(StaffListPageSkeleton), findsNothing);
    expect(find.text('Building Permit'), findsWidgets);

    _repo.gate!.complete();
    await t.pumpAndSettle();
    expect(find.text('Building Permit'), findsWidgets);
  });
}
