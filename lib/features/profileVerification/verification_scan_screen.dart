import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import '../../core/router/legacy_nav.dart';
import '../../core/services/id_check_service.dart';
import '../../core/services/id_verification_service.dart';
import '../../core/widgets/app_dialog.dart' show kWebDialogMaxWidth;
import '../../core/widgets/app_back_chevron.dart';

/// The size the live preview actually occupies, in the camera's own pixels,
/// given what the platform reports as `previewSize`.
///
/// ── Why this is not just "swap width and height" ─────────────────────────
/// It used to be. `SizedBox(width: previewSize.height, height: previewSize
/// .width)` is right on MOBILE and wrong on WEB, and the difference is where
/// the 100x zoom on mobile web came from.
///
/// On mobile the platform hands back a LANDSCAPE buffer (1920x1080) no matter
/// how the phone is held, and `CameraPreview` compensates: for a portrait
/// orientation it builds `AspectRatio(1 / controller.aspectRatio)`, i.e. the
/// transposed 9:16. Transposing the SizedBox to match is what makes the two
/// agree, and the `BoxFit.cover` around them then fills a portrait screen with
/// a portrait box - roughly 1:1, no zoom.
///
/// On web there is no sensor orientation to compensate for. camera_web reports
/// the video track's own settings (`getVideoSize`), which a mobile browser
/// already gives PORTRAIT - 1080x1920 - because the track is what the screen
/// is showing. `CameraPreview` cannot tell, so it transposes anyway and asks
/// for 16:9; the old SizedBox transposed a second time and asked for 16:9 too.
/// Consistent, and both landscape. `BoxFit.cover` then had to scale a 1920x1080
/// box to cover a ~390x780 viewport: it takes the LARGER ratio, 780/1080 =
/// 0.72, rendering 1386x780 into a 390-wide window. Under a quarter of the
/// frame survives, and the video element is `object-fit: cover` inside that
/// oversized box as well, so the crops multiply. That is the "uncontrollable
/// zoom": not a zoom setting at all, a preview scaled to the wrong axis.
///
/// So: transpose only when the platform's buffer needs it. On web, report the
/// track's size as given - already in the orientation the user is holding.
@visibleForTesting
Size previewSourceSize(Size previewSize, {required bool isWeb}) {
  if (isWeb) return previewSize;
  return Size(previewSize.height, previewSize.width);
}

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

  /// WEB only: the camera could not be started, so this screen has nothing
  /// to show and must offer a way out instead of a spinner. Never set on
  /// mobile - see [_initCamera].
  bool _webCameraFailed = false;

  /// WEB only: why the camera could not be started, in the browser's words.
  ///
  /// The screen used to say "your browser blocked it, or this device has no
  /// camera" for every failure, which sends people to check a permission that
  /// is already granted. The common case is a camera another app or tab is
  /// still holding, and that one is fixable from here - see [_webCameraHint].
  String? _webCameraErrorCode;

  /// WEB only: guards [_retryWebCamera] against a second tap while the first
  /// attempt is still asking the browser for a stream.
  bool _webCameraRetrying = false;

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

  /// WEB only: the server's verdict on each captured side.
  ///
  /// Held across the two captures because the front is scanned and accepted
  /// before the back is even taken, and the SUBMIT step needs both to store a
  /// combined result for the reviewer. Cleared alongside [frontImage] whenever
  /// the flow restarts, so a rejected retake cannot carry a stale verdict.
  IdCheckResult? _frontCheck;
  IdCheckResult? _backCheck;

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
    final List<CameraDescription> cameras;
    try {
      cameras = await availableCameras();
    } catch (e) {
      // WEB: the browser throws here when the user dismisses or blocks the
      // camera prompt. Mobile RETHROWS, so its behaviour - an unhandled
      // async error from initState - is exactly what it was.
      if (!kIsWeb) rethrow;
      debugPrint('[CAMERA] availableCameras failed: $e');
      _failWebCamera(e);
      return;
    }

    // WEB: there may be no BACK camera at all - a laptop has one webcam and
    // it faces the user - and `firstWhere` with no `orElse` throws a
    // StateError, which would land here as a black screen with no camera and
    // no explanation. A tablet does have a back camera and still gets it;
    // anything else gets whatever camera exists rather than nothing.
    //
    // Deliberately NOT applied to mobile. Every phone this ships to has a
    // back camera, so on mobile the original expression is kept exactly as
    // it was, including how it fails.
    final CameraDescription camera;
    if (kIsWeb) {
      if (cameras.isEmpty) {
        _failWebCamera('notFound');
        return;
      }
      camera = cameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
    } else {
      camera = cameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.back,
      );
    }

    // MOBILE: try max -> veryHigh -> high. Some Android devices silently
    // downgrade `max`, so we fall back rather than ending up with .high
    // anyway.
    //
    // WEB: one attempt only. camera_web turns a ResolutionPreset into `ideal`
    // width/height constraints, and a browser rounds `ideal` to the nearest
    // mode it actually has - asking a 720p webcam for 4096x2160 returns 720p
    // rather than failing. A preset can therefore never be the reason a web
    // attempt failed, and walking the list only opened the same device twice
    // more, each attempt competing with the stream the previous one left
    // running.
    final List<ResolutionPreset> presetsToTry = kIsWeb
        ? const <ResolutionPreset>[ResolutionPreset.ultraHigh]
        : const <ResolutionPreset>[
            ResolutionPreset.ultraHigh,
            ResolutionPreset.veryHigh,
            ResolutionPreset.high,
          ];

    CameraController? working;
    Object? lastError;
    for (final preset in presetsToTry) {
      CameraController? candidate;
      try {
        candidate = CameraController(
          camera,
          preset,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.jpeg,
        );
        await candidate.initialize();
        debugPrint(
          '[CAMERA] Init OK at preset=$preset '
          'preview=${candidate.value.previewSize}',
        );
        working = candidate;
        break;
      } catch (e) {
        lastError = e;
        debugPrint('[CAMERA] Preset $preset failed: $e - trying next');
        // A controller whose initialize() threw still holds whatever the
        // platform handed it before the failure. On web that is a live
        // getUserMedia stream: without this the browser goes on reporting
        // "Camera - Using now" for a screen that has just told the user it
        // cannot open the camera, and the next attempt has to fight the
        // abandoned stream for the device.
        await _releaseController(candidate);
      }
    }

    // The screen can be popped while the browser is still deciding. Releasing
    // here is what keeps that from leaving the camera light on.
    if (!mounted) {
      await _releaseController(working);
      return;
    }

    // WEB: no usable camera here - blocked by permission, already in use, or
    // unsupported. Without this the screen sat on a spinner whose only
    // sibling, the back chevron, is inside the branch that needs a live
    // controller. That was a trap with no exit.
    if (kIsWeb && working == null) {
      _failWebCamera(lastError);
      return;
    }

    _controller = working;
    _initializeControllerFuture = Future.value();

    if (_controller != null) {
      // Guarded, and not only on web. camera_web throws
      // `torchModeNotSupported` from setFlashMode for any camera without a
      // torch - which is every laptop webcam - and that exception escaped
      // _initCamera before the setState below, so a camera that had started
      // perfectly well was never shown: a permanent spinner over a live
      // stream. Failing to turn a flash off is not a reason to withhold the
      // preview on any platform.
      try {
        await _controller!.setFlashMode(FlashMode.off);
      } catch (e) {
        debugPrint('[CAMERA] setFlashMode unsupported: $e');
      }
      try {
        await _controller!.setFocusMode(FocusMode.auto);
        await _controller!.setExposureMode(ExposureMode.auto);
      } catch (_) {}
    }

    if (mounted) setState(() {});
  }

  /// Releases a controller that will not be used, swallowing what that costs.
  ///
  /// `dispose()` throws when the controller never got as far as a platform id,
  /// so the guard is the point: the caller wants the stream stopped and has
  /// nothing useful to do about a failure to stop it.
  Future<void> _releaseController(CameraController? controller) async {
    if (controller == null) return;
    try {
      await controller.dispose();
    } catch (e) {
      debugPrint('[CAMERA] dispose after failed init: $e');
    }
  }

  /// WEB only: moves the screen to its "no camera" state, remembering why.
  void _failWebCamera(Object? error) {
    if (!mounted) return;
    setState(() {
      _webCameraFailed = true;
      _webCameraRetrying = false;
      _webCameraErrorCode = error is CameraException
          ? error.code
          : error?.toString();
    });
  }

  /// WEB only: starts over, for the failures a second try can fix.
  ///
  /// A camera held by another tab, another app, or by this screen's own
  /// abandoned stream is free again moments later, and re-entering the flow
  /// from the previous screen was a long way to go for a retry.
  Future<void> _retryWebCamera() async {
    if (_webCameraRetrying) return;
    setState(() {
      _webCameraRetrying = true;
      _webCameraFailed = false;
      _webCameraErrorCode = null;
    });
    await _initCamera();
    if (mounted && _webCameraRetrying) {
      setState(() => _webCameraRetrying = false);
    }
  }

  /// WEB only: drops the live stream while this screen sits behind another.
  ///
  /// Clears the controller so [build] falls back to its "starting" state
  /// rather than handing a disposed controller to [CameraPreview].
  Future<void> _releaseCameraForPush() async {
    final controller = _controller;
    if (controller == null) return;
    _controller = null;
    _initializeControllerFuture = null;
    if (mounted) setState(() {});
    await _releaseController(controller);
  }

  /// WEB only: reopens the camera when the user comes BACK to this screen.
  ///
  /// Guarded on `_controller == null` so a normal rebuild never reopens a
  /// stream that is already running.
  Future<void> _ensureCameraForResume() async {
    if (!kIsWeb || _controller != null) return;
    setState(() {
      _webCameraFailed = false;
      _webCameraErrorCode = null;
    });
    await _initCamera();
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

  // ==========================================================================
  //  WEB-only states
  // ==========================================================================

  /// Shown while the browser is still deciding about the camera.
  ///
  /// Identical to the phone's spinner except that it carries the chevron, so a
  /// permission prompt left sitting in the corner of the screen is never a
  /// one-way door.
  Widget _buildWebCameraStarting() {
    return Stack(
      children: [
        const Center(child: CircularProgressIndicator()),
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 16,
          child: const AppBackChevron(onDark: true),
        ),
      ],
    );
  }

  /// What to tell the user about [_webCameraErrorCode], and what to do next.
  ///
  /// camera_web reports a `CameraErrorCode` name, so these match on the
  /// substring rather than the whole string - a code arrives as either
  /// `notReadable` or `CameraErrorCode.notReadable` depending on which layer
  /// wrapped it.
  String get _webCameraHint {
    final code = (_webCameraErrorCode ?? '').toLowerCase();
    if (code.contains('notreadable') || code.contains('trackstart')) {
      return 'Another app or browser tab is already using the camera. Close '
          'it and tap Try again, or continue with a photo from your device.';
    }
    if (code.contains('permissiondenied') || code.contains('notallowed')) {
      return 'Your browser is blocking the camera. Allow it from the padlock '
          'in the address bar and tap Try again, or continue with a photo '
          'from your device.';
    }
    if (code.contains('notfound') || code.contains('devicesnotfound')) {
      return 'This device has no camera available. Go back and choose '
          '"Upload a file instead" to continue with a photo from your device.';
    }
    if (code.contains('security') || code.contains('type')) {
      return 'This browser will not open a camera on an insecure page. Go '
          'back and choose "Upload a file instead" to continue with a photo '
          'from your device.';
    }
    return 'The camera could not be started. Tap Try again, or go back and '
        'choose "Upload a file instead" to continue with a photo from your '
        'device.';
  }

  /// Shown when the camera cannot be started at all.
  ///
  /// Two ways out, because the two causes need different ones. A camera held
  /// by another tab or app is free again seconds later, so Try again re-runs
  /// [_initCamera] in place; a blocked or absent camera is not going to
  /// appear, so the second button leaves for the file picker on the previous
  /// screen - which is where the user chose the camera in the first place, so
  /// it puts them back in front of the same two options.
  Widget _buildWebCameraError() {
    return SafeArea(
      child: Stack(
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.no_photography_outlined,
                      size: 44,
                      color: Colors.white70,
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      "Can't open the camera",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _webCameraHint,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.5,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _webCameraRetrying ? null : _retryWebCamera,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black87,
                          disabledBackgroundColor: Colors.white24,
                          disabledForegroundColor: Colors.white70,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: const Text('Try again'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: const Text('Upload a file instead'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 8,
            left: 16,
            child: const AppBackChevron(onDark: true),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      // WEB gets two states the phone never needs: a camera that could not
      // start, and a camera still starting. Both must carry a way out, because
      // the chevron below lives inside the live-preview Stack. On mobile
      // `kIsWeb` is a compile-time false, so this reads exactly as
      // `_controller == null ? spinner : FutureBuilder(...)` did.
      body: kIsWeb && _webCameraFailed
          ? _buildWebCameraError()
          : _controller == null
          ? (kIsWeb
                ? _buildWebCameraStarting()
                : const Center(child: CircularProgressIndicator()))
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
    final source = previewSourceSize(
      _controller!.value.previewSize!,
      isWeb: kIsWeb,
    );
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: source.width,
          height: source.height,
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
      // WEB: no OCR. [IdVerificationService] is built on ML Kit text
      // recognition and dart:io, neither of which has a web implementation -
      // the import compiles, but the call throws a MissingPluginException at
      // runtime, from inside this try block, where it would look to the user
      // like the shutter simply did nothing.
      //
      // WEB now goes to `verify-id` instead of being skipped. It used to
      // return null here ("not checked"), which meant a mobile-web scan was
      // accepted with no validation and no auto-fill at all. The Edge Function
      // runs the SAME rules server-side, so both platforms agree.
      IdVerificationResult? result;
      IdCheckResult? webResult;
      if (kIsWeb) {
        webResult = await IdCheckService.check(
          imageBytes: fixed,
          idType: widget.selectedId,
          isFront: isFront,
          source: 'camera',
        );
      } else {
        result = await IdVerificationService.verify(
          imageBytes: fixed,
          selectedIdType: widget.selectedId,
          isFront: isFront,
        );
      }
      if (mounted) setState(() => _isVerifying = false);

      await animFuture;
      if (mounted) setState(() => _showScanLine = false);

      // ── WEB: only an outright REJECT stops the scan ───────────────────
      //
      // A `review` verdict proceeds. The submission reaches a human with the
      // reasons attached, which is where every web scan went before this
      // existed; blocking on `review` would turn away genuine users whose card
      // photographed badly, and that loses real citizens.
      if (webResult != null && webResult.verdict == IdVerdict.reject) {
        if (!mounted) return;
        await _showInvalidIdDialog(webResult.userMessage);
        if (mounted) {
          setState(() {
            _isCapturing = false;
            isFront = true;
            frontImage = null;
            _extractedData = {};
            _frontCheck = null;
            _backCheck = null;
          });
        }
        return;
      }

      // ── Validity check BEFORE any data is merged ──────────────────────
      // `result != null` is the web arm only: on mobile the service always
      // returns a result, so this reads exactly as `!result.isValid` did.
      if (result != null && !result.isValid) {
        if (!mounted) return;
        await _showInvalidIdDialog(result.errorMessage ?? "Invalid ID");
        if (mounted) {
          setState(() {
            _isCapturing = false;
            isFront = true; // restart from front
            frontImage = null; // discard accepted front
            _extractedData = {}; // wipe any partial data
            _frontCheck = null;
            _backCheck = null;
          });
        }
        return;
      }

      // ── Only merge data from a verified scan ──────────────────────────
      //
      // On web these are the server's GATED fields: values that survived the
      // auto-fill confidence check, not everything OCR produced. A blank the
      // user types is a keystroke; a wrong value they skim past becomes their
      // permanent record.
      for (final entry
          in (result?.extractedData ??
                  webResult?.fields ??
                  const <String, String>{})
              .entries) {
        final existing = _extractedData[entry.key];
        if (existing == null || existing.isEmpty) {
          _extractedData[entry.key] = entry.value;
        }
      }

      if (isFront) {
        frontImage = fixed;
        _frontCheck = webResult;
        if (mounted) {
          setState(() {
            isFront = false;
            _isCapturing = false;
          });
        }
      } else {
        backImage = fixed;
        _backCheck = webResult;
        if (!mounted) return;
        // WEB: this is a PUSH, not a replacement - the scan screen stays alive
        // underneath the rest of the wizard, and on web an undisposed
        // CameraController is a live getUserMedia stream. It stayed open for
        // every screen that followed, so the face-scan step asked the browser
        // for the same webcam and got `notReadable` - surfaced to the user as
        // "another app or browser tab is already using the camera", with no
        // other tab in sight.
        //
        // Awaited, unlike the fire-and-forget call in [dispose]: the tracks
        // must actually be stopped before the next screen asks for the device,
        // and on web dispose() stops them inside its async body.
        //
        // Mobile is deliberately untouched - `kIsWeb` is a compile-time false
        // there, so the phone's controller keeps the lifecycle it always had.
        if (kIsWeb) await _releaseCameraForPush();
        if (!mounted) return;

        final push = pushLegacy(
          context,
          '/verification_review',
          arguments: {
            'username': widget.username,
            'selectedId': widget.selectedId,
            'frontImage': frontImage,
            'backImage': backImage,
            'extractedData': _extractedData,
            // Null on mobile: that path checks with ML Kit rather than the
            // Edge Function, so there is no server verdict to carry and the
            // column is left NULL rather than invented.
            'idCheck': IdSubmissionCheck.combine(
              _frontCheck,
              _backCheck,
            )?.toRouteArg(),
          },
        );

        // MOBILE keeps its original control flow exactly: the push is NOT
        // awaited, so nothing after it runs, `_isCapturing` stays true on a
        // screen that is never coming back, and a failure inside the pushed
        // route cannot fall into this method's catch.
        //
        // WEB has to await, because the camera released above must be reopened
        // when the user comes back - and coming back is a normal thing to do
        // here, since this screen stays on the stack either way.
        if (!kIsWeb) return;
        await push;
        if (!mounted) return;

        // Back on this screen. Restart from the FRONT: both stills were handed
        // to the review step, and a screen showing "Back" with no front image
        // behind it cannot produce a valid pair. `_isCapturing` is cleared with
        // them - it is set for the duration of a capture and was only ever left
        // true here because this screen used to be abandoned at this point.
        setState(() {
          isFront = true;
          frontImage = null;
          backImage = null;
          _extractedData = {};
          _frontCheck = null;
          _backCheck = null;
          _isCapturing = false;
        });
        await _ensureCameraForResume();
      }
    } catch (e) {
      debugPrint('Capture error: $e');
      if (mounted) {
        setState(() {
          _isCapturing = false;
          isFront = true; // also reset on exception
          frontImage = null;
          _extractedData = {};
          _frontCheck = null;
          _backCheck = null;
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
                  // WEB: a horizontal margin is not a width. Without this the
                  // rejection notice spanned the browser. Same 380 every other
                  // citizen-web confirm uses; unconstrained on the phone.
                  constraints: BoxConstraints(
                    maxWidth: kIsWeb ? kWebDialogMaxWidth : double.infinity,
                  ),
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

    // The crop has to reproduce the geometry the PREVIEW used, because the
    // frame the user lined the ID up inside is positioned in screen space.
    // Deriving cover from the decoded bytes' own dimensions is what keeps the
    // two in step on both platforms, and only because the bytes arrive in the
    // same orientation the preview showed:
    //
    //   MOBILE - a landscape sensor buffer, previewed through the transposed
    //   SizedBox in [previewSourceSize] and captured the same way.
    //   WEB - camera_web's takePicture sizes its canvas from the video
    //   element's own videoWidth/videoHeight, so a portrait track yields
    //   portrait bytes, which is now exactly what the preview shows too.
    //
    // Before [previewSourceSize] the web preview was transposed to landscape
    // while these bytes stayed portrait, so this scale was computed against a
    // frame that had never been on screen and the crop missed the card.
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
