import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// Secondary outlined button used on web (guest / phone / etc).
/// Transparent at rest; border + icon + label turn blue on hover. No fill.
class WebOutlinedButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const WebOutlinedButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        style: ButtonStyle(
          // No fill, ever.
          backgroundColor: WidgetStateProperty.all(Colors.transparent),
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          // Border → blue on hover/press.
          side: WidgetStateProperty.resolveWith((states) {
            final active =
                states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.pressed);
            return BorderSide(
              color: active
                  ? AppColors.primaryBlue
                  : const Color(0xFFCBD2DE), // visible gray at rest
              width: active ? 1.4 : 1.2,
            );
          }),
          // Icon + text → blue on hover/press.
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            final active =
                states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.pressed);
            return active ? AppColors.primaryBlue : const Color(0xFF374151);
          }),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          elevation: WidgetStateProperty.all(0),
        ),
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}
