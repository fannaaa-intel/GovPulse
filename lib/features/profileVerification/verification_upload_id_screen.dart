import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/router/legacy_nav.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/citizen_ui.dart';
import '../../core/widgets/Home/Account/account_web_kit.dart';
import '../../core/widgets/mobile_form_shell.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../core/widgets/modal/verification_required_dialog.dart'
    show showSuccessDialog;

const Map<String, Map<String, String>> idImages = {
  "PhilSys ID": {
    "front": "assets/images/idcards/phfront.webp",
    "back": "assets/images/idcards/phfront.webp",
  },
  "Driver's License ID": {
    "front": "assets/images/idcards/driversfront.webp",
    "back": "assets/images/idcards/driversfront.webp",
  },
  "Postal ID": {
    "front": "assets/images/idcards/postalfront.webp",
    "back": "assets/images/idcards/postalfront.webp",
  },
  "Philippine Passport ID": {
    "front": "assets/images/idcards/philpassfront.webp",
    "back": "assets/images/idcards/philpassfront.webp",
  },
  "PhilHealth ID": {
    "front": "assets/images/idcards/phealthfront.webp",
    "back": "assets/images/idcards/phealthfront.webp",
  },
  "PRC ID": {
    "front": "assets/images/idcards/prcharap.webp",
    "back": "assets/images/idcards/prcharap.webp",
  },
  "SSS ID": {
    "front": "assets/images/idcards/sssfront.webp",
    "back": "assets/images/idcards/sssfront.webp",
  },
  "TIN ID": {
    "front": "assets/images/idcards/tinfront.webp",
    "back": "assets/images/idcards/tinfront.webp",
  },
  "UMID ID": {
    "front": "assets/images/idcards/umidharap.webp",
    "back": "assets/images/idcards/umidharap.webp",
  },
};

class VerificationUploadIdScreen extends StatefulWidget {
  final String username;
  final String selectedId;

  const VerificationUploadIdScreen({
    super.key,
    required this.username,
    required this.selectedId,
  });

  @override
  State<VerificationUploadIdScreen> createState() =>
      _VerificationUploadIdScreenState();
}

