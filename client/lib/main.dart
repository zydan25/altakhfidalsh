import 'package:flutter/material.dart';
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
      home: state.loggedIn ? const SxAppShell() : const SxAuthFlowScreen(),
    );
  }
}
