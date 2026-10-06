import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_state.dart';
import 'auth_flow.dart';
import 'notifications_service.dart';
import 'product_detail.dart';
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
  runApp(const AltakhfidApp());

  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_prepareNotificationService());
  });
}

Future<void> _prepareNotificationService() async {
  if (api.token.isEmpty) return;
  final granted = await AltakhfidNotificationService.requestNotificationAccess();
  if (granted) {
    await AltakhfidNotificationService.ensureStarted();
  }
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

class _SxLaunchGateState extends State<SxLaunchGate>
    with SingleTickerProviderStateMixin {
  Timer? _launchTimer;
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..forward();

    _launchTimer = Timer(const Duration(milliseconds: 1700), () {
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
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.68, curve: Curves.easeOut),
    );
    final logoScale = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.05, 0.72, curve: Curves.easeOutBack),
      ),
    );
    final progress = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFF161616),
                      const Color(0xFF050505),
                      Colors.black,
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Center(
                child: FadeTransition(
                  opacity: fade,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ScaleTransition(
                        scale: logoScale,
                        child: Container(
                          width: 118,
                          height: 118,
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black,
                            border: Border.all(
                              color: const Color(0xFFF3B30D).withOpacity(.8),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFF3B30D).withOpacity(.12),
                                blurRadius: 24,
                                spreadRadius: 3,
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: Image.asset(
                              'assets/app_background.jpg',
                              fit: BoxFit.cover,
                              alignment: Alignment.center,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'مرحبًا بعودتك',
                        style: TextStyle(
                          color: Color(0xFFF0F0F0),
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          letterSpacing: .2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'التخفيض الصح',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 31,
                          fontWeight: FontWeight.w900,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 34),
                        child: Text(
                          'تسوّق بثقة، اكتشف العروض، واطلب بسهولة من مكان واحد.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFFB8B8B8),
                            fontSize: 11.5,
                            height: 1.65,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      AnimatedBuilder(
                        animation: progress,
                        builder: (context, _) {
                          return Column(
                            children: [
                              SizedBox(
                                width: 132,
                                height: 4,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(99),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      const ColoredBox(
                                        color: Color(0xFF2A2A2A),
                                      ),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: FractionallySizedBox(
                                          widthFactor: progress.value,
                                          child: const ColoredBox(
                                            color: Color(0xFFF3B30D),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Transform.translate(
                                    offset: Offset(
                                      -8 + (16 * progress.value),
                                      0,
                                    ),
                                    child: const Icon(
                                      Icons.search_rounded,
                                      size: 15,
                                      color: Color(0xFFF3B30D),
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  const Text(
                                    'نجهّز تجربتك…',
                                    style: TextStyle(
                                      color: Color(0xFF8E8E8E),
                                      fontSize: 9.5,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Positioned(
              left: 0,
              right: 0,
              bottom: 18,
              child: Text(
                'تجربة تسوق عربية صُممت للهاتف أولًا',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF606060),
                  fontSize: 8.5,
                  letterSpacing: .15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
