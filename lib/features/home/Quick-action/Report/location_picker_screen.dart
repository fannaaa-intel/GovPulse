import 'package:flutter/material.dart';
import '../../../../core/widgets/responsive_page.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'dart:async';
import 'package:geolocator/geolocator.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/app_dialog.dart';

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
const Map<String, LatLng> barangayCoords = {
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
  for (final entry in barangayCoords.entries) {
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
  final bool readOnly;

  const LocationPickerScreen({
    super.key,
    this.initialPosition,
    this.initialBarangay,
    this.readOnly = false,
  });

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryCtrl;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;
  bool _useCurrentLocation = false;
  bool _isLoadingGPS = false;
  String? _selectedBarangay;
  LatLng? _markerPosition;

  // MapTiler free-tier key for the display-only map tiles (streets-v2, retina).
  static const String _mapTilerKey = '0EIlUocqDFgChxbUV0Tu';

  @override
  void initState() {
    super.initState();

    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));

    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entryCtrl,
        curve: const Interval(0.0, 0.65, curve: Curves.easeOut),
      ),
    );
    _entryCtrl.forward();

    if (widget.initialBarangay != null &&
        widget.initialBarangay != 'Current Location') {
      _selectedBarangay = widget.initialBarangay;
      _markerPosition =
          barangayCoords[_selectedBarangay] ?? widget.initialPosition;
    } else if (widget.initialPosition != null) {
      _markerPosition = widget.initialPosition;
    }
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    super.dispose();
  }

  /// Closes the screen (optionally returning [result]). The OpenStreetMap view
  /// is a plain Flutter widget, so it fades out with the route on its own — no
  /// snapshot or platform-view handling needed.
  void _close([Map<String, dynamic>? result]) {
    Navigator.pop(context, result);
  }

  /// Display-only map — rendered with flutter_map + OpenStreetMap tiles, which
  /// draw entirely in Flutter (no Android platform view). It opens and fades
  /// with the route perfectly smoothly, needs no API key or billing, and never
  /// shows the platform-view flicker a live GoogleMap does. Location is chosen
  /// via the GPS toggle / barangay dropdown, so the map is non-interactive.
  Widget _mapArea(double width) {
    final center = _markerPosition ?? _aparriCenter;
    final double h = widget.readOnly ? width * 1.10 : width * 0.62;
    final llCenter = ll.LatLng(center.latitude, center.longitude);

    return ClipRRect(
      borderRadius: BorderRadius.circular(width * 0.035),
      child: SizedBox(
        height: h,
        width: double.infinity,
        // Neutral map-grey behind the tiles so any brief tile-load gap shows
        // this colour instead of white.
        child: ColoredBox(
          color: const Color(0xFFE8EAED),
          child: FlutterMap(
            // Re-create (recentre) whenever the chosen location changes.
            key: ValueKey('${center.latitude},${center.longitude}'),
            options: MapOptions(
              initialCenter: llCenter,
              initialZoom: 14,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.none,
              ),
            ),
            children: [
              TileLayer(
                // MapTiler "streets-v2" raster tiles (free tier). The {r}
                // placeholder becomes "@2x" on high-DPI screens (retinaMode),
                // fetching native double-resolution tiles so the map is crisp.
                urlTemplate:
                    'https://api.maptiler.com/maps/streets-v2/{z}/{x}/{y}{r}.png?key=$_mapTilerKey',
                userAgentPackageName: 'com.example.govpulse',
                retinaMode: RetinaMode.isHighDensity(context),
              ),
              if (_markerPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: llCenter,
                      width: 24,
                      height: 24,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.primaryBlue,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 4,
                              offset: Offset(0, 1),
                            ),
                          ],
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

  Future<void> _fetchCurrentLocation() async {
    setState(() => _isLoadingGPS = true);
    try {
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      if (!serviceOn) {
        if (mounted) {
          setState(() {
            _useCurrentLocation = false;
            _isLoadingGPS = false;
          });
          showAppSnackBar(
            context,
            "Location services are off. Please enable them to continue.",
            type: AppSnackType.error,
          );
        }
        return;
      }

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

      Position? pos;

      // ── Try high accuracy (FusedLocationProvider, your own timeout) ───────
      try {
        pos =
            await Geolocator.getCurrentPosition(
              locationSettings: AndroidSettings(
                accuracy: LocationAccuracy.high,
                forceLocationManager: false, // uses FusedLocationProvider
              ),
            ).timeout(
              const Duration(seconds: 20),
              onTimeout: () {
                debugPrint('GPS: high-accuracy timed out');
                throw TimeoutException('high-accuracy timeout');
              },
            );
      } catch (e) {
        debugPrint('GPS: high-accuracy failed → $e');
      }

      // ── Fallback 1: medium accuracy (WiFi + cell towers, works indoors) ───
      if (pos == null) {
        try {
          pos =
              await Geolocator.getCurrentPosition(
                locationSettings: AndroidSettings(
                  accuracy: LocationAccuracy.medium,
                  forceLocationManager: false,
                ),
              ).timeout(
                const Duration(seconds: 12),
                onTimeout: () {
                  debugPrint('GPS: medium-accuracy timed out');
                  throw TimeoutException('medium-accuracy timeout');
                },
              );
        } catch (e) {
          debugPrint('GPS: medium-accuracy failed → $e');
        }
      }

      // ── Fallback 2: low accuracy (cell towers only, fastest) ──────────────
      if (pos == null) {
        try {
          pos =
              await Geolocator.getCurrentPosition(
                locationSettings: AndroidSettings(
                  accuracy: LocationAccuracy.low,
                  forceLocationManager: false,
                ),
              ).timeout(
                const Duration(seconds: 8),
                onTimeout: () {
                  debugPrint('GPS: low-accuracy timed out');
                  throw TimeoutException('low-accuracy timeout');
                },
              );
        } catch (e) {
          debugPrint('GPS: low-accuracy failed → $e');
        }
      }

      // ── Fallback 3: last known cached position ────────────────────────────
      if (pos == null) {
        try {
          pos = await Geolocator.getLastKnownPosition();
          debugPrint('GPS: using last known → $pos');
        } catch (e) {
          debugPrint('GPS: last known failed → $e');
        }
      }

      if (pos == null) {
        debugPrint('All GPS attempts failed — pos is null');
        if (mounted) {
          setState(() {
            _useCurrentLocation = false;
            _isLoadingGPS = false;
          });
          showAppSnackBar(
            context,
            "Could not get your location. Please try again.",
            type: AppSnackType.error,
          );
        }
        return;
      }

      final latLng = LatLng(pos.latitude, pos.longitude);
      debugPrint('Got position: $latLng');

      if (!_isWithinAparri(latLng)) {
        if (mounted) {
          setState(() {
            _useCurrentLocation = false;
            _isLoadingGPS = false;
          });
          showAppSnackBar(
            context,
            "Your location is outside Aparri. Please pick a barangay manually.",
            type: AppSnackType.error,
          );
        }
        return;
      }

      // ── Success ───────────────────────────────────────────────────────────
      if (mounted) {
        final nearest = findNearestBarangay(latLng);
        setState(() {
          _markerPosition = latLng;
          _selectedBarangay = nearest;
          _useCurrentLocation = true; // ← only set true on actual success
          _isLoadingGPS = false;
        });
      }
    } catch (e) {
      debugPrint('Unexpected GPS error: $e');
      if (mounted) {
        setState(() {
          _useCurrentLocation = false;
          _isLoadingGPS = false;
        });
        showAppSnackBar(
          context,
          "Could not get your location. Please try again.",
          type: AppSnackType.error,
        );
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
      _close({
        'barangay': barangay,
        'useCurrentLocation': true,
        'latLng': _markerPosition,
      });
    } else {
      final coords = barangayCoords[_selectedBarangay] ?? _aparriCenter;
      _close({
        'barangay': _selectedBarangay,
        'useCurrentLocation': false,
        'latLng': coords,
      });
    }
  }

  // ── Dialogs ────────────────────────────────────────────────────────────────
  void _showPermissionDialog() {
    showAppDialog(
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
    final width = MediaQuery.of(context).size.width.clamp(0.0, 480.0);
    final bottomPad = MediaQuery.of(context).padding.bottom;

    final keyboardPad = MediaQuery.of(context).viewInsets.bottom;

    return PopScope(
      // Intercept the system back so the map is snapshotted and fades out with
      // the route, matching the header back button.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _close();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        resizeToAvoidBottomInset:
            false, // prevents GoogleMap from rebuilding when keyboard opens
        body: ResponsivePageBody(
          maxWidth: 640,
          child: SafeArea(
            child: Column(
              children: [
                // ── Header ──────────────────────────────────────────────────────
                _buildHeader(width),

                // ── Scrollable body (title + map + form all together) ────────────
                Expanded(
                  child: FadeTransition(
                    opacity: _fadeAnim,
                    child: SlideTransition(
                      position: _slideAnim,
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
                              widget.readOnly
                                  ? 'Pinned Location'
                                  : 'Edit Location',
                              style: TextStyle(
                                fontSize: width * 0.044,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF1F2937),
                              ),
                            ),
                            SizedBox(height: width * 0.008),
                            Text(
                              widget.readOnly
                                  ? 'Showing the exact location of the reported issue.'
                                  : 'Toggle GPS or select a barangay from the list.',
                              style: TextStyle(
                                fontSize: width * 0.030,
                                color: const Color(0xFF9CA3AF),
                              ),
                            ),
                            SizedBox(height: width * 0.03),

                            // ── Map inside a rounded container ───────────────────────
                            _mapArea(width),

                            if (!widget.readOnly) ...[
                              SizedBox(height: width * 0.04),

                              // ── Unified form card ────────────────────────────────────
                              Container(
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(
                                    width * 0.04,
                                  ),
                                  border: Border.all(
                                    color: const Color(0xFFE5E7EB),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.04,
                                      ),
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
                                              color: AppColors.primaryBlue
                                                  .withValues(alpha: 0.08),
                                              borderRadius:
                                                  BorderRadius.circular(
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
                                                    color: const Color(
                                                      0xFF1F2937,
                                                    ),
                                                  ),
                                                ),
                                                SizedBox(height: width * 0.005),
                                                Text(
                                                  'Detects your GPS position',
                                                  style: TextStyle(
                                                    fontSize: width * 0.027,
                                                    color: const Color(
                                                      0xFF9CA3AF,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (_isLoadingGPS)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                  ),
                                              child: SizedBox(
                                                width: 22,
                                                height: 22,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2.5,
                                                      color:
                                                          AppColors.primaryBlue,
                                                    ),
                                              ),
                                            )
                                          else
                                            Switch(
                                              value: _useCurrentLocation,
                                              onChanged: (v) async {
                                                if (!v) {
                                                  // Turning OFF — reset immediately
                                                  setState(() {
                                                    _useCurrentLocation = false;
                                                    _markerPosition =
                                                        _selectedBarangay !=
                                                            null
                                                        ? barangayCoords[_selectedBarangay]
                                                        : null;
                                                  });
                                                } else {
                                                  // Turning ON — let GPS fetch decide if it succeeds
                                                  await _fetchCurrentLocation();
                                                }
                                              },
                                              activeTrackColor:
                                                  AppColors.primaryBlue,
                                              activeThumbColor: Colors.white,
                                              inactiveThumbColor: Colors.white,
                                              inactiveTrackColor: const Color(
                                                0xFFD1D5DB,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),

                                    const Divider(
                                      height: 1,
                                      color: Color(0xFFE5E7EB),
                                    ),

                                    // ── Barangay section ───────────────────────────────
                                    Padding(
                                      padding: EdgeInsets.all(width * 0.04),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
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
                                            opacity: _useCurrentLocation
                                                ? 0.45
                                                : 1.0,
                                            duration: const Duration(
                                              milliseconds: 200,
                                            ),
                                            child: IgnorePointer(
                                              ignoring: _useCurrentLocation,
                                              child: Container(
                                                width: double.infinity,
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: width * 0.04,
                                                  vertical: width * 0.005,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: const Color(
                                                    0xFFF9FAFB,
                                                  ),
                                                  border: Border.all(
                                                    color: const Color(
                                                      0xFFE5E7EB,
                                                    ),
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        width * 0.025,
                                                      ),
                                                ),
                                                child: DropdownButton<String>(
                                                  value: _selectedBarangay,
                                                  isExpanded: true,
                                                  underline: const SizedBox(),
                                                  icon: Icon(
                                                    Icons
                                                        .keyboard_arrow_down_rounded,
                                                    color:
                                                        AppColors.primaryBlue,
                                                    size: width * 0.06,
                                                  ),
                                                  hint: Text(
                                                    _useCurrentLocation
                                                        ? 'Using current location'
                                                        : 'Select barangay',
                                                    style: TextStyle(
                                                      fontSize: width * 0.034,
                                                      color: const Color(
                                                        0xFF9CA3AF,
                                                      ),
                                                    ),
                                                  ),
                                                  style: TextStyle(
                                                    fontSize: width * 0.034,
                                                    color: const Color(
                                                      0xFF1F2937,
                                                    ),
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
                                                    final coords =
                                                        barangayCoords[val];
                                                    setState(() {
                                                      _selectedBarangay = val;
                                                      _markerPosition = coords;
                                                    });
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
                                                  padding: const EdgeInsets.all(
                                                    3,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.primaryBlue
                                                        .withValues(
                                                          alpha: 0.12,
                                                        ),
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: Icon(
                                                    Icons.check_rounded,
                                                    size: width * 0.032,
                                                    color:
                                                        AppColors.primaryBlue,
                                                  ),
                                                ),
                                                SizedBox(width: width * 0.02),
                                                Expanded(
                                                  child: Text(
                                                    '$_selectedBarangay selected',
                                                    style: TextStyle(
                                                      fontSize: width * 0.029,
                                                      color:
                                                          AppColors.primaryBlue,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
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
                                                      color:
                                                          AppColors.primaryBlue,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
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
                                    disabledBackgroundColor: const Color(
                                      0xFFD1D5DB,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        width * 0.03,
                                      ),
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
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
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
            onTap: () => _close(),
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
          if (!widget.readOnly)
            Image.asset(
              'assets/images/newslogo.webp',
              height: w * 0.085,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => Icon(
                Icons.account_balance_rounded,
                size: w * 0.065,
                color: AppColors.primaryBlue,
              ),
            ),
          if (!widget.readOnly) SizedBox(width: w * 0.03),
          Expanded(
            child: widget.readOnly
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Report Location',
                        style: TextStyle(
                          fontSize: w * 0.040,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1F2937),
                          letterSpacing: -0.2,
                        ),
                      ),
                      if (widget.initialBarangay != null)
                        Text(
                          '${widget.initialBarangay}, Aparri, Cagayan',
                          style: TextStyle(
                            fontSize: w * 0.027,
                            color: const Color(0xFF9CA3AF),
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
          if (widget.readOnly)
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: w * 0.025,
                vertical: w * 0.010,
              ),
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(w * 0.04),
                border: Border.all(
                  color: AppColors.primaryBlue.withValues(alpha: 0.20),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.visibility_rounded,
                    size: w * 0.030,
                    color: AppColors.primaryBlue,
                  ),
                  SizedBox(width: w * 0.010),
                  Text(
                    'View only',
                    style: TextStyle(
                      fontSize: w * 0.024,
                      fontWeight: FontWeight.w600,
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
