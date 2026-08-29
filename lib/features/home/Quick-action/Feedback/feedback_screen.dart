import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../shell/citizen_shell_dialogs.dart'
    show FormDialogGuard, kSplitDialogFullscreenBelow;
import '../../../../core/widgets/Home/Quick-action/Web/quick_action_split_panel.dart';
import '../../../../core/theme/citizen_ui.dart';
import '../../../../core/widgets/responsive_page.dart';
import '../../../../core/widgets/modal/media_picker_sheet.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/Home/Newsfeed/rate_limit_dialogs.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/services/gps_stamp_service.dart';
import '../../../../core/widgets/reveal_loading.dart';
import '../../../../core/widgets/app_dialog.dart';
import '../../../../core/theme/mobile_metrics.dart';
import '../../../../core/widgets/app_back_chevron.dart';

/// Standalone Send Feedback page — the full-screen route the mobile app and the
/// live web route open. Chrome only; the form itself is [FeedbackForm].
class FeedbackScreen extends StatelessWidget {
  final String username;
  const FeedbackScreen({super.key, required this.username});

  @override
  Widget build(BuildContext context) => FeedbackForm(username: username);
}

/// The Send Feedback form.
///
/// `embedded: false` (the default) renders the whole page — PopScope discard
/// guard, Scaffold, the ResponsivePageBody hero panel and the in-page header —
/// exactly as before, which is what mobile and the live route still get.
///
/// `embedded: true` renders ONLY the scrolling form, for the web shell's big
/// dialog: the dialog supplies the bounds, the title and the close button, and
/// the decorative hero panel is dropped because it is pure waste in a modal.
/// [guard] lets the dialog's close button reuse this form's discard
/// confirmation.
/// `splitPanel: true` renders the SAME sections as the two-column web panel
/// Report draws — a stepper over the working area on the left, a live summary
/// and the buttons on the right. Only the citizen web shell passes it.
///
/// The eight mobile sections group into the panel's four steps: Office,
/// Service (with the date of visit), Ratings (overall and per aspect), and
/// Details (comment, photos, anonymity). See [_splitStepStack].
class FeedbackForm extends StatefulWidget {
  final String username;
  final bool embedded;
  final FormDialogGuard? guard;

  /// Two-column web layout. Default false, and the default is what mobile, the
  /// native-tablet home body and the standalone route all get — none of them
  /// pass this, so their widget tree is unchanged.
  final bool splitPanel;

  /// Dismisses the hosting dialog. Only read in the [splitPanel] branch, whose
  /// rail owns the × and the Cancel button.
  final VoidCallback? onClose;

  const FeedbackForm({
    super.key,
    required this.username,
    this.embedded = false,
    this.guard,
    this.splitPanel = false,
    this.onClose,
  });

