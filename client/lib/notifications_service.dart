import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const String notificationAlertsChannelId = 'altakhfid_alerts_v4';
const String notificationBackgroundChannelId = 'altakhfid_background_v2';
const int notificationForegroundServiceId = 41001;
const String notificationLastSeenKey = 'notification_last_seen_id_v1';
const String notificationPendingPayloadKey = 'notification_pending_payload_v1';

typedef NotificationTapHandler = Future<void> Function(Map<String, dynamic> payload);

class AltakhfidNotificationService {
  static final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  static final FlutterBackgroundService _background = FlutterBackgroundService();
  static NotificationTapHandler? onTap;
  static bool _initialized = false;

  static Future<void> initialize({NotificationTapHandler? tapHandler}) async {
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
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          showBadge: true,
        ),
      );
      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          notificationBackgroundChannelId,
          'اتصال الإشعارات',
          description: 'اتصال التخفيض الصح لاستقبال التنبيهات الفورية.',
          importance: Importance.low,
          playSound: false,
          enableVibration: false,
          showBadge: false,
        ),
      );
    }

    final launch = await _local.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      await _storePendingPayload(launch?.notificationResponse?.payload);
    }

    await _background.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: notificationBackgroundEntrypoint,
        autoStart: false,
        autoStartOnBoot: true,
        isForegroundMode: true,
        notificationChannelId: notificationBackgroundChannelId,
        initialNotificationTitle: 'التخفيض الصح',
        initialNotificationContent: 'اتصال الإشعارات الفوري يعمل.',
        foregroundServiceNotificationId: notificationForegroundServiceId,
        foregroundServiceTypes: const [AndroidForegroundType.remoteMessaging],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: notificationIosForeground,
        onBackground: notificationIosBackground,
      ),
    );
  }

  static Future<bool> requestNotificationAccess() async {
    if (kIsWeb) return true;
    await initialize();
    final android = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;

    var enabled = await android.areNotificationsEnabled();
    if (enabled != true) {
      enabled = await android.requestNotificationsPermission();
    }
    final finalEnabled = await android.areNotificationsEnabled();
    if (finalEnabled != true) {
      debugPrint('Altakhfid notifications are disabled by Android.');
      return false;
    }
    return enabled != false || finalEnabled == true;
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
    final token = prefs.getString('access_token') ?? '';
    if (token.trim().isEmpty) return;
    if (!await _background.isRunning()) {
      await _background.startService();
    }
  }

  static Future<void> stop() async {
    if (kIsWeb) return;
    try {
      _background.invoke('stop');
    } catch (_) {}
  }

  static Future<void> storePendingPayload(String? raw) async {
    await _storePendingPayload(raw);
  }

  static Future<void> handlePendingTap() async {
    final payload = await takePendingPayload();
    if (payload == null) return;
    // The app shell polls pending payloads once Navigator is ready.
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

  static Future<void> _storePendingPayload(String? raw) async {
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final data = jsonDecode(raw);
      if (data is Map) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(notificationPendingPayloadKey, jsonEncode(Map<String, dynamic>.from(data)));
      }
    } catch (_) {}
  }

  static void _onNotificationResponse(NotificationResponse response) {
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
}

@pragma('vm:entry-point')
Future<bool> notificationIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void notificationIosForeground(ServiceInstance service) {}

