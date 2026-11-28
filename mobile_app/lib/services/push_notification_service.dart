import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const String kPushNotificationChannelId = 'tcaa_slaughter_alerts';
const String kPushNotificationChannelName = 'Slaughterhouse Updates';
const String kPushNotificationChannelDesc =
    'Real-time alerts from Tabaco City Slaughterhouse (approvals, inspections, billing, and releasing).';

/// Top-level background handler required by Firebase Messaging for
/// notifications received while the app is closed (terminated) or in background.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (e) {
    debugPrint('FCM background handler notice: $e');
  }
}

class PushNotificationService {
  PushNotificationService._internal();
  static final PushNotificationService instance = PushNotificationService._internal();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _firebaseReady = false;
  String? _currentToken;
  StreamSubscription<String>? _tokenRefreshSub;

  /// Incremented whenever the user taps a push notification (foreground,
  /// background, or launched from terminated state) so HomeScreen opens Notify.
  final ValueNotifier<int> openNotifyTabTrigger = ValueNotifier<int>(0);

  /// Incremented whenever a push arrives while the app is open so HomeScreen
  /// immediately refreshes the unread count & Notify list.
  final ValueNotifier<int> incomingPushTrigger = ValueNotifier<int>(0);

  bool _pendingOpenNotify = false;
  bool get hasPendingOpenNotify => _pendingOpenNotify;

  void consumePendingOpenNotify() {
    _pendingOpenNotify = false;
  }

