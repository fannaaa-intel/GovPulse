// Dev-only preview harness for the citizen web split-panel quick actions.
//
// Not part of the app: nothing under lib/ imports it, and it is never a build
// target for a shipped bundle. It exists so all four split panels can be opened
// in a real browser — the same widget trees the citizen web shell builds, in the
// same dialog host — without going through login, so their layout can be looked
// at instead of only asserted on in a widget test.
//
//   flutter run -d web-server --web-port 57809 -t tool/preview_quick_action_split.dart
//
// This supersedes preview_report_split.dart, which opened Report alone. Four
// panels behind one launcher rather than four targets, because the whole point
// of the mirror is that they are the same panel — and the only way to see that
// is to flip between them without restarting.
//
// Supabase is initialised with the app's own credentials because the forms'
// submit paths read the client, and because Events actually FETCHES through it;
// nothing here signs in, so the session is anonymous and Submit is never
// pressed.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:govpulse/core/theme/citizen_ui.dart';
import 'package:govpulse/features/home/Quick-action/Events/events_screen.dart';
import 'package:govpulse/features/home/Quick-action/Feedback/feedback_screen.dart';
import 'package:govpulse/features/home/Quick-action/Report/report_issue_screen.dart';
import 'package:govpulse/features/home/Quick-action/Suggestion/suggestion_screen.dart';
import 'package:govpulse/features/home/shell/citizen_docked_chat.dart';
import 'package:govpulse/features/home/shell/citizen_shell_dialogs.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://vxvflhjbafqwehuxnmeq.supabase.co',
    anonKey: 'sb_publishable_ZBDaQPQdFyC5kOHGbce9Ig_zdtIi6Mo',
  );
  runApp(const _PreviewApp());
}

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Quick-action split panels — preview',
      theme: ThemeData(useMaterial3: true, fontFamily: 'Roboto'),
      home: const _PreviewHome(),
    );
  }
}

enum _Panel { report, suggestion, feedback, events }

class _PreviewHome extends StatefulWidget {
  const _PreviewHome();

  @override
  State<_PreviewHome> createState() => _PreviewHomeState();
}

class _PreviewHomeState extends State<_PreviewHome> {
  /// Reopens the panel that was last closed, so a look at one panel is not one
  /// click of preview followed by a blank page.
  _Panel _last = _Panel.report;

  /// The docked chat, wired exactly as the shell wires it — so the narrow-band
  /// chat head and the wide-band pill can both be looked at without a login.
  DockedChatState _chat = DockedChatState.closed;

  Future<void> _open(_Panel panel) async {
    setState(() => _last = panel);

    // Events has no form to discard, so it gets no guard — exactly as the shell
    // wires it.
    if (panel == _Panel.events) {
      await showCitizenSplitPanelDialog<void>(
        context: context,
        builder: (_, close) => EventsScreen(
          username: 'Mark',
          isVerified: true,
          splitPanel: true,
          onClose: close,
          // The real shell copies the event's `/home/event/:id` address to the
          // clipboard; there is no router here, so this stands in with the same
          // shape — enough to exercise the enabled Share button.
          onShareEvent: (event) => ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Link copied for "${event.title}"')),
          ),
        ),
      );
      return;
    }

    final guard = FormDialogGuard();
    await showCitizenSplitPanelDialog<void>(
      context: context,
      guard: guard,
      builder: (_, close) => switch (panel) {
        _Panel.report => ReportIssueForm(
          username: 'Mark',
          splitPanel: true,
          guard: guard,
          onClose: close,
        ),
        _Panel.suggestion => SuggestionForm(
          username: 'Mark',
          splitPanel: true,
          guard: guard,
          onClose: close,
        ),
        _ => FeedbackForm(
          username: 'Mark',
          splitPanel: true,
          guard: guard,
          onClose: close,
        ),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // A plain stand-in for the citizen shell: the modal is what is being looked
    // at, and a busy page behind it only makes the screenshots harder to read.
    final page = Scaffold(
      backgroundColor: CitizenUi.pageBg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Quick-action split-panel preview',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: CitizenUi.textMuted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Last opened: ${_last.name}',
              style: const TextStyle(fontSize: 12, color: CitizenUi.textFaint),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              children: [
                for (final panel in _Panel.values)
                  FilledButton(
                    onPressed: () => _open(panel),
                    child: Text(panel.name),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () =>
                  setState(() => _chat = DockedChatState.open),
              child: const Text('open docked chat'),
            ),
          ],
        ),
      ),
    );

    // The shell puts the docked chat in a Stack over the page, and so does
    // this: the head has to be able to sit anywhere in the viewport, and the
    // page underneath has to stay live while it does.
    return Scaffold(
      backgroundColor: CitizenUi.pageBg,
      body: Stack(
        children: [
          Positioned.fill(child: page),
          CitizenDockedChat(
            state: _chat,
            onMinimise: () =>
                setState(() => _chat = DockedChatState.minimised),
            onRestore: () => setState(() => _chat = DockedChatState.open),
            onClose: () => setState(() => _chat = DockedChatState.closed),
          ),
        ],
      ),
    );
  }
}
