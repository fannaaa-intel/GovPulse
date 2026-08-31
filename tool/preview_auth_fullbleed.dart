// Preview target: the auth glass card at the widths that decide its shape.
//
//   flutter build web --release -t tool/preview_auth_fullbleed.dart
//
// The real login/signup screens reach Supabase and animate in, so this mounts
// WebGlassCard itself — the one widget every auth screen draws its surface
// with — over the same WebGlassSurface backdrop, with a stand-in form inside.
// What is being judged is the SHAPE decision (card vs full bleed) and the
// reading margin, which is exactly what this widget owns.
//
// Each frame gets its own MediaQuery, because the card reads the viewport
// rather than its own constraints — a card that decided from LayoutBuilder
// would go full-bleed inside a narrow COLUMN on a wide monitor, which is the
// bug this arrangement is here to avoid shipping.
import 'package:flutter/material.dart';

import 'package:govpulse/core/theme/app_colors.dart';
import 'package:govpulse/core/widgets/web/web_glass_card.dart';

void main() => runApp(const _App());

class _App extends StatelessWidget {
  const _App();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF2B2F3A),
        body: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              _Frame(width: 900, label: 'desktop 900 — card'),
              SizedBox(width: 24),
              _Frame(width: 700, label: 'tablet 700 — card'),
              SizedBox(width: 24),
              _Frame(width: 601, label: '601 — card (just above)'),
              SizedBox(width: 24),
              _Frame(width: 599, label: '599 — full bleed'),
              SizedBox(width: 24),
              _Frame(width: 390, label: 'phone 390 — full bleed'),
              SizedBox(width: 24),
              _Frame(width: 320, label: 'phone 320 — full bleed'),
            ],
          ),
        ),
      ),
    );
  }
}

class _Frame extends StatelessWidget {
  final double width;
  final String label;
  const _Frame({required this.width, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Container(
          width: width,
          height: 720,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(6)),
          // The card asks the MediaQuery for the viewport width, so each frame
          // has to declare its own or every one would read the real window.
          child: MediaQuery(
            data: MediaQueryData(size: Size(width, 720)),
            child: Scaffold(
              backgroundColor: const Color(0xFFEFF3FB),
              body: WebGlassSurface(
                child: SafeArea(
                  child: Builder(builder: (ctx) {
                    final bleed = authIsFullBleed(ctx);
                    final scroll = SingleChildScrollView(
                      padding: EdgeInsets.symmetric(
                        horizontal: bleed ? 0 : 40,
                        vertical: bleed ? 0 : 40,
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: bleed ? double.infinity : 460,
                        ),
                        child: WebGlassCard(child: const _Form()),
                      ),
                    );
                    // Centring a full-bleed page pins it to its own height and
                    // leaves the backdrop showing above and below; only the
                    // card layout wants centring.
                    return bleed
                        ? SizedBox(
                            width: double.infinity,
                            height: double.infinity,
                            child: scroll,
                          )
                        : Center(child: scroll);
                  }),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Stands in for _webFormContent — same shapes, no Supabase.
class _Form extends StatelessWidget {
  const _Form();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Image.asset('assets/images/applogocrop.webp',
                height: 34, errorBuilder: (_, _, _) => const SizedBox()),
            const SizedBox(width: 10),
            const Text('GovPulse',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryBlue)),
          ],
        ),
        const SizedBox(height: 30),
        const Text('Sign in',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text('Enter your credentials to access your account',
            style: TextStyle(fontSize: 14, color: Color(0xFF6B7280))),
        const SizedBox(height: 26),
        _field('Username', Icons.person_outline),
        const SizedBox(height: 14),
        _field('Password', Icons.lock_outline),
        const SizedBox(height: 10),
        const Align(
          alignment: Alignment.centerRight,
          child: Text('Forgot password?',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryBlue)),
        ),
        const SizedBox(height: 18),
        _primary('Sign in'),
        const SizedBox(height: 20),
        Row(children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('or',
                style: TextStyle(color: Colors.black.withValues(alpha: .45))),
          ),
          const Expanded(child: Divider()),
        ]),
        const SizedBox(height: 18),
        _outlined('Continue with Facebook', Icons.facebook),
        const SizedBox(height: 12),
        _outlined('Continue as guest', Icons.person_outline),
      ],
    );
  }

  Widget _field(String hint, IconData icon) => Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .75),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE3E6EF)),
        ),
        child: Row(children: [
          Icon(icon, size: 20, color: const Color(0xFF6B7280)),
          const SizedBox(width: 12),
          Text(hint,
              style: const TextStyle(fontSize: 15, color: Color(0xFF9CA3AF))),
        ]),
      );

  Widget _primary(String label) => Container(
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.primaryBlue,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700)),
      );

  Widget _outlined(String label, IconData icon) => Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFD8DEEA)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 20),
          const SizedBox(width: 10),
          Text(label,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600)),
        ]),
      );
}
