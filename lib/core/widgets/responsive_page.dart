// lib/core/widgets/responsive_page.dart
//
// Wraps a standalone (non-nav) page body — detail screens, settings sub-pages,
// info/legal pages — so it centres into a readable fixed-width column on wide
// (tablet / desktop) viewports instead of stretching edge-to-edge.
//
// On any viewport at or below [maxWidth] it returns the child untouched, so
// phones and narrow tablets render exactly as before. On wider viewports it
// centres the body and clamps the MediaQuery width the child sees, which keeps
// each page's internal `width * 0.xx` sizing self-consistent and prevents
// horizontal overflow inside the narrower column.
//
//   return Scaffold(
//     body: ResponsivePageBody(
//       child: SafeArea(child: <existing column>),
//     ),
//   );

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'web/settings_web_shell.dart';
import 'citizen_shell_scope.dart';

class ResponsivePageBody extends StatelessWidget {
  final Widget child;

  /// Readable column width on wide screens. Defaults to a comfortable reading
  /// measure for text-heavy pages; forms can pass something narrower.
  final double maxWidth;

  // ── Optional WEB shell (Settings sub-pages) ─────────────────────────────────
  // When [shellTitle] is set and the viewport is at/above [shellBreakpoint], the
  // page is shown as a brand/context panel + content (SettingsWebShell) so it
  // fills the width like a real web app. Below the breakpoint (and on the mobile
  // app) it falls back to the normal centered-column behaviour, untouched.
  final String? shellTitle;
  final String? shellSubtitle;
  final IconData? shellIcon;
  final List<(IconData, String)> shellHighlights;
  final double shellContentWidth;
  final double shellBreakpoint;

  const ResponsivePageBody({
    super.key,
    required this.child,
    this.maxWidth = 820,
    this.shellTitle,
    this.shellSubtitle,
    this.shellIcon,
    this.shellHighlights = const [],
    this.shellContentWidth = 520,
    this.shellBreakpoint = 900,
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);

    // Not inside the citizen shell: there, the brand panel would be a
    // decorative hero in the middle of a pane that already has a top nav and a
    // left rail. See [CitizenShellScope].
    if (kIsWeb &&
        shellTitle != null &&
        mq.size.width >= shellBreakpoint &&
        !CitizenShellScope.of(context)) {
      return SettingsWebShell(
        title: shellTitle!,
        subtitle: shellSubtitle ?? '',
        icon: shellIcon ?? const IconData(0xe33c, fontFamily: 'MaterialIcons'),
        highlights: shellHighlights,
        contentWidth: shellContentWidth,
        breakpoint: shellBreakpoint,
        child: child,
      );
    }

    if (mq.size.width <= maxWidth) return child;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        SizedBox(
          width: maxWidth,
          child: MediaQuery(
            data: mq.copyWith(size: Size(maxWidth, mq.size.height)),
            child: child,
          ),
        ),
        const Spacer(),
      ],
    );
  }
}
