// lib/core/widgets/Home/sections/Web/home_quick_actions_section_web.dart

import 'package:flutter/material.dart';
import 'package:govpulse/core/widgets/Home/sections/Web/home_community_section_web.dart'
    show WebGlassPanel;

class HomeQuickActionsSectionWeb extends StatelessWidget {
  final ValueChanged<String> onActionTap;
  final double? height;
  const HomeQuickActionsSectionWeb({
    super.key,
    required this.onActionTap,
    this.height,
  });

  static const List<_ActionDef> _actions = [
    _ActionDef(
      key: 'chat',
      iconPath: 'assets/images/customer.webp',
      fallback: Icons.support_agent_rounded,
      title: 'Chat with Agent',
      subtitle: 'Talk to our support team',
      gradA: Color(0xFF3B82F6),
      gradB: Color(0xFF1D4ED8),
      accent: Color(0xFF3B82F6),
      iconBg: Color(0xFFEFF6FF),
    ),
    _ActionDef(
      key: 'report',
      iconPath: 'assets/images/problem.webp',
      fallback: Icons.report_problem_rounded,
      title: 'Report an Issue',
      subtitle: 'Report problems in your community',
      gradA: Color(0xFFF87171),
      gradB: Color(0xFFDC2626),
      accent: Color(0xFFEF4444),
      iconBg: Color(0xFFFFF5F5),
    ),
    _ActionDef(
      key: 'events',
      iconPath: 'assets/images/events.webp',
      fallback: Icons.event_rounded,
      title: 'View Events',
      subtitle: 'Discover upcoming events in Aparri',
      gradA: Color(0xFF34D399),
      gradB: Color(0xFF059669),
      accent: Color(0xFF10B981),
      iconBg: Color(0xFFF0FDF4),
    ),
    _ActionDef(
      key: 'suggestion',
      iconPath: 'assets/images/suggestions.webp',
      fallback: Icons.lightbulb_rounded,
      title: 'Submit Suggestion',
      subtitle: 'Share your ideas for a better Aparri',
      gradA: Color(0xFFA78BFA),
      gradB: Color(0xFF7C3AED),
      accent: Color(0xFF8B5CF6),
      iconBg: Color(0xFFF5F3FF),
    ),
    // ─── NEW ────────────────────────────────────────────────────────────────
    _ActionDef(
      key: 'feedback',
      iconPath: 'assets/images/feedback.webp',
      fallback: Icons.star_rounded,
      title: 'Feedback',
      subtitle: 'Rate and review LGU services',
      gradA: Color(0xFFC084FC),
      gradB: Color(0xFF7C3AED),
      accent: Color(0xFF8B5CF6),
      iconBg: Color(0xFFFAF5FF),
    ),
    // ────────────────────────────────────────────────────────────────────────
  ];

