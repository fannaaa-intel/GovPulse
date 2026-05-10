import 'package:flutter/material.dart';

class VerificationIdSelectionScreen extends StatefulWidget {
  final String username;

  const VerificationIdSelectionScreen({super.key, required this.username});

  @override
  State<VerificationIdSelectionScreen> createState() =>
      _VerificationIdSelectionScreenState();
}

class _VerificationIdSelectionScreenState
    extends State<VerificationIdSelectionScreen>
    with SingleTickerProviderStateMixin {
  int selectedIndex = 0;
  bool isChecked = false;

  @override
  void initState() {
    super.initState();
  }

  final List<Map<String, String>> ids = [
    {
      "title": "PhilSys ID",
      "subtitle": "Recommended",
      "image": "assets/images/idcards/phfront.png",
    },
    {
      "title": "Driver's License ID",
      "subtitle": "Recommended",
      "image": "assets/images/idcards/driversfront.png",
    },
    {
      "title": "Postal ID",
      "subtitle": "Recommended",
      "image": "assets/images/idcards/postalfront.png",
    },
    {
      "title": "Philippine Passport ID",
      "subtitle": "",
      "image": "assets/images/idcards/philpassfront.png",
    },
    {
      "title": "PhilHealth ID",
      "subtitle": "",
      "image": "assets/images/idcards/phealthfront.png",
    },
    {
      "title": "PRC ID",
      "subtitle": "",
      "image": "assets/images/idcards/prcharap.png",
    },
    {
      "title": "SSS ID",
      "subtitle": "",
      "image": "assets/images/idcards/sssfront.png",
    },
    {
      "title": "TIN ID",
      "subtitle": "",
      "image": "assets/images/idcards/tinfront.png",
    },
    {
      "title": "UMID ID",
      "subtitle": "",
      "image": "assets/images/idcards/umidharap.png",
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFFF3F4F6),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
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

              const SizedBox(height: 30),

              /// STEP INDICATOR
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _stepWithLabel("1", "Upload ID", true),
                  Expanded(child: _stepLine()),
                  _stepWithLabel("2", "Additional\nInformation", false),
                  Expanded(child: _stepLine()),
                  _stepWithLabel("3", "Identity\nVerification", false),
                ],
              ),

              const SizedBox(height: 24),

              /// SELECT ID TITLE
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Select ID",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color.fromARGB(255, 0, 106, 255),
                  ),
                ),
              ),

              const SizedBox(height: 6),

              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "ID type",
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),

              const SizedBox(height: 10),

              /// SCROLLABLE ID LIST
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: List.generate(ids.length, (index) {
                      final item = ids[index];
                      final isSelected = selectedIndex == index;

                      return GestureDetector(
                        onTap: () {
                          setState(() => selectedIndex = index);
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF2563EB)
                                  : Colors.grey.shade300,
                            ),
                          ),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.asset(
                                  item["image"]!,
                                  height: 40,
                                  width: 60,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item["title"]!,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (item["subtitle"]!.isNotEmpty)
                                      const Text(
                                        "Recommended",
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.red,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Icon(
                                isSelected
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                color: isSelected
                                    ? const Color(0xFF2563EB)
                                    : Colors.grey,
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),

              /// INFO BOX
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(top: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 14, color: Colors.grey),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        "Only valid IDs are accepted. Verification is limited to Aparri residents.",
                        style: TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ),
                  ],
                ),
              ),

              /// CHECKBOX — blue active color
              Row(
                children: [
                  Checkbox(
                    value: isChecked,
                    activeColor: const Color(0xFF2563EB), // ← blue when checked
                    onChanged: (val) {
                      setState(() => isChecked = val!);
                    },
                  ),
                  const Expanded(
                    child: Text(
                      "I consent to GovPulse processing my personal data.",
                      style: TextStyle(fontSize: 10),
                    ),
                  ),
                ],
              ),

              /// BUTTON
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isChecked
                      ? () {
                          Navigator.pushNamed(
                            context,
                            '/verification_photo_instruction',
                            arguments: {
                              "username": widget.username,
                              "selectedId": ids[selectedIndex]["title"]!,
                            },
                          );
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isChecked
                        ? const Color(0xFF16A34A)
                        : Colors.grey,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text("Continue"),
                ),
              ),

              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  // Fixed-width so Expanded line fills exactly the gap between circles
  Widget _stepWithLabel(String number, String label, bool active) {
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
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 8, // ← smaller font so labels don't overflow
              color: active ? const Color(0xFF2563EB) : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  // top: 11 = circle radius (12) - half line height (1) → centers line on circle
  Widget _stepLine() {
    return Container(
      margin: const EdgeInsets.only(top: 11),
      height: 2,
      color: Colors.grey.shade300,
    );
  }
}
