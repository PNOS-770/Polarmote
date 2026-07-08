import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_text_styles.dart';

class AppDropdownButtonFormField<T> extends StatelessWidget {
  const AppDropdownButtonFormField({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.label,
    this.hint,
  });

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? label;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        hintText: hint,
        labelStyle: AppTextStyles.label,
        hintStyle: AppTextStyles.hint,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: AppRadius.radiusInput,
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.radiusInput,
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.radiusInput,
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        filled: true,
        fillColor: AppColors.background,
      ),
      items: items,
      onChanged: onChanged,
      style: AppTextStyles.body,
      dropdownColor: AppColors.cardBackground,
      icon: Icon(Icons.arrow_drop_down, color: AppColors.grey500),
    );
  }
}

