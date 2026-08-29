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
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
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
        return SizedBox(
          height: widget.height,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(widget.barCount, (index) {
              double factor = widget.isPlaying
                  ? sin((_controller.value * 2 * pi) + (index * 0.3)).abs()
                  : 0.15;
              double minHeight = 4.0;
              double maxHeight = widget.height * 0.85;
              double currentHeight = minHeight + (maxHeight - minHeight) * factor;

              Color barColor = AppColors.primary;
              if (index % 3 == 0) {
                barColor = AppColors.secondary;
              } else if (index % 5 == 0) {
                barColor = AppColors.tertiary;
              }

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                width: 3.5,
                height: currentHeight,
                decoration: BoxDecoration(
                  color: barColor.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}
