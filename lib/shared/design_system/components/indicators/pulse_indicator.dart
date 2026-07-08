import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// 脉冲指示器 - 波浪呼吸效果
/// 用于表示"运行中"状态，5个小方块产生波浪动画
class PulseIndicator extends StatefulWidget {
  const PulseIndicator({
    super.key,
    this.color = AppColors.success,
    this.lightColor = AppColors.successSoft,
    this.duration = const Duration(milliseconds: 1500),
    this.dotCount = 5,
    this.dotWidth = 4,
    this.dotHeight = 8,
    this.spacing = 1,
  });

  /// 深色（最亮时的颜色）
  final Color color;
  
  /// 浅色（最暗时的颜色）
  final Color lightColor;
  
  /// 动画周期
  final Duration duration;
  
  /// 方块数量
  final int dotCount;
  
  /// 方块宽度
  final double dotWidth;
  
  /// 方块高度
  final double dotHeight;
  
  /// 方块间距
  final double spacing;

  @override
  State<PulseIndicator> createState() => _PulseIndicatorState();
}

class _PulseIndicatorState extends State<PulseIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
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
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(widget.dotCount, (index) {
            final opacity = _calculateDotOpacity(index, _controller.value);
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: widget.spacing),
              child: Container(
                width: widget.dotWidth,
                height: widget.dotHeight,
                decoration: BoxDecoration(
                  color: Color.lerp(
                    widget.lightColor.withValues(alpha: 0.3),
                    widget.color,
                    opacity,
                  ),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  /// 计算每个方块的不透明度（产生波浪效果）
  /// 中间的方块先亮，向两边扩散
  double _calculateDotOpacity(int index, double progress) {
    final centerIndex = (widget.dotCount - 1) / 2;
    final distanceFromCenter = (index - centerIndex).abs();
    
    // 相位偏移：离中心越远，延迟越大
    final phaseOffset = distanceFromCenter * 0.15;
    final adjustedProgress = (progress + phaseOffset) % 1.0;
    
    // 呼吸效果：0 → 1 → 0
    if (adjustedProgress < 0.5) {
      return adjustedProgress * 2; // 0 → 1
    } else {
      return (1.0 - adjustedProgress) * 2; // 1 → 0
    }
  }
}

