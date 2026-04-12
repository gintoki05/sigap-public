import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'screens/splash_screen.dart';

void main() {
  runApp(const SigapApp());
}

class SigapApp extends StatelessWidget {
  const SigapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SIGAP',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1d3557),
          primary: const Color(0xFF1d3557),
          secondary: const Color(0xFFe63946),
          surface: const Color(0xFFf8f9fa),
        ),
        scaffoldBackgroundColor: const Color(0xFFf8f9fa),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1d3557),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFe63946),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        useMaterial3: true,
      ),
      home: const SplashScreen(nextScreen: HomeScreen()),
    );
  }
}
