import 'package:flutter/material.dart';

/// 应用颜色系统
/// 集中管理所有颜色定义，保持视觉一致性
class AppColors {
  AppColors._();

  // ============ 主色系 ============
  
  /// 主色 - 蓝色
  static const primary = Color(0xFF1F2937);
  static const primaryLight = Color(0xFF60A5FA);
  static const primaryDark = Color(0xFF2563EB);
  
  /// 强调色
  static const accent = Color(0xFF0078D4);

  // ============ 功能色 ============
  
  /// 成功 - 绿色
  static const success = Color(0xFF10B981);
  static const successLight = Color(0xFF34D399);
  static const successDark = Color(0xFF059669);
  static const successSoft = Color(0xFF6EE7B7); // 柔和绿（用于动画等）
  
  /// 警告 - 橙色
  static const warning = Color(0xFFF59E0B);
  static const warningLight = Color(0xFFFBBF24);
  static const warningDark = Color(0xFFD97706);
  
  /// 错误 - 红色
  static const error = Color(0xFFEF4444);
  static const errorLight = Color(0xFFFCA5A5);
  static const errorDark = Color(0xFFDC2626);
  
  /// 信息 - 蓝色
  static const info = Color(0xFF3B82F6);

  /// 搜索高亮 - 红色
  static const searchHighlight = Color(0xFFD32F2F);

  // ============ 中性色 ============
  
  /// 文字颜色
  static const textPrimary = Color(0xFF1F2937);
  static const textSecondary = Color(0xFF6B7280);
  static const textTertiary = Color(0xFF9CA3AF);
  static const textDisabled = Color(0xFFD1D5DB);
  
  /// 边框
  static const border = Color(0xFFE5E7EB);
  static const borderLight = Color(0xFFF3F4F6);
  static const borderDark = Color(0xFFD1D5DB);
  
  /// 背景
  static const background = Color(0xFFFFFFFF);
  static const backgroundGrey = Color(0xFFF9FAFB);
  static const backgroundDark = Color(0xFFF3F4F6);
  
  /// 卡片
  static const cardBackground = Color(0xFFFFFFFF);
  static const cardHover = Color(0xFFF9FAFB);
  
  /// 灰度
  static const grey50 = Color(0xFFF9FAFB);
  static const grey100 = Color(0xFFF3F4F6);
  static const grey200 = Color(0xFFE5E7EB);
  static const grey300 = Color(0xFFD1D5DB);
  static const grey400 = Color(0xFF9CA3AF);
  static const grey500 = Color(0xFF6B7280);
  static const grey600 = Color(0xFF4B5563);
  static const grey700 = Color(0xFF374151);
  static const grey800 = Color(0xFF1F2937);
  static const grey900 = Color(0xFF111827);

  // ============ 语义化颜色 ============
  
  /// 在线状态
  static const online = success;
  
  /// 离线状态
  static const offline = grey400;
  
  /// 连接中状态
  static const connecting = warning;
  
  /// 终端背景（深色）
  static const terminalBackground = Color(0xFF1E1E1E);

  /// 终端树背景（更深）
  static const terminalTreeBackground = Color(0xFF111111);

  /// 终端树文件夹行背景（展开时）
  static const terminalTreeFolderBg = Color(0xFF191919);

  /// 终端树搜索输入框背景
  static const terminalTreeInputBg = Color(0xFF1A1A1A);

  /// 终端树已连接主机行背景
  static const terminalTreeConnectedBg = Color(0xFF183E2C);

  /// 终端树悬停背景
  static const terminalTreeHover = Color(0xFF2A2A2A);

  /// 终端树图标/箭头色 (Colors.white54)
  static const terminalTreeIcon = Color(0x8AFFFFFF);

  /// 终端树次要色 (Colors.white38)
  static const terminalTreeMuted = Color(0x61FFFFFF);

  /// 终端树文本主色 (Colors.white70)
  static const terminalTreeText = Color(0xB3FFFFFF);
  
  /// 终端前景（浅色）
  static const terminalForeground = Color(0xFFCCCCCC);

  // ============ 透明度变体 ============
  
  /// 覆盖层
  static const overlay = Color(0x80000000); // 50% 黑色
  static const overlayLight = Color(0x40000000); // 25% 黑色
  
  /// 分隔线
  static const divider = Color(0xFFE5E7EB);

  // ============ 图表颜色 ============
  
  /// CPU 颜色
  static const chartCpu = error;
  
  /// 内存颜色
  static const chartMemory = success;
  
  /// 磁盘颜色
  static const chartDisk = warning;
  
  /// 网络颜色
  static const chartNetwork = info;
  
  /// 图表系列色
  static const chartSeries1 = Color(0xFF3B82F6);
  static const chartSeries2 = Color(0xFFEF4444);
  static const chartSeries3 = Color(0xFF10B981);
  static const chartSeries4 = Color(0xFFF59E0B);
  static const chartSeries5 = Color(0xFF8B5CF6);
  
  // ============ 性能限流颜色 ============
  
  /// 限流级别 - 正常（绿色）
  static const throttleNormal = success;
  static const throttleNormalLight = successLight;
  static const throttleNormalBg = Color(0xFFD1FAE5); // 浅绿背景
  
  /// 限流级别 - 中等压力（黄色）
  static const throttleModerate = Color(0xFFFBBF24);
  static const throttleModerateBg = Color(0xFFFEF3C7); // 浅黄背景
  
  /// 限流级别 - 高压力（橙色）
  static const throttleHigh = warning;
  static const throttleHighBg = Color(0xFFFED7AA); // 浅橙背景
  
  /// 限流级别 - 严重压力（红色）
  static const throttleCritical = error;
  static const throttleCriticalBg = Color(0xFFFEE2E2); // 浅红背景
}


