import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_radius.dart';

/// 应用搜索栏
class AppSearchBar extends StatelessWidget {
  const AppSearchBar({
    super.key,
    required this.onChanged,
    this.hint,
    this.controller,
    this.autofocus = false,
    this.prefixIcon,
  });

  final ValueChanged<String> onChanged;
  final String? hint;
  final TextEditingController? controller;
  final bool autofocus;
  final Widget? prefixIcon;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      onChanged: onChanged,
      style: AppTextStyles.body,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppTextStyles.body.copyWith(
          color: AppColors.textTertiary,
        ),
        prefixIcon: prefixIcon ?? Icon(Icons.search, color: AppColors.textSecondary),
        filled: true,
        fillColor: AppColors.backgroundGrey,
        border: OutlineInputBorder(
          borderRadius: AppRadius.radiusInput,
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.radiusInput,
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.radiusInput,
          borderSide: BorderSide(color: AppColors.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
      ),
    );
  }
}

