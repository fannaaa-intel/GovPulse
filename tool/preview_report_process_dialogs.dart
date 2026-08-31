// Preview target: the report-process dialogs and the work-log panel, at the
// four widths this change had to hold.
//
//   flutter run -d web-server --web-port 57941 -t tool/preview_report_process_dialogs.dart
//
// Query params:
//   ?w=<px>       force a viewport width (the dialogs switch shape at 640)
//   ?open=accept  open a dialog on start: accept | endorse | worklog
//
// Analyze, test and build all pass on a page that cannot render, so this exists
// to be LOOKED at. The dialogs are mounted through their real entry points —
// showAcceptAssignDialog / showEndorseEntityDialog — so what renders here is
// what the console renders.
//
// The work-log composer is the one piece that cannot be mounted for real: the
// production widget talks to Supabase in initState. Its chrome is rebuilt from
// the same numbers instead, which is enough to check the thing that changed —
// how many nested boxes the panel draws.
import 'package:flutter/material.dart';

import 'package:govpulse/features/admin/widgets/accept_assign_dialog.dart';
import 'package:govpulse/features/admin/widgets/endorse_entity_dialog.dart';

void main() {
  final q = Uri.base.queryParameters;
  runApp(_App(forcedWidth: double.tryParse(q['w'] ?? ''), open: q['open']));
}

class _App extends StatelessWidget {
  final double? forcedWidth;
  final String? open;
  const _App({this.forcedWidth, this.open});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _Home(forcedWidth: forcedWidth, open: open),
    );
  }
}

class _Home extends StatefulWidget {
  final double? forcedWidth;
  final String? open;
  const _Home({this.forcedWidth, this.open});

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  @override
  void initState() {
    super.initState();
    final which = widget.open;
    if (which == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      switch (which) {
        case 'accept':
          showAcceptAssignDialog(context,
              recommendedOffice: 'Engineering Office');
        case 'endorse':
          showEndorseEntityDialog(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final content = Scaffold(
      backgroundColor: const Color(0xFFEEF1F6),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Report-process dialogs',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'Viewport ${MediaQuery.sizeOf(context).width.toStringAsFixed(0)}px '
                '— under 640 each dialog is a full screen with a back chevron; '
                'at or above it is a modal with NO close X.',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton(
                    onPressed: () => showAcceptAssignDialog(context,
                        recommendedOffice: 'Engineering Office'),
                    child: const Text('Accept & Assign'),
                  ),
                  FilledButton(
                    onPressed: () => showEndorseEntityDialog(context),
                    child: const Text('Endorse to External Entity'),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              const Text(
                'Work log — one box, not three',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              const Text(
                'The composer draws no card of its own: the field keeps its '
                'outline, a hairline separates it from the history, and the '
                'panel is the only frame.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 14),
              const _WorkLogPanel(),
            ],
          ),
        ),
      ),
    );

    final w = widget.forcedWidth;
    if (w == null) return content;

    // Force a viewport so one browser window can be checked at several widths.
    return Center(
      child: SizedBox(
        width: w,
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(size: Size(w, 900)),
          child: content,
        ),
      ),
    );
  }
}

/// The progress-updates panel's chrome, rebuilt from the production numbers.
class _WorkLogPanel extends StatelessWidget {
  const _WorkLogPanel();

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF1D4ED8);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: blue.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.timeline_rounded, size: 18, color: blue),
              SizedBox(width: 8),
              Text('Progress updates',
                  style:
                      TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          // The composer — no container of its own.
          TextField(
            maxLines: 4,
            minLines: 2,
            style: const TextStyle(fontSize: 13.5, height: 1.45),
            decoration: InputDecoration(
              hintText: 'What has happened since the last update?',
              hintStyle:
                  const TextStyle(fontSize: 13, color: Colors.black38),
              filled: true,
              fillColor: const Color(0xFFF7F9FC),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.black12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.black12),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _seg('Progress', Icons.pending_actions, true)),
              const SizedBox(width: 8),
              Expanded(child: _seg('Completion', Icons.check_circle, false)),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 17),
                label: const Text('Add photos'),
              ),
              FilledButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.send_rounded, size: 16),
                label: const Text('Submit for approval'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Row(
            children: [
              Icon(Icons.visibility_off_outlined,
                  size: 14, color: Colors.black45),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'An admin reviews this before the citizen can see it.',
                  style: TextStyle(fontSize: 11.5, color: Colors.black54),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, thickness: 1, color: Color(0x14000000)),
          const SizedBox(height: 12),
          const Text('No updates yet.',
              style: TextStyle(fontSize: 13, color: Colors.black54)),
        ],
      ),
    );
  }

  static Widget _seg(String label, IconData icon, bool selected) {
    const blue = Color(0xFF1D4ED8);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        color: selected ? blue.withValues(alpha: 0.10) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? blue : Colors.black12,
          width: selected ? 1.4 : 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 15, color: selected ? blue : Colors.black45),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: selected ? blue : Colors.black54,
              )),
        ],
      ),
    );
  }
}
