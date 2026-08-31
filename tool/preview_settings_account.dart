// Preview target: the phone settings page's tail — ABOUT followed by the new
// ACCOUNT card.
//
//   flutter build web --release -t tool/preview_settings_account.dart
//
// The real screen branches its whole body on `kIsWeb`, so loading it in a
// browser shows the WEB layout and not the phone one that was changed. This
// rebuilds the mobile section stack from the same builders' constants, at the
// `uiScaleWidth` values a handset actually produces, so the thing being judged
// — does ACCOUNT sit in the page's rhythm — is what gets drawn.
//
// ?w= overrides the width (320..480).
import 'package:flutter/material.dart';

import 'package:govpulse/core/theme/app_colors.dart';
import 'package:govpulse/core/theme/citizen_ui.dart';
import 'package:govpulse/core/widgets/logout_control.dart';

void main() {
  final w = double.tryParse(Uri.base.queryParameters['w'] ?? '') ?? 390;
  runApp(_App(width: w.clamp(320, 480)));
}

class _App extends StatelessWidget {
  final double width;
  const _App({required this.width});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFFF3F4F6),
          body: SafeArea(
            child: Center(
              child: SizedBox(
                width: width,
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(width * 0.045),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _section(
                        'ABOUT',
                        width,
                        [
                          _tile(width,
                              icon: Icons.info_outline_rounded,
                              title: 'About GovPulse'),
                          _tile(width,
                              icon: Icons.place_outlined,
                              title: 'Location',
                              subtitle: 'Aparri, Cagayan',
                              chevron: false),
                          _tile(width,
                              icon: Icons.download_rounded,
                              title: 'App Version',
                              trailing: 'v1.0.0',
                              chevron: false,
                              divider: false),
                        ],
                      ),
                      SizedBox(height: width * 0.04),
                      _section(
                        'ACCOUNT',
                        width,
                        [
                          _dangerTile(width,
                              icon: Icons.logout_rounded, title: kLogoutLabel),
                          _dangerTile(width,
                              icon: Icons.delete_outline_rounded,
                              title: 'Delete account',
                              subtitle:
                                  'Permanently removes your account and its data',
                              divider: false),
                        ],
                      ),
                      SizedBox(height: width * 0.04),
                      Center(
                        child: Column(
                          children: [
                            Text('GovPulse',
                                style: TextStyle(
                                    fontSize: width * 0.030,
                                    color: AppColors.hint,
                                    fontWeight: FontWeight.w600)),
                            Text('Local Government Unit of Aparri, Cagayan',
                                style: TextStyle(
                                    fontSize: width * 0.028,
                                    color: AppColors.hint)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  /// Mirrors _buildSectionCard.
  Widget _section(String title, double width, List<Widget> children) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding:
                EdgeInsets.only(left: width * 0.01, bottom: width * 0.02),
            child: Text(
              title,
              style: TextStyle(
                fontSize: width * 0.034,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryBlue,
                letterSpacing: 0.3,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(width * 0.035),
              border: Border.all(color: CitizenUi.sharedStroke),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2)),
              ],
            ),
            child: Column(children: children),
          ),
        ],
      );

  /// Mirrors _buildTile.
  Widget _tile(
    double width, {
    required IconData icon,
    required String title,
    String? subtitle,
    String? trailing,
    bool chevron = true,
    bool divider = true,
  }) =>
      Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
                horizontal: width * 0.04, vertical: width * 0.034),
            child: Row(
              children: [
                Container(
                  width: width * 0.095,
                  height: width * 0.095,
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(width * 0.022),
                    border: Border.all(
                        color: AppColors.primaryBlue.withValues(alpha: 0.25),
                        width: 1.2),
                  ),
                  child: Icon(icon,
                      size: width * 0.05, color: AppColors.primaryBlue),
                ),
                SizedBox(width: width * 0.035),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              fontSize: width * 0.038,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF1F2937))),
                      if (subtitle != null) ...[
                        SizedBox(height: width * 0.005),
                        Text(subtitle,
                            style: TextStyle(
                                fontSize: width * 0.030,
                                color: AppColors.hint)),
                      ],
                    ],
                  ),
                ),
                if (trailing != null)
                  Text(trailing,
                      style: TextStyle(
                          fontSize: width * 0.034, color: AppColors.hint)),
                if (chevron)
                  Icon(Icons.arrow_forward_ios_rounded,
                      size: width * 0.035, color: const Color(0xFF9CA3AF)),
              ],
            ),
          ),
          if (divider)
            Divider(
                height: 1,
                thickness: 1,
                indent: width * 0.04,
                endIndent: width * 0.04,
                color: CitizenUi.sharedStroke),
        ],
      );

  /// Mirrors _buildDangerTile.
  Widget _dangerTile(
    double width, {
    required IconData icon,
    required String title,
    String? subtitle,
    bool divider = true,
  }) =>
      Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
                horizontal: width * 0.04, vertical: width * 0.034),
            child: Row(
              children: [
                Container(
                  width: width * 0.095,
                  height: width * 0.095,
                  decoration: BoxDecoration(
                    color: kLogoutTint,
                    borderRadius: BorderRadius.circular(width * 0.022),
                    border: Border.all(color: kLogoutBorder, width: 1.2),
                  ),
                  child:
                      Icon(icon, size: width * 0.05, color: AppColors.red),
                ),
                SizedBox(width: width * 0.035),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              fontSize: width * 0.038,
                              fontWeight: FontWeight.w700,
                              color: AppColors.red)),
                      if (subtitle != null) ...[
                        SizedBox(height: width * 0.005),
                        Text(subtitle,
                            style: TextStyle(
                                fontSize: width * 0.030,
                                color: AppColors.hint)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (divider)
            Divider(
                height: 1,
                thickness: 1,
                indent: width * 0.04,
                endIndent: width * 0.04,
                color: CitizenUi.sharedStroke),
        ],
      );
}
