import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class LoginAnimationScreen extends StatefulWidget {
  const LoginAnimationScreen({super.key});

  @override
  State<LoginAnimationScreen> createState() => _LoginAnimationScreenState();
}

class _LoginAnimationScreenState extends State<LoginAnimationScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoController;
  late AnimationController _backgroundController;

  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _glowOpacity;

  Timer? _navigationTimer;

  @override
  void initState() {
    super.initState();

    // ============================================================
    // LOGIN ANIMATION SCREEN OPENED
    // ============================================================

    debugPrint('==============================================');
    debugPrint('LOGIN ANIMATION SCREEN OPENED');
    debugPrint('==============================================');

    try {
      // ============================================================
      // LOGO ANIMATION CONTROLLER
      // ============================================================

      _logoController = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 5),
      );

      // ============================================================
      // LOGO SCALE
      // ============================================================

      _logoScale = Tween<double>(begin: 0.4, end: 1.0).animate(
        CurvedAnimation(parent: _logoController, curve: Curves.easeOutBack),
      );

      // ============================================================
      // LOGO OPACITY
      // ============================================================

      _logoOpacity = Tween<double>(
        begin: 0.0,
        end: 1.0,
      ).animate(CurvedAnimation(parent: _logoController, curve: Curves.easeIn));

      // ============================================================
      // GLOW OPACITY
      // ============================================================

      _glowOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _logoController, curve: Curves.easeInOut),
      );

      // ============================================================
      // BACKGROUND ANIMATION
      // ============================================================

      _backgroundController = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 4),
      );

      _backgroundController.repeat(reverse: true);

      // ============================================================
      // ANIMATION START
      // ============================================================

      debugPrint('LOGIN ANIMATION STARTED');

      // Start logo animation
      _logoController.forward();

      // ============================================================
      // WAIT FOR 5 SECONDS
      // THEN GO TO DASHBOARD
      // ============================================================

      _navigationTimer = Timer(const Duration(seconds: 5), () {
        if (!mounted) {
          debugPrint('==============================================');
          debugPrint('LOGIN ANIMATION FAILED');
          debugPrint('Animation screen was disposed before completion.');
          debugPrint('==============================================');

          return;
        }

        // ========================================================
        // ANIMATION SUCCESS
        // ========================================================

        debugPrint('==============================================');
        debugPrint('LOGIN ANIMATION SUCCESS');
        debugPrint('LOGIN ANIMATION COMPLETED');
        debugPrint('==============================================');

        // ========================================================
        // GO TO DASHBOARD
        // ========================================================

        debugPrint('GOING TO DASHBOARD...');

        context.go('/dashboard');
      });
    } catch (e, stackTrace) {
      // ============================================================
      // ANIMATION FAILED
      // ============================================================

      debugPrint('==============================================');
      debugPrint('LOGIN ANIMATION FAILED');
      debugPrint('ERROR: $e');
      debugPrint('STACK TRACE:');
      debugPrint('$stackTrace');
      debugPrint('==============================================');
    }
  }

  @override
  void dispose() {
    // Cancel navigation timer
    _navigationTimer?.cancel();

    // Dispose animation controllers
    _logoController.dispose();
    _backgroundController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1020),
      body: AnimatedBuilder(
        animation: _backgroundController,
        builder: (context, child) {
          return Stack(
            children: [
              // ======================================================
              // LEFT PURPLE GLOW
              // ======================================================
              Positioned(
                left: -100 + (_backgroundController.value * 80),
                top: 150,
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF7C4DFF).withValues(alpha: 0.25),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),

              // ======================================================
              // RIGHT PURPLE GLOW
              // ======================================================
              Positioned(
                right: -100 - (_backgroundController.value * 80),
                bottom: 100,
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF9D6BFF).withValues(alpha: 0.20),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),

              // ======================================================
              // MAIN ANIMATION
              // ======================================================
              Center(
                child: AnimatedBuilder(
                  animation: _logoController,
                  builder: (context, child) {
                    return Opacity(
                      opacity: _logoOpacity.value,
                      child: Transform.scale(
                        scale: _logoScale.value,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // ==========================================
                            // LOGO GLOW
                            // ==========================================
                            Container(
                              width: 150,
                              height: 150,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF7C4DFF).withValues(
                                      alpha: 0.35 * _glowOpacity.value,
                                    ),
                                    blurRadius: 70,
                                    spreadRadius: 20,
                                  ),
                                ],
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFF171C35),
                                  border: Border.all(
                                    color: const Color(0xFF7C4DFF),
                                    width: 2,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.music_note_rounded,
                                  size: 70,
                                  color: Color(0xFF9D6BFF),
                                ),
                              ),
                            ),

                            const SizedBox(height: 30),

                            // ==========================================
                            // APP NAME
                            // ==========================================
                            const Text(
                              'MusicVerse Academy',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),

                            const SizedBox(height: 10),

                            // ==========================================
                            // ADMIN PORTAL
                            // ==========================================
                            const Text(
                              'Admin Portal',
                              style: TextStyle(
                                color: Color(0xFFB0B5D3),
                                fontSize: 16,
                                letterSpacing: 1.5,
                              ),
                            ),

                            const SizedBox(height: 35),

                            // ==========================================
                            // LOADING INDICATOR
                            // ==========================================
                            const SizedBox(
                              width: 35,
                              height: 35,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Color(0xFF7C4DFF),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
