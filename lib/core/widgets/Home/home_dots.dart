import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class HomeDots extends StatelessWidget {
  final double width;
  final int count;
  final int activeIndex;

  const HomeDots({
    super.key,
    required this.width,
    required this.count,
    required this.activeIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final isActive = i == activeIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: EdgeInsets.symmetric(horizontal: width * 0.007),
          width: isActive ? width * 0.050 : width * 0.020,
          height: width * 0.020,
          decoration: BoxDecoration(
            color: isActive ? AppColors.primaryBlue : const Color(0xFFD1D5DB),
            borderRadius: BorderRadius.circular(width * 0.010),
          ),
        );
      }),
    );
  }
}
