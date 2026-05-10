import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../../../core/theme/app_colors.dart';

// ── Aparri bounding box ────────────────────────────────────────────────────
const double _aparriMinLat = 18.2800;
const double _aparriMaxLat = 18.4200;
const double _aparriMinLng = 121.5800;
const double _aparriMaxLng = 121.7200;
const LatLng _aparriCenter = LatLng(18.3566, 121.6361);

bool _isWithinAparri(LatLng pos) {
  return pos.latitude >= _aparriMinLat &&
      pos.latitude <= _aparriMaxLat &&
      pos.longitude >= _aparriMinLng &&
      pos.longitude <= _aparriMaxLng;
}

class LocationPickerScreen extends StatefulWidget {
  final LatLng? initialPosition;

  const LocationPickerScreen({super.key, this.initialPosition});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  GoogleMapController? _mapController;
  LatLng _pickedLocation = _aparriCenter;
  String _address = 'Tap the map to select a location';
  bool _isLoadingAddress = false;
  bool _isOutOfScope = false;
  bool _isLoadingGPS = false;

  // ── Used to measure actual bottom sheet height ──
  final GlobalKey _bottomSheetKey = GlobalKey();
  double _bottomSheetHeight = 200; // safe fallback

  @override
  void initState() {
    super.initState();
    // Measure sheet height after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureSheet());

    if (widget.initialPosition != null) {
      _pickedLocation = widget.initialPosition!;
      _reverseGeocode(_pickedLocation);
    }
  }

  void _measureSheet() {
    final ctx = _bottomSheetKey.currentContext;
    if (ctx != null) {
      final box = ctx.findRenderObject() as RenderBox;
      if (mounted) {
        setState(() => _bottomSheetHeight = box.size.height);
      }
    }
  }

