import 'package:flutter/material.dart';

/// A tiny corner tag that flags how likely an attached photo was AI-generated,
/// for admin reviewers. Purely INFORMATIONAL — it never hides, blocks, or
/// auto-rejects a submission; it only surfaces the score so a human can judge.
///
/// Thresholds (score is 0..1, the AI-likelihood from the check-ai-image Edge
/// Function):
///   • status != 'completed', score == null, or score < 0.3 → no badge
///   • 0.3 – 0.7  → amber  "Possibly AI (X%)"
///   • > 0.7      → red    "Likely AI (X%)"
///
/// Mirrors [MediaSourceBadge] in size/shape so the two corner tags read as a
/// matched pair (MediaSourceBadge sits top-left, this sits top-right).
class AiDetectionBadge extends StatelessWidget {
  /// AI-likelihood 0..1, or null when not yet scored.
  final double? score;

  /// Lifecycle status: 'pending' | 'completed' | 'failed' | null (legacy).
  final String? status;

  /// Shrinks the badge to just its icon (for very small thumbnails / narrow
  /// screens) — same responsive affordance as [MediaSourceBadge].
  final bool compact;

  const AiDetectionBadge({
    super.key,
    required this.score,
    this.status,
    this.compact = false,
  });

  /// Whether a badge should render at all for the given score/status. Callers
  /// can use this to avoid laying out an empty [Positioned].
  static bool shouldShow(double? score, String? status) {
    if (status != null && status != 'completed') return false;
    return score != null && score >= 0.3;
  }

  @override
  Widget build(BuildContext context) {
    final s = score;
    if (!shouldShow(s, status)) return const SizedBox.shrink();

    final bool likely = s! > 0.7;
    final Color bg = likely
        ? const Color(0xFFDC2626) // red
        : const Color(0xFFD97706); // amber
    final String emoji = likely ? '🚩' : '⚠';
    final String word = likely ? 'Likely AI' : 'Possibly AI';
    final int pct = (s * 100).round();
    final String label = '$emoji $word ($pct%)';

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 4 : 6,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(6),
      ),
      child: compact
          // Compact: just the emoji marker, keeps small thumbnails uncluttered.
          ? Text(
              emoji,
              style: const TextStyle(fontSize: 10, height: 1.0),
            )
          : Text(
              label,
              style: const TextStyle(
                fontSize: 9.5,
                height: 1.0,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 0.2,
              ),
            ),
    );
  }
}
