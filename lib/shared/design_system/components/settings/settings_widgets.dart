import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_spacing.dart';

/// 设置项开关行
class SettingSwitchRow extends StatelessWidget {
  const SettingSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      title: Text(
        title,
        style: AppTextStyles.body,
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            )
          : null,
      value: value,
      onChanged: onChanged,
    );
  }
}

/// 设置项操作行（带更多按钮）
class SettingActionRow extends StatelessWidget {
  const SettingActionRow({
    super.key,
    required this.title,
    required this.value,
    required this.onMoreTapDown,
    this.subtitle,
  });

  final String title;
  final String value;
  final String? subtitle;
  final void Function(TapDownDetails) onMoreTapDown;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTapDown: onMoreTapDown,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.body,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              value,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Icon(
              Icons.arrow_drop_down,
              size: 20,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

/// 设置区段标题
class SectionTitle extends StatelessWidget {
  const SectionTitle({
    super.key,
    required this.label,
    this.padding,
  });

  final String label;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ??
          const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.sm,
          ),
      child: Text(
        label,
        style: AppTextStyles.h5.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 可选择的卡片（用于单选或多选）
class ChoiceCard extends StatelessWidget {
  const ChoiceCard({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final Widget? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected ? AppColors.primary : AppColors.border;
    final background = selected ? AppColors.grey50 : AppColors.cardBackground;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor, width: selected ? 2 : 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              icon!,
              const SizedBox(width: AppSpacing.xs),
            ],
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: selected ? AppColors.primary : AppColors.textPrimary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

