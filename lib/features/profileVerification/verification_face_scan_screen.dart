import 'dart:async';
import 'dart:io';
import '../../core/network/network_wrapper.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../features/home/screen/home_screen.dart';
import '../home/screen/notification_popup.dart';

class VerificationFaceScanScreen extends StatefulWidget {
  final String username;
  final String selectedId;

  // ── Form data from VerificationReviewScreen ───────────────────────────────
  final String idNumber;
  final String firstName;
  final String middleName;
  final String lastName;
  final String? suffix;
  final String gender;
  final String birthdate;
  final String birthplace;
  final String civilStatus;
  final String contactNumber;
  final String barangay;
  final String street;

  // ── ID images ─────────────────────────────────────────────────────────────
  final Uint8List? frontImage;
  final Uint8List? backImage;

  const VerificationFaceScanScreen({
    super.key,
    required this.username,
    required this.selectedId,
    required this.idNumber,
    required this.firstName,
    required this.middleName,
    required this.lastName,
    this.suffix,
    required this.gender,
    required this.birthdate,
    required this.birthplace,
    required this.civilStatus,
    required this.contactNumber,
    required this.barangay,
    required this.street,
    this.frontImage,
    this.backImage,
  });

  @override
  State<VerificationFaceScanScreen> createState() =>
      _VerificationFaceScanScreenState();
}

enum _ScanState {
  initializing,
  warming,
  waitingForFace,
  faceDetected,
  holdSteady,
  done,
}

