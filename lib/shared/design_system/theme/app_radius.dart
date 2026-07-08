import 'package:flutter/material.dart';

/// 应用圆角系统
/// 统一管理所有圆角规范，保持视觉一致性
class AppRadius {
  AppRadius._();

  // ============ 基础圆角值 ============
  
  /// 无圆角
  static const double none = 0.0;
  
  /// 极小圆角 - 2px
  static const double xs = 2.0;
  
  /// 小圆角 - 4px
  static const double sm = 4.0;
  
  /// 常规圆角 - 6px
  static const double md = 6.0;
  
  /// 中圆角 - 8px
  static const double lg = 8.0;
  
  /// 大圆角 - 12px
  static const double xl = 12.0;
  
  /// 超大圆角 - 16px
  static const double xxl = 16.0;
  
  /// 极大圆角 - 24px
  static const double xxxl = 24.0;
  
  /// 圆形（用于按钮等）
  static const double circle = 999.0;

  // ============ BorderRadius 对象 ============
  
  static const BorderRadius radiusNone = BorderRadius.zero;
  static const BorderRadius radiusXS = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius radiusSM = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius radiusMD = BorderRadius.all(Radius.circular(md));
  static const BorderRadius radiusLG = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius radiusXL = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius radiusXXL = BorderRadius.all(Radius.circular(xxl));
  static const BorderRadius radiusXXXL = BorderRadius.all(Radius.circular(xxxl));

  // ============ 语义化圆角 ============
  
  /// 按钮圆角
  static const double button = lg;
  static const BorderRadius radiusButton = radiusLG;
  
  /// 卡片圆角
  static const double card = lg;
  static const BorderRadius radiusCard = radiusLG;
  
  /// 输入框圆角
  static const double input = md;
  static const BorderRadius radiusInput = radiusMD;
  
  /// 对话框圆角
  static const double dialog = xl;
  static const BorderRadius radiusDialog = radiusXL;
  
  /// 标签圆角
  static const double badge = sm;
  static const BorderRadius radiusBadge = radiusSM;
  
  /// 芯片圆角
  static const double chip = circle;
  static const BorderRadius radiusChip = BorderRadius.all(Radius.circular(circle));
}

