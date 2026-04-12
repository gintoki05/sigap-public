import 'dart:async';

import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../services/gemma_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    required this.nextScreen,
    this.duration = const Duration(seconds: 2),
  });

  final Widget nextScreen;
  final Duration duration;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _logoScale;
  late final Animation<double> _contentOpacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..forward();

    _logoScale = Tween<double>(
      begin: 0.82,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

    _contentOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.15, 1, curve: Curves.easeOut),
    );

    _initializeApp();
  }

  Future<void> _initializeApp() async {
    final stopwatch = Stopwatch()..start();

    try {
      // Inisialisasi service Gemma sembari splash screen tampil
      // Toleransi maksimal sesuai widget.duration (biasanya 2 detik)
      await GemmaService().initializeReadyModel().timeout(widget.duration);
    } catch (_) {
      // Timeout atau error diabaikan agar tetap bisa lanjut ke HomeScreen
    }

    stopwatch.stop();
    final elapsed = stopwatch.elapsed;
    // Minimal durasi untuk splash screen agar animasi sempat selesai
    const minDuration = Duration(milliseconds: 1400);

    if (elapsed < minDuration) {
      await Future.delayed(minDuration - elapsed);
    }

    _goToNextScreen();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goToNextScreen() {
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, _, _) => widget.nextScreen,
        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF28476F), AppColors.navy, Color(0xFF12253D)],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -80,
              right: -40,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              bottom: -110,
              left: -60,
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  color: AppColors.red.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 32,
                ),
                child: FadeTransition(
                  opacity: _contentOpacity,
                  child: Stack(
                    children: [
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ScaleTransition(
                              scale: _logoScale,
                              child: Container(
                                width: 124,
                                height: 124,
                                padding: const EdgeInsets.all(22),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(32),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.16,
                                      ),
                                      blurRadius: 28,
                                      offset: const Offset(0, 14),
                                    ),
                                  ],
                                ),
                                child: Image.asset(
                                  'assets/logo/logo-sigap-transparant.png',
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                            const SizedBox(height: 28),
                            const Text(
                              'SIGAP',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 4,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Siaga Pertolongan Pertama\nyang tetap siap saat sinyal hilang.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 15,
                                height: 1.6,
                                color: Color(0xFFD9E6F2),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 24),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.12),
                                ),
                              ),
                              child: const Text(
                                'Offline emergency companion',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            ),
                            SizedBox(height: 18),
                            Text(
                              'Menyiapkan panduan pertama yang aman',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFFBED2E7),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
