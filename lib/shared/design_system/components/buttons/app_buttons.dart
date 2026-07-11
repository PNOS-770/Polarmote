import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_text_styles.dart';

/// 主按钮 - 用于主要操作
/// 蓝色背景，白色文字，有阴影
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.iconWidget,
    this.loading = false,
    this.fullWidth = false,
    this.size = ButtonSize.medium,
  });

  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;
  final Widget? iconWidget;
  final bool loading;
  final bool fullWidth;
  final ButtonSize size;

  @override
  Widget build(BuildContext context) {
    final isDisabled = onPressed == null || loading;

    return SizedBox(
      width: fullWidth ? double.infinity : null,
      height: size.height,
      child: ElevatedButton(
        onPressed: isDisabled ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.grey300,
          disabledForegroundColor: AppColors.grey500,
          padding: EdgeInsets.symmetric(
            horizontal: size.paddingH,
            vertical: size.paddingV,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.radiusButton,
          ),
          elevation: 0,
          shadowColor: Colors.transparent,
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) {
              return Colors.white.withValues(alpha: 0.1);
            }
            if (states.contains(WidgetState.pressed)) {
              return Colors.white.withValues(alpha: 0.2);
            }
            return null;
          }),
        ),
        child: loading
            ? SizedBox(
                width: size.iconSize,
                height: size.iconSize,
                child: const CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (iconWidget != null)
                    iconWidget!
                  else if (icon != null) ...[
                    Icon(icon, size: size.iconSize),
                    SizedBox(width: size.iconSpacing),
                  ],
                  Text(label, style: size.textStyle),
                ],
              ),
      ),
    );
  }
}

/// 次按钮 - 用于次要操作
/// 白色背景，深色文字，有边框
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.iconWidget,
    this.loading = false,
    this.fullWidth = false,
    this.size = ButtonSize.medium,
  });

  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;
  final Widget? iconWidget;
  final bool loading;
  final bool fullWidth;
  final ButtonSize size;

  @override
  Widget build(BuildContext context) {
    final isDisabled = onPressed == null || loading;

    return SizedBox(
      width: fullWidth ? double.infinity : null,
      height: size.height,
      child: OutlinedButton(
        onPressed: isDisabled ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          disabledForegroundColor: AppColors.grey400,
          padding: EdgeInsets.symmetric(
            horizontal: size.paddingH,
            vertical: size.paddingV,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.radiusButton,
          ),
          side: BorderSide(
            color: isDisabled ? AppColors.grey300 : AppColors.border,
            width: 1,
          ),
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) {
              return AppColors.grey100;
            }
            if (states.contains(WidgetState.pressed)) {
              return AppColors.grey200;
            }
            return null;
          }),
        ),
        child: loading
            ? SizedBox(
                width: size.iconSize,
                height: size.iconSize,
                child: const CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (iconWidget != null)
                    iconWidget!
                  else if (icon != null) ...[
                    Icon(icon, size: size.iconSize),
                    SizedBox(width: size.iconSpacing),
                  ],
                  Text(label, style: size.textStyle),
                ],
              ),
      ),
    );
  }
}

/// 文字按钮 - 用于不重要的操作
/// 透明背景，文字颜色
class AppTextButton extends StatelessWidget {
  const AppTextButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.loading = false,
    this.color = AppColors.primary,
    this.size = ButtonSize.medium,
  });

  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;
  final bool loading;
  final Color color;
  final ButtonSize size;

  @override
  Widget build(BuildContext context) {
    final isDisabled = onPressed == null || loading;

    return SizedBox(
      height: size.height,
      child: TextButton(
        onPressed: isDisabled ? null : onPressed,
        style: TextButton.styleFrom(
          foregroundColor: color,
          disabledForegroundColor: AppColors.grey400,
          padding: EdgeInsets.symmetric(
            horizontal: size.paddingH,
            vertical: size.paddingV,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.radiusButton,
          ),
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) {
              return color.withValues(alpha: 0.08);
            }
            if (states.contains(WidgetState.pressed)) {
              return color.withValues(alpha: 0.12);
            }
            return null;
          }),
        ),
        child: loading
            ? SizedBox(
                width: size.iconSize,
                height: size.iconSize,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: size.iconSize),
                    SizedBox(width: size.iconSpacing),
                  ],
                  Text(label, style: size.textStyle),
                ],
              ),
      ),
    );
  }
}

/// 36px 方型图标按钮，用于顶栏等行内工具栏。
/// 自带悬浮高亮反馈，支持 toggle 状态的动态颜色。
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.iconSize = 18,
    this.color = AppColors.textSecondary,
    this.activeColor,
    this.isActive = false,
    this.tooltip,
    this.width = 36,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final double iconSize;
  final Color color;
  final Color? activeColor;
  final bool isActive;
  final String? tooltip;
  final double width;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = isActive && activeColor != null ? activeColor : color;
    final button = SizedBox(
      width: width,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          hoverColor: AppColors.grey100,
          onTap: onPressed,
          child: Center(
            child: Icon(icon, size: iconSize, color: effectiveColor),
          ),
        ),
      ),
    );
    if (tooltip != null) {
      return Tooltip(
        message: tooltip!,
        waitDuration: const Duration(milliseconds: 250),
        child: button,
      );
    }
    return button;
  }
}

/// Compact icon button for script step editor rows.
class StepIconButton extends StatelessWidget {
  const StepIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
  });

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          hoverColor: AppColors.grey100,
          onTap: onPressed,
          child: Ink(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(icon, size: 18, color: AppColors.textSecondary),
            ),
          ),
        ),
      ),
    );
  }
}

/// 按钮尺寸
enum ButtonSize {
  small(
    height: 32,
    paddingH: 12,
    paddingV: 6,
    iconSize: 14,
    iconSpacing: 6,
    textStyle: AppTextStyles.buttonSmall,
  ),
  medium(
    height: 40,
    paddingH: 16,
    paddingV: 10,
    iconSize: 16,
    iconSpacing: 8,
    textStyle: AppTextStyles.button,
  ),
  large(
    height: 48,
    paddingH: 20,
    paddingV: 12,
    iconSize: 18,
    iconSpacing: 8,
    textStyle: AppTextStyles.buttonLarge,
  );

  const ButtonSize({
    required this.height,
    required this.paddingH,
    required this.paddingV,
    required this.iconSize,
    required this.iconSpacing,
    required this.textStyle,
  });

  final double height;
  final double paddingH;
  final double paddingV;
  final double iconSize;
  final double iconSpacing;
  final TextStyle textStyle;
}

