// test/staff_detail_ref_lifetime_test.dart
//
// ════════════════════════════════════════════════════════════════════════════
//  "Bad state: Cannot use "ref" after the widget was disposed"
//
//  ── The defect ──────────────────────────────────────────────────────────
//  Reported from the staff console: pressing ANY button in the report detail —
//  Return to triage, Under review, In progress, Resolved — threw that error as
//  a red banner across the top of the screen.
//
//  Every one of those buttons went through one of two callbacks, and both were
//  built in `StaffReportsPage.build`:
//
//      onSetStatus: (id, s) =>
//          ref.read(staffReportsProvider.notifier).setStatus(id, s),
//
//  That closure captures THAT build's `ref`. The detail is presented as a
//  pushed ROUTE on a phone (showAdminDetail), so the list page underneath is
//  free to be rebuilt or disposed while the detail is still open — the list
//  polls on an interval, so it is rebuilt often. Once it is, the captured `ref`
//  is dead and every button in the detail throws on first press.
//
//  ── The fix these tests pin ─────────────────────────────────────────────
//  The detail is handed the PROVIDER and reads the notifier off its OWN `ref`,
//  which lives exactly as long as the detail does. A ConsumerState's ref stays
//  valid regardless of what happens to the widget that pushed it.
//
//  These tests model the lifetime rather than mounting the real staff console
//  (which needs Supabase and a signed-in officer): they reproduce the exact
//  disposal ordering with a stand-in provider, so the WRONG pattern fails here
//  and the right one passes.
// ════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stand-in for a staff queue notifier: one write action.
class _Queue extends Notifier<int> {
  @override
  int build() => 0;

  void setStatus() => state = state + 1;
}

final _queueProvider = NotifierProvider<_Queue, int>(_Queue.new);

// ── The BROKEN shape: a detail holding a closure over the list's ref ────────

class _ListPageCapturing extends ConsumerWidget {
  const _ListPageCapturing();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => _DetailCapturing(
                // The bug, verbatim: a closure over THIS build's ref, handed to
                // a route that outlives this widget.
                onSetStatus: () => ref.read(_queueProvider.notifier).setStatus(),
              ),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    );
  }
}

class _DetailCapturing extends StatelessWidget {
  final VoidCallback onSetStatus;
  const _DetailCapturing({required this.onSetStatus});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(onPressed: onSetStatus, child: const Text('apply')),
    ),
  );
}

// ── The FIXED shape: a detail holding the provider, using its own ref ───────

class _ListPageProvider extends ConsumerWidget {
  const _ListPageProvider();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => _DetailProvider(queue: _queueProvider),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    );
  }
}

class _DetailProvider extends ConsumerWidget {
  final NotifierProvider<_Queue, int> queue;
  const _DetailProvider({required this.queue});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: Center(
      child: TextButton(
        // Its OWN ref — alive for exactly as long as this widget is.
        onPressed: () => ref.read(queue.notifier).setStatus(),
        child: const Text('apply'),
      ),
    ),
  );
}

/// Opens the detail, then disposes the page underneath it — which is what the
/// staff list does to itself every time its interval poll lands.
Future<void> _openDetailThenDisposeList(
  WidgetTester tester,
  Widget listPage,
) async {
  await tester.pumpWidget(
    ProviderScope(child: MaterialApp(home: listPage)),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();

  // The detail is on top; now the route under it goes away. `maintainState:
  // false` on the pushed route would do this too, as does any rebuild that
  // replaces the list element.
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Navigator(
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (_) => _DetailProvider(queue: _queueProvider),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'a closure over a disposed page ref throws — the reported bug',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: _ListPageCapturing())),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Capture the closure the detail is holding, then dispose the list that
      // built it — exactly the ordering a pushed detail plus a polling list
      // produces.
      final detail = tester.widget<_DetailCapturing>(
        find.byType(_DetailCapturing),
      );
      await tester.pumpWidget(const ProviderScope(child: SizedBox()));

      expect(
        () => detail.onSetStatus(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('ref'),
          ),
        ),
        reason: 'this is the crash the staff console was showing — it is '
            'reproduced here so the fix below is provably a fix',
      );
    },
  );

  testWidgets(
    'the detail reading its OWN ref survives the list being disposed',
    (tester) async {
      await _openDetailThenDisposeList(tester, const _ListPageProvider());

      // The button that used to throw. Every staff detail action — Return to
      // triage, Under review, In progress, Resolved — goes through this path.
      await tester.tap(find.text('apply'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('and it still actually performs the write', (tester) async {
    late WidgetRef probe;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              probe = ref;
              return _DetailProvider(queue: _queueProvider);
            },
          ),
        ),
      ),
    );

    expect(probe.read(_queueProvider), 0);

    await tester.tap(find.text('apply'));
    await tester.pumpAndSettle();

    expect(
      probe.read(_queueProvider),
      1,
      reason: 'the action must reach the notifier, not merely fail to throw',
    );
  });
}
