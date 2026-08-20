// lib/core/widgets/Home/sections/Web/home_footer.dart

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../../core/theme/citizen_ui.dart';

class HomeFooter extends StatelessWidget {
  const HomeFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final gutter = MediaQuery.of(context).size.width < 600 ? 20.0 : 40.0;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 20,
            spreadRadius: 0,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Contact strip ───────────────────────────────────────
          const _ContactStrip(),

          Container(height: 1, color: CitizenUi.sharedBorder),

          // ── Main footer columns ─────────────────────────────────
          Container(
            color: Colors.white,
            padding: EdgeInsets.fromLTRB(gutter, 40, gutter, 32),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 700;
                return isNarrow ? _buildNarrowFooter() : _buildWideFooter();
              },
            ),
          ),

          // ── Bottom bar ──────────────────────────────────────────
          // FIX: was a hard-coded Row that overflows when the two Text widgets
          // are wider than the viewport. Use Wrap so they reflow on narrow
          // screens (900–1000 px with aggressive zoom, or tablet-web).
          Container(
            color: const Color(0xFFF3F4F6),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
            child: const Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 4,
              children: [
                Text(
                  'Local Government Unit of Aparri  •  Official Citizen Portal',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF6B7280),
                  ),
                ),
                Text(
                  // FIX: year was hard-coded as 2024; updated to 2026 to match
                  // the rest of the codebase (home_contact_strip.dart says 2026).
                  '© 2026 LGU Aparri. All rights reserved.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWideFooter() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 3, child: _BrandColumn()),
        const SizedBox(width: 48),
        Expanded(
          flex: 2,
          child: _LinkColumn(
            title: 'Quick Links',
            links: const [
              'My Reports',
              'News & Updates',
              'Events',
              'Emergency',
              'About Us',
            ],
          ),
        ),
        const SizedBox(width: 32),
        Expanded(
          flex: 2,
          child: _LinkColumn(
            title: 'Support',
            links: const [
              'Help Center',
              'FAQs',
              'Privacy Policy',
              'Terms of Service',
              'Contact Us',
            ],
          ),
        ),
        const SizedBox(width: 32),
        Expanded(flex: 3, child: const _ContactColumn()),
      ],
    );
  }

  Widget _buildNarrowFooter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BrandColumn(),
        const SizedBox(height: 28),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _LinkColumn(
                title: 'Quick Links',
                links: const [
                  'My Reports',
                  'News & Updates',
                  'Events',
                  'Emergency',
                  'About Us',
                ],
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: _LinkColumn(
                title: 'Support',
                links: const [
                  'Help Center',
                  'FAQs',
                  'Privacy Policy',
                  'Terms of Service',
                  'Contact Us',
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        const _ContactColumn(),
      ],
    );
  }
}

// ── Brand column ──────────────────────────────────────────────────────────────
class _BrandColumn extends StatelessWidget {
  const _BrandColumn();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/applogocrop.webp',
              width: 28,
              height: 28,
              errorBuilder: (_, _, _) => const Icon(
                Icons.account_balance_rounded,
                size: 24,
                color: Color(0xFF1A4DB8),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'GovPulse',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A4DB8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Text(
          'A digital platform for a smarter,\nstronger, and more connected\nAparri community.',
          style: TextStyle(
            fontSize: 12.5,
            color: Color(0xFF6B7280),
            height: 1.55,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SocialIcon(icon: Icons.facebook_rounded, onTap: () {}),
            const SizedBox(width: 10),
            _SocialIcon(icon: Icons.open_in_new_rounded, onTap: () {}),
            const SizedBox(width: 10),
            _SocialIcon(icon: Icons.play_circle_rounded, onTap: () {}),
            const SizedBox(width: 10),
            _SocialIcon(icon: Icons.camera_alt_rounded, onTap: () {}),
          ],
        ),
      ],
    );
  }
}

class _SocialIcon extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _SocialIcon({required this.icon, required this.onTap});

  @override
  State<_SocialIcon> createState() => _SocialIconState();
}

class _SocialIconState extends State<_SocialIcon> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: _hover ? const Color(0xFF1A4DB8) : const Color(0xFFE5E7EB),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            widget.icon,
            size: 16,
            color: _hover ? Colors.white : const Color(0xFF6B7280),
          ),
        ),
      ),
    );
  }
}

// ── Link column ───────────────────────────────────────────────────────────────
class _LinkColumn extends StatelessWidget {
  final String title;
  final List<String> links;
  const _LinkColumn({required this.title, required this.links});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            color: Color(0xFF111827),
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 14),
        for (final link in links) ...[
          _FooterLink(label: link),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _FooterLink extends StatefulWidget {
  final String label;
  const _FooterLink({required this.label});

  @override
  State<_FooterLink> createState() => _FooterLinkState();
}

class _FooterLinkState extends State<_FooterLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 150),
        style: TextStyle(
          fontSize: 12.5,
          color: _hover ? const Color(0xFF1A4DB8) : const Color(0xFF6B7280),
          fontWeight: _hover ? FontWeight.w600 : FontWeight.w400,
        ),
        child: Text(widget.label),
      ),
    );
  }
}