class _VerificationFaceScanScreenState extends State<VerificationFaceScanScreen>
    with TickerProviderStateMixin {
  // ── Camera ────────────────────────────────────────────────────────────────
  CameraController? _cameraController;
  bool _cameraReady = false;
  bool _isCapturing = false;

  // ── Captured still frame ──────────────────────────────────────────────────
  Uint8List? _capturedImageBytes;

  // ── Upload state ──────────────────────────────────────────────────────────
  bool _isUploading = false;
  String? _uploadError;

  // ── Face detection ────────────────────────────────────────────────────────
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast,
      enableContours: false,
      enableLandmarks: false,
      enableClassification: false,
      enableTracking: false,
      minFaceSize: 0.05,
    ),
  );

  // ── Scan state ────────────────────────────────────────────────────────────
  _ScanState _scanState = _ScanState.initializing;

  // ── Timers ────────────────────────────────────────────────────────────────
  Timer? _detectionTimer;
  Timer? _holdTimer;
  Timer? _warmupTimer;

  // ── Animations ────────────────────────────────────────────────────────────
  late AnimationController _borderController;
  late Animation<double> _borderAnim;
  late AnimationController _progressController;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initAnimations();
    _initCamera();
  }

  void _initAnimations() {
    _borderController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _borderAnim = Tween<double>(begin: 3.0, end: 6.5).animate(
      CurvedAnimation(parent: _borderController, curve: Curves.easeInOut),
    );

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );

    _progressController.addStatusListener((status) async {
      if (status == AnimationStatus.completed && mounted) {
        try {
          final XFile photo = await _cameraController!.takePicture();
          final bytes = await File(photo.path).readAsBytes();
          try {
            File(photo.path).deleteSync();
          } catch (_) {}
          if (mounted) {
            setState(() {
              _capturedImageBytes = bytes;
              _scanState = _ScanState.done;
            });
            return;
          }
        } catch (_) {}
        if (mounted) setState(() => _scanState = _ScanState.done);
      }
    });
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      _cameraController = CameraController(
        front,
        ResolutionPreset.low,
        enableAudio: false,
      );
      await _cameraController!.initialize();
      if (!mounted) return;
      setState(() {
        _cameraReady = true;
        _scanState = _ScanState.warming;
      });
      _warmupTimer = Timer(const Duration(milliseconds: 2000), () {
        if (!mounted) return;
        setState(() => _scanState = _ScanState.waitingForFace);
        _startDetectionLoop();
      });
    } catch (_) {
      if (mounted) setState(() => _scanState = _ScanState.waitingForFace);
    }
  }

  void _startDetectionLoop() {
    _detectionTimer?.cancel();
    _detectionTimer = Timer.periodic(
      const Duration(milliseconds: 800),
      (_) => _captureAndDetect(),
    );
  }

  Future<void> _captureAndDetect() async {
    if (_isCapturing) return;
    if (_cameraController == null) return;
    if (!(_cameraController!.value.isInitialized)) return;
    if (_cameraController!.value.isTakingPicture) return;
    if (_scanState == _ScanState.holdSteady) return;
    if (_scanState == _ScanState.done) return;
    if (_scanState == _ScanState.initializing) return;
    if (_scanState == _ScanState.warming) return;

    _isCapturing = true;
    try {
      final XFile photo = await _cameraController!.takePicture();
      final file = File(photo.path);
      final fileSize = await file.length();
      if (fileSize < 1000) {
        file.deleteSync();
        return;
      }

      final inputImage = InputImage.fromFilePath(photo.path);
      final faces = await _faceDetector.processImage(inputImage);
      try {
        file.deleteSync();
      } catch (_) {}
      if (!mounted) return;

      final detected = faces.isNotEmpty;
      if (detected && _scanState == _ScanState.waitingForFace) {
        setState(() => _scanState = _ScanState.faceDetected);
        _holdTimer?.cancel();
        _holdTimer = Timer(const Duration(milliseconds: 1500), () {
          if (!mounted) return;
          if (_scanState == _ScanState.faceDetected) {
            _detectionTimer?.cancel();
            setState(() => _scanState = _ScanState.holdSteady);
            _progressController.forward();
          }
        });
      } else if (!detected && _scanState == _ScanState.faceDetected) {
        _holdTimer?.cancel();
        setState(() => _scanState = _ScanState.waitingForFace);
      }
    } catch (_) {
      // silently ignore
    } finally {
      _isCapturing = false;
    }
  }

  Future<void> _retry() async {
    _holdTimer?.cancel();
    _detectionTimer?.cancel();
    _progressController.reset();
    setState(() {
      _scanState = _ScanState.waitingForFace;
      _capturedImageBytes = null;
      _uploadError = null;
    });
    _startDetectionLoop();
  }

  // ── Supabase upload + insert ───────────────────────────────────────────────
  Future<void> _submitAndGoHome() async {
    setState(() {
      _isUploading = true;
      _uploadError = null;
    });

    try {
      final supabase = Supabase.instance.client;
      final uid = supabase.auth.currentUser?.id;
      if (uid == null) throw 'Not logged in';

      const bucket = 'verification-assets';

      // ── 1. Upload ID front ────────────────────────────────────────────
      String? idFrontPath;
      if (widget.frontImage != null) {
        idFrontPath = '$uid/id-front.jpg';
        await supabase.storage
            .from(bucket)
            .uploadBinary(
              idFrontPath,
              widget.frontImage!,
              fileOptions: const FileOptions(
                contentType: 'image/jpeg',
                upsert: true,
              ),
            );
      }

      // ── 2. Upload ID back ─────────────────────────────────────────────
      String? idBackPath;
      if (widget.backImage != null) {
        idBackPath = '$uid/id-back.jpg';
        await supabase.storage
            .from(bucket)
            .uploadBinary(
              idBackPath,
              widget.backImage!,
              fileOptions: const FileOptions(
                contentType: 'image/jpeg',
                upsert: true,
              ),
            );
      }

      // ── 3. Upload face photo ──────────────────────────────────────────
      String? facePath;
      if (_capturedImageBytes != null) {
        facePath = '$uid/face.jpg';
        await supabase.storage
            .from(bucket)
            .uploadBinary(
              facePath,
              _capturedImageBytes!,
              fileOptions: const FileOptions(
                contentType: 'image/jpeg',
                upsert: true,
              ),
            );
      }

      // ── 4. Insert row into verification_submissions ───────────────────
      await supabase.from('verification_submissions').insert({
        'user_id': uid,
        'selected_id_type': widget.selectedId,
        'id_number': widget.idNumber,
        'first_name': widget.firstName,
        'middle_name': widget.middleName,
        'last_name': widget.lastName,
        'suffix': widget.suffix,
        'gender': widget.gender,
        'birthdate': widget.birthdate,
        'birthplace': widget.birthplace,
        'civil_status': widget.civilStatus,
        'contact_number': widget.contactNumber,
        'barangay': widget.barangay,
        'street': widget.street,
        'id_front_path': idFrontPath,
        'id_back_path': idBackPath,
        'face_photo_path': facePath,
        'status': 'pending',
      });

      // After successful submission
      await NotificationService.add(
        AppNotification(
          icon: Icons.hourglass_top_rounded,
          title: "Verification Submitted",
          subtitle:
              "Your ID is being reviewed by our team. We'll notify you once approved.",
          time: DateTime.now(),
          color: Colors.orange,
          type: 'verification_submitted',
        ),
      );

      if (!mounted) return;

      // ── 5. Show success popup then redirect ───────────────────────────
      setState(() => _isUploading = false);
      _showSuccessDialog();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploading = false;
          // Show the real error so we can diagnose it
          _uploadError = e.toString();
        });
      }
    }
  }

  // ── Success dialog with countdown ─────────────────────────────────────────
  void _showSuccessDialog() {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (_, _, _) => _SuccessDialog(
        onDone: () {
          Navigator.of(context).pushAndRemoveUntil(
            PageRouteBuilder(
              transitionDuration: const Duration(milliseconds: 400),
              pageBuilder: (_, _, _) =>
                  NetworkWrapper(child: HomePage(username: widget.username)),
              transitionsBuilder: (_, anim, _, child) => FadeTransition(
                opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
                child: child,
              ),
            ),
            (route) => false,
          );
        },
      ),
      transitionBuilder: (_, anim, _, child) => ScaleTransition(
        scale: Tween(
          begin: 0.75,
          end: 1.0,
        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutBack)),
        child: FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: child,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _borderController.dispose();
    _progressController.dispose();
    _holdTimer?.cancel();
    _detectionTimer?.cancel();
    _warmupTimer?.cancel();
    _faceDetector.close();
    _cameraController?.dispose();
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
    );
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  Color get _ovalColor {
    switch (_scanState) {
      case _ScanState.initializing:
      case _ScanState.warming:
      case _ScanState.waitingForFace:
        return AppColors.grey;
      case _ScanState.faceDetected:
        return AppColors.orange;
      case _ScanState.holdSteady:
      case _ScanState.done:
        return AppColors.green;
    }
  }

  String get _statusText {
    switch (_scanState) {
      case _ScanState.initializing:
        return "Starting Camera...";
      case _ScanState.warming:
        return "Preparing...";
      case _ScanState.waitingForFace:
        return "No Face Detected";
      case _ScanState.faceDetected:
        return "Get Closer";
      case _ScanState.holdSteady:
        return "Hold Steady";
      case _ScanState.done:
        return "Scan Complete";
    }
  }

  String get _instructionText {
    switch (_scanState) {
      case _ScanState.initializing:
      case _ScanState.warming:
        return "Please wait...";
      case _ScanState.waitingForFace:
        return "Position your face inside the oval";
      case _ScanState.faceDetected:
        return "Face detected — hold still";
      case _ScanState.holdSteady:
        return "Stay still while we scan";
      case _ScanState.done:
        return "Verification complete";
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    final size = MediaQuery.of(context).size;
    final ovalW = size.width * 0.62;
    final ovalH = ovalW * 1.36;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: Colors.white),

          // ── Camera preview / frozen still ─────────────────────────────
          if (_cameraReady && _cameraController != null)
            Center(
              child: SizedBox(
                width: ovalW,
                height: ovalH,
                child: ClipPath(
                  clipper: _OvalPathClipper(),
                  child:
                      (_capturedImageBytes != null &&
                          _scanState == _ScanState.done)
                      ? Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..scaleByDouble(-1.0, 1.0, 1.0, 1.0),
                          child: Image.memory(
                            _capturedImageBytes!,
                            fit: BoxFit.cover,
                            width: ovalW,
                            height: ovalH,
                          ),
                        )
                      : CameraPreview(_cameraController!),
                ),
              ),
            ),

          // ── White overlay outside oval ────────────────────────────────
          _OvalCutoutOverlay(ovalW: ovalW, ovalH: ovalH),

          // ── Oval border + progress arc ────────────────────────────────
          Center(
            child: AnimatedBuilder(
              animation: Listenable.merge([_borderAnim, _progressController]),
              builder: (_, _) => CustomPaint(
                size: Size(ovalW, ovalH),
                painter: _OvalBorderPainter(
                  color: _ovalColor,
                  strokeWidth: _borderAnim.value,
                  progress: _scanState == _ScanState.holdSteady
                      ? _progressController.value
                      : _scanState == _ScanState.done
                      ? 1.0
                      : 0.0,
                  showProgress:
                      _scanState == _ScanState.holdSteady ||
                      _scanState == _ScanState.done,
                ),
              ),
            ),
          ),

          // ── Corner brackets ───────────────────────────────────────────
          Center(
            child: SizedBox(
              width: ovalW + 32,
              height: ovalH + 32,
              child: CustomPaint(
                painter: _CornerBracketPainter(
                  color: _ovalColor.withValues(alpha: 0.45),
                ),
              ),
            ),
          ),

          // ── Status text ───────────────────────────────────────────────
          Positioned(
            top: size.height * 0.12,
            left: 0,
            right: 0,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              child: Text(
                _statusText,
                key: ValueKey(_statusText),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _ovalColor,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),

          // ── Bottom area ───────────────────────────────────────────────
          Positioned(
            bottom: size.height * 0.06,
            left: 24,
            right: 24,
            child: _scanState == _ScanState.done
                ? _buildResultButtons()
                : _buildScanningFooter(),
          ),

          // ── Spinner (initializing / warming) ──────────────────────────
          if (_scanState == _ScanState.initializing ||
              _scanState == _ScanState.warming)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    color: AppColors.primaryBlue,
                    strokeWidth: 2.5,
                  ),
                  SizedBox(height: 14),
                  Text(
                    "Starting camera...",
                    style: TextStyle(fontSize: 13, color: AppColors.hint),
                  ),
                ],
              ),
            ),

          // ── Upload loading overlay ────────────────────────────────────
          if (_isUploading)
            Container(
              color: Colors.black.withValues(alpha: 0.45),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                    SizedBox(height: 16),
                    Text(
                      "Hang tight, we're saving your info...",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Top bar ───────────────────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppColors.primaryBlue.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.primaryBlue.withValues(alpha: 0.20),
                        ),
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: AppColors.primaryBlue,
                        size: 16,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Image.asset(
                    "assets/images/applogocrop.png",
                    height: 36,
                    fit: BoxFit.contain,
                  ),
                  const Spacer(),
                  const SizedBox(width: 38),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanningFooter() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: Text(
          _instructionText,
          key: ValueKey(_scanState),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.hint,
            height: 1.5,
          ),
        ),
      ),
      const SizedBox(height: 20),
      if (_scanState != _ScanState.initializing &&
          _scanState != _ScanState.warming)
        _ScanningDots(color: _ovalColor),
    ],
  );

  Widget _buildResultButtons() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text(
        "Your face has been scanned successfully.",
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: AppColors.hint, height: 1.5),
      ),

      // ── Error message ─────────────────────────────────────────────────
      if (_uploadError != null) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.red.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
          ),
          child: Text(
            _uploadError!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.red,
              height: 1.4,
            ),
          ),
        ),
      ],

      const SizedBox(height: 24),

      // ── Go to Home → triggers upload then navigate ────────────────────
      _AnimatedButton(
        label: "Go to Home",
        color: AppColors.green,
        onPressed: _isUploading ? () {} : _submitAndGoHome,
      ),
      const SizedBox(height: 12),
      _OutlineButton(
        label: "Retry",
        color: AppColors.primaryBlue,
        onPressed: _isUploading ? () {} : _retry,
      ),
    ],
  );
}

