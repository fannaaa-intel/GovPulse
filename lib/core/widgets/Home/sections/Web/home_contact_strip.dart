// lib/core/widgets/Home/sections/Web/home_contact_strip.dart

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class HomeContactStrip extends StatelessWidget {
  const HomeContactStrip({super.key});

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 28,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF1A4DB8), Color(0xFF2D9CDB)],
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    "We're Here to Help",
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.3,
                    ),
                  ),
                  Text(
                    'Get in touch through any of these channels',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFF9CA3AF)),
                  ),
                ],
              ),
            ],
          ),
        ),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE8EEF8), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1A4DB8).withOpacity(0.06),
                blurRadius: 32,
                spreadRadius: -4,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.025),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, c) {
              final isNarrow = c.maxWidth < 600;
              final items = <_ContactItemData>[
                _ContactItemData(
                  icon: Icons.phone_rounded,
                  gradColors: [
                    const Color(0xFF0D47A1),
                    const Color(0xFF2D9CDB),
                  ],
                  label: 'Call Us',
                  value: _phoneDisplay,
                  onTap: _call,
                ),
                _ContactItemData(
                  icon: Icons.email_rounded,
                  gradColors: [
                    const Color(0xFF0EA5E9),
                    const Color(0xFF38BDF8),
                  ],
                  label: 'Email Us',
                  value: _email,
                  onTap: _mail,
                ),
                _ContactItemData(
                  icon: Icons.location_on_rounded,
                  gradColors: [
                    const Color(0xFFF59E0B),
                    const Color(0xFFFBBF24),
                  ],
                  label: 'Visit Us',
                  value: _address,
                ),
                _ContactItemData(
                  icon: Icons.facebook_rounded,
                  gradColors: [
                    const Color(0xFF1877F2),
                    const Color(0xFF3B82F6),
                  ],
                  label: 'Follow Us',
                  value: _facebook,
                ),
              ];

              if (isNarrow) {
                return Column(
                  children: [
                    for (int i = 0; i < items.length; i++) ...[
                      _ContactItem(data: items[i]),
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

              final useGrid = c.maxWidth >= 700;
              if (useGrid) {
                return Row(
                  children: [
                    for (int i = 0; i < items.length; i++) ...[
                      Expanded(child: _ContactItem(data: items[i])),
                      if (i < items.length - 1)
                        Container(
                          width: 1,
                          height: 44,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Color(0xFFDDE2ED),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                    ],
                  ],
                );
              }

              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: _ContactItem(data: items[0])),
                      Container(
                        width: 1,
                        height: 44,
                        color: const Color(0xFFE5E7EB),
                      ),
                      Expanded(child: _ContactItem(data: items[1])),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(height: 1, color: const Color(0xFFF3F4F6)),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(child: _ContactItem(data: items[2])),
                      Container(
                        width: 1,
                        height: 44,
                        color: const Color(0xFFE5E7EB),
                      ),
                      Expanded(child: _ContactItem(data: items[3])),
                    ],
                  ),
                ],
              );
            },
          ),
        ),

        const SizedBox(height: 20),

        Container(
          height: 1,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                Color(0xFFDDE2ED),
                Colors.transparent,
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Image.asset(
              'assets/images/applogocrop.png',
              height: 15,
              errorBuilder: (_, _, _) => const Icon(
                Icons.account_balance_rounded,
                size: 14,
                color: Color(0xFF0D47A1),
              ),
            ),
            const Text(
              'Local Government Unit of Aparri',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6B7280),
              ),
            ),
            Container(
              width: 3,
              height: 3,
              decoration: const BoxDecoration(
                color: Color(0xFFD1D5DB),
                shape: BoxShape.circle,
              ),
            ),
            const Text(
              'Official Citizen Portal',
              style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
            ),
          ],
        ),
        const SizedBox(height: 5),
        const Text(
          '© 2026 Municipality of Aparri, Cagayan. All rights reserved.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: Color(0xFFB0B6BE)),
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}

class _ContactItemData {
  final IconData icon;
  final List<Color> gradColors;
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _ContactItemData({
    required this.icon,
    required this.gradColors,
    required this.label,
    required this.value,
    this.onTap,
  });
}

// ── Contact item — smooth icon fill + text color, no border flicker ───────────
class _ContactItem extends StatefulWidget {
  final _ContactItemData data;
  const _ContactItem({required this.data});

  @override
  State<_ContactItem> createState() => _ContactItemState();
}

class _ContactItemState extends State<_ContactItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final tappable = d.onTap != null;
    return MouseRegion(
      cursor: tappable ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: d.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // FIX 2: use a gradient in BOTH states. Previously the resting
              // state set `color:` (gradient null) and hover set `gradient:`
              // (color null). AnimatedContainer can't lerp color↔gradient, so
              // it snapped instead of fading. The resting state is now a
              // two-identical-color gradient, so only the colors interpolate.
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: _hover
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: d.gradColors,
                        )
                      : LinearGradient(
                          colors: [
                            d.gradColors.first.withOpacity(0.10),
                            d.gradColors.first.withOpacity(0.10),
                          ],
                        ),
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: _hover
                      ? [
                          BoxShadow(
                            color: d.gradColors.first.withOpacity(0.24),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : [],
                ),
                child: Icon(
                  d.icon,
                  size: 18,
                  color: _hover ? Colors.white : d.gradColors.first,
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 0), // alignment anchor
                    Text(
                      d.label,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: Color(0xFF9CA3AF),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: (tappable && _hover)
                            ? const Color(0xFF0D47A1)
                            : const Color(0xFF1F2937),
                        decoration: (tappable && _hover)
                            ? TextDecoration.underline
                            : TextDecoration.none,
                        decorationColor: const Color(0xFF0D47A1),
                      ),
                      child: Text(
                        d.value,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
