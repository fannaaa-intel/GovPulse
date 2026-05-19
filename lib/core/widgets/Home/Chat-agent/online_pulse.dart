import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class OnlinePulse extends StatefulWidget {
  final double size;
  const OnlinePulse({super.key, required this.size});

  @override
  State<OnlinePulse> createState() => _OnlinePulseState();
}

class _OnlinePulseState extends State<OnlinePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, _) => Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: Color.lerp(
            AppColors.green,
            AppColors.green.withValues(alpha: 0.35),
            _anim.value,
          ),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
