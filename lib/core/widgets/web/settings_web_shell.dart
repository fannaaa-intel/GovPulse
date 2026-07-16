// lib/core/widgets/web/settings_web_shell.dart
//
// Reusable WEB shell for the Settings sub-screens (Edit Profile is bespoke; this
// covers Contact Support, Change Password, My Submissions, About, Terms,
// Privacy…). On wide screens it places a static brand/context panel on the left
// and the screen's existing body on the right, so the page fills the width and
// reads like a real web app instead of a stranded phone column.
//
// It is additive: below [breakpoint] it returns [child] untouched, so phones and
// the mobile app render byte-for-byte the same. On the right it overrides the
// MediaQuery width to [contentWidth] so each screen's existing `width.clamp(480)`
// sizing (and any ResponsivePageBody) stays self-consistent and never overflows.

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import 'web_constants.dart'; // kHeroBgTop / kHeroBgBottom
import 'web_hero_panel.dart' show GridPainter, GlowOrb;

/// One fixed content width for EVERY shelled screen, so the content column and
/// the brand panel stay the same size no matter which sub-screen you're on.
const double kShellContentWidth = 600;

class SettingsWebShell extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<(IconData, String)> highlights;
  final Widget child;

  /// Width of the right-hand content column on wide screens.
  final double contentWidth;
  final double breakpoint;

  const SettingsWebShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
    this.highlights = const [],
    this.contentWidth = 520,
    this.breakpoint = 900,
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    if (mq.size.width < breakpoint) return child;

    return ColoredBox(
      color: const Color(0xFFF3F4F6),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Content on the LEFT …
              Container(
                width: kShellContentWidth,
                decoration: const BoxDecoration(
                  color: Color(0xFFF3F4F6),
                  border: Border(
                    right: BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                ),
                child: MediaQuery(
                  data: mq.copyWith(
                    size: Size(kShellContentWidth, mq.size.height),
                  ),
                  child: child,
                ),
              ),
              // … brand/context panel on the RIGHT.
              Expanded(child: _panel()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _panel() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [kHeroBgTop, kHeroBgBottom],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: -120,
            top: -80,
            child: GlowOrb(
              size: 460,
              color: AppColors.primaryBlue.withValues(alpha: 0.28),
            ),
          ),
          Positioned(
            right: -80,
            bottom: -100,
            child: GlowOrb(
              size: 360,
              color: AppColors.green.withValues(alpha: 0.12),
            ),
          ),
          Positioned.fill(child: CustomPaint(painter: GridPainter())),
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, c) {
                final bool showHighlights = c.maxHeight > 520;
                return SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: c.maxHeight),
                    child: Padding(
                      padding: const EdgeInsets.all(56),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.10),
                              ),
                            ),
                            child: Icon(icon, size: 27, color: Colors.white),
                          ),
                          const SizedBox(height: 32),
                          Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 36,
                              fontWeight: FontWeight.w800,
                              height: 1.08,
                              letterSpacing: -1.2,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            subtitle,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.52),
                              fontSize: 15,
                              height: 1.6,
                            ),
                          ),
                          if (showHighlights && highlights.isNotEmpty) ...[
                            const SizedBox(height: 40),
                            ...highlights.map(_highlightRow),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _highlightRow((IconData, String) item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
            ),
            child: Icon(
              item.$1,
              size: 16,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(width: 14),
          Flexible(
            child: Text(
              item.$2,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.64),
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
