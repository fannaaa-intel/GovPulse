import 'package:supabase_flutter/supabase_flutter.dart';

/// Handles all authentication operations against Supabase.
class AuthService {
  static final _client = Supabase.instance.client;

  /// Returns true if [email] already exists in the profiles table.
  /// Used by [SignupScreen] to validate the email field in real time.
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

  /// Returns true if [username] already exists in the profiles table.
  /// Used by [SignupScreen] to validate the username field in real time.
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

  /// Signs in a user by [username] and [password].
  ///
  /// Looks up the email address linked to the username, then signs in
  /// with Supabase email+password auth.
  ///
  /// Returns the username string (as stored in the DB) on success.
  /// Throws a human-readable [String] on any failure.
  static Future<String> login(String username, String password) async {
    final cleanUsername = username.trim();
    final cleanPassword = password.trim();

    if (cleanUsername.isEmpty || cleanPassword.isEmpty) {
      throw 'Please enter your username and password.';
    }

    // Step 1: Resolve email from username
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

    // Step 2: Sign in with email + password
    try {
      final authResponse = await _client.auth.signInWithPassword(
        email: email,
        password: cleanPassword,
      );

      if (authResponse.user == null) {
        throw 'Login failed. Please try again.';
      }

      return usernameFromDB;
    } on AuthException catch (e) {
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
