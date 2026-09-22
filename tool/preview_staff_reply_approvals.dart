// Dev-only harness for the ADMIN "staff reply approvals" queue — the panel
// that sits above the toolbar on Admin -> Suggestions.
//
// Not part of the app: nothing under lib/ imports it, and it is never a build
// target for a shipped bundle.
//
//   flutter build web --release -t tool/preview_staff_reply_approvals.dart
//   python -m http.server 57816 --directory build/web
//
// ── Why this exists ────────────────────────────────────────────────────────
// This queue shipped INVISIBLE, and the reason it stayed invisible is that
// every automated signal was green: analyze passed, the tests passed, the
// release build succeeded. The panel simply rendered SizedBox.shrink() because
// its PostgREST read threw on every load (an admin_profiles embed with no FK
// behind it) and the widget treated "error" exactly like "nothing to approve".
//
// So the states have to be LOOKED at, not asserted at. The buttons below flip
// between all four.
//
// ── What to look at ────────────────────────────────────────────────────────
//  * error   — must say it FAILED and offer "Try again". It must never look
//              like an empty queue. This is the whole bug.
//  * loading — a skeleton in the panel's own shape, so nothing below it jumps
//              when the rows land.
//  * empty   — genuinely nothing: a queue, not a permanent section.
//  * queue   — the populated panel. Check at 360 px that the two action
//              buttons STACK, and at >= 420 that they share a row without the
//              labels clipping.
// The hostile row carries the longest plausible value in every field at once;
// a gentle fixture passes layouts that real data breaks.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:govpulse/features/admin/providers/admin_staff_replies_provider.dart';
import 'package:govpulse/features/admin/theme/admin_ui.dart';
import 'package:govpulse/features/admin/widgets/staff_reply_approvals.dart';

enum _State { queue, empty, loading, error }

/// Set before runApp and read by the stub notifier.
_State _current = _State.queue;

void main() => runApp(const _PreviewApp());

DateTime _ago(Duration d) => DateTime.now().subtract(d);

PendingStaffReply _reply({
  required String id,
  required String authorName,
  required String department,
  required String details,
  required String body,
  required Duration waited,
}) =>
    PendingStaffReply(
      id: id,
      suggestionId: 's-$id',
      authorId: 'a-$id',
      authorName: authorName,
      authorPhotoUrl: null,
      department: department,
      body: body,
      createdAt: _ago(const Duration(hours: 2)),
      suggestionCategory: 'infrastructure',
      suggestionCategoryOther: null,
      suggestionDetails: details,
      suggestionCreatedAt: _ago(waited),
    );

final _rows = <PendingStaffReply>[
  // Hostile: longest plausible name, longest office, a wrapping suggestion and
  // a wrapping reply, and an overdue badge — all in one row.
  _reply(
    id: 'h1',
    authorName: 'Engr. Maria Cristina Villanueva-Bautista',
    department: 'Municipal Planning & Development Office',
    details:
        'Good day po. I would like to respectfully suggest that the '
        'municipality consider installing additional streetlights along the '
        'entire stretch of Rizal Street, particularly between the public '
        'market and the barangay hall, because the area becomes extremely '
        'dark after sunset and many residents walk home through there.',
    body:
        'Thank you for raising this concern with our office. We have endorsed '
        'your request to the Engineering Office and an ocular inspection has '
        'been scheduled for the coming week, after which a costing will be '
        'prepared for the consideration of the Municipal Council.',
    waited: const Duration(days: 12),
  ),
  // Ordinary row, fresh — exercises the "just now"/minutes badge that used to
  // print a bare "0h waiting".
  _reply(
    id: 'h2',
    authorName: 'Ms. Reyes',
    department: 'Sanitation Office',
    details: 'Please add a covered waste bin near the plaza.',
    body: 'Noted. A bin will be installed before the end of the month.',
    waited: const Duration(minutes: 7),
  ),
];

class _StubReplies extends AdminStaffRepliesNotifier {
  @override
  Future<List<PendingStaffReply>> build() {
    switch (_current) {
      case _State.queue:
        return Future.value(_rows);
      case _State.empty:
        return Future.value(const []);
      case _State.loading:
        // Never completes: the first-load skeleton stays on screen to be read.
        return Future.any([]);
      case _State.error:
        return Future.error(
          Exception('PostgrestException: could not find a relationship'),
        );
    }
  }
}

class _PreviewApp extends StatefulWidget {
  const _PreviewApp();
  @override
  State<_PreviewApp> createState() => _PreviewAppState();
}

class _PreviewAppState extends State<_PreviewApp> {
  // 360 must STACK the action buttons; 420 is the breakpoint; 1280 is the real
  // desktop console width.
  double _width = 1280;
  _State _state = _State.queue;
  double _textScale = 1.0;

  @override
  Widget build(BuildContext context) {
    _current = _state;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF1F2937),
        body: Column(
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        for (final w in const [360.0, 420.0, 700.0, 1280.0])
                          FilledButton(
                            onPressed: () => setState(() => _width = w),
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  _width == w ? Colors.white : Colors.white24,
                              foregroundColor:
                                  _width == w ? Colors.black : Colors.white,
                            ),
                            child: Text('${w.toInt()} px'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        for (final s in _State.values)
                          FilledButton(
                            onPressed: () => setState(() => _state = s),
                            style: FilledButton.styleFrom(
                              backgroundColor: _state == s
                                  ? const Color(0xFF22C55E)
                                  : Colors.white24,
                              foregroundColor:
                                  _state == s ? Colors.black : Colors.white,
                            ),
                            child: Text(s.name),
                          ),
                        FilledButton(
                          onPressed: () => setState(
                            () => _textScale = _textScale == 1.0 ? 1.3 : 1.0,
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: _textScale == 1.3
                                ? const Color(0xFFF59E0B)
                                : Colors.white24,
                            foregroundColor: _textScale == 1.3
                                ? Colors.black
                                : Colors.white,
                          ),
                          child: Text('text ${_textScale}x'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: SizedBox(
                  width: _width,
                  child: ClipRect(
                    child: Builder(
                      builder: (outer) {
                        final mq = MediaQuery.of(outer);
                        return MediaQuery(
                          data: mq.copyWith(
                            size: Size(_width, mq.size.height - 140),
                            textScaler: TextScaler.linear(_textScale),
                          ),
                          child: Container(
                            color: AdminUi.pageBg,
                            // Keyed on the state so flipping the buttons
                            // rebuilds the provider rather than serving the
                            // first state's already-resolved future.
                            child: ProviderScope(
                              key: ValueKey(_state),
                              overrides: [
                                adminStaffRepliesProvider
                                    .overrideWith(_StubReplies.new),
                              ],
                              child: const SingleChildScrollView(
                                padding: EdgeInsets.all(16),
                                child: StaffReplyApprovalsPanel(),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
