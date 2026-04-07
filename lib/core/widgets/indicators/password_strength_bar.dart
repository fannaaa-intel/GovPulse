import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class PasswordStrengthBar extends StatelessWidget {
  final int score;

  const PasswordStrengthBar({super.key, required this.score});

  Color get color {
    if (score <= 1) return AppColors.red;
    if (score <= 3) return AppColors.orange;
    return AppColors.green;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 6,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.stroke,
        borderRadius: BorderRadius.circular(10),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: score / 4,
        child: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }
}
