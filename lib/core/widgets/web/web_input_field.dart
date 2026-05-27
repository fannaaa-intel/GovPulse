// lib/core/widgets/web/web_input_field.dart
//
// Premium web text field with animated focus + error states.
// Reusable on any web screen (auth, search bars, forms, etc).
//
// FIX: `keyboardType` used to be a required constructor arg that was never
// stored or passed to the TextField — so phone/email/number fields fell back to
// the default text keyboard on mobile web. It's now a real, optional field
// (defaults to TextInputType.text) and is wired into the TextField below.

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// Pass a [controller]/[focusNode] if you need to read or drive it; otherwise
/// it manages its own focus node internally. Optional [prefix] sits between the
/// leading icon and the text (e.g. a "+63" country code).
class WebInputField extends StatefulWidget {
  final String hint;
  final IconData icon;
  final bool obscure;
  final bool enabled;
  final bool isError;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<String> onChanged;
  final Widget? prefix;
  final Widget? suffix;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final TextInputType keyboardType;

  const WebInputField({
    super.key,
    required this.hint,
    required this.icon,
    required this.onChanged,
    this.obscure = false,
    this.enabled = true,
    this.isError = false,
    this.controller,
    this.focusNode,
    this.prefix,
    this.suffix,
    this.textInputAction,
    this.onSubmitted,
    this.keyboardType = TextInputType.text,
  });

  @override
  State<WebInputField> createState() => _WebInputFieldState();
}

class _WebInputFieldState extends State<WebInputField> {
  late final FocusNode _node;
  bool _ownsNode = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode != null) {
      _node = widget.focusNode!;
    } else {
      _node = FocusNode();
      _ownsNode = true;
    }
    _node.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (mounted) setState(() => _focused = _node.hasFocus);
  }

  @override
  void dispose() {
    _node.removeListener(_onFocusChange);
    if (_ownsNode) _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasError = widget.isError;
    final Color borderColor = hasError
        ? AppColors.red
        : (_focused ? AppColors.primaryBlue : AppColors.stroke);
    final Color iconColor = hasError
        ? AppColors.red
        : (_focused ? AppColors.primaryBlue : AppColors.hint);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      height: 52,
      decoration: BoxDecoration(
        color: widget.enabled
            ? (_focused ? Colors.white : AppColors.inputBg)
            : AppColors.inputBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: borderColor,
          width: (_focused || hasError) ? 1.4 : 1,
        ),
        boxShadow: (_focused || hasError)
            ? [
                BoxShadow(
                  color: (hasError ? AppColors.red : AppColors.primaryBlue)
                      .withValues(alpha: 0.10),
                  blurRadius: 0,
                  spreadRadius: 3,
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          Icon(widget.icon, size: 18, color: iconColor),
          const SizedBox(width: 12),
          if (widget.prefix != null) widget.prefix!,
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _node,
              enabled: widget.enabled,
              obscureText: widget.obscure,
              keyboardType: widget.keyboardType, // ← now actually applied
              onChanged: widget.onChanged,
              textInputAction: widget.textInputAction,
              onSubmitted: widget.onSubmitted,
              cursorColor: AppColors.primaryBlue,
              style: const TextStyle(fontSize: 14.5, color: Color(0xFF111827)),
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: TextStyle(color: AppColors.hint, fontSize: 14.5),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (widget.suffix != null) ...[
            widget.suffix!,
            const SizedBox(width: 16),
          ],
        ],
      ),
    );
  }
}
