import 'package:flutter/material.dart';
import '../../shell/citizen_shell_dialogs.dart' show FormDialogGuard;
import '../../../../core/widgets/responsive_page.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/modal/media_picker_sheet.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'dart:typed_data';
import 'package:video_player/video_player.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'location_picker_screen.dart';
import 'dart:async';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/services/gps_stamp_service.dart';
import '../../../../core/widgets/reveal_loading.dart';
import '../../../../core/widgets/Home/Newsfeed/news_feed_helpers.dart'
    show formatTimeAgo;
import '../../../../core/widgets/app_dialog.dart';
import '../../../../core/utils/submission_id.dart';
import '../../../../core/utils/picked_media.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

// ── Aparri bounding box — must match location_picker_screen.dart ──────────
const double _riMinLat = 18.2750;
const double _riMaxLat = 18.4200;
const double _riMinLng = 121.5300; // extended west for Binalan/Navagan
const double _riMaxLng = 121.7450; // extended east for Paddaya/Dodan

bool _withinAparri(double lat, double lng) =>
    lat >= _riMinLat &&
    lat <= _riMaxLat &&
    lng >= _riMinLng &&
    lng <= _riMaxLng;

// ── Duplicate detection ──────────────────────────────────────────────────────

/// Sentinel returned by the "already reported?" dialog when the citizen says
/// their issue is a genuinely different one — distinguishes "file it as new"
/// from dismissing the dialog, which leaves the draft untouched instead.
const String _kMineIsDifferent = 'different';

/// An open report of the same category already filed near the citizen's pin.
///
/// Deliberately carries no reporter identity: `nearby_open_reports` returns the
/// ISSUE only (what/where/when/how many agree), never user_id or is_anonymous,
/// so this prompt cannot expose who filed what.
class _NearbyReport {
  final String id;
  final String shortRef;
  final String remarks;
  final String? barangay;
  final int confirmCount;
  final int distanceM;
  final DateTime? createdAt;

  const _NearbyReport({
    required this.id,
    required this.shortRef,
    required this.remarks,
    required this.barangay,
    required this.confirmCount,
    required this.distanceM,
    required this.createdAt,
  });

  factory _NearbyReport.fromRow(Map<String, dynamic> r) => _NearbyReport(
    id: r['id'] as String,
    shortRef: (r['short_ref'] as String?) ?? '',
    remarks: (r['remarks'] as String?) ?? '',
    barangay: r['barangay'] as String?,
    confirmCount: (r['confirm_count'] as int?) ?? 0,
    distanceM: (r['distance_m'] as num?)?.round() ?? 0,
    createdAt: DateTime.tryParse(r['created_at']?.toString() ?? '')?.toLocal(),
  );

  /// The original reporter plus everyone who has confirmed since.
  int get reporterCount => confirmCount + 1;

  String get distanceLabel =>
      distanceM < 1000 ? '$distanceM m away' : '${(distanceM / 1000).toStringAsFixed(1)} km away';
}

// ─────────────────────────────────────────────────────────────────────────────

class _VideoPreviewDialog extends StatefulWidget {
  final XFile file;
  final double width;
  const _VideoPreviewDialog({required this.file, required this.width});

  @override
  State<_VideoPreviewDialog> createState() => _VideoPreviewDialogState();
}

