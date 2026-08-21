// Dev-only device simulator for the MOBILE citizen app.
//
// Not part of the app: nothing under lib/ imports it, and it is never a build
// target for a shipped bundle.
//
//   flutter run -d windows -t tool/preview_mobile_responsive.dart
//
// ── Why Windows and not the web-server target ─────────────────────────────
// The other harnesses in this folder run `-d web-server` because what they
// preview IS the web layout. This one previews the opposite side of every
// `kIsWeb` branch in the codebase — the layout Android and iOS get — and on a
// web target that branch is unreachable by construction. A desktop target has
// `kIsWeb == false`, so every screen opened here takes exactly the branch the
// shipped handset app takes.
//
// ── Why the frame rather than resizing the window ─────────────────────────
// Two things a resized window cannot show. First, `viewPadding`: on Android 15
// the app is edge-to-edge whether it asks or not, so the real question is
// where the chrome sits relative to a 48dp 3-button bar or a 24dp gesture
// handle, and a desktop window has neither. Second, side-by-side comparison —
// the bugs this was built to find are rotation bugs, and the only way to see
// one is to put portrait and landscape next to each other and check that the
// type did not change size between them.
//
// Supabase is initialised with the app's own credentials because most of these
// screens read the client on the way up. Nothing signs in, so the session is
// anonymous: screens that need a user render their empty/skeleton/error state,
// which is the correct thing to be auditing anyway — it is the CHROME, the
// gutters and the type scale that this harness exists to look at.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:govpulse/core/theme/app_colors.dart';
import 'package:govpulse/features/home/Quick-action/Events/events_screen.dart';
import 'package:govpulse/features/home/Quick-action/Feedback/feedback_screen.dart';
import 'package:govpulse/features/home/Quick-action/Report/report_issue_screen.dart';
import 'package:govpulse/features/home/Quick-action/Suggestion/suggestion_screen.dart';
import 'package:govpulse/features/home/emergency/emergency_screen.dart';
import 'package:govpulse/features/home/my_report/my_reports_screen.dart';
import 'package:govpulse/features/home/newsfeed/news_feed_screen.dart';
import 'package:govpulse/features/home/screen/home_screen.dart';
import 'package:govpulse/features/home/settings/settings_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://vxvflhjbafqwehuxnmeq.supabase.co',
    anonKey: 'sb_publishable_ZBDaQPQdFyC5kOHGbce9Ig_zdtIi6Mo',
  );
  runApp(const ProviderScope(child: _PreviewApp()));
}

// ── The device matrix ───────────────────────────────────────────────────────
//
// Shortest side stays under 600 on every phone here so `resolveNavBand` keeps
// them on NavBand.phone in BOTH orientations — which is the point: a rotated
// handset is still a handset, and must not fall through to the tablet drawer.

class _Device {
  final String name;
  final Size portrait;
  const _Device(this.name, this.portrait);
}

const _devices = <_Device>[
  _Device('small · 320×568', Size(320, 568)),
  _Device('compact · 360×640', Size(360, 640)),
  _Device('modern · 390×844', Size(390, 844)),
  _Device('large · 430×932', Size(430, 932)),
  _Device('tablet · 768×1024', Size(768, 1024)),
];

/// How Android is drawing its own navigation, and what that costs the app.
///
/// In 3-button landscape the bar moves to a SIDE — that is the case the app's
/// bottom nav used to walk straight into.
enum _SysNav { gesture, threeButton }

EdgeInsets _viewPadding(_SysNav nav, bool landscape) => switch ((nav, landscape)) {
  (_SysNav.gesture, false) => const EdgeInsets.only(top: 44, bottom: 24),
  (_SysNav.gesture, true) => const EdgeInsets.only(bottom: 16),
  (_SysNav.threeButton, false) => const EdgeInsets.only(top: 44, bottom: 48),
  // Rotated left: status bar on the left, nav bar on the right.
  (_SysNav.threeButton, true) => const EdgeInsets.only(left: 44, right: 48),
};

// ── Screens ─────────────────────────────────────────────────────────────────

const _kUser = 'preview';

final _screens = <String, Widget Function()>{
  'Home': () => const HomePage(username: _kUser),
  'My Reports': () => const MyReportsScreen(username: _kUser),
  'NewsFeed': () => const NewsFeedScreen(username: _kUser, isVerified: true),
  'Emergency': () => const EmergencyScreen(username: _kUser, isVerified: true),
  'Settings': () => const SettingScreen(username: _kUser),
  'Report Issue': () => const ReportIssueScreen(username: _kUser),
  'Suggestion': () => const SuggestionScreen(username: _kUser),
  'Feedback': () => const FeedbackScreen(username: _kUser),
  'Events': () => const EventsScreen(username: _kUser, isVerified: true),
};

