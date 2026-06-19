import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/loading/loading_overlay.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/widgets/modal/verification_required_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/user_profile_provider.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  final String username;

  const EditProfileScreen({super.key, required this.username});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen>
    with TickerProviderStateMixin {
  // ── Animation ─────────────────────────────────────────────────────────────
  late final AnimationController _slideCtrl;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;

  // ── Form ──────────────────────────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _middleNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _barangayCtrl = TextEditingController();
  final _streetCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();

  // ── State ─────────────────────────────────────────────────────────────────
  bool _loading = true;
  bool _saving = false;
  bool _isVerified = false;
  String? _errorMessage;

  // ── Stats ─────────────────────────────────────────────────────────────────
  int _reportCount = 0;
  String? _memberSince;
  String? _barangay;

  // ── Photo ─────────────────────────────────────────────────────────────────
  String? _currentPhotoUrl;
  String? _currentPhotoPath;
  String? _facePhotoPath;
  File? _pickedFile;
  Uint8List? _pickedBytes;

  // ── 30-day lock ───────────────────────────────────────────────────────────
  DateTime? _lastProfileUpdatedAt;
  bool get _isLocked {
    if (_lastProfileUpdatedAt == null) return false;
    return DateTime.now().difference(_lastProfileUpdatedAt!).inDays < 30;
  }

  int get _daysRemaining {
    if (_lastProfileUpdatedAt == null) return 0;
    final diff = 30 - DateTime.now().difference(_lastProfileUpdatedAt!).inDays;
    return diff.clamp(0, 30);
  }

  @override
  void initState() {
    super.initState();
    _isVerified = true;
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutQuart));
    _fadeAnim = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut));
    _loadData();
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    _firstNameCtrl.dispose();
    _middleNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _barangayCtrl.dispose();
    _streetCtrl.dispose();
    _contactCtrl.dispose();
    super.dispose();
  }

  // ── Load data ─────────────────────────────────────────────────────────────
  Future<void> _loadData() async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) {
        setState(() => _loading = false);
        return;
      }

      final verifRow = await supabase
          .from('verification_submissions')
          .select('status, face_photo_path')
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      final status = verifRow?['status'] as String? ?? 'none';
      final verified = status == 'approved';

      if (verified) {
        final cd = await supabase
            .from('citizen_details')
            .select(
              'first_name, middle_name, last_name, '
              'contact_number, barangay, street, '
              'created_at, profile_photo_path, last_profile_updated_at',
            )
            .eq('user_id', user.id)
            .maybeSingle();

        if (cd != null) {
          _firstNameCtrl.text = cd['first_name'] as String? ?? '';
          _middleNameCtrl.text = cd['middle_name'] as String? ?? '';
          _lastNameCtrl.text = cd['last_name'] as String? ?? '';
          _contactCtrl.text = cd['contact_number'] as String? ?? '';
          _streetCtrl.text = cd['street'] as String? ?? '';

          final barangayVal = cd['barangay'] as String? ?? '';
          _barangayCtrl.text = barangayVal;
          _barangay = barangayVal;

          final createdRaw = cd['created_at'];
          if (createdRaw != null) {
            final dt = DateTime.tryParse(createdRaw.toString());
            if (dt != null) _memberSince = dt.year.toString();
          }

          final updatedRaw = cd['last_profile_updated_at'];
          if (updatedRaw != null) {
            _lastProfileUpdatedAt = DateTime.tryParse(updatedRaw.toString());
          }

          _facePhotoPath = verifRow?['face_photo_path'] as String?;

          final photoPath =
              (cd['profile_photo_path'] as String?)?.isNotEmpty == true
              ? cd['profile_photo_path'] as String
              : null;

          if (photoPath != null && photoPath.isNotEmpty) {
            _currentPhotoPath = photoPath;
            _currentPhotoUrl = supabase.storage
                .from('profile-photos')
                .getPublicUrl(photoPath);
          }
        }

        try {
          final countRes = await supabase
              .from('reports')
              .select('id')
              .eq('user_id', user.id);
          _reportCount = (countRes as List).length;
        } catch (_) {
          _reportCount = 0;
        }
      }

      if (mounted) {
        setState(() {
          _isVerified = true;
          _loading = false;
        });
        _slideCtrl.forward();
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Pick photo ────────────────────────────────────────────────────────────
  Future<void> _pickPhoto() async {
    if (_isLocked) return;
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 800,
    );
    if (picked == null) return;

    final file = File(picked.path);
    final bytes = await file.readAsBytes();
    setState(() {
      _pickedFile = file;
      _pickedBytes = bytes;
    });
  }

  // ── Save ──────────────────────────────────────────────────────────────────
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isLocked) return;

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) throw 'Not authenticated';

      String? newPhotoPath;

      if (_pickedFile != null && _pickedBytes != null) {
        final ext = _pickedFile!.path.split('.').last;
        final filePath =
            '${user.id}/profile_${DateTime.now().millisecondsSinceEpoch}.$ext';

        String mimeType;
        switch (ext.toLowerCase()) {
          case 'jpg':
          case 'jpeg':
            mimeType = 'image/jpeg';
            break;
          case 'png':
            mimeType = 'image/png';
            break;
          case 'webp':
            mimeType = 'image/webp';
            break;
          default:
            mimeType = 'image/jpeg';
        }

        await supabase.storage
            .from('profile-photos')
            .uploadBinary(
              filePath,
              _pickedBytes!,
              fileOptions: FileOptions(contentType: mimeType, upsert: true),
            );
        newPhotoPath = filePath;
      }

      final now = DateTime.now().toUtc().toIso8601String();
      final updateData = <String, dynamic>{
        'first_name': _firstNameCtrl.text.trim(),
        'middle_name': _middleNameCtrl.text.trim(),
        'last_name': _lastNameCtrl.text.trim(),
        'barangay': _barangayCtrl.text.trim(),
        'street': _streetCtrl.text.trim(),
        'contact_number': _contactCtrl.text.trim(),
        'last_profile_updated_at': now,
      };
      if (newPhotoPath != null) {
        updateData['profile_photo_path'] = newPhotoPath;
        if (_currentPhotoPath != null) {
          await CachedNetworkImage.evictFromCache(_currentPhotoPath!);
          final isFaceScan = _currentPhotoPath == _facePhotoPath;
          if (!isFaceScan) {
            try {
              await supabase.storage.from('profile-photos').remove([
                _currentPhotoPath!,
              ]);
            } catch (_) {}
          }
        }
        _currentPhotoPath = newPhotoPath;
      }
      await supabase
          .from('citizen_details')
          .update(updateData)
          .eq('user_id', user.id);

      if (!mounted) return;
      await showSuccessDialog(
        context,
        title: 'Profile Updated',
        message: 'Your profile information has been saved successfully.',
      );
      if (!mounted) return;
      ref.read(userProfileProvider.notifier).refresh();
      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to save changes. Please try again.';
        _saving = false;
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    return LoadingOverlay(
      isLoading: _saving,
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F4F6),
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(width),
              Expanded(
                child: LoadingOverlay.bodyOrSkeleton(
                  isLoading: _loading,
                  layout: SkeletonLayout.editProfile,
                  child: FadeTransition(
                    opacity: _fadeAnim,
                    child: SlideTransition(
                      position: _slideAnim,
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(
                          width * 0.04,
                          width * 0.02,
                          width * 0.04,
                          width * 0.08,
                        ),
                        child: _isVerified
                            ? _buildForm(width)
                            : _buildNotVerifiedState(width),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader(double width) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        width * 0.02,
        width * 0.04,
        width * 0.04,
        width * 0.03,
      ),
      color: const Color(0xFFF3F4F6),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: width * 0.09,
              height: width * 0.09,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(width * 0.025),
                border: Border.all(color: AppColors.stroke),
              ),
              child: Icon(
                Icons.arrow_back_ios_rounded,
                size: width * 0.04,
                color: AppColors.primaryBlue,
              ),
            ),
          ),
          SizedBox(width: width * 0.02),
          Text(
            'Edit Profile',
            style: TextStyle(
              fontSize: width * 0.055,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryBlue,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }

  // ── Not verified ──────────────────────────────────────────────────────────
  Widget _buildNotVerifiedState(double width) {
    return Column(
      children: [
        SizedBox(height: width * 0.08),
        Container(
          padding: EdgeInsets.all(width * 0.06),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(width * 0.04),
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
                width: width * 0.22,
                height: width * 0.22,
                decoration: BoxDecoration(
                  color: AppColors.orange.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.verified_user_outlined,
                  size: width * 0.12,
                  color: AppColors.orange,
                ),
              ),
              SizedBox(height: width * 0.05),
              Text(
                'Verification Required',
                style: TextStyle(
                  fontSize: width * 0.048,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1F2937),
                ),
              ),
              SizedBox(height: width * 0.025),
              Text(
                'Only verified citizens can edit their profile information. '
                'Please complete the identity verification process first.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: width * 0.034,
                  color: AppColors.hint,
                  height: 1.55,
                ),
              ),
              SizedBox(height: width * 0.055),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    elevation: 0,
                    padding: EdgeInsets.symmetric(vertical: width * 0.04),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(width * 0.03),
                    ),
                  ),
                  child: Text(
                    'Go Back',
                    style: TextStyle(
                      fontSize: width * 0.038,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Main form ─────────────────────────────────────────────────────────────
  Widget _buildForm(double width) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAvatarCard(width),
          SizedBox(height: width * 0.04),

          if (_isLocked) ...[
            _buildLockBanner(width),
            SizedBox(height: width * 0.04),
          ],

          _buildSectionLabel('ACCOUNT', width),
          SizedBox(height: width * 0.02),
          _buildCard(
            width: width,
            children: [
              _buildLockedDisplayField(
                label: 'Email',
                value: Supabase.instance.client.auth.currentUser?.email ?? '—',
                icon: 'assets/images/email.webp',
                width: width,
              ),
              _divider(width),
              _buildLockedDisplayField(
                label: 'Username',
                value: widget.username,
                icon: '@',
                width: width,
              ),
            ],
          ),
          SizedBox(height: width * 0.04),

          _buildSectionLabel('PERSONAL INFORMATION', width),
          SizedBox(height: width * 0.02),
          _buildCard(
            width: width,
            children: [
              _buildField(
                ctrl: _firstNameCtrl,
                label: 'First Name',
                hint: 'Enter first name',
                icon: 'assets/images/username.webp',
                width: width,
                enabled: !_isLocked,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              _divider(width),
              _buildField(
                ctrl: _middleNameCtrl,
                label: 'Middle Name',
                hint: 'Enter middle name (optional)',
                icon: 'assets/images/username.webp',
                width: width,
                enabled: !_isLocked,
              ),
              _divider(width),
              _buildField(
                ctrl: _lastNameCtrl,
                label: 'Last Name',
                hint: 'Enter last name',
                icon: 'assets/images/username.webp',
                width: width,
                enabled: !_isLocked,
                showDivider: false,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
            ],
          ),
          SizedBox(height: width * 0.04),

          _buildSectionLabel('CONTACT', width),
          SizedBox(height: width * 0.02),
          _buildCard(
            width: width,
            children: [
              _buildField(
                ctrl: _contactCtrl,
                label: 'Mobile Number',
                hint: 'e.g. 09XXXXXXXXX',
                icon: 'assets/images/phone.webp',
                width: width,
                enabled: !_isLocked,
                showDivider: false,
                keyboardType: TextInputType.phone,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (!RegExp(r'^(09|\+639)\d{9}$').hasMatch(v.trim())) {
                    return 'Enter a valid PH mobile number';
                  }
                  return null;
                },
              ),
            ],
          ),
          SizedBox(height: width * 0.04),

          _buildSectionLabel('ADDRESS', width),
          SizedBox(height: width * 0.02),
          _buildCard(
            width: width,
            children: [
              _buildField(
                ctrl: _barangayCtrl,
                label: 'Barangay',
                hint: 'Enter your barangay',
                icon: 'assets/images/report/location.webp',
                width: width,
                enabled: !_isLocked,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              _divider(width),
              _buildField(
                ctrl: _streetCtrl,
                label: 'Street / Zone',
                hint: 'Enter street or zone',
                icon: 'assets/images/report/location.webp',
                width: width,
                enabled: !_isLocked,
                showDivider: false,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
            ],
          ),
          SizedBox(height: width * 0.04),

          if (_errorMessage != null)
            Container(
              margin: EdgeInsets.only(bottom: width * 0.03),
              padding: EdgeInsets.all(width * 0.035),
              decoration: BoxDecoration(
                color: AppColors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(width * 0.025),
                border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    color: AppColors.red,
                    size: width * 0.045,
                  ),
                  SizedBox(width: width * 0.025),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(
                        fontSize: width * 0.032,
                        color: AppColors.red,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_saving || _isLocked) ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                disabledBackgroundColor: AppColors.primaryBlue.withValues(
                  alpha: 0.4,
                ),
                elevation: 0,
                padding: EdgeInsets.symmetric(vertical: width * 0.045),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(width * 0.03),
                ),
              ),
              child: Text(
                _isLocked ? 'Profile Locked' : 'Save Changes',
                style: TextStyle(
                  fontSize: width * 0.042,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
          SizedBox(height: width * 0.03),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.stroke),
                padding: EdgeInsets.symmetric(vertical: width * 0.04),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(width * 0.03),
                ),
              ),
              child: Text(
                'Cancel',
                style: TextStyle(
                  fontSize: width * 0.038,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF374151),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Avatar card ───────────────────────────────────────────────────────────
  Widget _buildAvatarCard(double width) {
    final fullName =
        '${_firstNameCtrl.text.trim()} ${_lastNameCtrl.text.trim()}'.trim();
    final displayName = fullName.isNotEmpty ? fullName : widget.username;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        width * 0.04,
        width * 0.06,
        width * 0.04,
        width * 0.05,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(width * 0.04),
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
          GestureDetector(
            onTap: _isLocked ? null : _pickPhoto,
            child: Stack(
              children: [
                Container(
                  width: width * 0.28,
                  height: width * 0.28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.stroke, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipOval(child: _buildAvatarImage(width)),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: width * 0.082,
                    height: width * 0.082,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDBEAFE),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.10),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: _isLocked
                        ? Icon(
                            Icons.lock_rounded,
                            color: const Color(0xFF93C5FD),
                            size: width * 0.036,
                          )
                        : Padding(
                            padding: EdgeInsets.all(width * 0.016),
                            child: ColorFiltered(
                              colorFilter: const ColorFilter.mode(
                                Color(0xFF3B82F6),
                                BlendMode.srcIn,
                              ),
                              child: Image.asset(
                                'assets/images/report/cameraicon.webp',
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: width * 0.032),

          Text(
            displayName,
            style: TextStyle(
              fontSize: width * 0.052,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1F2937),
            ),
          ),

          SizedBox(height: width * 0.014),

          if (_isVerified)
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: width * 0.04,
                vertical: width * 0.012,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(width * 0.06),
                border: Border.all(
                  color: AppColors.green.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.verified_rounded,
                    color: AppColors.green,
                    size: width * 0.038,
                  ),
                  SizedBox(width: width * 0.014),
                  Text(
                    'Verified Citizen',
                    style: TextStyle(
                      fontSize: width * 0.030,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF15803D),
                    ),
                  ),
                ],
              ),
            ),

          SizedBox(height: width * 0.028),

          if (_isVerified)
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: width * 0.02,
                vertical: width * 0.028,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(width * 0.03),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: IntrinsicHeight(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatItem(
                      width: width,
                      iconPath: 'assets/images/report/report.webp',
                      iconColor: const Color(0xFF3B82F6),
                      value: '$_reportCount',
                      label: 'Reports',
                    ),
                    VerticalDivider(
                      color: const Color(0xFFE5E7EB),
                      thickness: 1,
                      width: width * 0.01,
                    ),
                    _buildStatItem(
                      width: width,
                      iconPath: 'assets/images/calendar.webp',
                      iconColor: const Color(0xFF22C55E),
                      value: _memberSince ?? '—',
                      label: 'Member Since',
                    ),
                    VerticalDivider(
                      color: const Color(0xFFE5E7EB),
                      thickness: 1,
                      width: width * 0.01,
                    ),
                    _buildStatItem(
                      width: width,
                      iconPath: 'assets/images/report/location.webp',
                      iconColor: const Color(0xFFF59E0B),
                      value: _barangay ?? '—',
                      label: 'Barangay',
                      isEllipsis: true,
                    ),
                  ],
                ),
              ),
            ),

          SizedBox(height: width * 0.022),

          Text(
            _isLocked
                ? 'Photo locked for $_daysRemaining more days'
                : _pickedFile != null
                ? 'New photo selected — tap Save to apply'
                : 'Tap photo to change',
            style: TextStyle(
              fontSize: width * 0.028,
              color: _isLocked ? AppColors.orange : AppColors.hint,
            ),
          ),

          if (_pickedFile != null && !_isLocked) ...[
            SizedBox(height: width * 0.012),
            GestureDetector(
              onTap: () => setState(() {
                _pickedFile = null;
                _pickedBytes = null;
              }),
              child: Text(
                'Remove new photo',
                style: TextStyle(
                  fontSize: width * 0.028,
                  color: AppColors.red,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                  decorationColor: AppColors.red,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Stat item ─────────────────────────────────────────────────────────────
  Widget _buildStatItem({
    required double width,
    required String iconPath,
    required Color iconColor,
    required String value,
    required String label,
    bool isEllipsis = false,
  }) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            iconPath,
            width: width * 0.052,
            height: width * 0.052,
            color: iconColor,
            errorBuilder: (_, _, _) =>
                Icon(Icons.info_outline, size: width * 0.052, color: iconColor),
          ),
          SizedBox(height: width * 0.010),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: width * 0.024,
              color: const Color(0xFF6B7280),
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: width * 0.004),
          Text(
            value,
            maxLines: 1,
            overflow: isEllipsis ? TextOverflow.ellipsis : TextOverflow.clip,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: width * 0.034,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1F2937),
            ),
          ),
        ],
      ),
    );
  }

  // ── Avatar image ──────────────────────────────────────────────────────────
  Widget _buildAvatarImage(double width) {
    final size = width * 0.28;
    if (_pickedBytes != null) {
      return Image.memory(
        _pickedBytes!,
        width: size,
        height: size,
        fit: BoxFit.cover,
      );
    }
    if (_currentPhotoUrl != null && _currentPhotoUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: _currentPhotoUrl!,
        cacheKey: _currentPhotoPath ?? _currentPhotoUrl!,
        memCacheWidth: 280,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          color: const Color(0xFFE5E7EB),
          child: const Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primaryBlue,
              ),
            ),
          ),
        ),
        errorWidget: (context, url, error) =>
            Image.asset('assets/images/profilenew.webp', fit: BoxFit.cover),
      );
    }
    return Image.asset('assets/images/profilenew.webp', fit: BoxFit.cover);
  }

  // ── Lock banner ───────────────────────────────────────────────────────────
  Widget _buildLockBanner(double width) {
    final unlockDate = _lastProfileUpdatedAt?.add(const Duration(days: 30));
    final dateStr = unlockDate != null
        ? '${unlockDate.month}/${unlockDate.day}/${unlockDate.year}'
        : '';

    const amber = Color(0xFFF59E0B);
    const amberDark = Color(0xFFB45309);
    const amberText = Color(0xFF92400E);
    // Fills up as the unlock date approaches (elapsed days / 30).
    final progress = ((30 - _daysRemaining) / 30.0).clamp(0.0, 1.0);

    return Container(
      padding: EdgeInsets.all(width * 0.045),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFBEB), Color(0xFFFFF1D6)],
        ),
        borderRadius: BorderRadius.circular(width * 0.05),
        border: Border.all(color: amber.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: amber.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 8),
            spreadRadius: -6,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Vivid icon chip ──────────────────────────────────────
              Container(
                width: width * 0.12,
                height: width * 0.12,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFBBF24), Color(0xFFF59E0B)],
                  ),
                  borderRadius: BorderRadius.circular(width * 0.036),
                  boxShadow: [
                    BoxShadow(
                      color: amber.withValues(alpha: 0.40),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                      spreadRadius: -3,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.lock_clock_rounded,
                  color: Colors.white,
                  size: width * 0.062,
                ),
              ),
              SizedBox(width: width * 0.035),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Profile Editing Locked',
                      style: TextStyle(
                        fontSize: width * 0.040,
                        fontWeight: FontWeight.w800,
                        color: amberDark,
                        letterSpacing: -0.2,
                      ),
                    ),
                    SizedBox(height: width * 0.012),
                    Text(
                      'Your profile was recently updated. You can edit again '
                      'in $_daysRemaining day${_daysRemaining == 1 ? '' : 's'}.',
                      style: TextStyle(
                        fontSize: width * 0.032,
                        color: amberText,
                        height: 1.5,
                      ),
                    ),
                    if (dateStr.isNotEmpty) ...[
                      SizedBox(height: width * 0.012),
                      Row(
                        children: [
                          Icon(
                            Icons.event_available_rounded,
                            size: width * 0.038,
                            color: amberDark,
                          ),
                          SizedBox(width: width * 0.015),
                          Text(
                            'Available from $dateStr',
                            style: TextStyle(
                              fontSize: width * 0.030,
                              color: amberDark,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: width * 0.04),
          // ── Progress + days-left pill ──────────────────────────────────
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(width * 0.02),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: width * 0.022,
                    backgroundColor: amber.withValues(alpha: 0.18),
                    valueColor: const AlwaysStoppedAnimation<Color>(amber),
                  ),
                ),
              ),
              SizedBox(width: width * 0.03),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: width * 0.028,
                  vertical: width * 0.012,
                ),
                decoration: BoxDecoration(
                  color: amber.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(width * 0.05),
                ),
                child: Text(
                  '$_daysRemaining day${_daysRemaining == 1 ? '' : 's'} left',
                  style: TextStyle(
                    fontSize: width * 0.028,
                    fontWeight: FontWeight.w800,
                    color: amberDark,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Locked display field ──────────────────────────────────────────────────
  /// Single source of truth for the trailing padlock so it renders at an
  /// identical size everywhere (the SizedBox + BoxFit pins it regardless of
  /// whether it sits in a Row or inside an InputDecoration suffix).
  Widget _lockBadge(double width) => SizedBox(
    width: width * 0.04,
    height: width * 0.04,
    child: Image.asset(
      'assets/images/settings/password.webp',
      fit: BoxFit.contain,
      color: const Color(0xFFD1D5DB),
      colorBlendMode: BlendMode.srcIn,
    ),
  );

  Widget _buildLockedDisplayField({
    required String label,
    required String value,
    required String icon,
    required double width,
    bool showDivider = true,
  }) {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: width * 0.04,
            vertical: width * 0.034,
          ),
          child: Row(
            children: [
              Container(
                width: width * 0.095,
                height: width * 0.095,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(width * 0.022),
                  border: Border.all(color: AppColors.stroke, width: 1.2),
                ),
                padding: EdgeInsets.all(width * 0.018),
                child: icon == '@'
                    ? FittedBox(
                        fit: BoxFit.contain,
                        child: Text(
                          '@',
                          style: TextStyle(
                            fontSize: width * 0.048,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF9CA3AF),
                          ),
                        ),
                      )
                    : ColorFiltered(
                        colorFilter: const ColorFilter.mode(
                          Color(0xFF9CA3AF),
                          BlendMode.srcIn,
                        ),
                        child: Image.asset(icon, fit: BoxFit.contain),
                      ),
              ),
              SizedBox(width: width * 0.035),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: width * 0.028,
                        color: AppColors.hint,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: width * 0.005),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: width * 0.036,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF9CA3AF),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: width * 0.02),
              _lockBadge(width),
            ],
          ),
        ),
        if (showDivider) _divider(width),
      ],
    );
  }

  // ── Section label ─────────────────────────────────────────────────────────
  Widget _buildSectionLabel(String label, double width) {
    return Padding(
      padding: EdgeInsets.only(left: width * 0.01),
      child: Text(
        label,
        style: TextStyle(
          fontSize: width * 0.034,
          fontWeight: FontWeight.w700,
          color: AppColors.primaryBlue,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  // ── Card wrapper ──────────────────────────────────────────────────────────
  Widget _buildCard({required double width, required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(width * 0.035),
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

  // ── Editable text field ───────────────────────────────────────────────────
  Widget _buildField({
    required TextEditingController ctrl,
    required String label,
    required String hint,
    required String icon,
    required double width,
    int maxLines = 1,
    bool showDivider = true,
    bool enabled = true,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: width * 0.04,
            vertical: width * 0.015,
          ),
          child: Row(
            crossAxisAlignment: maxLines > 1
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              Padding(
                padding: EdgeInsets.only(top: maxLines > 1 ? width * 0.025 : 0),
                child: Container(
                  width: width * 0.095,
                  height: width * 0.095,
                  decoration: BoxDecoration(
                    color: enabled
                        ? AppColors.primaryBlue.withValues(alpha: 0.10)
                        : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(width * 0.022),
                    border: Border.all(
                      color: enabled
                          ? AppColors.primaryBlue.withValues(alpha: 0.25)
                          : AppColors.stroke,
                      width: 1.2,
                    ),
                  ),
                  padding: EdgeInsets.all(width * 0.018),
                  child: ColorFiltered(
                    colorFilter: ColorFilter.mode(
                      enabled ? AppColors.primaryBlue : const Color(0xFF9CA3AF),
                      BlendMode.srcIn,
                    ),
                    child: Image.asset(icon, fit: BoxFit.contain),
                  ),
                ),
              ),
              SizedBox(width: width * 0.035),
              Expanded(
                child: TextFormField(
                  controller: ctrl,
                  maxLines: maxLines,
                  enabled: enabled,
                  validator: validator,
                  keyboardType: keyboardType,
                  style: TextStyle(
                    fontSize: width * 0.038,
                    fontWeight: FontWeight.w500,
                    color: enabled
                        ? const Color(0xFF1F2937)
                        : const Color(0xFF9CA3AF),
                  ),
                  decoration: InputDecoration(
                    labelText: label,
                    hintText: hint,
                    suffixIcon: !enabled
                        ? Padding(
                            padding: EdgeInsets.only(left: width * 0.02),
                            child: _lockBadge(width),
                          )
                        : null,
                    suffixIconConstraints: BoxConstraints(
                      minWidth: width * 0.04,
                      minHeight: width * 0.04,
                    ),
                    labelStyle: TextStyle(
                      fontSize: width * 0.032,
                      color: AppColors.hint,
                      fontWeight: FontWeight.w500,
                    ),
                    hintStyle: TextStyle(
                      fontSize: width * 0.034,
                      color: AppColors.hint.withValues(alpha: 0.6),
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      vertical: width * 0.02,
                    ),
                    errorStyle: TextStyle(
                      fontSize: width * 0.028,
                      color: AppColors.red,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showDivider) _divider(width),
      ],
    );
  }

  Widget _divider(double width) => Padding(
    padding: EdgeInsets.only(left: width * 0.165),
    child: const Divider(height: 1, color: AppColors.stroke),
  );
}
