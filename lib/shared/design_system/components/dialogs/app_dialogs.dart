import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../buttons/app_buttons.dart';

/// 确认对话框 - 标准的确认/取消对话框
Future<bool?> showConfirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  String confirmText = 'Confirm',
  String cancelText = 'Cancel',
  bool destructive = false,
  IconData? icon,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.radiusDialog,
      ),
      title: Row(
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              color: destructive ? AppColors.error : AppColors.primary,
              size: 24,
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Text(
              title,
              style: AppTextStyles.h4,
            ),
          ),
        ],
      ),
      content: message != null
          ? Text(
              message,
              style: AppTextStyles.body,
            )
          : null,
      contentPadding: message != null
          ? const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.md,
              AppSpacing.xl,
              AppSpacing.md,
            )
          : EdgeInsets.zero,
      actionsPadding: const EdgeInsets.all(AppSpacing.lg),
      actions: [
        SecondaryButton(
          onPressed: () => Navigator.of(context).pop(false),
          label: cancelText,
          size: ButtonSize.medium,
        ),
        const SizedBox(width: AppSpacing.sm),
        PrimaryButton(
          onPressed: () => Navigator.of(context).pop(true),
          label: confirmText,
          size: ButtonSize.medium,
        ),
      ],
    ),
  );
}

/// 输入对话框 - 带输入框的对话框
Future<String?> showInputDialog(
  BuildContext context, {
  required String title,
  String? message,
  String? hint,
  String? initialValue,
  String confirmText = 'Confirm',
  String cancelText = 'Cancel',
  String? Function(String?)? validator,
  TextInputType? keyboardType,
  int maxLines = 1,
}) {
  final controller = TextEditingController(text: initialValue);
  final formKey = GlobalKey<FormState>();

  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.radiusDialog,
      ),
      title: Text(title, style: AppTextStyles.h4),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message != null) ...[
              Text(message, style: AppTextStyles.body),
              const SizedBox(height: AppSpacing.md),
            ],
            TextFormField(
              controller: controller,
              autofocus: true,
              keyboardType: keyboardType,
              maxLines: maxLines,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: AppTextStyles.hint,
                filled: true,
                fillColor: AppColors.backgroundGrey,
                contentPadding: const EdgeInsets.all(AppSpacing.md),
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
                errorBorder: OutlineInputBorder(
                  borderRadius: AppRadius.radiusInput,
                  borderSide: const BorderSide(color: AppColors.error),
                ),
              ),
              validator: validator,
            ),
          ],
        ),
      ),
      contentPadding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.md,
      ),
      actionsPadding: const EdgeInsets.all(AppSpacing.lg),
      actions: [
        SecondaryButton(
          onPressed: () => Navigator.of(context).pop(),
          label: cancelText,
          size: ButtonSize.medium,
        ),
        const SizedBox(width: AppSpacing.sm),
        PrimaryButton(
          onPressed: () {
            if (formKey.currentState?.validate() ?? false) {
              Navigator.of(context).pop(controller.text);
            }
          },
          label: confirmText,
          size: ButtonSize.medium,
        ),
      ],
    ),
  );
}

/// 加载对话框 - 显示加载中
void showLoadingDialog(
  BuildContext context, {
  String? message,
}) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: AppColors.cardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.radiusDialog,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.lg),
              Text(
                message,
                style: AppTextStyles.body,
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// 消息对话框 - 简单的消息提示
Future<void> showMessageDialog(
  BuildContext context, {
  required String title,
  required String message,
  String buttonText = 'OK',
  IconData? icon,
  Color? iconColor,
}) {
  return showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.radiusDialog,
      ),
      title: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: iconColor ?? AppColors.primary, size: 24),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Text(title, style: AppTextStyles.h4),
          ),
        ],
      ),
      content: Text(message, style: AppTextStyles.body),
      contentPadding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.md,
      ),
      actionsPadding: const EdgeInsets.all(AppSpacing.lg),
      actions: [
        PrimaryButton(
          onPressed: () => Navigator.of(context).pop(),
          label: buttonText,
          size: ButtonSize.medium,
        ),
      ],
    ),
  );
}

