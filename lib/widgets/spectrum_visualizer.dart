import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class SpectrumVisualizer extends StatefulWidget {
  final bool isPlaying;
  final int barCount;
  final double height;

  const SpectrumVisualizer({
    super.key,
    required this.isPlaying,
    this.barCount = 32,
    this.height = 60,
  });

  @override
  State<SpectrumVisualizer> createState() => _SpectrumVisualizerState();
}

class _SpectrumVisualizerState extends State<SpectrumVisualizer> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    if (widget.isPlaying) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(SpectrumVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value * 2 * pi;

        return SizedBox(
          height: widget.height,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(widget.barCount, (index) {
              double factor;
              if (widget.isPlaying) {
                // Generar un comportamiento pseudo-aleatorio único para CADA barra usando semillas matemáticas irracionales
                double speed1 = 2.5 + (index % 3) * 1.5;
                double speed2 = 6.0 + (index % 5) * 1.2;
                double speed3 = 14.0 + (index % 7) * 0.8;
                
                double phase1 = index * 0.5;
                double phase2 = index * 1.3;
                double phase3 = index * 2.7;

                // Combinación de 3 ondas a diferentes velocidades para crear ruido suave y desincronizado (smooth noise)
                double wave1 = sin(t * speed1 + phase1).abs();
                double wave2 = cos(t * speed2 + phase2).abs();
                double wave3 = sin(t * speed3 + phase3).abs();

                // Envolvente tipo "campana" para simular EQ real (vocales al centro más altas, bajos y agudos a los lados)
                double envelope = sin((index / (widget.barCount - 1)) * pi);
                
                factor = (wave1 * 0.4 + wave2 * 0.4 + wave3 * 0.2) * (0.3 + 0.7 * envelope);
                factor = factor.clamp(0.08, 1.0);
              } else {
                factor = 0.08;
              }

              double minHeight = 6.0;
              double maxHeight = widget.height;
              double currentHeight = minHeight + (maxHeight - minHeight) * factor;

              // Alternancia neón elegante (Violeta Eléctrico y Cyan)
              Color barColor = (index % 2 == 0) ? AppColors.primary : AppColors.secondary;

              return AnimatedContainer(
                duration: const Duration(milliseconds: 40),
                margin: const EdgeInsets.symmetric(horizontal: 2.0),
                width: 4.5,
                height: currentHeight,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      barColor.withOpacity(0.50),
                      barColor,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: widget.isPlaying
                      ? [
                          BoxShadow(
                            color: barColor.withOpacity(0.45),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ]
                      : [],
                ),
              );
            }),
          ),
        );
      },
    );
  }
}
