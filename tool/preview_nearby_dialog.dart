// Preview target: the "Already reported here?" duplicate-check dialog.
//
//   flutter run -d chrome -t tool/preview_nearby_dialog.dart
//
// ── What this round changed, and why it needed looking at ──────────────────
// The screenshot that prompted it showed a dialog whose HIERARCHY pointed at
// the wrong answer: "No — mine is a different issue" was a full-width bordered
// button, while "This is my issue — confirm it" — the thing the dialog exists
// to ask — was a bare text link in the bottom corner of a card. The citizen's
// eye lands on the decline.
//
// So the accept became a real filled button on the card, and the two declines
// stepped down to match what they are. The other half is size: the old card
// capped its list at a flat 260px and let the rest run free, which on a short
// phone or at a large text scale pushed the actions off the viewport — and a
// Dialog does not scroll, so they were simply gone.
//
// The frames below are the ones that would have caught both: a 1-card and a
// 3-card dialog at phone, tablet and desktop widths, plus a deliberately short
// viewport and 1.3x/1.6x text.
import 'package:flutter/material.dart';

import 'package:govpulse/core/theme/app_colors.dart';
import 'package:govpulse/core/theme/citizen_ui.dart';
import 'package:govpulse/core/widgets/no_scrollbar_behavior.dart';

void main() => runApp(const _App());

const _kMineIsDifferent = '__different__';

class _Nearby {
  final String id;
  final String shortRef;
  final String remarks;
  final String meta;
  final int reporterCount;
  const _Nearby({
    required this.id,
    required this.shortRef,
    required this.remarks,
    required this.meta,
    this.reporterCount = 1,
  });
}

const _one = [
  _Nearby(
    id: '1',
    shortRef: '49708275',
    remarks: 'test for staff',
    meta: '0 m away · 1m Ago · Macanaya (Pescaria)',
  ),
];

const _three = [
  _Nearby(
    id: '1',
    shortRef: '49708275',
    remarks: 'Deep pothole right at the corner, a tricycle already tipped.',
    meta: '12 m away · 1m Ago · Macanaya (Pescaria)',
    reporterCount: 4,
  ),
  _Nearby(
    id: '2',
    shortRef: '31882640',
    remarks: 'No description given.',
    meta: '48 m away · 3h Ago · Macanaya (Pescaria)',
  ),
  _Nearby(
    id: '3',
    shortRef: '77120934',
    remarks:
        'Streetlight has been out for two weeks and the whole stretch by the '
        'barangay hall is pitch dark after seven.',
    meta: '91 m away · 2d Ago · Centro 4',
    reporterCount: 2,
  ),
];

class _App extends StatelessWidget {
  const _App();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFEEF1F6),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '"Already reported here?" — duplicate check',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                const Text(
                  'The accept is now the only filled button on screen; the two '
                  'ways of declining are an outline and a text link. Each frame '
                  'is a real viewport — the dialog is capped at 85% of it, and '
                  'the CARD LIST is the part that scrolls, so the actions can '
                  'never leave the screen.',
                  style: TextStyle(
                      fontSize: 12, color: Colors.black54, height: 1.5),
                ),
                const SizedBox(height: 24),
                _Label('Phone · 360x640 · one match'),
                const SizedBox(height: 10),
                _Frame(w: 360, h: 640, items: _one),
                const SizedBox(height: 24),
                _Label('Phone · 360x640 · three matches (list scrolls)'),
                const SizedBox(height: 10),
                _Frame(w: 360, h: 640, items: _three),
                const SizedBox(height: 24),
                _Label('SHORT phone · 360x560 — the case that used to overflow'),
                const SizedBox(height: 10),
                _Frame(w: 360, h: 560, items: _three),
                const SizedBox(height: 24),
                _Label(
                  'SMALL phone · 320x568 · 1.3x — overflowed by 46px until the '
                  'chrome reserve scaled with the text',
                ),
                const SizedBox(height: 10),
                _Frame(w: 320, h: 568, items: _one, scale: 1.3),
                const SizedBox(height: 24),
                _Label('Phone · 1.3x text'),
                const SizedBox(height: 10),
                _Frame(w: 360, h: 640, items: _three, scale: 1.3),
                const SizedBox(height: 24),
                _Label('Phone · 1.6x text — the actions must still be on screen'),
                const SizedBox(height: 10),
                _Frame(w: 360, h: 640, items: _one, scale: 1.6),
                const SizedBox(height: 24),
                _Label('Tablet · 700x900'),
                const SizedBox(height: 10),
                _Frame(w: 700, h: 900, items: _three),
                const SizedBox(height: 24),
                _Label('Desktop web · 1200x820 — the 400px cap holds'),
                const SizedBox(height: 10),
                _Frame(w: 1200, h: 820, items: _three),
                const SizedBox(height: 40),
              ],
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
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.7,
          color: Colors.black54,
        ),
      );
}

