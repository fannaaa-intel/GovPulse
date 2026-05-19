import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import 'news_feed_helpers.dart';

void showCommentOptions(
  BuildContext context,
  double width,
  Map<String, dynamic> entry, {
  ValueChanged<Map<String, dynamic>>? onEdit,
  ValueChanged<Map<String, dynamic>>? onDelete,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(width * 0.06)),
    ),
    builder: (ctx) => SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(0, width * 0.025, 0, width * 0.03),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            dragHandle(width),
            if (onEdit != null)
              InkWell(
                onTap: () {
                  Navigator.pop(ctx);
                  onEdit(entry);
                },
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: width * 0.05,
                    vertical: width * 0.038,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: width * 0.11,
                        height: width * 0.11,
                        decoration: BoxDecoration(
                          color: AppColors.primaryBlue.withValues(alpha: 0.10),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.edit_rounded,
                          size: width * 0.052,
                          color: AppColors.primaryBlue,
                        ),
                      ),
                      SizedBox(width: width * 0.04),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Edit',
                            style: TextStyle(
                              fontSize: width * 0.04,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF1F2937),
                            ),
                          ),
                          SizedBox(height: width * 0.005),
                          Text(
                            'Change what you wrote',
                            style: TextStyle(
                              fontSize: width * 0.030,
                              color: const Color(0xFF9CA3AF),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (onEdit != null && onDelete != null)
              Container(
                height: 1,
                margin: EdgeInsets.symmetric(horizontal: width * 0.05),
                color: const Color(0xFFE5E7EB),
              ),
            if (onDelete != null)
              InkWell(
                onTap: () {
                  Navigator.pop(ctx);
                  onDelete(entry);
                },
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: width * 0.05,
                    vertical: width * 0.038,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: width * 0.11,
                        height: width * 0.11,
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFEF4444,
                          ).withValues(alpha: 0.10),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.delete_rounded,
                          size: width * 0.052,
                          color: const Color(0xFFEF4444),
                        ),
                      ),
                      SizedBox(width: width * 0.04),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Delete',
                            style: TextStyle(
                              fontSize: width * 0.04,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFFEF4444),
                            ),
                          ),
                          SizedBox(height: width * 0.005),
                          Text(
                            'Remove this comment permanently',
                            style: TextStyle(
                              fontSize: width * 0.030,
                              color: const Color(0xFF9CA3AF),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
