import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../features/profileVerification/verification_id_selection_screen.dart';

class VerificationScreen extends StatefulWidget {
  final String username;

  const VerificationScreen({super.key, required this.username});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen>
    with SingleTickerProviderStateMixin {
  double _scale = 1.0;

  @override
  void initState() {
    super.initState();
  }

  /// FEATURE CARD
  Widget _featureCard({
    required String icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            height: 35,
            width: 35,
            child: Image.asset(icon, fit: BoxFit.contain),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10.5, color: Color(0xFF6B7280)),
          ),
        ],
      ),
    );
  }

  /// MAIN CONTENT
  Widget _buildContent() {
    return Column(
      children: [
        const SizedBox(height: 16),

        /// ❌ LOGO REMOVED

        /// ILLUSTRATION
        Center(
          child: ColorFiltered(
            colorFilter: const ColorFilter.mode(
              Color(0xFFF3F4F6),
              BlendMode.modulate,
            ),
            child: Image.asset(
              "assets/images/verification/getver.gif",
              height: 150,
              fit: BoxFit.contain,
            ),
          ),
        ),

        const SizedBox(height: 24),

        /// 🔻 BOTTOM CARD
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.stroke),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                /// TITLE
                const Text(
                  "Why Need to be Fully Verified?",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: Color.fromARGB(255, 0, 106, 255),
                  ),
                ),

                const SizedBox(height: 14),

                /// GRID
                GridView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.3,
                  ),
                  children: [
                    _featureCard(
                      icon: "assets/images/verification/access.png",
                      title: "Access Full Services",
                      subtitle: "Unlock all LGU features",
                    ),
                    _featureCard(
                      icon: "assets/images/verification/checksec.png",
                      title: "Secure & Trusted",
                      subtitle: "Safe and protected account",
                    ),
                    _featureCard(
                      icon: "assets/images/verification/faster.png",
                      title: "Faster Transaction",
                      subtitle: "Quick processing of request",
                    ),
                    _featureCard(
                      icon: "assets/images/verification/verified.png",
                      title: "Verified Access",
                      subtitle: "Be recognized as a verified citizen",
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                /// ✨ PROFESSIONAL INFO BOX
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.stroke),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      /// HEADER
                      Row(
                        children: const [
                          Icon(
                            Icons.info_outline,
                            size: 16,
                            color: Color(0xFF6B7280),
                          ),
                          SizedBox(width: 6),
                          Text(
                            "Important Information",
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF374151),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      /// ITEM 1
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Icon(
                            Icons.badge_outlined,
                            size: 14,
                            color: Color(0xFF6B7280),
                          ),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              "Only valid government-issued IDs are accepted for verification.",
                              style: TextStyle(
                                fontSize: 10.5,
                                color: Color(0xFF6B7280),
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      /// ITEM 2
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Icon(
                            Icons.location_on_outlined,
                            size: 14,
                            color: Color(0xFF6B7280),
                          ),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              "Verification is currently available for Aparri residents only.",
                              style: TextStyle(
                                fontSize: 10.5,
                                color: Color(0xFF6B7280),
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      /// ITEM 3
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Icon(
                            Icons.person_outline,
                            size: 14,
                            color: Color(0xFF6B7280),
                          ),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              "Non-residents may continue using the app with limited access.",
                              style: TextStyle(
                                fontSize: 10.5,
                                color: Color(0xFF6B7280),
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                /// BUTTON
                GestureDetector(
                  onTapDown: (_) => setState(() => _scale = 0.96),
                  onTapUp: (_) => setState(() => _scale = 1.0),
                  onTapCancel: () => setState(() => _scale = 1.0),
                  onTap: () {
                    Navigator.push(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (_, _, _) => VerificationIdSelectionScreen(
                          username: widget.username,
                        ),
                        transitionsBuilder: (_, animation, _, child) {
                          final slide = Tween(
                            begin: const Offset(1, 0),
                            end: Offset.zero,
                          ).animate(animation);

                          return SlideTransition(position: slide, child: child);
                        },
                        transitionDuration: const Duration(milliseconds: 400),
                      ),
                    );
                  },
                  child: AnimatedScale(
                    scale: _scale,
                    duration: const Duration(milliseconds: 120),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: AppColors.green,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        "Verify Now",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// BUILD
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF3F4F6),
        elevation: 0,
        automaticallyImplyLeading: true,
        title: const Text(
          "Profile Verification",
          style: TextStyle(
            color: Color.fromARGB(255, 0, 106, 255),
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      body: SafeArea(child: SingleChildScrollView(child: _buildContent())),
    );
  }
}
