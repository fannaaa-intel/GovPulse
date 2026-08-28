// Dev-only harness for the HOME PROFILE CARD's verified seal.
//
//   flutter build web --release -t tool/preview_verified_name_badge.dart
//
// ── What it is for ─────────────────────────────────────────────────────────
// The seal moved out of a full-width strip below the name and onto the name's
// own line, and the sentence it used to carry is now revealed on tap/hover.
// The point of the change is VERTICAL SPACE — the quick actions below the card
// should reach the first screenful — so the thing worth looking at is the two
// cards side by side at the same width, where the height difference is the
// whole argument.
//
// [HomeProfileCard] takes no Supabase session and no provider scope: it is a
// StatelessWidget over plain fields, so unlike the other previews in this
// folder there is nothing here to fake. The `width` parameter is passed
// explicitly (rather than left to MediaQuery) so both frames lay out at the
// 390dp of a modern phone no matter how wide the browser is — the same reason
// the real web shell caps it.
import 'package:flutter/material.dart';

import 'package:govpulse/core/widgets/Home/home_enums.dart';
import 'package:govpulse/core/widgets/Home/sections/home_profile_card.dart';

/// A modern phone's logical width — what the card is proportioned for.
const double _kPhone = 390;

void main() => runApp(const _App());

class _App extends StatelessWidget {
  const _App();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Verified name badge preview',
      home: Scaffold(
        backgroundColor: const Color(0xFFEEF2F6),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: Wrap(
                spacing: 36,
                runSpacing: 36,
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.start,
                children: const [
                  _Frame(
                    label: 'VERIFIED — seal on the name',
                    note: 'Tap or hover the seal for the sentence.',
                    status: VerifStatus.verified,
                  ),
                  _Frame(
                    label: 'VERIFIED — long name',
                    note: 'Name ellipsizes; the seal keeps its place.',
                    status: VerifStatus.verified,
                    fullName: 'Bonifacio Maximiliano Villanueva-Dimaculangan',
                  ),
                  _Frame(
                    label: 'PENDING — unchanged',
                    note: 'No seal until verification lands.',
                    status: VerifStatus.pending,
                  ),
                  _Frame(
                    label: 'NOT VERIFIED — unchanged',
                    note: 'No seal.',
                    status: VerifStatus.none,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One card at phone width, captioned, on a white strip exactly [_kPhone] wide
/// so the four frames can be compared edge to edge and height to height.
class _Frame extends StatelessWidget {
  final String label;
  final String note;
  final VerifStatus status;
  final String fullName;

  const _Frame({
    required this.label,
    required this.note,
    required this.status,
    this.fullName = 'Mark Reduca',
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _kPhone,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            note,
            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 10),
          DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: HomeProfileCard(
                width: _kPhone,
                username: 'Mark',
                verifStatus: status,
                fullName: fullName,
                facePhotoUrl: null,
                profileLoading: false,
                notificationCount: 3,
                onNotificationTap: () {},
                onVerifyTap: () {},
              ),
            ),
          ),
        ],
      ),
    );
  }
}
