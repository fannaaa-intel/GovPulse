import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  static final _client = Supabase.instance.client;

  static Future<bool> checkEmailExists(String email) async {
    if (email.trim().isEmpty) return false;
    try {
      final result = await _client
          .from('profiles')
          .select('email')
          .ilike('email', email.trim())
          .limit(1);
      return result.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> checkUsernameExists(String username) async {
    if (username.trim().isEmpty) return false;
    try {
      final result = await _client
          .from('profiles')
          .select('username')
          .ilike('username', username.trim())
          .limit(1);
      return result.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<String> login(String username, String password) async {
    final cleanUsername = username.trim();
    final cleanPassword = password.trim();

    if (cleanUsername.isEmpty || cleanPassword.isEmpty) {
      throw 'Please enter your username and password.';
    }

    // Step 1 — resolve email from username
    final List result;
    try {
      result = await _client
          .from('profiles')
          .select('email, username')
          .ilike('username', cleanUsername)
          .limit(1);
    } catch (_) {
      throw 'Unable to connect. Please check your internet connection and try again.';
    }

    if (result.isEmpty) throw 'No account found with that username.';

    final email = result[0]['email'] as String;
    final usernameFromDB = result[0]['username'] as String;

    // Step 2 — sign in with email + password
    try {
      final authResponse = await _client.auth.signInWithPassword(
        email: email,
        password: cleanPassword,
      );

      if (authResponse.user == null) {
        throw 'Login failed. Please try again.';
      }

      // Clear failures on success
      await _client.rpc(
        'clear_login_failures',
        params: {'p_identifier': cleanUsername},
      );

      return usernameFromDB;
    } on AuthException catch (e) {
      // Record failure for lockout tracking
      await _client.rpc(
        'record_login_failure',
        params: {'p_identifier': cleanUsername},
      );

      switch (e.statusCode) {
        case '400':
          throw 'Incorrect password. Please try again.';
        case '429':
          throw 'Too many login attempts. Please wait a moment and try again.';
        default:
          throw 'Login failed. Please check your credentials and try again.';
      }
    } catch (_) {
      throw 'Something went wrong. Please try again later.';
    }
  }
}
