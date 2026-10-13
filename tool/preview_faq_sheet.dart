// Preview target for the FAQ picker's presentation split (2026-10-13).
//
//   flutter build web --release -t tool/preview_faq_sheet.dart -o build/preview_faq_sheet
//
// ?mode=phone    opens showAllFaqs inside a 359px-wide surface -> bottom sheet
// ?mode=wide     opens it inside a 1100px-wide surface        -> centred dialog
//
// The point is the BREAKPOINT, so each mode forces its own width with a
// MediaQuery override rather than relying on the browser window: that way one
// build proves both branches, and the phone case is reproducible at the exact
// width the bug was reported at.
//
// No Supabase and no Hive here. The FAQ list is a const catalogue in the app
// (faq_catalog.dart) and the picker reads nothing else, so this target needs no
// backend at all -- which also keeps it off the Hive-on-IndexedDB stall that
// preview_kuya_faq.dart has to work around.
import 'package:flutter/material.dart';
import 'package:govpulse/core/services/web_splash.dart';
import 'package:govpulse/core/widgets/Home/Chat-agent/faq_picker.dart';

String get _mode {
  final m = Uri.base.queryParameters['mode'];
  return (m == null || m.isEmpty) ? 'phone' : m;
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: _Host()));
  WidgetsBinding.instance.endOfFrame.then((_) => removeWebSplash());
}

class _Host extends StatelessWidget {
  const _Host();

  @override
  Widget build(BuildContext context) {
    final phone = _mode == 'phone';
    final w = phone ? 359.0 : 1100.0;
    return Scaffold(
      backgroundColor: const Color(0xFF4A3A4A),
      body: Center(
        child: Container(
          width: w,
          height: 760,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(8),
          ),
          // The override is what makes the picker believe it is on a phone (or
          // a desktop): showAllFaqs branches on MediaQuery width, so forcing
          // the width here exercises the real code path, not a copy of it.
          child: MediaQuery(
            data: MediaQueryData(size: Size(w, 760)),
            child: const _OpenOnFirstFrame(),
          ),
        ),
      ),
    );
  }
}

class _OpenOnFirstFrame extends StatefulWidget {
  const _OpenOnFirstFrame();
  @override
  State<_OpenOnFirstFrame> createState() => _OpenOnFirstFrameState();
}

class _OpenOnFirstFrameState extends State<_OpenOnFirstFrame> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showAllFaqs(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Something behind the pop-up, so the scrim and the sheet's rounded top
    // are visible against real content rather than flat white.
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Ask Kuya Gov',
          style: TextStyle(fontSize: 16, color: Colors.black87),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 8,
        itemBuilder: (_, i) => Container(
          height: 54,
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }
}