  Future<void> _reverseGeocode(LatLng pos) async {
    if (!mounted) return;
    setState(() => _isLoadingAddress = true);
    try {
      final placemarks = await placemarkFromCoordinates(
        pos.latitude,
        pos.longitude,
      );
      if (placemarks.isNotEmpty && mounted) {
        final p = placemarks.first;

        // Filter out Plus Codes like "8JXV+4X9"
        final plusCodeRegex = RegExp(r'^[0-9A-Z]{4}\+[0-9A-Z]+$');

        final parts =
            [
                  p.name,
                  p.thoroughfare,
                  p.subThoroughfare,
                  p.subLocality,
                  p.locality,
                  p.subAdministrativeArea,
                  p.administrativeArea,
                ]
                .where((e) => e != null && e.isNotEmpty)
                .where((e) => !plusCodeRegex.hasMatch(e!))
                .toSet()
                .toList();

        final coords =
            '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';

        setState(
          () => _address = parts.isEmpty
              ? coords // no address: coords only
              : '${parts.join(', ')}\n$coords',
        ); // has address: address + coords

        // Re-measure sheet since address text changed height
        WidgetsBinding.instance.addPostFrameCallback((_) => _measureSheet());
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _address =
              '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingAddress = false);
    }
  }

  Future<void> _goToMyLocation() async {
    setState(() => _isLoadingGPS = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) _showPermissionDeniedDialog();
        return;
      }

      final pos = await Geolocator.getCurrentPosition();
      final latLng = LatLng(pos.latitude, pos.longitude);

      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(latLng, 16));
      _onMapTap(latLng);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not get current location.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingGPS = false);
    }
  }

  void _onMapTap(LatLng pos) {
    final outOfScope = !_isWithinAparri(pos);
    setState(() {
      _pickedLocation = pos;
      _isOutOfScope = outOfScope;
      _address = 'Fetching address...';
    });

    if (outOfScope) {
      _showOutOfScopeDialog();
    } else {
      _reverseGeocode(pos);
    }
  }

  void _showOutOfScopeDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
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
                  color: Colors.orange.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.location_off_rounded,
                  color: Colors.orange,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Out of Scope',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1F2937),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'The selected location is outside the Aparri, Cagayan area. Please pin a location within Aparri.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF6B7280),
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _mapController?.animateCamera(
                      CameraUpdate.newLatLngZoom(_aparriCenter, 13),
                    );
                    setState(() {
                      _pickedLocation = _aparriCenter;
                      _isOutOfScope = false;
                      _address = 'Tap the map to select a location';
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text(
                    'Go Back to Aparri',
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

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Location Permission'),
        content: const Text(
          'Location permission is permanently denied. Please enable it in your device settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Geolocator.openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      body: Stack(
        children: [
          // ── Map ──────────────────────────────────────────────────────────
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: widget.initialPosition ?? _aparriCenter,
              zoom: 14,
            ),
            onMapCreated: (c) => _mapController = c,
            onTap: _onMapTap,
            markers: {
              if (!_isOutOfScope)
                Marker(
                  markerId: const MarkerId('picked'),
                  position: _pickedLocation,
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueAzure,
                  ),
                ),
            },
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
          ),

          // ── Header ───────────────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: width * 0.04,
                vertical: width * 0.03,
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: width * 0.10,
                      height: width * 0.10,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: width * 0.045,
                        color: const Color(0xFF374151),
                      ),
                    ),
                  ),
                  SizedBox(width: width * 0.03),
                  Expanded(
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: width * 0.04,
                        vertical: width * 0.025,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(width * 0.03),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.10),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.search_rounded,
                            color: AppColors.primaryBlue,
                            size: width * 0.05,
                          ),
                          SizedBox(width: width * 0.02),
                          Text(
                            'Aparri, Cagayan',
                            style: TextStyle(
                              fontSize: width * 0.033,
                              color: const Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── GPS button — always sits just above the bottom sheet ──────────
          Positioned(
            right: width * 0.04,
            bottom: _bottomSheetHeight + width * 0.03,
            child: GestureDetector(
              onTap: _isLoadingGPS ? null : _goToMyLocation,
              child: Container(
                width: width * 0.12,
                height: width * 0.12,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: _isLoadingGPS
                    ? Padding(
                        padding: const EdgeInsets.all(14),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primaryBlue,
                        ),
                      )
                    : Icon(
                        Icons.my_location_rounded,
                        color: AppColors.primaryBlue,
                        size: width * 0.06,
                      ),
              ),
            ),
          ),

          // ── Bottom sheet ─────────────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              key: _bottomSheetKey, // ← measures actual height
              padding: EdgeInsets.fromLTRB(
                width * 0.05,
                width * 0.05,
                width * 0.05,
                width * 0.05 + bottomPadding, // ← clears system nav bar
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 16,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1D5DB),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  SizedBox(height: width * 0.04),

                  // Label
                  Text(
                    'Selected Location',
                    style: TextStyle(
                      fontSize: width * 0.032,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF9CA3AF),
                    ),
                  ),
                  SizedBox(height: width * 0.02),

                  // Address row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.location_on_rounded,
                        color: AppColors.primaryBlue,
                        size: width * 0.06,
                      ),
                      SizedBox(width: width * 0.025),
                      Expanded(
                        child: _isLoadingAddress
                            ? Row(
                                children: [
                                  SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.primaryBlue,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text('Fetching address...'),
                                ],
                              )
                            : RichText(
                                text: TextSpan(
                                  children: () {
                                    final lines = _address.split('\n');
                                    if (lines.length == 2) {
                                      // Has address + coords
                                      return [
                                        TextSpan(
                                          text: '${lines[0]}\n',
                                          style: TextStyle(
                                            fontSize: width * 0.038,
                                            fontWeight: FontWeight.w700,
                                            color: const Color(0xFF1F2937),
                                            height: 1.4,
                                          ),
                                        ),
                                        TextSpan(
                                          text: lines[1],
                                          style: TextStyle(
                                            fontSize: width * 0.028,
                                            fontWeight: FontWeight.w400,
                                            color: const Color(0xFF9CA3AF),
                                            height: 1.4,
                                          ),
                                        ),
                                      ];
                                    }
                                    // Coords only or fallback text
                                    return [
                                      TextSpan(
                                        text: lines[0],
                                        style: TextStyle(
                                          fontSize: width * 0.038,
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFF1F2937),
                                          height: 1.4,
                                        ),
                                      ),
                                    ];
                                  }(),
                                ),
                              ),
                      ),
                    ],
                  ),

                  SizedBox(height: width * 0.05),

                  // Confirm button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isOutOfScope || _isLoadingAddress
                          ? null
                          : () => Navigator.pop(context, {
                              'latLng': _pickedLocation,
                              'address': _address,
                            }),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        disabledBackgroundColor: const Color(0xFFD1D5DB),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: EdgeInsets.symmetric(vertical: width * 0.042),
                        elevation: 2,
                      ),
                      child: Text(
                        'Confirm Location',
                        style: TextStyle(
                          fontSize: width * 0.04,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