/// A real viewport of the given size, with the dialog laid over a scrim, so the
/// height cap is exercised against a MediaQuery that is actually that tall.
class _Frame extends StatelessWidget {
  final double w;
  final double h;
  final List<_Nearby> items;
  final double scale;
  const _Frame({
    required this.w,
    required this.h,
    required this.items,
    this.scale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: const Color(0xFF9AA3B2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black26),
      ),
      clipBehavior: Clip.antiAlias,
      child: MediaQuery(
        data: MediaQueryData(
          size: Size(w, h),
          textScaler: TextScaler.linear(scale),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _Card(items: items),
          ),
        ),
      ),
    );
  }
}

/// Mirrors _showNearbyReportsDialog in report_issue_screen.dart.
class _Card extends StatelessWidget {
  final List<_Nearby> items;
  const _Card({required this.items});

  @override
  Widget build(BuildContext ctx) {
    final media = MediaQuery.of(ctx);
    final maxCardHeight = media.size.height * 0.85;
    // Scaled with the text: 320 is the chrome's height at 1.0 only, and a
    // fixed reserve overflowed a 320px phone at 1.3x by 46px.
    final scale = media.textScaler.scale(14) / 14;
    final listMax = (maxCardHeight - 320 * scale).clamp(72.0, 320.0);
    // On the tightest phone at 1.3x+ the header and actions alone exceed the
    // whole card (measured: 579px of chrome against a 483px budget), so the
    // header sheds its icon and its second sentence.
    final compact = maxCardHeight < 414 * scale;
    // Squeezed to its leftover height, the list clipped the first card partway
    // down — and what it cut was the accept button at the card's bottom edge.
    final oneCardHigh = 150 * scale;
    final listFloor = listMax < oneCardHigh
        ? oneCardHigh.clamp(0.0, maxCardHeight)
        : listMax;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: EdgeInsets.zero,
      constraints: BoxConstraints(
        maxWidth: 400,
        minWidth: 280,
        maxHeight: maxCardHeight,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: ScrollConfiguration(
            behavior: const NoScrollbarBehavior(),
            child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, compact ? 18 : 24, 24, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!compact) ...[
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.where_to_vote_outlined,
                      color: AppColors.primaryBlue,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                Text(
                  items.length == 1
                      ? 'Already reported here?'
                      : 'Already reported nearby?',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1F2937),
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  compact
                      ? 'Confirming pushes it up the queue.'
                      : items.length == 1
                          ? 'Someone has already reported an issue at this '
                                'spot. Confirming it pushes it up the queue.'
                          : 'These were reported near your pin. Confirming one '
                                'pushes it up the queue.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6B7280),
                    height: 1.5,
                  ),
                ),
                SizedBox(height: compact ? 12 : 16),
              ],
            ),
            ),
            ),
          ),
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: listFloor),
              // ⚠ ShaderMask on web: srcATop repaints whatever is already
              // behind the mask (see the admin-shimmer bug). dstIn only
              // multiplies alpha, which is what a fade wants — but that is
              // exactly the claim this preview exists to check, so look at the
              // three-card frames rather than trusting the mode name.
              child: ShaderMask(
                shaderCallback: (rect) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white, Colors.white, Colors.transparent],
                  stops: [0.0, 0.88, 1.0],
                ).createShader(rect),
                blendMode: BlendMode.dstIn,
                child: ScrollConfiguration(
                  behavior: const NoScrollbarBehavior(),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (int i = 0; i < items.length; i++) ...[
                          if (i > 0) const SizedBox(height: 10),
                          _card(ctx, items[i]),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
                24, compact ? 10 : 16, 24, compact ? 12 : 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, _kMineIsDifferent),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFD1D5DB)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  child: const Text(
                    'No — mine is a different issue',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF374151),
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  child: const Text(
                    'Go back and check my pin',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF6B7280),
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext ctx, _Nearby n) => Material(
        color: const Color(0xFFFAFBFD),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () {},
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              border: Border.all(color: CitizenUi.sharedBorder),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'RPT-${n.shortRef}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF6B7280),
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    if (n.reporterCount > 1) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primaryBlue.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${n.reporterCount} reports',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primaryBlue,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  n.remarks,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Color(0xFF1F2937),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  n.meta,
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.35,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
                const SizedBox(height: 11),
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: ElevatedButton.icon(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon:
                        const Icon(Icons.check_circle_outline_rounded, size: 16),
                    label: const Text(
                      'Yes, this is my issue',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