// ── Success dialog with auto-countdown ───────────────────────────────────────
class _SuccessDialog extends StatefulWidget {
  final VoidCallback onDone;
  const _SuccessDialog({required this.onDone});

  @override
  State<_SuccessDialog> createState() => _SuccessDialogState();
}

class _SuccessDialogState extends State<_SuccessDialog> {
  int _countdown = 5;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_countdown == 1) {
        _timer?.cancel();
        Navigator.of(context).pop();
        widget.onDone();
      } else {
        setState(() => _countdown--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
    child: Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 32),
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Checkmark circle ─────────────────────────────────────
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.green.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                color: AppColors.green,
                size: 40,
              ),
            ),
            const SizedBox(height: 18),

            // ── Title ────────────────────────────────────────────────
            const Text(
              "You're All Set!",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.primaryBlue,
              ),
            ),
            const SizedBox(height: 10),

            // ── Body ─────────────────────────────────────────────────
            const Text(
              "Your information has been recorded and is now under review by our admin team.\n\nYou will receive a notification within 3 business days once your verification is complete.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.hint,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 24),

            // ── Countdown ring ───────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  "Redirecting in  ",
                  style: TextStyle(fontSize: 12, color: AppColors.hint),
                ),
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.primaryBlue.withValues(alpha: 0.35),
                      width: 1.5,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$_countdown',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryBlue,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}

