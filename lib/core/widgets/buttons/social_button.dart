import 'package:flutter/material.dart';

class SocialButton extends StatelessWidget {
  final String? iconPath;
  final IconData? icon;
  final bool isIconData;
  final String label;
  final VoidCallback onTap;

  const SocialButton({
    super.key,
    this.iconPath,
    this.icon,
    this.isIconData = false,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 70,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE3E6EF)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            isIconData
                ? Icon(icon, color: const Color(0xFF0D47A1), size: 22)
                : Image.asset(iconPath!, height: 26),

            const SizedBox(height: 4),

            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
