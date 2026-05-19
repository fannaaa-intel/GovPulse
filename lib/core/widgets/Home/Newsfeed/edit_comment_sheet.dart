import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import 'news_feed_helpers.dart';

class EditCommentSheet extends StatefulWidget {
  final String initialText;
  final double width;

  const EditCommentSheet({
    super.key,
    required this.initialText,
    required this.width,
  });

  @override
  State<EditCommentSheet> createState() => _EditCommentSheetState();
}

class _EditCommentSheetState extends State<EditCommentSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.width;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(w * 0.05, w * 0.03, w * 0.05, w * 0.04),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: dragHandle(w)),
              Row(
                children: [
                  Container(
                    width: w * 0.11,
                    height: w * 0.11,
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.edit_rounded,
                      size: w * 0.052,
                      color: AppColors.primaryBlue,
                    ),
                  ),
                  SizedBox(width: w * 0.03),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Edit Comment',
                        style: TextStyle(
                          fontSize: w * 0.045,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF1F2937),
                        ),
                      ),
                      Text(
                        'Make changes to your comment',
                        style: TextStyle(
                          fontSize: w * 0.030,
                          color: const Color(0xFF9CA3AF),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              SizedBox(height: w * 0.035),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: w * 0.04,
                  vertical: w * 0.03,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(w * 0.04),
                  border: Border.all(
                    color: AppColors.primaryBlue.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                ),
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  maxLines: null,
                  minLines: 3,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isCollapsed: true,
                    hintText: 'Edit your comment...',
                    hintStyle: TextStyle(
                      color: const Color(0xFF9CA3AF),
                      fontSize: w * 0.035,
                    ),
                  ),
                  style: TextStyle(
                    fontSize: w * 0.035,
                    color: const Color(0xFF1F2937),
                    height: 1.4,
                  ),
                ),
              ),
              SizedBox(height: w * 0.04),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: EdgeInsets.symmetric(vertical: w * 0.038),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(w * 0.035),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            fontSize: w * 0.038,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF374151),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: w * 0.03),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context, _controller.text),
                      child: Container(
                        padding: EdgeInsets.symmetric(vertical: w * 0.038),
                        decoration: BoxDecoration(
                          color: AppColors.primaryBlue,
                          borderRadius: BorderRadius.circular(w * 0.035),
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: w * 0.042,
                            ),
                            SizedBox(width: w * 0.015),
                            Text(
                              'Save',
                              style: TextStyle(
                                fontSize: w * 0.038,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