  @override
  State<FeedbackForm> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackForm>
    with SingleTickerProviderStateMixin {
  // ── Shared palette (mirrors SuggestionScreen exactly) ────────────────────────
  static const _kGrayText = Color(0xFF374151);
  static const _kGrayMuted = Color(0xFF6B7280);
  static const _kGrayHint = Color(0xFF9CA3AF);
  static const _kGrayBorder = CitizenUi.sharedBorder;
  static const _kGrayBg = Color(0xFFF9FAFB);
  static const _kRed = Color(0xFFEF4444);
  static const _kAmber = Color(0xFFF59E0B); // star fill color

  // ── Per-office icon colors (always visible, unselected = colored too) ────────
  static const Map<String, Color> _officeColors = {
    'health': Color(0xFFEF4444), // red
    'mayor': Color(0xFF3B82F6), // blue
    'mpdo': Color(0xFF10B981), // green
    'civil': Color(0xFFF59E0B), // amber
    'cert': Color(0xFF8B5CF6), // purple
  };

  // ── Animation ────────────────────────────────────────────────────────────────
  late final AnimationController _entryCtrl;

  // ── Form state ────────────────────────────────────────────────────────────────
  String? _selectedOfficeId;
  String? _selectedService;
  int _starRating = 0;
  final Map<String, int> _aspectRatings = {
    'Staff Attitude': 0,
    'Wait Time': 0,
    'Process Clarity': 0,
    'Facility': 0,
  };
  final _commentCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  DateTime _visitDate = DateTime.now();
  final List<XFile> _photos = [];
  final Map<String, Uint8List> _photoCache = {};

  /// Paths of camera-captured photos carrying a baked-in GPS stamp. Everything
  /// else (gallery photos) is an unverified upload. Written to `photo_sources`
  /// on submit, aligned index-for-index with the uploaded photo URLs.
  final Set<String> _gpsVerifiedPaths = {};

  /// Paths of photos still being processed — camera photos baking a GPS stamp,
  /// or gallery photos decoding. Their tile shows an in-place bottom-to-top
  /// reveal and Submit is guarded until they finish.
  final Set<String> _processingPaths = {};

  /// Paths whose work has just finished: the tile's reveal is still mounted but
  /// now plays its closing sweep to the very top + fade-out. Cleared (together
  /// with [_processingPaths]) once the reveal reports it has finished.
  final Set<String> _completedPaths = {};

  /// Minimum time a tile's reveal stays visible so quick items still animate.
  static const Duration _minReveal = Duration(milliseconds: 500);
  bool _isAnonymous = false;
  bool _isSubmitting = false;
  bool _consentInEnglish = true;

  // ── Split-panel step (web only) ───────────────────────────────────────────
  /// Which step the two-column web panel is showing. Read ONLY by the
  /// `widget.splitPanel` branch; mobile and the standalone route never look at
  /// it, so it cannot change what they render.
  int _splitStep = 0;

  /// The working area's scroll position, so changing step can return it to the
  /// top. Web only — an unattached controller costs a mobile build nothing.
  final ScrollController _splitScrollCtrl = ScrollController();

  /// The four steps the eight mobile sections group into.
  ///
  /// The last is "Details", not "Review": the grouping keeps every section on a
  /// step that COLLECTS something, so there is no read-only recap step to call
  /// Review. The rail's summary is the recap, and it is on screen the whole way
  /// through rather than only at the end.
  static const List<String> _kSplitSteps = [
    'Office',
    'Service',
    'Ratings',
    'Details',
  ];

  /// Which PANE the stacked panel is showing: 0 = Feedback, 1 = Summary.
  int _splitTab = 0;

  static const List<String> _kSplitTabs = ['Feedback', 'Summary'];

  /// Inline error under the offending field on the current split-panel step,
  /// and which field it belongs under ('office' | 'service' | 'rating' |
  /// 'photos').
  ///
  /// It never reaches `_submit()`'s own checks — those stay the sole authority
  /// on what may be filed.
  String? _stepError;
  String? _stepErrorField;

  /// Whether [_stepError] belongs under [field] right now.
  bool _errorOn(String field) => _stepError != null && _stepErrorField == field;

  /// Drops the inline error once the citizen acts on the field it named.
  void _clearStepError(String field) {
    if (_errorOn(field)) {
      _stepError = null;
      _stepErrorField = null;
    }
  }

  // ── Static data ───────────────────────────────────────────────────────────────
  static const List<String> _ratingLabels = [
    '',
    'Very Poor',
    'Poor',
    'Okay',
    'Good',
    'Excellent',
  ];

  static const List<Map<String, String>> _offices = [
    {
      'id': 'health',
      'label': 'Municipal\nHealth Office',
      'full': 'Municipal Health Office',
    },
    {'id': 'mayor', 'label': "Mayor's\nOffice", 'full': "Mayor's Office"},
    {
      'id': 'mpdo',
      'label': 'Planning &\nDevelopment',
      'full': 'Municipal Planning & Development Office',
    },
    {
      'id': 'civil',
      'label': 'Civil\nRegistrar',
      'full': 'Municipal Civil Registrar',
    },
    {
      'id': 'cert',
      'label': 'Certificate\nVerification',
      'full': 'Certificate Verification',
    },
  ];

  static const Map<String, IconData> _officeIcons = {
    'health': Icons.local_hospital_rounded,
    'mayor': Icons.account_balance_rounded,
    'mpdo': Icons.map_rounded,
    'civil': Icons.assignment_rounded,
    'cert': Icons.task_alt_rounded,
  };

  static const Map<String, List<String>> _services = {
    'health': [
      'Availing of Anti-Rabies',
      'Availing of Immunization Services',
      'Availing of Laboratory Services',
      'Availing of Maternal and Child Health Care Services',
      'Availing of Anti-Tuberculosis Drugs or Medicines',
      'Availing of Dental Services',
      'Availing STD/STI Services',
      'Securing Medical/Death Certificate',
      'Out-Patient Department',
      'Issuance of Sanitary Permit',
    ],
    'mayor': [
      "Issuance of Mayor's Clearance",
      'Issuance of Business Permit',
      'Issuance of Working Permit',
      "Issuance of Motorized Tricycle Operator's Permit",
    ],
    'mpdo': [
      'Issuance of Zoning Certification/Land',
      'Issuance of Locational Clearance for Business Permit',
    ],
    'civil': [
      'Timely Registration of Birth of a Legitimate Child',
      'Timely Registration of Birth of an Illegitimate Child',
      'Delayed Registration of Birth',
      'Out-of-Town Delayed Registration of Birth',
      'Timely Registration of Marriage',
      'Delayed Registration of Marriage',
      'Issuance of Birth Certificate (Form 1A / 1B / 1C)',
      'Issuance of Marriage Certificate (Form 3A / 3B)',
      'Issuance of Death Certificate (Form 2A / 2B / 2C)',
      'Timely Registration of Death',
      'Delayed Registration of Death',
      'Application for Marriage License',
      'Petition for Correction of Clerical Error/Change of Name',
      'Registration of Court Orders',
      'Registration of Legal Instrument',
      'Supplemental Report',
    ],
    'cert': ['Barangay Verify Certificate', 'ATOP Verify Certificate'],
  };

  // ── Lifecycle ─────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    // Let the shell's dialog reuse this form's discard confirmation when it is
    // closed from the outside. Passed DOWN via widget.guard, never looked up.
    widget.guard?.confirmDiscard = _showDiscardConfirmation;
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 80), () {
        if (mounted) _entryCtrl.forward();
      });
    });
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _commentCtrl.dispose();
    _searchCtrl.dispose();
    _splitScrollCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────
  List<String> get _filteredServices {
    final q = _searchCtrl.text.toLowerCase().trim();
    final all = _services[_selectedOfficeId] ?? [];
    return q.isEmpty
        ? all
        : all.where((s) => s.toLowerCase().contains(q)).toList();
  }

  String get _selectedOfficeFullLabel => _offices.firstWhere(
    (o) => o['id'] == _selectedOfficeId,
    orElse: () => {'full': ''},
  )['full']!;

  bool _hasAnyInput() =>
      _selectedOfficeId != null ||
      _selectedService != null ||
      _starRating > 0 ||
      _commentCtrl.text.isNotEmpty ||
      _photos.isNotEmpty ||
      _isAnonymous;

  // ── Stagger animations ────────────────────────────────────────────────────────
  Animation<double> _fade(int i) => Tween<double>(begin: 0, end: 1).animate(
    CurvedAnimation(
      parent: _entryCtrl,
      curve: Interval(
        (i * 0.10).clamp(0.0, 0.80),
        ((i * 0.10) + 0.40).clamp(0.0, 1.0),
        curve: Curves.easeOut,
      ),
    ),
  );

  Animation<Offset> _slide(int i) =>
      Tween<Offset>(begin: const Offset(0, 0.18), end: Offset.zero).animate(
        CurvedAnimation(
          parent: _entryCtrl,
          curve: Interval(
            (i * 0.10).clamp(0.0, 0.80),
            ((i * 0.10) + 0.40).clamp(0.0, 1.0),
            curve: Curves.easeOutCubic,
          ),
        ),
      );

  Widget _animated(int i, Widget child) => FadeTransition(
    opacity: _fade(i),
    child: SlideTransition(position: _slide(i), child: child),
  );

  // ── Discard confirmation ──────────────────────────────────────────────────────
  Future<bool> _showDiscardConfirmation() async {
    if (!_hasAnyInput()) return true;

    FocusScope.of(context).unfocus();
    await Future.delayed(const Duration(milliseconds: 50));
    if (!mounted) return false;

    final result = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Discard',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 280),
      transitionBuilder: (ctx, anim, secondAnim, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
        return FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: ScaleTransition(scale: curved, child: child),
        );
      },
      pageBuilder: (ctx, anim, secondAnim) {
        final width = uiScaleWidth(ctx);
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              // Without a cap this confirm stretches the full viewport on web,
              // leaving one short sentence spread across a metre of screen and
              // the two buttons a mouse-drag apart.
              constraints: const BoxConstraints(maxWidth: 400),
              margin: EdgeInsets.symmetric(horizontal: width * 0.07),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF3F4F6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.edit_off_rounded,
                      color: Color(0xFF6B7280),
                      size: 30,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Discard changes?',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'You have unsaved information. Are you sure you want to go back? All your entries will be lost.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF6B7280),
                      height: 1.55,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: AppColors.primaryBlue),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: Text(
                            'Keep editing',
                            style: TextStyle(
                              color: AppColors.primaryBlue,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kRed,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text(
                            'Discard',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    FocusManager.instance.primaryFocus?.unfocus();
    return result ?? false;
  }

  // ── Validation dialog (matches SuggestionScreen — no snackbars for errors) ───
  void _showValidationDialog(String message) {
    showAppDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        // Without a cap, the full-width OK button stretches the card across the
        // whole browser window. A phone screen is narrower than this, so the
        // constraint only ever bites on web/tablet.
        constraints: const BoxConstraints(maxWidth: 400, minWidth: 280),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.info_outline_rounded,
                  color: Colors.orange,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Incomplete Form',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1F2937),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF6B7280),
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text(
                    'OK',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
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

  // ── Date picker ───────────────────────────────────────────────────────────────
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _visitDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: ThemeData.light().copyWith(
          colorScheme: ColorScheme.light(primary: AppColors.primaryBlue),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) setState(() => _visitDate = picked);
  }

  // ── Photo picker ──────────────────────────────────────────────────────────────
  Future<void> _pickPhoto() async {
    if (kIsWeb) {
      _showValidationDialog(
        'Photo upload is available on the mobile app only.',
      );
      return;
    }
    if (_photos.length >= 3) {
      _showValidationDialog('Maximum 3 photos allowed.');
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    await Future.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;

    final choice = await showMediaPickerSheet(context, allowVideo: false);
    if (choice == null || !mounted) return;
    final source = choice == 'camera'
        ? ImageSource.camera
        : ImageSource.gallery;

    try {
      final file = await ImagePicker().pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1200,
      );
      if (file == null || !mounted) return;

      // Live camera capture → add instantly and bake the GPS stamp in the
      // background (the tile shows a bottom-to-top reveal meanwhile). Gallery
      // photos are added as-is (they may be old / from elsewhere — no location
      // to verify).
      if (source == ImageSource.camera) {
        _addCameraPhoto(file);
        return;
      }

      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _photos.add(file);
        _photoCache[file.path] = bytes;
        _processingPaths.add(file.path);
      });
      Future<void>.delayed(_minReveal).whenComplete(() {
        if (!mounted) return;
        // Keep the reveal mounted; let it sweep to the top, then it clears itself.
        setState(() => _completedPaths.add(file.path));
      });
    } catch (e) {
      if (mounted) {
        showFriendlyErrorDialog(
          context,
          'Could not pick photo. Please try again.',
        );
      }
    }
  }

  /// Adds a freshly captured camera photo immediately (original preview under a
  /// reveal animation), then bakes the GPS stamp in the background and swaps in
  /// the stamped file when ready.
  Future<void> _addCameraPhoto(XFile original) async {
    final originalBytes = await original.readAsBytes();
    if (!mounted) return;
    setState(() {
      _photos.add(original);
      _photoCache[original.path] = originalBytes;
      _processingPaths.add(original.path);
    });

    GpsStampService.stampPhoto(original).then((result) async {
      final finalFile = result.file;
      final bytes = await finalFile.readAsBytes();
      if (!mounted) return;
      setState(() {
        final idx = _photos.indexWhere((f) => f.path == original.path);
        if (idx == -1) {
          _processingPaths.remove(original.path); // removed while processing
          _photoCache.remove(original.path);
          return;
        }
        _photos[idx] = finalFile;
        _photoCache.remove(original.path);
        _photoCache[finalFile.path] = bytes;
        if (result.stamped) _gpsVerifiedPaths.add(finalFile.path);
        // Hand the still-mounted reveal over to the stamped file's path and let
        // it play its closing sweep to the top.
        _processingPaths.remove(original.path);
        _processingPaths.add(finalFile.path);
        _completedPaths.add(finalFile.path);
      });
    });
  }

  // ── Submit ────────────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (_selectedOfficeId == null) {
      _showValidationDialog('Please select an office first.');
      return;
    }
    if (_selectedService == null) {
      _showValidationDialog('Please select the service you availed.');
      return;
    }
    if (_starRating == 0) {
      _showValidationDialog('Please rate your overall experience.');
      return;
    }
    if (_processingPaths.isNotEmpty) {
      _showValidationDialog('Please wait for your photo to finish processing.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;

      // Upload photos. `photoSources` stays aligned index-for-index with
      // `photoUrls` so the admin can label each one (camera = GPS-stamped).
      final List<String> photoUrls = [];
      final List<String> photoSources = [];
      for (final photo in _photos) {
        final bytes = _photoCache[photo.path] ?? await photo.readAsBytes();
        final ext = photo.path.split('.').last.toLowerCase();
        final mimeType = ext == 'png' ? 'image/png' : 'image/jpeg';
        final path =
            'feedback/${userId ?? 'anon'}/'
            '${DateTime.now().millisecondsSinceEpoch}.$ext';
        await supabase.storage
            .from('feedback-assets')
            .uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(contentType: mimeType),
            );
        photoUrls.add(
          supabase.storage.from('feedback-assets').getPublicUrl(path),
        );
        photoSources.add(
          _gpsVerifiedPaths.contains(photo.path) ? 'camera' : 'upload',
        );
      }

      // Build payload
      //
      // FIX: keep `user_id` even for anonymous feedback so the owner can still
      // see it in "My Submissions" (which filters by user_id). Anonymity is
      // enforced by the `is_anonymous` flag + nulling the public-facing
      // `username`, NOT by detaching the row from the user.
      final Map<String, dynamic> payload = {
        'user_id': userId,
        'username': _isAnonymous ? null : widget.username,
        'office_id': _selectedOfficeId,
        'office_label': _selectedOfficeFullLabel,
        'service_name': _selectedService,
        'overall_rating': _starRating,
        'visit_date':
            '${_visitDate.year}-'
            '${_visitDate.month.toString().padLeft(2, '0')}-'
            '${_visitDate.day.toString().padLeft(2, '0')}',
        'photo_urls': photoUrls,
        'photo_sources': photoSources,
        'is_anonymous': _isAnonymous,
      };

      if ((_aspectRatings['Staff Attitude'] ?? 0) > 0) {
        payload['aspect_staff'] = _aspectRatings['Staff Attitude'];
      }
      if ((_aspectRatings['Wait Time'] ?? 0) > 0) {
        payload['aspect_wait'] = _aspectRatings['Wait Time'];
      }
      if ((_aspectRatings['Process Clarity'] ?? 0) > 0) {
        payload['aspect_clarity'] = _aspectRatings['Process Clarity'];
      }
      if ((_aspectRatings['Facility'] ?? 0) > 0) {
        payload['aspect_facility'] = _aspectRatings['Facility'];
      }

      final comment = _commentCtrl.text.trim();
      if (comment.isNotEmpty) payload['comment'] = comment;

      // Capture the inserted row id so per-photo AI checks can target it.
      Map<String, dynamic> insertedFeedback;
      try {
        insertedFeedback = await supabase
            .from('feedbacks')
            .insert(payload)
            .select('id')
            .single();
      } on PostgrestException catch (e) {
        // `photo_sources` column may not be migrated yet — retry without it so
        // submitting feedback never breaks (media_source_column.sql).
        if (e.message.toLowerCase().contains('photo_sources')) {
          payload.remove('photo_sources');
          insertedFeedback = await supabase
              .from('feedbacks')
              .insert(payload)
              .select('id')
              .single();
        } else {
          rethrow;
        }
      }

      // Fire-and-forget AI-generated-image check, once per photo. NOT awaited —
      // it must never delay the success toast/navigation, and a failure (or an
      // un-migrated DB / down detector) leaves the submission untouched. Feedback
      // photos are already public, so we pass the URL. `index` is 1-BASED because
      // Postgres arrays start at 1 (see update_feedback_photo_ai).
      final feedbackId = insertedFeedback['id'];
      for (int i = 0; i < photoUrls.length; i++) {
        supabase.functions
            .invoke(
              'check-ai-image',
              body: {
                'table': 'feedbacks',
                'feedbackId': feedbackId,
                'index': i + 1,
                'publicUrl': photoUrls[i],
              },
            )
            .ignore(); // swallow errors — never disturb the submission flow
      }

      if (!mounted) return;
      showAppSnackBar(
        context,
        "Feedback submitted successfully.",
        type: AppSnackType.success,
      );
      Navigator.pop(context);
    } on StorageException catch (e) {
      if (!mounted) return;
      showFriendlyErrorDialog(context, 'File upload failed: ${e.message}');
    } on PostgrestException catch (e) {
      if (!mounted) return;
      if ((e.hint ?? '') == 'rate_limit_exceeded') {
        showRateLimitDialog(
          context,
          'You have reached the daily limit for feedback submissions. Please come back tomorrow.',
        );
      } else {
        showFriendlyErrorDialog(
          context,
          'Could not save your feedback. Please try again.',
        );
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      showFriendlyErrorDialog(context, 'Auth error: ${e.message}');
    } catch (e) {
      if (!mounted) return;
      showFriendlyErrorDialog(
        context,
        'Something went wrong. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ── Anonymous consent dialog (identical to SuggestionScreen) ─────────────────
  void _showAnonymousConsentDialog() {
    showAppDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final isEn = _consentInEnglish;
          final screenW = MediaQuery.of(context).size.width;
          final width = screenW.clamp(0.0, 480.0);
          // On web/desktop this is a block of terms to READ, not a banner: past
          // ~520px the lines get long enough that the eye loses its place on the
          // wrap. Cap the card there and give the surplus back as margin; on a
          // phone the cap never binds and the old 5% inset stands.
          final sideInset = ((screenW - 520) / 2).clamp(
            width * 0.05,
            screenW * 0.5,
          );

          final title = isEn
              ? 'Anonymous Feedback Consent'
              : 'Pahintulot sa Anonymous na Feedback';
          final introBold = isEn
              ? 'Anonymous Feedback'
              : 'Anonymous na Feedback';
          final introText = isEn
              ? ', you acknowledge and agree to the following:'
              : ', kinikilala mo at sumasang-ayon sa mga sumusunod:';
          final bullets = isEn
              ? [
                  'Your identity and personal profile information will remain protected and hidden from public view.',
                  'The content of your submitted feedback, including attached photos, timestamps, and related submission details, may still be securely recorded and stored.',
                  'Submitted feedback may be used for verification, investigation, moderation, legal compliance, and maintaining system integrity and security.',
                  'Authorized administrators or personnel may access feedback records only when necessary for review and processing.',
                  'Any abuse, false reporting, fraudulent activity, or misuse of the anonymous feedback feature may result in appropriate action in accordance with platform policies and applicable laws.',
                ]
              : [
                  'Ang iyong pagkakakilanlan at personal na impormasyon ay mananatiling protektado at nakatago mula sa pampublikong tingin.',
                  'Ang nilalaman ng iyong isinumiteng feedback, kasama ang mga nakalakip na larawan, timestamp, at iba pang detalye, ay maaaring ligtas na mairekord at maiimbak.',
                  'Ang mga isinumiteng feedback ay maaaring gamitin para sa pagpapatunay, imbestigasyon, moderasyon, pagsunod sa batas, at pagpapanatili ng integridad ng sistema.',
                  'Ang mga awtorisadong administrador o tauhan ay maaaring ma-access ang mga rekord ng feedback lamang kung kinakailangan para sa pagsusuri at pagproseso.',
                  'Ang anumang pag-abuso, maling pag-uulat, mapanlinlang na aktibidad, o maling paggamit ng tampok na ito ay maaaring magresulta sa naaangkop na aksyon ayon sa mga patakaran ng platform at naaangkop na batas.',
                ];
          final footer = isEn
              ? 'By choosing "I Agree", you confirm that you understand and agree to these terms.'
              : 'Sa pag-click ng "Sumasang-ayon Ako", kinukumpirma mo na nauunawaan at sumasang-ayon ka sa mga tuntuning ito.';
          final cancelLabel = isEn ? 'Cancel' : 'Kanselahin';
          final agreeLabel = isEn ? 'I Agree' : 'Sumasang-ayon Ako';
          final byEnabling = isEn ? 'By enabling ' : 'Sa pag-enable ng ';

          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            insetPadding: EdgeInsets.symmetric(
              horizontal: sideInset,
              vertical: 24,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: CitizenUi.sharedBorder),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _langPill(
                              'Eng',
                              isEn,
                              () =>
                                  setModalState(() => _consentInEnglish = true),
                            ),
                            _langPill(
                              'Fil',
                              !isEn,
                              () => setModalState(
                                () => _consentInEnglish = false,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.42,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RichText(
                            text: TextSpan(
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF374151),
                                height: 1.55,
                              ),
                              children: [
                                TextSpan(text: byEnabling),
                                TextSpan(
                                  text: introBold,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primaryBlue,
                                  ),
                                ),
                                TextSpan(text: introText),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          ...bullets.map(
                            (b) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '• ',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF374151),
                                      height: 1.55,
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      b,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF374151),
                                        height: 1.55,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            footer,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: Color(0xFF374151),
                              height: 1.55,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          setState(() => _isAnonymous = false);
                          FocusManager.instance.primaryFocus?.unfocus();
                        },
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          cancelLabel,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryBlue,
                          ),
                        ),
                      ),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          setState(() => _isAnonymous = true);
                          FocusManager.instance.primaryFocus?.unfocus();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryBlue,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          elevation: 2,
                        ),
                        child: Text(
                          agreeLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _langPill(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: active ? AppColors.primaryBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: active ? Colors.white : const Color(0xFF6B7280),
          ),
        ),
      ),
    );
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final width = uiScaleWidth(context);

    // The citizen web shell's two-column panel. Checked FIRST because it is the
    // most specific host; the two branches below are untouched.
    if (widget.splitPanel) {
      return GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: _splitPanelBody(width),
      );
    }

    // Inside the shell's dialog the dialog owns the header, the close button and
    // the bounds; the form just scrolls in it. The decorative hero panel is
    // dropped — it is pure waste in a modal. The discard guard moves to the
    // dialog's close path via [widget.guard].
    if (widget.embedded) {
      return GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: _formScroll(width),
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final shouldPop = await _showDiscardConfirmation();
        if (shouldPop && mounted) navigator.pop();
      },
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: Scaffold(
          backgroundColor: const Color(0xFFF3F4F6),
          body: ResponsivePageBody(
            maxWidth: 640,
            shellTitle: 'Send Feedback',
            shellSubtitle:
                'Rate and review LGU services so they keep getting better.',
            shellIcon: Icons.rate_review_outlined,
            shellHighlights: const [
              (Icons.star_border_rounded, 'Rate a service'),
              (Icons.comment_outlined, 'Add a comment'),
              (Icons.thumb_up_alt_outlined, 'Be heard'),
            ],
            shellContentWidth: 600,
            child: SafeArea(
              child: Column(
                children: [
                  _buildHeader(width),
                  Expanded(child: _formScroll(width)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The form itself — every section, scrolling, with no page chrome around it.
  /// Extracted so the shell can host it in a dialog while the standalone screen
  /// keeps rendering it under its own header.
  Widget _formScroll(double width) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.only(bottom: width * 0.06),
      child: Column(
        children: [
          SizedBox(height: width * 0.04),
          _animated(0, _buildOfficeSection(width)),
          SizedBox(height: width * 0.04),
          _animated(1, _buildServiceSection(width)),
          SizedBox(height: width * 0.04),
          _animated(2, _buildStarSection(width)),
          SizedBox(height: width * 0.04),
          _animated(3, _buildAspectSection(width)),
          SizedBox(height: width * 0.04),
          _animated(4, _buildCommentSection(width)),
          SizedBox(height: width * 0.04),
          _animated(5, _buildDateSection(width)),
          SizedBox(height: width * 0.04),
          _animated(6, _buildPhotoSection(width)),
          SizedBox(height: width * 0.04),
          _animated(7, _buildAnonymousSection(width)),
          SizedBox(height: width * 0.035),
          _animated(7, _buildDisclaimer(width)),
          SizedBox(height: width * 0.045),
          _animated(8, _buildSubmitButton(width)),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  Split panel (citizen web only)
  // ══════════════════════════════════════════════════════════════════════════
  //
  //  The same two-column panel Report draws, on the same shared chrome
  //  (quick_action_split_panel.dart) and with the same four numbered steps.
  //
  //  ── Eight sections, four steps ──────────────────────────────────────────
  //  Feedback collects more than Report does, and the panel's frame is fixed,
  //  so the eight mobile sections are grouped rather than paged one-to-one:
  //
  //    1. Office   — the office grid.
  //    2. Service  — the searchable service list, plus the date of the visit.
  //                  The date belongs to the visit the service was availed on,
  //                  so it is asked where that visit is being identified.
  //    3. Ratings  — the overall stars and the four aspect stars. One step,
  //                  because they are the same question at two resolutions and
  //                  splitting them left both halves floating in an empty card.
  //    4. Details  — the comment, the photos and the anonymity toggle: the
  //                  three OPTIONAL things, which is what makes this the step
  //                  the citizen may pass straight through.

  /// The two-column web layout.
  ///
  /// ── Every section is built on every step ─────────────────────────────────
  /// The four steps switch VISIBILITY, not construction: each group is wrapped
  /// in an [Offstage], which leaves the widget mounted and its state intact
  /// while skipping layout and paint. So no TextEditingController is torn down
  /// mid-form, no rating or picked photo is dropped by moving between steps,
  /// and `_submit()` sees exactly the same state it sees on mobile.
  Widget _splitPanelBody(double width) {
    // Rebuild the summary and the review as the citizen types. Scoped to this
    // branch rather than added as initState listeners, so mobile keeps its
    // existing rebuild behaviour untouched.
    return AnimatedBuilder(
      animation: Listenable.merge([_commentCtrl, _searchCtrl]),
      builder: (context, _) => QaSplitPanel(
        left: (stacked) => _splitLeftPanel(width, stacked),
        right: (stacked) => _splitRightRail(stacked),
      ),
    );
  }

  // ── Left panel ────────────────────────────────────────────────────────────

  /// The instruction block's copy for the step in hand. Extracted so the two
  /// layouts read the same words from one place — side by side it sits in the
  /// fixed head, stacked it scrolls with the body.
  (String title, String body) _splitStepCopy() {
    return switch (_splitStep) {
      0 => (
        'Step 1 — Which office did you visit?',
        'Pick the office you dealt with. The services in the next step are '
            'the ones that office actually offers.',
      ),
      1 => (
        'Step 2 — Which service, and when?',
        'Search or scroll for the service you availed, then set the date you '
            'visited. Today is assumed unless you change it.',
      ),
      2 => (
        'Step 3 — How did it go?',
        'The overall rating is required. Rating the four aspects underneath '
            'is optional, but it is what tells the office where to improve.',
      ),
      _ => (
        'Step 4 — Anything to add? (Optional)',
        'A comment, a photo and whether to send this anonymously. All three '
            'are optional — you can send your rating as it stands.',
      ),
    };
  }

  /// The four steps, stacked as [Offstage] siblings. Identical in both layouts —
  /// only what is wrapped AROUND it differs.
  Widget _splitStepStack(double width) {
    return Center(
      child: ConstrainedBox(
        // Capped for the same reason Report's is: the sections below still
        // render against the 480px mobile-proportional scale in places, and the
        // office grid is meant to run the full width of the panel.
        constraints: const BoxConstraints(maxWidth: 700),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Offstage, NOT `if` — see [_splitPanelBody]'s doc.
            Offstage(offstage: _splitStep != 0, child: _splitOfficeStep()),
            Offstage(offstage: _splitStep != 1, child: _splitServiceStep()),
            Offstage(offstage: _splitStep != 2, child: _splitRatingsStep()),
            Offstage(
              offstage: _splitStep != 3,
              child: _splitDetailsStep(width),
            ),
          ],
        ),
      ),
    );
  }

  /// The working card: a fixed head over a scrolling working area.
  ///
  /// ── What [stacked] changes, and why ──────────────────────────────────────
  /// Side by side this card is one of two columns and the rail beside it owns
  /// the panel's identity — its title, its × and its summary. Stacked there is
  /// no rail: [QaSplitPanel] reduces `right` to the pinned action zone, so this
  /// card becomes zones 1 and 2 of the three and takes on what the rail can no
  /// longer carry.
  Widget _splitLeftPanel(double width, bool stacked) {
    final (String title, String body) = _splitStepCopy();

    // Phone-web, derived LOCALLY and only where it is used: `stacked` short
    // circuits, so the side-by-side path never even reads the size. It is the
    // host's own fullscreen threshold, not a second copy that can drift.
    final bool phone =
        stacked &&
        MediaQuery.sizeOf(context).width < kSplitDialogFullscreenBelow;

    return QaPanelCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        // Fit the card to the step, not to the height on offer. A
        // `MainAxisSize.max` column would answer "all of it" and put the dead
        // space straight back.
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Zone 1: the fixed head ───────────────────────────────────────
          if (stacked) ...[
            QaRailHeader(
              title: 'Send Feedback',
              onClose: widget.onClose ?? () {},
              useBackArrow: phone,
            ),
            const SizedBox(height: 14),
            QaSegmentedTabs(
              labels: _kSplitTabs,
              selected: _splitTab,
              onSelect: (i) => setState(() => _splitTab = i),
            ),
            const SizedBox(height: 14),
          ] else ...[
            const QaPanelTitle('Send Feedback'),
            const SizedBox(height: 16),
            QaStepper(
              labels: _kSplitSteps,
              current: _splitStep,
              onSelect: _onStepperTap,
            ),
            const SizedBox(height: 16),
            QaInstructionBlock(title: title, body: body),
            const SizedBox(height: 16),
          ],

          // ── Zone 2: the working area, the panel's only scroller ──────────
          _splitScrollable(
            child: stacked
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Offstage, NOT `if` — keeping the pane mounted is what
                      // makes a glance at the Summary cost nothing. The service
                      // search field in particular would lose its query.
                      Offstage(
                        offstage: _splitTab != 0,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            QaStepper(
                              labels: _kSplitSteps,
                              current: _splitStep,
                              onSelect: _onStepperTap,
                              compact: true,
                            ),
                            const SizedBox(height: 16),
                            QaInstructionBlock(title: title, body: body),
                            const SizedBox(height: 16),
                            _splitStepStack(width),
                          ],
                        ),
                      ),
                      Offstage(
                        offstage: _splitTab != 1,
                        child: _splitSummaryBlock(),
                      ),
                    ],
                  )
                : _splitStepStack(width),
          ),
        ],
      ),
    );
  }

  /// Wraps the working area in the panel's one scroll view.
  ///
  /// `Expanded` gives the scroll view the whole remaining column, and the
  /// `minHeight` makes its CONTENT at least that tall — so the [Center] already
  /// wrapping the step splits a short step's surplus evenly above and below
  /// instead of letting it pool at the bottom as one dead band.
  Widget _splitScrollable({required Widget child}) {
    return Expanded(
      child: LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          controller: _splitScrollCtrl,
          physics: const BouncingScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight),
            child: child,
          ),
        ),
      ),
    );
  }

  /// Moves the panel to [step] and returns the working area to the top.
  ///
  /// All four steps share ONE scroll view, so without this a citizen who
  /// scrolled to the bottom of the service list arrives at Ratings already
  /// scrolled past the stars.
  void _goToSplitStep(int step) {
    setState(() => _splitStep = step);
    if (_splitScrollCtrl.hasClients) _splitScrollCtrl.jumpTo(0);
  }

  // ── Per-step gates ────────────────────────────────────────────────────────

  /// What [step] still needs before it may be left, or null if it is satisfied.
  /// Returns the message and the field it belongs under.
  ///
  /// The one authority on step-to-step progress: both ways forward consult it —
  /// [_continueSplitStep] for the step in hand, [_onStepperTap] for every step
  /// it would skip over — so there is exactly one set of rules and one set of
  /// words for them.
  ///
  /// ── Relationship to `_submit()` ──────────────────────────────────────────
  /// These are the SAME four conditions `_submit()` checks before it will file
  /// anything, split across the steps that own them and worded identically, so
  /// a citizen never sees one message here and a different one at submit.
  /// `_submit()` is untouched and still runs all four in full — it remains the
  /// only authority on what may actually be SENT. Step 4 has no requirement of
  /// its own beyond the processing check, because everything it collects is
  /// optional.
  (String message, String field)? _splitStepGate(int step) {
    switch (step) {
      case 0:
        if (_selectedOfficeId == null) {
          return ('Please select an office first.', 'office');
        }
      case 1:
        if (_selectedService == null) {
          return ('Please select the service you availed.', 'service');
        }
      case 2:
        if (_starRating == 0) {
          return ('Please rate your overall experience.', 'rating');
        }
      case 3:
        // Photos are optional, but a HALF-BAKED one is not — the file would
        // upload without its GPS stamp.
        if (_processingPaths.isNotEmpty) {
          return ('Please wait for your photo to finish processing.', 'photos');
        }
    }
    return null;
  }

  /// A tap on one of the stepper's numbers.
  ///
  /// Backwards is free — re-reading your own answer is never blocked. Forwards
  /// walks the steps in between and stops at the first one that is not
  /// satisfied, MOVING to it and raising the same message [_continueSplitStep]
  /// raises, because a tap that appears to do nothing reads as a broken control.
  void _onStepperTap(int step) {
    if (step <= _splitStep) {
      _goToSplitStep(step);
      return;
    }
    for (var i = 0; i < step; i++) {
      final gate = _splitStepGate(i);
      if (gate == null) continue;
      setState(() {
        _stepError = gate.$1;
        _stepErrorField = gate.$2;
      });
      if (i != _splitStep) _goToSplitStep(i);
      return;
    }
    _goToSplitStep(step);
  }

  /// Continue: gate the CURRENT step, then advance. Never skips ahead, never
  /// touches the submit path.
  void _continueSplitStep() {
    final gate = _splitStepGate(_splitStep);
    if (gate != null) {
      setState(() {
        _stepError = gate.$1;
        _stepErrorField = gate.$2;
      });
      return;
    }
    setState(() {
      _stepError = null;
      _stepErrorField = null;
    });
    _goToSplitStep(_splitStep + 1);
  }

  /// The inline message under a field, when it is the one that failed AND the
  /// condition it names is still unsatisfied.
  ///
  /// Re-checking the live gate is what clears the message the instant the
  /// citizen fixes the field, without any shared handler having to know this
  /// error exists.
  Widget _splitFieldError(String field) {
    if (!_errorOn(field)) return const SizedBox.shrink();
    final live = _splitStepGate(_splitStep);
    if (live == null || live.$2 != field) return const SizedBox.shrink();
    return QaFieldError(_stepError);
  }

  // ── Step 1: office ────────────────────────────────────────────────────────

  /// The office grid, sized to the PANEL rather than to the 480px mobile scale,
  /// with the numbered section card dropped — the stepper already says this is
  /// step 1.
  ///
  /// Writes `_selectedOfficeId` and clears `_selectedService` and the search
  /// box exactly as the mobile card does, because a service list belongs to one
  /// office and carrying a selection across would leave the form claiming a
  /// service the new office does not offer.
  Widget _splitOfficeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const QaFieldLabel(
          'Select an office',
          hint: 'Required',
          hintColor: CitizenUi.danger,
        ),
        LayoutBuilder(
          builder: (context, c) {
            // Three across, filling whatever the panel gives us, sized from
            // that width rather than from a viewport fraction. Office is the
            // SHORTEST step and the panel's frame is fixed, so the tiles are
            // what stands between "a grid of choices" and "five small boxes
            // floating in an empty card". Below ~300 the fixed icon disc makes
            // three across overflow sideways, so it drops to two.
            final cols = c.maxWidth < 300 ? 2 : 3;
            const gap = 14.0;
            final tileW = (c.maxWidth - gap * (cols - 1)) / cols;
            final tileH = (tileW * 0.95).clamp(138.0, 205.0);

            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final office in _offices)
                  SizedBox(
                    width: tileW,
                    height: tileH,
                    child: QaChoiceTile(
                      // Pinned to the OFFICE, not to its position — without a
                      // key a rebuild can hand a tile's State, and with it its
                      // live hover flag, to a different tile.
                      key: ValueKey(office['id']),
                      selected: _selectedOfficeId == office['id'],
                      onTap: () => setState(() {
                        _selectedOfficeId = office['id'];
                        _selectedService = null;
                        _searchCtrl.clear();
                        _clearStepError('office');
                      }),
                      // The grid labels carry a hard wrap sized for a phone
                      // tile; the web tile is wider, so let it flow.
                      label: office['label']!.replaceAll('\n', ' '),
                      // The per-office colour is kept: it is the only thing
                      // telling five otherwise identical tiles apart at a
                      // glance, and it is the same mapping the mobile grid uses.
                      icon: Icon(
                        _officeIcons[office['id']] ?? Icons.business_rounded,
                        size: 34,
                        color:
                            _officeColors[office['id']] ??
                            AppColors.primaryBlue,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        _splitFieldError('office'),
      ],
    );
  }

  // ── Step 2: service + date ────────────────────────────────────────────────

  /// The searchable service list and the date of the visit.
  ///
  /// The list is the same `_filteredServices` the mobile card renders, off the
  /// same `_searchCtrl` — only the row chrome is at panel scale. The "select an
  /// office first" placeholder is unreachable here in practice, since step 1's
  /// gate will not let an officeless citizen arrive; it is kept because the
  /// stepper allows backwards moves and clearing an office mid-form must not
  /// leave this step rendering an empty list with no explanation.
  Widget _splitServiceStep() {
    final services = _filteredServices;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const QaFieldLabel(
          'Select the service you availed',
          hint: 'Required',
          hintColor: CitizenUi.danger,
        ),
        if (_selectedOfficeId == null)
          const QaReviewEmpty('Pick an office on step 1 first')
        else ...[
          TextField(
            controller: _searchCtrl,
            style: const TextStyle(fontSize: 13.5),
            onChanged: (_) => setState(() {}),
            decoration: qaInputDecoration(hint: 'Search services…').copyWith(
              prefixIcon: const Icon(
                Icons.search_rounded,
                size: 18,
                color: CitizenUi.textFaint,
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 38,
                minHeight: 38,
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (services.isEmpty)
            const QaReviewEmpty('No matching services found')
          else
            // A plain column, not a nested scroller: the panel has exactly one
            // scroll view (see [_splitScrollable]) and a second one here would
            // arbitrate every drag over the list against it.
            Column(
              children: [
                for (final service in services)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _splitServiceRow(service),
                  ),
              ],
            ),
        ],
        _splitFieldError('service'),

        const SizedBox(height: 18),
        const QaFieldLabel('Date of visit'),
        _splitDateField(),
      ],
    );
  }

  /// One selectable service row — the mobile card's row at panel scale, with a
  /// hover state that has no meaning on touch and so lives only here.
  Widget _splitServiceRow(String service) {
    final selected = _selectedService == service;
    return _SplitServiceRow(
      label: service,
      selected: selected,
      onTap: () => setState(() {
        _selectedService = service;
        _clearStepError('service');
      }),
    );
  }

  /// The visit date, as a field-shaped button opening the same `_pickDate`
  /// dialog the mobile card opens.
  Widget _splitDateField() {
    final d = _visitDate;
    final dateStr =
        '${d.day.toString().padLeft(2, '0')} / '
        '${d.month.toString().padLeft(2, '0')} / '
        '${d.year}';

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _pickDate,
        behavior: HitTestBehavior.opaque,
        child: QaReviewBox(
          child: Row(
            children: [
              const Icon(
                Icons.calendar_today_rounded,
                size: 17,
                color: CitizenUi.accent,
              ),
              const SizedBox(width: 10),
              Text(
                dateStr,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: CitizenUi.textPrimary,
                ),
              ),
              const Spacer(),
              const Icon(
                Icons.edit_calendar_rounded,
                size: 17,
                color: CitizenUi.textFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Step 3: ratings ───────────────────────────────────────────────────────

  /// The overall rating and the four aspect ratings on one step.
  ///
  /// Both write the same `_starRating` and `_aspectRatings` the mobile cards
  /// write, including the aspect rows' tap-the-same-star-to-clear behaviour.
  Widget _splitRatingsStep() {
    const aspectIcons = <String, IconData>{
      'Staff Attitude': Icons.sentiment_satisfied_alt_rounded,
      'Wait Time': Icons.hourglass_bottom_rounded,
      'Process Clarity': Icons.checklist_rounded,
      'Facility': Icons.home_work_rounded,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const QaFieldLabel(
          'Overall experience',
          hint: 'Required',
          hintColor: CitizenUi.danger,
        ),
        QaReviewBox(
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var n = 1; n <= 5; n++)
                    _SplitStar(
                      filled: n <= _starRating,
                      size: 38,
                      onTap: () => setState(() {
                        _starRating = n;
                        _clearStepError('rating');
                      }),
                    ),
                ],
              ),
              // The word for the number. It appears only once a rating is set,
              // so an untouched control is five outlines and nothing else.
              if (_starRating > 0) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _ratingLabels[_starRating],
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF92400E),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        _splitFieldError('rating'),

        const SizedBox(height: 18),
        const QaFieldLabel('Rate specific aspects', hint: 'Optional'),
        QaReviewBox(
          child: Column(
            children: [
              for (final aspect in _aspectRatings.keys) ...[
                if (aspect != _aspectRatings.keys.first)
                  const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      aspectIcons[aspect] ?? Icons.star_outline_rounded,
                      size: 17,
                      color: CitizenUi.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        aspect,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: CitizenUi.textSecondary,
                        ),
                      ),
                    ),
                    for (var n = 1; n <= 5; n++)
                      _SplitStar(
                        filled: n <= (_aspectRatings[aspect] ?? 0),
                        size: 24,
                        // Same as the mobile row: tapping the star already set
                        // clears the aspect back to unrated, so an accidental
                        // tap on an OPTIONAL field can be taken back.
                        onTap: () => setState(() {
                          _aspectRatings[aspect] = _aspectRatings[aspect] == n
                              ? 0
                              : n;
                        }),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ── Step 4: comment, photos, anonymity ────────────────────────────────────

  /// The three optional things, on the step a citizen may pass straight through.
  Widget _splitDetailsStep(double width) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const QaFieldLabel('Tell us more', hint: 'Optional'),
        TextField(
          controller: _commentCtrl,
          maxLength: 500,
          maxLines: 5,
          style: const TextStyle(fontSize: 13.5, height: 1.45),
          decoration: qaInputDecoration(
            hint: 'What went well, and what could be better?',
          ),
        ),
        const SizedBox(height: 14),
        _splitPhotoBlock(width),
        const SizedBox(height: 18),
        // Feedback is not published to the public feed, so the row's default
        // subtitle would be a promise about somewhere this never appears.
        QaAnonymousRow(
          value: _isAnonymous,
          subtitle: 'Your name is hidden from the office you are rating',
          // Same gate as the mobile card: turning it ON asks for consent first,
          // turning it OFF is immediate.
          onChanged: (v) {
            if (v) {
              _showAnonymousConsentDialog();
            } else {
              setState(() => _isAnonymous = false);
            }
          },
        ),
      ],
    );
  }

  /// The photo block.
  ///
  /// ── Why web says "mobile app only" instead of offering a dropzone ────────
  /// `_pickPhoto` refuses outright under [kIsWeb] — feedback photos are a
  /// camera-and-GPS-stamp flow the browser has no equivalent for, and that
  /// refusal predates this panel. A dropzone here would therefore be a control
  /// whose ONLY possible outcome is an "Incomplete Form" dialog. So on web the
  /// block states the limitation and offers nothing to press; everywhere else
  /// (including widget tests, where `kIsWeb` is false) it draws the same square
  /// grid the other two quick actions use.
  Widget _splitPhotoBlock(double width) {
    if (kIsWeb) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          QaFieldLabel('Photos', hint: 'Mobile app only'),
          QaCallout(
            icon: Icons.phone_iphone_rounded,
            text:
                'Photos are attached from the GovPulse mobile app, where a '
                'camera shot carries a GPS stamp. Your feedback sends fine '
                'without one.',
          ),
        ],
      );
    }

    final canAdd = _photos.length < _kSplitMaxPhotos;
    final itemCount = (canAdd ? 1 : 0) + _photos.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const QaFieldLabel('Photos', hint: 'Optional — up to 3'),
        // Sized by EXTENT rather than by a fixed column count, so a narrowing
        // column drops a column instead of driving the square TILE down with
        // it. Same delegate the other two quick actions use, so the three
        // attachment grids are one shape at every width.
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 170,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1, // square
          ),
          itemCount: itemCount,
          itemBuilder: (context, index) {
            if (canAdd && index == 0) {
              return QaDropzoneTile(
                count: _photos.length,
                max: _kSplitMaxPhotos,
                onTap: _pickPhoto,
              );
            }
            return _splitPhotoTile(canAdd ? index - 1 : index);
          },
        ),
        const SizedBox(height: 8),
        const Text(
          'Image: JPG, PNG (Max. 10MB)',
          style: TextStyle(fontSize: 11.5, color: CitizenUi.textFaint),
        ),
        _splitFieldError('photos'),
      ],
    );
  }

  /// One attached photo's square tile — the cached preview, the processing
  /// reveal and the delete button, in the panel's square cell.
  Widget _splitPhotoTile(int index) {
    final photo = _photos[index];
    final processing = _processingPaths.contains(photo.path);
    final bytes = _photoCache[photo.path];
    final radius = BorderRadius.circular(CitizenUi.controlRadius);

    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: radius,
          child: bytes != null
              ? Image.memory(bytes, fit: BoxFit.cover)
              : Container(
                  color: CitizenUi.subtle,
                  child: const Icon(
                    Icons.image_rounded,
                    color: CitizenUi.textFaint,
                  ),
                ),
        ),
        // Bottom-to-top reveal while the GPS stamp bakes; it fills to the top
        // the moment processing completes. Same widget and same bookkeeping as
        // the mobile row — only the cell around it is different.
        if (processing)
          Positioned.fill(
            child: RevealLoading(
              borderRadius: radius,
              completed: _completedPaths.contains(photo.path),
              onFinished: () {
                if (!mounted) return;
                setState(() {
                  _processingPaths.remove(photo.path);
                  _completedPaths.remove(photo.path);
                });
              },
            ),
          ),
        if (!processing)
          Positioned(
            top: 5,
            right: 5,
            child: GestureDetector(
              onTap: () => setState(() {
                _photoCache.remove(_photos[index].path);
                _photos.removeAt(index);
              }),
              child: Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  color: _kRed,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 14,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// The mobile form's own cap, named so the panel's grid and its counter read
  /// from one number rather than repeating the literal.
  static const int _kSplitMaxPhotos = 3;

  // ── Summary values — derived, never stored ────────────────────────────────

  String? _splitOfficeLabel() {
    final id = _selectedOfficeId;
    if (id == null) return null;
    final office = _offices.firstWhere(
      (o) => o['id'] == id,
      orElse: () => const {'full': ''},
    );
    // The 'full' name, not the tile's wrapped 'label': a rail line has the room
    // and "Municipal Planning & Development Office" is what the office is called.
    return office['full'];
  }

  String? _splitRatingLabel() {
    if (_starRating == 0) return null;
    final rated = _aspectRatings.values.where((v) => v > 0).length;
    final base = '$_starRating/5 · ${_ratingLabels[_starRating]}';
    return rated == 0 ? base : '$base · $rated aspect${rated == 1 ? '' : 's'}';
  }

  String _splitDateLabel() {
    final d = _visitDate;
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  String? _splitPhotoLabel() {
    if (_photos.isEmpty) return null;
    final n = _photos.length;
    final pending = _processingPaths.length;
    final base = '$n photo${n == 1 ? '' : 's'}';
    return pending == 0 ? base : '$base · $pending still processing';
  }

  // ── Right rail ────────────────────────────────────────────────────────────

  /// The summary rows and the step's callout.
  ///
  /// One block, two homes: the rail renders it side by side, and the stacked
  /// panel renders THE SAME widget inside its Summary pane. Every value is read
  /// live off the form's own fields on each build, so the two placements cannot
  /// drift — there is no second copy of anything here.
  ///
  /// ── Why this rail carries five rows where Report carries four ────────────
  /// Feedback collects five things worth reading back, and the date is one of
  /// them: it defaults to today and is therefore the field most likely to be
  /// wrong without anyone having touched it. A rail that showed everything
  /// except the one value nobody set would be hiding the likeliest mistake.
  Widget _splitSummaryBlock() {
    final isLast = _splitStep == _kSplitSteps.length - 1;
    final waitingOnMedia = _processingPaths.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        QaSummaryRow(
          icon: Icons.account_balance_rounded,
          label: 'OFFICE',
          value: _splitOfficeLabel(),
        ),
        QaSummaryRow(
          icon: Icons.assignment_turned_in_rounded,
          label: 'SERVICE',
          value: _selectedService,
        ),
        QaSummaryRow(
          icon: Icons.event_rounded,
          label: 'VISITED',
          // Never null — the form seeds it to today — so this row always reads
          // as answered, which is exactly the point of showing it.
          value: _splitDateLabel(),
        ),
        QaSummaryRow(
          icon: Icons.star_rounded,
          label: 'RATING',
          value: _splitRatingLabel(),
        ),
        QaSummaryRow(
          icon: Icons.chat_bubble_outline_rounded,
          label: 'COMMENT',
          value: _commentCtrl.text,
          placeholder: 'Optional — none',
          maxLines: 2,
        ),
        // ── Dropped on web, and only on web ──────────────────────────────
        // `_pickPhoto` refuses under [kIsWeb], so on the browser this row can
        // never say anything but "Mobile app only" — a permanent line of
        // furniture in a list whose whole job is to change as the form fills.
        //
        // It is not cosmetic. This rail carries more rows than Report's, and
        // the panel's height is FIXED: with six rows the action stack was
        // pushed to the bottom edge of the card and Cancel fell off it
        // entirely, so the citizen had to scroll a summary to reach the
        // buttons. Removing the one row that can never carry information is
        // what buys the stack its place back.
        if (!kIsWeb)
          QaSummaryRow(
            icon: Icons.photo_library_rounded,
            label: 'PHOTOS',
            value: _splitPhotoLabel(),
            placeholder: 'Optional — none',
          ),

        const SizedBox(height: 26),
        // Three states, most urgent first. On the last step the info line gives
        // way to the note that matters immediately before Send.
        if (waitingOnMedia)
          const QaCallout(
            icon: Icons.hourglass_top_rounded,
            accent: AppColors.orange,
            text:
                'A photo is still being prepared. Send unlocks once it '
                'finishes.',
          )
        else if (isLast)
          const QaCallout(
            icon: Icons.gpp_maybe_rounded,
            accent: CitizenUi.warn,
            text:
                'Your rating goes to the office named above. Check the office '
                'and the service before sending.',
          )
        else
          const QaCallout(
            icon: Icons.rate_review_outlined,
            accent: CitizenUi.accent,
            text:
                'Feedback helps the Municipality of Aparri improve its '
                'services. Track it under My Submissions.',
          ),
      ],
    );
  }

  /// Continue/Send, Back and Cancel.
  ///
  /// Extracted for the same reason as [_splitSummaryBlock]: side by side these
  /// sit at the foot of the rail, stacked they ARE the pinned action zone, and
  /// neither placement may fork what the buttons do. [compact] is the pinned
  /// zone's sizing — the buttons, their order, their handlers and their disabled
  /// rules are the same either way.
  Widget _splitActionStack({bool compact = false}) {
    final isLast = _splitStep == _kSplitSteps.length - 1;
    final busy = _isSubmitting;
    final waitingOnMedia = _processingPaths.isNotEmpty;

    void handleCancel() {
      final close = widget.onClose;
      if (close == null) return;
      close();
    }

    return QaActionStack(
      compact: compact,
      children: [
        if (isLast)
          QaActionButton(
            label: waitingOnMedia ? 'Finishing photo…' : 'Send Feedback',
            icon: Icons.send_rounded,
            color: AppColors.green,
            busy: busy,
            compact: compact,
            // The existing handler, unmodified — it runs its own four checks
            // first, so an incomplete form is refused here exactly as on mobile.
            onTap: waitingOnMedia ? null : _submit,
          )
        else
          QaActionButton(
            label: 'Continue',
            icon: Icons.arrow_forward_rounded,
            compact: compact,
            onTap: _continueSplitStep,
          ),
        if (_splitStep > 0)
          QaActionButton(
            label: 'Back',
            icon: Icons.arrow_back_rounded,
            kind: QaActionKind.secondary,
            compact: compact,
            onTap: busy ? null : () => _goToSplitStep(_splitStep - 1),
          ),
        QaActionButton(
          label: 'Cancel',
          kind: QaActionKind.danger,
          compact: compact,
          onTap: busy ? null : handleCancel,
        ),
      ],
    );
  }

  /// The right-hand column.
  ///
  /// ── Side by side ─────────────────────────────────────────────────────────
  /// The full rail: header, summary, callout, buttons, inside a
  /// [SingleChildScrollView]. That scroll view is not decoration — the rail is
  /// drawn to the panel's FIXED height and this rail carries six rows, so at a
  /// narrow rail it would otherwise run past the card.
  ///
  /// ── Stacked ──────────────────────────────────────────────────────────────
  /// Reduced to the ACTION ZONE and returned BARE — a card holding the buttons
  /// and nothing else, no scroll view of its own, because a scroll view here
  /// would share an edge with the working area's and arbitrate drags with it.
  /// The header and summary are not dropped: the working card takes them over.
  ///
  /// The Summary pane has no buttons, because the buttons act on the STEP and
  /// the Summary is not a step.
  Widget? _splitRightRail(bool stacked) {
    if (stacked) {
      // Null, not an empty box: the Summary pane has nothing to press, and
      // [QaSplitPanel] draws the zone's separator only when there is a zone.
      // Returning a zero-height widget instead left a hairline across the
      // bottom of the screen in the fullscreen presentation.
      if (_splitTab != 0) return null;
      // Tighter chrome than the rail's 20 a side: this card is a bar, and every
      // pixel of padding on it is a pixel the step above loses.
      return QaPanelCard(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: _splitActionStack(compact: true),
      );
    }

    return QaPanelCard(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      // ── Head and actions fixed, only the SUMMARY scrolls ────────────────
      // The rail is drawn to the panel's fixed height, so when its contents
      // exceed that something has to give. Scrolling the whole column gave way
      // at the bottom — the buttons — which is the one part that must never be
      // out of reach: a citizen who cannot see Cancel cannot leave, and a
      // Continue below the fold reads as a form with no way forward.
      //
      // `MainAxisSize.min` + `Flexible` is what keeps this free where there is
      // room. Below the frame the column shrink-wraps exactly as it always did
      // and the summary keeps its natural height, so nothing moves; only once
      // the content genuinely overruns does the summary give up the difference
      // and scroll inside itself. The panel's ScrollConfiguration keeps the bar
      // hidden either way.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          QaRailHeader(title: 'Summary', onClose: widget.onClose ?? () {}),
          const SizedBox(height: 20),
          Flexible(child: SingleChildScrollView(child: _splitSummaryBlock())),
          const SizedBox(height: 34),
          _splitActionStack(),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────────
  Widget _buildHeader(double width) {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.symmetric(
        horizontal: width * 0.04,
        vertical: width * 0.03,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () async {
              final shouldPop = await _showDiscardConfirmation();
              if (shouldPop && mounted) Navigator.pop(context);
            },
            child: Container(
              width: width * 0.09,
              height: width * 0.09,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(width * 0.025),
              ),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: width * 0.046,
                color: kBackChevronGlyph,
              ),
            ),
          ),
          SizedBox(width: width * 0.03),
          Image.asset(
            'assets/images/newslogo.webp',
            height: width * 0.085,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => Row(
              children: [
                Icon(
                  Icons.account_balance_rounded,
                  size: width * 0.07,
                  color: AppColors.primaryBlue,
                ),
                SizedBox(width: width * 0.02),
                Text(
                  'GovPulse',
                  style: TextStyle(
                    fontSize: width * 0.048,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryBlue,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Hero banner ───────────────────────────────────────────────────────────────
  Widget _buildHeroBanner(double width) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: width * 0.04),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: width * 0.045,
          vertical: width * 0.045,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(width * 0.04),
          border: Border.all(color: CitizenUi.sharedBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Feedback',
                    style: TextStyle(
                      fontSize: width * 0.058,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1F2937),
                    ),
                  ),
                  SizedBox(height: width * 0.015),
                  Text(
                    'Rate and review LGU services to\nhelp us serve Aparri better.',
                    style: TextStyle(
                      fontSize: width * 0.031,
                      color: const Color(0xFF6B7280),
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            Image.asset(
              'assets/images/feedback.webp',
              width: width * 0.22,
              height: width * 0.22,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => Icon(
                Icons.star_half_rounded,
                size: width * 0.20,
                color: _kAmber,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Section card ──────────────────────────────────────────────────────────────
  Widget _sectionCard({
    required double width,
    required String title,
    required Widget child,
    Widget? trailingTitle,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: width * 0.04),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(width * 0.04),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(width * 0.04),
          border: Border.all(color: CitizenUi.sharedBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: width * 0.040,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1F2937),
                    ),
                  ),
                ),
                ?trailingTitle,
              ],
            ),
            SizedBox(height: width * 0.035),
            child,
          ],
        ),
      ),
    );
  }

  Widget _optionalBadge(double width) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: const Color(0xFFF3F4F6),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      'Optional',
      style: TextStyle(
        fontSize: width * 0.026,
        color: _kGrayHint,
        fontWeight: FontWeight.w500,
      ),
    ),
  );

  // ── 1. Office selection ───────────────────────────────────────────────────────
  Widget _buildOfficeSection(double width) => Column(
    children: [
      _buildHeroBanner(width),
      SizedBox(height: width * 0.04),
      _sectionCard(
        width: width,
        title: '1. Which office did you visit?',
        child: _buildOfficeGrid(width),
      ),
    ],
  );

  Widget _buildOfficeGrid(double width) {
    // 3-column GridView — matches SuggestionScreen category grid layout
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: width * 0.025,
      mainAxisSpacing: width * 0.025,
      childAspectRatio: 1.05,
      children: _offices.map((o) => _officeCard(width, o['id']!)).toList(),
    );
  }

  Widget _officeCard(double width, String id) {
    final office = _offices.firstWhere((o) => o['id'] == id);
    final isSelected = _selectedOfficeId == id;
    final iconColor = _officeColors[id] ?? AppColors.primaryBlue;

    return GestureDetector(
      onTap: () => setState(() {
        _selectedOfficeId = id;
        _selectedService = null;
        _searchCtrl.clear();
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primaryBlue.withOpacity(0.07)
              : _kGrayBg,
          borderRadius: BorderRadius.circular(width * 0.03),
          border: Border.all(
            color: isSelected ? AppColors.primaryBlue : _kGrayBorder,
            width: isSelected ? 1.8 : 1.0,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _officeIcons[id] ?? Icons.business_rounded,
              size: width * 0.085,
              color: iconColor, // always per-office color
            ),
            SizedBox(height: width * 0.012),
            Text(
              office['label']!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: width * 0.026,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: const Color(0xFF374151), // always dark gray
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 2. Service selection ──────────────────────────────────────────────────────
  Widget _buildServiceSection(double width) => _sectionCard(
    width: width,
    title: '2. Which service did you avail?',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_selectedOfficeId == null)
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: width * 0.06),
            decoration: BoxDecoration(
              color: _kGrayBg,
              borderRadius: BorderRadius.circular(width * 0.025),
              border: Border.all(color: _kGrayBorder),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.touch_app_rounded,
                  size: width * 0.08,
                  color: _kGrayHint,
                ),
                SizedBox(height: width * 0.02),
                Text(
                  'Select an office above first',
                  style: TextStyle(fontSize: width * 0.033, color: _kGrayHint),
                ),
              ],
            ),
          )
        else ...[
          TextField(
            controller: _searchCtrl,
            onChanged: (_) => setState(() {}),
            style: TextStyle(fontSize: width * 0.035, color: _kGrayText),
            decoration: InputDecoration(
              hintText: 'Search service...',
              hintStyle: TextStyle(fontSize: width * 0.034, color: _kGrayHint),
              prefixIcon: const Icon(Icons.search_rounded, color: _kGrayHint),
              filled: true,
              fillColor: _kGrayBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(width * 0.025),
                borderSide: const BorderSide(color: _kGrayBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(width * 0.025),
                borderSide: const BorderSide(color: _kGrayBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(width * 0.025),
                borderSide: BorderSide(
                  color: AppColors.primaryBlue,
                  width: 1.5,
                ),
              ),
              contentPadding: EdgeInsets.symmetric(vertical: width * 0.028),
            ),
          ),
          SizedBox(height: width * 0.025),
          if (_filteredServices.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: width * 0.03),
              child: Text(
                'No matching services found.',
                style: TextStyle(fontSize: width * 0.033, color: _kGrayHint),
              ),
            )
          else
            Column(
              children: _filteredServices.map((service) {
                final isSelected = _selectedService == service;
                return GestureDetector(
                  onTap: () => setState(() => _selectedService = service),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: double.infinity,
                    margin: EdgeInsets.only(bottom: width * 0.018),
                    padding: EdgeInsets.symmetric(
                      horizontal: width * 0.035,
                      vertical: width * 0.03,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primaryBlue.withOpacity(0.07)
                          : _kGrayBg,
                      borderRadius: BorderRadius.circular(width * 0.022),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primaryBlue
                            : _kGrayBorder,
                        width: isSelected ? 1.8 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            service,
                            style: TextStyle(
                              fontSize: width * 0.033,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: isSelected
                                  ? AppColors.primaryBlue
                                  : _kGrayText,
                              height: 1.35,
                            ),
                          ),
                        ),
                        if (isSelected)
                          Icon(
                            Icons.check_circle_rounded,
                            size: width * 0.05,
                            color: AppColors.primaryBlue,
                          ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ],
    ),
  );

  // ── 3. Overall star rating ────────────────────────────────────────────────────
  Widget _buildStarSection(double width) => _sectionCard(
    width: width,
    title: '3. Overall experience',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (i) {
            final n = i + 1;
            return GestureDetector(
              onTap: () => setState(() => _starRating = n),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: width * 0.02),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    n <= _starRating
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    key: ValueKey('star_${n}_${n <= _starRating}'),
                    size: width * 0.10,
                    color: n <= _starRating ? _kAmber : const Color(0xFFD1D5DB),
                  ),
                ),
              ),
            );
          }),
        ),
        if (_starRating > 0) ...[
          SizedBox(height: width * 0.025),
          Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Container(
                key: ValueKey(_starRating),
                padding: EdgeInsets.symmetric(
                  horizontal: width * 0.045,
                  vertical: width * 0.016,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _ratingLabels[_starRating],
                  style: TextStyle(
                    fontSize: width * 0.036,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF92400E),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );

  // ── 4. Aspect star ratings ────────────────────────────────────────────────────
  Widget _buildAspectSection(double width) {
    final aspectIcons = <String, IconData>{
      'Staff Attitude': Icons.sentiment_satisfied_alt_rounded,
      'Wait Time': Icons.hourglass_bottom_rounded,
      'Process Clarity': Icons.checklist_rounded,
      'Facility': Icons.home_work_rounded,
    };

    return _sectionCard(
      width: width,
      title: '4. Rate specific aspects',
      trailingTitle: _optionalBadge(width),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tap a star to rate each aspect',
            style: TextStyle(fontSize: width * 0.03, color: _kGrayHint),
          ),
          SizedBox(height: width * 0.035),
          ..._aspectRatings.keys.map((aspect) {
            final rating = _aspectRatings[aspect] ?? 0;
            return Padding(
              padding: EdgeInsets.only(bottom: width * 0.035),
              child: Row(
                children: [
                  Icon(
                    aspectIcons[aspect] ?? Icons.star_outline_rounded,
                    size: width * 0.048,
                    color: _kGrayMuted,
                  ),
                  SizedBox(width: width * 0.02),
                  SizedBox(
                    width: width * 0.26,
                    child: Text(
                      aspect,
                      style: TextStyle(
                        fontSize: width * 0.031,
                        fontWeight: FontWeight.w500,
                        color: _kGrayMuted,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(5, (i) {
                        final n = i + 1;
                        return GestureDetector(
                          onTap: () => setState(() {
                            _aspectRatings[aspect] = _aspectRatings[aspect] == n
                                ? 0
                                : n;
                          }),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Icon(
                              n <= rating
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              key: ValueKey(
                                '${aspect}_star_${n}_${n <= rating}',
                              ),
                              size: width * 0.072,
                              color: n <= rating
                                  ? _kAmber
                                  : const Color(0xFFD1D5DB),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── 5. Comment ────────────────────────────────────────────────────────────────
  Widget _buildCommentSection(double width) => _sectionCard(
    width: width,
    title: '5. Tell us more',
    trailingTitle: _optionalBadge(width),
    child: TextField(
      controller: _commentCtrl,
      maxLines: 4,
      maxLength: 500,
      style: TextStyle(fontSize: width * 0.035, color: _kGrayText),
      decoration: InputDecoration(
        hintText: 'Share your experience in detail...',
        hintStyle: TextStyle(fontSize: width * 0.033, color: _kGrayHint),
        filled: true,
        fillColor: _kGrayBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(width * 0.025),
          borderSide: const BorderSide(color: _kGrayBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(width * 0.025),
          borderSide: const BorderSide(color: _kGrayBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(width * 0.025),
          borderSide: BorderSide(color: AppColors.primaryBlue, width: 1.5),
        ),
        contentPadding: EdgeInsets.all(width * 0.035),
        counterStyle: TextStyle(fontSize: width * 0.028, color: _kGrayHint),
      ),
    ),
  );

  // ── 6. Date of visit ──────────────────────────────────────────────────────────
  Widget _buildDateSection(double width) {
    final dateStr =
        '${_visitDate.day.toString().padLeft(2, '0')} / '
        '${_visitDate.month.toString().padLeft(2, '0')} / '
        '${_visitDate.year}';
    return _sectionCard(
      width: width,
      title: '6. Date of visit',
      child: GestureDetector(
        onTap: _pickDate,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: width * 0.04,
            vertical: width * 0.035,
          ),
          decoration: BoxDecoration(
            color: _kGrayBg,
            borderRadius: BorderRadius.circular(width * 0.025),
            border: Border.all(color: _kGrayBorder),
          ),
          child: Row(
            children: [
              Icon(
                Icons.calendar_today_rounded,
                size: width * 0.05,
                color: AppColors.primaryBlue,
              ),
              SizedBox(width: width * 0.03),
              Text(
                dateStr,
                style: TextStyle(
                  fontSize: width * 0.038,
                  color: _kGrayText,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.edit_calendar_rounded,
                size: width * 0.045,
                color: _kGrayHint,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 7. Photos ─────────────────────────────────────────────────────────────────
  Widget _buildPhotoSection(double width) => _sectionCard(
    width: width,
    title: '7. Add photos',
    trailingTitle: _optionalBadge(width),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Up to 3 photos',
          style: TextStyle(fontSize: width * 0.03, color: _kGrayHint),
        ),
        SizedBox(height: width * 0.03),
        if (_photos.isNotEmpty)
          Row(
            children: [
              ..._photos.asMap().entries.map((entry) {
                final processing = _processingPaths.contains(entry.value.path);
                return Padding(
                  padding: EdgeInsets.only(right: width * 0.025),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(width * 0.025),
                        child: _photoCache.containsKey(entry.value.path)
                            ? Image.memory(
                                _photoCache[entry.value.path]!,
                                width: width * 0.22,
                                height: width * 0.22,
                                fit: BoxFit.cover,
                              )
                            : Container(
                                width: width * 0.22,
                                height: width * 0.22,
                                color: _kGrayBg,
                                child: const Icon(
                                  Icons.image_rounded,
                                  color: _kGrayHint,
                                ),
                              ),
                      ),
                      // Bottom-to-top reveal while the GPS stamp bakes; it fills
                      // to the top the moment processing completes.
                      if (processing)
                        Positioned.fill(
                          child: RevealLoading(
                            borderRadius: BorderRadius.circular(width * 0.025),
                            completed: _completedPaths.contains(
                              entry.value.path,
                            ),
                            onFinished: () {
                              if (!mounted) return;
                              setState(() {
                                _processingPaths.remove(entry.value.path);
                                _completedPaths.remove(entry.value.path);
                              });
                            },
                          ),
                        ),
                      if (!processing)
                        Positioned(
                          top: 3,
                          right: 3,
                          child: GestureDetector(
                            onTap: () => setState(() {
                              _photoCache.remove(_photos[entry.key].path);
                              _photos.removeAt(entry.key);
                            }),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: _kRed,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.close_rounded,
                                size: width * 0.04,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }),
              if (_photos.length < 3)
                GestureDetector(
                  onTap: _pickPhoto,
                  child: Container(
                    width: width * 0.22,
                    height: width * 0.22,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F9FF),
                      borderRadius: BorderRadius.circular(width * 0.025),
                      border: Border.all(
                        color: AppColors.primaryBlue,
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      Icons.add_rounded,
                      size: width * 0.08,
                      color: AppColors.primaryBlue,
                    ),
                  ),
                ),
            ],
          )
        else
          GestureDetector(
            onTap: _pickPhoto,
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: width * 0.065),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F9FF),
                borderRadius: BorderRadius.circular(width * 0.03),
                border: Border.all(
                  color: AppColors.primaryBlue.withOpacity(0.35),
                  width: 1.5,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.add_a_photo_rounded,
                    size: width * 0.095,
                    color: AppColors.primaryBlue,
                  ),
                  SizedBox(height: width * 0.02),
                  Text(
                    'Tap to upload a photo',
                    style: TextStyle(
                      fontSize: width * 0.034,
                      color: AppColors.primaryBlue,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        SizedBox(height: width * 0.022),
        Text(
          'Image: JPG, PNG (Max. 10MB)',
          style: TextStyle(fontSize: width * 0.026, color: _kGrayHint),
        ),
      ],
    ),
  );

  // ── 8. Anonymous toggle ───────────────────────────────────────────────────────
  Widget _buildAnonymousSection(double width) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: width * 0.04),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: width * 0.04,
          vertical: width * 0.032,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(width * 0.04),
          border: Border.all(color: _kGrayBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Image.asset(
              'assets/images/report/padlock.webp',
              width: width * 0.07,
              height: width * 0.07,
              errorBuilder: (_, _, _) => Icon(
                Icons.lock_outline_rounded,
                size: width * 0.07,
                color: _kGrayText,
              ),
            ),
            SizedBox(width: width * 0.03),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Submit anonymously',
                    style: TextStyle(
                      fontSize: width * 0.036,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1F2937),
                    ),
                  ),
                  SizedBox(height: width * 0.005),
                  Text(
                    'Your identity will be hidden from\npublic view.',
                    style: TextStyle(
                      fontSize: width * 0.028,
                      color: _kGrayMuted,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: _isAnonymous,
              onChanged: (v) {
                if (v) {
                  _showAnonymousConsentDialog();
                } else {
                  setState(() => _isAnonymous = false);
                }
              },
              activeThumbColor: Colors.white,
              activeTrackColor: AppColors.green,
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: const Color(0xFFD1D5DB),
            ),
          ],
        ),
      ),
    );
  }

  // ── Disclaimer ────────────────────────────────────────────────────────────────
  Widget _buildDisclaimer(double width) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: width * 0.04),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: width * 0.035,
          vertical: width * 0.030,
        ),
        decoration: BoxDecoration(
          color: AppColors.orange.withOpacity(0.08),
          borderRadius: BorderRadius.circular(width * 0.03),
          border: Border.all(color: AppColors.orange.withOpacity(0.30)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: width * 0.05,
              color: AppColors.orange,
            ),
            SizedBox(width: width * 0.025),
            Expanded(
              child: Text(
                'Please ensure all information submitted is accurate and truthful. False or misleading submissions may result in appropriate action.',
                style: TextStyle(
                  fontSize: width * 0.029,
                  color: const Color(0xFF7C5500),
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Submit button ─────────────────────────────────────────────────────────────
  Widget _buildSubmitButton(double width) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: width * 0.04),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: (_isSubmitting || _processingPaths.isNotEmpty)
              ? null
              : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.green,
            disabledBackgroundColor: _kGrayBorder,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(width * 0.035),
            ),
            padding: EdgeInsets.symmetric(vertical: width * 0.042),
            elevation: 2,
            shadowColor: AppColors.green.withOpacity(0.4),
          ),
          child: _isSubmitting
              ? SizedBox(
                  height: width * 0.05,
                  width: width * 0.05,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : Text(
                  _processingPaths.isNotEmpty
                      ? 'Finishing photo…'
                      : 'Submit Feedback',
                  style: TextStyle(
                    fontSize: width * 0.042,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.3,
                  ),
                ),
        ),
      ),
    );
  }
}

// ── Split-panel row widgets (citizen web only) ───────────────────────────────
//
// Both are stateful only because they carry a HOVER state, which exists for a
// pointer and means nothing on touch. They live here rather than in the shared
// chrome because a service row and a star row are Feedback's shapes; the pieces
// every quick action shares are in quick_action_split_panel.dart.

/// One selectable service in the panel's step-2 list.
class _SplitServiceRow extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SplitServiceRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_SplitServiceRow> createState() => _SplitServiceRowState();
}

class _SplitServiceRowState extends State<_SplitServiceRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: selected
                ? CitizenUi.accent.withValues(alpha: 0.08)
                : (_hover ? CitizenUi.accentWash : CitizenUi.subtle),
            borderRadius: BorderRadius.circular(CitizenUi.controlRadius),
            border: Border.all(
              color: selected
                  ? CitizenUi.accent
                  : (_hover
                        ? CitizenUi.accent.withValues(alpha: 0.35)
                        : CitizenUi.border),
              width: selected ? 1.8 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? CitizenUi.accent
                        : CitizenUi.textSecondary,
                  ),
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                const Icon(
                  Icons.check_circle_rounded,
                  size: 17,
                  color: CitizenUi.accent,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One star in a rating row.
///
/// The animated swap between the outline and the filled glyph is the mobile
/// form's, kept: it is what makes a rating feel set rather than merely recorded.
class _SplitStar extends StatelessWidget {
  final bool filled;
  final double size;
  final VoidCallback onTap;

  const _SplitStar({
    required this.filled,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Icon(
              filled ? Icons.star_rounded : Icons.star_outline_rounded,
              key: ValueKey('${size}_$filled'),
              size: size,
              color: filled ? const Color(0xFFF59E0B) : CitizenUi.borderStrong,
            ),
          ),
        ),
      ),
    );
  }
}
