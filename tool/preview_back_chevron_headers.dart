// Dev-only harness for the app-wide BACK CHEVRON + header combination.
//
// Not part of the app: nothing under lib/ imports it, and it is never a build
// target for a shipped bundle.
//
//   flutter build web --release -t tool/preview_back_chevron_headers.dart
//   python -m http.server 57815 --directory build/web
//
// ── Why this exists ────────────────────────────────────────────────────────
// The chevron + title block was unified across citizen, admin and staff in one
// sweep touching 20+ screens. Most of those screens are behind a login, a role
// gate or a multi-step form, so opening each one to eyeball the header is not
// practical. This renders the three shared implementations side by side, at a
// phone width, so "are they actually the same control" is one screenshot.
//
// ── What to look at ────────────────────────────────────────────────────────
//  * All three chips are OUTLINES — no grey fill — with a neutral glyph.
//  * All three titles are near-black. Nothing in a header is blue any more:
//    back is chrome and a page's own name is not an action.
//  * The citizen chip scales off the layout width; the two consoles are fixed
//    at 32px because they are desktop surfaces. They should still read as the
//    same control at a phone width, which is what this compares.

import 'package:flutter/material.dart';

import 'package:govpulse/core/widgets/app_back_chevron.dart';
import 'package:govpulse/core/widgets/app_screen_header.dart';
import 'package:govpulse/features/admin/theme/admin_ui.dart';
import 'package:govpulse/features/admin/widgets/admin_dialog_back.dart';

void main() => runApp(const _PreviewApp());

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF1F2937),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: SizedBox(
                width: 390,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: const [
                    _Label('CITIZEN — AppScreenHeader (shared widget)'),
                    AppScreenHeader(title: 'Terms of Service', width: 390),
                    SizedBox(height: 22),

                    _Label('CITIZEN — hand-rolled settings header'),
                    _CitizenHandRolled(title: 'About GovPulse'),
                    SizedBox(height: 22),

                    _Label('ADMIN — AdminChevronHeader'),
                    _AdminHeader(title: 'Event details'),
                    SizedBox(height: 22),

                    _Label('ADMIN — sheet header (Activity log)'),
                    _AdminSheetHeader(title: 'Activity log'),
                    SizedBox(height: 22),

                    _Label('STAFF — thread header chevron'),
                    _StaffHeader(title: 'Juan Dela Cruz'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white70,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
      ),
    ),
  );
}

/// A transcription of the settings-screen header block, which each of the nine
/// settings screens still draws inline rather than through [AppScreenHeader].
class _CitizenHandRolled extends StatelessWidget {
  final String title;
  const _CitizenHandRolled({required this.title});

  @override
  Widget build(BuildContext context) {
    const w = 390.0;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(
        w * 0.04,
        w * 0.04,
        w * 0.04,
        w * 0.035,
      ),
      child: Row(
        children: [
          Container(
            width: w * 0.09,
            height: w * 0.09,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(w * 0.025),
              border: Border.all(color: kBackChevronBorder),
            ),
            child: const Icon(
              Icons.arrow_back_ios_new_rounded,
              size: w * 0.046,
              color: kBackChevronGlyph,
            ),
          ),
          const SizedBox(width: w * 0.035),
          Text(
            title,
            style: const TextStyle(
              fontSize: w * 0.052,
              fontWeight: FontWeight.w700,
              color: kScreenTitleColor,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminHeader extends StatelessWidget {
  final String title;
  const _AdminHeader({required this.title});

  @override
  Widget build(BuildContext context) => Container(
    color: AdminUi.surface,
    padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
    child: Row(
      children: [
        AdminDialogBack(onTap: () {}),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AdminUi.textPrimary,
            letterSpacing: -0.3,
          ),
        ),
      ],
    ),
  );
}

class _AdminSheetHeader extends StatelessWidget {
  final String title;
  const _AdminSheetHeader({required this.title});

  @override
  Widget build(BuildContext context) => Container(
    color: AdminUi.surface,
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
    child: Row(
      children: [
        AdminDialogBack(onTap: () {}),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: AdminUi.textPrimary,
            letterSpacing: -0.3,
          ),
        ),
      ],
    ),
  );
}

class _StaffHeader extends StatelessWidget {
  final String title;
  const _StaffHeader({required this.title});

  @override
  Widget build(BuildContext context) => Container(
    color: Colors.white,
    padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
    child: Row(
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kBackChevronBorder),
          ),
          child: const Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 18,
            color: kBackChevronGlyph,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: kScreenTitleColor,
          ),
        ),
      ],
    ),
  );
}
