import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

const String notificationAlertsChannelId = 'altakhfid_alerts_v5';
const String notificationLastSeenKey = 'notification_last_seen_id_v1';
const String notificationPendingPayloadKey = 'notification_pending_payload_v1';
const String notificationDeviceIdKey = 'notification_device_id_v1';

typedef NotificationTapHandler = Future<void> Function(
  Map<String, dynamic> payload,
);

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Notification messages are displayed by Android automatically while the
  // app is in the background/terminated. Keep this handler intentionally light.
  // It is also invoked for data-only messages.
}

class AltakhfidNotificationService {
  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  static NotificationTapHandler? onTap;
  static bool _initialized = false;
  static StreamSubscription<RemoteMessage>? _foregroundSubscription;
  static StreamSubscription<RemoteMessage>? _openedSubscription;
  static StreamSubscription<String>? _tokenSubscription;

  static Future<void> initialize({
    NotificationTapHandler? tapHandler,
  }) async {
    onTap ??= tapHandler;
    if (_initialized || kIsWeb) return;
    _initialized = true;

    const initialization = InitializationSettings(
      android: AndroidInitializationSettings('app_icon'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );

    await _local.initialize(
      settings: initialization,
      onDidReceiveNotificationResponse: _onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
          notificationTapBackground,
    );

    final android = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (android != null) {
      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          notificationAlertsChannelId,
          'تنبيهات التخفيض الصح',
          description: 'رسائل الطلبات والمحادثات والعروض الجديدة.',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          showBadge: true,
        ),
      );
    }

    FirebaseMessaging.onBackgroundMessage(
      firebaseMessagingBackgroundHandler,
    );

    _foregroundSubscription = FirebaseMessaging.onMessage.listen(
      (message) async {
        try {
          await _showFromRemoteMessage(message);
        } catch (_) {}
      },
    );

    _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
      (message) async {
        await _dispatchTap(_remotePayload(message));
      },
    );

    _tokenSubscription = _messaging.onTokenRefresh.listen(
      (token) async {
        try {
          await _registerToken(token);
        } catch (_) {}
      },
    );

    try {
      final initial = await _messaging.getInitialMessage();
      if (initial != null) {
        await _storePendingPayload(
          jsonEncode(_remotePayload(initial)),
        );
      }
    } catch (_) {}
  }

  static Future<bool> requestNotificationAccess() async {
    if (kIsWeb) return true;
    await initialize();

    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      final authorized =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
              settings.authorizationStatus ==
                  AuthorizationStatus.provisional;

      if (!authorized) {
        return false;
      }
    } catch (_) {}

    final android = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;

    try {
      final enabled = await android.areNotificationsEnabled();
      if (enabled != true) {
        return false;
      }
    } catch (_) {}

    return true;
  }

  static Future<void> openNotificationSettings() async {
    if (kIsWeb) return;
    try {
      await _local.openAppNotificationSettings();
    } catch (_) {}
  }

  static Future<void> ensureStarted() async {
    if (kIsWeb) return;
    await initialize();

    final prefs = await SharedPreferences.getInstance();
    final token = await _messaging.getToken();
    if (token == null || token.trim().isEmpty) return;

    await _registerToken(token, prefs: prefs);
  }

  static Future<String> _deviceId(
    SharedPreferences prefs,
  ) async {
    final existing = prefs.getString(notificationDeviceIdKey);
    if (existing != null && existing.trim().isNotEmpty) {
      return existing;
    }

    const alphabet =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    final value = StringBuffer('android-');
    for (var i = 0; i < 24; i++) {
      value.write(alphabet[random.nextInt(alphabet.length)]);
    }
    final id = value.toString();
    await prefs.setString(notificationDeviceIdKey, id);
    return id;
  }

  static Future<void> _registerToken(
    String token, {
    SharedPreferences? prefs,
  }) async {
    if (token.trim().isEmpty) return;

    final p = prefs ?? await SharedPreferences.getInstance();
    final accessToken = p.getString('access_token') ?? '';
    if (accessToken.trim().isEmpty) return;

    final deviceId = await _deviceId(p);
    await api.registerPushToken(
      token: token.trim(),
      deviceId: deviceId,
      platform: 'android',
    );
  }

  static Future<void> stop() async {
    if (kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = await _messaging.getToken();
      final deviceId = await _deviceId(prefs);
      if (token != null && token.trim().isNotEmpty) {
        await api.unregisterPushToken(
          token: token,
          deviceId: deviceId,
        );
      }
    } catch (_) {}
  }

  static Future<void> storePendingPayload(String? raw) async {
    await _storePendingPayload(raw);
  }

  static Future<void> handlePendingTap() async {}

  static Future<Map<String, dynamic>?> takePendingPayload() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(notificationPendingPayloadKey);
    if (raw == null || raw.trim().isEmpty) return null;
    await prefs.remove(notificationPendingPayloadKey);

    try {
      final parsed = jsonDecode(raw);
      return parsed is Map
          ? Map<String, dynamic>.from(parsed)
          : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _storePendingPayload(String? raw) async {
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final data = jsonDecode(raw);
      if (data is Map) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          notificationPendingPayloadKey,
          jsonEncode(Map<String, dynamic>.from(data)),
        );
      }
    } catch (_) {}
  }

  static Map<String, dynamic> _remotePayload(RemoteMessage message) {
    final data = <String, dynamic>{...message.data};
    if (message.messageId != null && message.messageId!.isNotEmpty) {
      data['fcm_message_id'] = message.messageId;
    }

    final notification = message.notification;
    if (notification != null) {
      data['title'] ??= notification.title ?? 'التخفيض الصح';
      data['body'] ??= notification.body ?? '';
    }
    return data;
  }

  static Future<void> _showFromRemoteMessage(
    RemoteMessage message,
  ) async {
    final payload = _remotePayload(message);
    final title = (payload['title'] ?? 'التخفيض الصح').toString();
    final body = (payload['body'] ?? '').toString();

    if (title.trim().isEmpty && body.trim().isEmpty) return;

    final id = int.tryParse(
          (payload['notification_id'] ?? '').toString(),
        ) ??
        DateTime.now().millisecondsSinceEpoch ~/ 1000;

    await _local.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          notificationAlertsChannelId,
          'تنبيهات التخفيض الصح',
          channelDescription: 'رسائل الطلبات والمحادثات والعروض الجديدة.',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.message,
          visibility: NotificationVisibility.public,
          icon: 'notification_icon',
          ticker: 'التخفيض الصح',
          playSound: true,
          enableVibration: true,
          onlyAlertOnce: false,
          autoCancel: true,
          showWhen: true,
        ),
      ),
      payload: jsonEncode(payload),
    );
  }

  static Future<void> _dispatchTap(
    Map<String, dynamic> payload,
  ) async {
    if (onTap != null) {
      await onTap!(payload);
    } else {
      await _storePendingPayload(jsonEncode(payload));
    }
  }

  static void _onNotificationResponse(NotificationResponse response) {
    final raw = response.payload;
    if (raw == null || raw.trim().isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map && onTap != null) {
        unawaited(
          onTap!(Map<String, dynamic>.from(decoded)),
        );
      } else {
        unawaited(_storePendingPayload(raw));
      }
    } catch (_) {
      unawaited(_storePendingPayload(raw));
    }
  }
}

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  final raw = response.payload;
  if (raw == null || raw.trim().isEmpty) return;
  unawaited(
    AltakhfidNotificationService._storePendingPayload(raw),
  );
}