@pragma('vm:entry-point')
void notificationBackgroundEntrypoint(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();

  final local = FlutterLocalNotificationsPlugin();
  const initialization = InitializationSettings(
    android: AndroidInitializationSettings('app_icon'),
    iOS: DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    ),
  );
  try {
    await local.initialize(
      settings: initialization,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
  } catch (_) {}

  service.on('stop').listen((_) {
    service.stopSelf();
  });
  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
    service.setForegroundNotificationInfo(
      title: 'التخفيض الصح',
      content: 'اتصال الإشعارات الفوري يعمل.',
    );
  }

  var retrySeconds = 2;
  while (true) {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final token = prefs.getString('access_token') ?? '';
    if (token.trim().isEmpty) {
      service.stopSelf();
      return;
    }

    try {
      await _syncMissedNotifications(prefs, token, local);
      final base = _apiBaseUrl();
      final socketScheme = base.startsWith('https://') ? 'wss://' : 'ws://';
      final socketBase = base.replaceFirst(RegExp(r'^https?://'), socketScheme);
      final channel = WebSocketChannel.connect(
        Uri.parse(socketBase + '/notifications/ws'),
        protocols: ['altakhfid-bearer', token],
      );

      final done = Completer<void>();
      late StreamSubscription<dynamic> subscription;
      subscription = channel.stream.listen(
        (raw) async {
          try {
            final decoded = raw is String ? jsonDecode(raw) : raw;
            if (decoded is! Map) return;
            final payload = Map<String, dynamic>.from(decoded);
            if (payload['type'] == 'heartbeat' || payload['type'] == 'connected' || payload['type'] == 'error') return;
            final notificationId = int.tryParse((payload['notification_id'] ?? '').toString());
            if (notificationId == null || notificationId <= 0) return;
            // Only advance the durable cursor after Android accepted the notification.
            // This prevents a local-notification failure from silently dropping the event.
            await _showFromLocal(local, payload);
            await _saveLastSeen(prefs, notificationId);
            debugPrint('Altakhfid native notification shown: $notificationId');
          } catch (_) {}
        },
        onError: (_) { if (!done.isCompleted) done.complete(); },
        onDone: () { if (!done.isCompleted) done.complete(); },
        cancelOnError: true,
      );
      await done.future.timeout(const Duration(minutes: 5), onTimeout: () {});
      await subscription.cancel();
      try { await channel.sink.close(); } catch (_) {}
      retrySeconds = 2;
    } catch (_) {
      retrySeconds = (retrySeconds * 2).clamp(2, 60);
    }
    await Future<void>.delayed(Duration(seconds: retrySeconds));
  }
}

Future<void> _syncMissedNotifications(SharedPreferences prefs, String token, FlutterLocalNotificationsPlugin local) async {
  try {
    final response = await http.get(
      Uri.parse(_apiBaseUrl() + '/notifications/notifications/me'),
      headers: <String, String>{'Authorization': 'Bearer ' + token, 'Accept': 'application/json'},
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) return;
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) return;
    final rows = (decoded['items'] as List? ?? const [])
        .whereType<Map>()
        .map((x) => Map<String, dynamic>.from(x))
        .toList()
      ..sort((a, b) => (int.tryParse((a['id'] ?? '').toString()) ?? 0).compareTo(int.tryParse((b['id'] ?? '').toString()) ?? 0));
    final stored = prefs.getInt(notificationLastSeenKey);
    if (stored == null) {
      final maxId = rows.fold<int>(0, (max, row) { final id = int.tryParse((row['id'] ?? '').toString()) ?? 0; return id > max ? id : max; });
      if (maxId > 0) await prefs.setInt(notificationLastSeenKey, maxId);
      return;
    }
    var lastSeen = stored;
    for (final row in rows) {
      final id = int.tryParse((row['id'] ?? '').toString()) ?? 0;
      if (id <= lastSeen) continue;
      try {
        await _showFromLocal(local, row);
        lastSeen = id;
        await prefs.setInt(notificationLastSeenKey, lastSeen);
      } catch (_) {
        // Keep the cursor unchanged so this notification is retried on the next sync.
      }
    }
  } catch (_) {}
}

Future<void> _showFromLocal(FlutterLocalNotificationsPlugin local, Map<String, dynamic> payload) async {
  final id = int.tryParse((payload['notification_id'] ?? payload['id'] ?? '').toString()) ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000);
  await local.show(
    id: id,
    title: (payload['title'] ?? 'التخفيض الصح').toString(),
    body: (payload['body'] ?? '').toString(),
    notificationDetails: NotificationDetails(
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
        vibrationPattern: Int64List.fromList(<int>[0, 250, 120, 250]),
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

Future<void> _saveLastSeen(SharedPreferences prefs, int id) async {
  final old = prefs.getInt(notificationLastSeenKey) ?? 0;
  if (id > old) await prefs.setInt(notificationLastSeenKey, id);
}

String _apiBaseUrl() {
  const value = String.fromEnvironment('API_BASE_URL', defaultValue: 'https://takhfidsh.alattab.site/api/v1');
  return value.replaceAll(RegExp(r'/$'), '');
}

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  final raw = response.payload;
  if (raw == null || raw.trim().isEmpty) return;
  unawaited(
    AltakhfidNotificationService._storePendingPayload(raw),
  );
}
