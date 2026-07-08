import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// 高级活动指示器 - 带明显呼吸动效的徽章
/// 用于导航栏按钮，显示活跃任务数量
class ActivityBadge extends StatefulWidget {
  const ActivityBadge({
    super.key,
    required this.icon,
    required this.count,
    required this.active,
    required this.color,
    this.size = 24,
    this.badgeColor = AppColors.error,
  });

  final IconData icon;
  final int count;
  final bool active;
  final Color color;
  final double size;
  final Color badgeColor;

  @override
  State<ActivityBadge> createState() => _ActivityBadgeState();
}

class _ActivityBadgeState extends State<ActivityBadge> {
  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        // 主图标（不移动）
        Icon(widget.icon, size: widget.size, color: widget.color),
        
        // 徽章（简单显示，不呼吸）
        if (widget.active && widget.count > 0)
          Positioned(
            right: -8,
            top: -6,
            child: _SimpleBadge(
              count: widget.count,
              color: widget.badgeColor,
            ),
          ),
      ],
    );
  }
}

/// 简单徽章 - 无动效
class _SimpleBadge extends StatelessWidget {
  const _SimpleBadge({
    required this.count,
    required this.color,
  });

  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = count > 99 ? '99+' : '$count';
    
    return Container(
      constraints: const BoxConstraints(
        minWidth: 16,
        minHeight: 16,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}

/// 小方格呼吸指示器 - 可单独使用
/// 5个小方格，波浪呼吸效果，更高级的视觉呈现
class SquareBreathIndicator extends StatefulWidget {
  const SquareBreathIndicator({
    super.key,
    this.color = AppColors.success,
    this.lightColor = AppColors.successSoft,
    this.duration = const Duration(milliseconds: 1800),
    this.squareCount = 5,
    this.squareSize = 4.0,
    this.spacing = 2.0,
    this.breathIntensity = 0.7,
  });

  final Color color;
  final Color lightColor;
  final Duration duration;
  final int squareCount;
  final double squareSize;
  final double spacing;
  final double breathIntensity;

  @override
  State<SquareBreathIndicator> createState() => _SquareBreathIndicatorState();
}

class _SquareBreathIndicatorState extends State<SquareBreathIndicator> with SingleTickerProviderStateMixin {
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
          children: List.generate(widget.squareCount, (index) {
            final opacity = _calculateSquareOpacity(index, _controller.value);
            final scale = 1 + (widget.breathIntensity * 0.3 * opacity);
            
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: widget.spacing / 2),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: widget.squareSize,
                  height: widget.squareSize * 1.8,
                  decoration: BoxDecoration(
                    color: Color.lerp(
                      widget.lightColor.withValues(alpha: 0.25),
                      widget.color,
                      opacity,
                    ),
                    borderRadius: BorderRadius.circular(1.5),
                    boxShadow: opacity > 0.5
                        ? [
                            BoxShadow(
                              color: widget.color.withValues(alpha: 0.3 * opacity),
                              blurRadius: 3,
                              spreadRadius: 0.5,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  double _calculateSquareOpacity(int index, double progress) {
    final centerIndex = (widget.squareCount - 1) / 2;
    final distanceFromCenter = (index - centerIndex).abs();
    
    // 波浪相位偏移
    final phaseOffset = distanceFromCenter * 0.12;
    final adjustedProgress = (progress + phaseOffset) % 1.0;
    
    // 平滑呼吸曲线（正弦波）
    return (1 + math.sin(adjustedProgress * 2 * math.pi)) / 2;
  }
}

/// 圆形脉冲指示器 - 更现代的视觉效果
class CirclePulseIndicator extends StatefulWidget {
  const CirclePulseIndicator({
    super.key,
    this.color = AppColors.primary,
    this.size = 12.0,
    this.duration = const Duration(milliseconds: 1500),
  });

  final Color color;
  final double size;
  final Duration duration;

  @override
  State<CirclePulseIndicator> createState() => _CirclePulseIndicatorState();
}

class _CirclePulseIndicatorState extends State<CirclePulseIndicator> with SingleTickerProviderStateMixin {
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
        final breathe = 0.5 - (0.5 - _controller.value).abs() * 2;
        
        return Stack(
          alignment: Alignment.center,
          children: [
            // 外圈脉冲
            Container(
              width: widget.size * (1.5 + breathe * 0.8),
              height: widget.size * (1.5 + breathe * 0.8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: widget.color.withValues(alpha: 0.3 * (1 - breathe)),
                  width: 2,
                ),
              ),
            ),
            // 内圈
            Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color,
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.5),
                    blurRadius: 4 + breathe * 4,
                    spreadRadius: breathe * 2,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

