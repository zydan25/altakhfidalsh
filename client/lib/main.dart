import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_state.dart';
import 'auth_flow.dart';
import 'notifications_service.dart';
import 'shein_ui.dart';
import 'theme.dart';

final GlobalKey<NavigatorState> notificationNavigatorKey =
    GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await api.restore();
  await state.restorePreferences();

  await AltakhfidNotificationService.initialize(
    tapHandler: handleNotificationTap,
  );
  if (api.token.isNotEmpty) {
    await AltakhfidNotificationService.ensureStarted();
  }

  runApp(const AltakhfidApp());

  unawaited(
    Future<void>.delayed(
      const Duration(milliseconds: 900),
      AltakhfidNotificationService.handlePendingTap,
    ),
  );
}

Future<void> handleNotificationTap(Map<String, dynamic> payload) async {
  final rawData = payload['data'];
  final data = rawData is Map
      ? Map<String, dynamic>.from(rawData)
      : Map<String, dynamic>.from(payload);

  final screenType =
      (data['screen_type'] ?? data['target'] ?? '').toString();
  final navigator = notificationNavigatorKey.currentState;

  if (navigator == null) {
    await AltakhfidNotificationService.storePendingPayload(
      jsonEncode(payload),
    );
    return;
  }

  if (screenType == 'product_details' || screenType == 'product') {
    final productId =
        int.tryParse((data['product_id'] ?? '').toString()) ?? 0;
    if (productId > 0) {
      await navigator.push(
        MaterialPageRoute(
          builder: (_) => SxProductScreen(
            id: productId,
            cartBuilder: (_) => const SxCartScreen(),
          ),
        ),
      );
    }
    return;
  }

  if (screenType == 'order_details' || screenType == 'order') {
    final orderId = int.tryParse((data['order_id'] ?? '').toString()) ?? 0;
    if (orderId > 0) {
      await navigator.push(
        MaterialPageRoute(
          builder: (_) => SxOrderDetailScreen(id: orderId),
        ),
      );
    }
    return;
  }

  if (screenType == 'conversation') {
    final conversationId =
        int.tryParse((data['conversation_id'] ?? '').toString()) ?? 0;
    if (conversationId > 0) {
      await navigator.push(
        MaterialPageRoute(
          builder: (_) => SxConversationScreen(
            conversationId: conversationId,
            title: data['order_id'] != null
                ? 'محادثة الطلب'
                : 'خدمة العملاء',
          ),
        ),
      );
    }
  }
}

class AltakhfidApp extends StatelessWidget {
  const AltakhfidApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'التخفيض الصح',
      theme: ClientTheme.theme(),
      locale: const Locale('ar'),
      navigatorKey: notificationNavigatorKey,
      home: const SxLaunchGate(),
    );
  }
}

class SxEntryGate extends StatefulWidget {
  const SxEntryGate({super.key});
  @override
  State<SxEntryGate> createState() => _SxEntryGateState();
}

class _SxEntryGateState extends State<SxEntryGate> {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _welcomeSeen(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        return snapshot.data == true
            ? const SxAuthFlowScreen()
            : const SxWelcomeScreen();
      },
    );
  }

  Future<bool> _welcomeSeen() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool('welcome_seen_v1') ?? false;
  }
}

class SxLaunchGate extends StatefulWidget {
  const SxLaunchGate({super.key});

  @override
  State<SxLaunchGate> createState() => _SxLaunchGateState();
}

class _SxLaunchGateState extends State<SxLaunchGate> {
  Timer? _launchTimer;

  @override
  void initState() {
    super.initState();
    _launchTimer = Timer(const Duration(milliseconds: 1100), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              state.loggedIn ? const SxAppShell() : const SxEntryGate(),
        ),
      );
    });
  }

  @override
  void dispose() {
    _launchTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox.expand(
        child: Image(
          image: AssetImage('assets/app_background.jpg'),
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}
