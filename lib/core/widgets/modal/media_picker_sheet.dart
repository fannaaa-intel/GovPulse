import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A polished bottom sheet for choosing how to attach media.
///
/// Returns one of: `'gallery'`, `'video'`, `'camera'`, or `null` if dismissed.
/// Set [allowVideo] to false for flows that only accept photos.
Future<String?> showMediaPickerSheet(
  BuildContext context, {
  bool allowVideo = true,
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    // On wide screens (tablet / web) this keeps the sheet a sensible width and
    // centered, instead of stretching across the whole window.
    constraints: const BoxConstraints(maxWidth: 480),
    builder: (ctx) => _MediaPickerSheet(allowVideo: allowVideo),
  );
}

class _MediaPickerSheet extends StatelessWidget {
  const _MediaPickerSheet({required this.allowVideo});

  final bool allowVideo;

  @override
  Widget build(BuildContext context) {
    // Size relative to the sheet's own width, capped so fonts and padding stay
    // phone-sized on tablet/web (where the raw screen width would be huge).
    final w = math.min(MediaQuery.of(context).size.width, 460).toDouble();

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(w * 0.05, w * 0.03, w * 0.05, w * 0.05),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Grab handle
              Center(
                child: Container(
                  width: w * 0.11,
                  height: w * 0.012,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1D5DB),
                    borderRadius: BorderRadius.circular(w * 0.01),
                  ),
                ),
              ),
              SizedBox(height: w * 0.05),
              Text(
                'Add attachment',
                style: TextStyle(
                  fontSize: w * 0.048,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF111827),
                  letterSpacing: -0.3,
                ),
              ),
              SizedBox(height: w * 0.012),
              Text(
                'Choose where to add your photo or video.',
                style: TextStyle(
                  fontSize: w * 0.034,
                  color: const Color(0xFF6B7280),
                  height: 1.4,
                ),
              ),
              SizedBox(height: w * 0.05),
              _PickerOption(
                w: w,
                icon: Icons.photo_library_rounded,
                gradient: const [Color(0xFF3B82F6), Color(0xFF2563EB)],
                title: 'Photo from Gallery',
                subtitle: 'Pick existing photos',
                onTap: () => Navigator.pop(context, 'gallery'),
              ),
              if (allowVideo) ...[
                SizedBox(height: w * 0.03),
                _PickerOption(
                  w: w,
                  icon: Icons.videocam_rounded,
                  gradient: const [Color(0xFFA855F7), Color(0xFF7C3AED)],
                  title: 'Video from Gallery',
                  subtitle: 'Pick a video clip',
                  onTap: () => Navigator.pop(context, 'video'),
                ),
              ],
              SizedBox(height: w * 0.03),
              _PickerOption(
                w: w,
                icon: Icons.photo_camera_rounded,
                gradient: const [Color(0xFF22C55E), Color(0xFF16A34A)],
                title: 'Take a Photo',
                subtitle: 'Use your camera',
                onTap: () => Navigator.pop(context, 'camera'),
              ),
              SizedBox(height: w * 0.04),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: w * 0.035),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(w * 0.04),
                    ),
                    backgroundColor: const Color(0xFFF3F4F6),
                  ),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      fontSize: w * 0.04,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF374151),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickerOption extends StatelessWidget {
  const _PickerOption({
    required this.w,
    required this.icon,
    required this.gradient,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final double w;
  final IconData icon;
  final List<Color> gradient;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF9FAFB),
      borderRadius: BorderRadius.circular(w * 0.045),
      child: InkWell(
        borderRadius: BorderRadius.circular(w * 0.045),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(w * 0.035),
          child: Row(
            children: [
              Container(
                width: w * 0.12,
                height: w * 0.12,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: gradient,
                  ),
                  borderRadius: BorderRadius.circular(w * 0.036),
                  boxShadow: [
                    BoxShadow(
                      color: gradient.last.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                      spreadRadius: -3,
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: w * 0.062),
              ),
              SizedBox(width: w * 0.04),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: w * 0.04,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF111827),
                      ),
                    ),
                    SizedBox(height: w * 0.005),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: w * 0.032,
                        color: const Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: const Color(0xFF9CA3AF),
                size: w * 0.06,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
