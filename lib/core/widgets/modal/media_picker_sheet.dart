import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../app_dialog.dart';

/// Below this the picker is a bottom sheet (phone); at or above it the picker is
/// a centered dialog, like every other pop-up on web/desktop.
const double _kSheetBreakpoint = 600;

/// Ask the user where to attach media from.
///
/// Returns one of: `'gallery'`, `'video'`, `'camera'`, or `null` if dismissed.
/// Set [allowVideo] to false for flows that only accept photos.
///
/// Presentation follows the viewport, not the platform: a bottom sheet under
/// [_kSheetBreakpoint] (phones, narrow browser windows), a centered dialog above
/// it so it matches the other web pop-ups instead of a full-width sheet glued to
/// the bottom of a desktop window.
///
/// On web there is no camera option — capture there goes through the browser's
/// file picker anyway, and the GPS-stamped capture path is mobile-only. When
/// that leaves gallery as the only choice, this resolves to `'gallery'` without
/// showing a pop-up at all.
Future<String?> showMediaPickerSheet(
  BuildContext context, {
  bool allowVideo = true,
}) {
  final allowCamera = !kIsWeb;
  if (!allowCamera && !allowVideo) {
    return Future.value('gallery');
  }

  final isWide = MediaQuery.sizeOf(context).width >= _kSheetBreakpoint;

  if (isWide) {
    return showAppDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        constraints: const BoxConstraints(maxWidth: 400, minWidth: 280),
        child: _MediaPickerBody(
          allowVideo: allowVideo,
          allowCamera: allowCamera,
          asSheet: false,
        ),
      ),
    );
  }

  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 480),
    builder: (ctx) => _MediaPickerBody(
      allowVideo: allowVideo,
      allowCamera: allowCamera,
      asSheet: true,
    ),
  );
}

class _MediaPickerBody extends StatelessWidget {
  const _MediaPickerBody({
    required this.allowVideo,
    required this.allowCamera,
    required this.asSheet,
  });

  final bool allowVideo;
  final bool allowCamera;
  final bool asSheet;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Metrics scale off the pop-up's own width, not the screen's, so a
        // 400px dialog in a 1600px window is typeset like a phone sheet rather
        // than blown up. Clamped so a very narrow window still reads.
        final w = math.max(math.min(constraints.maxWidth, 460), 280).toDouble();

        final body = Padding(
          padding: EdgeInsets.fromLTRB(
            w * 0.05,
            asSheet ? w * 0.03 : w * 0.055,
            w * 0.05,
            w * 0.05,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (asSheet) ...[
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
              ],
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
                allowVideo
                    ? 'Choose where to add your photo or video.'
                    : 'Choose where to add your photo.',
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
              if (allowCamera) ...[
                SizedBox(height: w * 0.03),
                _PickerOption(
                  w: w,
                  icon: Icons.photo_camera_rounded,
                  gradient: const [Color(0xFF22C55E), Color(0xFF16A34A)],
                  title: 'Take a Photo',
                  subtitle: 'Use your camera',
                  onTap: () => Navigator.pop(context, 'camera'),
                ),
              ],
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
        );

        // The dialog gets its shape and background from the Dialog itself; only
        // the sheet has to paint its own rounded top and dodge the home bar.
        if (!asSheet) return body;

        return Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(top: false, child: body),
        );
      },
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