// ── Contact column ────────────────────────────────────────────────────────────
class _ContactColumn extends StatelessWidget {
  const _ContactColumn();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Contact Us',
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            color: Color(0xFF111827),
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 14),
        _ContactRow(
          icon: Icons.location_on_rounded,
          text: 'LGU Aparri, Cagayan',
          color: const Color(0xFF1A4DB8),
        ),
        const SizedBox(height: 10),
        _ContactRow(
          icon: Icons.phone_rounded,
          text: '(078) 888-1234',
          color: const Color(0xFF1A4DB8),
          onTap: () async {
            final uri = Uri(scheme: 'tel', path: '+637888881234');
            if (await canLaunchUrl(uri)) launchUrl(uri);
          },
        ),
        const SizedBox(height: 10),
        _ContactRow(
          icon: Icons.email_rounded,
          text: 'info@aparri.gov.ph',
          color: const Color(0xFF1A4DB8),
          onTap: () async {
            final uri = Uri(scheme: 'mailto', path: 'info@aparri.gov.ph');
            if (await canLaunchUrl(uri)) launchUrl(uri);
          },
        ),
        const SizedBox(height: 10),
        _ContactRow(
          icon: Icons.access_time_rounded,
          text: 'Mon - Fri: 8:00 AM - 5:00 PM',
          color: const Color(0xFF1A4DB8),
        ),
      ],
    );
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  final VoidCallback? onTap;

  const _ContactRow({
    required this.icon,
    required this.text,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                color: onTap != null
                    ? const Color(0xFF1A4DB8)
                    : const Color(0xFF6B7280),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Contact strip ─────────────────────────────────────────────────────────────
// FIX: The previous _ContactStrip always rendered a horizontal Row with 4
// Expanded items and NO narrow-layout fallback. On screens where the footer
// goes narrow (< 600 px wide, or a tablet with aggressive zoom), the items
// became unreadably thin. The strip now switches to a 2×2 grid below 600 px
// and a single-column list below 400 px, matching the pattern used in the
// standalone home_contact_strip.dart widget.
class _ContactStrip extends StatelessWidget {
  const _ContactStrip();

  static const String _phoneDisplay = '+63 78 888 2001';
  static const String _phoneDial = '+63788882001';
  static const String _email = 'info@aparri.gov.ph';
  static const String _address = 'Municipal Hall, Luna St, Aparri 3515';
  static const String _facebook = 'Aparri LGU Official';

  Future<void> _call() async {
    final uri = Uri(scheme: 'tel', path: _phoneDial);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _mail() async {
    final uri = Uri(scheme: 'mailto', path: _email);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: MediaQuery.of(context).size.width < 600 ? 20 : 40,
        vertical: 20,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            spreadRadius: 0,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final items = [
            _StripItem(
              icon: Icons.phone_rounded,
              color: const Color(0xFF0D47A1),
              label: 'Call Us',
              value: _phoneDisplay,
              onTap: _call,
            ),
            _StripItem(
              icon: Icons.email_rounded,
              color: const Color(0xFF0EA5E9),
              label: 'Email Us',
              value: _email,
              onTap: _mail,
            ),
            _StripItem(
              icon: Icons.location_on_rounded,
              color: const Color(0xFFF59E0B),
              label: 'Visit Us',
              value: _address,
            ),
            _StripItem(
              icon: Icons.facebook_rounded,
              color: const Color(0xFF1877F2),
              label: 'Follow Us',
              value: _facebook,
            ),
          ];

          // Single column below 400 px
          if (c.maxWidth < 400) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < items.length; i++) ...[
                  items[i],
                  if (i < items.length - 1) ...[
                    const SizedBox(height: 12),
                    Container(
                      height: 1,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            Color(0xFFE5E7EB),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ],
            );
          }

          // 2×2 grid below 600 px
          if (c.maxWidth < 600) {
            return Column(
              children: [
                Row(
                  children: [
                    Expanded(child: items[0]),
                    Container(
                      width: 1,
                      height: 44,
                      color: const Color(0xFFE5E7EB),
                    ),
                    Expanded(child: items[1]),
                  ],
                ),
                const SizedBox(height: 14),
                Container(height: 1, color: const Color(0xFFF3F4F6)),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: items[2]),
                    Container(
                      width: 1,
                      height: 44,
                      color: const Color(0xFFE5E7EB),
                    ),
                    Expanded(child: items[3]),
                  ],
                ),
              ],
            );
          }

          // Full horizontal row (≥ 600 px)
          return Row(
            children: [
              for (int i = 0; i < items.length; i++) ...[
                Expanded(child: items[i]),
                if (i < items.length - 1)
                  Container(
                    width: 1,
                    height: 40,
                    color: const Color(0xFFE5E7EB),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _StripItem extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _StripItem({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withOpacity(0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: Color(0xFF9CA3AF),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: onTap != null
                          ? const Color(0xFF0D47A1)
                          : const Color(0xFF1F2937),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
