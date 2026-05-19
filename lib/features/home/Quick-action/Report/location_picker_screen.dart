import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../../../../core/theme/app_colors.dart';

// ── Aparri bounding box (expanded to cover all 42 official barangays) ─────
const double _aparriMinLat = 18.2750;
const double _aparriMaxLat = 18.4200;
const double _aparriMinLng = 121.5300; // extended west for Binalan/Navagan
const double _aparriMaxLng = 121.7450; // extended east for Paddaya/Dodan
const LatLng _aparriCenter = LatLng(18.3566, 121.6406);

bool _isWithinAparri(LatLng pos) =>
    pos.latitude >= _aparriMinLat &&
    pos.latitude <= _aparriMaxLat &&
    pos.longitude >= _aparriMinLng &&
    pos.longitude <= _aparriMaxLng;

// ── Official 42 barangays of Aparri, Cagayan (PSA / PhilAtlas verified) ──
const List<String> _barangayList = [
  'Backiling',
  'Bangag',
  'Binalan',
  'Bisagu',
  'Bukig',
  'Bulala Norte',
  'Bulala Sur',
  'Caagaman',
  'Centro 1 (Pob.)',
  'Centro 2 (Pob.)',
  'Centro 3 (Pob.)',
  'Centro 4 (Pob.)',
  'Centro 5 (Pob.)',
  'Centro 6 (Pob.)',
  'Centro 7 (Pob.)',
  'Centro 8 (Pob.)',
  'Centro 9 (Pob.)',
  'Centro 10 (Pob.)',
  'Centro 11 (Pob.)',
  'Centro 12 (Pob.)',
  'Centro 13 (Pob.)',
  'Centro 14 (Pob.)',
  'Centro 15 (Pob.)',
  'Dodan',
  'Gaddang',
  'Linao',
  'Mabanguc',
  'Macanaya (Pescaria)',
  'Maura',
  'Minanga',
  'Navagan',
  'Paddaya',
  'Paruddun Norte',
  'Paruddun Sur',
  'Plaza',
  'Punta',
  'San Antonio',
  'Sanja',
  'Tallungan',
  'Toran',
  'Zinarag',
  // Fuga Island (42nd brgy) omitted — remote island, not mainland Aparri
];

// ── Verified coordinates — sourced from PhilAtlas (PSA census data) ──────
const Map<String, LatLng> _barangayCoords = {
  // ── Verified from PhilAtlas ──
  'Backiling': LatLng(18.2861, 121.5849),
  'Bangag': LatLng(18.2964, 121.5615),
  'Binalan': LatLng(18.3248, 121.5434),
  'Bisagu': LatLng(18.3494, 121.6071),
  'Bukig': LatLng(18.3102, 121.6065),
  'Bulala Norte': LatLng(18.3797, 121.5754),
  'Bulala Sur': LatLng(18.3700, 121.5780), // near Bulala Norte
  'Caagaman': LatLng(18.3236, 121.5941),
  'Dodan': LatLng(18.3362, 121.7036),
  'Gaddang': LatLng(18.3431, 121.6522),
  'Linao': LatLng(18.3713, 121.5998),
  'Mabanguc': LatLng(18.2886, 121.6468),
  'Macanaya (Pescaria)': LatLng(18.3504, 121.6404),
  'Maura': LatLng(18.3544, 121.6481),
  'Minanga': LatLng(18.3517, 121.6374),
  'Navagan': LatLng(18.3593, 121.5636),
  'Paddaya': LatLng(18.3249, 121.7350),
  'Paruddun Norte': LatLng(18.3180, 121.6250),
  'Paruddun Sur': LatLng(18.3008, 121.6432),
  'Punta': LatLng(18.3595, 121.6323),
  'San Antonio': LatLng(18.3589, 121.6412),
  'Sanja': LatLng(18.3126, 121.6383),
  'Tallungan': LatLng(18.3364, 121.6492),
  'Toran': LatLng(18.3145, 121.6556),
  'Zinarag': LatLng(18.3109, 121.5680),
  // ── Centro (Poblacion) cluster — PhilAtlas Centro 7: 18.3564, 121.6405 ─
  'Centro 1 (Pob.)': LatLng(18.3580, 121.6418),
  'Centro 2 (Pob.)': LatLng(18.3575, 121.6413),
  'Centro 3 (Pob.)': LatLng(18.3572, 121.6410),
  'Centro 4 (Pob.)': LatLng(18.3568, 121.6407),
  'Centro 5 (Pob.)': LatLng(18.3565, 121.6405),
  'Centro 6 (Pob.)': LatLng(18.3562, 121.6403),
  'Centro 7 (Pob.)': LatLng(18.3564, 121.6405),
  'Centro 8 (Pob.)': LatLng(18.3558, 121.6400),
  'Centro 9 (Pob.)': LatLng(18.3555, 121.6398),
  'Centro 10 (Pob.)': LatLng(18.3552, 121.6395),
  'Centro 11 (Pob.)': LatLng(18.3549, 121.6392),
  'Centro 12 (Pob.)': LatLng(18.3546, 121.6390),
  'Centro 13 (Pob.)': LatLng(18.3543, 121.6387),
  'Centro 14 (Pob.)': LatLng(18.3540, 121.6385),
  'Centro 15 (Pob.)': LatLng(18.3537, 121.6382),
  // ── Plaza — poblacion core, near Centro cluster ───────────────────────
  'Plaza': LatLng(18.3560, 121.6395),
};

