import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import 'online_pulse.dart';
import '../../../../core/theme/citizen_ui.dart';

const _kTextPri = Color(0xFF111827);

/// Who the citizen is talking to: always Kuya Gov, the automated assistant.
///
/// Until the 2026-10-12 panel revision this swapped to a connected staff
/// member's name and photo and carried a staff star-rating badge. There is no
/// live staff chat any more, so the bar says plainly that this is an assistant
/// for common questions — a citizen should never think a person is reading.
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
          border: Border.all(color: CitizenUi.sharedStroke, width: 1),
        ),
        child: Row(
          children: [
            // ── Avatar ───────────────────────────────────────────────────────
            Container(
              width: width * 0.112,
              height: width * 0.112,
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Image.asset(
                  'assets/images/customer.webp',
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

            // ── Name + status ────────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Kuya Gov',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
                          '· Automated assistant for common questions',
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
          ],
        ),
      ),
    );
  }
}
