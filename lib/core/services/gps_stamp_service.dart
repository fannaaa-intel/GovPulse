import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:path_provider/path_provider.dart';

/// Bakes a "GPS Map Camera"-style overlay (location, address, coordinates and
/// timestamp) into the bottom of a freshly-captured camera photo.
///
/// Only ever call this for photos taken LIVE with the in-app camera — that is
/// the only moment we truthfully know where and when the shot was taken. Never
/// stamp gallery images (they may be old / from elsewhere) or videos.
///
/// The overlay is drawn into the pixels themselves, so it travels with the
/// image to storage and is visible to admins with zero backend changes.
///
/// This never throws and never blocks the user: on any failure (no GPS, no
/// permission, decode error) it simply returns the original [photo] unstamped —
/// with [GpsStampResult.stamped] set to false so callers can label it honestly.
class GpsStampResult {
  /// The photo to attach — a new stamped file, or the original if unstamped.
  final XFile file;

  /// True only when the GPS overlay was actually baked into a fresh file.
  final bool stamped;

  const GpsStampResult(this.file, this.stamped);
}

class GpsStampService {
  const GpsStampService._();

  static Future<GpsStampResult> stampPhoto(XFile photo) async {
    try {
      final position = await _currentPosition();
      if (position == null) return GpsStampResult(photo, false); // No GPS.

      // Reverse-geocode to a human address line (best-effort — optional).
      String addressLine = '';
      try {
        final marks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        ).timeout(const Duration(seconds: 6));
        if (marks.isNotEmpty) addressLine = _formatPlacemark(marks.first);
      } catch (_) {
        // Geocoding is best-effort; coordinates + time are enough.
      }

      final original = await photo.readAsBytes();
      final stamped = await _drawOverlay(
        bytes: original,
        latitude: position.latitude,
        longitude: position.longitude,
        addressLine: addressLine,
      );
      if (stamped == null) return GpsStampResult(photo, false);

      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/gps_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(path).writeAsBytes(stamped, flush: true);
      return GpsStampResult(XFile(path), true);
    } catch (_) {
      // Stamping must never stop the user from attaching a photo.
      return GpsStampResult(photo, false);
    }
  }

  // ── GPS: quick, with graceful fallbacks (mirrors report screen logic) ───────
  static Future<Position?> _currentPosition() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return null;
    }

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 12));
    } catch (_) {}

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      ).timeout(const Duration(seconds: 8));
    } catch (_) {}

    try {
      return await Geolocator.getLastKnownPosition();
    } catch (_) {
      return null;
    }
  }

  static String _formatPlacemark(Placemark p) {
    final parts = <String>[
      if ((p.street ?? '').trim().isNotEmpty) p.street!.trim(),
      if ((p.subLocality ?? '').trim().isNotEmpty) p.subLocality!.trim(),
      if ((p.locality ?? '').trim().isNotEmpty) p.locality!.trim(),
      if ((p.administrativeArea ?? '').trim().isNotEmpty)
        p.administrativeArea!.trim(),
    ];
    // De-duplicate consecutive identical fragments (common with geocoders).
    final seen = <String>{};
    final unique = parts.where((e) => seen.add(e.toLowerCase())).toList();
    return unique.join(', ');
  }

  // ── GovPulse logo, decoded once and cached for reuse across captures ────────
  static ui.Image? _logo;
  static Future<ui.Image?> _loadLogo() async {
    if (_logo != null) return _logo;
    try {
      final data = await rootBundle.load('assets/images/applogo.png');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      _logo = frame.image;
      return _logo;
    } catch (_) {
      return null; // Logo is decorative — never block stamping on it.
    }
  }

  // ── Overlay rendering ───────────────────────────────────────────────────────
  static Future<Uint8List?> _drawOverlay({
    required Uint8List bytes,
    required double latitude,
    required double longitude,
    required String addressLine,
  }) async {
    // Decode via dart:ui so EXIF orientation is applied upfront — the overlay
    // then always lands at the true visual bottom of the image.
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final ui.Image image = frame.image;
    final w = image.width.toDouble();
    final h = image.height.toDouble();
    if (w <= 0 || h <= 0) return null;

    final logo = await _loadLogo();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(image, Offset.zero, Paint());

    // ── Layout metrics (all relative to image width) ─────────────────────────
    final margin = w * 0.020;
    final pad = w * 0.028;
    final radius = w * 0.030;
    final logoBox = w * 0.135;
    final logoGap = w * 0.030;
    final lineGap = w * 0.009;
    final dateSize = w * 0.037;
    final bodySize = w * 0.031;

    const shadow = Shadow(color: Colors.black87, blurRadius: 3);

    TextPainter tp(
      String text,
      double size,
      FontWeight weight,
      double maxW, {
      int maxLines = 1,
    }) {
      return TextPainter(
        textDirection: TextDirection.ltr,
        maxLines: maxLines,
        ellipsis: '…',
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: size,
            height: 1.28,
            fontWeight: weight,
            color: Colors.white,
            shadows: const [shadow],
          ),
        ),
      )..layout(maxWidth: maxW);
    }

    // Width available to the text column (panel inner width minus the logo).
    final hasLogo = logo != null;
    final textMaxWidth =
        (w - margin * 2) - pad * 2 - (hasLogo ? logoBox + logoGap : 0);

    final now = DateTime.now();
    final datePainter = tp(
      '${DateFormat('MM/dd/yyyy  hh:mm a').format(now)}   GMT+8',
      dateSize,
      FontWeight.w700,
      textMaxWidth,
    );
    final addrPainter = tp(
      addressLine.isNotEmpty ? addressLine : 'Aparri, Cagayan',
      bodySize,
      FontWeight.w400,
      textMaxWidth,
      maxLines: 2,
    );
    final coordPainter = tp(
      'Lat ${latitude.toStringAsFixed(6)}      '
      'Long ${longitude.toStringAsFixed(6)}',
      bodySize,
      FontWeight.w400,
      textMaxWidth,
    );

    final textColHeight =
        datePainter.height +
        lineGap +
        addrPainter.height +
        lineGap +
        coordPainter.height;
    final contentHeight = math.max(textColHeight, hasLogo ? logoBox : 0.0);
    final panelHeight = contentHeight + pad * 2;

    // ── Rounded translucent panel at the bottom, inset by [margin] ───────────
    final panelLeft = margin;
    final panelTop = h - margin - panelHeight;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(panelLeft, panelTop, w - margin, h - margin),
        Radius.circular(radius),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );

    // ── GovPulse logo on a rounded white chip (left) ─────────────────────────
    final logoLeft = panelLeft + pad;
    final logoTop = panelTop + (panelHeight - logoBox) / 2;
    if (hasLogo) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(logoLeft, logoTop, logoBox, logoBox),
          Radius.circular(logoBox * 0.22),
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.96),
      );
      final inset = logoBox * 0.14;
      final dst = Rect.fromLTWH(
        logoLeft + inset,
        logoTop + inset,
        logoBox - inset * 2,
        logoBox - inset * 2,
      );
      final sw = logo.width.toDouble();
      final sh = logo.height.toDouble();
      final scale = math.min(dst.width / sw, dst.height / sh);
      final dw = sw * scale;
      final dh = sh * scale;
      canvas.drawImageRect(
        logo,
        Rect.fromLTWH(0, 0, sw, sh),
        Rect.fromLTWH(
          dst.left + (dst.width - dw) / 2,
          dst.top + (dst.height - dh) / 2,
          dw,
          dh,
        ),
        Paint()..filterQuality = FilterQuality.high,
      );
    }

    // ── Text column: date · time, address, coordinates ───────────────────────
    final textLeft = hasLogo ? logoLeft + logoBox + logoGap : panelLeft + pad;
    var dy = panelTop + (panelHeight - textColHeight) / 2;
    datePainter.paint(canvas, Offset(textLeft, dy));
    dy += datePainter.height + lineGap;
    addrPainter.paint(canvas, Offset(textLeft, dy));
    dy += addrPainter.height + lineGap;
    coordPainter.paint(canvas, Offset(textLeft, dy));

    final picture = recorder.endRecording();
    final rendered = await picture.toImage(image.width, image.height);
    // Grab the composited pixels as raw RGBA. This (and `toImage`) run on the
    // engine's raster thread, not the Dart UI isolate, so they don't jank.
    final rgbaData = await rendered.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    final int outW = image.width;
    final int outH = image.height;
    image.dispose();
    rendered.dispose();
    if (rgbaData == null) return null;

    // Re-encode to JPEG on a BACKGROUND isolate. package:image's encode is pure
    // Dart CPU work; doing it inline here would freeze the whole UI (and stall
    // the reveal animation) for a full-res photo. compute() keeps the main
    // thread free so the tile stays responsive until the file is ready.
    return compute(
      _encodeJpg,
      _JpgJob(rgbaData.buffer.asUint8List(), outW, outH),
    );
  }

  // ── Off-isolate JPEG encode ─────────────────────────────────────────────────
  static Uint8List? _encodeJpg(_JpgJob job) {
    final image = img.Image.fromBytes(
      width: job.width,
      height: job.height,
      bytes: job.rgba.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    // Quality 88 keeps the attachment small (stays under the 10MB cap).
    return Uint8List.fromList(img.encodeJpg(image, quality: 88));
  }
}

/// Payload for the background JPEG-encode isolate. Raw RGBA pixels plus their
/// dimensions — everything the isolate needs, all trivially copyable.
class _JpgJob {
  final Uint8List rgba;
  final int width;
  final int height;
  const _JpgJob(this.rgba, this.width, this.height);
}
