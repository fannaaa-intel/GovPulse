import 'dart:convert';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;

class FacebookSignInService {
  static final _client = Supabase.instance.client;

  static Future<User> signIn() async {
    // ── 1. Trigger native Facebook login ─────────────────────────────────
    final loginResult = await FacebookAuth.instance.login(
      permissions: ['email', 'public_profile'],
    );

    switch (loginResult.status) {
      case LoginStatus.cancelled:
        throw 'Facebook sign-in was cancelled.';
      case LoginStatus.failed:
        throw loginResult.message ??
            'Facebook sign-in failed. Please try again.';
      case LoginStatus.operationInProgress:
        throw 'A Facebook sign-in is already in progress.';
      case LoginStatus.success:
        break;
    }

    final accessToken = loginResult.accessToken?.tokenString;
    if (accessToken == null) {
      throw 'Could not retrieve Facebook access token.';
    }

    // ── 2. Exchange Facebook access token for Supabase session ───────────
    // Supabase supports Facebook via its token endpoint
    try {
      const supabaseUrl = 'https://vxvflhjbafqwehuxnmeq.supabase.co';
      const supabaseKey = 'sb_publishable_ZBDaQPQdFyC5kOHGbce9Ig_zdtIi6Mo';

      final response = await http.post(
        Uri.parse('$supabaseUrl/auth/v1/token?grant_type=facebook'),
        headers: {'Content-Type': 'application/json', 'apikey': supabaseKey},
        body: jsonEncode({'access_token': accessToken}),
      );

      if (response.statusCode != 200) {
        final error = jsonDecode(response.body);
        throw error['error_description'] ??
            error['msg'] ??
            'Facebook sign-in failed.';
      }

      final data = jsonDecode(response.body);
      final accessTokenRes = data['access_token'] as String?;
      final refreshToken = data['refresh_token'] as String?;

      if (accessTokenRes == null || refreshToken == null) {
        throw 'Invalid response from server.';
      }

      // Set the session in Supabase client
      final sessionResponse = await _client.auth.setSession(refreshToken);
      final user = sessionResponse.user;
      if (user == null) throw 'Could not establish session.';

      return user;
    } on AuthException catch (e) {
      throw e.message;
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      if (msg == 'Facebook sign-in was cancelled.') throw msg;
      throw 'Something went wrong. Please try again.';
    }
  }

  static Future<Map<String, dynamic>> getUserData() async {
    try {
      return await FacebookAuth.instance.getUserData(fields: 'name,email');
    } catch (_) {
      return {};
    }
  }

  static Future<void> signOut() async {
    await FacebookAuth.instance.logOut();
    await _client.auth.signOut();
  }
}
