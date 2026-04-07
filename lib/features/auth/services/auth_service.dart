import 'dart:convert';
import 'package:http/http.dart' as http;

class AuthService {
  static const String baseUrl =
      "https://vxvflhjbafqwehuxnmeq.supabase.co/functions/v1";

  static const Map<String, String> headers = {
    "Content-Type": "application/json",
    "apikey": "sb_publishable_ZBDaQPQdFyC5kOHGbce9Ig_zdtIi6Mo",
  };

  /// ✅ CHECK EMAIL
  static Future<bool> checkEmailExists(String email) async {
    if (email.isEmpty || !email.contains("@")) return false;

    final response = await http.post(
      Uri.parse("$baseUrl/check-email-exists"),
      headers: headers,
      body: jsonEncode({"email": email}),
    );

    final data = jsonDecode(response.body);

    print("📧 EMAIL CHECK: ${response.body}");

    return data["exists"] == true;
  }

  /// ✅ CHECK USERNAME
  static Future<bool> checkUsernameExists(String username) async {
    if (username.isEmpty) return false;

    final response = await http.post(
      Uri.parse("$baseUrl/check-username-exists"),
      headers: headers,
      body: jsonEncode({"username": username}),
    );

    final data = jsonDecode(response.body);

    print("👤 USERNAME CHECK: ${response.body}");

    return data["exists"] == true;
  }
}
