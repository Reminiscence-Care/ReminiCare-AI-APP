import 'package:flutter/material.dart';

abstract final class ReminiCareTheme {
  static const yellow = Color(0xFFFFE14A);
  static const paleYellow = Color(0xFFFFF8D6);
  static const languagePill = Color(0xFFEBEBEB);
  static const ink = Color(0xFF202020);
  static const muted = Color(0xFF707070);

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: Colors.white,
    colorScheme: ColorScheme.fromSeed(
      seedColor: yellow,
      primary: ink,
      surface: Colors.white,
    ),
    fontFamily: 'Inter',
    textTheme: const TextTheme(
      displayLarge: TextStyle(fontSize: 64, height: 1.16, color: ink),
      headlineLarge: TextStyle(fontSize: 48, height: 1.2, color: ink),
      bodyLarge: TextStyle(fontSize: 32, height: 1.45, color: ink),
    ),
  );
}

abstract final class ReminiCareBreakpoints {
  static const phone = 600.0;
  static const tablet = 900.0;

  static bool isPhone(BuildContext context) =>
      MediaQuery.sizeOf(context).width < phone;

  static double titleSize(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < phone) return 34;
    if (width < tablet) return 46;
    return 64;
  }

  static double actionSize(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < phone) return 24;
    if (width < tablet) return 34;
    return 48;
  }

  static double bodySize(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < phone) return 21;
    if (width < tablet) return 27;
    return 34;
  }
}
