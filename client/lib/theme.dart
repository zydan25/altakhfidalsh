import 'package:flutter/material.dart';
class ClientTheme {
  static const ink=Color(0xFF111111);
  static const bg=Color(0xFFF7F7F7);
  static const muted=Color(0xFF777777);
  static const border=Color(0xFFE6E6E6);
  static const promo=Color(0xFFFF5A36);
  static ThemeData theme()=>ThemeData(
    useMaterial3:true,
    scaffoldBackgroundColor:bg,
    colorScheme:ColorScheme.fromSeed(seedColor:ink),
    appBarTheme:const AppBarTheme(backgroundColor:Colors.white,foregroundColor:ink,elevation:0,centerTitle:true),
    inputDecorationTheme:InputDecorationTheme(
      filled:true,fillColor:Color(0xFFF3F3F3),
      border:OutlineInputBorder(borderSide:BorderSide.none,borderRadius:BorderRadius.all(Radius.circular(2))),
    ),
  );
}
