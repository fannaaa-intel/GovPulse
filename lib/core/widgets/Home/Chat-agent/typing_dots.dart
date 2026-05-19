import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class TypingDots extends StatefulWidget {
  final double width;
  const TypingDots({super.key, required this.width});

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.width;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final delay = i * 0.28;
            final raw = (_ctrl.value - delay) % 1.0;
            final t = raw < 0 ? raw + 1.0 : raw;
            final opacity = 0.25 + 0.75 * (t < 0.5 ? t * 2 : (1.0 - t) * 2);
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: w * 0.008),
              child: Opacity(
                opacity: opacity,
                child: Container(
                  width: w * 0.020,
                  height: w * 0.020,
                  decoration: const BoxDecoration(
                    color: AppColors.primaryBlue,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
