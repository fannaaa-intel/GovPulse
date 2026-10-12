// Preview target for the AI-likelihood badge + meter (2026-10-12).
//
//   flutter build web --release -t tool/preview_ai_meter.dart
//
// No Supabase: the thumbnails mirror the real tile Stack (source tag top-left,
// AI pill bottom-left, zoom bottom-right) over a flat colour, and the last
// panel mounts the REAL FullscreenImageDialog with a dead image URL so only the
// meter's placement is under test.
import 'package:flutter/material.dart';
import 'package:govpulse/core/widgets/ai_detection_badge.dart';
import 'package:govpulse/core/widgets/media_source_badge.dart';
import 'package:govpulse/features/admin/widgets/report_detail_kit.dart'
    show FullscreenImageDialog;

void main() => runApp(const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _Preview(),
    ));

const _scores = [0.06, 0.29, 0.30, 0.48, 0.70, 0.71, 0.86, 1.0];

class _Preview extends StatelessWidget {
  const _Preview();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Thumbnails (92px, real tile layout)',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final s in _scores) _Thumb(score: s, gps: s < 0.5),
                const _Thumb(score: 0.9, status: 'pending', gps: false),
                const _Thumb(score: null, gps: true),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
                'last two: pending + unscored → no pill (expected)',
                style: TextStyle(fontSize: 11, color: Colors.black54)),
            const SizedBox(height: 18),
            const Text('Meter',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Container(
              color: Colors.black87,
              padding: const EdgeInsets.all(12),
              child: const Column(
                children: [
                  AiLikelihoodMeter(score: 0.06),
                  SizedBox(height: 10),
                  AiLikelihoodMeter(score: 0.48),
                  SizedBox(height: 10),
                  AiLikelihoodMeter(score: 0.86),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const Text('Real FullscreenImageDialog @ 360×640',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const SizedBox(
              width: 360,
              height: 640,
              child: ColoredBox(
                color: Colors.black87,
                child: FullscreenImageDialog(
                  url: 'http://127.0.0.1:1/none.jpg',
                  aiScore: 0.82,
                  aiStatus: 'completed',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final double? score;
  final String? status;
  final bool gps;
  const _Thumb({required this.score, this.status = 'completed', required this.gps});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 92,
        height: 92,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0xFF8BA3B8)),
            Positioned(top: 5, left: 5, child: MediaSourceBadge(verified: gps)),
            Positioned(
              left: 5,
              bottom: 5,
              child: AiDetectionBadge(score: score, status: status, compact: true),
            ),
            Positioned(
              right: 5,
              bottom: 5,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.zoom_in_rounded,
                    size: 13, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
