import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/audio_player_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../widgets/glass_container.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  String _formatDb(double normalizedGain) {
    final db = (normalizedGain - 0.5) * 24.0; // -12.0 dB a +12.0 dB
    if (db.abs() < 0.05) return '0.0 dB';
    final sign = db > 0 ? '+' : '';
    return '$sign${db.toStringAsFixed(1)} dB';
  }

  @override
  Widget build(BuildContext context) {
    final audioService = Provider.of<AudioPlayerService>(context);
    final gains = audioService.equalizerGains;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Barra Superior: Ajustes
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 14.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Ajustes',
                      style: AppTypography.headlineMd.copyWith(
                        color: AppColors.primary,
                        fontSize: 26,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.primaryContainer.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.primary.withOpacity(0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.graphic_eq, color: AppColors.primary, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            audioService.activePreset,
                            style: AppTypography.bodySm.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Ecualizador Profesional de Estudio (Única sección visible en Ajustes)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                child: GlassContainer(
                  borderRadius: BorderRadius.circular(24),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Encabezado del Ecualizador
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Ecualizador Maestro',
                                style: AppTypography.headlineSm.copyWith(
                                  color: Colors.white,
                                  fontSize: 19,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Procesador paramétrico de 5 bandas',
                                style: AppTypography.bodySm.copyWith(
                                  color: AppColors.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          TextButton.icon(
                            onPressed: () => audioService.resetEqualizer(),
                            style: TextButton.styleFrom(
                              backgroundColor: AppColors.surfaceContainerHigh,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            icon: const Icon(Icons.restart_alt, size: 16, color: AppColors.secondary),
                            label: Text(
                              'Restablecer',
                              style: AppTypography.bodySm.copyWith(
                                color: AppColors.secondary,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // Gráfica de Curva de Respuesta de Frecuencia en Tiempo Real
                      Container(
                        height: 140,
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0A0B10),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.08)),
                        ),
                        child: CustomPaint(
                          painter: _EqualizerCurvePainter(gains: gains),
                          size: Size.infinite,
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Selector de Perfiles de Sonido
                      Text(
                        'PERFILES DE SONIDO',
                        style: AppTypography.labelCaps.copyWith(
                          color: AppColors.onSurfaceVariant,
                          fontSize: 11,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: audioService.availablePresets.map((preset) {
                            final isSelected = audioService.activePreset == preset;
                            return Container(
                              margin: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(
                                  preset,
                                  style: TextStyle(
                                    color: isSelected ? Colors.white : AppColors.onSurfaceVariant,
                                    fontSize: 12,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  ),
                                ),
                                selected: isSelected,
                                selectedColor: AppColors.primaryContainer,
                                backgroundColor: AppColors.surfaceContainerHigh,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                onSelected: (_) {
                                  audioService.applyEqualizerPreset(preset);
                                },
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 22),

                      // 5 Faders de Frecuencia con Lectura en dB
                      SizedBox(
                        height: 250,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildProEqBand('60 Hz', 'Sub-Bajos', 0, audioService),
                            _buildProEqBand('230 Hz', 'Graves', 1, audioService),
                            _buildProEqBand('910 Hz', 'Medios', 2, audioService),
                            _buildProEqBand('4 kHz', 'Presencia', 3, audioService),
                            _buildProEqBand('14 kHz', 'Brillo', 4, audioService),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(
              child: SizedBox(height: 100),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProEqBand(String freqLabel, String bandName, int index, AudioPlayerService audioService) {
    final val = audioService.equalizerGains[index];
    final dbText = _formatDb(val);
    final isBoosted = val > 0.52;
    final isCut = val < 0.48;

    return Expanded(
      child: Column(
        children: [
          // Indicador numérico en dB
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              dbText,
              style: AppTypography.monoLabel.copyWith(
                fontSize: 10,
                color: isBoosted
                    ? AppColors.secondary
                    : (isCut ? AppColors.primary : Colors.white70),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Fader vertical con escala graduada
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Marcas de graduación de estudio
                Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(9, (i) {
                    final isCenter = i == 4;
                    return Container(
                      width: isCenter ? 22 : 12,
                      height: isCenter ? 1.5 : 1,
                      color: isCenter
                          ? AppColors.secondary.withOpacity(0.5)
                          : Colors.white.withOpacity(0.12),
                    );
                  }),
                ),
                RotatedBox(
                  quarterTurns: 3,
                  child: SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: AppColors.primary,
                      inactiveTrackColor: AppColors.surfaceContainerHighest,
                      thumbColor: Colors.white,
                      overlayColor: AppColors.primary.withOpacity(0.2),
                      trackHeight: 5,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                    ),
                    child: Slider(
                      value: val,
                      min: 0.0,
                      max: 1.0,
                      onChanged: (newGain) {
                        audioService.setEqualizerGain(index, newGain);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Frecuencia
          Text(
            freqLabel,
            style: AppTypography.monoLabel.copyWith(
              fontSize: 11,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            bandName,
            style: AppTypography.bodySm.copyWith(
              fontSize: 10,
              color: AppColors.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _EqualizerCurvePainter extends CustomPainter {
  final List<double> gains;

  _EqualizerCurvePainter({required this.gains});

  @override
  void paint(Canvas canvas, Size size) {
    if (gains.isEmpty) return;

    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.07)
      ..strokeWidth = 1;

    final zeroLinePaint = Paint()
      ..color = AppColors.secondary.withOpacity(0.3)
      ..strokeWidth = 1;

    // Líneas horizontales (+12dB, +6dB, 0dB, -6dB, -12dB)
    for (int i = 0; i <= 4; i++) {
      final y = (size.height / 4) * i;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        i == 2 ? zeroLinePaint : gridPaint,
      );
    }

    // Puntos de las bandas
    final points = <Offset>[];
    final count = gains.length;
    for (int i = 0; i < count; i++) {
      final x = (size.width / (count - 1)) * i;
      final y = size.height * (1.0 - gains[i].clamp(0.0, 1.0));
      points.add(Offset(x, y));
      // Línea vertical de cada banda
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    // Construir curva suave Bézier cúbica
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final controlX1 = p0.dx + (p1.dx - p0.dx) / 2;
      final controlX2 = p0.dx + (p1.dx - p0.dx) / 2;
      path.cubicTo(controlX1, p0.dy, controlX2, p1.dy, p1.dx, p1.dy);
    }

    // Relleno degradado bajo la curva
    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppColors.primary.withOpacity(0.42),
          AppColors.secondary.withOpacity(0.08),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    // Trazo principal de la curva
    final linePaint = Paint()
      ..shader = const LinearGradient(
        colors: [AppColors.primary, AppColors.secondary],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, linePaint);

    // Nodos brillantes en cada banda
    final dotGlowPaint = Paint()
      ..color = AppColors.secondary.withOpacity(0.45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    final dotPaint = Paint()..color = Colors.white;

    for (final pt in points) {
      canvas.drawCircle(pt, 6, dotGlowPaint);
      canvas.drawCircle(pt, 3.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _EqualizerCurvePainter oldDelegate) => true;
}
