import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import '../../core/router/legacy_nav.dart';
import '../../core/services/id_verification_service.dart';
import '../../core/widgets/app_back_chevron.dart';

class VerificationScanScreen extends StatefulWidget {
  final String username;
  final String selectedId;

  const VerificationScanScreen({
    super.key,
    required this.username,
    required this.selectedId,
  });

  @override
  State<VerificationScanScreen> createState() => _VerificationScanScreenState();
}

class _VerificationScanScreenState extends State<VerificationScanScreen>
    with TickerProviderStateMixin {
  // ─── Frame geometry (single source of truth) ────────────────────────
  // CR80 / PH ID aspect ratio is ~1.586 (landscape, like a credit card).
  static const double _frameWidth = 320.0;
  static const double _frameHeight = 200.0;

  CameraController? _controller;
  Future<void>? _initializeControllerFuture;

  bool isFront = true;
  bool _isCapturing = false;
  bool _showScanLine = false;
  bool _isVerifying = false;

  late AnimationController _shutterController;
  late Animation<double> _shutterScaleAnimation;

  late AnimationController _scanLineController;
  late Animation<double> _scanLineAnimation;

  Uint8List? frontImage;
  Uint8List? backImage;
  Map<String, String> _extractedData = {};

  // Brief tap-to-focus indicator
  Offset? _focusPoint;
  bool _showFocusIndicator = false;

  @override
  void initState() {
    super.initState();

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

    _initCamera();

    _shutterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _shutterScaleAnimation = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _shutterController, curve: Curves.easeInOut),
    );

    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _scanLineAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _scanLineController, curve: Curves.easeInOut),
    );
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    final camera = cameras.firstWhere(
      (cam) => cam.lensDirection == CameraLensDirection.back,
    );

    // Try max → veryHigh → high. Some Android devices silently downgrade
    // `max`, so we fall back rather than ending up with .high anyway.
    final presetsToTry = [
      ResolutionPreset.ultraHigh,
      ResolutionPreset.veryHigh,
      ResolutionPreset.high,
    ];

    CameraController? working;
    for (final preset in presetsToTry) {
      try {
        final c = CameraController(
          camera,
          preset,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.jpeg,
        );
        await c.initialize();
        debugPrint(
          '[CAMERA] Init OK at preset=$preset '
          'preview=${c.value.previewSize}',
        );
        working = c;
        break;
      } catch (e) {
        debugPrint('[CAMERA] Preset $preset failed: $e — trying next');
      }
    }

    _controller = working;
    _initializeControllerFuture = Future.value();

    if (_controller != null) {
      await _controller!.setFlashMode(FlashMode.off);
      try {
        await _controller!.setFocusMode(FocusMode.auto);
        await _controller!.setExposureMode(ExposureMode.auto);
      } catch (_) {}
    }

    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?.dispose();
    _shutterController.dispose();
    _scanLineController.dispose();

    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    super.dispose();
  }

  String get label => "${widget.selectedId} ${isFront ? "Front" : "Back"}";

  // ── Tap-to-focus ───────────────────────────────────────────────────────
  Future<void> _focusAt(Offset position, Size screenSize) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      final x = (position.dx / screenSize.width).clamp(0.0, 1.0);
      final y = (position.dy / screenSize.height).clamp(0.0, 1.0);
      await _controller!.setFocusPoint(Offset(x, y));
      await _controller!.setExposurePoint(Offset(x, y));
      HapticFeedback.selectionClick();

      if (mounted) {
        setState(() {
          _focusPoint = position;
          _showFocusIndicator = true;
        });
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) setState(() => _showFocusIndicator = false);
      }
    } catch (e) {
      debugPrint('Focus failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      body: _controller == null
          ? const Center(child: CircularProgressIndicator())
          : FutureBuilder(
              future: _initializeControllerFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }

                return Stack(
                  children: [
                    // Tappable preview (tap-to-focus)
                    GestureDetector(
                      onTapDown: (details) =>
                          _focusAt(details.globalPosition, screenSize),
                      child: _buildCameraPreview(),
                    ),

                    _buildOverlay(),
                    Center(child: _buildFrame()),

                    // Tap-to-focus ring
                    if (_showFocusIndicator && _focusPoint != null)
                      Positioned(
                        left: _focusPoint!.dx - 30,
                        top: _focusPoint!.dy - 30,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 1.4, end: 1.0),
                          duration: const Duration(milliseconds: 250),
                          builder: (_, scale, _) => Transform.scale(
                            scale: scale,
                            child: Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                    if (_showScanLine)
                      Center(
                        child: SizedBox(
                          width: _frameWidth,
                          height: _frameHeight,
                          child: AnimatedBuilder(
                            animation: _scanLineAnimation,
                            builder: (context, _) {
                              final pos =
                                  _scanLineAnimation.value *
                                  (_frameHeight - 20);

                              return Stack(
                                children: [
                                  Positioned(
                                    top: pos - 6,
                                    left: 0,
                                    right: 0,
                                    child: Container(
                                      height: 14,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            Colors.transparent,
                                            Colors.blue.withValues(alpha: 0.2),
                                            Colors.blue.withValues(alpha: 0.6),
                                            Colors.blue.withValues(alpha: 0.2),
                                            Colors.transparent,
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: pos,
                                    left: 0,
                                    right: 0,
                                    child: Container(
                                      height: 3,
                                      decoration: BoxDecoration(
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.blueAccent.withValues(
                                              alpha: 0.9,
                                            ),
                                            blurRadius: 12,
                                            spreadRadius: 2,
                                          ),
                                        ],
                                        gradient: const LinearGradient(
                                          colors: [
                                            Colors.transparent,
                                            Colors.white,
                                            Colors.blueAccent,
                                            Colors.white,
                                            Colors.transparent,
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  AnimatedOpacity(
                                    duration: const Duration(milliseconds: 200),
                                    opacity:
                                        0.15 * (1 - _scanLineAnimation.value),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        color: Colors.blueAccent,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),

                    // Label above the landscape frame
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 70,
                      left: 0,
                      right: 0,
                      child: Column(
                        children: [
                          Text(
                            label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            "Tap the screen to focus",
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (_isVerifying)
                      Positioned(
                        top: screenSize.height * 0.65,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation(
                                      Colors.white,
                                    ),
                                  ),
                                ),
                                SizedBox(width: 10),
                                Text(
                                  "Verifying ID…",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    Positioned(
                      bottom: 30,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: GestureDetector(
                          onTap: _isCapturing ? null : _capture,
                          child: ScaleTransition(
                            scale: _shutterScaleAnimation,
                            child: Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: 0.15),
                                border: Border.all(
                                  color: _isCapturing
                                      ? Colors.blue
                                      : Colors.white,
                                  width: _isCapturing ? 4 : 3,
                                ),
                              ),
                              child: Center(
                                child: Container(
                                  width: 52,
                                  height: 52,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _isCapturing
                                        ? Colors.blue.withValues(alpha: 0.3)
                                        : Colors.white24,
                                  ),
                                  child: Icon(
                                    _isCapturing
                                        ? Icons.check
                                        : Icons.camera_alt_outlined,
                                    size: 28,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Was a bare white IconButton with the Material
                    // Icons.arrow_back — the fourth distinct back chevron in
                    // this one wizard. The Scaffold here is BLACK behind a
                    // full-bleed camera preview, so the chip takes its dark
                    // variant: same shape and proportions as Settings, inverted
                    // colours, because a light fill has nothing to sit against
                    // and a light border would vanish.
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 8,
                      left: 16,
                      child: const AppBackChevron(onDark: true),
                    ),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildCameraPreview() {
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _controller!.value.previewSize!.height,
          height: _controller!.value.previewSize!.width,
          child: CameraPreview(_controller!),
        ),
      ),
    );
  }

  Widget _buildFrame() {
    return SizedBox(
      width: _frameWidth,
      height: _frameHeight,
      child: Stack(
        children: [
          _corner(top: 0, left: 0),
          _corner(top: 0, right: 0),
          _corner(bottom: 0, left: 0),
          _corner(bottom: 0, right: 0),
        ],
      ),
    );
  }

  Widget _corner({double? top, double? left, double? right, double? bottom}) {
    return Positioned(
      top: top,
      left: left,
      right: right,
      bottom: bottom,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          border: Border(
            top: top != null
                ? const BorderSide(color: Colors.blue, width: 4)
                : BorderSide.none,
            left: left != null
                ? const BorderSide(color: Colors.blue, width: 4)
                : BorderSide.none,
            right: right != null
                ? const BorderSide(color: Colors.blue, width: 4)
                : BorderSide.none,
            bottom: bottom != null
                ? const BorderSide(color: Colors.blue, width: 4)
                : BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildOverlay() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final rect = Rect.fromCenter(
          center: Offset(constraints.maxWidth / 2, constraints.maxHeight / 2),
          width: _frameWidth,
          height: _frameHeight,
        );

        return ClipPath(
          clipper: _InverseHoleClipper(rect),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(color: Colors.black.withValues(alpha: 0.45)),
          ),
        );
      },
    );
  }

  Future<void> _capture() async {
    if (_isCapturing) return;
    setState(() => _isCapturing = true);

    final screenSize = MediaQuery.of(context).size;

    await _shutterController.forward();
    await _shutterController.reverse();

    HapticFeedback.lightImpact();

    try {
      await _initializeControllerFuture;

      try {
        await _controller!.setFocusMode(FocusMode.locked);
        await Future.delayed(const Duration(milliseconds: 300));
      } catch (_) {}

      final image = await _controller!.takePicture();

      try {
        await _controller!.setFocusMode(FocusMode.auto);
      } catch (_) {}

      final bytes = await image.readAsBytes();
      final fixed = _rotateAndCrop(bytes, screenSize);

      _scanLineController.reset();
      if (mounted) setState(() => _showScanLine = true);
      await Future.delayed(const Duration(milliseconds: 50));
      final animFuture = _scanLineController.forward();

      if (mounted) setState(() => _isVerifying = true);
      final result = await IdVerificationService.verify(
        imageBytes: fixed,
        selectedIdType: widget.selectedId,
        isFront: isFront,
      );
      if (mounted) setState(() => _isVerifying = false);

      await animFuture;
      if (mounted) setState(() => _showScanLine = false);

      // ── Validity check BEFORE any data is merged ──────────────────────
      if (!result.isValid) {
        if (!mounted) return;
        await _showInvalidIdDialog(result.errorMessage ?? "Invalid ID");
        if (mounted) {
          setState(() {
            _isCapturing = false;
            isFront = true; // restart from front
            frontImage = null; // discard accepted front
            _extractedData = {}; // wipe any partial data
          });
        }
        return;
      }

      // ── Only merge data from a verified scan ──────────────────────────
      for (final entry in result.extractedData.entries) {
        final existing = _extractedData[entry.key];
        if (existing == null || existing.isEmpty) {
          _extractedData[entry.key] = entry.value;
        }
      }

      if (isFront) {
        frontImage = fixed;
        if (mounted) {
          setState(() {
            isFront = false;
            _isCapturing = false;
          });
        }
      } else {
        backImage = fixed;
        if (!mounted) return;
        pushLegacy(
          context,
          '/verification_review',
          arguments: {
            'username': widget.username,
            'selectedId': widget.selectedId,
            'frontImage': frontImage,
            'backImage': backImage,
            'extractedData': _extractedData,
          },
        );
      }
    } catch (e) {
      debugPrint('Capture error: $e');
      if (mounted) {
        setState(() {
          _isCapturing = false;
          isFront = true; // also reset on exception
          frontImage = null;
          _extractedData = {};
        });
      }
    }
  }

  Future<void> _showInvalidIdDialog(String message) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, _, _) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, _, _) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
        return ScaleTransition(
          scale: Tween(begin: 0.8, end: 1.0).animate(curved),
          child: FadeTransition(
            opacity: anim,
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 28),
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                        ),
                        child: const Icon(
                          Icons.camera_alt_outlined,
                          color: Color(0xFF2563EB),
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        "Hmm, let's try that again",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF6B7280),
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _ScanTip(
                              icon: Icons.wb_sunny_outlined,
                              text: "Use bright, even lighting",
                            ),
                            SizedBox(height: 8),
                            _ScanTip(
                              icon: Icons.center_focus_strong_outlined,
                              text: "Fit the ID inside the blue frame",
                            ),
                            SizedBox(height: 8),
                            _ScanTip(
                              icon: Icons.text_fields,
                              text: "Make sure all text is sharp and readable",
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            "Retake Photo",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Uint8List _rotateAndCrop(Uint8List bytes, Size screenSize) {
    final decoded = img.decodeImage(bytes)!;

    final rawW = decoded.width.toDouble();
    final rawH = decoded.height.toDouble();

    final screenW = screenSize.width;
    final screenH = screenSize.height;

    // Camera sensor is landscape (rawW > rawH)
    // Preview is shown as portrait via cover fit
    // So we treat imgW = rawW, imgH = rawH directly
    final coverScale = (screenW / rawW) > (screenH / rawH)
        ? screenW / rawW
        : screenH / rawH;

    final scaledW = rawW * coverScale;
    final scaledH = rawH * coverScale;
    final imgLeftOnScreen = (screenW - scaledW) / 2;
    final imgTopOnScreen = (screenH - scaledH) / 2;

    final frameLeftOnScreen = (screenW - _frameWidth) / 2;
    final frameTopOnScreen = (screenH - _frameHeight) / 2;

    final padX = (_frameWidth * 0.05) / coverScale;
    final padY = (_frameHeight * 0.05) / coverScale;

    // Frame position in raw image space
    final cropX = ((frameLeftOnScreen - imgLeftOnScreen) / coverScale - padX)
        .round();
    final cropY = ((frameTopOnScreen - imgTopOnScreen) / coverScale - padY)
        .round();
    final cropW = (_frameWidth / coverScale + 2 * padX).round();
    final cropH = (_frameHeight / coverScale + 2 * padY).round();

    final safeX = cropX.clamp(0, decoded.width - 1).toInt();
    final safeY = cropY.clamp(0, decoded.height - 1).toInt();
    final safeW = cropW.clamp(1, decoded.width - safeX).toInt();
    final safeH = cropH.clamp(1, decoded.height - safeY).toInt();

    debugPrint(
      'CROP: raw=${decoded.width}x${decoded.height} '
      'crop=$safeW x$safeH @ ($safeX,$safeY)',
    );

    final cropped = img.copyCrop(
      decoded,
      x: safeX,
      y: safeY,
      width: safeW,
      height: safeH,
    );

    // No rotation needed — sensor already delivers landscape
    // which matches our landscape frame
    return Uint8List.fromList(img.encodeJpg(cropped, quality: 95));
  }
}

class _InverseHoleClipper extends CustomClipper<Path> {
  final Rect hole;

  _InverseHoleClipper(this.hole);

  @override
  Path getClip(Size size) {
    return Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(hole, const Radius.circular(12)))
      ..fillType = PathFillType.evenOdd;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

class _ScanTip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _ScanTip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF2563EB)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 12, color: Color(0xFF374151)),
          ),
        ),
      ],
    );
  }
}
