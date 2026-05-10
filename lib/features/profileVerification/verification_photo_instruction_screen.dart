import 'package:flutter/material.dart';

class VerificationPhotoInstructionScreen extends StatelessWidget {
  final String username;
  final String selectedId;

  const VerificationPhotoInstructionScreen({
    super.key,
    required this.username,
    required this.selectedId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFFF3F4F6),
      body: SafeArea(
        child: SingleChildScrollView(
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
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color.fromARGB(255, 0, 106, 255),
                ),
              ),

              const SizedBox(height: 25),

              /// STEP INDICATOR
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

              /// HEADER TEXT
              Text(
                "Get your $selectedId ready",
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 16),

              const Divider(thickness: 1),

              /// PHOTO INSTRUCTION
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Photo Instruction",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2563EB),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      "Your ID should be original and not modified in any form.",
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),

                    const SizedBox(height: 20),

                    /// BAD EXAMPLES
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: const [
                        _BadExample(
                          image: "assets/images/idicons/expired.png",
                          label: "Expired",
                        ),
                        _BadExample(
                          image: "assets/images/idicons/blurry.png",
                          label: "Blurry",
                        ),
                        _BadExample(
                          image: "assets/images/idicons/withglare.png",
                          label: "With Glare",
                        ),
                        _BadExample(
                          image: "assets/images/idicons/dark.png",
                          label: "Dark",
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    /// GOOD EXAMPLE
                    const Center(
                      child: Column(
                        children: [
                          _GoodExample(
                            image: "assets/images/idicons/correctsample.png",
                          ),
                          SizedBox(height: 6),
                          Text(
                            "Correct example",
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              const Divider(thickness: 1),

              /// NOTE BOX
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Column(
                    children: [
                      _NoteRow(
                        icon: Icons.lightbulb_outline,
                        text:
                            "Please ensure you are in a well-lit area for best results.",
                      ),
                      SizedBox(height: 8),
                      _NoteRow(
                        icon: Icons.crop_free,
                        text: "Align your ID properly within the camera frame.",
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              /// BUTTON
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pushNamed(
                        context,
                        '/verification_upload_id',
                        arguments: {
                          "username": username,
                          "selectedId": selectedId,
                        },
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF16A34A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text("Continue"),
                  ),
                ),
              ),

              const SizedBox(height: 14),
            ],
          ),
        ),
      ),
    );
  }

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
              fontSize: 8, // ← was 10
              color: active ? const Color(0xFF2563EB) : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  static Widget _line() {
    return Container(
      margin: const EdgeInsets.only(top: 11),
      height: 2,
      color: Colors.grey.shade300,
    );
  }
}

class _BadExample extends StatelessWidget {
  final String image;
  final String label;

  const _BadExample({required this.image, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.red),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Image.asset(image, height: 40, width: 60, fit: BoxFit.cover),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 10)),
      ],
    );
  }
}

class _GoodExample extends StatelessWidget {
  final String image;

  const _GoodExample({required this.image});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.green),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Image.asset(image, height: 70),
    );
  }
}

class _NoteRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _NoteRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.blueGrey),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 11))),
      ],
    );
  }
}