  Future<void> init() async {
    if (_initialized || kIsWeb) return;
    _initialized = true;

    // 1. Initialize local notifications + high-importance Android channel with badge support
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidInit);
      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (_) {
          _triggerOpenNotifyTab();
        },
      );

      const androidChannel = AndroidNotificationChannel(
        kPushNotificationChannelId,
        kPushNotificationChannelName,
        description: kPushNotificationChannelDesc,
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      );

      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(androidChannel);
      await androidPlugin?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('Local notifications init notice: $e');
    }

    // 2. Initialize Firebase Messaging gracefully (safe even before google-services.json is added)
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      _firebaseReady = true;

      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      // Foreground push messages -> display heads-up notification & refresh badge
      FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
        final notif = message.notification;
        final title = notif?.title ?? message.data['title']?.toString() ?? 'Slaughterhouse Update';
        final body = notif?.body ?? message.data['message']?.toString() ?? '';
        final unread = int.tryParse(message.data['unread_count']?.toString() ?? '');

        if (body.isNotEmpty) {
          await _showForegroundNotification(
            title: title,
            body: body,
            badgeNumber: unread,
          );
        }

        if (unread != null) {
          await updateAppIconBadge(unread);
        }
        incomingPushTrigger.value++;
      });

      // Tapping notification while app is in background
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        _triggerOpenNotifyTab();
      });

      // App launched from completely closed (terminated) state via tapping notification
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        _triggerOpenNotifyTab();
      }

      // Keep Supabase token synced whenever FCM rotates the device token
      _tokenRefreshSub?.cancel();
      _tokenRefreshSub = messaging.onTokenRefresh.listen((newToken) async {
        _currentToken = newToken;
        await _saveTokenToSupabase(newToken);
      });
    } catch (e) {
      _firebaseReady = false;
      debugPrint('Firebase Messaging not active yet (add google-services.json to enable): $e');
    }
  }

  void _triggerOpenNotifyTab() {
    _pendingOpenNotify = true;
    openNotifyTabTrigger.value++;
  }

  Future<void> _showForegroundNotification({
    required String title,
    required String body,
    int? badgeNumber,
  }) async {
    try {
      final androidDetails = AndroidNotificationDetails(
        kPushNotificationChannelId,
        kPushNotificationChannelName,
        channelDescription: kPushNotificationChannelDesc,
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        channelShowBadge: true,
        number: badgeNumber,
        icon: '@mipmap/ic_launcher',
      );
      final details = NotificationDetails(android: androidDetails);
      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch.remainder(100000),
        title,
        body,
        details,
      );
    } catch (e) {
      debugPrint('Foreground notification display notice: $e');
    }
  }

  /// Registers the current device's FCM token in Supabase `public.user_push_tokens`
  /// for the currently signed-in customer.
  Future<void> syncTokenForCurrentUser() async {
    if (kIsWeb || !_firebaseReady) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.trim().isEmpty) return;
      _currentToken = token.trim();
      await _saveTokenToSupabase(_currentToken!);
    } catch (e) {
      debugPrint('FCM token sync notice: $e');
    }
  }

  Future<bool> _saveTokenToSupabase(String token) async {
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) return false;

      final platform = defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
      try {
        await client.rpc(
          'register_user_push_token',
          params: {
            'p_fcm_token': token,
            'p_platform': platform,
          },
        );
        return true;
      } catch (rpcErr) {
        debugPrint('register_user_push_token RPC fallback: $rpcErr');
        await client.from('user_push_tokens').upsert(
          {
            'user_id': user.id,
            'fcm_token': token,
            'platform': platform,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          onConflict: 'fcm_token',
        );
        return true;
      }
    } catch (e) {
      debugPrint('Save FCM token notice: $e');
      return false;
    }
  }

  /// Diagnostic helper: re-syncs this phone's FCM token and invokes `send-push-notification`
  /// so the customer/tester can confirm real Android push + badge delivery in one tap.
  Future<String> sendTestPushNotification() async {
    if (kIsWeb) return 'Push notifications are only supported on Android/iOS devices.';
    if (!_firebaseReady) {
      return 'Firebase is not initialized on this build. Please rebuild the Android app.';
    }
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return 'Please sign in first.';

    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.trim().isEmpty) {
        return 'Could not get FCM device token from Google Play Services.';
      }
      _currentToken = token.trim();
      final saved = await _saveTokenToSupabase(_currentToken!);
      if (!saved) {
        return 'Device token could not be saved to Supabase (run register_user_push_token SQL).';
      }

      final res = await client.functions.invoke(
        'send-push-notification',
        body: {
          'user_id': user.id,
          'title': 'TCAA Slaughterhouse Test Alert',
          'message': 'Push notifications and app icon badges are active on this device!',
          'type': 'test_push',
        },
      );

      final data = res.data;
      if (data is Map) {
        final sent = data['sent'] ?? 0;
        final reason = data['reason'] ?? data['error'];
        if (sent is num && sent > 0) {
          return 'Test push sent to $sent device(s)! Check your notification shade.';
        }
        return 'Push function responded (${res.status}): ${reason ?? data.toString()}';
      }
      return 'Push function responded (${res.status}): $data';
    } catch (e) {
      return 'Test push failed: $e';
    }
  }

  /// Removes this device's FCM token on sign-out and clears the launcher badge.
  Future<void> removeCurrentTokenOnSignOut() async {
    if (kIsWeb) return;
    try {
      final token = _currentToken ??
          (_firebaseReady ? await FirebaseMessaging.instance.getToken() : null);
      if (token != null && token.trim().isNotEmpty) {
        await Supabase.instance.client
            .from('user_push_tokens')
            .delete()
            .eq('fcm_token', token.trim());
      }
      _currentToken = null;
    } catch (e) {
      debugPrint('Remove FCM token notice: $e');
    }
    await updateAppIconBadge(0);
  }

  /// Clears the native Android launcher app icon badge when all notifications
  /// have been read (`unreadCount <= 0`). When new pushes arrive while closed,
  /// Android natively shows the launcher badge via the `tcaa_slaughter_alerts`
  /// channel (`showBadge: true`) and FCM `notification_count`.
  Future<void> updateAppIconBadge(int unreadCount) async {
    if (kIsWeb) return;
    try {
      if (unreadCount <= 0) {
        await _localNotifications.cancelAll();
      }
    } catch (e) {
      debugPrint('App icon badge clear notice: $e');
    }
  }
}