// ── Finds the nearest barangay name to a GPS coordinate ──────────────────
String findNearestBarangay(LatLng pos) {
  String nearest = _barangayList.first;
  double minDist = double.maxFinite;
  for (final entry in _barangayCoords.entries) {
    final dlat = entry.value.latitude - pos.latitude;
    final dlng = entry.value.longitude - pos.longitude;
    final d = dlat * dlat + dlng * dlng;
    if (d < minDist) {
      minDist = d;
      nearest = entry.key;
    }
  }
  return nearest;
}

// ─────────────────────────────────────────────────────────────────────────────

class LocationPickerScreen extends StatefulWidget {
  final LatLng? initialPosition;
  final String? initialBarangay;

  const LocationPickerScreen({
    super.key,
    this.initialPosition,
    this.initialBarangay,
  });

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  GoogleMapController? _mapController;

  bool _useCurrentLocation = false;
  bool _isLoadingGPS = false;
  String? _selectedBarangay;
  LatLng? _markerPosition;

  @override
  void initState() {
    super.initState();
    if (widget.initialBarangay != null &&
        widget.initialBarangay != 'Current Location') {
      _selectedBarangay = widget.initialBarangay;
      _markerPosition =
          _barangayCoords[_selectedBarangay] ?? widget.initialPosition;
    } else if (widget.initialPosition != null) {
      _markerPosition = widget.initialPosition;
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  // ── GPS fetch ──────────────────────────────────────────────────────────────
  Future<void> _fetchCurrentLocation() async {
    setState(() => _isLoadingGPS = true);
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _useCurrentLocation = false;
            _isLoadingGPS = false;
          });
          _showPermissionDialog();
        }
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      final latLng = LatLng(pos.latitude, pos.longitude);

      if (!_isWithinAparri(latLng)) {
        if (mounted) {
          setState(() {
            _useCurrentLocation = false;
            _isLoadingGPS = false;
          });
          _showOutsideAparriDialog();
        }
        return;
      }

