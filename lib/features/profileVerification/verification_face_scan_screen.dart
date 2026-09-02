import 'dart:async';
import 'dart:io';
import '../../core/network/network_wrapper.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:dotted_border/dotted_border.dart';
import '../../core/widgets/Home/Account/account_web_kit.dart';
import '../../core/theme/citizen_ui.dart';
import '../../core/widgets/app_dialog.dart' show kWebDialogMaxWidth;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/providers/user_profile_provider.dart';
import '../../core/router/legacy_nav.dart';
import '../../core/services/id_check_service.dart';
import '../../core/services/image_compressor.dart';
import '../../core/services/selfie_quality.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_back_chevron.dart';
import '../home/screen/home_screen.dart';
import '../home/screen/notification_popup.dart';
// CitizenTab.home.path — the shell's Home location, for the web arm of the
// success handler. Web-only in effect; the import itself is inert off web.
import '../home/shell/citizen_shell_router.dart' show CitizenTab;
import '../../core/theme/mobile_metrics.dart';

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

  /// What the automated check concluded about the two ID captures.
  ///
  /// Threaded from the scan/upload screen through three route hops to be
  /// stored with the submission. Null when nothing checked the ID — the mobile
  /// camera path uses ML Kit rather than the Edge Function, and a checker
  /// outage produces nothing — and a null is written as NULL, which the
  /// console renders as "not checked" rather than inventing a verdict.
  final IdSubmissionCheck? idCheck;

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
    this.idCheck,
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

  // ── WEB camera path ─────────────────────────────────────────────────────
  // On a phone or tablet browser the camera IS the natural way to take a
  // selfie, so web gets a live preview and a shutter. What it does not get is
  // detection: the oval never fills, nothing says "Hold Steady", and no frame
  // is auto-captured, because all of that is ML Kit and ML Kit has no web
  // implementation. The oval is a FRAMING GUIDE here, not a detector, and the
  // copy is written so it never claims otherwise.
  //
  // Nothing is lost against the file-picker path this replaces: that had no
  // automated check either, and every submission is reviewed by a person.
  bool _webUsesCamera = false;
  bool _webCamStarted = false;
  bool _webCamFailed = false;

  // ── Captured still frame ──────────────────────────────────────────────────
  Uint8List? _capturedImageBytes;

  // ── Upload state ──────────────────────────────────────────────────────────
  bool _isUploading = false;
  String? _uploadError;

  // ── Face detection ────────────────────────────────────────────────────────
  // `late` so the detector is built on FIRST USE rather than when the State is
  // created. On web nothing ever touches it — there is no detection loop — so
  // ML Kit, which has no web implementation, is never instantiated. On mobile
  // the first access is inside _captureAndDetect, before any detection runs,
  // with exactly the options below.
  late final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast,
      enableContours: false,
      enableLandmarks: false,
      // Turned ON so the quality gate can see whether the eyes were open at
      // the moment of capture — the one selfie fault a person genuinely does
      // not notice themselves. Classification is the cheap ML Kit extra
      // (contours and landmarks are the expensive ones, and both stay off),
      // and the detection LOOP ignores it: only the final capture is graded.
      enableClassification: true,
      enableTracking: false,
      minFaceSize: 0.05,
    ),
  );

  /// What the quality gate said about the captured selfie, if anything.
  ///
  /// Null until a still has been graded. Drives the retake prompt; the photo
  /// is kept either way, because the gate ADVISES the citizen rather than
  /// discarding their capture behind their back.
  SelfieCheckResult? _selfieCheck;

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
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _initAnimations();
    // WEB: no camera scan exists. `camera` and ML Kit face detection have no
    // web implementation, so no CameraController is ever constructed here —
    // the user picks a selfie file instead (see [_pickSelfieForWeb]) and the
    // state sits at waitingForFace until they do.
    if (kIsWeb) {
      _scanState = _ScanState.waitingForFace;
    } else {
      _initCamera();
    }
  }

  /// Picks the web capture method once, the first time a [MediaQuery] exists.
  ///
  /// Not [initState]: MediaQuery cannot be read there. Not [build] either -
  /// starting a camera is a side effect and build must stay pure.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!kIsWeb || _webCamStarted) return;
    _webCamStarted = true;
    _webUsesCamera =
        MediaQuery.of(context).size.width <= kVerificationCameraMaxWidth;
    if (_webUsesCamera) _initWebCamera();
  }

  /// Starts a plain preview — no image stream, no detector, no timers.
  ///
  /// Prefers the FRONT camera: this is a selfie. Failure is a state rather
  /// than an exception, because the footer has to be able to offer the file
  /// picker instead of leaving the user looking at an empty oval.
  Future<void> _initWebCamera() async {
    CameraController? controller;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw 'no cameras';
      final cam = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      controller = CameraController(
        cam,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _cameraController = controller;
        _cameraReady = true;
        _scanState = _ScanState.waitingForFace;
      });
    } catch (e) {
      debugPrint('[FACE/WEB] camera unavailable: $e');
      // A controller whose initialize() threw can still be holding a live
      // getUserMedia stream, and this screen then falls back to the file
      // picker and never touches it again. Without this the browser keeps
      // reporting the camera as in use for the rest of the session - and the
      // ID scan screen, which wants the same device, finds it busy.
      if (controller != null) {
        try {
          await controller.dispose();
        } catch (e) {
          debugPrint('[FACE/WEB] dispose after failed init: $e');
        }
      }
      if (!mounted) return;
      setState(() {
        _webUsesCamera = false;
        _webCamFailed = true;
      });
    }
  }

  /// MOBILE only: runs ML Kit over the captured still and normalises the
  /// result for [SelfieQuality].
  ///
  /// ML Kit reports bounding boxes in IMAGE PIXELS; the gate's thresholds are
  /// fractions of the frame, so one set of numbers works at any resolution.
  /// Dividing here is what makes "the face fills at least 18% of the height"
  /// mean the same thing on a 12MP phone and a 2MP one.
  ///
  /// Returns an empty list on any failure, which the caller treats as "no face
  /// found" — correct on mobile, where the detector genuinely did look.
  Future<List<FaceBox>> _detectFacesForGrading(String path) async {
    try {
      final input = InputImage.fromFilePath(path);
      final faces = await _faceDetector.processImage(input);
      if (faces.isEmpty) return const [];

      final decoded = await decodeImageFromList(
        await File(path).readAsBytes(),
      );
      final w = decoded.width.toDouble();
      final h = decoded.height.toDouble();
      if (w <= 0 || h <= 0) return const [];

      return [
        for (final f in faces)
          FaceBox(
            left: f.boundingBox.left / w,
            top: f.boundingBox.top / h,
            width: f.boundingBox.width / w,
            height: f.boundingBox.height / h,
            // Null when classification produced nothing — the gate treats a
            // missing signal as "not a problem", never as closed eyes.
            eyeOpenProbability:
                (f.leftEyeOpenProbability != null &&
                    f.rightEyeOpenProbability != null)
                // BOTH eyes: the lower of the two, because one closed eye is
                // still a blink in the photo the reviewer has to work with.
                ? (f.leftEyeOpenProbability! < f.rightEyeOpenProbability!
                      ? f.leftEyeOpenProbability!
                      : f.rightEyeOpenProbability!)
                : null,
            yawDegrees: f.headEulerAngleY,
            rollDegrees: f.headEulerAngleZ,
          ),
      ];
    } catch (e) {
      debugPrint('[FACE] grading detection failed: $e');
      return const [];
    }
  }

  /// Grades a captured selfie and stores the result in [_selfieCheck].
  ///
  /// ── What runs where ──────────────────────────────────────────────────────
  /// MOBILE gets the full check: ML Kit locates the face, and the image itself
  /// supplies sharpness and brightness.
  ///
  /// WEB has no ML Kit, so there is no face box — and rather than guess, the
  /// face-shaped checks are simply ABSENT. What web can still measure is the
  /// image: a black frame or a motion-blurred one is catchable without knowing
  /// where the face is, and those are two of the most common unusable selfies.
  /// Passing an empty `faces` list would report "no face" on every web capture,
  /// which is why this returns [SelfieCheckResult.notChecked] when there is
  /// nothing face-shaped to judge and no image fault either.
  ///
  /// NEVER throws and never blocks: a capture that could not be examined
  /// passes. Refusing a citizen because the app's own detector failed is the
  /// worse error.
  Future<void> _gradeSelfie(Uint8List bytes, {required List<FaceBox> faces}) async {
    try {
      final m = SelfieQuality.measure(bytes);

      // Web: no detector, so only the image-quality bands can speak. With no
      // faces to judge, an empty list would mean "no face found" — a different
      // claim entirely — so the face bands are skipped by handing the gate a
      // single synthetic well-framed box. Its geometry can never fail, leaving
      // brightness and sharpness as the only possible issues.
      final effectiveFaces = faces.isEmpty && kIsWeb
          ? const [
              FaceBox(left: 0.3, top: 0.24, width: 0.4, height: 0.5),
            ]
          : faces;

      final result = SelfieQuality.check(
        faces: effectiveFaces,
        sharpness: m.sharpness,
        brightness: m.brightness,
      );
      if (mounted) setState(() => _selfieCheck = result);
    } catch (e) {
      debugPrint('[FACE] quality check failed: $e');
      if (mounted) setState(() => _selfieCheck = SelfieCheckResult.notChecked);
    }
  }

  /// The web shutter. Manual, because nothing here is watching for a face.
  Future<void> _webCapture() async {
    final controller = _cameraController;
    if (controller == null || _isCapturing) return;
    setState(() => _isCapturing = true);
    try {
      final shot = await controller.takePicture();
      final bytes = await shot.readAsBytes();
      if (!mounted) return;
      setState(() {
        _capturedImageBytes = bytes;
        _uploadError = null;
        _scanState = _ScanState.done;
      });
      await _gradeSelfie(bytes, faces: const []);
    } catch (e) {
      debugPrint('[FACE/WEB] capture failed: $e');
      if (!mounted) return;
      setState(
        () => _uploadError =
            "Couldn't take that photo. Try again, or upload a file instead.",
      );
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  /// WEB selfie path — file picker instead of the live face scan.
  ///
  /// Produces exactly what the mobile capture produces: [_capturedImageBytes]
  /// as a [Uint8List], and `_scanState = done`. Everything after this point —
  /// the oval preview, the Go to Home button, and [_submitAndGoHome]'s upload
  /// and insert — is the shared path and is untouched.
  ///
  /// There is deliberately NO automated face check here: ML Kit cannot run on
  /// web. The selfie is attached for human review by an admin instead, which is
  /// the same queue every submission already goes through.
  Future<void> _pickSelfieForWeb() async {
    try {
      final shot = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (shot == null) return;
      final bytes = await shot.readAsBytes();
      if (!mounted) return;
      setState(() {
        _capturedImageBytes = bytes;
        _uploadError = null;
        _scanState = _ScanState.done;
      });
      await _gradeSelfie(bytes, faces: const []);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _uploadError =
            "Couldn't read that image. Please choose another file.",
      );
    }
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

          // Graded on THIS frame, before the file is deleted — the detection
          // loop only ever answered "is a face there", and the still actually
          // submitted can differ from the frame that satisfied the loop (the
          // user relaxes, blinks, or lowers the phone during the hold). The
          // photo the reviewer receives is the one worth judging.
          final faces = await _detectFacesForGrading(photo.path);

          try {
            File(photo.path).deleteSync();
          } catch (_) {}
          if (mounted) {
            setState(() {
              _capturedImageBytes = bytes;
              _scanState = _ScanState.done;
            });
            await _gradeSelfie(bytes, faces: faces);
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
    // WEB: no detection loop to restart, and no timers or progress controller
    // in play. With a live preview "Retry" just drops the still and lets the
    // camera show through again; with the file picker it reopens the picker.
    if (kIsWeb) {
      setState(() {
        _capturedImageBytes = null;
        _selfieCheck = null;
        _uploadError = null;
        _scanState = _ScanState.waitingForFace;
      });
      if (!_webUsesCamera) await _pickSelfieForWeb();
      return;
    }

    _holdTimer?.cancel();
    _detectionTimer?.cancel();
    _progressController.reset();
    setState(() {
      _scanState = _ScanState.waitingForFace;
      _capturedImageBytes = null;
      _selfieCheck = null;
      _uploadError = null;
    });
    _startDetectionLoop();
  }

  Future<void> _submitAndGoHome() async {
    setState(() {
      _isUploading = true;
      _uploadError = null;
    });

    try {
      final supabase = Supabase.instance.client;
      final uid = supabase.auth.currentUser?.id;
      if (uid == null) throw 'Not logged in';

      // ── STEP 3 PRE-CHECK — fail fast before wasting bandwidth ─────────
      final pendingCheck = await supabase
          .from('verification_submissions')
          .select('id, status')
          .eq('user_id', uid)
          .or('status.eq.pending,status.eq.approved')
          .maybeSingle();

      if (pendingCheck != null) {
        final status = pendingCheck['status'] as String;
        throw status == 'approved'
            ? 'You are already verified.'
            : 'You already have a pending verification. Please wait for our team to review it.';
      }
      // ── END PRE-CHECK ─────────────────────────────────────────────────

      const bucket = 'verification-assets';

      // These three are capped at the `identity` tier — 2000px and quality 88,
      // markedly more generous than evidence. A reviewer has to read the small
      // print on a licence and match a face against it, so the saving here
      // comes from capping a 12 MP original, not from squeezing the encoder.
      // The output is always JPEG, so the `.jpg` paths and the `image/jpeg`
      // content-types below stay truthful.
      //
      // Neither the ID frames nor the face capture ever passed through a
      // picker option: the ID screens crop their own frames and the face
      // screen takes a CameraController still, so this is the only place the
      // size of an identity photo is decided.

      // ── 1. Upload ID front ────────────────────────────────────────────
      String? idFrontPath;
      if (widget.frontImage != null) {
        final front = await ImageCompressor.compressBytes(
          widget.frontImage!,
          purpose: ImagePurpose.identity,
        );
        idFrontPath = '$uid/id-front.jpg';
        await supabase.storage
            .from(bucket)
            .uploadBinary(
              idFrontPath,
              front.bytes,
              fileOptions: const FileOptions(
                contentType: 'image/jpeg',
                upsert: true,
              ),
            );
      }

      // ── 2. Upload ID back ─────────────────────────────────────────────
      String? idBackPath;
      if (widget.backImage != null) {
        final back = await ImageCompressor.compressBytes(
          widget.backImage!,
          purpose: ImagePurpose.identity,
        );
        idBackPath = '$uid/id-back.jpg';
        await supabase.storage
            .from(bucket)
            .uploadBinary(
              idBackPath,
              back.bytes,
              fileOptions: const FileOptions(
                contentType: 'image/jpeg',
                upsert: true,
              ),
            );
      }

      // ── 3. Upload face photo ──────────────────────────────────────────
      String? facePath;
      if (_capturedImageBytes != null) {
        final face = await ImageCompressor.compressBytes(
          _capturedImageBytes!,
          purpose: ImagePurpose.identity,
        );
        facePath = '$uid/face.jpg';
        await supabase.storage
            .from(bucket)
            .uploadBinary(
              facePath,
              face.bytes,
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
        // What the automated check concluded, so the REVIEWER can see it.
        // Without this the scoring was computed, used to decide whether to let
        // the citizen continue, and then discarded — a submission flagged
        // `review` looked identical in the console to one that scored 95.
        // Spread, not null-assigned: an unchecked submission leaves these
        // columns NULL, which the console renders honestly as "not checked".
        ...?widget.idCheck?.toSubmissionColumns(),
      });

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

      setState(() => _isUploading = false);
      _showSuccessDialog();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadError = _friendlyError(e); // ← STEP 2 CHANGE
        });
      }
    }
  }

  // ── STEP 2 HELPER — add this anywhere inside _VerificationFaceScanScreenState ──
  String _friendlyError(Object e) {
    final msg = e.toString();
    if (msg.contains('already verified')) {
      return 'You are already verified. No need to resubmit.';
    }
    if (msg.contains('pending verification') ||
        msg.contains('already have a pending')) {
      return 'You already have a pending verification. Please wait for our team to review it.';
    }
    if (msg.contains('daily limit') || msg.contains('rate_limit')) {
      return 'You\'ve reached the daily limit for verification attempts. Please try again tomorrow.';
    }
    if (msg.contains('row-level security')) {
      return 'You don\'t have permission to submit. Please contact support.';
    }
    if (msg.contains('storage')) {
      return 'Could not upload your photos. Check your internet connection and try again.';
    }
    return 'Something went wrong. Please try again or contact support.';
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
          // ── Web: land on the SHELL, clearing the wizard first ─────────────
          //
          // The mobile arm below pushes HomePage with pushAndRemoveUntil and a
          // `(route) => false` predicate. On web that empties the Navigator of
          // go_router's OWN pages, leaving the match list describing pages that
          // no longer exist — and it mounts HomePage, the legacy MOBILE
          // surface, on a browser. This was the live defect.
          //
          // The clear is mandatory, not cosmetic. By this point the wizard has
          // stacked nine pageless routes — eight pushLegacy steps plus this
          // dialog — so a bare context.go would fire over all of them and
          // desync exactly the way the reset-password chain used to. Popping to
          // the topmost go_router page first makes the stack match the match
          // list before it changes. goClearingPageless captures the navigator
          // and router BEFORE popping, which matters here: this screen is one
          // of the routes being popped.
          //
          // The wizard steps hold no browser history of their own (pageless
          // routes get none), so Back after this lands on whatever shell
          // location they left, never on a half-completed face scan.
          if (kIsWeb) {
            // The submission just moved them to `pending`, but nothing in this
            // flow refreshes the profile — so the shell's rail would still read
            // verifStatus.none and offer "Verify now" to someone who just
            // verified, and its re-entry guard would not block a second run.
            // Same idiom the auth flows use (see app_router.dart).
            ProviderScope.containerOf(context).invalidate(userProfileProvider);
            goClearingPageless(context, CitizenTab.home.path);
            return;
          }
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
    // Guarded so web never touches the lazy `late` field — reading it just to
    // close it would construct the ML Kit detector that web must never build.
    if (!kIsWeb) _faceDetector.close();
    _cameraController?.dispose();
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
    );
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
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

  // ==========================================================================
  //  WEB SCAFFOLD
  // ==========================================================================
  //
  // This was the ONE step of the eight-screen wizard that rendered its PHONE
  // layout on a desktop browser: a full-bleed white Stack with a ~700px oval
  // floating in a 1920px viewport, a status line pinned at 12% of the window
  // height and a footer at 6%, with nothing anchoring either. Every sibling
  // step - id_selection, photo_instruction, upload_id, review, identity -
  // already renders through [AccountPageBody] with a title, a stepper and
  // cards; arriving here dropped all of it, which is why the page read as
  // broken rather than merely plain. It is also why the "Selfie Added" state
  // looked empty: the picked image was drawn INSIDE the oval clip, so on a
  // desktop the visible result was a bare green outline.
  //
  // The oval survives, because it is still the right framing guide for a
  // selfie. It is just no longer the whole page - it lives in a card, at a
  // size the card gives it.
  //
  // Nothing below runs off the web: [build] returns this only under `kIsWeb`,
  // which is a compile-time false on mobile, so the phone's camera Stack is
  // byte-identical to what it was.
  Widget _buildWebScaffold() {
    return Scaffold(
      backgroundColor: CitizenUi.pageBg,
      body: SafeArea(
        child: AccountPageBody(
          builder: (context, stack) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AccountPageTitle(
                title: 'Add a selfie',
                // "so we can match it" read as a promise of automatic face
                // matching. Nothing in the app does that — no face recognition
                // exists anywhere in it, and a REVIEWER makes the comparison.
                // The note lower down this same screen already says so; this
                // makes the two agree.
                subtitle: _webUsesCamera
                    ? 'Take a photo of your face so our team can match it to '
                          'your ID.'
                    : 'Choose a clear photo of your face so our team can match '
                          'it to your ID.',
                onBack: _isUploading ? null : () => Navigator.pop(context),
                backLabel: 'Back to identity verification',
              ),
              const AccountStepper(step: 2, labels: kVerificationSteps),

              const AccountSectionLabel('Your selfie'),
              AccountCard(child: _webSelfieRow(stack)),
              const SizedBox(height: kAccountSectionGap),

              const AccountSectionLabel('Note'),
              AccountCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _WebFaceNote(
                      icon: Icons.lightbulb_outline,
                      text:
                          'Please ensure you are in a well-lit area, facing '
                          'the light.',
                    ),
                    const SizedBox(height: 12),
                    const _WebFaceNote(
                      icon: Icons.visibility_outlined,
                      text:
                          'Look straight ahead with your whole face visible - '
                          'no hats, masks or sunglasses.',
                    ),
                    const SizedBox(height: 12),
                    _WebFaceNote(
                      icon: Icons.verified_user_outlined,
                      // Web has no ML Kit, so nothing on this screen checks the
                      // photo. A person does, and saying so is both honest and
                      // what actually happens.
                      text: _capturedImageBytes == null
                          ? 'Our team checks every selfie against the ID you '
                                'uploaded.'
                          : 'Submitting sends your ID and selfie for review. '
                                'This usually takes a few business days.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: kAccountSectionGap),

              if (_uploadError != null) ...[
                AccountErrorStrip(_uploadError!),
                const SizedBox(height: kAccountSectionGap),
              ],

              // The quality gate ADVISES; it never discards the photo or
              // disables Submit. A citizen who has tried three times in a dim
              // room must still be able to send what they have and let a
              // reviewer decide — blocking them here is how a verification
              // flow silently loses the people it exists to serve.
              if (_selfieCheck != null && !_selfieCheck!.ok) ...[
                _SelfieHintStrip(hint: _selfieCheck!.hint!),
                const SizedBox(height: kAccountSectionGap),
              ],

              // Submit appears only once there is something to submit, so the
              // page never shows a dead primary control. Until then the card's
              // own button is the single call to action.
              if (_capturedImageBytes != null)
                AccountActions(
                  stack: stack,
                  primaryLabel: 'Submit for review',
                  onPrimary: _isUploading ? null : _submitAndGoHome,
                  secondaryLabel: _webUsesCamera
                      ? 'Retake photo'
                      : 'Choose another',
                  onSecondary: _isUploading ? null : _retry,
                  busy: _isUploading,
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// The capture control beside the preview, stacking when there is no room.
  Widget _webSelfieRow(bool stack) {
    final capture = _webCaptureColumn();
    final preview = _webPreview();

    if (stack) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          preview,
          const SizedBox(height: kAccountSectionGap),
          capture,
        ],
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 3, child: capture),
          const SizedBox(width: kAccountSectionGap),
          Expanded(flex: 2, child: preview),
        ],
      ),
    );
  }

  /// The dropzone / shutter, plus a way to reach the OTHER capture method.
  ///
  /// Mirrors [verification_upload_id_screen]'s dropzone on purpose: the two
  /// screens are one step apart and were asking for the same thing in two
  /// completely different visual languages.
  Widget _webCaptureColumn() {
    final done = _capturedImageBytes != null;
    final accent = done ? AppColors.green : CitizenUi.accent;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(CitizenUi.controlRadius),
          child: InkWell(
            onTap: _isUploading
                ? null
                : (_webUsesCamera
                      ? (_cameraReady && !_isCapturing ? _webCapture : null)
                      : _pickSelfieForWeb),
            borderRadius: BorderRadius.circular(CitizenUi.controlRadius),
            child: DottedBorder(
              color: accent,
              strokeWidth: 1.4,
              dashPattern: const [8, 5],
              borderType: BorderType.RRect,
              radius: Radius.circular(CitizenUi.controlRadius),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 34),
                decoration: BoxDecoration(
                  color: done
                      ? AppColors.green.withValues(alpha: 0.06)
                      : CitizenUi.accentWash,
                  borderRadius: BorderRadius.circular(CitizenUi.controlRadius),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: accent,
                      child: Icon(
                        done
                            ? Icons.check_rounded
                            : (_webUsesCamera
                                  ? Icons.camera_alt_outlined
                                  : Icons.upload_file_outlined),
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      done
                          ? 'Selfie added'
                          : (_webUsesCamera
                                ? (_isCapturing ? 'Taking photo...' : 'Take photo')
                                : 'Choose a selfie'),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      done
                          ? 'Submit below, or pick a different photo'
                          : (_webCamFailed
                                ? "We couldn't open your camera - upload a "
                                      'photo instead'
                                : (_webUsesCamera
                                      ? 'Centre your face in the oval, then '
                                            'take the photo'
                                      : 'Pick a clear photo of your face from '
                                            'your computer')),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        color: CitizenUi.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Whichever method the window picked, the other stays one click away.
        // The width test is a guess about hardware - a narrow desktop window
        // has no usable camera, a tablet can have it blocked - so it decides
        // the DEFAULT and never the only way through.
        const SizedBox(height: 10),
        TextButton(
          onPressed: _isUploading
              ? null
              : (_webUsesCamera ? _pickSelfieForWeb : _webEnableCamera),
          style: TextButton.styleFrom(
            foregroundColor: CitizenUi.textSecondary,
            textStyle: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: Text(
            _webUsesCamera ? 'Upload a file instead' : 'Use my camera instead',
          ),
        ),
      ],
    );
  }

  /// Switches a desktop-width browser over to the live camera on request.
  ///
  /// The width test only chooses a default, so a laptop webcam has to stay
  /// reachable. [_webCamFailed] is cleared so a second attempt is not
  /// pre-judged by the first - the user may have just granted the permission
  /// they denied, or closed the tab that held the device.
  Future<void> _webEnableCamera() async {
    setState(() {
      _webUsesCamera = true;
      _webCamFailed = false;
      _uploadError = null;
    });
    await _initWebCamera();
  }

  /// The live preview, cover-fitted into a [w] x [h] box without distortion.
  ///
  /// A bare `CameraPreview` here was stretched. Both callers put it inside a
  /// tight `SizedBox` shaped like the OVAL (1 : 1.36), and a tight constraint
  /// overrides the `AspectRatio` that `CameraPreview` builds internally - the
  /// ratio is not violated so much as ignored, so a 9:16 stream was drawn at
  /// the oval's 0.735 instead of its native 0.562. That is a 31% horizontal
  /// stretch: every face in the framing oval looked wider than it is.
  ///
  /// The frozen still next to it has always used `BoxFit.cover`, so the stretch
  /// also meant the preview and the photo it produced disagreed - the user
  /// framed one face and got another. This gives the preview the same cover
  /// treatment, so the two finally match.
  Widget _coverPreview(double w, double h) {
    final controller = _cameraController!;
    final preview = controller.value.previewSize;
    if (preview == null) return CameraPreview(controller);

    // Web reports the video track's own size, already in the orientation the
    // user is holding. Mobile hands back a landscape sensor buffer that
    // `CameraPreview` transposes for a portrait screen, so match that here.
    final src = kIsWeb
        ? preview
        : Size(preview.height, preview.width);

    return SizedBox(
      width: w,
      height: h,
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: src.width,
          height: src.height,
          child: CameraPreview(controller),
        ),
      ),
    );
  }

  /// The oval, at a size the CARD gives it rather than the viewport.
  ///
  /// Same framing guide the phone shows, kept because it is the right shape
  /// for a selfie - but bounded, so it can no longer grow to 700px tall on a
  /// desktop and push the rest of the page off screen.
  Widget _webPreview() {
    const double previewW = 168;
    const double previewH = previewW * 1.36;
    final bytes = _capturedImageBytes;
    final live = _webUsesCamera && _cameraReady && _cameraController != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: CitizenUi.surface,
            border: Border.all(color: CitizenUi.border),
            borderRadius: BorderRadius.circular(CitizenUi.controlRadius),
          ),
          child: Center(
            child: SizedBox(
              width: previewW,
              height: previewH,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipPath(
                    clipper: _OvalPathClipper(),
                    child: bytes != null
                        // A picked FILE is not mirrored, so it is shown as-is.
                        // A frame from the FRONT camera is, so it is flipped
                        // back - otherwise the still does not match the live
                        // preview the user just framed themselves in.
                        ? (_webUsesCamera
                              ? Transform(
                                  alignment: Alignment.center,
                                  transform: Matrix4.identity()
                                    ..scaleByDouble(-1.0, 1.0, 1.0, 1.0),
                                  child: Image.memory(
                                    bytes,
                                    fit: BoxFit.cover,
                                    width: previewW,
                                    height: previewH,
                                  ),
                                )
                              : Image.memory(
                                  bytes,
                                  fit: BoxFit.cover,
                                  width: previewW,
                                  height: previewH,
                                ))
                        : live
                        ? _coverPreview(previewW, previewH)
                        : Container(color: CitizenUi.pageBg),
                  ),
                  // Painted OVER the clip so the stroke is not eaten by it.
                  IgnorePointer(
                    child: CustomPaint(
                      painter: _OvalBorderPainter(
                        color: bytes != null
                            ? AppColors.green
                            : CitizenUi.border,
                        strokeWidth: 2.0,
                        progress: 0.0,
                        showProgress: false,
                      ),
                    ),
                  ),
                  if (bytes == null && !live)
                    Center(
                      child: Icon(
                        Icons.person_outline,
                        size: 44,
                        color: CitizenUi.textMuted.withValues(alpha: 0.5),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          bytes != null
              ? 'Your selfie'
              : (live ? 'Live preview' : 'Preview appears here'),
          style: const TextStyle(fontSize: 12, color: CitizenUi.textMuted),
        ),
      ],
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return _buildWebScaffold();

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    final size = MediaQuery.of(context).size;

    // Sized off viewport WIDTH, which is right on a phone: narrow and tall.
    // The web clamp that used to live here is gone with the rest of the web
    // arm - web returns [_buildWebScaffold] above and never reaches this.
    final double ovalW = size.width * 0.62;
    final double ovalH = ovalW * 1.36;

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
                      // Un-mirrors the front-camera still so it matches the
                      // preview the user was just looking at.
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
                      : _coverPreview(ovalW, ovalH),
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
                  // Was a 38px blue-tinted CIRCLE with arrow_back_ios_new —
                  // one of four different back chevrons this wizard had. The
                  // Scaffold behind it is white, so the standard light chip
                  // reads here exactly as it does in Settings.
                  const AppBackChevron(),
                  const Spacer(),
                  Image.asset(
                    "assets/images/applogocrop.webp",
                    height: 36,
                    fit: BoxFit.contain,
                  ),
                  const Spacer(),
                  // Mirrors the chevron's width so the logo stays optically
                  // centred. Tracks the chip's own sizing rule rather than the
                  // 38 that matched the old circle.
                  SizedBox(width: uiScaleWidth(context) * 0.09),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanningFooter() {
    return Column(
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
  }

  Widget _buildResultButtons() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text(
        "Your face has been scanned successfully.",
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 13,
          color: AppColors.hint,
          height: 1.5,
        ),
      ),

      // ── Selfie quality advice ─────────────────────────────────────────
      // Advisory only: Submit stays enabled below. See the web arm for why.
      if (_selfieCheck != null && !_selfieCheck!.ok) ...[
        const SizedBox(height: 8),
        _SelfieHintStrip(hint: _selfieCheck!.hint!),
      ],

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
        // WEB: capped for the same reason as every other dialog in this
        // wizard - a margin bounds the gap at the edges, not the box itself,
        // so the success card grew to the width of the monitor.
        constraints: BoxConstraints(
          maxWidth: kIsWeb ? kWebDialogMaxWidth : double.infinity,
        ),
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

/// One bullet in the web "Note" card.
///
/// A local twin of `verification_upload_id_screen`'s `_WebUploadNote`, which is
/// private to that file. Same shape, so the two consecutive wizard steps read
/// as one page.
class _WebFaceNote extends StatelessWidget {
  final IconData icon;
  final String text;
  const _WebFaceNote({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 16, color: CitizenUi.accent),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            height: 1.45,
            color: CitizenUi.textSecondary,
          ),
        ),
      ),
    ],
  );
}

/// One line of advice about the selfie just captured.
///
/// Deliberately AMBER, not red, and deliberately not an error strip: the photo
/// was accepted and Submit is still enabled. This tells the citizen how to get
/// a better result if they want one, which is a different message from "you
/// did something wrong" — and a very different one from "you may not proceed".
class _SelfieHintStrip extends StatelessWidget {
  final String hint;
  const _SelfieHintStrip({required this.hint});

  static const _amber = Color(0xFFB26A00);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: _amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _amber.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lightbulb_outline_rounded, size: 15, color: _amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hint,
              style: const TextStyle(
                fontSize: 12,
                color: _amber,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
