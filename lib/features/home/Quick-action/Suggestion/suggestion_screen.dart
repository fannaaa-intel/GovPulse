import 'package:flutter/material.dart';
import '../../../../core/widgets/responsive_page.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/modal/media_picker_sheet.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'dart:typed_data';
import 'package:video_player/video_player.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../Report/location_picker_screen.dart';
import '../../../../core/widgets/Home/Newsfeed/rate_limit_dialogs.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/services/gps_stamp_service.dart';
import '../../../../core/widgets/reveal_loading.dart';

// ── Video preview dialog (same as Report) ─────────────────────────────────────
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
    _controller = VideoPlayerController.file(File(widget.file.path));
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

class SuggestionScreen extends StatefulWidget {
  final String username;
  const SuggestionScreen({super.key, required this.username});

  @override
  State<SuggestionScreen> createState() => _SuggestionScreenState();
}

class _SuggestionScreenState extends State<SuggestionScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entryCtrl;

  // ── Form state ─────────────────────────────────────────────────────────────
  String? _selectedCategory;
  final TextEditingController _othersCtrl = TextEditingController();
  final TextEditingController _detailsCtrl = TextEditingController();
  final TextEditingController _streetDetailCtrl = TextEditingController();
  bool _submitAnonymously = false;
  bool _isSubmitting = false;
  final List<XFile> _attachedFiles = [];
  static const int _maxFiles = 6;
  final ImagePicker _picker = ImagePicker();
  bool _consentInEnglish = true;

  /// Paths of camera-captured attachments that carry a baked-in GPS stamp.
  /// Everything else (gallery photos, videos) is an unverified upload.
  final Set<String> _gpsVerifiedPaths = {};

  /// Paths of attachments still being processed — camera photos baking a GPS
  /// stamp, gallery images decoding, or videos generating a thumbnail. Their
  /// tile shows an in-place bottom-to-top reveal and Submit is guarded until
  /// they finish.
  final Set<String> _processingPaths = {};

  /// Paths whose work has just finished: the tile's reveal is still mounted but
  /// now plays its closing sweep to the very top + fade-out. Cleared (together
  /// with [_processingPaths]) once the reveal reports it has finished.
  final Set<String> _completedPaths = {};

  /// Generated video-thumbnail bytes, keyed by file path.
  final Map<String, Uint8List> _thumbCache = {};

  /// Minimum time a tile's reveal stays visible so quick items still animate.
  static const Duration _minReveal = Duration(milliseconds: 500);

  // ── Location state (OPTIONAL for suggestions) ──────────────────────────────
  LatLng? _pickedLatLng;
  String? _pickedBarangay;
  bool _useCurrentLocation = false;

  bool _hasAnyInput() {
    return _selectedCategory != null ||
        _othersCtrl.text.isNotEmpty ||
        _detailsCtrl.text.isNotEmpty ||
        _streetDetailCtrl.text.isNotEmpty ||
        _attachedFiles.isNotEmpty ||
        _submitAnonymously ||
        _pickedBarangay != null;
  }

  // ── Categories (suggestion-specific) ───────────────────────────────────────
  final List<Map<String, dynamic>> _categories = [
    {
      'key': 'public_service',
      'label': 'Public\nService',
      'icon': 'assets/images/suggestion/courthouse.webp',
      'fallbackIcon': Icons.account_balance_rounded,
    },
    {
      'key': 'community_program',
      'label': 'Community\nProgram',
      'icon': 'assets/images/suggestion/group.webp',
      'fallbackIcon': Icons.groups_rounded,
    },
    {
      'key': 'health_safety',
      'label': 'Health &\nSafety',
      'icon': 'assets/images/suggestion/health.webp',
      'fallbackIcon': Icons.health_and_safety_rounded,
    },
    {
      'key': 'infrastructure',
      'label': 'Infrastructure',
      'icon': 'assets/images/suggestion/building.webp',
      'fallbackIcon': Icons.apartment_rounded,
    },
    {
      'key': 'environment',
      'label': 'Environment &\nCleanliness',
      'icon': 'assets/images/suggestion/trees.webp',
      'fallbackIcon': Icons.eco_rounded,
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
    _othersCtrl.dispose();
    _detailsCtrl.dispose();
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

  // ── Open location picker (optional for suggestions) ────────────────────────
  Future<void> _openLocationPicker() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      PageRouteBuilder(
        pageBuilder: (_, _, _) => LocationPickerScreen(
          initialPosition: _pickedLatLng,
          initialBarangay: _pickedBarangay,
        ),
        transitionDuration: const Duration(milliseconds: 380),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          );
        },
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _pickedLatLng = result['latLng'] as LatLng?;
        _pickedBarangay = result['barangay'] as String?;
        _useCurrentLocation = result['useCurrentLocation'] as bool? ?? false;
      });
    }
  }

  void _clearLocation() {
    setState(() {
      _pickedLatLng = null;
      _pickedBarangay = null;
      _useCurrentLocation = false;
      _streetDetailCtrl.clear();
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
            shellTitle: 'Share a Suggestion',
            shellSubtitle:
                'Have an idea to improve Aparri? Send it straight to your '
                'local government.',
            shellIcon: Icons.lightbulb_outline_rounded,
            shellHighlights: const [
              (Icons.edit_note_rounded, 'Describe your idea'),
              (Icons.category_outlined, 'Pick a category'),
              (Icons.how_to_vote_outlined, 'Help shape decisions'),
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
                          _animated(0, _buildCategorySection(width)),
                          SizedBox(height: width * 0.04),
                          _animated(1, _buildLocationSection(width)),
                          SizedBox(height: width * 0.04),
                          _animated(2, _buildDetailsSection(width)),
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
                    'Suggestion',
                    style: TextStyle(
                      fontSize: width * 0.058,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1F2937),
                    ),
                  ),
                  SizedBox(height: width * 0.015),
                  Text(
                    'Share ideas that can help improve\nyour community and local\ngovernment services.',
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
              'assets/images/suggestion/suggestion.webp',
              width: width * 0.22,
              height: width * 0.22,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => Icon(
                Icons.lightbulb_outline_rounded,
                size: width * 0.20,
                color: AppColors.orange,
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
              color: Colors.black.withValues(alpha: 0.04),
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

  // ── 1. Category ─────────────────────────────────────────────────────────────
  Widget _buildCategorySection(double width) {
    return Column(
      children: [
        _buildHeroBanner(width),
        SizedBox(height: width * 0.04),
        _sectionCard(
          width: width,
          title: '1. Select Suggestion Category',
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

  // ── 2. Location (OPTIONAL) ──────────────────────────────────────────────────
  Widget _buildLocationSection(double width) {
    final hasLocation = _pickedLatLng != null && _pickedBarangay != null;
    return _sectionCard(
      width: width,
      title: '2. Suggestion Location (Optional)',
      trailingTitle: hasLocation
          ? GestureDetector(
              onTap: _clearLocation,
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  'Clear',
                  style: TextStyle(
                    fontSize: width * 0.032,
                    fontWeight: FontWeight.w600,
                    color: AppColors.red,
                  ),
                ),
              ),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLocationBody(width),
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
    // ── Empty / not yet picked ──
    if (_pickedLatLng == null || _pickedBarangay == null) {
      return _locationTile(
        width: width,
        bgColor: const Color(0xFFF9FAFB),
        borderColor: const Color(0xFFE5E7EB),
        leading: Icon(
          Icons.location_on_outlined,
          size: width * 0.07,
          color: const Color(0xFF9CA3AF),
        ),
        text: 'Location',
        subText: 'Tap change to add a location',
        textColor: const Color(0xFF9CA3AF),
        onTap: _openLocationPicker,
        actionLabel: 'Change',
      );
    }

    // ── Picked via GPS ──
    if (_useCurrentLocation) {
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

    // ── Picked manually ──
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

  // ── 3. Details ──────────────────────────────────────────────────────────────
  Widget _buildDetailsSection(double width) {
    return _sectionCard(
      width: width,
      title: '3. Suggestion Details',
      child: TextField(
        controller: _detailsCtrl,
        maxLength: 2500,
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

  // ── Media helpers (identical to Report) ─────────────────────────────────────
  bool _isVideo(XFile file) {
    final ext = file.name.toLowerCase();
    return ext.endsWith('.mp4') || ext.endsWith('.mov') || ext.endsWith('.avi');
  }

  Future<void> _pickMedia() async {
    final remaining = _maxFiles - _attachedFiles.length;
    if (remaining <= 0) return;

    FocusManager.instance.primaryFocus?.unfocus();
    await Future.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;

    final choice = await showMediaPickerSheet(context);

    FocusManager.instance.primaryFocus?.unfocus();
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusManager.instance.primaryFocus?.unfocus();
    });
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
      precacheImage(FileImage(File(file.path)), context),
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

  /// Video thumbnail for a grid tile — cached bytes if ready, else generated
  /// (the reveal covers the plain placeholder while processing).
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

  void _previewImage(BuildContext context, XFile file, double width) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: Image.file(File(file.path), fit: BoxFit.contain),
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
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => _VideoPreviewDialog(file: file, width: width),
    );
  }

  // ── 4. Attach (OPTIONAL for suggestions) ────────────────────────────────────
  Widget _buildAttachSection(double width) {
    final slotCount = _attachedFiles.length < _maxFiles
        ? _attachedFiles.length + 1
        : _maxFiles;

    return _sectionCard(
      width: width,
      title: '4. Attach Image / Video (Optional)',
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
                            : Image.file(File(file.path), fit: BoxFit.cover),
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

  // ── Anonymous consent dialog (identical to Report) ─────────────────────────
  void _showAnonymousConsentDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final isEn = _consentInEnglish;
          final width = MediaQuery.of(context).size.width.clamp(0.0, 480.0);

          final title = isEn
              ? 'Anonymous Suggestion Consent'
              : 'Pahintulot sa Anonymous na Suhestiyon';
          final introBold = isEn
              ? 'Anonymous Suggestion'
              : 'Anonymous na Suhestiyon';
          final introText = isEn
              ? ', you acknowledge and agree to the following:'
              : ', kinikilala mo at sumasang-ayon sa mga sumusunod:';
          final bullets = isEn
              ? [
                  'Your identity and personal profile information will remain protected and hidden from public view.',
                  'The content of your submitted suggestion, including attached files, timestamps, and related submission details, may still be securely recorded and stored.',
                  'Submitted suggestions may be used for verification, investigation, moderation, legal compliance, and maintaining system integrity and security.',
                  'Authorized administrators or personnel may access suggestion records only when necessary for review and processing.',
                  'Any abuse, false reporting, fraudulent activity, or misuse of the anonymous suggestion feature may result in appropriate action in accordance with platform policies and applicable laws.',
                ]
              : [
                  'Ang iyong pagkakakilanlan at personal na impormasyon ay mananatiling protektado at nakatago mula sa pampublikong tingin.',
                  'Ang nilalaman ng iyong isinumiteng suhestiyon, kasama ang mga nakalakip na file, timestamp, at iba pang detalye, ay maaaring ligtas na mairekord at maiimbak.',
                  'Ang mga isinumiteng suhestiyon ay maaaring gamitin para sa pagpapatunay, imbestigasyon, moderasyon, pagsunod sa batas, at pagpapanatili ng integridad ng sistema.',
                  'Ang mga awtorisadong administrador o tauhan ay maaaring ma-access ang mga rekord ng suhestiyon lamang kung kinakailangan para sa pagsusuri at pagproseso.',
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
            insetPadding: EdgeInsets.symmetric(horizontal: width * 0.05),
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
                          setState(() => _submitAnonymously = true);
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

  // ── 5. Anonymous toggle ─────────────────────────────────────────────────────
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

  // ── Disclaimer banner ───────────────────────────────────────────────────────
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

  // ── Validation (location & media OPTIONAL) ──────────────────────────────────
  String? _validate() {
    if (_selectedCategory == null) {
      return 'Please select a suggestion category.';
    }
    if (_selectedCategory == 'others' && _othersCtrl.text.trim().isEmpty) {
      return 'Please specify the category under "Others".';
    }
    if (_detailsCtrl.text.trim().isEmpty) {
      return 'Please describe your suggestion in detail.';
    }
    if (_processingPaths.isNotEmpty) {
      return 'Please wait for your photo to finish processing.';
    }
    return null;
  }

  Future<void> _submitSuggestion() async {
    final error = _validate();
    if (error != null) {
      _showValidationDialog(error);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final supabase = Supabase.instance.client;

      final session = supabase.auth.currentSession;

      if (session == null) {
        setState(() => _isSubmitting = false);
        showFriendlyErrorDialog(
          context,
          'Session expired. Please log in again.',
        );
        return;
      }

      await supabase.auth.refreshSession();

      if (!mounted) return;

      final freshSession = supabase.auth.currentSession;

      if (freshSession == null) {
        setState(() => _isSubmitting = false);

        showFriendlyErrorDialog(
          context,
          'Session expired. Please log in again.',
        );

        return;
      }

      final userId = session.user.id;

      // ── Upload media ──────────────────────────────────────────────────────
      final List<Map<String, String>> mediaItems = [];
      for (int i = 0; i < _attachedFiles.length; i++) {
        final file = _attachedFiles[i];
        final bytes = await file.readAsBytes();
        final ext = file.name.split('.').last.toLowerCase();
        final fileName =
            '${DateTime.now().millisecondsSinceEpoch}_${i}_${file.name}';
        final storagePath = 'suggestions/$userId/$fileName';
        final contentType = _isVideo(file) ? 'video/$ext' : 'image/$ext';

        await supabase.storage
            .from('suggestion-media')
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

      // ── Insert suggestion ─────────────────────────────────────────────────
      final insertPayload = {
        'user_id': userId, // ← always send real user_id
        'category': _selectedCategory,
        'category_other': _selectedCategory == 'others'
            ? _othersCtrl.text.trim()
            : null,
        'barangay': _pickedBarangay,
        'address': _streetDetailCtrl.text.trim().isEmpty
            ? null
            : _streetDetailCtrl.text.trim(),
        'latitude': _pickedLatLng?.latitude,
        'longitude': _pickedLatLng?.longitude,
        'details': _detailsCtrl.text.trim(),
        'is_anonymous': _submitAnonymously,
        'status': 'pending',
      };

      final response = await supabase
          .from('suggestions')
          .insert(insertPayload)
          .select('id')
          .single();

      final suggestionId = response['id'] as String;

      // ── Insert media rows ─────────────────────────────────────────────────
      for (int i = 0; i < mediaItems.length; i++) {
        final row = <String, dynamic>{
          'suggestion_id': suggestionId,
          'storage_path': mediaItems[i]['path'],
          'mime_type': mediaItems[i]['mime'],
          'display_order': i + 1,
          'source': mediaItems[i]['source'],
        };
        // Capture the inserted row id so the AI-image check can target it.
        Map<String, dynamic> inserted;
        try {
          inserted = await supabase
              .from('suggestion_media')
              .insert(row)
              .select('id')
              .single();
        } on PostgrestException catch (e) {
          // `source` column may not be migrated yet — retry without it so
          // submitting a suggestion never breaks (media_source_column.sql).
          if ((e.message).toLowerCase().contains('source')) {
            row.remove('source');
            inserted = await supabase
                .from('suggestion_media')
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
            'bucket': 'suggestion-media',
            'path': mediaItems[i]['path'],
            'table': 'suggestion_media',
            'id': inserted['id'],
          }).ignore(); // swallow errors — never disturb the submission flow
        }
      }

      if (mounted) {
        showAppSnackBar(
          context,
          "Suggestion submitted successfully.",
          type: AppSnackType.success,
        );
        Navigator.pop(context);
      }
    } on StorageException catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false); // ← FIX: reset spinner
        showAppSnackBar(
          context,
          'File upload failed: ${e.message}',
          type: AppSnackType.error,
        );
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false); // ← FIX: reset spinner
        if ((e.hint ?? '') == 'rate_limit_exceeded') {
          showAppSnackBar(
            context,
            "You've reached your daily limit of 3 suggestions. Please come back tomorrow.",
            type: AppSnackType.error,
          );
        } else {
          showAppSnackBar(
            context,
            "Could not submit your suggestion. Please try again.",
            type: AppSnackType.error,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        showAppSnackBar(
          context,
          "Something went wrong. Please try again.",
          type: AppSnackType.error,
        );
      }
    } finally {
      // Safety net — always reset spinner
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ── Dialogs ─────────────────────────────────────────────────────────────────

  void _showValidationDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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

  // ── Submit button ───────────────────────────────────────────────────────────
  Widget _buildSubmitButton(double width) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: width * 0.04),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: (_isSubmitting || _processingPaths.isNotEmpty)
              ? null
              : _submitSuggestion,
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
                      : 'Submit Suggestion',
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
