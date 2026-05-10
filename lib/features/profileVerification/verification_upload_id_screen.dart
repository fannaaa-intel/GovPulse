import 'package:flutter/material.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:permission_handler/permission_handler.dart';

const Map<String, Map<String, String>> idImages = {
  "PhilSys ID": {
    "front": "assets/images/idcards/phfront.png",
    "back": "assets/images/idcards/phfront.png",
  },
  "Driver's License ID": {
    "front": "assets/images/idcards/driversfront.png",
    "back": "assets/images/idcards/driversfront.png",
  },
  "Postal ID": {
    "front": "assets/images/idcards/postalfront.png",
    "back": "assets/images/idcards/postalfront.png",
  },
  "Philippine Passport ID": {
    "front": "assets/images/idcards/philpassfront.png",
    "back": "assets/images/idcards/philpassfront.png",
  },
  "PhilHealth ID": {
    "front": "assets/images/idcards/phealthfront.png",
    "back": "assets/images/idcards/phealthfront.png",
  },
  "PRC ID": {
    "front": "assets/images/idcards/prcharap.png",
    "back": "assets/images/idcards/prcharap.png",
  },
  "SSS ID": {
    "front": "assets/images/idcards/sssfront.png",
    "back": "assets/images/idcards/sssfront.png",
  },
  "TIN ID": {
    "front": "assets/images/idcards/tinfront.png",
    "back": "assets/images/idcards/tinfront.png",
  },
  "UMID ID": {
    "front": "assets/images/idcards/umidharap.png",
    "back": "assets/images/idcards/umidharap.png",
  },
};

class VerificationUploadIdScreen extends StatelessWidget {
  final String username;
  final String selectedId;

  const VerificationUploadIdScreen({
    super.key,
    required this.username,
    required this.selectedId,
  });

  @override
  Widget build(BuildContext context) {
    final images =
        idImages[selectedId] ??
        {
          "front": "assets/images/idcards/phfront.png",
          "back": "assets/images/idcards/phfront.png",
        };

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFFF3F4F6),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 10),

            /// LOGO
            Center(
              child: Image.asset(
                "assets/images/applogocrop.png",
                height: MediaQuery.of(context).size.height * 0.12,
              ),
            ),

            const SizedBox(height: 16),

            /// TITLE
            const Text(
              "Aparri Citizenship Verification",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color.fromARGB(255, 0, 106, 255),
              ),
            ),

            const SizedBox(height: 25),

            /// STEP INDICATOR — lines connected, font fixed
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _step("1", "Upload ID", true),
                  Expanded(child: _line()),
                  _step("2", "Additional\nInformation", false),
                  Expanded(child: _line()),
                  _step("3", "Identity\nVerification", false),
                ],
              ),
            ),

            const SizedBox(height: 24),

            /// HEADER
            Text(
              "Upload Your $selectedId",
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),

            const SizedBox(height: 12),
            const Divider(thickness: 1),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    const SizedBox(height: 38),

                    /// UPLOAD + SAMPLES
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: GestureDetector(
                            onTap: () async {
                              final status = await Permission.camera.request();
                              if (!context.mounted) return;

                              if (status.isGranted) {
                                Navigator.pushNamed(
                                  context,
                                  '/verification_scan',
                                  arguments: {
                                    'username': username,
                                    'selectedId': selectedId,
                                  },
                                );
                              } else if (status.isDenied) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      "Camera permission is required",
                                    ),
                                  ),
                                );
                              } else if (status.isPermanentlyDenied) {
                                openAppSettings();
                              }
                            },
                            child: DottedBorder(
                              color: const Color(0xFF2563EB),
                              strokeWidth: 1,
                              dashPattern: const [8, 4],
                              borderType: BorderType.RRect,
                              radius: const Radius.circular(4),
                              child: Container(
                                height: 129,
                                color: Colors.white,
                                child: const Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      CircleAvatar(
                                        radius: 28,
                                        backgroundColor: Color(0xFF0B57A4),
                                        child: Icon(
                                          Icons.camera_alt_outlined,
                                          color: Colors.white,
                                          size: 30,
                                        ),
                                      ),
                                      SizedBox(height: 8),
                                      Text(
                                        "Tap to Upload your ID",
                                        style: TextStyle(fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),

                        Expanded(
                          flex: 2,
                          child: Column(
                            children: [
                              _sampleCard(images["front"]!, "Front sample"),
                              const SizedBox(height: 10),
                              _sampleCard(images["back"]!, "Back sample"),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 22),
                    const Divider(thickness: 1),
                    const SizedBox(height: 16),

                    /// NOTE BOX
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5E7EB),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Note",
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.black87,
                            ),
                          ),
                          SizedBox(height: 10),
                          _UploadNoteRow(
                            icon: Icons.lightbulb_outline,
                            text:
                                "Please ensure you are in a well-lit area for best results.",
                          ),
                          SizedBox(height: 10),
                          _UploadNoteRow(
                            icon: Icons.credit_card,
                            text:
                                "Align your ID properly within the camera frame.",
                          ),
                        ],
                      ),
                    ),

                    const Spacer(),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _sampleCard(String imagePath, String label) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFD1D5DB)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Image.asset(imagePath, height: 42, fit: BoxFit.contain),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Colors.black87),
        ),
      ],
    );
  }

  // Fixed-width so Expanded line fills exactly the gap between circles
  static Widget _step(String number, String label, bool active) {
    return SizedBox(
      width: 54,
      child: Column(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: active
                ? const Color(0xFF2563EB)
                : Colors.grey.shade300,
            child: Text(
              number,
              style: TextStyle(
                fontSize: 10,
                color: active ? Colors.white : Colors.black,
              ),
            ),
          ),
          const SizedBox(height: 4), // ← was 6
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 8, // ← was 10, fits without overflow
              color: active ? const Color(0xFF2563EB) : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  // top: 11 = circle radius (12) - half line height (1) → centers line on circle
  static Widget _line() {
    return Container(
      margin: const EdgeInsets.only(top: 11),
      height: 2,
      color: Colors.grey.shade300,
    );
  }
}

class _UploadNoteRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _UploadNoteRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF2563EB)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 11, color: Colors.black87),
          ),
        ),
      ],
    );
  }
}
