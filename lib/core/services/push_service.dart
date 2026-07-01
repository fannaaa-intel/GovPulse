// ════════════════════════════════════════════════════════════════════════════
//  lib/core/services/push_service.dart
//
//  Handles Firebase Cloud Messaging on the device:
//    • requests notification permission (Android 13+ / iOS)
//    • stores this device's FCM token in Supabase `device_tokens`
//    • subscribes every device to the "all" topic (for target_all broadcasts)
//    • shows a local notification when a push arrives while the app is OPEN
//      (the OS shows it automatically when the app is backgrounded/killed)
//    • exposes a tap stream so the app can navigate when a push is opened
// ════════════════════════════════════════════════════════════════════════════

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Background / terminated handler. MUST be top-level (or static) and annotated.
/// When the message carries a `notification` block (ours does), the OS shows it
/// automatically — so there is nothing to display here. Keep it lightweight.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Intentionally empty. Add data-only processing here if you ever need it.
}

class PushService {
  PushService._();
  static final PushService I = PushService._();

  final FirebaseMessaging _fm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;
  static const String _broadcastTopic = 'all';

  /// Notification taps surface here as the message's `data` map. Listen to this
  /// from your root widget to navigate (e.g. open the verification screen).
  final ValueNotifier<Map<String, dynamic>?> lastTap = ValueNotifier(null);

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'general_channel',
    'Notifications',
    description: 'Aparri app notifications',
    importance: Importance.high,
  );

  SupabaseClient get _db => Supabase.instance.client;

  /// Call ONCE at startup, after Firebase.initializeApp() and
  /// Supabase.initialize(). Safe to call again — it no-ops.
  Future<void> init() async {
    if (_ready) return;
    _ready = true;

    // Web has no FCM device token / topic support and no local-notifications
    // plugin. The admin console (which runs on web) instead receives its
    // notifications from the Supabase `notifications` table + Realtime, so we
    // simply no-op the whole FCM path here. This is what stops the
    // "subscribeToTopic() is not supported on the web clients" crash.
    if (kIsWeb) return;

    // Local notifications — used to display pushes while the app is foreground.
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _local.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (resp) {
        // A tap on a locally-shown (foreground) notification.
        lastTap.value = {'tapped': 'local'};
      },
    );
    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);

    // Permission (Android 13+, iOS).
    await _fm.requestPermission(alert: true, badge: true, sound: true);

    // iOS: also show banners while the app is in the foreground.
    await _fm.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Foreground pushes: the OS won't display them, so we do (mainly Android).
    FirebaseMessaging.onMessage.listen(_showForeground);

    // Tap on a system notification that opened the app from background.
    FirebaseMessaging.onMessageOpenedApp.listen((m) {
      lastTap.value = m.data;
    });

    // App launched from terminated by tapping a notification.
    final initial = await _fm.getInitialMessage();
    if (initial != null) lastTap.value = initial.data;

    // Re-claim the token whenever Firebase rotates it.
    _fm.onTokenRefresh.listen(_register);
  }

  // This device's current FCM token, captured at registration time so that
  // logout can delete the right row even after the session is gone.
  String? _cachedToken;

  /// Call right after the user is authenticated (and once on startup if a
  /// session was restored). Claims this device's token for the current user,
  /// reassigning it away from whoever held it before on this phone.
  Future<void> registerForUser() async {
    if (kIsWeb) return; // FCM topics/tokens unsupported on web — see init().
    try {
      await _fm.subscribeToTopic(_broadcastTopic);
      final token = await _fm.getToken();
      if (token != null) {
        _cachedToken = token;
        await _register(token);
      }
    } catch (e) {
      debugPrint('PushService.registerForUser error: $e');
    }
  }

  /// Call on logout so this device stops receiving the user's pushes.
  /// Uses the token captured at login (reading it after sign-out is
  /// unreliable — the session is already gone).
  Future<void> unregister() async {
    if (kIsWeb) {
      _cachedToken = null;
      return; // no device token to release on web
    }
    try {
      final uid = _db.auth.currentUser?.id; // captured while still logged in
      final token = _cachedToken ?? await _fm.getToken();
      if (token != null && uid != null) {
        await _db.rpc(
          'unregister_device_token',
          params: {'p_token': token, 'p_user_id': uid},
        );
      }
      _cachedToken = null;
    } catch (e) {
      debugPrint('PushService.unregister error: $e');
    }
  }

  /// Claims [token] for the current user via the security-definer RPC, which
  /// reassigns it away from any previous owner (RLS can't do this from the
  /// client, since a user may only touch rows they already own).
  Future<void> _register(String token) async {
    if (kIsWeb) return;
    if (_db.auth.currentUser == null) return;
    try {
      await _db.rpc(
        'register_device_token',
        params: {
          'p_token': token,
          'p_platform': Platform.isIOS ? 'ios' : 'android',
        },
      );
    } catch (e) {
      debugPrint('PushService._register error: $e');
    }
  }

  Future<void> _showForeground(RemoteMessage m) async {
    final n = m.notification;
    final title = n?.title ?? (m.data['title'] as String?) ?? 'Notification';
    final body = n?.body ?? (m.data['subtitle'] as String?) ?? '';
    await _local.show(
      title.hashCode & 0x7fffffff,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }
}