class _OvalPathClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) =>
      Path()..addOval(Rect.fromLTWH(0, 0, size.width, size.height));

  @override
  bool shouldReclip(_OvalPathClipper old) => false;
}

// ── White cutout overlay ──────────────────────────────────────────────────────
class _OvalCutoutOverlay extends StatelessWidget {
  final double ovalW;
  final double ovalH;
  const _OvalCutoutOverlay({required this.ovalW, required this.ovalH});

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _CutoutPainter(ovalW: ovalW, ovalH: ovalH),
    child: const SizedBox.expand(),
  );
}

class _CutoutPainter extends CustomPainter {
  final double ovalW;
  final double ovalH;
  _CutoutPainter({required this.ovalW, required this.ovalH});

  @override
  void paint(Canvas canvas, Size size) {
    final full = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final oval = Path()
      ..addOval(
        Rect.fromCenter(
          center: Offset(size.width / 2, size.height / 2),
          width: ovalW,
          height: ovalH,
        ),
      );
    canvas.drawPath(
      Path.combine(PathOperation.difference, full, oval),
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_CutoutPainter old) =>
      old.ovalW != ovalW || old.ovalH != ovalH;
}

// ── Oval border + progress arc ────────────────────────────────────────────────
class _OvalBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double progress;
  final bool showProgress;

