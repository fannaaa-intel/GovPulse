// lib/core/widgets/Home/sections/Web/home_stats_bar.dart

import 'package:flutter/material.dart';

class HomeStatsBar extends StatelessWidget {
  const HomeStatsBar({super.key});

  // FIX: max content width keeps stat tiles from stretching absurdly on
  // ultra-wide screens (> 1280 px). Matches the dashboard's _kDashboardMaxWidth.
  static const double _kMaxWidth = 1280;

  static const _stats = [
    _StatDef(
      icon: Icons.description_rounded,
      iconColor: Color(0xFF22C55E),
      iconBg: Color(0xFF14532D),
      value: '1,245',
      label: 'Reports Submitted',
      sub: 'Total reports from citizens',
    ),
    _StatDef(
      icon: Icons.check_circle_rounded,
      iconColor: Color(0xFFFBBF24),
      iconBg: Color(0xFF78350F),
      value: '987',
      label: 'Reports Resolved',
      sub: 'Issues resolved successfully',
    ),
    _StatDef(
      icon: Icons.people_rounded,
      iconColor: Color(0xFF60A5FA),
      iconBg: Color(0xFF1E3A5F),
      value: '12,456',
      label: 'Active Users',
      sub: 'Citizens actively using GovPulse',
    ),
    _StatDef(
      icon: Icons.account_balance_rounded,
      iconColor: Color(0xFFA78BFA),
      iconBg: Color(0xFF3B1F6E),
      value: '24',
      label: 'Government Services',
      sub: 'Access various LGU services online',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0A1628), Color(0xFF0D2352), Color(0xFF10337A)],
          stops: [0.0, 0.5, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 32,
            spreadRadius: -4,
            offset: const Offset(0, -6),
          ),
          BoxShadow(
            color: const Color(0xFF0D2352).withOpacity(0.30),
            blurRadius: 48,
            spreadRadius: 0,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      // FIX: wrap everything in a Center + ConstrainedBox so tiles never
      // spread wider than the dashboard content band on ultra-wide screens.
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kMaxWidth),
          child: Padding(
            // FIX: horizontal padding is responsive — narrow on small web
            // (900 px) so tiles don't become unreadably thin.
            padding: const EdgeInsets.symmetric(vertical: 36),
            child: LayoutBuilder(
              builder: (context, c) {
                // FIX: use LayoutBuilder width (content band) not screen width
                // for all breakpoint decisions, consistent with other panels.
                final w = c.maxWidth;
                final hPad = w < 600 ? 16.0 : 40.0;

                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: hPad),
                  child: Column(
                    children: [
                      const Text(
                        'Your Voice. Our Action. Better Aparri.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 28),
                      _buildGrid(w),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGrid(double w) {
    // Single column for very narrow web (shouldn't happen often but safe)
    if (w < 480) {
      return Center(
        child: IntrinsicWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int i = 0; i < _stats.length; i++) ...[
                _StatTile(data: _stats[i], compact: true),
                if (i < _stats.length - 1) const SizedBox(height: 18),
              ],
            ],
          ),
        ),
      );
    }

    // Two-column grid for medium-narrow web (900–1050 px drawer falls through
    // but just in case the layout resolves to top-nav at an odd breakpoint).
    if (w < 700) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: _StatTile(data: _stats[0], compact: false)),
              _vDivider(),
              Expanded(child: _StatTile(data: _stats[1], compact: false)),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _StatTile(data: _stats[2], compact: false)),
              _vDivider(),
              Expanded(child: _StatTile(data: _stats[3], compact: false)),
            ],
          ),
        ],
      );
    }

    // Four-column layout (900 px+): FIX — pass the per-tile width so the
    // tile can scale its value font instead of overflowing on 900 px.
    final tileW = (w - 3 * 1.0) / 4; // 3 dividers of width 1
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (int i = 0; i < _stats.length; i++) ...[
          Expanded(
            child: _StatTile(data: _stats[i], compact: tileW < 220),
          ),
          if (i < _stats.length - 1) _vDivider(),
        ],
      ],
    );
  }

  Widget _vDivider() =>
      Container(width: 1, height: 60, color: Colors.white.withOpacity(0.10));
}

class _StatDef {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String value;
  final String label;
  final String sub;

  const _StatDef({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.value,
    required this.label,
    required this.sub,
  });
}

class _StatTile extends StatelessWidget {
  final _StatDef data;

  /// When true the tile is in a narrow column — shrink value font slightly
  /// and hide the sub-label to prevent overflow.
  final bool compact;

  const _StatTile({required this.data, required this.compact});

  @override
  Widget build(BuildContext context) {
    // FIX: scale value font down on compact tiles (900–1050 px four-column)
    // so "12,456" doesn't overflow a ~200 px tile.
    final double valueFs = compact ? 18.0 : 22.0;
    final double labelFs = compact ? 11.0 : 12.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: compact ? 40 : 48,
            height: compact ? 40 : 48,
            decoration: BoxDecoration(
              color: data.iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              data.icon,
              size: compact ? 20 : 24,
              color: data.iconColor,
            ),
          ),
          const SizedBox(width: 14),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  data.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: valueFs,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  data.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: labelFs,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                  ),
                ),
                // FIX: hide sub-label on compact tiles — it would wrap or
                // overflow in a ~200 px column at 10.5 px.
                if (!compact)
                  Text(
                    data.sub,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: Colors.white.withOpacity(0.40),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