  @override
  Widget build(BuildContext context) {
    final panel = WebGlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Section header ──────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 3,
                height: 36,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF7C3AED), Color(0xFF8B5CF6)],
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Quick Actions',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.4,
                    ),
                  ),
                  Text(
                    'What would you like to do today?',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF9CA3AF),
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 18),

          Container(
            width: double.infinity,
            height: 1.5,
            color: const Color(0xFFC9D2E0),
          ),

          const SizedBox(height: 18),

          // ── Action list — LayoutBuilder so each tile reads its own
          // available width and adapts icon / font sizing accordingly.
          LayoutBuilder(
            builder: (context, constraints) {
              final tileWidth = constraints.maxWidth;

              // Three breakpoint tiers:
              //   wide   ≥ 420 px  – full-size icons & fonts
              //   normal 340–419   – standard compact
              //   narrow < 340     – extra-compact (single-column narrow web)
              final _TileSizing sizing = tileWidth >= 420
                  ? const _TileSizing(
                      boxSize: 48,
                      imgSize: 25,
                      titleFs: 14,
                      subFs: 12,
                      hPad: 14,
                      vPad: 12,
                      gap: 14,
                      maxSubLines: 2,
                    )
                  : tileWidth >= 340
                  ? const _TileSizing(
                      boxSize: 42,
                      imgSize: 22,
                      titleFs: 13,
                      subFs: 11,
                      hPad: 12,
                      vPad: 10,
                      gap: 12,
                      maxSubLines: 1,
                    )
                  : const _TileSizing(
                      boxSize: 36,
                      imgSize: 18,
                      titleFs: 12,
                      subFs: 10,
                      hPad: 10,
                      vPad: 9,
                      gap: 10,
                      maxSubLines: 1,
                    );

              return Column(
                children: [
                  for (int i = 0; i < _actions.length; i++) ...[
                    _ActionTile(
                      def: _actions[i],
                      onTap: () => onActionTap(_actions[i].key),
                      sizing: sizing,
                    ),
                    if (i < _actions.length - 1)
                      Container(
                        height: 1,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        color: const Color(0xFFF1F5FD),
                      ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );

    if (height != null) {
      return SizedBox(height: height, child: panel);
    }
    return panel;
  }
}

// ── Sizing token bag ──────────────────────────────────────────────────────────

class _TileSizing {
  final double boxSize;
  final double imgSize;
  final double titleFs;
  final double subFs;
  final double hPad;
  final double vPad;
  final double gap;
  final int maxSubLines;

  const _TileSizing({
    required this.boxSize,
    required this.imgSize,
    required this.titleFs,
    required this.subFs,
    required this.hPad,
    required this.vPad,
    required this.gap,
    required this.maxSubLines,
  });
}

// ── Action definition ─────────────────────────────────────────────────────────

class _ActionDef {
  final String key;
  final String iconPath;
  final IconData fallback;
  final String title;
  final String subtitle;
  final Color gradA;
  final Color gradB;
  final Color accent;
  final Color iconBg;

  const _ActionDef({
    required this.key,
    required this.iconPath,
    required this.fallback,
    required this.title,
    required this.subtitle,
    required this.gradA,
    required this.gradB,
    required this.accent,
    required this.iconBg,
  });
}

// ── Action tile ───────────────────────────────────────────────────────────────

class _ActionTile extends StatefulWidget {
  final _ActionDef def;
  final VoidCallback onTap;
  final _TileSizing sizing;

  const _ActionTile({
    required this.def,
    required this.onTap,
    required this.sizing,
  });

  @override
  State<_ActionTile> createState() => _ActionTileState();
}

class _ActionTileState extends State<_ActionTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.def;
    final s = widget.sizing;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: EdgeInsets.symmetric(horizontal: s.hPad, vertical: s.vPad),
          decoration: BoxDecoration(
            // Gray-flash fix: fade from d.iconBg at ZERO opacity so the RGB
            // channel never changes — only alpha 0→1 moves.
            color: _hover ? d.iconBg : d.iconBg.withOpacity(0.0),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: d.accent.withOpacity(_hover ? 0.25 : 0.0),
              width: 1.2,
            ),
          ),
          child: Row(
            children: [
              // ── Icon box ──────────────────────────────────────────
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                width: s.boxSize,
                height: s.boxSize,
                decoration: BoxDecoration(
                  gradient: _hover
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [d.gradA, d.gradB],
                        )
                      : LinearGradient(
                          colors: [
                            d.accent.withOpacity(0.12),
                            d.accent.withOpacity(0.12),
                          ],
                        ),
                  borderRadius: BorderRadius.circular(13),
                  boxShadow: _hover
                      ? [
                          BoxShadow(
                            color: d.accent.withOpacity(0.28),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : [],
                ),
                child: Center(
                  child: Image.asset(
                    d.iconPath,
                    width: s.imgSize,
                    height: s.imgSize,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => Icon(
                      d.fallback,
                      size: s.imgSize,
                      color: _hover ? Colors.white : d.accent,
                    ),
                  ),
                ),
              ),

              SizedBox(width: s.gap),

              // ── Labels ────────────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      style: TextStyle(
                        fontSize: s.titleFs,
                        fontWeight: FontWeight.w700,
                        color: _hover ? d.accent : const Color(0xFF111827),
                      ),
                      child: Text(
                        d.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      d.subtitle,
                      maxLines: s.maxSubLines,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: s.subFs,
                        color: const Color(0xFF9CA3AF),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Arrow ─────────────────────────────────────────────
              AnimatedSlide(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                offset: Offset(_hover ? 0.2 : 0, 0),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    // Same gray-flash fix for the arrow circle.
                    color: d.accent.withOpacity(_hover ? 0.12 : 0.0),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: 15,
                    color: _hover ? d.accent : const Color(0xFFD1D5DB),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
