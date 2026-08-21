import 'package:flutter/material.dart';
import '../../shell/citizen_shell_dialogs.dart'
    show FormDialogGuard, kSplitDialogFullscreenBelow;
import '../../../../core/widgets/responsive_page.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/citizen_ui.dart';
import '../../../../core/widgets/Home/Quick-action/Web/quick_action_split_panel.dart';
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
import '../../../../core/theme/mobile_metrics.dart';

/// The split panel's SQUARE "Add file" tile — the first cell of the panel's
/// 4-column attachment grid, sized to match the file tiles beside it.
///
/// A private widget rather than a method so the hover flag is local state; the
/// form's own `setState` must not be spent on a pointer moving over a box.
/// Web-only by construction: it is built solely from the `splitPanel` branch,
/// and [MouseRegion] reports nothing without a real pointer anyway.

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

  String get distanceLabel => distanceM < 1000
      ? '$distanceM m away'
      : '${(distanceM / 1000).toStringAsFixed(1)} km away';
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
  Widget build(BuildContext context) => ReportIssueForm(username: username);
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
///
/// `splitPanel: true` renders the SAME sections as a two-column web panel — a
/// stepper over the working area on the left, a live summary and the buttons on
/// the right. Only the citizen web shell passes it. See [_splitPanelBody] for
/// why every section is still built on every step.
class ReportIssueForm extends StatefulWidget {
  final String username;
  final bool embedded;
  final FormDialogGuard? guard;

  /// Two-column web layout. Default false, and the default is what mobile, the
  /// native-tablet home body and the standalone route all get — none of them
  /// pass this, so their widget tree is unchanged.
  final bool splitPanel;

  /// Dismisses the hosting dialog. Only read in the [splitPanel] branch, whose
  /// rail owns the × and the Cancel button; the other two branches close
  /// through the dialog's own header or through `Navigator.pop`.
  final VoidCallback? onClose;

  const ReportIssueForm({
    super.key,
    required this.username,
    this.embedded = false,
    this.guard,
    this.splitPanel = false,
    this.onClose,
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

  // ── Split-panel step (web only) ───────────────────────────────────────────
  /// Which step the two-column web panel is showing. Read ONLY by the
  /// `widget.splitPanel` branch; mobile and the standalone route never look at
  /// it, so it cannot change what they render.
  ///
  /// This is a view index, not a wizard position: it decides which sections are
  /// VISIBLE, never which are built, and it gates nothing on submit.
  int _splitStep = 0;

  /// The working area's scroll position, so changing step can return it to the
  /// top. Web only: the [_splitScrollable] that attaches it is built solely
  /// from the `widget.splitPanel` branch, and an unattached controller costs a
  /// mobile build nothing.
  final ScrollController _splitScrollCtrl = ScrollController();

  static const List<String> _kSplitSteps = [
    'Category',
    'Location',
    'Details',
    'Review',
  ];

  /// Which PANE the stacked panel is showing: 0 = Report, 1 = Summary.
  ///
  /// Read ONLY by the `widget.splitPanel` branch, and within it only when the
  /// panel is stacked — side by side the summary is a rail beside the work and
  /// there is nothing to switch between. Mobile and the standalone route never
  /// look at it.
  ///
  /// ── A pane, not a step ───────────────────────────────────────────────────
  /// This is the one piece of state in the panel that is purely about what is
  /// on screen. [_splitStep] is where the citizen is in the form and is EARNED:
  /// `_splitStepGate` can refuse to move it. A tab is never refused, because
  /// looking at the recap is not progress and cannot fail. Keeping the two
  /// apart is why switching tabs does not touch `_splitStep`, why the buttons
  /// keep reading `_splitStep` rather than this, and why the two controls are
  /// drawn as visibly different things.
  int _splitTab = 0;

  static const List<String> _kSplitTabs = ['Report', 'Summary'];

  /// Inline error under the offending field on the current split-panel step,
  /// and which field it belongs under ('category' | 'location' | 'remarks' |
  /// 'attach').
  ///
  /// Set only when Continue is pressed on an unsatisfied step, cleared the
  /// moment the field it complains about changes. It never reaches
  /// `_validate()` or `_submitReport()` — those stay the sole authority on what
  /// may be filed, so a citizen who clicks the stepper straight to Review is
  /// still refused there by the existing dialog rather than by this.
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
    _splitScrollCtrl.dispose();
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
      _applyLocationResult(result);
    }
  }

