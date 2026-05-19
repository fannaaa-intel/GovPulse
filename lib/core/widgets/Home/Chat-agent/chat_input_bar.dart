import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

const _kTextPri = Color(0xFF111827);

/// Stable key so the TextField element survives parent rebuilds. Without
/// this, every ChatService.notifyListeners() triggers a full rebuild that
/// recreates the TextField, which drops and re-attaches the IME and makes
/// the keyboard bounce down-then-up after sending a message.
final GlobalKey _chatInputFieldKey = GlobalKey();

class ChatInputBar extends StatelessWidget {
  final double width;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;

  const ChatInputBar({
    super.key,
    required this.width,
    required this.controller,
    required this.focusNode,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.stroke, width: 1)),
      ),
      padding: EdgeInsets.fromLTRB(
        width * 0.04,
        width * 0.020,
        width * 0.04,
        width * 0.028,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.inputBg,
                borderRadius: BorderRadius.circular(width * 0.055),
                border: Border.all(color: AppColors.stroke, width: 1),
              ),
              child: TextField(
                key: _chatInputFieldKey, // ← the fix
                controller: controller,
                focusNode: focusNode,
                maxLines: 4,
                minLines: 1,
                textInputAction: TextInputAction.newline,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const [],
                style: TextStyle(
                  fontSize: width * 0.034,
                  color: _kTextPri,
                  height: 1.5,
                ),
                decoration: InputDecoration(
                  hintText: 'Type a message…',
                  hintStyle: TextStyle(
                    fontSize: width * 0.034,
                    color: AppColors.hint,
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: width * 0.040,
                    vertical: width * 0.024,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: width * 0.022),
          GestureDetector(
            onTap: onSend,
            child: Container(
              width: width * 0.108,
              height: width * 0.108,
              decoration: const BoxDecoration(
                color: AppColors.primaryBlue,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Image.asset(
                  'assets/images/send.png',
                  width: width * 0.046,
                  height: width * 0.046,
                  fit: BoxFit.contain,
                  color: Colors.white,
                  colorBlendMode: BlendMode.srcIn,
                  errorBuilder: (_, _, _) => Icon(
                    Icons.send_rounded,
                    size: width * 0.046,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
