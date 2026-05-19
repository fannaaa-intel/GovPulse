import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import 'online_pulse.dart';

const _kTextPri = Color(0xFF111827);

class ChatAgentInfoBar extends StatelessWidget {
  final double width;
  const ChatAgentInfoBar({super.key, required this.width});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(
        width * 0.04,
        width * 0.022,
        width * 0.04,
        width * 0.026,
      ),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: width * 0.036,
          vertical: width * 0.026,
        ),
        decoration: BoxDecoration(
          color: AppColors.inputBg,
          borderRadius: BorderRadius.circular(width * 0.032),
          border: Border.all(color: AppColors.stroke, width: 1),
        ),
        child: Row(
          children: [
            // ── Avatar ──────────────────────────────────────────────────────
            Container(
              width: width * 0.112,
              height: width * 0.112,
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Image.asset(
                  'assets/images/customer.png',
                  width: width * 0.058,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => Icon(
                    Icons.support_agent_rounded,
                    size: width * 0.058,
                    color: AppColors.primaryBlue,
                  ),
                ),
              ),
            ),
            SizedBox(width: width * 0.028),

            // ── Name + online status ─────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'LGU Aparri Agent',
                    style: TextStyle(
                      fontSize: width * 0.036,
                      fontWeight: FontWeight.w600,
                      color: _kTextPri,
                      letterSpacing: -0.2,
                    ),
                  ),
                  SizedBox(height: width * 0.006),
                  Row(
                    children: [
                      OnlinePulse(size: width * 0.016),
                      SizedBox(width: width * 0.010),
                      Text(
                        'Online',
                        style: TextStyle(
                          fontSize: width * 0.027,
                          color: AppColors.green,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(width: width * 0.008),
                      Expanded(
                        child: Text(
                          '· Replies within minutes',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: width * 0.026,
                            color: AppColors.hint,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(width: width * 0.02),

            // ── Rating badge ─────────────────────────────────────────────────
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: width * 0.022,
                vertical: width * 0.012,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(width * 0.020),
                border: Border.all(color: AppColors.stroke, width: 1),
              ),
              child: Column(
                children: [
                  Text(
                    '4.9 ★',
                    style: TextStyle(
                      fontSize: width * 0.028,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryBlue,
                    ),
                  ),
                  Text(
                    'RATING',
                    style: TextStyle(
                      fontSize: width * 0.019,
                      color: AppColors.hint,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
