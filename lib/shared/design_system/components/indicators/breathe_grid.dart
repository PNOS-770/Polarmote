import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class BreatheGrid extends StatefulWidget {
  const BreatheGrid({
    super.key,
    this.color = AppColors.grey400,
    this.lightColor = AppColors.grey200,
    this.cellSize = 16,
    this.spacing = 3,
    this.duration = const Duration(milliseconds: 3000),
  });

  final Color color;
  final Color lightColor;
  final double cellSize;
  final double spacing;
  final Duration duration;

  @override
  State<BreatheGrid> createState() => _BreatheGridState();
}

class _BreatheGridState extends State<BreatheGrid>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: widget.duration, vsync: this);
    _controller.repeat();
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
        return CustomPaint(
          painter: _BreatheGridPainter(
            color: widget.color,
            lightColor: widget.lightColor,
            cellSize: widget.cellSize,
            spacing: widget.spacing,
            progress: _controller.value,
          ),
        );
      },
    );
  }
}

class _BreatheGridPainter extends CustomPainter {
  _BreatheGridPainter({
    required this.color,
    required this.lightColor,
    required this.cellSize,
    required this.spacing,
    required this.progress,
  });

  final Color color;
  final Color lightColor;
  final double cellSize;
  final double spacing;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final step = cellSize + spacing;
    final columns = (size.width / step).ceil() + 1;
    final rows = (size.height / step).ceil() + 1;

    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < columns; col++) {
        final x = col * step;
        final y = row * step;

        final phase = col * 0.15;
        final t = (progress + phase) % 1.0;
        final a = t < 0.5 ? t * 2 : (1.0 - t) * 2;

        final alpha = 0.15 + a * 0.55;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, cellSize, cellSize),
            const Radius.circular(2),
          ),
          Paint()
            ..color = Color.fromARGB(
              (alpha * 255).round().clamp(0, 255),
              (color.r * 255).round().clamp(0, 255),
              (color.g * 255).round().clamp(0, 255),
              (color.b * 255).round().clamp(0, 255),
            ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BreatheGridPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

