// Throwaway preview: the citizen-web "View on map" page (the read-only
// LocationPickerScreen) rendered on its own, so its header, card and
// responsiveness can be LOOKED AT without logging in and opening a report.
//
//   flutter run -d web-server --web-port 57815 -t tool/preview_report_location_map.dart
//
// The real page is pushed inside the citizen shell's centre column, so the box
// it gets is the window minus the two rails — not the window. The grey blocks
// either side stand in for those rails at their real widths, which is what
// makes the centring and the 760 cap look here the way they look in the app.
import 'package:flutter/material.dart';

import 'package:govpulse/features/home/Quick-action/Report/location_picker_screen.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;

void main() => runApp(const _App());

class _App extends StatelessWidget {
  const _App();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFF3F4F6),
        body: LayoutBuilder(
          builder: (context, c) {
            // Below the shell's own collapse point there are no rails, so the
            // page gets the whole window — same as the app.
            final rails = c.maxWidth >= 1100;
            return Row(
              children: [
                if (rails) const _Rail(width: 288, label: 'left rail'),
                const Expanded(
                  child: LocationPickerScreen(
                    initialPosition: LatLng(18.3720, 121.6890),
                    initialBarangay: 'Dodan',
                    readOnly: true,
                  ),
                ),
                if (rails) const _Rail(width: 340, label: 'quick actions'),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  final double width;
  final String label;
  const _Rail({required this.width, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      color: const Color(0xFFE9EDF3),
      alignment: Alignment.topCenter,
      padding: const EdgeInsets.only(top: 24),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
      ),
    );
  }
}
