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
    this.barCount = 36,
    this.height = 32,
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
      duration: const Duration(milliseconds: 800),
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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(widget.barCount, (index) {
              double factor;
              if (widget.isPlaying) {
                // Multi-harmonic audio frequency simulation
                double freq1 = sin(t * 3.0 + index * 0.45);
                double freq2 = cos(t * 5.0 - index * 0.25);
                double freq3 = sin(t * 7.5 + index * 0.85);
                
                // Bass boost curve towards center/sides
                double envelope = 0.5 + 0.5 * sin((index / widget.barCount) * pi);
                
                factor = ((freq1 + freq2 + freq3) / 3.0).abs() * envelope;
                factor = factor.clamp(0.12, 1.0);
              } else {
                factor = 0.12;
              }

              double minHeight = 4.0;
              double maxHeight = widget.height * 0.90;
              double currentHeight = minHeight + (maxHeight - minHeight) * factor;

              Color barColor = AppColors.primary;
              if (index % 4 == 0) {
                barColor = AppColors.secondary;
              } else if (index % 3 == 0) {
                barColor = AppColors.tertiary;
              }

              return AnimatedContainer(
                duration: const Duration(milliseconds: 50),
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                width: 3.5,
                height: currentHeight,
                decoration: BoxDecoration(
                  color: barColor.withOpacity(widget.isPlaying ? 0.90 : 0.40),
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: widget.isPlaying
                      ? [
                          BoxShadow(
                            color: barColor.withOpacity(0.35),
                            blurRadius: 4,
                            spreadRadius: 0.5,
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