      if (mounted) {
        final nearest = findNearestBarangay(latLng);
        setState(() {
          _markerPosition = latLng;
          _selectedBarangay = nearest;
          _isLoadingGPS = false;
        });
        _mapController?.animateCamera(CameraUpdate.newLatLngZoom(latLng, 16));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _useCurrentLocation = false;
          _isLoadingGPS = false;
        });
        _showLocationErrorDialog();
      }
    }
  }

  // ── Confirm ────────────────────────────────────────────────────────────────
  bool get _canConfirm {
    if (_useCurrentLocation && _markerPosition != null) return true;
    if (!_useCurrentLocation && _selectedBarangay != null) return true;
    return false;
  }

  void _confirm() {
    if (_useCurrentLocation) {
      final barangay =
          _selectedBarangay ?? findNearestBarangay(_markerPosition!);
      Navigator.pop(context, {
        'barangay': barangay,
        'useCurrentLocation': true,
        'latLng': _markerPosition,
      });
    } else {
      final coords = _barangayCoords[_selectedBarangay] ?? _aparriCenter;
      Navigator.pop(context, {
        'barangay': _selectedBarangay,
        'useCurrentLocation': false,
        'latLng': coords,
      });
    }
  }

  // ── Dialogs ────────────────────────────────────────────────────────────────
  void _showOutsideAparriDialog() {
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
                  color: Colors.red.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.wrong_location_rounded,
                  color: Colors.red,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Outside Aparri',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1F2937),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your current location is outside Aparri, Cagayan. Please pick a barangay manually instead.',
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
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text(
                    'OK, I\'ll pick manually',
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

  void _showLocationErrorDialog() {
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
                  Icons.location_off_rounded,
                  color: Colors.orange,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Could Not Get Location',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1F2937),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'We were unable to detect your current location. Please pick a barangay manually.',
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

  void _showPermissionDialog() {
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
                  Icons.lock_outline_rounded,
                  color: Colors.orange,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Location Permission',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1F2937),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Location permission is denied. Please enable it in your device settings to use current location.',
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
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppColors.primaryBlue),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: AppColors.primaryBlue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        Geolocator.openAppSettings();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text(
                        'Open Settings',
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
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    final keyboardPad = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset:
          false, // prevents GoogleMap from rebuilding when keyboard opens
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────────
            _buildHeader(width),

            // ── Scrollable body (title + map + form all together) ────────────
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  width * 0.045,
                  width * 0.035,
                  width * 0.045,
                  bottomPad + keyboardPad + width * 0.02,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Title + subtitle ─────────────────────────────────────
                    Text(
                      'Edit Location',
                      style: TextStyle(
                        fontSize: width * 0.044,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1F2937),
                      ),
                    ),
                    SizedBox(height: width * 0.008),
                    Text(
                      'Toggle GPS or select a barangay from the list.',
                      style: TextStyle(
                        fontSize: width * 0.030,
                        color: const Color(0xFF9CA3AF),
                      ),
                    ),
                    SizedBox(height: width * 0.03),

                    // ── Map inside a rounded container ───────────────────────
                    ClipRRect(
                      borderRadius: BorderRadius.circular(width * 0.035),
                      child: SizedBox(
                        height: width * 0.62,
                        child: GoogleMap(
                          initialCameraPosition: CameraPosition(
                            target: _markerPosition ?? _aparriCenter,
                            zoom: 14,
                          ),
                          onMapCreated: (c) => _mapController = c,
                          markers: _markerPosition != null
                              ? {
                                  Marker(
                                    markerId: const MarkerId('loc'),
                                    position: _markerPosition!,
                                    icon: BitmapDescriptor.defaultMarkerWithHue(
                                      BitmapDescriptor.hueAzure,
                                    ),
                                  ),
                                }
                              : {},
                          myLocationButtonEnabled: false,
                          zoomControlsEnabled: false,
                          mapToolbarEnabled: false,
                        ),
                      ),
                    ),

                    SizedBox(height: width * 0.04),

                    // ── Unified form card ────────────────────────────────────
                    Container(
                      width: double.infinity,
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
                          // ── Toggle row ─────────────────────────────────────
                          Padding(
                            padding: EdgeInsets.all(width * 0.04),
                            child: Row(
                              children: [
                                Container(
                                  width: width * 0.105,
                                  height: width * 0.105,
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryBlue.withValues(
                                      alpha: 0.08,
                                    ),
                                    borderRadius: BorderRadius.circular(
                                      width * 0.03,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.my_location_rounded,
                                    size: width * 0.05,
                                    color: AppColors.primaryBlue,
                                  ),
                                ),
                                SizedBox(width: width * 0.03),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Use my current location',
                                        style: TextStyle(
                                          fontSize: width * 0.034,
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFF1F2937),
                                        ),
                                      ),
                                      SizedBox(height: width * 0.005),
                                      Text(
                                        'Detects your GPS position',
                                        style: TextStyle(
                                          fontSize: width * 0.027,
                                          color: const Color(0xFF9CA3AF),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (_isLoadingGPS)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    child: SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: AppColors.primaryBlue,
                                      ),
                                    ),
                                  )
                                else
                                  Switch(
                                    value: _useCurrentLocation,
                                    onChanged: (v) async {
                                      setState(() {
                                        _useCurrentLocation = v;
                                        if (!v) {
                                          _markerPosition =
                                              _selectedBarangay != null
                                              ? _barangayCoords[_selectedBarangay]
                                              : null;
                                          if (_markerPosition != null) {
                                            _mapController?.animateCamera(
                                              CameraUpdate.newLatLngZoom(
                                                _markerPosition!,
                                                15,
                                              ),
                                            );
                                          }
                                        }
                                      });
                                      if (v) await _fetchCurrentLocation();
                                    },
                                    activeTrackColor: AppColors.primaryBlue,
                                    activeThumbColor: Colors.white,
                                    inactiveThumbColor: Colors.white,
                                    inactiveTrackColor: const Color(0xFFD1D5DB),
                                  ),
                              ],
                            ),
                          ),

                          const Divider(height: 1, color: Color(0xFFE5E7EB)),

                          // ── Barangay section ───────────────────────────────
                          Padding(
                            padding: EdgeInsets.all(width * 0.04),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.location_on_rounded,
                                      size: width * 0.038,
                                      color: AppColors.primaryBlue,
                                    ),
                                    SizedBox(width: width * 0.015),
                                    Text(
                                      'Barangay',
                                      style: TextStyle(
                                        fontSize: width * 0.032,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.primaryBlue,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: width * 0.025),

                                // Dropdown
                                AnimatedOpacity(
                                  opacity: _useCurrentLocation ? 0.45 : 1.0,
                                  duration: const Duration(milliseconds: 200),
                                  child: IgnorePointer(
                                    ignoring: _useCurrentLocation,
                                    child: Container(
                                      width: double.infinity,
                                      padding: EdgeInsets.symmetric(
                                        horizontal: width * 0.04,
                                        vertical: width * 0.005,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF9FAFB),
                                        border: Border.all(
                                          color: const Color(0xFFE5E7EB),
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          width * 0.025,
                                        ),
                                      ),
                                      child: DropdownButton<String>(
                                        value: _selectedBarangay,
                                        isExpanded: true,
                                        underline: const SizedBox(),
                                        icon: Icon(
                                          Icons.keyboard_arrow_down_rounded,
                                          color: AppColors.primaryBlue,
                                          size: width * 0.06,
                                        ),
                                        hint: Text(
                                          _useCurrentLocation
                                              ? 'Using current location'
                                              : 'Select barangay',
                                          style: TextStyle(
                                            fontSize: width * 0.034,
                                            color: const Color(0xFF9CA3AF),
                                          ),
                                        ),
                                        style: TextStyle(
                                          fontSize: width * 0.034,
                                          color: const Color(0xFF1F2937),
                                        ),
                                        items: _barangayList
                                            .map(
                                              (b) => DropdownMenuItem(
                                                value: b,
                                                child: Text(b),
                                              ),
                                            )
                                            .toList(),
                                        onChanged: (val) {
                                          if (val == null) return;
                                          final coords = _barangayCoords[val];
                                          setState(() {
                                            _selectedBarangay = val;
                                            _markerPosition = coords;
                                          });
                                          if (coords != null) {
                                            _mapController?.animateCamera(
                                              CameraUpdate.newLatLngZoom(
                                                coords,
                                                15,
                                              ),
                                            );
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                ),

                                // Confirmation chip — manual selection
                                if (_selectedBarangay != null &&
                                    !_useCurrentLocation) ...[
                                  SizedBox(height: width * 0.025),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(3),
                                        decoration: BoxDecoration(
                                          color: AppColors.primaryBlue
                                              .withValues(alpha: 0.12),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          Icons.check_rounded,
                                          size: width * 0.032,
                                          color: AppColors.primaryBlue,
                                        ),
                                      ),
                                      SizedBox(width: width * 0.02),
                                      Expanded(
                                        child: Text(
                                          '$_selectedBarangay selected',
                                          style: TextStyle(
                                            fontSize: width * 0.029,
                                            color: AppColors.primaryBlue,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],

                                // Confirmation chip — GPS placed
                                if (_selectedBarangay != null &&
                                    _useCurrentLocation) ...[
                                  SizedBox(height: width * 0.025),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.my_location_rounded,
                                        size: width * 0.038,
                                        color: AppColors.primaryBlue,
                                      ),
                                      SizedBox(width: width * 0.02),
                                      Expanded(
                                        child: Text(
                                          'GPS placed in $_selectedBarangay',
                                          style: TextStyle(
                                            fontSize: width * 0.029,
                                            color: AppColors.primaryBlue,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: width * 0.04),

                    // ── Confirm button ────────────────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _canConfirm ? _confirm : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryBlue,
                          disabledBackgroundColor: const Color(0xFFD1D5DB),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(width * 0.03),
                          ),
                          padding: EdgeInsets.symmetric(
                            vertical: width * 0.042,
                          ),
                          elevation: 2,
                        ),
                        child: Text(
                          'Confirm Address',
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
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────
  Widget _buildHeader(double w) {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.symmetric(horizontal: w * 0.04, vertical: w * 0.03),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: w * 0.09,
              height: w * 0.09,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(w * 0.025),
              ),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: w * 0.045,
                color: AppColors.primaryBlue,
              ),
            ),
          ),
          SizedBox(width: w * 0.03),
          Image.asset(
            'assets/images/newslogo.png',
            height: w * 0.085,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => Row(
              children: [
                Icon(
                  Icons.account_balance_rounded,
                  size: w * 0.07,
                  color: AppColors.primaryBlue,
                ),
                SizedBox(width: w * 0.02),
                Text(
                  'GovPulse',
                  style: TextStyle(
                    fontSize: w * 0.048,
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
}
