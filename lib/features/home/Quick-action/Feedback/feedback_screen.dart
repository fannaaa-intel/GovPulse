import 'dart:typed_data';
import 'package:flutter/material.dart';
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

class FeedbackScreen extends StatefulWidget {
  final String username;
  const FeedbackScreen({super.key, required this.username});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen>
    with SingleTickerProviderStateMixin {
  // ── Shared palette (mirrors SuggestionScreen exactly) ────────────────────────
  static const _kGrayText = Color(0xFF374151);
  static const _kGrayMuted = Color(0xFF6B7280);
  static const _kGrayHint = Color(0xFF9CA3AF);
  static const _kGrayBorder = Color(0xFFE5E7EB);
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
        final width = MediaQuery.of(ctx).size.width.clamp(0.0, 480.0);
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
        insertedFeedback =
            await supabase.from('feedbacks').insert(payload).select('id').single();
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
        supabase.functions.invoke('check-ai-image', body: {
          'table': 'feedbacks',
          'feedbackId': feedbackId,
          'index': i + 1,
          'publicUrl': photoUrls[i],
        }).ignore(); // swallow errors — never disturb the submission flow
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
                          border: Border.all(color: const Color(0xFFE5E7EB)),
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
    final width = MediaQuery.of(context).size.width.clamp(0.0, 480.0);

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
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
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
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(width * 0.025),
              ),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: width * 0.045,
                color: AppColors.primaryBlue,
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
          border: Border.all(color: const Color(0xFFE5E7EB)),
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
          border: Border.all(color: const Color(0xFFE5E7EB)),
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
