import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/inputs/rounded_input_field.dart';

class ResetPasswordPhoneScreen extends StatefulWidget {
  final VoidCallback onVerify;
  final VoidCallback onLogin;

  const ResetPasswordPhoneScreen({
    super.key,
    required this.onVerify,
    required this.onLogin,
  });

  @override
  State<ResetPasswordPhoneScreen> createState() =>
      _ResetPasswordPhoneScreenState();
}

class _ResetPasswordPhoneScreenState extends State<ResetPasswordPhoneScreen> {
  String phone = "";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,

      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.symmetric(horizontal: 26),
          child: Column(
            children: [
              const SizedBox(height: 30),

              /// LOGO
              Image.asset(
                "assets/images/applogocrop.png",
                width: MediaQuery.of(context).size.width * 0.32,
              ),

              const SizedBox(height: 14),

              /// TITLE
              Text(
                "Reset Password",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryBlue,
                ),
              ),

              const SizedBox(height: 6),

              /// SUBTITLE
              Text(
                "Enter your Phone Number to receive a\nverification code.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),

              const SizedBox(height: 22),

              /// PHONE INPUT
              RoundedInputField(
                value: phone,
                hintText: "Phone number",
                icon: Icons.phone,
                prefix: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    "+63",
                    style: TextStyle(
                      color: AppColors.primaryBlue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                onChanged: (val) {
                  if (val.length <= 10) {
                    setState(() {
                      phone = val;
                    });
                  }
                },
              ),

              const SizedBox(height: 18),

              /// VERIFY BUTTON
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: phone.length == 10 ? widget.onVerify : null,
                  child: const Text(
                    "Verify Code",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              /// INFO TEXT
              Text(
                "We will send you a verification code via SMS",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),

              const SizedBox(height: 26),

              /// OR RETURN
              Row(
                children: [
                  Expanded(child: Divider(color: Colors.grey.shade300)),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      "Or Return to",
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ),
                  Expanded(child: Divider(color: Colors.grey.shade300)),
                ],
              ),

              const SizedBox(height: 16),

              /// LOGIN BUTTON
              SizedBox(
                height: 56,
                width: 170,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.grey.shade300),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: widget.onLogin,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        "assets/images/out.png",
                        width: 20,
                        height: 20,
                        color: AppColors.primaryBlue,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        "Log In",
                        style: TextStyle(
                          color: AppColors.primaryBlue,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
