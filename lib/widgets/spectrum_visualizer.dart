import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/audio_player_service.dart';

class SpectrumVisualizer extends StatefulWidget {
  final bool isPlaying;
  final int barCount;
  final double height;

  const SpectrumVisualizer({
    super.key,
    required this.isPlaying,
    this.barCount = 36,
    this.height = 36,
  });

  @override
  State<SpectrumVisualizer> createState() => _SpectrumVisualizerState();
}

class _SpectrumVisualizerState extends State<SpectrumVisualizer> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  List<double> _barHeights = [];
  double _phase = 0.0;

  @override
  void initState() {
    super.initState();
    _barHeights = List.filled(widget.barCount, 0.08);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..addListener(_onTick);

    if (widget.isPlaying) {
      _controller.repeat();
      _requestLiveSpectrum();
    }
  }

  void _requestLiveSpectrum() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final audioService = Provider.of<AudioPlayerService>(context, listen: false);
      audioService.spectrum.ensureLive();
    });
  }

  @override
  void didUpdateWidget(SpectrumVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.barCount != oldWidget.barCount) {
      _barHeights = List.filled(widget.barCount, 0.08);
    }
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _controller.repeat();
        _requestLiveSpectrum();
      } else {
        // No detenemos de golpe: dejamos que el decay baje suavemente a cero
      }
    }
  }

  void _onTick() {
    if (!mounted) return;
    final audioService = Provider.of<AudioPlayerService>(context, listen: false);
    final Float32List? realLevels = widget.isPlaying ? audioService.spectrum.currentLevels() : null;

    _phase += 0.08;
    if (_phase > 2 * pi) _phase -= 2 * pi;

    bool anyActive = false;

    for (int i = 0; i < widget.barCount; i++) {
      double target = 0.06;

      if (widget.isPlaying) {
        if (realLevels != null && realLevels.isNotEmpty) {
          // Mapear el índice de la barra al rango de frecuencias del espectro real
          // Usamos curva logarítmica/perceptual para dar más espacio a bajos y medios
          final norm = i / (widget.barCount - 1).clamp(1, 999);
          final bandIndex = (pow(norm, 1.25) * (realLevels.length - 1)).clamp(0, realLevels.length - 1).toInt();
          target = realLevels[bandIndex].toDouble().clamp(0.06, 1.0);
        } else {
          // Fallback dinámico si aún no hay datos del decodificador/micrófono
          final wave1 = sin(_phase * 2.5 + i * 0.45).abs();
          final wave2 = cos(_phase * 4.2 + i * 1.1).abs();
          final envelope = sin((i / (widget.barCount - 1)) * pi);
          target = ((wave1 * 0.5 + wave2 * 0.5) * (0.35 + 0.65 * envelope)).clamp(0.08, 0.95);
        }
      }

      // Física de audio profesional: Ataque rápido (reacciona al instante a los golpes de batería y notas)
      // y caída suave (decay / release)
      if (target > _barHeights[i]) {
        _barHeights[i] = _barHeights[i] * 0.35 + target * 0.65;
      } else {
        _barHeights[i] = _barHeights[i] * 0.86 + target * 0.14;
      }

      if (_barHeights[i] > 0.07) anyActive = true;
    }

    if (!widget.isPlaying && !anyActive && _controller.isAnimating) {
      _controller.stop();
    }

    setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onTick);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: CustomPaint(
        size: Size.infinite,
        painter: _SpectrumPainter(
          heights: _barHeights,
          isPlaying: widget.isPlaying,
        ),
      ),
    );
  }
}

class _SpectrumPainter extends CustomPainter {
  final List<double> heights;
  final bool isPlaying;

  _SpectrumPainter({
    required this.heights,
    required this.isPlaying,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (heights.isEmpty) return;

    final int count = heights.length;
    final double spacing = 2.5;
    final double totalSpacing = spacing * (count - 1);
    final double barWidth = ((size.width - totalSpacing) / count).clamp(2.5, 6.0);
    final double actualWidth = (count * barWidth) + totalSpacing;
    final double startX = (size.width - actualWidth) / 2;

    for (int i = 0; i < count; i++) {
      final double x = startX + i * (barWidth + spacing);
      final double normalizedHeight = heights[i].clamp(0.08, 1.0);
      final double barH = (size.height * normalizedHeight).clamp(4.0, size.height);
      final double y = size.height - barH;

      final Rect rect = Rect.fromLTWH(x, y, barWidth, barH);
      final RRect rrect = RRect.fromRectAndRadius(rect, const Radius.circular(3));

      // Barras del espectro en color blanco puro con brillo sutil
      const Color baseColor = Colors.white;
      final Paint paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            baseColor.withOpacity(0.65),
            baseColor,
          ],
        ).createShader(rect);

      // Sombra de brillo blanco sutil cuando hay volumen activo
      if (isPlaying && heights[i] > 0.15) {
        final Paint glowPaint = Paint()
          ..color = baseColor.withOpacity((heights[i] * 0.35).clamp(0.08, 0.40))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
        canvas.drawRRect(rrect, glowPaint);
      }

      canvas.drawRRect(rrect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SpectrumPainter oldDelegate) => true;
}