class _VideoPreviewDialogState extends State<_VideoPreviewDialog> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    // Same dart:io constraint as pickedImageProvider — on web the picked file
    // is a blob: URL, so it has to be opened as a network source.
    _controller = kIsWeb
        ? VideoPlayerController.networkUrl(Uri.parse(widget.file.path))
        : VideoPlayerController.file(File(widget.file.path));
    _controller
        .initialize()
        .then((_) {
          if (!mounted) return;
          setState(() => _isInitialized = true);
          _controller.play();
        })
        .catchError((Object e) {
          debugPrint('Video init error: $e');
          return null;
        });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        children: [
          Center(
            child: _isInitialized
                ? AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: VideoPlayer(_controller),
                  )
                : const CircularProgressIndicator(color: Colors.white),
          ),
          if (_isInitialized)
            Center(
              child: GestureDetector(
                onTap: () => setState(() {
                  _controller.value.isPlaying
                      ? _controller.pause()
                      : _controller.play();
                }),
                child: Container(
                  color: Colors.transparent,
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
            ),
          if (_isInitialized)
            Center(
              child: ValueListenableBuilder(
                valueListenable: _controller,
                builder: (_, VideoPlayerValue value, _) => AnimatedOpacity(
                  opacity: value.isPlaying ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    padding: EdgeInsets.all(widget.width * 0.04),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: widget.width * 0.12,
                    ),
                  ),
                ),
              ),
            ),
          if (_isInitialized)
            Positioned(
              bottom: 60,
              left: 16,
              right: 16,
              child: VideoProgressIndicator(
                _controller,
                allowScrubbing: true,
                colors: VideoProgressColors(
                  playedColor: Colors.white,
                  bufferedColor: Colors.white38,
                  backgroundColor: Colors.white24,
                ),
              ),
            ),
          Positioned(
            top: 40,
            right: 16,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: widget.width * 0.10,
                height: widget.width * 0.10,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// Standalone Report an Issue page — the full-screen route the mobile app and the
/// live web route open. Chrome only; the form itself is [ReportIssueForm].
class ReportIssueScreen extends StatelessWidget {
  final String username;
  const ReportIssueScreen({super.key, required this.username});

  @override
  Widget build(BuildContext context) =>
      ReportIssueForm(username: username);
}

/// The Report an Issue form.
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
class ReportIssueForm extends StatefulWidget {
  final String username;
  final bool embedded;
  final FormDialogGuard? guard;
  const ReportIssueForm({
    super.key,
    required this.username,
    this.embedded = false,
    this.guard,
  });

  @override
  State<ReportIssueForm> createState() => _ReportIssueScreenState();
}

class _ReportIssueScreenState extends State<ReportIssueForm>
    with TickerProviderStateMixin {
  late final AnimationController _entryCtrl;

  // ── Form state ─────────────────────────────────────────────────────────────
  String? _selectedCategory;
  final TextEditingController _othersCtrl = TextEditingController();
  final TextEditingController _remarksCtrl = TextEditingController();
  final TextEditingController _streetDetailCtrl = TextEditingController();
  bool _submitAnonymously = false;
  bool _isSubmitting = false;
  final List<XFile> _attachedFiles = [];
  static const int _maxFiles = 6;
  final ImagePicker _picker = ImagePicker();
  bool _consentInEnglish = true;

  /// Paths of attachments that were captured live with the camera and carry a
  /// baked-in GPS stamp. Everything else (gallery photos, videos) is treated as
  /// an unverified upload. Used to label each media row's `source` on submit.
  final Set<String> _gpsVerifiedPaths = {};

  /// Paths of attachments still being processed — camera photos baking a GPS
  /// stamp, gallery images decoding, or videos generating a thumbnail. Their
  /// tile shows an in-place bottom-to-top reveal instead of a full-screen
  /// spinner, and Submit is guarded until they finish.
  final Set<String> _processingPaths = {};

  /// Paths whose work has just finished: the tile's reveal is still mounted but
  /// now plays its closing sweep to the very top + fade-out. Cleared (together
  /// with [_processingPaths]) once the reveal reports it has finished.
  final Set<String> _completedPaths = {};

  /// Generated video-thumbnail bytes, keyed by file path, so a video tile shows
  /// instantly once its thumbnail is ready (populated during processing).
  final Map<String, Uint8List> _thumbCache = {};

  /// Minimum time a tile's reveal stays visible, so quick items (gallery image
  /// decode) still show the animation instead of flickering.
  static const Duration _minReveal = Duration(milliseconds: 500);

  // ── Location state (barangay-based) ───────────────────────────────────────
  LatLng? _pickedLatLng;

  /// null = using GPS current location; non-null = specific barangay name
  String? _pickedBarangay;
  bool _useCurrentLocation = false;
  bool _isFetchingLocation = true;
  bool _locationOutsideAparri = false;
  bool _locationPermissionDenied = false;

  bool _hasAnyInput() {
    return _selectedCategory != null ||
        _othersCtrl.text.isNotEmpty ||
        _remarksCtrl.text.isNotEmpty ||
        _streetDetailCtrl.text.isNotEmpty ||
        _attachedFiles.isNotEmpty ||
        _submitAnonymously ||
        (_pickedBarangay != null && !_useCurrentLocation); // manually picked
  }

  // ── Categories ─────────────────────────────────────────────────────────────
  final List<Map<String, dynamic>> _categories = [
    {
      'key': 'road',
      'label': 'Road &\nInfrastructure',
      'icon': 'assets/images/report/roadtwo.webp',
      'fallbackIcon': Icons.add_road_rounded,
    },
    {
      'key': 'waste',
      'label': 'Waste &\nGarbage',
      'icon': 'assets/images/report/bin.webp',
      'fallbackIcon': Icons.delete_outline,
    },
    {
      'key': 'drainage',
      'label': 'Drainage &\nFlooding',
      'icon': 'assets/images/report/road.webp',
      'fallbackIcon': Icons.water,
    },
    {
      'key': 'streetlight',
      'label': 'Streetlight\nOutage',
      'icon': 'assets/images/report/lamppost.webp',
      'fallbackIcon': Icons.light,
    },
    {
      'key': 'environment',
      'label': 'Environment &\nPollution',
      'icon': 'assets/images/report/leaf.webp',
      'fallbackIcon': Icons.eco,
    },
    {
      'key': 'others',
      'label': 'Others',
      'icon': 'assets/images/report/menu.webp',
      'fallbackIcon': Icons.more_horiz,
    },
  ];

  // ─────────────────────────────────────────────────────────────────────────────

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
      _autoFetchLocation();
    });
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _othersCtrl.dispose();
    _remarksCtrl.dispose();
    _streetDetailCtrl.dispose();
    super.dispose();
  }

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
                color: Theme.of(ctx).dialogBackgroundColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
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
                            backgroundColor: Colors.red,
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

  // ── GPS auto-fetch — sets current location (no barangay name needed) ────────
  Future<void> _autoFetchLocation() async {
    if (!mounted) return;
    setState(() {
      _isFetchingLocation = true;
      _locationPermissionDenied = false;
      _locationOutsideAparri = false;
    });

    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _isFetchingLocation = false;
            _locationPermissionDenied = true;
          });
        }
        return;
      }

      Position? pos;

      // ── High accuracy with manual timeout ────────────────────────────────
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: AndroidSettings(
            accuracy: LocationAccuracy.high,
            forceLocationManager: false,
          ),
        ).timeout(const Duration(seconds: 20));
      } catch (e) {
        debugPrint('Auto GPS high-accuracy failed: $e');
      }

      // ── Fallback: medium accuracy (WiFi + cell towers, works indoors) ────
      if (pos == null) {
        try {
          pos = await Geolocator.getCurrentPosition(
            locationSettings: AndroidSettings(
              accuracy: LocationAccuracy.medium,
              forceLocationManager: false,
            ),
          ).timeout(const Duration(seconds: 12));
        } catch (e) {
          debugPrint('Auto GPS medium-accuracy failed: $e');
        }
      }

      // ── Fallback: low accuracy (cell towers only) ────────────────────────
      if (pos == null) {
        try {
          pos = await Geolocator.getCurrentPosition(
            locationSettings: AndroidSettings(
              accuracy: LocationAccuracy.low,
              forceLocationManager: false,
            ),
          ).timeout(const Duration(seconds: 8));
        } catch (e) {
          debugPrint('Auto GPS low-accuracy failed: $e');
        }
      }

      // ── Fallback: last known position ────────────────────────────────────
      if (pos == null) {
        try {
          pos = await Geolocator.getLastKnownPosition();
          debugPrint('Auto GPS: using last known → $pos');
        } catch (e) {
          debugPrint('Auto GPS last known failed: $e');
        }
      }

      if (pos == null) {
        if (mounted) {
          setState(() {
            _isFetchingLocation = false;
            _pickedLatLng = null;
            _pickedBarangay = null;
            _useCurrentLocation = false;
          });
        }
        return;
      }

      final lat = pos.latitude;
      final lng = pos.longitude;

      if (!mounted) return;

      if (!_withinAparri(lat, lng)) {
        setState(() {
          _isFetchingLocation = false;
          _locationOutsideAparri = true;
          _pickedLatLng = null;
          _pickedBarangay = null;
          _useCurrentLocation = false;
        });
        showAppSnackBar(
          context,
          "Your location is outside Aparri. Please pick a barangay manually.",
          type: AppSnackType.error,
        );
        return;
      }

      // GPS success — resolve nearest barangay from coordinates
      final nearestBarangay = findNearestBarangay(LatLng(lat, lng));
      setState(() {
        _pickedLatLng = LatLng(lat, lng);
        _pickedBarangay = nearestBarangay;
        _useCurrentLocation = true;
        _isFetchingLocation = false;
        _locationOutsideAparri = false;
      });
    } catch (e) {
      debugPrint('GPS error: $e');
      if (mounted) {
        setState(() {
          _isFetchingLocation = false;
          _pickedLatLng = null;
          _pickedBarangay = null;
          _useCurrentLocation = false;
        });
      }
    }
  }

  Future<void> _openLocationPicker() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      PageRouteBuilder<Map<String, dynamic>>(
        transitionDuration: Duration.zero, // instant in
        reverseTransitionDuration: const Duration(
          milliseconds: 300,
        ), // fade out
        pageBuilder: (_, _, _) => LocationPickerScreen(
          initialPosition: _pickedLatLng,
          initialBarangay: _pickedBarangay,
        ),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _pickedLatLng = result['latLng'] as LatLng?;
        _pickedBarangay = result['barangay'] as String?;
        _useCurrentLocation = result['useCurrentLocation'] as bool;
        _locationOutsideAparri = false;
        _locationPermissionDenied = false;
      });
    }
  }

  // ── Animations ──────────────────────────────────────────────────────────────
  Animation<double> _fade(int i) => Tween<double>(begin: 0, end: 1).animate(
    CurvedAnimation(
      parent: _entryCtrl,
      curve: Interval(
        (i * 0.15).clamp(0.0, 1.0),
        ((i * 0.15) + 0.55).clamp(0.0, 1.0),
        curve: Curves.easeOut,
      ),
    ),
  );

  Animation<Offset> _slide(int i) =>
      Tween<Offset>(begin: const Offset(0, 0.28), end: Offset.zero).animate(
        CurvedAnimation(
          parent: _entryCtrl,
          curve: Interval(
            (i * 0.15).clamp(0.0, 1.0),
            ((i * 0.15) + 0.55).clamp(0.0, 1.0),
            curve: Curves.easeOutCubic,
          ),
        ),
      );

  Widget _animated(int i, Widget child) => FadeTransition(
    opacity: _fade(i),
    child: SlideTransition(position: _slide(i), child: child),
  );

  // ─────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width.clamp(0.0, 480.0);

    // Inside the shell's dialog there is no page to own: the dialog supplies the
    // header, the close button and the bounds, and the form just scrolls in it.
    // The discard confirmation moves to the dialog's close path (see
    // [confirmDiscard]) so an accidental dismissal still asks first.
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
            shellTitle: 'Report an Issue',
            shellSubtitle:
                'Tell your LGU about a community problem — with photos and a '
                'location so it can be acted on quickly.',
            shellIcon: Icons.report_gmailerrorred_rounded,
            shellHighlights: const [
              (Icons.add_a_photo_outlined, 'Attach photos'),
              (Icons.location_on_outlined, 'Pin the location'),
              (Icons.track_changes_rounded, 'Track the status'),
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
  ///
  /// Extracted so the shell can host it inside a dialog while the standalone
  /// screen keeps rendering it under its own header. This is the same
  /// Screen/Body idea as the tabs, applied to a form.
  Widget _formScroll(double width) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.only(bottom: width * 0.06),
      child: Column(
        children: [
          SizedBox(height: width * 0.04),
          _animated(0, _buildCategorySection(width)),
          SizedBox(height: width * 0.04),
          _animated(1, _buildLocationSection(width)),
          SizedBox(height: width * 0.04),
          _animated(2, _buildRemarksSection(width)),
          SizedBox(height: width * 0.04),
          _animated(3, _buildAttachSection(width)),
          SizedBox(height: width * 0.04),
          _animated(4, _buildAnonymousSection(width)),
          SizedBox(height: width * 0.035),
          _animated(5, _buildDisclaimer(width)),
          SizedBox(height: width * 0.045),
          _animated(5, _buildSubmitButton(width)),
        ],
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────────
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

  // ── Hero Banner ─────────────────────────────────────────────────────────────
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
              color: Colors.black.withValues(alpha: 0.05),
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
                    'Report Issue',
                    style: TextStyle(
                      fontSize: width * 0.058,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1F2937),
                    ),
                  ),
                  SizedBox(height: width * 0.015),
                  Text(
                    'Help us improve our community by\nreporting issues in your area.',
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
              'assets/images/report/clipboard.webp',
              width: width * 0.22,
              height: width * 0.22,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => Icon(
                Icons.assignment_rounded,
                size: width * 0.20,
                color: const Color(0xFF6B7280),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Section card ────────────────────────────────────────────────────────────
  Widget _sectionCard({
    required double width,
    required String title,
    required Widget child,
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
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: width * 0.040,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1F2937),
              ),
            ),
            SizedBox(height: width * 0.035),
            child,
          ],
        ),
      ),
    );
  }

  // ── 1. Category ─────────────────────────────────────────────────────────────
  Widget _buildCategorySection(double width) {
    return Column(
      children: [
        _buildHeroBanner(width),
        SizedBox(height: width * 0.04),
        _sectionCard(
          width: width,
          title: '1. Select Issue Category',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: width * 0.025,
                mainAxisSpacing: width * 0.025,
                childAspectRatio: 1.05,
                children: _categories.map((cat) {
                  final isSelected = _selectedCategory == cat['key'];
                  return GestureDetector(
                    onTap: () => setState(
                      () => _selectedCategory = cat['key'] as String,
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primaryBlue.withValues(alpha: 0.07)
                            : const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(width * 0.03),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primaryBlue
                              : const Color(0xFFE5E7EB),
                          width: isSelected ? 1.8 : 1.0,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset(
                            cat['icon'] as String,
                            width: width * 0.085,
                            height: width * 0.085,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => Icon(
                              cat['fallbackIcon'] as IconData,
                              size: width * 0.085,
                              color: isSelected
                                  ? AppColors.primaryBlue
                                  : const Color(0xFF6B7280),
                            ),
                          ),
                          SizedBox(height: width * 0.012),
                          Text(
                            cat['label'] as String,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: width * 0.026,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isSelected
                                  ? AppColors.primaryBlue
                                  : const Color(0xFF374151),
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              if (_selectedCategory == 'others') ...[
                SizedBox(height: width * 0.03),
                Text(
                  'If others please specify,',
                  style: TextStyle(
                    fontSize: width * 0.032,
                    color: const Color(0xFF6B7280),
                  ),
                ),
                SizedBox(height: width * 0.015),
                TextField(
                  controller: _othersCtrl,
                  maxLength: 50,
                  style: TextStyle(fontSize: width * 0.034),
                  decoration: InputDecoration(
                    hintText:
                        'Please describe the category in shortest term if possible...',
                    hintStyle: TextStyle(
                      fontSize: width * 0.029,
                      color: const Color(0xFFD1D5DB),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(width * 0.025),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(width * 0.025),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(width * 0.025),
                      borderSide: BorderSide(color: AppColors.primaryBlue),
                    ),
                    contentPadding: EdgeInsets.all(width * 0.035),
                    counterStyle: TextStyle(
                      fontSize: width * 0.028,
                      color: const Color(0xFF9CA3AF),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ── 2. Location ─────────────────────────────────────────────────────────────
  Widget _buildLocationSection(double width) {
    final hasLocation = _pickedLatLng != null && _pickedBarangay != null;
    return _sectionCard(
      width: width,
      title: '2. Location',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLocationBody(width),

          // ── Street detail — only visible once a location is resolved ────────
          if (hasLocation) ...[
            SizedBox(height: width * 0.04),
            Row(
              children: [
                Text(
                  'Street Name & Detailed Location',
                  style: TextStyle(
                    fontSize: width * 0.032,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF374151),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Optional',
                    style: TextStyle(
                      fontSize: width * 0.026,
                      color: const Color(0xFF9CA3AF),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: width * 0.02),
            TextField(
              controller: _streetDetailCtrl,
              style: TextStyle(fontSize: width * 0.034),
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'e.g. Near the church, beside the market…',
                hintStyle: TextStyle(
                  fontSize: width * 0.031,
                  color: const Color(0xFFD1D5DB),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(width * 0.025),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(width * 0.025),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(width * 0.025),
                  borderSide: BorderSide(color: AppColors.primaryBlue),
                ),
                contentPadding: EdgeInsets.all(width * 0.035),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLocationBody(double width) {
    // ── Loading GPS ──
    if (_isFetchingLocation) {
      return _locationTile(
        width: width,
        bgColor: const Color(0xFFF0F9FF),
        borderColor: const Color(0xFFBAE6FD),
        leading: SizedBox(
          width: width * 0.055,
          height: width * 0.055,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: AppColors.primaryBlue,
          ),
        ),
        text: 'Detecting your location…',
        subText: 'Please wait',
        textColor: const Color(0xFF374151),
      );
    }

    // ── Permission denied ──
    if (_locationPermissionDenied) {
      return _locationTile(
        width: width,
        bgColor: const Color(0xFFFFF7ED),
        borderColor: const Color(0xFFFED7AA),
        leading: Icon(
          Icons.location_off_rounded,
          size: width * 0.07,
          color: Colors.orange,
        ),
        text: 'Location permission denied.',
        subText: 'Tap to pick a barangay manually.',
        textColor: const Color(0xFF374151),
        onTap: _openLocationPicker,
        actionLabel: 'Pick',
      );
    }

    // ── Outside Aparri ──
    if (_locationOutsideAparri) {
      return _locationTile(
        width: width,
        bgColor: const Color(0xFFFEF2F2),
        borderColor: const Color(0xFFFECACA),
        leading: Icon(
          Icons.wrong_location_rounded,
          size: width * 0.07,
          color: Colors.red,
        ),
        text: 'You are outside Aparri.',
        subText: 'Tap to pick a barangay manually.',
        textColor: const Color(0xFF374151),
        onTap: _openLocationPicker,
        actionLabel: 'Pick',
      );
    }

    // ── Location resolved — GPS current location ──
    if (_pickedLatLng != null &&
        _useCurrentLocation &&
        _pickedBarangay != null) {
      return _locationTile(
        width: width,
        bgColor: const Color(0xFFF0F9FF),
        borderColor: const Color(0xFFBAE6FD),
        leading: Icon(
          Icons.my_location_rounded,
          size: width * 0.07,
          color: AppColors.primaryBlue,
        ),
        text: _pickedBarangay!,
        subText: 'Via GPS · Aparri, Cagayan',
        textColor: const Color(0xFF1F2937),
        onTap: _openLocationPicker,
        actionLabel: 'Change',
      );
    }

    // ── Location resolved — specific barangay picked manually ──
    if (_pickedLatLng != null && _pickedBarangay != null) {
      return _locationTile(
        width: width,
        bgColor: const Color(0xFFF9FAFB),
        borderColor: const Color(0xFFE5E7EB),
        leading: Icon(
          Icons.location_on_rounded,
          size: width * 0.07,
          color: AppColors.primaryBlue,
        ),
        text: _pickedBarangay!,
        subText: 'Aparri, Cagayan',
        textColor: const Color(0xFF1F2937),
        onTap: _openLocationPicker,
        actionLabel: 'Change',
      );
    }

    // ── Could not get location ──
    return _locationTile(
      width: width,
      bgColor: const Color(0xFFF9FAFB),
      borderColor: const Color(0xFFE5E7EB),
      leading: Icon(
        Icons.location_searching_rounded,
        size: width * 0.07,
        color: const Color(0xFF9CA3AF),
      ),
      text: 'Could not detect location.',
      subText: 'Tap to pick a barangay manually.',
      textColor: const Color(0xFF374151),
      onTap: _openLocationPicker,
      actionLabel: 'Pick',
    );
  }

  Widget _locationTile({
    required double width,
    required Color bgColor,
    required Color borderColor,
    required Widget leading,
    required String text,
    String? subText,
    required Color textColor,
    VoidCallback? onTap,
    String? actionLabel,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: width * 0.035,
        vertical: width * 0.033,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(width * 0.03),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          leading,
          SizedBox(width: width * 0.03),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: TextStyle(
                    fontSize: width * 0.035,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                    height: 1.4,
                  ),
                ),
                if (subText != null) ...[
                  SizedBox(height: width * 0.005),
                  Text(
                    subText,
                    style: TextStyle(
                      fontSize: width * 0.028,
                      color: const Color(0xFF9CA3AF),
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (actionLabel != null && onTap != null) ...[
            SizedBox(width: width * 0.02),
            GestureDetector(
              onTap: onTap,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    actionLabel,
                    style: TextStyle(
                      fontSize: width * 0.034,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryBlue,
                    ),
                  ),
                  SizedBox(width: width * 0.008),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: width * 0.030,
                    color: AppColors.primaryBlue,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── 3. Remarks ──────────────────────────────────────────────────────────────
  Widget _buildRemarksSection(double width) {
    return _sectionCard(
      width: width,
      title: '3. Remarks / Concern',
      child: TextField(
        controller: _remarksCtrl,
        maxLength: 1000,
        maxLines: 5,
        style: TextStyle(fontSize: width * 0.034),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: 'Please describe the issue in detail...',
          hintStyle: TextStyle(
            fontSize: width * 0.032,
            color: const Color(0xFFD1D5DB),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(width * 0.025),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(width * 0.025),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(width * 0.025),
            borderSide: BorderSide(color: AppColors.primaryBlue),
          ),
          contentPadding: EdgeInsets.all(width * 0.035),
          counterStyle: TextStyle(
            fontSize: width * 0.028,
            color: const Color(0xFF9CA3AF),
          ),
        ),
      ),
    );
  }

  // ── Media helpers ───────────────────────────────────────────────────────────
  bool _isVideo(XFile file) {
    final ext = file.name.toLowerCase();
    return ext.endsWith('.mp4') || ext.endsWith('.mov') || ext.endsWith('.avi');
  }

  Future<void> _pickMedia() async {
    final remaining = _maxFiles - _attachedFiles.length;
    if (remaining <= 0) return;

    FocusManager.instance.primaryFocus?.unfocus();

    final choice = await showMediaPickerSheet(context);

    if (choice == null) return;

    // Live camera capture → add the tile instantly and bake the GPS stamp in
    // the background (the tile shows a bottom-to-top reveal meanwhile). No
    // full-screen spinner.
    if (choice == 'camera') {
      final p = await _picker.pickImage(source: ImageSource.camera);
      if (p != null) _addCameraCapture(p);
      return;
    }

    List<XFile> picked = [];
    if (choice == 'gallery') {
      picked = await _picker.pickMultiImage(limit: remaining);
    } else if (choice == 'video') {
      final v = await _picker.pickVideo(source: ImageSource.gallery);
      if (v != null) picked = [v];
    }

    if (picked.isEmpty) return;

    final List<XFile> validFiles = [];
    bool hasOversized = false;

    for (final file in picked) {
      final bytes = await file.length();
      final isVid = _isVideo(file);
      final maxBytes = isVid ? 50 * 1024 * 1024 : 10 * 1024 * 1024;
      if (bytes > maxBytes) {
        hasOversized = true;
      } else {
        validFiles.add(file);
      }
    }

    if (hasOversized && mounted) {
      showAppSnackBar(
        context,
        "Some files were too large. Images must be under 10MB, videos under 50MB.",
        type: AppSnackType.error,
      );
    }

    if (validFiles.isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final canAdd = _maxFiles - _attachedFiles.length;
    for (final f in validFiles.take(canAdd)) {
      _isVideo(f) ? _addGalleryVideo(f) : _addGalleryImage(f);
    }
  }

  /// Adds a gallery image instantly, showing the reveal while it decodes.
  void _addGalleryImage(XFile file) {
    if (!mounted) return;
    setState(() {
      _attachedFiles.add(file);
      _processingPaths.add(file.path);
    });
    Future.wait([
      precacheImage(pickedImageProvider(file), context),
      Future<void>.delayed(_minReveal),
    ]).whenComplete(() {
      if (!mounted) return;
      // Keep the reveal mounted; let it sweep to the top, then it clears itself.
      setState(() => _completedPaths.add(file.path));
    });
  }

  /// Adds a gallery video instantly, showing the reveal while its thumbnail is
  /// generated (then cached so the tile renders it without a spinner).
  void _addGalleryVideo(XFile file) {
    if (!mounted) return;
    setState(() {
      _attachedFiles.add(file);
      _processingPaths.add(file.path);
    });
    Future.wait([
      VideoThumbnail.thumbnailData(
        video: file.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 200,
        quality: 75,
      ).then((data) {
        if (data != null) _thumbCache[file.path] = data;
      }).catchError((_) {}),
      Future<void>.delayed(_minReveal),
    ]).whenComplete(() {
      if (!mounted) return;
      setState(() => _completedPaths.add(file.path));
    });
  }

  /// Adds a freshly captured camera photo to the grid immediately (showing the
  /// original as a preview under a reveal animation), then bakes the GPS stamp
  /// in the background and swaps in the stamped file when ready.
  void _addCameraCapture(XFile original) {
    if (!mounted) return;
    setState(() {
      _attachedFiles.add(original);
      _processingPaths.add(original.path);
    });

    GpsStampService.stampPhoto(original).then((result) async {
      final finalFile = result.file;
      final tooLarge = await finalFile.length() > 10 * 1024 * 1024;
      if (!mounted) return;
      setState(() {
        final idx = _attachedFiles.indexWhere((f) => f.path == original.path);
        if (idx == -1) {
          _processingPaths.remove(original.path); // removed while processing
          return;
        }
        if (tooLarge) {
          _attachedFiles.removeAt(idx);
          _processingPaths.remove(original.path);
        } else {
          _attachedFiles[idx] = finalFile;
          if (result.stamped) _gpsVerifiedPaths.add(finalFile.path);
          // Hand the still-mounted reveal over to the stamped file's path and
          // let it play its closing sweep to the top.
          _processingPaths.remove(original.path);
          _processingPaths.add(finalFile.path);
          _completedPaths.add(finalFile.path);
        }
      });
      if (tooLarge) {
        showAppSnackBar(
          context,
          "That photo was too large (over 10MB) and was removed.",
          type: AppSnackType.error,
        );
      }
    });
  }

  /// Video thumbnail for a grid tile — uses the cached bytes if ready, else
  /// generates them (the reveal covers the plain placeholder while processing).
  Widget _videoThumb(XFile file, double width) {
    final cached = _thumbCache[file.path];
    Widget withPlay(Widget image) => Stack(
      fit: StackFit.expand,
      children: [
        image,
        Center(
          child: Container(
            padding: EdgeInsets.all(width * 0.015),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.play_arrow_rounded,
              color: Colors.white,
              size: width * 0.06,
            ),
          ),
        ),
      ],
    );

    if (cached != null) {
      return withPlay(Image.memory(cached, fit: BoxFit.cover));
    }
    return FutureBuilder<Uint8List?>(
      future: VideoThumbnail.thumbnailData(
        video: file.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 200,
        quality: 75,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.data != null) {
          return withPlay(Image.memory(snapshot.data!, fit: BoxFit.cover));
        }
        return const ColoredBox(color: Color(0xFFE0F2FE));
      },
    );
  }

  void _previewImage(BuildContext context, XFile file, double width) {
    showAppDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: Image(
                  image: pickedImageProvider(file),
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Positioned(
              top: 40,
              right: 16,
              child: GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  width: width * 0.10,
                  height: width * 0.10,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _previewVideo(BuildContext context, XFile file, double width) {
    showAppDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => _VideoPreviewDialog(file: file, width: width),
    );
  }

  // ── 4. Attach ────────────────────────────────────────────────────────────────
  Widget _buildAttachSection(double width) {
    final slotCount = _attachedFiles.length < _maxFiles
        ? _attachedFiles.length + 1
        : _maxFiles;

    return _sectionCard(
      width: width,
      title: '4. Attach Image / Video (Required)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: _attachedFiles.length < _maxFiles ? _pickMedia : null,
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: width * 0.065),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F9FF),
                borderRadius: BorderRadius.circular(width * 0.03),
                border: Border.all(
                  color: AppColors.primaryBlue.withValues(alpha: 0.35),
                  width: 1.5,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_a_photo_rounded,
                    size: width * 0.095,
                    color: AppColors.primaryBlue,
                  ),
                  SizedBox(height: width * 0.02),
                  Text(
                    'Tap to upload photo or video',
                    style: TextStyle(
                      fontSize: width * 0.034,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF374151),
                    ),
                  ),
                  SizedBox(height: width * 0.008),
                  Text(
                    _attachedFiles.isEmpty
                        ? 'You can upload up to $_maxFiles files'
                        : '${_attachedFiles.length}/$_maxFiles uploaded',
                    style: TextStyle(
                      fontSize: width * 0.028,
                      color: const Color(0xFF9CA3AF),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_attachedFiles.isNotEmpty) ...[
            SizedBox(height: width * 0.03),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: width * 0.025,
                mainAxisSpacing: width * 0.025,
                childAspectRatio: 1.0,
              ),
              itemCount: slotCount,
              itemBuilder: (context, index) {
                final isPlus = index == _attachedFiles.length;
                if (isPlus) {
                  return GestureDetector(
                    onTap: _pickMedia,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F9FF),
                        borderRadius: BorderRadius.circular(width * 0.025),
                        border: Border.all(
                          color: AppColors.primaryBlue.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Center(
                        child: Image.asset(
                          'assets/images/report/plus_sign.webp',
                          width: width * 0.07,
                          height: width * 0.07,
                          errorBuilder: (_, _, _) => Icon(
                            Icons.add_rounded,
                            size: width * 0.07,
                            color: AppColors.primaryBlue,
                          ),
                        ),
                      ),
                    ),
                  );
                }
                final file = _attachedFiles[index];
                final processing = _processingPaths.contains(file.path);
                return GestureDetector(
                  onTap: processing
                      ? null
                      : () {
                          _isVideo(file)
                              ? _previewVideo(context, file, width)
                              : _previewImage(context, file, width);
                        },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(width * 0.025),
                        child: _isVideo(file)
                            ? _videoThumb(file, width)
                            : Image(
                                image: pickedImageProvider(file),
                                fit: BoxFit.cover,
                              ),
                      ),
                      // Bottom-to-top reveal while the GPS stamp bakes; it fills
                      // to the top the moment processing completes.
                      if (processing)
                        Positioned.fill(
                          child: RevealLoading(
                            borderRadius: BorderRadius.circular(width * 0.025),
                            completed: _completedPaths.contains(file.path),
                            onFinished: () {
                              if (!mounted) return;
                              setState(() {
                                _processingPaths.remove(file.path);
                                _completedPaths.remove(file.path);
                              });
                            },
                          ),
                        ),
                      if (!processing)
                        Positioned(
                          top: 5,
                          right: 5,
                          child: GestureDetector(
                            onTap: () =>
                                setState(() => _attachedFiles.removeAt(index)),
                            child: Container(
                              width: width * 0.055,
                              height: width * 0.055,
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.close_rounded,
                                color: Colors.white,
                                size: width * 0.034,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
          SizedBox(height: width * 0.022),
          Text(
            'Image: JPG, PNG (Max. 10MB)  •  Video: MP4 (Max. 50MB)',
            style: TextStyle(
              fontSize: width * 0.026,
              color: const Color(0xFF9CA3AF),
            ),
          ),
        ],
      ),
    );
  }

  // ── Anonymous consent dialog ────────────────────────────────────────────────
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
              ? 'Anonymous Report Consent'
              : 'Pahintulot sa Anonymous na Ulat';
          final introBold = isEn ? 'Anonymous Report' : 'Anonymous na Ulat';
          final introText = isEn
              ? ', you acknowledge and agree to the following:'
              : ', kinikilala mo at sumasang-ayon sa mga sumusunod:';
          final bullets = isEn
              ? [
                  'Your identity and personal profile information will remain protected and hidden from public view.',
                  'The content of your submitted report, including attached files, timestamps, and related submission details, may still be securely recorded and stored.',
                  'Submitted reports may be used for verification, investigation, moderation, legal compliance, and maintaining system integrity and security.',
                  'Authorized administrators or personnel may access report records only when necessary for review and processing.',
                  'Any abuse, false reporting, fraudulent activity, or misuse of the anonymous reporting feature may result in appropriate action in accordance with platform policies and applicable laws.',
                ]
              : [
                  'Ang iyong pagkakakilanlan at personal na impormasyon ay mananatiling protektado at nakatago mula sa pampublikong tingin.',
                  'Ang nilalaman ng iyong isinumiteng ulat, kasama ang mga nakalakip na file, timestamp, at iba pang detalye, ay maaaring ligtas na mairekord at maiimbak.',
                  'Ang mga isinumiteng ulat ay maaaring gamitin para sa pagpapatunay, imbestigasyon, moderasyon, pagsunod sa batas, at pagpapanatili ng integridad ng sistema.',
                  'Ang mga awtorisadong administrador o tauhan ay maaaring ma-access ang mga rekord ng ulat lamang kung kinakailangan para sa pagsusuri at pagproseso.',
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
                          setState(() => _submitAnonymously = false);
                          FocusScope.of(context).unfocus();
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
                          setState(() => _submitAnonymously = true);
                          FocusScope.of(context).unfocus();
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

  // ── 5. Anonymous toggle ──────────────────────────────────────────────────────
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
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
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
                color: const Color(0xFF374151),
              ),
            ),
            SizedBox(width: width * 0.03),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Submit Anonymously',
                    style: TextStyle(
                      fontSize: width * 0.036,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1F2937),
                    ),
                  ),
                  SizedBox(height: width * 0.005),
                  Text(
                    'Your identity will be hidden from the\npublic view.',
                    style: TextStyle(
                      fontSize: width * 0.028,
                      color: const Color(0xFF6B7280),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: _submitAnonymously,
              onChanged: (v) {
                if (v) {
                  _showAnonymousConsentDialog();
                } else {
                  setState(() => _submitAnonymously = false);
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

  // ── Submission ───────────────────────────────────────────────────────────────

  /// Validates all required fields. Returns an error message or null if valid.
  String? _validate() {
    if (_selectedCategory == null) {
      return 'Please select an issue category.';
    }
    if (_selectedCategory == 'others' && _othersCtrl.text.trim().isEmpty) {
      return 'Please specify the category under "Others".';
    }
    if (_pickedLatLng == null || _pickedBarangay == null) {
      return 'Please set a location before submitting.';
    }
    if (_attachedFiles.isEmpty) {
      return 'Please attach at least one photo or video.';
    }
    if (_processingPaths.isNotEmpty) {
      return 'Please wait for your photo to finish processing.';
    }
    return null;
  }

  /// Open reports of the same category already filed within the dedupe radius
  /// (report_duplicates.sql). Empty on any failure — including the migration not
  /// being applied yet — because a "someone already reported this" hint must
  /// never be what stops a citizen from reporting.
  Future<List<_NearbyReport>> _fetchNearbyReports() async {
    try {
      final rows = await Supabase.instance.client.rpc(
        'nearby_open_reports',
        params: {
          'p_category': _selectedCategory,
          'p_lat': _pickedLatLng!.latitude,
          'p_lng': _pickedLatLng!.longitude,
          'p_limit': 3,
        },
      );
      return List<Map<String, dynamic>>.from(rows as List)
          .map(_NearbyReport.fromRow)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _submitReport() async {
    // ── 1. Validate ──────────────────────────────────────────────────────────
    final error = _validate();
    if (error != null) {
      _showValidationDialog(error);
      return;
    }

    setState(() => _isSubmitting = true);

    // ── 2. Already reported here? ────────────────────────────────────────────
    // Checked BEFORE the media upload, so confirming an existing report doesn't
    // cost the citizen an upload they didn't need. Confirming still files their
    // own report (linked via duplicate_of) rather than discarding it — they keep
    // their own record and their own status notifications, and their photos ride
    // along as extra evidence on the same issue.
    String? duplicateOf;
    final nearby = await _fetchNearbyReports();
    if (nearby.isNotEmpty) {
      if (!mounted) return;
      final choice = await _showNearbyReportsDialog(nearby);
      if (choice == null) {
        // Backed out to re-check their pin — leave the draft exactly as it was.
        if (mounted) setState(() => _isSubmitting = false);
        return;
      }
      if (choice != _kMineIsDifferent) duplicateOf = choice;
    }

    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser!.id;

      // The report id is generated HERE, before anything is uploaded, so media
      // can be keyed by the report instead of by the citizen. The old path
      // `reports/$userId/...` put the reporter's uuid in the object key even on
      // anonymous submissions, which let staff de-anonymise a report without
      // reading the reports table. See lib/core/utils/submission_id.dart.
      final reportId = uuidV4();

      // ── 2. Upload media files to storage ─────────────────────────────────
      final List<Map<String, String>> mediaItems = [];
      for (int i = 0; i < _attachedFiles.length; i++) {
        final file = _attachedFiles[i];
        final bytes = await file.readAsBytes();
        final ext = file.name.split('.').last.toLowerCase();
        final fileName =
            '${DateTime.now().millisecondsSinceEpoch}_${i}_${file.name}';
        final storagePath = 'reports/$reportId/$fileName';
        final contentType = _isVideo(file) ? 'video/$ext' : 'image/$ext';

        await supabase.storage
            .from('report-media')
            .uploadBinary(
              storagePath,
              bytes,
              fileOptions: FileOptions(contentType: contentType),
            );

        mediaItems.add({
          'path': storagePath,
          'mime': contentType,
          'source': _gpsVerifiedPaths.contains(file.path) ? 'camera' : 'upload',
        });
      }

      // ── 3. Insert report into database ────────────────────────────────────
      final response = await supabase
          .from('reports')
          .insert({
            // Explicit id: the media above was already uploaded under
            // reports/$reportId/. `.insert` (never `.upsert`) so a colliding id
            // fails on the primary key instead of overwriting someone's row.
            'id': reportId,
            'user_id': userId,
            'category': _selectedCategory,
            'category_other': _selectedCategory == 'others'
                ? _othersCtrl.text.trim()
                : null,
            'barangay': _pickedBarangay,
            'address': _streetDetailCtrl.text.trim().isEmpty
                ? null
                : _streetDetailCtrl.text.trim(),
            'latitude': _pickedLatLng!.latitude,
            'longitude': _pickedLatLng!.longitude,
            'remarks': _remarksCtrl.text.trim(),
            'is_anonymous': _submitAnonymously,
            'status': 'pending',
            // Only sent when the citizen confirmed an existing report — which
            // can only happen if the lookup RPC answered, so the column is
            // guaranteed to exist by then.
            'duplicate_of': ?duplicateOf,
          })
          .select('id')
          .single();

      // `reportId` is already known — it was generated before the upload. The
      // round-trip is kept only so a failed insert throws here rather than
      // surfacing later as media rows pointing at a report that never existed.
      assert(response['id'] == reportId);

      // ── 4. Insert media rows into report_media table ──────────────────────
      for (int i = 0; i < mediaItems.length; i++) {
        final row = <String, dynamic>{
          'report_id': reportId,
          'storage_path': mediaItems[i]['path'],
          'mime_type': mediaItems[i]['mime'],
          'display_order': i + 1,
          'source': mediaItems[i]['source'],
        };
        // Capture the inserted row id so the AI-image check can target it.
        Map<String, dynamic> inserted;
        try {
          inserted = await supabase
              .from('report_media')
              .insert(row)
              .select('id')
              .single();
        } on PostgrestException catch (e) {
          // `source` column may not be migrated yet — retry without it so
          // submitting a report never breaks (media_source_column.sql).
          if ((e.message).toLowerCase().contains('source')) {
            row.remove('source');
            inserted = await supabase
                .from('report_media')
                .insert(row)
                .select('id')
                .single();
          } else {
            rethrow;
          }
        }

        // Fire-and-forget AI-generated-image check (images only). NOT awaited —
        // it must never delay the success toast/navigation, and a failure (or an
        // un-migrated DB / down detector) leaves the submission untouched.
        final mime = (mediaItems[i]['mime'] ?? '').toLowerCase();
        if (mime.startsWith('image/')) {
          supabase.functions.invoke('check-ai-image', body: {
            'bucket': 'report-media',
            'path': mediaItems[i]['path'],
            'table': 'report_media',
            'id': inserted['id'],
          }).ignore(); // swallow errors — never disturb the submission flow
        }
      }
      // ── 5. Success ────────────────────────────────────────────────────────
      if (mounted) {
        showAppSnackBar(
          context,
          duplicateOf == null
              ? "Report submitted successfully."
              : "Thanks — your confirmation was added to the existing report.",
          type: AppSnackType.success,
        );
        Navigator.pop(context);
      }
    } on StorageException catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          'File upload failed: ${e.message}',
          type: AppSnackType.error,
        );
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        if ((e.hint ?? '') == 'rate_limit_exceeded') {
          showAppSnackBar(
            context,
            "You've reached your daily limit of 5 reports. Please come back tomorrow.",
            type: AppSnackType.error,
          );
        } else {
          showAppSnackBar(
            context,
            "Could not submit your report. Please try again.",
            type: AppSnackType.error,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          "Could not submit your report. Please try again.",
          type: AppSnackType.error,
        );
      }
    } finally {
      // EVERY exit has to clear the spinner. Without this the button stays in
      // its loading state after any failure — an unsupported file type, a
      // storage error, an RLS denial — and the citizen cannot retry without
      // killing the screen. The success path pops the route, so the mounted
      // guard covers it.
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ── "Already reported?" dialog ───────────────────────────────────────────────
  /// Returns the id of the report the citizen chose to confirm,
  /// [_kMineIsDifferent] to file theirs as a new issue, or null if they backed
  /// out to re-check their pin.
  ///
  /// Framed as a question, never a refusal: the citizen is always allowed to
  /// file. Getting this wrong in the strict direction (blocking a real report
  /// because it looked like a duplicate) is far more costly than a duplicate.
  Future<String?> _showNearbyReportsDialog(List<_NearbyReport> nearby) {
    return showAppDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        // Without a cap, the full-width button inside stretches the card across
        // the whole browser window. A phone screen is narrower than this, so
        // the constraint only ever bites on web/tablet.
        constraints: const BoxConstraints(maxWidth: 400, minWidth: 280),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.where_to_vote_outlined,
                    color: AppColors.primaryBlue,
                    size: 32,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                nearby.length == 1
                    ? 'Already reported here?'
                    : 'Already reported nearby?',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1F2937),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Confirming an existing report helps us prioritise it — the more '
                'people confirm, the higher it moves up the queue.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF6B7280),
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 16),
              // Bounded so three long-remark cards can never push the actions
              // off a small screen.
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final n in nearby) ...[
                        _nearbyReportCard(ctx, n),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, _kMineIsDifferent),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFD1D5DB)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text(
                    'No — mine is a different issue',
                    style: TextStyle(
                      color: Color(0xFF374151),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text(
                  'Go back and check my pin',
                  style: TextStyle(
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// One tappable existing-report card — tapping it confirms that report.
  Widget _nearbyReportCard(BuildContext ctx, _NearbyReport n) {
    final meta = [
      n.distanceLabel,
      if (n.createdAt != null) formatTimeAgo(n.createdAt!),
      if (n.barangay != null && n.barangay!.isNotEmpty) n.barangay!,
    ].join(' · ');

    return InkWell(
      onTap: () => Navigator.pop(ctx, n.id),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE5E7EB)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'RPT-${n.shortRef}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF6B7280),
                    letterSpacing: 0.4,
                  ),
                ),
                const Spacer(),
                if (n.reporterCount > 1)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${n.reporterCount} reports',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryBlue,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              n.remarks.isEmpty ? 'No description given.' : n.remarks,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: Color(0xFF1F2937),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              meta,
              style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'This is my issue — confirm it',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryBlue,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 14,
                  color: AppColors.primaryBlue,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Validation dialog ────────────────────────────────────────────────────────
  void _showValidationDialog(String message) {
    showAppDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        // Without a cap, the full-width button inside stretches the card across
        // the whole browser window. A phone screen is narrower than this, so
        // the constraint only ever bites on web/tablet.
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
                  color: Colors.orange.withValues(alpha: 0.10),
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

  Widget _buildDisclaimer(double width) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: width * 0.04),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: width * 0.035,
          vertical: width * 0.030,
        ),
        decoration: BoxDecoration(
          color: AppColors.orange.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(width * 0.03),
          border: Border.all(color: AppColors.orange.withValues(alpha: 0.30)),
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
                'Please ensure that all information submitted is accurate and truthful. False or misleading submissions may result in penalties or possible consequences.',
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

  // ── Submit button ────────────────────────────────────────────────────────────
  Widget _buildSubmitButton(double width) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: width * 0.04),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: (_isSubmitting || _processingPaths.isNotEmpty)
              ? null
              : _submitReport,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.green,
            disabledBackgroundColor: const Color(0xFFD1D5DB),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(width * 0.035),
            ),
            padding: EdgeInsets.symmetric(vertical: width * 0.042),
            elevation: 2,
            shadowColor: AppColors.green.withValues(alpha: 0.4),
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
                      : 'Submit Report',
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