class _VerificationUploadIdScreenState extends State<VerificationUploadIdScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryCtrl;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));
    _fadeAnim = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) _entryCtrl.forward();
      });
    });
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    super.dispose();
  }

  /// WEB capture path — file picker instead of the camera.
  ///
  /// There is no camera step on web to send the user to. `/verification_scan`
  /// drives the `camera` package's live preview and runs ML Kit OCR
  /// (IdVerificationService), and neither has a web implementation — ML Kit
  /// pulls in `dart:io` and `path_provider` on top of being mobile-only. So on
  /// web the user picks the two ID images from disk and goes straight to the
  /// review step.
  ///
  /// The arguments handed to `/verification_review` are the SAME shape the scan
  /// screen produces — front and back as [Uint8List] plus an `extractedData`
  /// map — so every later step of the wizard is untouched.
  ///
  /// The one unavoidable difference: `extractedData` is EMPTY, because OCR
  /// cannot run here. That is already a supported state — the review screen
  /// reads `widget.extractedData ?? {}` and simply leaves the fields blank for
  /// the user to type, which is also what happens on mobile whenever a scan
  /// reads nothing confidently.
  Future<void> _pickIdImagesForWeb() async {
    final picker = ImagePicker();

    try {
      final front = await picker.pickImage(source: ImageSource.gallery);
      if (front == null) return;
      final frontBytes = await front.readAsBytes();
      if (!mounted) return;

      // The OS file dialog cannot say which side it wants, so the prompt has to
      // come from us — otherwise the second picker opens with no explanation.
      await showSuccessDialog(
        context,
        title: 'Front received',
        message: 'Now choose a photo of the BACK of your ${widget.selectedId}.',
        buttonLabel: 'Choose back',
        iconData: Icons.badge_outlined,
        iconColor: AppColors.primaryBlue,
      );
      if (!mounted) return;

      final back = await picker.pickImage(source: ImageSource.gallery);
      if (back == null) return;
      final backBytes = await back.readAsBytes();
      if (!mounted) return;

      pushLegacy(
        context,
        '/verification_review',
        arguments: {
          'username': widget.username,
          'selectedId': widget.selectedId,
          'frontImage': frontBytes,
          'backImage': backBytes,
          'extractedData': const <String, String>{},
        },
      );
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        "Couldn't read that image. Please try another file.",
        type: AppSnackType.error,
      );
    }
  }

  // ==========================================================================
  //  WEB
  // ==========================================================================

  /// True when the camera should be the PRIMARY capture method.
  ///
  /// See [kVerificationCameraMaxWidth] for why this reads the window rather than
  /// the content box, and why it only decides which method is offered first.
  bool _webPrefersCamera(BuildContext context) =>
      MediaQuery.of(context).size.width <= kVerificationCameraMaxWidth;

  /// The web dropzone's primary action.
  Future<void> _startWebCapture() async {
    if (_webPrefersCamera(context)) {
      _openWebCameraScan();
      return;
    }
    await _pickIdImagesForWeb();
  }

  /// Hands off to the same camera screen the phone uses.
  ///
  /// No `Permission.camera.request()` on the way: permission_handler has no web
  /// implementation, and the browser prompts for the camera itself the moment
  /// getUserMedia runs. Asking first would throw before the browser ever got the
  /// chance to ask properly.
  void _openWebCameraScan() {
    pushLegacy(
      context,
      '/verification_scan',
      arguments: {'username': widget.username, 'selectedId': widget.selectedId},
    );
  }

  Widget _buildWebScaffold() {
    final images =
        idImages[widget.selectedId] ??
        {
          'front': 'assets/images/idcards/phfront.webp',
          'back': 'assets/images/idcards/phfront.webp',
        };

    return Scaffold(
      backgroundColor: CitizenUi.pageBg,
      body: SafeArea(
        child: AccountPageBody(
          builder: (context, stack) {
            final camera = _webPrefersCamera(context);
            return FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AccountPageTitle(
                      title: 'Upload your ${widget.selectedId}',
                      subtitle: camera
                          ? 'Take a photo of the front and back of your ID.'
                          : 'Choose a photo of the front and back of your ID.',
                      onBack: () => Navigator.pop(context),
                      backLabel: 'Back to photo instructions',
                    ),
                    const AccountStepper(step: 0, labels: kVerificationSteps),

                    const AccountSectionLabel('Capture your ID'),
                    AccountCard(child: _webCaptureRow(stack, camera, images)),
                    const SizedBox(height: kAccountSectionGap),

                    const AccountSectionLabel('Note'),
                    AccountCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _WebUploadNote(
                            icon: Icons.lightbulb_outline,
                            text:
                                'Please ensure you are in a well-lit area for '
                                'best results.',
                          ),
                          const SizedBox(height: 12),
                          _WebUploadNote(
                            icon: Icons.credit_card,
                            // The phone always says "camera frame" because the
                            // phone always uses the camera. On a desktop that
                            // sentence describes a control that is not there.
                            text: camera
                                ? 'Align your ID properly within the camera '
                                      'frame.'
                                : 'Use a photo where the ID fills most of the '
                                      'frame and all four corners are visible.',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// The dropzone beside the two samples, stacking when there is no room.
  Widget _webCaptureRow(bool stack, bool camera, Map<String, String> images) {
    final dropzone = _webDropzone(camera);
    final samples = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _webSample(images['front']!, 'Front sample'),
        const SizedBox(height: kAccountGap),
        _webSample(images['back']!, 'Back sample'),
      ],
    );

    if (stack) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          dropzone,
          const SizedBox(height: kAccountSectionGap),
          samples,
        ],
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 3, child: dropzone),
          const SizedBox(width: kAccountSectionGap),
          Expanded(flex: 2, child: samples),
        ],
      ),
    );
  }

  /// The tap target, plus a way to reach the OTHER capture method.
  ///
  /// The secondary link is the whole reason the width test above is safe to make
  /// at all: a desktop browser dragged narrow has no rear camera, and a tablet
  /// can have its camera blocked, so whichever method the window picked, the
  /// other one is one click away and nobody is stranded.
  Widget _webDropzone(bool camera) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(CitizenUi.controlRadius),
          child: InkWell(
            onTap: _startWebCapture,
            borderRadius: BorderRadius.circular(CitizenUi.controlRadius),
            child: DottedBorder(
              color: CitizenUi.accent,
              strokeWidth: 1.4,
              dashPattern: const [8, 5],
              borderType: BorderType.RRect,
              radius: Radius.circular(CitizenUi.controlRadius),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 34),
                decoration: BoxDecoration(
                  color: CitizenUi.accentWash,
                  borderRadius: BorderRadius.circular(CitizenUi.controlRadius),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: CitizenUi.accent,
                      child: Icon(
                        camera
                            ? Icons.camera_alt_outlined
                            : Icons.upload_file_outlined,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      camera ? 'Open camera' : 'Choose files',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: CitizenUi.accent,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      camera
                          ? 'Scan the front and back of your ID'
                          : 'Pick the front and back from your computer',
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
        const SizedBox(height: 10),
        TextButton(
          onPressed: camera ? _pickIdImagesForWeb : _openWebCameraScan,
          style: TextButton.styleFrom(
            foregroundColor: CitizenUi.textSecondary,
            textStyle: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: Text(
            camera ? 'Upload a file instead' : 'Use my camera instead',
          ),
        ),
      ],
    );
  }

  Widget _webSample(String imagePath, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: CitizenUi.surface,
            border: Border.all(color: CitizenUi.border),
            borderRadius: BorderRadius.circular(CitizenUi.controlRadius),
          ),
          child: Image.asset(imagePath, height: 74, fit: BoxFit.contain),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: CitizenUi.textMuted),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return _buildWebScaffold();

    final images =
        idImages[widget.selectedId] ??
        {
          "front": "assets/images/idcards/phfront.webp",
          "back": "assets/images/idcards/phfront.webp",
        };

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFFF3F4F6),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: SafeArea(
            child: MobileFormShell(
              child: Column(
                children: [
                  const SizedBox(height: 10),

                  /// LOGO
                  Center(
                    child: Image.asset(
                      "assets/images/applogocrop.webp",
                      height: (MediaQuery.of(context).size.height * 0.12).clamp(
                        44.0,
                        88.0,
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  /// TITLE
                  const Text(
                    "Aparri Citizenship Verification",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color.fromARGB(255, 0, 106, 255),
                    ),
                  ),

                  const SizedBox(height: 25),

                  /// STEP INDICATOR
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _step("1", "Upload ID", true),
                        Expanded(child: _line()),
                        _step("2", "Additional\nInformation", false),
                        Expanded(child: _line()),
                        _step("3", "Identity\nVerification", false),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  /// HEADER
                  Text(
                    "Upload Your ${widget.selectedId}",
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 12),
                  const Divider(thickness: 1),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        const SizedBox(height: 38),

                        /// UPLOAD + SAMPLES
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: GestureDetector(
                                onTap: () async {
                                  // WEB: the capture method depends on the
                                  // window - see [_startWebCapture]. This used
                                  // to send every web user to the file picker.
                                  // Everything below is the unchanged mobile
                                  // path.
                                  if (kIsWeb) {
                                    await _startWebCapture();
                                    return;
                                  }

                                  final status = await Permission.camera
                                      .request();
                                  if (!context.mounted) return;

                                  if (status.isGranted) {
                                    pushLegacy(
                                      context,
                                      '/verification_scan',
                                      arguments: {
                                        'username': widget.username,
                                        'selectedId': widget.selectedId,
                                      },
                                    );
                                  } else if (status.isDenied) {
                                    showAppSnackBar(
                                      context,
                                      'Camera permission is required',
                                      type: AppSnackType.error,
                                    );
                                  } else if (status.isPermanentlyDenied) {
                                    openAppSettings();
                                  }
                                },
                                child: DottedBorder(
                                  color: const Color(0xFF2563EB),
                                  strokeWidth: 1,
                                  dashPattern: const [8, 4],
                                  borderType: BorderType.RRect,
                                  radius: const Radius.circular(4),
                                  child: Container(
                                    height: 129,
                                    color: Colors.white,
                                    child: const Center(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          CircleAvatar(
                                            radius: 28,
                                            backgroundColor: Color(0xFF0B57A4),
                                            child: Icon(
                                              Icons.camera_alt_outlined,
                                              color: Colors.white,
                                              size: 30,
                                            ),
                                          ),
                                          SizedBox(height: 8),
                                          Text(
                                            "Tap to Upload your ID",
                                            style: TextStyle(fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),

                            Expanded(
                              flex: 2,
                              child: Column(
                                children: [
                                  _sampleCard(images["front"]!, "Front sample"),
                                  const SizedBox(height: 10),
                                  _sampleCard(images["back"]!, "Back sample"),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 22),
                        const Divider(thickness: 1),
                        const SizedBox(height: 16),

                        /// NOTE BOX
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE5E7EB),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Note",
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.black87,
                                ),
                              ),
                              SizedBox(height: 10),
                              _UploadNoteRow(
                                icon: Icons.lightbulb_outline,
                                text:
                                    "Please ensure you are in a well-lit area for best results.",
                              ),
                              SizedBox(height: 10),
                              _UploadNoteRow(
                                icon: Icons.credit_card,
                                text:
                                    "Align your ID properly within the camera frame.",
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _sampleCard(String imagePath, String label) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFD1D5DB)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Image.asset(imagePath, height: 42, fit: BoxFit.contain),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Colors.black87),
        ),
      ],
    );
  }

  static Widget _step(String number, String label, bool active) {
    return SizedBox(
      width: 54,
      child: Column(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: active
                ? const Color(0xFF2563EB)
                : Colors.grey.shade300,
            child: Text(
              number,
              style: TextStyle(
                fontSize: 10,
                color: active ? Colors.white : Colors.black,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 8,
              color: active ? const Color(0xFF2563EB) : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  static Widget _line() {
    return Container(
      margin: const EdgeInsets.only(top: 11),
      height: 2,
      color: Colors.grey.shade300,
    );
  }
}

class _UploadNoteRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _UploadNoteRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF2563EB)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 11, color: Colors.black87),
          ),
        ),
      ],
    );
  }
}

/// Web-only. The phone's [_UploadNoteRow] at the kit's type sizes.
class _WebUploadNote extends StatelessWidget {
  final IconData icon;
  final String text;

  const _WebUploadNote({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: CitizenUi.textFaint),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.45,
              color: CitizenUi.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
