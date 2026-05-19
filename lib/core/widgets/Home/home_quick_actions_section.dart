import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class HomeQuickActionsSection extends StatelessWidget {
  final double width;
  final ValueChanged<String> onActionTap;

  const HomeQuickActionsSection({
    super.key,
    required this.width,
    required this.onActionTap,
    ScrollController? scrollController,
    int currentDot = 0,
    ValueChanged<int>? onDotChanged,
  });

  static const List<Map<String, dynamic>> _actions = [
    {
      'key': 'report',
      'iconPath': 'assets/images/problem.png',
      'title': 'Report Issue',
      'subtitle': 'Report a problem in your area',
      'accentColor': Color(0xFFEF4444),
    },
    {
      'key': 'chat',
      'iconPath': 'assets/images/customer.png',
      'title': 'Chat with Agent',
      'subtitle': 'Talk to an LGU support agent',
      'accentColor': Color(0xFF3B82F6),
    },
    {
      'key': 'events',
      'iconPath': 'assets/images/events.png',
      'title': 'Events',
      'subtitle': 'Browse upcoming local events',
      'accentColor': Color(0xFF22C55E),
    },
    {
      'key': 'suggestion',
      'iconPath': 'assets/images/suggestions.png',
      'title': 'Suggestion',
      'subtitle': 'Share your ideas with the LGU',
      'accentColor': Color(0xFF60A5FA),
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: width * 0.04),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(width * 0.04),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(width * 0.04),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quick Action',
              style: TextStyle(
                color: AppColors.primaryBlue,
                fontSize: width * 0.047,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: width * 0.03),
            ...List.generate(
              _actions.length,
              (i) => Column(
                children: [
                  _buildCard(_actions[i]),
                  if (i < _actions.length - 1) SizedBox(height: width * 0.025),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> a) {
    final accent = a['accentColor'] as Color;
    final key = a['key'] as String;

    return GestureDetector(
      onTap: () => onActionTap(key),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: width * 0.04,
          vertical: width * 0.035,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(width * 0.03),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .04),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: width * 0.13,
              height: width * 0.13,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(width * 0.03),
              ),
              child: Center(
                child: Image.asset(
                  a['iconPath'] as String,
                  width: width * 0.075,
                  height: width * 0.075,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            SizedBox(width: width * 0.04),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    a['title'] as String,
                    style: TextStyle(
                      fontSize: width * 0.038,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF111827),
                    ),
                  ),
                  SizedBox(height: width * 0.008),
                  Text(
                    a['subtitle'] as String,
                    style: TextStyle(
                      fontSize: width * 0.031,
                      color: const Color(0xFF6B7280),
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: width * 0.055,
              color: const Color(0xFF9CA3AF),
            ),
          ],
        ),
      ),
    );
  }
}
