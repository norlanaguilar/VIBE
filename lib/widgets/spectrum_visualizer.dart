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
                // Frecuencias verticales dinámicas que reaccionan al ritmo
                double bassBeat = sin(t * 4.0 + (index % 4) * 0.8).abs();
                double midRange = cos(t * 7.0 - index * 0.35).abs();
                double treblePeak = sin(t * 11.0 + index * 1.2).abs();

                double envelope = sin((index / widget.barCount) * pi); // Curva cóncava de ecualizador
                factor = ((bassBeat * 0.5) + (midRange * 0.3) + (treblePeak * 0.2)) * (0.4 + 0.6 * envelope);
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