class _PreviewApp extends StatefulWidget {
  const _PreviewApp();
  @override
  State<_PreviewApp> createState() => _PreviewAppState();
}

class _PreviewAppState extends State<_PreviewApp> {
  String _screen = 'Home';
  _Device _device = _devices[2];
  _SysNav _nav = _SysNav.gesture;
  double _textScale = 1.0;
  bool _bothOrientations = true;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'GovPulse mobile — responsiveness preview',
      theme: ThemeData(useMaterial3: true, fontFamily: 'Roboto'),
      home: Scaffold(
        backgroundColor: const Color(0xFF111827),
        body: SafeArea(
          child: Column(
            children: [
              _controls(),
              const Divider(height: 1, color: Color(0xFF374151)),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _frame(landscape: false),
                      if (_bothOrientations) ...[
                        const SizedBox(width: 32),
                        _frame(landscape: true),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _controls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: const Color(0xFF1F2937),
      child: Wrap(
        spacing: 20,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _dropdown<String>(
            'Screen',
            _screen,
            _screens.keys.toList(),
            (v) => setState(() => _screen = v),
            (v) => v,
          ),
          _dropdown<_Device>(
            'Device',
            _device,
            _devices,
            (v) => setState(() => _device = v),
            (v) => v.name,
          ),
          _dropdown<_SysNav>(
            'System nav',
            _nav,
            _SysNav.values,
            (v) => setState(() => _nav = v),
            (v) => v == _SysNav.gesture ? 'gesture' : '3-button',
          ),
          _dropdown<double>(
            'Text scale',
            _textScale,
            const [1.0, 1.3, 1.6, 2.0],
            (v) => setState(() => _textScale = v),
            (v) => '${v}x',
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: _bothOrientations,
                onChanged: (v) => setState(() => _bothOrientations = v ?? true),
                fillColor: WidgetStatePropertyAll(AppColors.primaryBlue),
              ),
              const Text(
                'both orientations',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dropdown<T>(
    String label,
    T value,
    List<T> items,
    ValueChanged<T> onChanged,
    String Function(T) name,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label  ', style: const TextStyle(color: Color(0xFF9CA3AF))),
        DropdownButton<T>(
          value: value,
          dropdownColor: const Color(0xFF1F2937),
          style: const TextStyle(color: Colors.white),
          underline: const SizedBox.shrink(),
          items: [
            for (final i in items)
              DropdownMenuItem(value: i, child: Text(name(i))),
          ],
          onChanged: (v) => v == null ? null : onChanged(v),
        ),
      ],
    );
  }

  /// One device, at 1:1 logical pixels, with the system-nav insets painted on
  /// top so it is obvious when something has been laid out underneath them.
  Widget _frame({required bool landscape}) {
    final size = landscape
        ? Size(_device.portrait.height, _device.portrait.width)
        : _device.portrait;
    final pad = _viewPadding(_nav, landscape);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${landscape ? 'landscape' : 'portrait'}  '
          '${size.width.toInt()}×${size.height.toInt()}',
          style: const TextStyle(
            color: Color(0xFF9CA3AF),
            fontSize: 12,
            letterSpacing: .4,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF4B5563), width: 2),
            borderRadius: BorderRadius.circular(6),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: Stack(
                children: [
                  MediaQuery(
                    data: MediaQueryData(
                      size: size,
                      padding: pad,
                      viewPadding: pad,
                      textScaler: TextScaler.linear(_textScale),
                      devicePixelRatio: 1,
                    ),
                    // A fresh Navigator per frame so pushes inside one device
                    // stay inside it.
                    child: Navigator(
                      onGenerateRoute: (_) => MaterialPageRoute(
                        builder: (_) => _screens[_screen]!(),
                      ),
                    ),
                  ),
                  // The system-nav overlay. Anything the app draws under this
                  // tint is something the user cannot reach.
                  IgnorePointer(
                    child: Stack(
                      children: [
                        if (pad.bottom > 0)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            height: pad.bottom,
                            child: const ColoredBox(color: Color(0x33FF0055)),
                          ),
                        if (pad.right > 0)
                          Positioned(
                            top: 0,
                            bottom: 0,
                            right: 0,
                            width: pad.right,
                            child: const ColoredBox(color: Color(0x33FF0055)),
                          ),
                        if (pad.left > 0)
                          Positioned(
                            top: 0,
                            bottom: 0,
                            left: 0,
                            width: pad.left,
                            child: const ColoredBox(color: Color(0x2200AAFF)),
                          ),
                        if (pad.top > 0)
                          Positioned(
                            left: 0,
                            right: 0,
                            top: 0,
                            height: pad.top,
                            child: const ColoredBox(color: Color(0x2200AAFF)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
