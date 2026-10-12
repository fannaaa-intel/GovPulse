import 'package:flutter/material.dart';

/// How likely an attached photo is to be AI-generated, as the check-ai-image
/// Edge Function scored it (Sightengine, 0..1). For admin and staff reviewers.
///
/// Purely INFORMATIONAL — it never hides, blocks, or auto-rejects a submission;
/// it surfaces the number so a human can judge.
///
/// Until 2026-10-12 this was a bare 🚩 on every thumbnail and stayed hidden
/// below 30%, so a reviewer saw either a flag or nothing — never the score, and
/// never whether a photo had been checked at all. It now shows the percentage
/// for EVERY scored photo, with a fill bar, in three bands:
///
///   • < 30%      green  "Likely real"
///   • 30 – 70%   amber  "Possibly AI"
///   • > 70%      red    "Likely AI"
///
/// Unscored photos (pending, failed, videos, older rows) still render nothing:
/// a "checking…" that never finishes would be a claim the app cannot keep,
/// because the check is fired client-side after upload and may never run.
enum AiBand { real, possible, likely }

/// The band for [score] (0..1). Thresholds are shared by every AI surface so
/// the thumbnail pill and the full-screen meter can never disagree.
AiBand aiBandFor(double score) {
  if (score > 0.7) return AiBand.likely;
  if (score >= 0.3) return AiBand.possible;
  return AiBand.real;
}

Color aiBandColor(AiBand band) => switch (band) {
      AiBand.likely => const Color(0xFFDC2626), // red
      AiBand.possible => const Color(0xFFD97706), // amber
      AiBand.real => const Color(0xFF16A34A), // green
    };

String aiBandLabel(AiBand band) => switch (band) {
      AiBand.likely => 'Likely AI',
      AiBand.possible => 'Possibly AI',
      AiBand.real => 'Likely real',
    };

/// The small corner tag on a thumbnail: "AI 82%" over a fill bar.
class AiDetectionBadge extends StatelessWidget {
  /// AI-likelihood 0..1, or null when not yet scored.
  final double? score;

  /// Lifecycle status: 'pending' | 'completed' | 'failed' | null (legacy).
  final String? status;

  /// The narrow form for small thumbnails: just "AI 82%" and the bar, no band
  /// word. Same responsive affordance as [MediaSourceBadge].
  final bool compact;

  const AiDetectionBadge({
    super.key,
    required this.score,
    this.status,
    this.compact = false,
  });

  /// Whether anything should render for the given score/status. Callers use
  /// this to avoid laying out an empty [Positioned] or meter.
  static bool shouldShow(double? score, String? status) {
    if (status != null && status != 'completed') return false;
    return score != null && score >= 0 && score <= 1;
  }

  @override
  Widget build(BuildContext context) {
    final s = score;
    if (!shouldShow(s, status)) return const SizedBox.shrink();

    final band = aiBandFor(s!);
    final color = aiBandColor(band);
    final pct = (s * 100).round();
    final label = compact ? 'AI $pct%' : '${aiBandLabel(band)} · $pct%';

    return Semantics(
      label: 'AI-generated likelihood $pct percent, ${aiBandLabel(band)}',
      child: Container(
        padding: const EdgeInsets.fromLTRB(5, 3, 5, 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.9), width: 1),
        ),
        child: IntrinsicWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 9.5,
                  height: 1.0,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 3),
              _FillBar(value: s, color: color, height: 3),
            ],
          ),
        ),
      ),
    );
  }
}

/// The full meter for the photo viewer: the number, the band, and a track with
/// the 30% / 70% thresholds marked, so a reviewer can see how close a photo
/// sits to the next band rather than reading a verdict with no context.
class AiLikelihoodMeter extends StatelessWidget {
  final double? score;
  final String? status;

  const AiLikelihoodMeter({super.key, required this.score, this.status});

  @override
  Widget build(BuildContext context) {
    final s = score;
    if (!AiDetectionBadge.shouldShow(s, status)) return const SizedBox.shrink();

    final band = aiBandFor(s!);
    final color = aiBandColor(band);
    final pct = (s * 100).round();

    return Semantics(
      label: 'AI-generated likelihood $pct percent, ${aiBandLabel(band)}',
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Expanded(
                    child: Text(
                      'AI-generated likelihood',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$pct%',
                    style: TextStyle(
                      fontSize: 22,
                      height: 1.0,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _ThresholdTrack(value: s, color: color),
              const SizedBox(height: 4),
              const Row(
                children: [
                  Expanded(flex: 30, child: _TrackLabel('Real')),
                  Expanded(flex: 40, child: _TrackLabel('Possibly AI')),
                  Expanded(flex: 30, child: _TrackLabel('Likely AI')),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: color.withValues(alpha: 0.7)),
                    ),
                    child: Text(
                      aiBandLabel(band),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'An automated estimate. It never blocks a submission — '
                      'you decide.',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.35,
                        color: Colors.white60,
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

class _TrackLabel extends StatelessWidget {
  final String text;
  const _TrackLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 10, color: Colors.white54),
      );
}

/// A rounded bar filled to [value] (0..1).
class _FillBar extends StatelessWidget {
  final double value;
  final Color color;
  final double height;
  const _FillBar({
    required this.value,
    required this.color,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: Colors.white.withValues(alpha: 0.25)),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value.clamp(0.0, 1.0),
              child: ColoredBox(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// The meter's track: the three bands tinted underneath, the score filled in
/// its band colour on top, and ticks at the 30% and 70% thresholds.
class _ThresholdTrack extends StatelessWidget {
  final double value;
  final Color color;
  const _ThresholdTrack({required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    const h = 10.0;
    return SizedBox(
      height: h,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(h),
            // stretch, or each empty ColoredBox takes the Row's minimum height
            // — zero — and the bands silently never paint.
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (flex, band) in const [
                  (30, AiBand.real),
                  (40, AiBand.possible),
                  (30, AiBand.likely),
                ])
                  Expanded(
                    flex: flex,
                    child: ColoredBox(
                      color: aiBandColor(band).withValues(alpha: 0.3),
                    ),
                  ),
              ],
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(h),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value.clamp(0.0, 1.0),
              child: ColoredBox(color: color),
            ),
          ),
          for (final at in const [0.3, 0.7])
            Align(
              alignment: Alignment(at * 2 - 1, 0),
              child: Container(
                width: 2,
                height: h,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
        ],
      ),
    );
  }
}
