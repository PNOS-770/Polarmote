import 'package:flutter/material.dart';
import 'package:safe_layout_x/safe_layout_x.dart';

/// 创建带活动任务指示的导航按钮
/// 有活动任务时，按钮背景显示横向流光动效
ShellNavItem createAnimatedNavItem({
  required IconData icon,
  required String label,
  required bool selected,
  required VoidCallback onTap,
  Widget Function(BuildContext, bool, Color, double)? iconBuilder,
  bool hasActiveTask = false,
}) {
  return ShellNavItem(
    icon: icon,
    label: label,
    selected: selected,
    onTap: onTap,
    iconBuilder: iconBuilder,
    overlay: hasActiveTask ? const _ShimmerSweep() : null,
  );
}

class _ShimmerSweep extends StatefulWidget {
  const _ShimmerSweep();

  @override
  State<_ShimmerSweep> createState() => _ShimmerSweepState();
}

class _ShimmerSweepState extends State<_ShimmerSweep>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat();
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
          painter: _ShimmerPainter(progress: _controller.value),
        );
      },
    );
  }
}

class _ShimmerPainter extends CustomPainter {
  _ShimmerPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final bandWidth = size.width * 0.3;
    final featherWidth = bandWidth * 0.35;
    final centerX = progress * (size.width + bandWidth) - bandWidth / 2;

    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          const Color(0xFF4CAF50).withValues(alpha: 0),
          const Color(0xFF4CAF50).withValues(alpha: 0.15),
          const Color(0xFF4CAF50).withValues(alpha: 0.15),
          const Color(0xFF4CAF50).withValues(alpha: 0),
        ],
        stops: const [0, 0.35, 0.65, 1],
      ).createShader(Rect.fromLTWH(
        centerX - bandWidth / 2 - featherWidth / 2,
        0,
        bandWidth + featherWidth,
        size.height,
      ));

    canvas.drawRect(
      Rect.fromLTWH(
        centerX - bandWidth / 2 - featherWidth / 2,
        0,
        bandWidth + featherWidth,
        size.height,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(_ShimmerPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

