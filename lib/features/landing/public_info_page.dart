import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/citizen_ui.dart';
import 'widgets/public_page_nav.dart';

/// Hosts Privacy Policy, Terms of Service and About GovPulse as PUBLIC web
/// pages, so the landing footer has somewhere real to send a visitor.
///
/// Those three screens were written for the account area, where Settings
/// pushes them and their back chevron pops back to it. Opened from the footer
/// there is no Settings underneath and nothing to pop, so [builder] is handed
/// the way out instead: back to the landing page. The nav above gives the same
/// two exits the 404 page does — the mark (home) and Sign in.
class PublicInfoPage extends StatelessWidget {
  final Widget Function(VoidCallback onBack) builder;

  const PublicInfoPage({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CitizenUi.pageBg,
      body: SafeArea(
        child: Column(
          children: [
            const ColoredBox(color: Colors.white, child: PublicPageNav()),
            const Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),
            Expanded(child: builder(() => context.go('/'))),
          ],
        ),
      ),
    );
  }
}