  _OvalBorderPainter({
    required this.color,
    required this.strokeWidth,
    required this.progress,
    required this.showProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawOval(
      rect,
      Paint()
        ..color = color.withValues(alpha: 0.28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );
    if (showProgress && progress > 0) {
      canvas.drawArc(
        rect,
        -1.5708,
        2 * 3.14159 * progress,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth + 2.0
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_OvalBorderPainter old) =>
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.progress != progress;
}

// ── Corner brackets ───────────────────────────────────────────────────────────
class _CornerBracketPainter extends CustomPainter {
  final Color color;
  _CornerBracketPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const len = 20.0;
    final w = size.width;
    final h = size.height;
    canvas.drawLine(Offset(0, len), Offset.zero, p);
    canvas.drawLine(Offset.zero, Offset(len, 0), p);
    canvas.drawLine(Offset(w - len, 0), Offset(w, 0), p);
    canvas.drawLine(Offset(w, 0), Offset(w, len), p);
    canvas.drawLine(Offset(0, h - len), Offset(0, h), p);
    canvas.drawLine(Offset(0, h), Offset(len, h), p);
    canvas.drawLine(Offset(w - len, h), Offset(w, h), p);
    canvas.drawLine(Offset(w, h), Offset(w, h - len), p);
  }

  @override
  bool shouldRepaint(_CornerBracketPainter old) => old.color != color;
}

// ── Scanning dots ─────────────────────────────────────────────────────────────
class _ScanningDots extends StatefulWidget {
  final Color color;
  const _ScanningDots({required this.color});

  @override
  State<_ScanningDots> createState() => _ScanningDotsState();
}

class _ScanningDotsState extends State<_ScanningDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _ctrl,
    builder: (_, _) => Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (i) {
        final delay = i / 3;
        final val = ((_ctrl.value - delay) % 1.0).clamp(0.0, 1.0);
        final opacity = val < 0.5 ? val * 2 : (1.0 - val) * 2;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: 0.3 + opacity * 0.7),
            shape: BoxShape.circle,
          ),
        );
      }),
    ),
  );
}

// ── Animated filled button ────────────────────────────────────────────────────
class _AnimatedButton extends StatefulWidget {
  final String label;
  final Color color;
  final VoidCallback onPressed;
  const _AnimatedButton({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  State<_AnimatedButton> createState() => _AnimatedButtonState();
}

class _AnimatedButtonState extends State<_AnimatedButton> {
  bool _p = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown: (_) => setState(() => _p = true),
    onTapUp: (_) {
      setState(() => _p = false);
      widget.onPressed();
    },
    onTapCancel: () => setState(() => _p = false),
    child: AnimatedScale(
      scale: _p ? 0.94 : 1.0,
      duration: const Duration(milliseconds: 110),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 110),
        height: 50,
        width: double.infinity,
        decoration: BoxDecoration(
          color: _p ? widget.color.withValues(alpha: 0.80) : widget.color,
          borderRadius: BorderRadius.circular(25),
          boxShadow: _p
              ? []
              : [
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.28),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        alignment: Alignment.center,
        child: Text(
          widget.label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
    ),
  );
}

// ── Animated outline button ───────────────────────────────────────────────────
class _OutlineButton extends StatefulWidget {
  final String label;
  final Color color;
  final VoidCallback onPressed;
  const _OutlineButton({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  State<_OutlineButton> createState() => _OutlineButtonState();
}

class _OutlineButtonState extends State<_OutlineButton> {
  bool _p = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown: (_) => setState(() => _p = true),
    onTapUp: (_) {
      setState(() => _p = false);
      widget.onPressed();
    },
    onTapCancel: () => setState(() => _p = false),
    child: AnimatedScale(
      scale: _p ? 0.94 : 1.0,
      duration: const Duration(milliseconds: 110),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 110),
        height: 50,
        width: double.infinity,
        decoration: BoxDecoration(
          color: _p ? widget.color.withValues(alpha: 0.07) : Colors.white,
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: widget.color, width: 1.5),
        ),
        alignment: Alignment.center,
        child: Text(
          widget.label,
          style: TextStyle(
            color: widget.color,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
    ),
  );
}
