import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class TermsOfServiceScreen extends StatefulWidget {
  const TermsOfServiceScreen({super.key});

  @override
  State<TermsOfServiceScreen> createState() => _TermsOfServiceScreenState();
}

class _TermsOfServiceScreenState extends State<TermsOfServiceScreen>
    with SingleTickerProviderStateMixin {
  // ── Content slide-up animation (mirrors ContactSupportScreen) ──────────────
  late final AnimationController _slideCtrl;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();

    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.10),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));
    _fadeAnim = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut));

    _slideCtrl.forward();
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: SafeArea(
        child: Column(
          children: [
            // Header is pinned — NOT part of the slide-up animation.
            _buildHeader(w),
            Expanded(
              child: FadeTransition(
                opacity: _fadeAnim,
                child: SlideTransition(
                  position: _slideAnim,
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      w * 0.04,
                      w * 0.035,
                      w * 0.04,
                      w * 0.08,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildIntroCard(w),
                        SizedBox(height: w * 0.05),
                        _sectionLabel(w, 'ACCEPTANCE OF TERMS'),
                        SizedBox(height: w * 0.02),
                        _buildCard(w, [
                          _buildBodyTile(
                            w,
                            icon: Icons.handshake_outlined,
                            color: AppColors.primaryBlue,
                            title: 'Agreement to Use',
                            body:
                                'By accessing or using GovPulse, you agree to be bound by these Terms of Service and all applicable laws. If you do not agree, you are not authorized to use this application.',
                          ),
                          _buildBodyTile(
                            w,
                            icon: Icons.update_rounded,
                            color: AppColors.primaryBlue,
                            title: 'Changes to Terms',
                            body:
                                'The Local Government Unit of Aparri, Cagayan reserves the right to modify these terms at any time. Continued use of the application after changes are posted constitutes your acceptance of the revised terms.',
                            showDivider: false,
                          ),
                        ]),
                        SizedBox(height: w * 0.05),
                        _sectionLabel(w, 'ELIGIBILITY & ACCOUNTS'),
                        SizedBox(height: w * 0.02),
                        _buildCard(w, [
                          _buildBodyTile(
                            w,
                            icon: Icons.person_outline_rounded,
                            color: AppColors.green,
                            title: 'Who May Register',
                            body:
                                'GovPulse is available to residents of Aparri, Cagayan who are at least 18 years of age and possess a valid government-issued ID for identity verification.',
                          ),
                          _buildBodyTile(
                            w,
                            icon: Icons.verified_user_outlined,
                            color: AppColors.green,
                            title: 'Account Responsibility',
                            body:
                                'You are responsible for maintaining the confidentiality of your account credentials and for all activities that occur under your account. Notify the LGU immediately of any unauthorized access.',
                            showDivider: false,
                          ),
                        ]),
                        SizedBox(height: w * 0.05),
                        _sectionLabel(w, 'ACCEPTABLE USE'),
                        SizedBox(height: w * 0.02),
                        _buildCard(w, [
                          _buildBodyTile(
                            w,
                            icon: Icons.thumb_up_alt_outlined,
                            color: AppColors.primaryBlue,
                            title: 'Permitted Activities',
                            body:
                                'You may use GovPulse to submit legitimate civic concerns, view community news, engage with LGU services, and interact with other verified citizens in a respectful manner.',
                          ),
                          _buildBodyTile(
                            w,
                            icon: Icons.block_outlined,
                            color: AppColors.red,
                            title: 'Prohibited Activities',
                            body:
                                'You must not submit false or misleading reports, impersonate other persons, engage in harassment or hate speech, attempt to gain unauthorized access to LGU systems, or use the application for any unlawful purpose.',
                            showDivider: false,
                          ),
                        ]),
                        SizedBox(height: w * 0.05),
                        _sectionLabel(w, 'CONTENT & PRIVACY'),
                        SizedBox(height: w * 0.02),
                        _buildCard(w, [
                          _buildBodyTile(
                            w,
                            icon: Icons.photo_library_outlined,
                            color: AppColors.orange,
                            title: 'User-Submitted Content',
                            body:
                                'By submitting reports, photos, or community posts, you grant the LGU a non-exclusive license to use that content for public service purposes. You retain ownership of your content.',
                          ),
                          _buildBodyTile(
                            w,
                            icon: Icons.lock_outline_rounded,
                            color: AppColors.orange,
                            title: 'Data & Privacy',
                            body:
                                'Your personal information is collected and processed in accordance with our Privacy Policy and the Philippine Data Privacy Act of 2012 (Republic Act No. 10173). We do not sell your personal data to third parties.',
                            showDivider: false,
                          ),
                        ]),
                        SizedBox(height: w * 0.05),
                        _sectionLabel(w, 'LIABILITY & ENFORCEMENT'),
                        SizedBox(height: w * 0.02),
                        _buildCard(w, [
                          _buildBodyTile(
                            w,
                            icon: Icons.gavel_rounded,
                            color: AppColors.primaryBlue,
                            title: 'Limitation of Liability',
                            body:
                                'The LGU of Aparri shall not be liable for any indirect, incidental, or consequential damages arising from your use of GovPulse. The application is provided "as is" without warranty of any kind.',
                          ),
                          _buildBodyTile(
                            w,
                            icon: Icons.warning_amber_rounded,
                            color: AppColors.red,
                            title: 'Account Suspension',
                            body:
                                'The LGU reserves the right to suspend or terminate accounts that violate these terms, submit fraudulent reports, or engage in conduct detrimental to the civic community.',
                            showDivider: false,
                          ),
                        ]),
                        SizedBox(height: w * 0.05),
                        _buildEffectiveNote(w),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header — identical to ContactSupportScreen for consistency ─────────────
  Widget _buildHeader(double w) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(w * 0.04, w * 0.04, w * 0.04, w * 0.035),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: w * 0.09,
              height: w * 0.09,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(w * 0.025),
                border: Border.all(color: AppColors.stroke),
              ),
              child: Icon(
                Icons.arrow_back_ios_rounded,
                size: w * 0.04,
                color: AppColors.primaryBlue,
              ),
            ),
          ),
          SizedBox(width: w * 0.035),
          Text(
            'Terms of Service',
            style: TextStyle(
              fontSize: w * 0.052,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryBlue,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }

  // ── Intro / hero card ──────────────────────────────────────────────────────
  Widget _buildIntroCard(double w) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(w * 0.05),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(w * 0.04),
        border: Border.all(color: AppColors.stroke),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: w * 0.16,
            height: w * 0.16,
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.description_outlined,
              size: w * 0.085,
              color: AppColors.primaryBlue,
            ),
          ),
          SizedBox(height: w * 0.035),
          Text(
            'Terms of Service',
            style: TextStyle(
              fontSize: w * 0.046,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1F2937),
            ),
          ),
          SizedBox(height: w * 0.018),
          Text(
            'Please read these terms carefully before using GovPulse. '
            'They govern your use of the civic engagement platform provided by the '
            'Local Government Unit of Aparri, Cagayan.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: w * 0.033,
              color: const Color(0xFF6B7280),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── Section label ──────────────────────────────────────────────────────────
  Widget _sectionLabel(double w, String text) {
    return Padding(
      padding: EdgeInsets.only(left: w * 0.01),
      child: Text(
        text,
        style: TextStyle(
          fontSize: w * 0.034,
          fontWeight: FontWeight.w700,
          color: AppColors.primaryBlue,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  // ── White rounded section container ────────────────────────────────────────
  Widget _buildCard(double w, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(w * 0.035),
        border: Border.all(color: AppColors.stroke),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  // ── Content tile (icon + title + body text) ────────────────────────────────
  Widget _buildBodyTile(
    double w, {
    required IconData icon,
    required Color color,
    required String title,
    required String body,
    bool showDivider = true,
  }) {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: w * 0.04,
            vertical: w * 0.038,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: w * 0.105,
                height: w * 0.105,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(w * 0.025),
                  border: Border.all(
                    color: color.withValues(alpha: 0.25),
                    width: 1.2,
                  ),
                ),
                child: Icon(icon, size: w * 0.05, color: color),
              ),
              SizedBox(width: w * 0.035),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: w * 0.038,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1F2937),
                      ),
                    ),
                    SizedBox(height: w * 0.012),
                    Text(
                      body,
                      style: TextStyle(
                        fontSize: w * 0.032,
                        color: const Color(0xFF6B7280),
                        height: 1.55,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Padding(
            padding: EdgeInsets.only(left: w * 0.175),
            child: const Divider(height: 1, color: AppColors.stroke),
          ),
      ],
    );
  }

  // ── Effective date note ────────────────────────────────────────────────────
  Widget _buildEffectiveNote(double w) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(w * 0.04),
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(w * 0.03),
        border: Border.all(
          color: AppColors.primaryBlue.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: w * 0.045,
            color: AppColors.primaryBlue,
          ),
          SizedBox(width: w * 0.025),
          Expanded(
            child: Text(
              'Effective Date: June 2025. For questions about these terms, '
              'please contact the LGU of Aparri through the Contact Support page.',
              style: TextStyle(
                fontSize: w * 0.030,
                color: const Color(0xFF374151),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
