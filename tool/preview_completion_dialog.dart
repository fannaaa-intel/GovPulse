// Preview target: the staff "Mark this report resolved" dialog — the second of
// the two presses that close a report, and the one that collects the account of
// what was done.
//
//   flutter run -d web-server --web-port 57961 -t tool/preview_completion_dialog.dart
//
// Mounts the REAL dialog (it touches Supabase only on submit, which the preview
// never reaches), so what is on screen is the shipping widget.
//
// ── ONE WIDTH AT A TIME, ON PURPOSE ─────────────────────────────────────────
// An earlier version of this file tried to render all three widths side by
// side by nesting each in its own Navigator + MediaQuery override. It did not
// work and could not: showDialog walks to the ROOT navigator, so every nested
// copy escaped its frame and drew one dialog over the whole page. A preview
// that shows one thing while claiming to show three is worse than no preview.
//
// So the width is a query parameter and the shapes are checked one at a time.
// AdminResponsiveDialog switches at kAdminDialogFullscreenBelow (640), so:
//
//   ?w=380   the full-bleed phone form — header pinned, body scrolling,
//            actions on the floor
//   ?w=700   the narrow modal
//   ?w=1100  the desktop modal, capped at the dialog's own maxWidth of 520
//
// Add ?error=1 to open with the required-note error already showing, which is
// the state most likely to shift the layout.
import 'package:flutter/material.dart';

import 'package:govpulse/features/staff/widgets/staff_completion_dialog.dart';

void main() {
  final q = Uri.base.queryParameters;
  runApp(
    _App(
      width: double.tryParse(q['w'] ?? '380') ?? 380,
      error: q['error'] == '1',
    ),
  );
}

class _App extends StatelessWidget {
  final double width;
  final bool error;
  const _App({required this.width, required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      // The dialog reads MediaQuery to pick its shape, so the override has to
      // wrap the whole app rather than a box inside it.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          size: Size(width, MediaQuery.sizeOf(context).height),
        ),
        child: child!,
      ),
      home: _Host(width: width, error: error),
    );
  }
}

class _Host extends StatefulWidget {
  final double width;
  final bool error;
  const _Host({required this.width, required this.error});

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    if (!mounted) return;
    final r = await showStaffCompletionDialog(
      context,
      office: 'Engineering Office',
    );
    if (!mounted) return;
    // Reopen, so the preview never lands on an empty page after a Cancel.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          r == null
              ? 'Cancelled — reopening.'
              : 'Would resolve with ${r.photos.length} photo(s): "${r.body}"',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) _open();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEEF2F8),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Completion dialog at ${widget.width.toInt()}px\n\n'
            'Change with ?w=380 | 700 | 1100',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
          ),
        ),
      ),
    );
  }
}
