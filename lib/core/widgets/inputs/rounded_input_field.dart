import 'package:flutter/material.dart';

class RoundedInputField extends StatelessWidget {
  final String value;
  final String hintText;
  final IconData icon;
  final bool obscureText;
  final Function(String) onChanged;
  final Widget? suffixWidget;
  final TextEditingController? controller;
  final bool enabled;
  final FocusNode? focusNode;

  final Widget? prefix;

  final bool isError;

  const RoundedInputField({
    super.key,
    required this.value,
    required this.hintText,
    required this.icon,
    required this.onChanged,
    this.obscureText = false,
    this.suffixWidget,
    this.controller,
    this.enabled = true,
    this.focusNode,
    this.prefix,
    this.isError = false,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isError ? Colors.red : const Color(0xFFE3E6EF);

    final focusColor = isError ? Colors.red : const Color(0xFF0D47A1);

    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      obscureText: obscureText,
      onChanged: onChanged,
      cursorColor: focusColor,

      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0xFFF6F7FB),

        hintText: hintText,
        hintStyle: const TextStyle(color: Colors.grey, fontSize: 15),

        prefixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 12),
            Icon(icon, color: focusColor),
            if (prefix != null) ...[const SizedBox(width: 6), prefix!],
            const SizedBox(width: 6),
          ],
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0),

        suffixIcon: suffixWidget,

        contentPadding: const EdgeInsets.symmetric(
          vertical: 16,
          horizontal: 10,
        ),

        // ✅ NORMAL BORDER
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: borderColor),
        ),

        // ✅ ENABLED
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: borderColor, width: 1),
        ),

        // ✅ FOCUSED
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: focusColor, width: 2),
        ),

        // 🔥 ADDED (IMPORTANT)
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.red, width: 1),
        ),

        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.red, width: 2),
        ),
      ),
    );
  }
}
