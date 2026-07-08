import 'package:flutter/material.dart';
import 'app_colors.dart';

/// 应用文字样式系统
/// 统一管理所有文字样式，保持排版一致性
class AppTextStyles {
  AppTextStyles._();

  // ============ 标题样式 ============
  
  /// H1 - 超大标题
  static const h1 = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    height: 1.2,
  );
  
  /// H2 - 大标题
  static const h2 = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    height: 1.3,
  );
  
  /// H3 - 中标题
  static const h3 = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.4,
  );
  
  /// H4 - 小标题
  static const h4 = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.4,
  );
  
  /// H5 - 次小标题
  static const h5 = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.5,
  );
  
  /// H6 - 最小标题
  static const h6 = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.5,
  );

  // ============ 正文样式 ============
  
  /// 大正文
  static const bodyLarge = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 1.5,
  );
  
  /// 常规正文
  static const body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 1.5,
  );
  
  /// 小正文
  static const bodySmall = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 1.5,
  );

  // ============ 次要文字 ============
  
  /// 次要文字（大）
  static const secondaryLarge = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.5,
  );
  
  /// 次要文字（常规）
  static const secondary = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.5,
  );
  
  /// 次要文字（小）
  static const secondarySmall = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.5,
  );

  // ============ 辅助文字 ============
  
  /// 说明文字
  static const caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.4,
  );
  
  /// 小说明文字
  static const captionSmall = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.4,
  );
  
  /// 提示文字
  static const hint = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textTertiary,
    height: 1.5,
  );

  // ============ 按钮文字 ============
  
  /// 大按钮
  static const buttonLarge = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.25,
  );
  
  /// 常规按钮
  static const button = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.25,
  );
  
  /// 小按钮
  static const buttonSmall = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.25,
  );

  // ============ 标签文字 ============
  
  /// 标签（常规）
  static const label = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
    height: 1.3,
  );
  
  /// 标签（小）
  static const labelSmall = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.3,
  );

  // ============ 特殊样式 ============
  
  /// 代码样式（等宽字体）
  static const code = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    fontFamily: 'monospace',
    color: AppColors.textPrimary,
    height: 1.5,
  );
  
  /// 链接样式
  static const link = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.primary,
    decoration: TextDecoration.underline,
    height: 1.5,
  );
  
  /// 错误提示
  static const error = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.error,
    height: 1.4,
  );
  
  // ============ 终端树样式 ============

  /// 终端树 - 区域标题
  static const terminalTreeHeader = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: Color(0xB3FFFFFF), // Colors.white70
  );

  /// 终端树 - 文件夹名称
  static const terminalTreeFolder = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: Color(0xB3FFFFFF), // Colors.white70
  );

  /// 终端树 - 文件夹计数
  static const terminalTreeFolderCount = TextStyle(
    fontSize: 9,
    fontWeight: FontWeight.w700,
    color: Color(0x61FFFFFF), // Colors.white38
  );

  /// 终端树 - 主机名称
  static const terminalTreeHost = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: Color(0xFFFFFFFF), // Colors.white
  );

  /// 终端树 - 徽章标签
  static const terminalTreeBadge = TextStyle(
    fontSize: 9,
    fontWeight: FontWeight.w700,
  );

  /// 终端树 - 空状态提示
  static const terminalTreeEmpty = TextStyle(
    fontSize: 12,
    color: Color(0x8AFFFFFF), // Colors.white54
  );

  /// 终端树 - 文件夹名称（浅色主题，白色背景用）
  static const terminalTreeFolderLight = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  /// 终端树 - 文件夹计数（浅色主题，白色背景用）
  static const terminalTreeFolderCountLight = TextStyle(
    fontSize: 9,
    fontWeight: FontWeight.w700,
    color: AppColors.grey400,
  );

  /// 成功提示
  static const success = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.success,
    height: 1.4,
  );

  // ============ 数值显示 ============
  
  /// 大数值
  static const numberLarge = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    height: 1.2,
  );
  
  /// 常规数值
  static const number = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.3,
  );
  
  /// 小数值
  static const numberSmall = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.4,
  );

  /// 构建搜索高亮 TextSpan，匹配部分标红加粗
  static TextSpan highlightSpan({
    required String text,
    required String query,
    required TextStyle baseStyle,
    Color? matchColor,
  }) {
    final normalized = query.trim();
    if (normalized.isEmpty) {
      return TextSpan(text: text, style: baseStyle);
    }
    final lowerText = text.toLowerCase();
    final lowerQuery = normalized.toLowerCase();
    final spans = <TextSpan>[];
    var start = 0;
    while (true) {
      final index = lowerText.indexOf(lowerQuery, start);
      if (index < 0) {
        if (start < text.length) {
          spans.add(TextSpan(text: text.substring(start), style: baseStyle));
        }
        break;
      }
      if (index > start) {
        spans.add(
          TextSpan(text: text.substring(start, index), style: baseStyle),
        );
      }
      spans.add(
        TextSpan(
          text: text.substring(index, index + lowerQuery.length),
          style: baseStyle.copyWith(
            color: matchColor ?? AppColors.searchHighlight,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      start = index + lowerQuery.length;
    }
    return TextSpan(children: spans, style: baseStyle);
  }
}

