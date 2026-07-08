import 'package:flutter/material.dart';
import '../../../../shared/design_system/design_system.dart';

/// 模态面板的基础框架
/// 提供统一的布局、动画和交互体验
class ModalPanelBase extends StatelessWidget {
  const ModalPanelBase({
    super.key,
    required this.title,
    required this.child,
    this.width = 600,
    this.height = 500,
    this.actions = const [],
    this.onClose,
  });

  final String title;
  final Widget child;
  final double width;
  final double height;
  final List<Widget> actions;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final responsiveWidth = width > 0 ? width : screenSize.width * 0.9;
    final responsiveHeight = height > 0 ? height : screenSize.height * 0.85;
    final clampedWidth = responsiveWidth.clamp(320.0, screenSize.width * 0.95);
    final clampedHeight = responsiveHeight.clamp(240.0, screenSize.height * 0.9);
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: clampedWidth,
          height: clampedHeight,
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      child: Row(
        children: [
          Text(
            title,
            style: AppTextStyles.h4,
          ),
          const Spacer(),
          ...actions,
          if (actions.isNotEmpty) const SizedBox(width: AppSpacing.sm),
          IconButton(
            icon: const Icon(Icons.close),
            iconSize: 20,
            onPressed: onClose ?? () => Navigator.of(context).pop(),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  /// 显示模态面板
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required Widget child,
    double width = 600,
    double height = 500,
    List<Widget> actions = const [],
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: Colors.black54,
      builder: (context) => ModalPanelBase(
        title: title,
        width: width,
        height: height,
        actions: actions,
        child: child,
      ),
    );
  }
}

