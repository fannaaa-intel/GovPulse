// Dev-only harness proving the Material 3 surface tint fix.
//
//   flutter build web --release -t tool/preview_popup_surface_tint.dart
//   python -m http.server 57817 --directory build/web
//
// LEFT  = the OLD theme (bare `ThemeData()`), which seeds M3 from Flutter's
//         default PURPLE. Its popup menus, dialogs and dropdowns render on
//         `surfaceContainer` #F3EDF7 — the lavender tint that was reported.
// RIGHT = the NEW `_appTheme` shape from main.dart: seeded from our blue with
//         every surface pinned white and the elevation tint removed.
//
// Same widgets, same code, only the Theme differs — so any colour difference
// is the tint and nothing else.

import 'package:flutter/material.dart';
import 'package:govpulse/core/theme/app_colors.dart';

// Mirrors _appTheme in main.dart.
ThemeData fixedTheme() {
  final base = ColorScheme.fromSeed(seedColor: AppColors.primaryBlue);
  final scheme = base.copyWith(
    surface: Colors.white,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Colors.white,
    surfaceContainer: Colors.white,
    surfaceContainerHigh: Colors.white,
    surfaceContainerHighest: const Color(0xFFF4F6FA),
    surfaceTint: Colors.transparent,
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.white,
    canvasColor: Colors.white,
    popupMenuTheme: const PopupMenuThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
    ),
    drawerTheme: const DrawerThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: const CardThemeData(surfaceTintColor: Colors.transparent),
    appBarTheme: const AppBarTheme(surfaceTintColor: Colors.transparent),
  );
}

void main() => runApp(const _App());

class _App extends StatelessWidget {
  const _App();
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: fixedTheme(),
        home: const _Page(),
      );
}

class _Page extends StatelessWidget {
  const _Page();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Theme(
                data: ThemeData(scaffoldBackgroundColor: Colors.white),
                child: const _Column(label: 'BEFORE — bare ThemeData()'),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: _Column(label: 'AFTER — _appTheme')),
          ],
        ),
      ),
    );
  }
}

class _Column extends StatelessWidget {
  final String label;
  const _Column({required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('surfaceContainer = ${_hex(cs.surfaceContainer)}\n'
              'surface = ${_hex(cs.surface)}',
              style: const TextStyle(fontSize: 11, color: Colors.black54)),
          const SizedBox(height: 14),

          // The exact swatch a PopupMenu paints on.
          const Text('Swatches', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Row(children: [
            _sw('surface', cs.surface),
            _sw('surfContainer', cs.surfaceContainer),
            _sw('surfCntHigh', cs.surfaceContainerHigh),
          ]),
          const SizedBox(height: 18),

          // A real account menu, opened inline so it shows in a screenshot.
          const Text('Account menu (as rendered)',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            // No explicit colour: this is exactly what PopupMenuButton does,
            // so it picks up the theme's popup/surface colour.
            color: Theme.of(context).popupMenuTheme.color,
            surfaceTintColor: Theme.of(context).popupMenuTheme.surfaceTintColor,
            child: SizedBox(
              width: 210,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  SizedBox(height: 8),
                  _Row(icon: Icons.edit_rounded, label: 'Edit profile'),
                  _Row(icon: Icons.lock_outline_rounded, label: 'Change password'),
                  Divider(height: 9),
                  _Row(
                      icon: Icons.logout_rounded,
                      label: 'Log out',
                      danger: true),
                  SizedBox(height: 8),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),

          const Text('Dialog / Card / Drawer',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(14),
            color: Theme.of(context).dialogTheme.backgroundColor,
            surfaceTintColor: Theme.of(context).dialogTheme.surfaceTintColor,
            child: const SizedBox(
              width: 240,
              height: 74,
              child: Center(child: Text('Dialog surface')),
            ),
          ),
          const SizedBox(height: 10),
          const Card(
            elevation: 6,
            child: SizedBox(
                width: 240, height: 58, child: Center(child: Text('Card'))),
          ),
        ],
      ),
    );
  }

  static String _hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  static Widget _sw(String name, Color c) => Container(
        margin: const EdgeInsets.only(right: 8),
        width: 96,
        height: 52,
        decoration: BoxDecoration(
          color: c,
          border: Border.all(color: Colors.black26),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(name, style: const TextStyle(fontSize: 9)),
      );
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool danger;
  const _Row({required this.icon, required this.label, this.danger = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(children: [
          Icon(icon,
              size: 18,
              color: danger ? const Color(0xFFE53935) : Colors.black54),
          const SizedBox(width: 10),
          Text(label,
              style: TextStyle(
                  fontSize: 14,
                  color: danger ? const Color(0xFFE53935) : Colors.black87)),
        ]),
      );
}
