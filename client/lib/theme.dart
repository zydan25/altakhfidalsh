import 'package:flutter/material.dart';

class ClientTheme {
  static const ink = Color(0xFF111111);
  static const bg = Color(0xFFF7F7F7);
  static const surface = Colors.white;
  static const muted = Color(0xFF777777);
  static const border = Color(0xFFE7E7E7);
  static const soft = Color(0xFFF1F1F1);
  static const promo = Color(0xFFFF3B70);
  static const accent = Color(0xFF7A2FD3);
  static const success = Color(0xFF16845B);

  static ThemeData theme() => ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: bg,
    colorScheme: const ColorScheme.light(
      primary: ink,
      onPrimary: Colors.white,
      surface: surface,
      onSurface: ink,
      secondary: ink,
      onSecondary: Colors.white,
      error: Color(0xFFC62828),
    ),
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: const AppBarTheme(
      backgroundColor: surface,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: ink,
        fontSize: 17,
        fontWeight: FontWeight.w900,
      ),
      iconTheme: IconThemeData(color: ink),
    ),
    dividerTheme: const DividerThemeData(
      color: border,
      thickness: 0.7,
      space: 0,
    ),
    navigationBarTheme: const NavigationBarThemeData(
      height: 70,
      backgroundColor: surface,
      elevation: 0,
      indicatorColor: Colors.transparent,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
      ),
      iconTheme: WidgetStatePropertyAll(IconThemeData(size: 22)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: soft,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      hintStyle: const TextStyle(color: muted, fontSize: 12),
      border: OutlineInputBorder(
        borderSide: BorderSide.none,
        borderRadius: BorderRadius.circular(3),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide.none,
        borderRadius: BorderRadius.circular(3),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: ink, width: 1),
        borderRadius: BorderRadius.circular(3),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: soft,
      selectedColor: ink,
      labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      secondaryLabelStyle: const TextStyle(color: Colors.white),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    ),
  );
}