  /// Folds a confirmed pick into the form's location state.
  ///
  /// Extracted so the pushed picker (mobile, the standalone route) and the
  /// inline picker (the web split panel's step 2) run byte-identical code —
  /// they differ only in how the map gets here, never in what it does.
  void _applyLocationResult(Map<String, dynamic> result) {
    setState(() {
      _pickedLatLng = result['latLng'] as LatLng?;
      _pickedBarangay = result['barangay'] as String?;
      _useCurrentLocation = result['useCurrentLocation'] as bool;
      _locationOutsideAparri = false;
      _locationPermissionDenied = false;
      // A confirmed location clears step 2's inline error, same as any other
      // field change clearing its own.
      _stepError = null;
    });
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

  // ══════════════════════════════════════════════════════════════════════════
  //  Split panel (citizen web only)
  // ══════════════════════════════════════════════════════════════════════════

  /// The two-column web layout.
  ///
  /// ── Every section is built on every step ─────────────────────────────────
  /// The four steps switch VISIBILITY, not construction: each group is wrapped
  /// in an [Offstage], which leaves the widget mounted, its element alive and
  /// its state intact while skipping layout and paint. So no TextEditingController
  /// is ever torn down mid-form, no picked file or lat/lng is dropped by moving
  /// between steps, and `_validate()` at submit sees exactly the same state it
  /// sees on mobile — including fields that are not currently on screen.
  ///
  /// ── The stepper gates nothing ────────────────────────────────────────────
  /// Continue simply advances the index and the numbers are clickable, so a
  /// citizen can reach Review with an empty category. That is on purpose: the
  /// existing `_validate()` is left as the single authority on what may be
  /// submitted, and Submit here calls the unmodified `_submitReport()`.
  ///
  /// ── The review step has no copy of the data ──────────────────────────────
  /// [_splitReviewStep] reads `_selectedCategory`, `_pickedBarangay`,
  /// `_remarksCtrl` and friends directly on each build — the very fields the
  /// inputs write to — so it cannot drift from them.
  Widget _splitPanelBody(double width) {
    // Rebuild the summary and the review as the citizen types. Scoped to this
    // branch rather than added as initState listeners, so mobile keeps its
    // existing rebuild behaviour untouched.
    return AnimatedBuilder(
      animation: Listenable.merge([
        _remarksCtrl,
        _streetDetailCtrl,
        _othersCtrl,
      ]),
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
        'Step 1 — What kind of issue is it?',
        'Pick the category that best describes the problem. Choose "Others" '
            'if none of them fit and tell us in a few words.',
      ),
      1 => (
        'Step 2 — Where is it?',
        'We use your location so the Municipality of Aparri knows where to '
            'send help. Pick a barangay manually if the detected spot is off.',
      ),
      2 => (
        'Step 3 — Describe it and add proof',
        'A short description and at least one photo or video. Photos taken '
            'with the camera carry a GPS stamp.',
      ),
      _ => (
        'Step 4 — Check before you send',
        'Everything below is what will be filed. Use the steps above to go '
            'back and change anything.',
      ),
    };
  }

