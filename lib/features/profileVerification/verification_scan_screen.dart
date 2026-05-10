import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

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
  CameraController? _controller;
  Future<void>? _initializeControllerFuture;

  bool isFront = true;
  bool _isCapturing = false;
  bool _showScanLine = false;

  late AnimationController _shutterController;
  late Animation<double> _shutterScaleAnimation;

  late AnimationController _scanLineController;
  late Animation<double> _scanLineAnimation;

  Uint8List? frontImage;
  Uint8List? backImage;

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

    // 🔥 Faster + smoother scan
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

    _controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
    );

    _initializeControllerFuture = _controller!.initialize();

    await _initializeControllerFuture;
    await _controller!.setFlashMode(FlashMode.off); // ✅ fix

    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?.dispose();
    _shutterController.dispose();
    _scanLineController.dispose();

    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    super.dispose();
  }

  String get label => "${widget.selectedId} ${isFront ? "Front" : "Back"}";

  @override
  Widget build(BuildContext context) {
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
                    _buildCameraPreview(),
                    _buildOverlay(),
                    Center(child: _buildFrame()),

                    /// 🔥 ENHANCED SCAN EFFECT
                    if (_showScanLine)
                      Center(
                        child: SizedBox(
                          width: 220,
                          height: 320,
                          child: AnimatedBuilder(
                            animation: _scanLineAnimation,
                            builder: (context, _) {
                              final pos = _scanLineAnimation.value * 300;

                              return Stack(
                                children: [
                                  /// Glow beam
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

                                  /// Core laser line
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

                                  /// Subtle pulse fill
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

                    Positioned(
                      right: 15,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: RotatedBox(
                          quarterTurns: 1,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                label,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
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

                    Positioned(
                      top: 20,
                      left: 10,
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
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
      width: 220,
      height: 320,
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
          width: 220,
          height: 320,
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

    await _shutterController.forward();
    await _shutterController.reverse();

    HapticFeedback.lightImpact();

    try {
      await _initializeControllerFuture;
      final image = await _controller!.takePicture();
      final bytes = await image.readAsBytes();
      final fixed = _rotate(bytes);

      _scanLineController.reset(); // 🔥 FORCE start from 0

      setState(() => _showScanLine = true);

      await Future.delayed(
        const Duration(milliseconds: 50),
      ); // allow frame render

      _scanLineController.forward().then((_) {
        if (mounted) setState(() => _showScanLine = false);
      });

      await Future.delayed(const Duration(milliseconds: 800));

      if (isFront) {
        frontImage = fixed;

        setState(() {
          isFront = false;
          _isCapturing = false;
        });
      } else {
        backImage = fixed;
        if (!mounted) return;
        Navigator.pushNamed(
          context,
          '/verification_review',
          arguments: {
            'username': widget.username,
            'selectedId': widget.selectedId,
            'frontImage': frontImage,
            'backImage': backImage,
          },
        );
      }
    } catch (e) {
      debugPrint(e.toString());
      setState(() => _isCapturing = false);
    }
  }

  Uint8List _rotate(Uint8List bytes) {
    final original = img.decodeImage(bytes)!;
    final rotated = img.copyRotate(original, angle: 90);
    return Uint8List.fromList(img.encodeJpg(rotated));
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
