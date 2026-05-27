import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// Segmented (4-bar) password-strength indicator for web.
class WebStrengthBar extends StatelessWidget {
  final int score; // 0..4
  final Color color;
  const WebStrengthBar({super.key, required this.score, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(4, (i) {
        final active = i < score;
        return Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            margin: EdgeInsets.only(right: i < 3 ? 6 : 0),
            height: 4,
            decoration: BoxDecoration(
              color: active ? color : AppColors.stroke,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }
}
