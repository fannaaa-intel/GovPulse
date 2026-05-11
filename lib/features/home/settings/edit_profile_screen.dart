import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_colors.dart';

class EditProfileScreen extends StatefulWidget {
  final String username;

  const EditProfileScreen({super.key, required this.username});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen>
    with TickerProviderStateMixin {
  // ── Animation ─────────────────────────────────────────────────────────────
  late final AnimationController _entryCtrl;

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
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 60), () {
        if (mounted) _entryCtrl.forward();
      });
    });
    _loadData();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _firstNameCtrl.dispose();
    _middleNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _barangayCtrl.dispose();
    _streetCtrl.dispose();
    _contactCtrl.dispose();
    super.dispose();
  }

  // ── Staggered entry animation ─────────────────────────────────────────────
  Widget _animated(int i, Widget child) {
    final start = (i * 0.09).clamp(0.0, 0.85);
    final end = (start + 0.45).clamp(0.0, 1.0);
    final fade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entryCtrl,
        curve: Interval(start, end, curve: Curves.easeOut),
      ),
    );
    final slide =
        Tween<Offset>(begin: const Offset(0.0, 0.25), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _entryCtrl,
            curve: Interval(start, end, curve: Curves.easeOutCubic),
          ),
        );
    return FadeTransition(
      opacity: fade,
      child: SlideTransition(position: slide, child: child),
    );
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
              'address, street, contact_number, created_at, '
              'profile_photo_path, last_profile_updated_at',
            )
            .eq('user_id', user.id)
            .maybeSingle();

        if (cd != null) {
          _firstNameCtrl.text = cd['first_name'] as String? ?? '';
          _middleNameCtrl.text = cd['middle_name'] as String? ?? '';
          _lastNameCtrl.text = cd['last_name'] as String? ?? '';
          _barangayCtrl.text = cd['address'] as String? ?? '';
          _streetCtrl.text = cd['street'] as String? ?? '';
          _contactCtrl.text = cd['contact_number'] as String? ?? '';

          // ── Member since ──
          final createdRaw = cd['created_at'];
          if (createdRaw != null) {
            final dt = DateTime.tryParse(createdRaw.toString());
            if (dt != null) _memberSince = dt.year.toString();
          }

          // ── Barangay for stats ──
          final addressVal = cd['address'] as String? ?? '';
          if (addressVal.isNotEmpty) {
            _barangay = addressVal.split(',').first.trim();
          }

          // ── Lock ──
          final updatedRaw = cd['last_profile_updated_at'];
          if (updatedRaw != null) {
            _lastProfileUpdatedAt = DateTime.tryParse(updatedRaw.toString());
          }

          // ── Photo ──
          final photoPath =
              (cd['profile_photo_path'] as String?)?.isNotEmpty == true
              ? cd['profile_photo_path'] as String
              : verifRow?['face_photo_path'] as String?;

          if (photoPath != null && photoPath.isNotEmpty) {
            try {
              _currentPhotoUrl = await supabase.storage
                  .from('verification-assets')
                  .createSignedUrl(photoPath, 3600);
            } catch (_) {
              try {
                _currentPhotoUrl = supabase.storage
                    .from('verification-assets')
                    .getPublicUrl(photoPath);
              } catch (_) {}
            }
          }
        }

        // ── Report count ──
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
          _isVerified = verified;
          _loading = false;
        });
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
            .from('verification-assets')
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
        'address': _barangayCtrl.text.trim(),
        'street': _streetCtrl.text.trim(),
        'contact_number': _contactCtrl.text.trim(),
        'last_profile_updated_at': now,
      };
      if (newPhotoPath != null) {
        updateData['profile_photo_path'] = newPhotoPath;
      }

      await supabase
          .from('citizen_details')
          .update(updateData)
          .eq('user_id', user.id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Profile updated successfully'),
          backgroundColor: AppColors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
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

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: SafeArea(
        child: Column(
          children: [
            _animated(0, _buildHeader(width)),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primaryBlue,
                      ),
                    )
                  : SingleChildScrollView(
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
          ],
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
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            color: AppColors.primaryBlue,
            iconSize: width * 0.055,
          ),
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
        _animated(
          1,
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
          _animated(1, _buildAvatarCard(width)),
          SizedBox(height: width * 0.04),

          if (_isLocked) ...[
            _animated(2, _buildLockBanner(width)),
            SizedBox(height: width * 0.04),
          ],

          _animated(3, _buildSectionLabel('ACCOUNT', width)),
          SizedBox(height: width * 0.02),
          _animated(
            4,
            _buildCard(
              width: width,
              children: [
                _buildLockedDisplayField(
                  label: 'Email',
                  value:
                      Supabase.instance.client.auth.currentUser?.email ?? '—',
                  icon: 'assets/images/email.png',
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
          ),
          SizedBox(height: width * 0.04),

          _animated(5, _buildSectionLabel('PERSONAL INFORMATION', width)),
          SizedBox(height: width * 0.02),
          _animated(
            6,
            _buildCard(
              width: width,
              children: [
                _buildField(
                  ctrl: _firstNameCtrl,
                  label: 'First Name',
                  hint: 'Enter first name',
                  icon: 'assets/images/username.png',
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
                  icon: 'assets/images/username.png',
                  width: width,
                  enabled: !_isLocked,
                ),
                _divider(width),
                _buildField(
                  ctrl: _lastNameCtrl,
                  label: 'Last Name',
                  hint: 'Enter last name',
                  icon: 'assets/images/username.png',
                  width: width,
                  enabled: !_isLocked,
                  showDivider: false,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
              ],
            ),
          ),
          SizedBox(height: width * 0.04),

          _animated(7, _buildSectionLabel('CONTACT', width)),
          SizedBox(height: width * 0.02),
          _animated(
            8,
            _buildCard(
              width: width,
              children: [
                _buildField(
                  ctrl: _contactCtrl,
                  label: 'Mobile Number',
                  hint: 'e.g. 09XXXXXXXXX',
                  icon: 'assets/images/phone.png',
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
          ),
          SizedBox(height: width * 0.04),

          _animated(9, _buildSectionLabel('ADDRESS', width)),
          SizedBox(height: width * 0.02),
          _animated(
            10,
            _buildCard(
              width: width,
              children: [
                _buildField(
                  ctrl: _barangayCtrl,
                  label: 'Barangay',
                  hint: 'Enter your barangay',
                  icon: 'assets/images/report/location.png',
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
                  icon: 'assets/images/report/location.png',
                  width: width,
                  enabled: !_isLocked,
                  showDivider: false,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
              ],
            ),
          ),
          SizedBox(height: width * 0.04),

          if (_errorMessage != null)
            _animated(
              11,
              Container(
                margin: EdgeInsets.only(bottom: width * 0.03),
                padding: EdgeInsets.all(width * 0.035),
                decoration: BoxDecoration(
                  color: AppColors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(width * 0.025),
                  border: Border.all(
                    color: AppColors.red.withValues(alpha: 0.3),
                  ),
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
            ),

          _animated(
            12,
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
                child: _saving
                    ? SizedBox(
                        width: width * 0.05,
                        height: width * 0.05,
                        child: const CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : Text(
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
          ),
          SizedBox(height: width * 0.03),

          _animated(
            13,
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
          // ── Avatar with camera badge ──
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
                                'assets/images/report/cameraicon.png',
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

          // ── Display name ──
          Text(
            displayName,
            style: TextStyle(
              fontSize: width * 0.052,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1F2937),
            ),
          ),

          SizedBox(height: width * 0.014),

          // ── Verified badge ──
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

          // ── Stats row ──
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
                      iconPath: 'assets/images/report/report.png',
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
                      iconPath: 'assets/images/calendar.png',
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
                      iconPath: 'assets/images/report/location.png',
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

          // ── Photo hint ──
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

  // ── Stat item — icon → label → value ─────────────────────────────────────
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
          // ── label first ──
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
          // ── value second ──
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
      return Image.network(
        _currentPhotoUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) =>
            Image.asset('assets/images/profilenew.png', fit: BoxFit.cover),
      );
    }
    return Image.asset('assets/images/profilenew.png', fit: BoxFit.cover);
  }

  // ── Lock banner ───────────────────────────────────────────────────────────
  Widget _buildLockBanner(double width) {
    final unlockDate = _lastProfileUpdatedAt?.add(const Duration(days: 30));
    final dateStr = unlockDate != null
        ? '${unlockDate.month}/${unlockDate.day}/${unlockDate.year}'
        : '';

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: width * 0.04,
        vertical: width * 0.04,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(width * 0.03),
        border: Border.all(color: AppColors.orange.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(width * 0.02),
            decoration: BoxDecoration(
              color: AppColors.orange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(width * 0.02),
            ),
            child: Image.asset(
              'assets/images/settings/time.png',
              width: width * 0.06,
              height: width * 0.06,
              color: AppColors.orange,
              colorBlendMode: BlendMode.srcIn,
            ),
          ),
          SizedBox(width: width * 0.03),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Profile Editing Locked',
                  style: TextStyle(
                    fontSize: width * 0.036,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFB45309),
                  ),
                ),
                SizedBox(height: width * 0.01),
                Text(
                  'Your profile was recently updated. You can edit again in '
                  '$_daysRemaining day${_daysRemaining == 1 ? '' : 's'}.',
                  style: TextStyle(
                    fontSize: width * 0.030,
                    color: const Color(0xFF92400E),
                    height: 1.45,
                  ),
                ),
                if (dateStr.isNotEmpty) ...[
                  SizedBox(height: width * 0.008),
                  Text(
                    'Available from: $dateStr',
                    style: TextStyle(
                      fontSize: width * 0.028,
                      color: const Color(0xFFB45309),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                SizedBox(height: width * 0.02),
                ClipRRect(
                  borderRadius: BorderRadius.circular(width * 0.01),
                  child: LinearProgressIndicator(
                    value: (_daysRemaining / 30.0).clamp(0.0, 1.0),
                    minHeight: width * 0.015,
                    backgroundColor: AppColors.orange.withValues(alpha: 0.2),
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.orange),
                  ),
                ),
                SizedBox(height: width * 0.008),
                Text(
                  '$_daysRemaining / 30 days remaining',
                  style: TextStyle(
                    fontSize: width * 0.026,
                    color: const Color(0xFFB45309),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Locked display field ──────────────────────────────────────────────────
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
              Image.asset(
                'assets/images/settings/password.png',
                width: width * 0.038,
                height: width * 0.038,
                color: const Color(0xFFD1D5DB),
                colorBlendMode: BlendMode.srcIn,
              ),
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
                            padding: EdgeInsets.all(width * 0.03),
                            child: Image.asset(
                              'assets/images/settings/password.png',
                              width: width * 0.038,
                              height: width * 0.038,
                              color: const Color(0xFFD1D5DB),
                              colorBlendMode: BlendMode.srcIn,
                            ),
                          )
                        : null,
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
