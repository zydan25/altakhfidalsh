import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

const String notificationAlertsChannelId = 'altakhfid_alerts_v5';
const String notificationDeviceIdKey = 'altakhfid_fcm_device_id_v1';
const String notificationPendingPayloadKey = 'notification_pending_payload_v1';

typedef NotificationTapHandler = Future<void> Function(
  Map<String, dynamic> payload,
);

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  // Notification messages received while the Android app is backgrounded or
  // terminated are displayed by FCM/Android. Do not post another local copy.
}

class AltakhfidNotificationService {
  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  static NotificationTapHandler? onTap;
  static StreamSubscription<RemoteMessage>? _openedSubscription;
  static StreamSubscription<String>? _tokenSubscription;
  static bool _initialized = false;
  static bool _permissionRequested = false;

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> initialize({
    NotificationTapHandler? tapHandler,
  }) async {
    onTap ??= tapHandler;
    if (!_isAndroid || _initialized) return;
    _initialized = true;

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    const initialization = InitializationSettings(
      android: AndroidInitializationSettings('app_icon'),
    );
    await _local.initialize(
      settings: initialization,
      onDidReceiveNotificationResponse: _onLocalNotificationResponse,
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

    _openedSubscription =
        FirebaseMessaging.onMessageOpenedApp.listen((message) {
      unawaited(_handleRemoteTap(message));
    });

    _tokenSubscription =
        FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      unawaited(_registerToken(token));
    });

    try {
      final initialMessage =
          await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        await _handleRemoteTap(initialMessage);
      }
    } catch (_) {}

    try {
      final launch = await _local.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        await _storePendingPayload(launch?.notificationResponse?.payload);
      }
    } catch (_) {}
  }

  static Future<bool> requestNotificationAccess() async {
    if (!_isAndroid) return true;
    await initialize();

    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        announcement: false,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
      );
      _permissionRequested = true;

      final granted =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;

      if (granted) {
        await _registerCurrentToken();
      }
      return granted;
    } catch (error) {
      debugPrint('FCM permission request failed: $error');
      return false;
    }
  }

  static Future<void> openNotificationSettings() async {
    if (!_isAndroid) return;
    try {
      await _local.openAppNotificationSettings();
    } catch (_) {}
  }

  static Future<void> ensureStarted() async {
    if (!_isAndroid) return;
    await initialize();

    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString('access_token') ?? '';
    if (accessToken.trim().isEmpty) return;

    try {
      final settings =
          await FirebaseMessaging.instance.getNotificationSettings();
      final enabled = settings.authorizationStatus ==
              AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
      if (enabled || !_permissionRequested) {
        await _registerCurrentToken();
      }
    } catch (_) {
      await _registerCurrentToken();
    }
  }

  static Future<void> stop() async {
    if (!_isAndroid) return;
    try {
      final client = ApiService();
      await client.restore();
      if (client.token.isEmpty) return;
      await client.unregisterPushToken(deviceId: await _deviceId());
    } catch (_) {}
  }

  static Future<String> _deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = (prefs.getString(notificationDeviceIdKey) ?? '').trim();
    if (existing.isNotEmpty) return existing;

    final random = Random.secure();
    final parts = List<String>.generate(
      4,
      (_) => random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0'),
    );
    final id =
        DateTime.now().microsecondsSinceEpoch.toRadixString(16) +
        '-' +
        parts.join();
    await prefs.setString(notificationDeviceIdKey, id);
    return id;
  }

  static Future<void> _registerCurrentToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.trim().isEmpty) return;
      await _registerToken(token);
    } catch (error) {
      debugPrint('FCM token registration failed: $error');
    }
  }

  static Future<void> _registerToken(String token) async {
    final cleanToken = token.trim();
    if (cleanToken.isEmpty) return;

    final client = ApiService();
    await client.restore();
    if (client.token.isEmpty) return;

    try {
      await client.registerPushToken(
        deviceId: await _deviceId(),
        pushToken: cleanToken,
        platform: 'android',
      );
    } catch (error) {
      debugPrint('FCM server registration failed: $error');
    }
  }

  static Map<String, dynamic> _payloadFromRemote(RemoteMessage message) {
    final data = Map<String, dynamic>.from(message.data);
    final id = data['notification_id']?.toString() ??
        message.messageId ??
        DateTime.now().millisecondsSinceEpoch.toString();

    return <String, dynamic>{
      'notification_id': id,
      'title': message.notification?.title ??
          data['title'] ??
          'التخفيض الصح',
      'body': message.notification?.body ?? data['body'] ?? '',
      'data': data,
    };
  }

  static Future<void> _handleRemoteTap(RemoteMessage message) async {
    final payload = _payloadFromRemote(message);
    final handler = onTap;
    if (handler == null) {
      await _storePendingPayload(jsonEncode(payload));
      return;
    }
    try {
      await handler(payload);
    } catch (_) {
      await _storePendingPayload(jsonEncode(payload));
    }
  }

  static Future<void> showForegroundMessage(RemoteMessage message) async {
    if (!_isAndroid) return;

    final payload = _payloadFromRemote(message);
    final id = int.tryParse(
          payload['notification_id']?.toString() ?? '',
        ) ??
        DateTime.now().millisecondsSinceEpoch.remainder(2147483647);

    await _local.show(
      id,
      (payload['title'] ?? 'التخفيض الصح').toString(),
      (payload['body'] ?? '').toString(),
      NotificationDetails(
        android: AndroidNotificationDetails(
          notificationAlertsChannelId,
          'تنبيهات التخفيض الصح',
          channelDescription:
              'رسائل الطلبات والمحادثات والعروض الجديدة.',
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
          styleInformation: BigTextStyleInformation(
            (payload['body'] ?? '').toString(),
          ),
        ),
      ),
      payload: jsonEncode(payload),
    );
  }

  static Future<void> storePendingPayload(String? raw) async {
    await _storePendingPayload(raw);
  }

  static Future<Map<String, dynamic>?> takePendingPayload() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(notificationPendingPayloadKey);
    if (raw == null || raw.trim().isEmpty) return null;
    await prefs.remove(notificationPendingPayloadKey);
    try {
      final parsed = jsonDecode(raw);
      return parsed is Map ? Map<String, dynamic>.from(parsed) : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> handlePendingTap() async {}

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

  static void _onLocalNotificationResponse(
    NotificationResponse response,
  ) {
    final raw = response.payload;
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map && onTap != null) {
        unawaited(onTap!(Map<String, dynamic>.from(decoded)));
      } else {
        unawaited(_storePendingPayload(raw));
      }
    } catch (_) {
      unawaited(_storePendingPayload(raw));
    }
  }

  static Future<void> dispose() async {
    await _openedSubscription?.cancel();
    await _tokenSubscription?.cancel();
    _openedSubscription = null;
    _tokenSubscription = null;
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
