import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// Small inline error label shown beneath web input fields.
class WebFieldError extends StatelessWidget {
  final String? text;
  const WebFieldError({super.key, this.text});

  @override
  Widget build(BuildContext context) {
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 7, left: 4),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 14, color: AppColors.red),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text!,
              style: TextStyle(color: AppColors.red, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
