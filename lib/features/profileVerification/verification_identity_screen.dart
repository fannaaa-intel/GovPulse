import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';

class VerificationIdentityScreen extends StatefulWidget {
  final String username;
  final String selectedId;

  // ── Form data passed through from VerificationReviewScreen ───────────────
  final String idNumber;
  final String firstName;
  final String middleName;
  final String lastName;
  final String? suffix;
  final String gender;
  final String birthdate;
  final String birthplace;
  final String civilStatus;
  final String contactNumber;
  final String barangay;
  final String street;

  // ── ID images ─────────────────────────────────────────────────────────────
  final Uint8List? frontImage;
  final Uint8List? backImage;

  const VerificationIdentityScreen({
    super.key,
    required this.username,
    required this.selectedId,
    required this.idNumber,
    required this.firstName,
    required this.middleName,
    required this.lastName,
    this.suffix,
    required this.gender,
    required this.birthdate,
    required this.birthplace,
    required this.civilStatus,
    required this.contactNumber,
    required this.barangay,
    required this.street,
    this.frontImage,
    this.backImage,
  });

  @override
  State<VerificationIdentityScreen> createState() =>
      _VerificationIdentityScreenState();
}

class _VerificationIdentityScreenState
    extends State<VerificationIdentityScreen> {
  bool _confirmPressed = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
    );
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: true,
        bottom: false,
        child: Column(
          children: [
            _buildHeader(context),
            _buildStepper(),
            Expanded(child: _buildContent()),
            _buildBottomButton(bottomPadding),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 8),
    child: Column(
      children: [
        Image.asset(
          "assets/images/applogocrop.png",
          height: MediaQuery.of(context).size.height * 0.10,
        ),
        const SizedBox(height: 6),
        const Text(
          "Aparri Citizenship Verification",
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryBlue,
          ),
        ),
      ],
    ),
  );

  // ── Stepper ───────────────────────────────────────────────────────────────
  Widget _buildStepper() => Padding(
    padding: const EdgeInsets.only(bottom: 16, left: 8, right: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _step("1", "Upload ID", active: true),
        Expanded(child: _divider(active: true)),
        _step("2", "Additional\nInformation", active: true),
        Expanded(child: _divider(active: true)),
        _step("3", "Identity\nVerification", active: true),
      ],
    ),
  );

  Widget _step(String n, String label, {required bool active}) => SizedBox(
    width: 54,
    child: Column(
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: active
              ? AppColors.primaryBlue
              : Colors.grey.shade300,
          child: Text(
            n,
            style: TextStyle(
              fontSize: 10,
              color: active ? Colors.white : Colors.black54,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 8,
            color: active ? AppColors.primaryBlue : Colors.grey,
          ),
        ),
      ],
    ),
  );

  Widget _divider({required bool active}) => Container(
    margin: const EdgeInsets.only(top: 11),
    height: 2,
    color: active ? AppColors.primaryBlue : AppColors.stroke,
  );

  // ── Content ───────────────────────────────────────────────────────────────
  Widget _buildContent() => SingleChildScrollView(
    padding: const EdgeInsets.symmetric(horizontal: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 10),
        const Text(
          "Identity Verification",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          "Hold your phone at a proper distance and\nensure your face is centered in the frame.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.black54, height: 1.5),
        ),
        const SizedBox(height: 24),
        Center(
          child: Image.asset(
            "assets/images/face_ver.png",
            height: 180,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(height: 28),
        const Divider(thickness: 1, color: Color(0xFFE5E7EB)),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: const [
            _RestrictItem(
              image: "assets/images/sunglasses.png",
              label: "No Shade",
            ),
            _RestrictItem(image: "assets/images/cap.png", label: "No Cap"),
            _RestrictItem(
              image: "assets/images/face_mask.png",
              label: "No Mask",
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Divider(thickness: 1, color: Color(0xFFE5E7EB)),
        const SizedBox(height: 14),
        const Text(
          "Please make sure your entire face is clear and well lit.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.black54, height: 1.5),
        ),
        const SizedBox(height: 24),
      ],
    ),
  );

  // ── Bottom button ─────────────────────────────────────────────────────────
  Widget _buildBottomButton(double bottomPadding) => Container(
    padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding + 12),
    color: Colors.white,
    child: GestureDetector(
      onTapDown: (_) => setState(() => _confirmPressed = true),
      onTapUp: (_) {
        setState(() => _confirmPressed = false);

        // ── Forward every field to the face scan screen ───────────────
        Navigator.pushNamed(
          context,
          '/verification_face_scan',
          arguments: {
            'username': widget.username,
            'selectedId': widget.selectedId,
            'idNumber': widget.idNumber,
            'firstName': widget.firstName,
            'middleName': widget.middleName,
            'lastName': widget.lastName,
            'suffix': widget.suffix,
            'gender': widget.gender,
            'birthdate': widget.birthdate,
            'birthplace': widget.birthplace,
            'civilStatus': widget.civilStatus,
            'contactNumber': widget.contactNumber,
            'barangay': widget.barangay,
            'street': widget.street,
            'frontImage': widget.frontImage,
            'backImage': widget.backImage,
          },
        );
      },
      onTapCancel: () => setState(() => _confirmPressed = false),
      child: AnimatedScale(
        scale: _confirmPressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeInOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 48,
          decoration: BoxDecoration(
            color: _confirmPressed
                ? AppColors.green.withValues(alpha: .80)
                : AppColors.green,
            borderRadius: BorderRadius.circular(24),
            boxShadow: _confirmPressed
                ? []
                : [
                    BoxShadow(
                      color: AppColors.green.withValues(alpha: 0.38),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
          ),
          alignment: Alignment.center,
          child: const Text(
            "Confirm",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: Colors.white,
            ),
          ),
        ),
      ),
    ),
  );
}

// ── Restriction item widget ───────────────────────────────────────────────────
class _RestrictItem extends StatelessWidget {
  final String image;
  final String label;

  const _RestrictItem({required this.image, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.stroke),
              ),
              padding: const EdgeInsets.all(10),
              child: Image.asset(image, fit: BoxFit.contain),
            ),
            Positioned(
              bottom: -8,
              right: -8,
              child: Image.asset(
                "assets/images/notwear.png",
                width: 26,
                height: 26,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: Colors.black54,
          ),
        ),
      ],
    );
  }
}
