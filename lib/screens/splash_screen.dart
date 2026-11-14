import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/audio_player_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../widgets/glass_container.dart';
import 'main_shell.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _progressController;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..forward();

    // Escanear y refrescar la biblioteca automáticamente mientras se muestra la pantalla inicial
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Provider.of<AudioPlayerService>(context, listen: false).scanLocalLibrary();
      }
    });

    Timer(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const MainShell(),
            transitionsBuilder: (_, animation, __, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        // 75% negro puro (#000000) y 25% blanco plateado suave (#D8DCE6 / #8E96A4)
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.0, -0.15),
            radius: 0.72,
            colors: [
              Color(0x38E2E6EE), // Resplandor blanco plateado (25% de presencia)
              Color(0x14949CA8), // Transición plateado opaco
              Color(0xFF000000), // 75% Negro profundo dominante
            ],
            stops: [0.0, 0.35, 0.75],
          ),
        ),
        child: Stack(
          children: [
            // Sutil destello plateado superior
            Positioned(
              top: -90,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 240,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFE2E6EE).withOpacity(0.14),
                        blurRadius: 110,
                        spreadRadius: 15,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Contenido Central
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Tarjeta del Logo en Negro y Blanco Plateado
                    GlassContainer(
                      blur: 32,
                      opacity: 0.12,
                      borderRadius: BorderRadius.circular(32),
                      padding: const EdgeInsets.all(30),
                      child: Container(
                        width: 82,
                        height: 82,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF0A0B0E),
                          border: Border.all(
                            color: const Color(0xFFE2E6EE).withOpacity(0.45),
                            width: 1.4,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFE2E6EE).withOpacity(0.22),
                              blurRadius: 24,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.music_note_rounded,
                          color: Color(0xFFF2F4F8),
                          size: 46,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Nombre de la App en Blanco Plateado
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [
                          Color(0xFFFFFFFF),
                          Color(0xFFD8DCE6),
                          Color(0xFF949CA8),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ).createShader(bounds),
                      child: Text(
                        'Vibe App',
                        style: AppTypography.displayLg.copyWith(
                          color: Colors.white,
                          letterSpacing: -1,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Subtítulo en Plateado Opaco
                    Text(
                      'Experiencia de audio de alta fidelidad.',
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),

            // Indicador de Carga Inferior
            Positioned(
              bottom: 48,
              left: 32,
              right: 32,
              child: Column(
                children: [
                  AnimatedBuilder(
                    animation: _progressController,
                    builder: (context, child) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: _progressController.value,
                          backgroundColor: const Color(0xFF16181E),
                          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFE2E6EE)),
                          minHeight: 2.5,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'SINCRONIZANDO BIBLIOTECA',
                        style: AppTypography.labelCaps.copyWith(
                          letterSpacing: 2.0,
                          color: AppColors.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Row(
                        children: List.generate(3, (i) {
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 1.5),
                            width: 4,
                            height: 4,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFFE2E6EE),
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

