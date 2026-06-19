import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  static final _client = Supabase.instance.client;

  // ── Signup checks ───────────────────────────────────────────────────────
  // These run BEFORE any session exists, so they call SECURITY DEFINER RPCs
  // (anon-callable) that return only a boolean — never any row data. The
  // `profiles` table itself is no longer readable by the anon key.

  static Future<bool> checkEmailExists(String email) async {
    if (email.trim().isEmpty) return false;
    try {
      final exists = await _client.rpc(
        'email_exists',
        params: {'p_email': email.trim()},
      );
      return exists == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> checkUsernameExists(String username) async {
    if (username.trim().isEmpty) return false;
    try {
      final exists = await _client.rpc(
        'username_exists',
        params: {'p_username': username.trim()},
      );
      return exists == true;
    } catch (_) {
      return false;
    }
  }

  // ── Login ─────────────────────────────────────────────────────────────────
  static Future<String> login(String username, String password) async {
    final cleanUsername = username.trim();
    final cleanPassword = password.trim();

    if (cleanUsername.isEmpty || cleanPassword.isEmpty) {
      throw 'Please enter your username and password.';
    }

    // Step 1 — resolve email from username via a SECURITY DEFINER RPC, so the
    // `profiles` table is not directly readable by the anon key. The RPC
    // matches the username case-insensitively and returns at most one row
    // ({email, username}); it exposes nothing else about the table.
    final List lookup;
    try {
      lookup =
          await _client.rpc(
                'lookup_login_email',
                params: {'p_username': cleanUsername},
              )
              as List;
    } catch (_) {
      throw 'Unable to connect. Please check your internet connection and try again.';
    }

    if (lookup.isEmpty) throw 'No account found with that username.';

    final row = lookup.first as Map<String, dynamic>;
    final email = (row['email'] as String?) ?? '';
    final usernameFromDB = (row['username'] as String?) ?? cleanUsername;

    if (email.isEmpty) throw 'No account found with that username.';

    // Step 2 — sign in with email + password
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
