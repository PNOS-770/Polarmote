import 'package:flutter/material.dart';

/// 应用阴影系统
/// 统一管理所有阴影效果，保持视觉层次一致性
class AppShadows {
  AppShadows._();

  // ============ 基础阴影 ============
  
  /// 无阴影
  static const List<BoxShadow> none = [];
  
  /// 极小阴影 - 悬停提示
  static const List<BoxShadow> xs = [
    BoxShadow(
      color: Color(0x0A000000), // 4% 黑色
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
  ];
  
  /// 小阴影 - 按钮、标签
  static const List<BoxShadow> sm = [
    BoxShadow(
      color: Color(0x14000000), // 8% 黑色
      blurRadius: 4,
      offset: Offset(0, 2),
    ),
  ];
  
  /// 常规阴影 - 卡片
  static const List<BoxShadow> md = [
    BoxShadow(
      color: Color(0x1A000000), // 10% 黑色
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];
  
  /// 中阴影 - 浮动卡片
  static const List<BoxShadow> lg = [
    BoxShadow(
      color: Color(0x1F000000), // 12% 黑色
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];
  
  /// 大阴影 - 对话框
  static const List<BoxShadow> xl = [
    BoxShadow(
      color: Color(0x29000000), // 16% 黑色
      blurRadius: 16,
      offset: Offset(0, 6),
    ),
  ];
  
  /// 超大阴影 - 模态框
  static const List<BoxShadow> xxl = [
    BoxShadow(
      color: Color(0x33000000), // 20% 黑色
      blurRadius: 24,
      offset: Offset(0, 8),
    ),
  ];

  // ============ 语义化阴影 ============
  
  /// 按钮阴影
  static const List<BoxShadow> button = sm;
  
  /// 按钮悬停阴影
  static const List<BoxShadow> buttonHover = md;
  
  /// 卡片阴影
  static const List<BoxShadow> card = md;
  
  /// 卡片悬停阴影
  static const List<BoxShadow> cardHover = lg;
  
  /// 对话框阴影
  static const List<BoxShadow> dialog = xl;
  
  /// 下拉菜单阴影
  static const List<BoxShadow> dropdown = lg;
  
  /// 工具栏阴影
  static const List<BoxShadow> toolbar = xs;

  // ============ 特殊阴影 ============
  
  /// 内阴影效果（需要用 Container + decoration 实现）
  static const List<BoxShadow> inner = [
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 4,
      offset: Offset(0, 2),
      spreadRadius: -2,
    ),
  ];
  
  /// 光晕效果 - 成功
  static const List<BoxShadow> glowSuccess = [
    BoxShadow(
      color: Color(0x4010B981), // 25% 绿色
      blurRadius: 8,
      spreadRadius: 2,
    ),
  ];
  
  /// 光晕效果 - 警告
  static const List<BoxShadow> glowWarning = [
    BoxShadow(
      color: Color(0x40F59E0B), // 25% 橙色
      blurRadius: 8,
      spreadRadius: 2,
    ),
  ];
  
  /// 光晕效果 - 错误
  static const List<BoxShadow> glowError = [
    BoxShadow(
      color: Color(0x40EF4444), // 25% 红色
      blurRadius: 8,
      spreadRadius: 2,
    ),
  ];
  
  /// 光晕效果 - 主色
  static const List<BoxShadow> glowPrimary = [
    BoxShadow(
      color: Color(0x403B82F6), // 25% 蓝色
      blurRadius: 8,
      spreadRadius: 2,
    ),
  ];

  // ============ 动态生成阴影的辅助方法 ============
  
  /// 生成自定义颜色的光晕阴影
  static List<BoxShadow> customGlow(Color color, {double opacity = 0.25, double blur = 8, double spread = 2}) {
    return [
      BoxShadow(
        color: color.withValues(alpha: opacity),
        blurRadius: blur,
        spreadRadius: spread,
      ),
    ];
  }
  
  /// 生成自定义的基础阴影
  static List<BoxShadow> custom({
    Color color = const Color(0x1A000000),
    double blur = 8,
    double offsetY = 2,
    double offsetX = 0,
    double spread = 0,
  }) {
    return [
      BoxShadow(
        color: color,
        blurRadius: blur,
        offset: Offset(offsetX, offsetY),
        spreadRadius: spread,
      ),
    ];
  }
}

