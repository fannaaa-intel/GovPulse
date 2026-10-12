// Preview target for Kuya Gov's FAQ chips (panel revision, 2026-10-12).
//
//   flutter build web --release -t tool/preview_kuya_faq.dart -o build/preview_kuya_faq
//
// ?mode=chips     the REAL ChatAgentScreen beside the REAL floating panel
// ?mode=answered  same, after two chips were tapped (one fact-free answer, one
//                 that reads lgu_facts and must fall back gracefully)
// ?mode=mayor     a fact-backed answer with lgu_facts unreachable
// ?mode=dialog    the "All questions" dialog
//
// Supabase points at a dead port on purpose: the AI greeting and lgu_facts both
// fail fast, which is the offline path — the chips must still answer.
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:govpulse/core/services/chat_service.dart';
import 'package:govpulse/core/services/faq_catalog.dart';
import 'package:govpulse/core/services/web_splash.dart';
import 'package:govpulse/core/widgets/Home/Chat-agent/faq_picker.dart';
import 'package:govpulse/core/widgets/Home/Chat-bubbles/chat_panel_card.dart';
import 'package:govpulse/features/home/Quick-action/Chat-with-Agent/chat_agent_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: _Boot()));
  // The real app tears the HTML boot splash down from Dart (main.dart); a
  // preview target has to do the same or the splash covers everything.
  WidgetsBinding.instance.endOfFrame.then((_) => removeWebSplash());
}

/// Initialises AFTER the first frame, showing each step, so a stalled
/// initialiser is visible in the screenshot instead of hiding behind the splash.
class _Boot extends StatefulWidget {
  const _Boot();
  @override
  State<_Boot> createState() => _BootState();
}

class _BootState extends State<_Boot> {
  String step = 'starting';
  bool ready = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      setState(() => step = 'Hive.initFlutter');
      await Hive.initFlutter();
      setState(() => step = 'Supabase.initialize');
      await Supabase.initialize(url: 'http://127.0.0.1:1', anonKey: 'preview');
      // ChatService.I.init() is skipped: its IndexedDB open never completes
      // under headless Chrome's virtual clock (a harness limit, not an app
      // one). The service opens its box lazily anyway.
      setState(() => ready = true);
    } catch (e) {
      setState(() => step = 'FAILED at $step: $e');
    }
  }

  @override
  Widget build(BuildContext context) => ready
      ? const _Preview()
      : Scaffold(body: Center(child: Text('boot: $step')));
}

class _Preview extends StatefulWidget {
  const _Preview();
  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  final mode = Uri.base.queryParameters['mode'] ?? 'chips';

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 3), () async {
      if (!mounted) return;
      if (mode == 'answered') {
        await ChatService.I.askFaq(kFaqs.firstWhere((f) => f.id == 'how_to_report'));
        await ChatService.I.askFaq(kFaqs.firstWhere((f) => f.id == 'mayor'));
      } else if (mode == 'mayor') {
        // lgu_facts is unreachable here: the answer must fall back, not hang.
        await ChatService.I.askFaq(kFaqs.firstWhere((f) => f.id == 'mayor'));
      } else if (mode == 'dialog') {
        showAllFaqs(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE5E7EB),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 760,
            height: 900,
            child: ChatAgentScreen(username: 'preview'),
          ),
          const SizedBox(width: 24),
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: HomeChatPanelCard(
              onAgentMessage: () {},
              panelW: 360,
              panelH: 520,
            ),
          ),
        ],
      ),
    );
  }
}
