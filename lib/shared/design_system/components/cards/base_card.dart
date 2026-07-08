import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_shadows.dart';

/// 基础卡片 - 统一样式的容器
class BaseCard extends StatelessWidget {
  const BaseCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.color,
    this.shadow = true,
    this.border = false,
    this.borderColor,
    this.onTap,
    this.radius,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final bool shadow;
  final bool border;
  final Color? borderColor;
  final VoidCallback? onTap;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: padding ?? const EdgeInsets.all(AppSpacing.cardPadding),
      margin: margin,
      decoration: BoxDecoration(
        color: color ?? AppColors.cardBackground,
        borderRadius: BorderRadius.circular(radius ?? AppRadius.card),
        boxShadow: shadow ? AppShadows.card : null,
        border: border
            ? Border.all(
                color: borderColor ?? AppColors.border,
                width: 1,
              )
            : null,
      ),
      child: child,
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius ?? AppRadius.card),
        child: content,
      );
    }

    return content;
  }
}

/// 列表卡片 - 带分隔线的卡片
class ListCard extends StatelessWidget {
  const ListCard({
    super.key,
    required this.children,
    this.padding,
    this.margin,
    this.divider = true,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    return BaseCard(
      padding: EdgeInsets.zero,
      margin: margin,
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: padding ?? const EdgeInsets.all(AppSpacing.sm),
        itemCount: children.length,
        separatorBuilder: (context, index) => divider
            ? const Divider(height: 1, color: AppColors.divider)
            : const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) => children[index],
      ),
    );
  }
}

/// 信息卡片 - 带图标和标题的卡片
class InfoCard extends StatelessWidget {
  const InfoCard({
    super.key,
    this.icon,
    this.title,
    required this.child,
    this.padding,
    this.margin,
    this.color,
  });

  final IconData? icon;
  final String? title;
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return BaseCard(
      padding: padding ?? const EdgeInsets.all(AppSpacing.lg),
      margin: margin,
      color: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null || title != null) ...[
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20, color: AppColors.primary),
                  const SizedBox(width: AppSpacing.sm),
                ],
                if (title != null)
                  Expanded(
                    child: Text(
                      title!,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          child,
        ],
      ),
    );
  }
}

