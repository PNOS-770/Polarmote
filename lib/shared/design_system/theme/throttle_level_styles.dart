import 'package:flutter/material.dart';
import '../../../features/terminal/models/terminal_adaptive_throttle.dart';
import '../theme/app_colors.dart';

/// 限流级别的视觉样式工具类
class ThrottleLevelStyles {
  ThrottleLevelStyles._();

  /// 获取限流级别的颜色
  static Color getColor(ThrottleLevel level) {
    return switch (level) {
      ThrottleLevel.normal => AppColors.throttleNormal,
      ThrottleLevel.moderate => AppColors.throttleModerate,
      ThrottleLevel.high => AppColors.throttleHigh,
      ThrottleLevel.critical => AppColors.throttleCritical,
    };
  }

  /// 获取限流级别的背景颜色
  static Color getBackgroundColor(ThrottleLevel level) {
    return switch (level) {
      ThrottleLevel.normal => AppColors.throttleNormalBg,
      ThrottleLevel.moderate => AppColors.throttleModerateBg,
      ThrottleLevel.high => AppColors.throttleHighBg,
      ThrottleLevel.critical => AppColors.throttleCriticalBg,
    };
  }

  /// 获取限流级别的图标
  static IconData getIcon(ThrottleLevel level) {
    return switch (level) {
      ThrottleLevel.normal => Icons.check_circle,
      ThrottleLevel.moderate => Icons.info,
      ThrottleLevel.high => Icons.warning,
      ThrottleLevel.critical => Icons.error,
    };
  }

  /// 获取限流级别的指示器图标（用于状态栏）
  static IconData getIndicatorIcon(ThrottleLevel level) {
    return switch (level) {
      ThrottleLevel.normal => Icons.speed,
      ThrottleLevel.moderate => Icons.slow_motion_video,
      ThrottleLevel.high => Icons.hourglass_bottom,
      ThrottleLevel.critical => Icons.warning_amber,
    };
  }

  /// 获取限流级别的亮度（用于动画）
  static double getBrightness(ThrottleLevel level) {
    return switch (level) {
      ThrottleLevel.normal => 1.0,
      ThrottleLevel.moderate => 0.85,
      ThrottleLevel.high => 0.7,
      ThrottleLevel.critical => 0.5,
    };
  }

  /// 获取限流级别的优先级（数值越大越严重）
  static int getPriority(ThrottleLevel level) {
    return switch (level) {
      ThrottleLevel.normal => 0,
      ThrottleLevel.moderate => 1,
      ThrottleLevel.high => 2,
      ThrottleLevel.critical => 3,
    };
  }

  /// 判断是否需要显示警告
  static bool shouldShowWarning(ThrottleLevel level) {
    return level == ThrottleLevel.high || level == ThrottleLevel.critical;
  }

  /// 判断是否需要显示通知
  static bool shouldShowNotification(ThrottleLevel oldLevel, ThrottleLevel newLevel) {
    // 升级到 High/Critical 或从 High/Critical 降级时显示通知
    final oldPriority = getPriority(oldLevel);
    final newPriority = getPriority(newLevel);
    
    if (newPriority >= 2 && oldPriority < 2) {
      // 升级到 High 或 Critical
      return true;
    }
    
    if (oldPriority >= 2 && newPriority < 2) {
      // 从 High/Critical 恢复
      return true;
    }
    
    return false;
  }
}

