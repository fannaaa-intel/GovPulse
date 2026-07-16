import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../../core/services/ticket_repository.dart';
import '../../../../core/theme/app_colors.dart';
import 'online_pulse.dart';

const _kTextPri = Color(0xFF111827);

class ChatAgentInfoBar extends StatefulWidget {
  final double width;

  /// When true, a live staff member is connected — the header shows a person
  /// identity instead of the bot. [staffLabel] is the real staff name once
  /// known, else a department fallback ("Engineering Office staff");
  /// [staffPhotoUrl] shows their photo when available.
  final bool connected;
  final String? staffLabel;
  final String? staffPhotoUrl;

  const ChatAgentInfoBar({
    super.key,
    required this.width,
    this.connected = false,
    this.staffLabel,
    this.staffPhotoUrl,
  });

  /// Fetched once per app session and shared across every chat open, so the
  /// header doesn't re-query on each entry.
  static Future<({double avg, int count})?>? _ratingFuture;

  @override
  State<ChatAgentInfoBar> createState() => _ChatAgentInfoBarState();
}

class _ChatAgentInfoBarState extends State<ChatAgentInfoBar> {
  ({double avg, int count})? _rating;

  @override
  void initState() {
    super.initState();
    ChatAgentInfoBar._ratingFuture ??= TicketRepository.I.fetchAgentRating();
    ChatAgentInfoBar._ratingFuture!.then((r) {
      if (mounted) setState(() => _rating = r);
    });
  }

  Widget _personIcon(double width) => Center(
        child: Icon(Icons.person_rounded,
            size: width * 0.062, color: AppColors.primaryBlue),
      );

  @override
  Widget build(BuildContext context) {
    final width = widget.width;
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
            // ── Avatar — headphone bot, or a person once a staffer connects ──
            Container(
              width: width * 0.112,
              height: width * 0.112,
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              clipBehavior: Clip.antiAlias,
              child: !widget.connected
                  ? Center(
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
                    )
                  : (widget.staffPhotoUrl?.isNotEmpty ?? false)
                      ? CachedNetworkImage(
                          imageUrl: widget.staffPhotoUrl!,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) => _personIcon(width),
                        )
                      : _personIcon(width),
            ),
            SizedBox(width: width * 0.028),

            // ── Name + online status ─────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.connected
                        ? (widget.staffLabel?.trim().isNotEmpty ?? false
                            ? widget.staffLabel!.trim()
                            : 'LGU Staff')
                        : 'LGU Aparri Agent',
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
                          widget.connected
                              ? '· Connected to a person'
                              : '· Replies within minutes',
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
                    // Real average once loaded; "New" when nobody's rated yet.
                    (_rating == null || _rating!.count == 0)
                        ? 'New'
                        : '${_rating!.avg.toStringAsFixed(1)} ★',
                    style: TextStyle(
                      fontSize: width * 0.028,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryBlue,
                    ),
                  ),
                  Text(
                    (_rating != null && _rating!.count > 0)
                        ? '${_rating!.count} RATING${_rating!.count == 1 ? '' : 'S'}'
                        : 'RATING',
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
