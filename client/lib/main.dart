import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'auth_flow.dart';
import 'app_state.dart';
import 'shein_ui.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await api.restore();
  await state.restorePreferences();
  runApp(const AltakhfidApp());
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
      home: state.loggedIn ? const SxAppShell() : const SxEntryGate(),
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
          return const Scaffold(body: Center(child: CircularProgressIndicator(strokeWidth: 2)));
        }
        return snapshot.data == true ? const SxAuthFlowScreen() : const SxWelcomeScreen();
      },
    );
  }

  Future<bool> _welcomeSeen() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool('welcome_seen_v1') ?? false;
  }
}
