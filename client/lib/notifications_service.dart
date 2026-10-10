import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'firebase_options.dart';

const String notificationAlertsChannelId = 'altakhfid_alerts_v7';
const String notificationDeviceIdKey = 'altakhfid_fcm_device_id_v1';
const String notificationPendingPayloadKey = 'notification_pending_payload_v1';
const String notificationFcmLastErrorKey = 'altakhfid_fcm_last_error_v1';
const String notificationFcmLastStatusKey = 'altakhfid_fcm_last_status_v1';

typedef NotificationTapHandler = Future<void> Function(
  Map<String, dynamic> payload,
);

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp(options: androidFirebaseOptions);
  } catch (_) {
    // Firebase may already have been initialized by the Android host process.
  }
  // Action-capable devices receive data-only FCM messages, so render the
  // notification here while the Flutter app is backgrounded or terminated.
  await AltakhfidNotificationService.showBackgroundMessage(message);
}

class AltakhfidNotificationService {
  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  static NotificationTapHandler? onTap;
  static StreamSubscription<RemoteMessage>? _messageSubscription;
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
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
          showBadge: true,
        ),
      );
      // Match the official Firebase Flutter pattern for foreground presentation.
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    _messageSubscription = FirebaseMessaging.onMessage.listen((message) {
      unawaited(showForegroundMessage(message));
    });

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
      final response = launch?.notificationResponse;
      if (launch?.didNotificationLaunchApp == true && response != null) {
        await _handleLocalNotificationResponse(response);
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

      // Ask the Android local-notification plugin explicitly too. This is
      // especially important on Android 13+ for POST_NOTIFICATIONS.
      final android = _local.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        final localGranted = await android.requestNotificationsPermission();
        if (localGranted == false) {
          _permissionRequested = true;
          return false;
        }
      }

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
      // FCM auto-initialization is enabled explicitly, then the plugin's
      // supported getToken() API requests the registration token.
      await FirebaseMessaging.instance.setAutoInitEnabled(true);

      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.trim().isEmpty) {
        await _saveFcmDiagnostic(
          status: 'token_empty',
          error: 'FirebaseMessaging.getToken() returned null/empty.',
        );
        return;
      }
      await _saveFcmDiagnostic(
        status: 'token_obtained',
        error: '',
      );
      await _registerToken(token);
    } catch (error) {
      await _saveFcmDiagnostic(
        status: 'token_error',
        error: error.toString(),
      );
      debugPrint('FCM token registration failed: $error');
    }
  }

  static Future<void> _registerToken(String token) async {
    final cleanToken = token.trim();
    if (cleanToken.isEmpty) return;

    final client = ApiService();
    await client.restore();
    if (client.token.isEmpty) {
      await _saveFcmDiagnostic(
        status: 'server_registration_skipped',
        error: 'Access token is empty while registering FCM token.',
      );
      return;
    }

    try {
      await client.registerPushToken(
        deviceId: await _deviceId(),
        pushToken: cleanToken,
        platform: 'android_actions_v1',
      );
      await _saveFcmDiagnostic(
        status: 'server_registered',
        error: '',
      );
    } catch (error) {
      await _saveFcmDiagnostic(
        status: 'server_registration_error',
        error: error.toString(),
      );
      debugPrint('FCM server registration failed: $error');
    }
  }

  static Future<void> _saveFcmDiagnostic({
    required String status,
    required String error,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(notificationFcmLastStatusKey, status);
      if (error.trim().isEmpty) {
        await prefs.remove(notificationFcmLastErrorKey);
      } else {
        await prefs.setString(notificationFcmLastErrorKey, error);
      }
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> fcmDiagnostics() async {
    if (!_isAndroid) {
      return <String, dynamic>{
        'platform': defaultTargetPlatform.name,
        'supported': false,
      };
    }

    final prefs = await SharedPreferences.getInstance();
    String authorization = 'unknown';
    try {
      final settings =
          await FirebaseMessaging.instance.getNotificationSettings();
      authorization = settings.authorizationStatus.name;
    } catch (error) {
      authorization = 'error:' + error.runtimeType.toString();
    }

    String tokenState = 'unknown';
    String tokenPreview = '';
    String tokenError = '';
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.trim().isEmpty) {
        tokenState = 'empty';
      } else {
        tokenState = 'available';
        final clean = token.trim();
        tokenPreview = clean.length <= 12
            ? clean
            : clean.substring(0, 6) + '…' + clean.substring(clean.length - 4);
      }
    } catch (error) {
      tokenState = 'error';
      tokenError = error.toString();
    }

    return <String, dynamic>{
      'platform': defaultTargetPlatform.name,
      'supported': true,
      'authorization': authorization,
      'token_state': tokenState,
      'token_preview': tokenPreview,
      'token_error': tokenError,
      'last_status': prefs.getString(notificationFcmLastStatusKey) ?? '',
      'last_error': prefs.getString(notificationFcmLastErrorKey) ?? '',
    };
  }

  static Future<Uint8List?> _downloadNotificationImage(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 4));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty || response.bodyBytes.length > 5 * 1024 * 1024) return null;
      final contentType = response.headers['content-type'] ?? '';
      if (!contentType.toLowerCase().startsWith('image/')) return null;
      return response.bodyBytes;
    } catch (_) {
      return null;
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

  static Future<void> showBackgroundMessage(RemoteMessage message) async {
    try {
      await _local.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('app_icon'),
        ),
        onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
      );
      final android = _local.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        await android.createNotificationChannel(
          const AndroidNotificationChannel(
            notificationAlertsChannelId,
            'تنبيهات التخفيض الصح',
            description: 'رسائل الطلبات والمحادثات والعروض الجديدة.',
            importance: Importance.high,
            playSound: true,
            enableVibration: true,
            showBadge: true,
          ),
        );
      }
      await _showRemoteMessage(message, plugin: _local);
    } catch (error) {
      debugPrint('Background notification display failed: $error');
    }
  }

  static Future<void> showForegroundMessage(RemoteMessage message) async {
    if (!_isAndroid) return;
    await _showRemoteMessage(message, plugin: _local);
  }

  static Color? _colorFromHex(String raw) {
    final value = raw.trim();
    if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)) return null;
    return Color(int.parse('FF' + value.substring(1), radix: 16));
  }

  static Future<void> _showRemoteMessage(
    RemoteMessage message, {
    required FlutterLocalNotificationsPlugin plugin,
  }) async {
    final payload = _payloadFromRemote(message);
    final id = int.tryParse(payload['notification_id']?.toString() ?? '') ??
        DateTime.now().millisecondsSinceEpoch.remainder(2147483647);
    final title = (payload['title'] ?? 'التخفيض الصح').toString();
    final body = (payload['body'] ?? '').toString();
    final rawData = payload['data'];
    final data =
        rawData is Map ? Map<String, dynamic>.from(rawData) : <String, dynamic>{};
    final imageUrl = (data['image_url'] ?? '').toString().trim();

    try {
      final imageBytes =
          imageUrl.isEmpty ? null : await _downloadNotificationImage(imageUrl);
      final rawAccent = (data['accent_color'] ?? '').toString();
      final accent = _colorFromHex(rawAccent);
      final rawActionColor = (data['action_color'] ?? '').toString();
      final actionColor = _colorFromHex(rawActionColor) ?? accent;
      final showAction = const <String>{'1', 'true', 'yes', 'on'}.contains(
        (data['show_action_button'] ?? '').toString().trim().toLowerCase(),
      );
      final actionLabel = (data['action_label'] ?? 'عرض التفاصيل')
          .toString()
          .trim();
      final actions = showAction
          ? <AndroidNotificationAction>[
              AndroidNotificationAction(
                'open_action',
                actionLabel.isEmpty ? 'عرض التفاصيل' : actionLabel,
                titleColor: actionColor,
                showsUserInterface: true,
                cancelNotification: true,
              ),
            ]
          : null;

      final StyleInformation style = imageBytes == null
          ? BigTextStyleInformation(body)
          : BigPictureStyleInformation(
              ByteArrayAndroidBitmap(imageBytes),
              contentTitle: title,
              summaryText: body,
              showBigPictureWhenCollapsed: true,
            );
      await plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            notificationAlertsChannelId,
            'تنبيهات التخفيض الصح',
            channelDescription: 'رسائل الطلبات والمحادثات والعروض الجديدة.',
            importance: Importance.max,
            priority: Priority.high,
            category: AndroidNotificationCategory.message,
            visibility: NotificationVisibility.public,
            icon: 'notification_icon',
            ticker: 'التخفيض الصح',
            color: accent,
            actions: actions,
            playSound: true,
            enableVibration: true,
            onlyAlertOnce: false,
            autoCancel: true,
            showWhen: true,
            styleInformation: style,
          ),
        ),
        payload: jsonEncode(payload),
      );
    } catch (error) {
      debugPrint('Notification display failed: $error');
    }
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
    unawaited(_handleLocalNotificationResponse(response));
  }

  static Future<void> _handleLocalNotificationResponse(
    NotificationResponse response,
  ) async {
    final payload = _effectiveLocalNotificationPayload(response);
    if (payload == null) {
      await _storePendingPayload(response.payload);
      return;
    }
    final handler = onTap;
    if (handler != null) {
      try {
        await handler(payload);
        return;
      } catch (_) {}
    }
    await _storePendingPayload(jsonEncode(payload));
  }

  static Future<void> dispose() async {
    await _messageSubscription?.cancel();
    await _openedSubscription?.cancel();
    await _tokenSubscription?.cancel();
    _messageSubscription = null;
    _openedSubscription = null;
    _tokenSubscription = null;
  }
}

Map<String, dynamic>? _effectiveLocalNotificationPayload(
  NotificationResponse response,
) {
  final raw = response.payload;
  if (raw == null || raw.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final payload = Map<String, dynamic>.from(decoded);
    if (response.actionId == 'open_action' && payload['data'] is Map) {
      final data = Map<String, dynamic>.from(payload['data'] as Map);
      final rawUrl = (data['action_url'] ?? '').toString().trim();
      final uri = Uri.tryParse(rawUrl);
      if (uri != null &&
          (uri.scheme == 'https' || uri.scheme == 'http') &&
          uri.host.isNotEmpty) {
        data['url'] = rawUrl;
        data['screen_type'] = 'url';
        data['target'] = 'url';
        payload['data'] = data;
      }
    }
    return payload;
  } catch (_) {
    return null;
  }
}

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  final payload = _effectiveLocalNotificationPayload(response);
  if (payload != null) {
    unawaited(
      AltakhfidNotificationService.storePendingPayload(jsonEncode(payload)),
    );
    return;
  }
  unawaited(
    AltakhfidNotificationService.storePendingPayload(response.payload),
  );
}