  /// The four steps, stacked as [Offstage] siblings. Identical in both layouts —
  /// only what is wrapped AROUND it differs.
  Widget _splitStepStack(double width) {
    return Center(
      child: ConstrainedBox(
        // The location section still renders against the 480px
        // mobile-proportional scale, so the column is capped to keep it
        // from stretching into something that scale never anticipated.
        //
        // 700 does not bind at the dialog's own maximum (1160 wide
        // leaves the working area ~660), which is deliberate: the
        // category grid is meant to run the full width of the panel,
        // and a cap 40px inside it left a visible margin on both sides
        // that read as the content being narrower than its card.
        constraints: const BoxConstraints(maxWidth: 700),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Offstage, NOT `if` — see [_splitPanelBody]'s doc.
            Offstage(offstage: _splitStep != 0, child: _splitCategoryStep()),
            Offstage(
              offstage: _splitStep != 1,
              child: _splitLocationStep(width),
            ),
            Offstage(
              offstage: _splitStep != 2,
              child: Column(
                children: [
                  _buildRemarksSection(width, bare: true),
                  const SizedBox(height: 18),
                  _buildAttachSection(width, bare: true),
                  const SizedBox(height: 18),
                  _splitAnonymousRow(),
                ],
              ),
            ),
            Offstage(offstage: _splitStep != 3, child: _splitReviewStep(width)),
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
  ///
  ///   • The title and the dismiss control move into this head.
  ///   • The summary becomes the second of two PANES — "Report | Summary" —
  ///     rather than a column beside the work. See [_splitTab].
  ///
  /// The instruction block moves from the head into the scrolling body: at a
  /// phone's width it is four lines, and four lines of advice pinned over a
  /// step is most of the room the step has to be filled in.
  Widget _splitLeftPanel(double width, bool stacked) {
    final (String title, String body) = _splitStepCopy();

    // Phone-web, derived LOCALLY and only where it is used: `stacked` short
    // circuits, so the side-by-side path never even reads the size and does not
    // gain a dependency on it. It is the host's own fullscreen threshold — one
    // definition of 600, not a second copy that can drift out of step with the
    // presentation it describes. Deliberately NOT the 480-clamped `width` this
    // method already carries: that is the mobile proportional scale the shared
    // sections are drawn against, and reusing it as a breakpoint would tie the
    // two together.
    final bool phone =
        stacked &&
        MediaQuery.sizeOf(context).width < kSplitDialogFullscreenBelow;

    return QaPanelCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        // Fit the card to the step, not to the height on offer. Paired with
        // [QaSplitPanel]'s measuring row: that row asks this column how tall it
        // wants to be, and a `MainAxisSize.max` column would answer "all of it"
        // and put the dead space straight back. The `Expanded` below still
        // gives the working area every pixel that is left over when a step IS
        // taller than the dialog, so the scroll behaviour is unchanged.
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Zone 1: the fixed head ───────────────────────────────────────
          if (stacked) ...[
            // Title and dismiss control in one row — the rail's own header
            // widget, reused rather than rebuilt, so it is the same control in
            // both layouts. Fullscreen it wears a back chevron instead of an ×,
            // which is the same tap: see [QaRailHeader.useBackArrow].
            QaRailHeader(
              title: 'Report an Issue',
              onClose: widget.onClose ?? () {},
              useBackArrow: phone,
            ),
            const SizedBox(height: 14),
            // The pane switcher. Deliberately NOT the stepper — see [_splitTab]
            // for why the two controls have to stay tellable apart.
            QaSegmentedTabs(
              labels: _kSplitTabs,
              selected: _splitTab,
              onSelect: (i) => setState(() => _splitTab = i),
            ),
            const SizedBox(height: 14),
          ] else ...[
            const QaPanelTitle('Report an Issue'),
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
                      // Offstage, NOT `if` — for the reason the steps are, and
                      // one more besides. `LocationPickerScreen` seeds its GPS
                      // toggle to false in initState, so a picker rebuilt from
                      // scratch after a glance at the Summary would silently
                      // flick "Use my current location" back off. Keeping the
                      // pane mounted is what makes the tabs cost nothing.
                      Offstage(
                        offstage: _splitTab != 0,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // The stepper is UNCHANGED — same widget, same
                            // gating, same messages. `compact` only lets its
                            // columns narrow when the row cannot seat four
                            // 82px ones; above that it is pixel-identical.
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
  /// ── Why there is no longer a stacked fork ────────────────────────────────
  /// This used to hand the stacked layout its child bare, because stacked meant
  /// "inside the shell's one long scroll view", where an `Expanded` has no
  /// height to expand into. It does not mean that any more: [QaSplitPanel]'s
  /// stacked branch is three bounded zones, and this is zone 2 of them. So both
  /// layouts arrive here with a bounded height and both scroll the same way —
  /// which is also what stops the rail's own scroll view from ever ending up
  /// nested inside a second one.
  ///
  /// ── Where a short step's surplus goes ────────────────────────────────────
  /// The frame is a fixed [kQaSplitPanelHeight] and Category needs less than
  /// that, so something has to hold the difference. `Expanded` gives the scroll
  /// view the whole remaining column, and the `minHeight` below makes its
  /// CONTENT at least that tall — so the [Center] already wrapping the step
  /// splits the surplus evenly above and below instead of letting it pool at
  /// the bottom as one dead band. A step that overruns the frame is unaffected:
  /// its content is taller than the minimum, and it simply scrolls.
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
  /// All four steps share ONE scroll view (they are stacked as [Offstage]
  /// siblings), so without this a citizen who scrolled to the bottom of the
  /// location step arrives at Review already scrolled past its first field —
  /// with nothing on screen to explain why the step starts in the middle.
  void _goToSplitStep(int step) {
    setState(() => _splitStep = step);
    if (_splitScrollCtrl.hasClients) _splitScrollCtrl.jumpTo(0);
  }

  // ── Per-step gates ────────────────────────────────────────────────────────

  /// What [step] still needs before it may be left, or null if it is
  /// satisfied. Returns the message and the field it belongs under.
  ///
  /// The one authority on step-to-step progress: both ways forward consult it —
  /// [_continueSplitStep] for the step in hand, [_onStepperTap] for every step
  /// it would skip over — so there is exactly one set of rules and one set of
  /// words for them.
  ///
  /// ── Relationship to `_validate()` ────────────────────────────────────────
  /// These are the SAME conditions `_validate()` checks, split across the steps
  /// that own them and worded identically, so a citizen never sees one message
  /// here and a different one at submit. `_validate()` itself is untouched and
  /// still runs in full on Submit — it remains the only authority on what may
  /// actually be FILED.
  ///
  /// One asymmetry is worth knowing about: step 3 requires a non-empty
  /// description, which `_validate()` does NOT — mobile can still file without
  /// one. Now that the stepper gates too, the panel has no route to Review that
  /// skips it, so on web a description is effectively required. That is a
  /// stricter panel, not a changed submit rule; `_validate()` is untouched, and
  /// making description mandatory at submit for every client would be a
  /// separate decision.
  (String message, String field)? _splitStepGate(int step) {
    switch (step) {
      case 0:
        // Mirrors the first two checks in _validate().
        if (_selectedCategory == null) {
          return ('Please select an issue category.', 'category');
        }
        if (_selectedCategory == 'others' && _othersCtrl.text.trim().isEmpty) {
          return ('Please specify the category under "Others".', 'category');
        }
      case 1:
        // Mirrors _validate()'s location check.
        if (_pickedLatLng == null || _pickedBarangay == null) {
          return ('Please set a location before continuing.', 'location');
        }
      case 2:
        if (_remarksCtrl.text.trim().isEmpty) {
          return ('Please describe the issue before continuing.', 'remarks');
        }
        // Mirrors _validate()'s attachment and processing checks.
        if (_attachedFiles.isEmpty) {
          return ('Please attach at least one photo or video.', 'attach');
        }
        if (_processingPaths.isNotEmpty) {
          return ('Please wait for your photo to finish processing.', 'attach');
        }
    }
    return null;
  }

  /// A tap on one of the stepper's numbers.
  ///
  /// ── Backwards is free, forwards is earned ────────────────────────────────
  /// Going back to a step already passed is just re-reading your own answer,
  /// so it is never blocked. Jumping FORWARD past an unfinished step is not:
  /// the numbers used to be a plain view switcher, which meant a citizen could
  /// land on Review with no category, no location and no photo, press Submit,
  /// and only then be told — four steps from where the problem actually was.
  ///
  /// So a forward tap walks the steps in between and stops at the first one
  /// that is not satisfied. It does not just refuse: it MOVES to that step and
  /// raises the same message [_continueSplitStep] raises, under the same field,
  /// because a tap that appears to do nothing reads as a broken control.
  ///
  /// [_splitStepGate] is the single source of those rules — this method adds no
  /// conditions and no wording of its own, so the stepper and Continue can
  /// never disagree about what is missing.
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
      // Show it where the offending field actually is. Already being there is
      // the common case (tapping ahead from an empty step), and jumping then
      // would only reset the scroll for nothing.
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
  /// citizen fixes the field, without any shared add/remove handler having to
  /// know this error exists — which is why picking a photo or picking a
  /// barangay makes it disappear even though `_pickMedia` and the attachment
  /// tile were left alone.
  Widget _splitFieldError(String field) {
    if (!_errorOn(field)) return const SizedBox.shrink();
    final live = _splitStepGate(_splitStep);
    if (live == null || live.$2 != field) return const SizedBox.shrink();
    return QaFieldError(_stepError);
  }

  // ── Step 1: category ──────────────────────────────────────────────────────

  /// The category grid, sized to the PANEL rather than to the 480px mobile
  /// scale, with the numbered section card dropped — the stepper already says
  /// this is step 1, so a second "1. Select Issue Category" heading inside it
  /// was saying the same thing twice.
  ///
  /// Reads and writes `_selectedCategory` and `_othersCtrl`, the same two
  /// fields the mobile grid writes to; `_categories` is the same list. Only the
  /// tiles are different, and only because [QaChoiceTile] adds a hover state
  /// that has no meaning on touch.
  Widget _splitCategoryStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const QaFieldLabel(
          'Select a category',
          hint: 'Required',
          hintColor: CitizenUi.danger,
        ),
        LayoutBuilder(
          builder: (context, c) {
            // Three across, filling whatever the panel gives us. The tile is
            // sized from that width rather than from a viewport fraction, so
            // it stays compact as the panel grows instead of ballooning.
            //
            // Category is the SHORTEST step and the panel's frame is fixed,
            // so these tiles are what stands between "a grid of choices" and
            // "six small boxes floating in an empty card". They are sized to
            // FILL: at the panel's ~660px the ratio draws a 210 × 200 card and
            // the two rows plus the label come to within ~85px of the working
            // area, which the step then splits evenly above and below. Drop
            // the ratio and that 85 becomes a visible hole under the banner —
            // the grid has to earn the height, the spacing cannot fake it.
            //
            // The FLOOR is not cosmetic: a narrow panel wraps the longer
            // labels ("Environment & Pollution") onto two lines, and the 64px
            // icon disc, a 12px gap, two 16px label lines and 24px of tile
            // padding come to 133. Below the floor the tile overflows, which is
            // what the width sweep in report_split_panel_test.dart catches.
            // ── Why the count is not always three ────────────────────────
            // The floor above stops the tile getting too SHORT; nothing was
            // stopping it getting too NARROW. [QaChoiceTile] draws a fixed
            // 64px icon disc inside 10px of horizontal padding a side, so a
            // tile below ~84px overflows sideways no matter how tall it is —
            // and three across reaches that at ~280px of column, which is a
            // phone in the fullscreen panel. Dropping to two there keeps the
            // tile above its own minimum. The threshold is above the 280 it
            // has to clear so the last usable 3-up row is not a hairline
            // fit; every side-by-side width (~620–700) is far above it and
            // still draws three.
            final cols = c.maxWidth < 300 ? 2 : 3;
            const gap = 14.0;
            final tileW = (c.maxWidth - gap * (cols - 1)) / cols;
            final tileH = (tileW * 0.95).clamp(138.0, 205.0);

            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final cat in _categories)
                  SizedBox(
                    width: tileW,
                    height: tileH,
                    child: QaChoiceTile(
                      // Pinned to the CATEGORY, not to its position. Without a
                      // key the element at index 2 is whatever the grid builds
                      // at index 2, so a rebuild can hand a tile's State — and
                      // with it, its live hover flag and running animation — to
                      // a different tile. That is what made hovering flash.
                      key: ValueKey(cat['key']),
                      selected: _selectedCategory == cat['key'],
                      // Same handler as the mobile grid, plus clearing this
                      // step's inline error now that the field has changed.
                      onTap: () => setState(() {
                        _selectedCategory = cat['key'] as String;
                        _clearStepError('category');
                      }),
                      // The grid labels carry a hard wrap sized for a phone
                      // tile; the web tile is wider, so let it flow.
                      label: (cat['label'] as String).replaceAll('\n', ' '),
                      icon: Image.asset(
                        cat['icon'] as String,
                        width: 34,
                        height: 34,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) =>
                            Icon(cat['fallbackIcon'] as IconData),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        if (_selectedCategory == 'others') ...[
          const SizedBox(height: 16),
          const QaFieldLabel('Specify the category'),
          TextField(
            controller: _othersCtrl,
            maxLength: 50,
            style: const TextStyle(fontSize: 13.5),
            onChanged: (_) => setState(() => _clearStepError('category')),
            decoration: _splitInputDecoration(
              hint: 'Describe it in a few words…',
            ),
          ),
        ],
        _splitFieldError('category'),
      ],
    );
  }

  // ── Step 2: location, hosted inline ───────────────────────────────────────

  /// The Edit Location picker, rendered INSIDE the panel instead of pushed as a
  /// route.
  ///
  /// Same widget, same GPS logic, same barangay list — the only difference is
  /// that `onConfirm` is non-null, so a pick hands the result map straight to
  /// [_applyLocationResult] rather than popping a route. Nothing here dismisses
  /// the dialog or navigates.
  ///
  /// ── Why the key is now constant ──────────────────────────────────────────
  /// It used to carry the current pick, which rebuilt the picker from scratch
  /// on every confirm so its `initialPosition`/`initialBarangay` were re-read.
  /// Now that a pick SAVES ITSELF, that key would fire on every barangay tap —
  /// throwing away the picker's state, replaying its entry animation, and
  /// (because a fresh picker seeds `_useCurrentLocation` to false) silently
  /// flicking the GPS toggle back off after a GPS pick. The picker keeps its
  /// own state instead and re-seeds from `didUpdateWidget` when the form's
  /// location changes underneath it — the auto-fetch on open being the case
  /// that matters.
  Widget _splitLocationStep(double width) {
    final hasLocation = _pickedLatLng != null && _pickedBarangay != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LocationPickerScreen(
          key: const ValueKey('inline-picker'),
          initialPosition: _pickedLatLng,
          initialBarangay: _pickedBarangay,
          onConfirm: _applyLocationResult,
        ),
        _splitFieldError('location'),

        // The optional street detail, which the mobile section also shows only
        // once a location resolves. Same `_streetDetailCtrl`, at panel scale.
        if (hasLocation) ...[
          const SizedBox(height: 18),
          const QaFieldLabel(
            'Street name & detailed location',
            hint: 'Optional',
          ),
          TextField(
            controller: _streetDetailCtrl,
            maxLines: 2,
            style: const TextStyle(fontSize: 13.5),
            decoration: _splitInputDecoration(
              hint: 'e.g. Near the church, beside the market…',
            ),
          ),
        ],
      ],
    );
  }

  // ── Step 3: details ───────────────────────────────────────────────────────

  /// Shared field chrome for the panel's inputs, so the textarea, the "others"
  /// box and anything added later cannot drift apart.
  InputDecoration _splitInputDecoration({required String hint}) =>
      qaInputDecoration(hint: hint);

  /// The description field at panel scale. Same `_remarksCtrl`, same
  /// `maxLength: 1000` (the 0/1000 counter is Flutter's, drawn from it), same
  /// `onChanged` — only the metrics differ.
  Widget _splitRemarksField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const QaFieldLabel('Describe the issue', hint: 'Required'),
        TextField(
          controller: _remarksCtrl,
          maxLength: 1000,
          maxLines: 6,
          style: const TextStyle(fontSize: 13.5, height: 1.45),
          onChanged: (_) => setState(() => _clearStepError('remarks')),
          decoration: _splitInputDecoration(
            hint: 'What is the problem, and where exactly is it?',
          ),
        ),
        _splitFieldError('remarks'),
      ],
    );
  }

  /// Step 4 — the DETAILED render of the report, in the left working area.
  ///
  /// ── Why the detail lives on the left ─────────────────────────────────────
  /// The left panel is the main area on every step and the rail is the summary
  /// on every step; Review keeps that. So this is the full, rendered report —
  /// the category as its own tile, the real description in a field-shaped box,
  /// the actual photo thumbnails — while the rail goes on showing the same
  /// compact Category/Location/Details/Attachments list it shows on steps 1–3.
  /// Nothing swaps sides, and the 1.7 : 1 ratio is the panel's, not the step's.
  ///
  /// Every value below is read straight off the fields the inputs write to
  /// (`_selectedCategory`, `_pickedBarangay`, `_streetDetailCtrl`,
  /// `_remarksCtrl`, `_attachedFiles`, `_submitAnonymously`), so the detail and
  /// the rail are two renderings of one state, not two copies of it.
  Widget _splitReviewStep(double width) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Category, as its selected tile ────────────────────────────────
        const QaFieldLabel('Category'),
        _splitReviewCategoryTile(),
        const SizedBox(height: 16),

        // ── Location ──────────────────────────────────────────────────────
        const QaFieldLabel('Location'),
        _splitReviewBox(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _useCurrentLocation
                    ? Icons.my_location_rounded
                    : Icons.location_on_rounded,
                size: 18,
                color: _pickedBarangay == null
                    ? CitizenUi.textFaint
                    : CitizenUi.accent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _pickedBarangay ?? 'No location set',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        fontStyle: _pickedBarangay == null
                            ? FontStyle.italic
                            : FontStyle.normal,
                        color: _pickedBarangay == null
                            ? CitizenUi.textFaint
                            : CitizenUi.textPrimary,
                      ),
                    ),
                    if (_pickedBarangay != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        _useCurrentLocation
                            ? 'Via GPS · Aparri, Cagayan'
                            : 'Aparri, Cagayan',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: CitizenUi.textFaint,
                        ),
                      ),
                    ],
                    // The optional street detail, when one was typed.
                    if (_streetDetailCtrl.text.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        _streetDetailCtrl.text.trim(),
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          color: CitizenUi.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Description, in a box shaped like the field it was typed in ───
        const QaFieldLabel('Description'),
        _splitReviewBox(
          minHeight: 76,
          child: SelectableText(
            _remarksCtrl.text.trim().isEmpty
                ? 'No description written'
                : _remarksCtrl.text.trim(),
            style: TextStyle(
              fontSize: 13.5,
              height: 1.45,
              fontStyle: _remarksCtrl.text.trim().isEmpty
                  ? FontStyle.italic
                  : FontStyle.normal,
              color: _remarksCtrl.text.trim().isEmpty
                  ? CitizenUi.textFaint
                  : CitizenUi.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ── Attachments, as the real thumbnails ───────────────────────────
        QaFieldLabel(
          'Attachments',
          hint: _splitAttachmentLabel() ?? 'Nothing attached',
        ),
        if (_attachedFiles.isEmpty)
          _splitReviewBox(
            child: const Text(
              'No photo or video attached',
              style: TextStyle(
                fontSize: 12.5,
                fontStyle: FontStyle.italic,
                color: CitizenUi.textFaint,
              ),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            // Sized by EXTENT, not by column count. A fixed four-across grid
            // stretches its thumbnails as the panel widens — at the panel's
            // ~660px that is a 157px tile, which on a step whose job is to be
            // read at a glance is a photo album, not a summary. Capping the
            // tile instead keeps the row compact and, since the form allows at
            // most six files, fits every attachment on ONE row here — which is
            // also what keeps Review inside the panel's fixed height.
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 120,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1,
            ),
            itemCount: _attachedFiles.length,
            // The same tile step 3 draws — real previews, video thumbnails and
            // the tap-to-enlarge viewers, not a second thumbnail widget.
            itemBuilder: (context, i) => _attachFileTile(i, width),
          ),
        const SizedBox(height: 16),

        // ── Submitted as ──────────────────────────────────────────────────
        const QaFieldLabel('Submitted as'),
        _splitReviewBox(
          child: Row(
            children: [
              Icon(
                _submitAnonymously
                    ? Icons.visibility_off_rounded
                    : Icons.person_rounded,
                size: 18,
                color: CitizenUi.accent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _submitAnonymously ? 'Anonymous' : widget.username,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: CitizenUi.textPrimary,
                  ),
                ),
              ),
              if (_submitAnonymously)
                const Text(
                  'Name hidden from the public feed',
                  style: TextStyle(fontSize: 11.5, color: CitizenUi.textFaint),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// A field-shaped read-only container — same border, radius and padding as
  /// [_splitInputDecoration], so a reviewed value reads as the input it came
  /// from rather than as plain text on the card.
  Widget _splitReviewBox({required Widget child, double? minHeight}) =>
      QaReviewBox(minHeight: minHeight, child: child);

  /// The chosen category drawn as its own tile — the same illustration and
  /// label the step-1 grid uses, in the accent-selected treatment, but inert.
  Widget _splitReviewCategoryTile() {
    final key = _selectedCategory;
    if (key == null) {
      return _splitReviewBox(
        child: const Text(
          'No category selected',
          style: TextStyle(
            fontSize: 12.5,
            fontStyle: FontStyle.italic,
            color: CitizenUi.textFaint,
          ),
        ),
      );
    }
    final def = _categories.firstWhere(
      (c) => c['key'] == key,
      orElse: () => const <String, dynamic>{},
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: CitizenUi.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(CitizenUi.controlRadius),
        border: Border.all(color: CitizenUi.accent, width: 2),
      ),
      child: Row(
        children: [
          if (def['icon'] != null)
            Image.asset(
              def['icon'] as String,
              width: 26,
              height: 26,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => Icon(
                def['fallbackIcon'] as IconData? ?? Icons.flag_rounded,
                size: 26,
                color: CitizenUi.accent,
              ),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              // Same derivation the rail uses, so the tile and the rail can
              // never disagree about which category this is.
              _splitCategoryLabel() ?? '',
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: CitizenUi.accent,
              ),
            ),
          ),
          const Icon(
            Icons.check_circle_rounded,
            size: 18,
            color: CitizenUi.accent,
          ),
        ],
      ),
    );
  }

  // ── Summary values — derived, never stored ────────────────────────────────

  String? _splitCategoryLabel() {
    final key = _selectedCategory;
    if (key == null) return null;
    if (key == 'others') {
      final other = _othersCtrl.text.trim();
      return other.isEmpty ? 'Others' : 'Others — $other';
    }
    final match = _categories.firstWhere(
      (c) => c['key'] == key,
      orElse: () => const {'label': ''},
    );
    // The grid labels carry a hard wrap for the tile; flatten it for a line.
    return (match['label'] as String).replaceAll('\n', ' ').trim();
  }

  String? _splitLocationLabel() {
    if (_pickedBarangay == null) return null;
    final street = _streetDetailCtrl.text.trim();
    return street.isEmpty ? _pickedBarangay : '$_pickedBarangay — $street';
  }

  String? _splitAttachmentLabel() {
    if (_attachedFiles.isEmpty) return null;
    final n = _attachedFiles.length;
    final pending = _processingPaths.length;
    final base = '$n file${n == 1 ? '' : 's'} attached';
    return pending == 0 ? base : '$base · $pending still processing';
  }

  // ── Right rail ────────────────────────────────────────────────────────────

  /// The four summary rows and the step's callout.
  ///
  /// One block, two homes: the rail renders it side by side, and the stacked
  /// panel renders THE SAME widget inside its collapsible Summary section.
  /// Every value is read live off the form's own fields on each build, so the
  /// two placements cannot drift — there is no second copy of anything here.
  Widget _splitSummaryBlock() {
    final isLast = _splitStep == _kSplitSteps.length - 1;
    final waitingOnMedia = _processingPaths.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Four ruled rows, one per field the form collects, in the order the
        // steps collect them. The glyphs are picked to be recognisable at
        // 20px and grey — a grid for the category chooser, a pin for the
        // map, ruled lines for the written description, a clip for files.
        QaSummaryRow(
          icon: Icons.grid_view_rounded,
          label: 'CATEGORY',
          value: _splitCategoryLabel(),
        ),
        QaSummaryRow(
          icon: Icons.place_rounded,
          label: 'LOCATION',
          value: _splitLocationLabel(),
        ),
        QaSummaryRow(
          icon: Icons.format_list_bulleted_rounded,
          label: 'DETAILS',
          value: _remarksCtrl.text,
          maxLines: 2,
        ),
        QaSummaryRow(
          icon: Icons.attach_file_rounded,
          label: 'ATTACHMENTS',
          value: _splitAttachmentLabel(),
        ),

        const SizedBox(height: 26),
        // Three states, most urgent first. On Review the info line gives way
        // to the truthfulness warning — the one thing a citizen should read
        // immediately before pressing Submit. Same sentence as the mobile
        // disclaimer, cut to one line for the rail; the left panel no longer
        // repeats it, since the warning belongs beside the button it warns
        // about.
        if (waitingOnMedia)
          const QaCallout(
            icon: Icons.hourglass_top_rounded,
            accent: AppColors.orange,
            text:
                'A photo is still being prepared. Submit unlocks once it '
                'finishes.',
          )
        else if (isLast)
          const QaCallout(
            icon: Icons.gpp_maybe_rounded,
            accent: CitizenUi.warn,
            text:
                'False or misleading reports may carry penalties. Check the '
                'details before submitting.',
          )
        else
          const QaCallout(
            icon: Icons.shield_outlined,
            accent: CitizenUi.accent,
            text:
                'Your report goes to the Municipality of Aparri for triage. '
                'You can track its status under My Reports.',
          ),
      ],
    );
  }

  /// Continue/Submit, Back and Cancel.
  ///
  /// Extracted for the same reason as [_splitSummaryBlock]: side by side these
  /// sit at the foot of the rail, stacked they ARE the pinned action zone, and
  /// neither placement may fork what the buttons do.
  /// [compact] is the PINNED zone's sizing — see [QaActionStack.compact]. The
  /// buttons, their order, their handlers and their disabled rules are the same
  /// either way: only the metrics differ, so there is still one answer to what
  /// each button does.
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
            label: waitingOnMedia ? 'Finishing photo…' : 'Submit Report',
            icon: Icons.send_rounded,
            color: AppColors.green,
            busy: busy,
            compact: compact,
            // The existing handler, unmodified — it runs `_validate()`
            // first, so an incomplete form is refused here exactly as it
            // is on mobile.
            onTap: waitingOnMedia ? null : _submitReport,
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
  /// ── Side by side (`stacked == false`) ────────────────────────────────────
  /// The full rail, exactly as before: header, summary, callout, buttons, all
  /// inside a [SingleChildScrollView]. That scroll view is not decoration. The
  /// rail is drawn to the panel's FIXED height, so its content cannot simply
  /// grow when it needs more room — and on Review it needs the most, carrying
  /// three buttons instead of two. At a narrow rail (a ~1200px window, where
  /// the values start wrapping onto second lines) that ran a few pixels past
  /// the card. Scrolling is the honest fallback: on any normal window there is
  /// nothing to scroll, and where there is, the Cancel button stays reachable
  /// instead of being clipped. The panel's ScrollConfiguration keeps the bar
  /// itself hidden.
  ///
  /// ── Stacked (`stacked == true`) ──────────────────────────────────────────
  /// The rail is reduced to the ACTION ZONE and returned BARE — a card holding
  /// the buttons and nothing else, no scroll view of its own.
  ///
  /// Bare is not a tidy-up, it is the point. Stacked, [QaSplitPanel] pins this
  /// card to the bottom of the panel while the working area scrolls above it;
  /// a scroll view here would be a second scrollable sharing an edge with the
  /// first, and a drag that started on the buttons would be arbitrated between
  /// them instead of doing the obvious thing. The header and the summary are
  /// not dropped either — the working card takes them over (see
  /// [_splitLeftPanel]), so nothing this rail carried has been lost.
  ///
  /// ── Why the Summary pane has no buttons ──────────────────────────────────
  /// The buttons act on the STEP ("Continue" from Location to Details), and the
  /// Summary pane is not a step — it is a glance at what has been filled in.
  /// Leaving Continue under it would invite the reading that it continues from
  /// the summary, and Submit under a read-only recap is worse: it would look
  /// like the recap is the thing being confirmed. So the zone goes away with
  /// the pane, and comes back exactly as it was — the buttons never stopped
  /// reading `_splitStep`, so nothing about the wizard moved while it was gone.
  Widget _splitRightRail(bool stacked) {
    if (stacked) {
      if (_splitTab != 0) return const SizedBox.shrink();
      // Tighter chrome than the rail's 20 a side: this card is a bar, and every
      // pixel of padding on it is a pixel the step above loses. The border and
      // radius stay, so it still reads as one of the panel's cards.
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
          border: Border.all(color: CitizenUi.sharedBorder),
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
          border: Border.all(color: CitizenUi.sharedBorder),
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
                      borderSide: const BorderSide(
                        color: CitizenUi.sharedBorder,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(width * 0.025),
                      borderSide: const BorderSide(
                        color: CitizenUi.sharedBorder,
                      ),
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
                  borderSide: const BorderSide(color: CitizenUi.sharedBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(width * 0.025),
                  borderSide: const BorderSide(color: CitizenUi.sharedBorder),
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
        borderColor: CitizenUi.sharedBorder,
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
      borderColor: CitizenUi.sharedBorder,
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
  /// [bare] true drops the numbered section card and sizes the field for the
  /// web panel instead of the 480px mobile scale — same controller, same
  /// `maxLength: 1000` (which is what draws the 0/1000 counter), same
  /// `onChanged`. Only the citizen web split panel passes it.
  Widget _buildRemarksSection(double width, {bool bare = false}) {
    if (bare) return _splitRemarksField();
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
            borderSide: const BorderSide(color: CitizenUi.sharedBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(width * 0.025),
            borderSide: const BorderSide(color: CitizenUi.sharedBorder),
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

  /// One attached file's square tile — preview or video thumbnail, the
  /// processing reveal, and the delete button.
  ///
  /// Extracted verbatim from the mobile grid's itemBuilder so the web panel's
  /// 4-column square grid can lay the SAME tile out differently without a
  /// second copy of the preview, reveal or delete behaviour. Both grids call
  /// this; only the surrounding delegate differs.
  Widget _attachFileTile(int index, double width) {
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
                : Image(image: pickedImageProvider(file), fit: BoxFit.cover),
          ),
          // Bottom-to-top reveal while the GPS stamp bakes; it fills to the top
          // the moment processing completes.
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
                onTap: () => setState(() => _attachedFiles.removeAt(index)),
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

    // ── The panel goes straight to the browser's file picker ────────────────
    // On the web there is no camera path and no separate photo/video library
    // to choose between — both branches of the chooser sheet end in the same
    // OS file dialog. Asking "photos or video?" first is a pop-up on top of a
    // pop-up that only makes the citizen pick the accept filter by hand, and
    // gets it wrong if they meant the other one. `pickMultipleMedia` opens
    // that dialog directly with `image/*,video/*`, so one click reaches the
    // files and either kind can be selected.
    //
    // Mobile is untouched: it keeps the sheet, because there the choice is
    // real — camera capture is a genuinely different source, and it is the one
    // that produces a GPS-stamped photo.
    if (widget.splitPanel) {
      final picked = await _picker.pickMultipleMedia(limit: remaining);
      await _acceptPickedMedia(picked);
      return;
    }

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

    await _acceptPickedMedia(picked);
  }

  /// Size-checks a set of freshly picked files and adds what passes.
  ///
  /// Extracted verbatim from [_pickMedia] so the panel's direct file-picker
  /// path and the sheet's gallery/video paths share one set of limits and one
  /// message — the caller only decides how the files were chosen.
  Future<void> _acceptPickedMedia(List<XFile> picked) async {
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
          )
          .then((data) {
            if (data != null) _thumbCache[file.path] = data;
          })
          .catchError((_) {}),
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
  /// [bare] true drops the numbered section card and swaps the tall mobile
  /// dropzone for a web-sized one. The attachment GRID below is deliberately
  /// left on the shared path — it carries the processing reveal, the delete
  /// buttons, the video thumbnails and the preview taps, and none of that is
  /// layout worth forking. `_maxFiles`, `_pickMedia` and every limit are
  /// untouched either way.
  Widget _buildAttachSection(double width, {bool bare = false}) {
    if (bare) return _splitAttachGrid(width);

    final slotCount = _attachedFiles.length < _maxFiles
        ? _attachedFiles.length + 1
        : _maxFiles;

    final dropzone = GestureDetector(
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
    );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        dropzone,
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
              return _attachFileTile(index, width);
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
    );

    if (bare) return _splitAttachGrid(width);

    return _sectionCard(
      width: width,
      title: '4. Attach Image / Video (Required)',
      child: body,
    );
  }

  /// The panel's attachment area: one square "Add file" tile followed by the
  /// attached files as square tiles, four across.
  ///
  /// The tiles themselves are [_attachFileTile] — the same previews, video
  /// thumbnails, processing reveal and delete buttons the mobile grid draws.
  /// Only the grid delegate and the leading tile are different.
  Widget _splitAttachGrid(double width) {
    final canAdd = _attachedFiles.length < _maxFiles;
    // Leading dropzone tile, then one tile per file.
    final itemCount = (canAdd ? 1 : 0) + _attachedFiles.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const QaFieldLabel('Photos or video', hint: 'Required — at least one'),
        // ── Reflow, don't shrink ────────────────────────────────────────────
        // Four across was hard-coded, which is fine at the panel's ~620px and
        // wrong below it: the cells are square, so a narrowing column drove the
        // TILE down with it, and the dropzone's icon + "Add file" + "n/6" stack
        // needs ~57px of height before it overflows its own cell. Sized by
        // EXTENT instead, exactly as the Review grid is (see
        // [_splitReviewStep]), the grid drops a column rather than shrinking
        // what is in it.
        //
        // ── Why 170 ─────────────────────────────────────────────────────────
        // The delegate takes `ceil(width / (extent + spacing))` columns, so the
        // number chosen decides where the count CHANGES. 170 puts the 4→5
        // boundary at 720px of grid — above the 700 the working column is
        // capped at — so every side-by-side width still draws exactly four,
        // at exactly the tile size it drew before. Below, the boundaries fall
        // where the tile would otherwise start crowding: 3 across under ~540,
        // 2 under ~360.
        //
        // It also sets the tile's FLOOR, which is the dropzone's real
        // protection. The smallest tile this can produce is just past a
        // boundary — ~85px, at the width where two columns first fit — and 85
        // clears the 57px the dropzone's stack needs with room to spare. The
        // [FittedBox] in [QaDropzoneTile] is the backstop under that.
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
                count: _attachedFiles.length,
                max: _maxFiles,
                onTap: _pickMedia,
              );
            }
            return _attachFileTile(canAdd ? index - 1 : index, width);
          },
        ),
        const SizedBox(height: 8),
        const Text(
          'Image: JPG, PNG (Max. 10MB)  ·  Video: MP4 (Max. 50MB)',
          style: TextStyle(fontSize: 11.5, color: CitizenUi.textFaint),
        ),
        _splitFieldError('attach'),
      ],
    );
  }

  /// "Submit anonymously" as a single compact row.
  ///
  /// Writes the same `_submitAnonymously` field and goes through the same
  /// `_showAnonymousConsentDialog` on the way on, so the consent copy a citizen
  /// must read is identical to mobile's — only the row around it is smaller.
  Widget _splitAnonymousRow() {
    return QaAnonymousRow(
      value: _submitAnonymously,
      // Same gate as the mobile card: turning it ON asks for consent first,
      // turning it OFF is immediate.
      onChanged: (v) {
        if (v) {
          _showAnonymousConsentDialog();
        } else {
          setState(() => _submitAnonymously = false);
        }
      },
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
          border: Border.all(color: CitizenUi.sharedBorder),
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
      return List<Map<String, dynamic>>.from(
        rows as List,
      ).map(_NearbyReport.fromRow).toList();
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
          supabase.functions
              .invoke(
                'check-ai-image',
                body: {
                  'bucket': 'report-media',
                  'path': mediaItems[i]['path'],
                  'table': 'report_media',
                  'id': inserted['id'],
                },
              )
              .ignore(); // swallow errors — never disturb the submission flow
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
          border: Border.all(color: CitizenUi.sharedBorder),
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
