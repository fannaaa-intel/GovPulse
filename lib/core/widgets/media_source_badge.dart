import 'package:flutter/material.dart';

/// A tiny corner tag that tells an admin / staff reviewer where an attached
/// photo or video came from:
///
///   verified = true  → live camera capture with a baked-in GPS stamp
///   verified = false → uploaded from gallery, or a video (location unverified)
///
/// Keeps the story honest and consistent: every attachment is labelled, so the
/// absence of a GPS stamp is never mistaken for missing data.
class MediaSourceBadge extends StatelessWidget {
  final bool verified;

  /// Shrinks the badge to just its icon (for very small thumbnails).
  final bool compact;

  const MediaSourceBadge({
    super.key,
    required this.verified,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg = verified
        ? const Color(0xFF16A34A) // green
        : const Color(0xFF4B5563); // slate gray
    final IconData icon =
        verified ? Icons.location_on_rounded : Icons.file_upload_rounded;
    final String label = verified ? 'GPS' : 'Uploaded';

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 4 : 6,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: Colors.white),
          if (!compact) ...[
            const SizedBox(width: 3),
            Text(
              label,
              style: const TextStyle(
                fontSize: 9.5,
                height: 1.0,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
