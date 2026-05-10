import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'dart:typed_data';
import 'package:video_player/video_player.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'location_picker_screen.dart';

// ── Aparri bounding box (same values as location_picker_screen.dart) ────────
const double _riMinLat = 18.2800;
const double _riMaxLat = 18.4200;
const double _riMinLng = 121.5800;
const double _riMaxLng = 121.7200;

bool _withinAparri(double lat, double lng) =>
    lat >= _riMinLat &&
    lat <= _riMaxLat &&
    lng >= _riMinLng &&
    lng <= _riMaxLng;

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

class ReportIssueScreen extends StatefulWidget {
  final String username;
  const ReportIssueScreen({super.key, required this.username});

  @override
  State<ReportIssueScreen> createState() => _ReportIssueScreenState();
}

class _ReportIssueScreenState extends State<ReportIssueScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entryCtrl;

  // ── Form state ─────────────────────────────────────────────────────────────
  String? _selectedCategory;
  final TextEditingController _othersCtrl = TextEditingController();
  final TextEditingController _remarksCtrl = TextEditingController();
  bool _submitAnonymously = false;
  final List<XFile> _attachedFiles = [];
  static const int _maxFiles = 6;
  final ImagePicker _picker = ImagePicker();
  bool _consentInEnglish = true;

  // ── Location state ─────────────────────────────────────────────────────────
  LatLng? _pickedLatLng;
  String? _pickedAddress; // null = not yet resolved
  bool _isFetchingLocation = true; // true on first load
  bool _locationOutsideAparri = false;
  bool _locationPermissionDenied = false;

  // ── Categories ─────────────────────────────────────────────────────────────
  final List<Map<String, dynamic>> _categories = [
    {
      'key': 'road',
      'label': 'Road &\nInfrastructure',
      'icon': 'assets/images/report/roadtwo.png',
      'fallbackIcon': Icons.add_road_rounded,
    },
    {
      'key': 'waste',
      'label': 'Waste &\nGarbage',
      'icon': 'assets/images/report/bin.png',
      'fallbackIcon': Icons.delete_outline,
    },
    {
      'key': 'drainage',
      'label': 'Drainage &\nFlooding',
      'icon': 'assets/images/report/road.png',
      'fallbackIcon': Icons.water,
    },
    {
      'key': 'streetlight',
      'label': 'Streetlight\nOutage',
      'icon': 'assets/images/report/lamppost.png',
      'fallbackIcon': Icons.light,
    },
    {
      'key': 'environment',
      'label': 'Environment &\nPollution',
      'icon': 'assets/images/report/leaf.png',
      'fallbackIcon': Icons.eco,
    },
    {
      'key': 'others',
      'label': 'Others',
      'icon': 'assets/images/report/menu.png',
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
      _autoFetchLocation();
    });
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _othersCtrl.dispose();
    _remarksCtrl.dispose();
    super.dispose();
  }

  // ── GPS auto-fetch ──────────────────────────────────────────────────────────
  Future<void> _autoFetchLocation() async {
    if (!mounted) return;
    setState(() {
      _isFetchingLocation = true;
      _locationPermissionDenied = false;
      _locationOutsideAparri = false;
    });

    try {
      // 1. Check / request permission
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

      // 2. Get GPS fix
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      if (!mounted) return;
      final lat = pos.latitude;
      final lng = pos.longitude;

      // 3. Bounds check
      if (!_withinAparri(lat, lng)) {
        setState(() {
          _isFetchingLocation = false;
          _locationOutsideAparri = true;
          _pickedLatLng = null;
          _pickedAddress = null;
        });
        return;
      }

      // 4. Reverse-geocode
      String address = '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
      try {
        final marks = await placemarkFromCoordinates(lat, lng);
        if (marks.isNotEmpty) {
          final p = marks.first;
          final parts = <String>[
            if ((p.subLocality ?? '').isNotEmpty) p.subLocality!,
            if ((p.locality ?? '').isNotEmpty) p.locality!,
            if ((p.administrativeArea ?? '').isNotEmpty) p.administrativeArea!,
          ];
          if (parts.isNotEmpty) address = parts.join(', ');
        }
      } catch (_) {
        // Keep coordinate fallback
      }

      if (mounted) {
        setState(() {
          _pickedLatLng = LatLng(lat, lng);
          _pickedAddress = address;
          _isFetchingLocation = false;
          _locationOutsideAparri = false;
        });
      }
    } catch (e) {
      debugPrint('GPS error: $e');
      if (mounted) {
        setState(() {
          _isFetchingLocation = false;
          // Leave address null → user must pick manually
        });
      }
    }
  }

  // ── Open location picker ────────────────────────────────────────────────────
  Future<void> _openLocationPicker() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(initialPosition: _pickedLatLng),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _pickedLatLng = result['latLng'] as LatLng;
        _pickedAddress = result['address'] as String;
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
    final width = MediaQuery.of(context).size.width;
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(width),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
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
                    SizedBox(height: width * 0.05),
                    _animated(5, _buildSubmitButton(width)),
                  ],
                ),
              ),
            ),
          ],
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
            onTap: () => Navigator.pop(context),
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
                color: const Color(0xFF374151),
              ),
            ),
          ),
          SizedBox(width: width * 0.03),
          Image.asset(
            'assets/images/newslogo.png',
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
              'assets/images/report/clipboard.png',
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
    return _sectionCard(
      width: width,
      title: '2. Location',
      child: _buildLocationBody(width),
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
        subText: 'Please pick a location manually.',
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
        subText: 'Please pick a location manually.',
        textColor: const Color(0xFF374151),
        onTap: _openLocationPicker,
        actionLabel: 'Pick',
      );
    }

    // ── Location resolved (GPS or manually picked) ──
    if (_pickedLatLng != null && _pickedAddress != null) {
      return _locationTile(
        width: width,
        bgColor: const Color(0xFFF9FAFB),
        borderColor: const Color(0xFFE5E7EB),
        leading: Icon(
          Icons.location_on_rounded,
          size: width * 0.07,
          color: AppColors.primaryBlue,
        ),
        text: _pickedAddress!,
        subText:
            '${_pickedLatLng!.latitude.toStringAsFixed(5)}, '
            '${_pickedLatLng!.longitude.toStringAsFixed(5)}',
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
      subText: 'Please pick a location manually.',
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
                    fontSize: width * 0.033,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                    height: 1.4,
                  ),
                ),
                if (subText != null) ...[
                  SizedBox(height: width * 0.005),
                  Text(
                    subText,
                    style: TextStyle(
                      fontSize: width * 0.027,
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

    final choice = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD1D5DB),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Image.asset(
                'assets/images/report/gallery.png',
                width: 28,
                height: 28,
                errorBuilder: (_, _, _) => Icon(
                  Icons.photo_library_rounded,
                  color: AppColors.primaryBlue,
                ),
              ),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: Image.asset(
                'assets/images/report/video.png',
                width: 28,
                height: 28,
                errorBuilder: (_, _, _) =>
                    Icon(Icons.videocam_rounded, color: AppColors.primaryBlue),
              ),
              title: const Text('Choose Video from Gallery'),
              onTap: () => Navigator.pop(ctx, 'video'),
            ),
            ListTile(
              leading: Image.asset(
                'assets/images/report/cameraicon.png',
                width: 28,
                height: 28,
                errorBuilder: (_, _, _) => Icon(
                  Icons.camera_alt_rounded,
                  color: AppColors.primaryBlue,
                ),
              ),
              title: const Text('Take a Photo'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );

    if (choice == null) return;

    List<XFile> picked = [];
    if (choice == 'gallery') {
      picked = await _picker.pickMultiImage(limit: remaining);
    } else if (choice == 'video') {
      final v = await _picker.pickVideo(source: ImageSource.gallery);
      if (v != null) picked = [v];
    } else if (choice == 'camera') {
      final p = await _picker.pickImage(source: ImageSource.camera);
      if (p != null) picked = [p];
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
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          contentPadding: const EdgeInsets.all(24),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/report/sad_face.png',
                width: 72,
                height: 72,
                errorBuilder: (_, _, _) => const Icon(
                  Icons.sentiment_dissatisfied_rounded,
                  size: 72,
                  color: Colors.orange,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'File Too Large!',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F2937),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Some files exceeded the size limit.\nImages must be under 10MB and videos under 50MB.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF6B7280),
                  height: 1.5,
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
                    'Got it',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (validFiles.isEmpty) return;
    setState(() {
      final canAdd = _maxFiles - _attachedFiles.length;
      _attachedFiles.addAll(validFiles.take(canAdd));
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
                  Image.asset(
                    'assets/images/report/camera.png',
                    width: width * 0.10,
                    height: width * 0.10,
                    errorBuilder: (_, _, _) => Icon(
                      Icons.camera_alt_rounded,
                      size: width * 0.10,
                      color: AppColors.primaryBlue,
                    ),
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
                          'assets/images/report/plus_sign.png',
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
                return GestureDetector(
                  onTap: () {
                    _isVideo(_attachedFiles[index])
                        ? _previewVideo(context, _attachedFiles[index], width)
                        : _previewImage(context, _attachedFiles[index], width);
                  },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(width * 0.025),
                        child: _isVideo(_attachedFiles[index])
                            ? FutureBuilder<Uint8List?>(
                                future: VideoThumbnail.thumbnailData(
                                  video: _attachedFiles[index].path,
                                  imageFormat: ImageFormat.JPEG,
                                  maxWidth: 200,
                                  quality: 75,
                                ),
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState ==
                                          ConnectionState.done &&
                                      snapshot.data != null) {
                                    return Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        Image.memory(
                                          snapshot.data!,
                                          fit: BoxFit.cover,
                                        ),
                                        Center(
                                          child: Container(
                                            padding: EdgeInsets.all(
                                              width * 0.015,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.black.withValues(
                                                alpha: 0.5,
                                              ),
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
                                  }
                                  return Container(
                                    color: const Color(0xFFE0F2FE),
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        color: AppColors.primaryBlue,
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  );
                                },
                              )
                            : Image.file(
                                File(_attachedFiles[index].path),
                                fit: BoxFit.cover,
                              ),
                      ),
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
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final isEn = _consentInEnglish;
          final width = MediaQuery.of(context).size.width;

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
              'assets/images/report/padlock.png',
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

  // ── Submit ───────────────────────────────────────────────────────────────────
  Widget _buildSubmitButton(double width) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: width * 0.04),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () {
            // TODO: submission logic
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.green,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(width * 0.035),
            ),
            padding: EdgeInsets.symmetric(vertical: width * 0.042),
            elevation: 2,
            shadowColor: AppColors.green.withValues(alpha: 0.4),
          ),
          child: Text(
            'Submit Report',
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
