import 'package:flutter/material.dart';
import 'command_bar_models.dart';
import '../../../../shared/design_system/theme/app_colors.dart';
import '../../../../shared/design_system/theme/app_shadows.dart';
import '../../../../shared/design_system/theme/app_spacing.dart';

/// 命令栏展开面板
class CommandBarPanel extends StatelessWidget {
  final CommandBarSection section;
  final VoidCallback onClose;

  const CommandBarPanel({
    super.key,
    required this.section,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return SizeTransition(
          sizeFactor: CurvedAnimation(
            parent: AlwaysStoppedAnimation(value),
            curve: Curves.easeOutCubic,
          ),
          child: child,
        );
      },
      child: Container(
        constraints: const BoxConstraints(maxHeight: 150),  // 200 → 150
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          border: Border(
            bottom: BorderSide(
              color: AppColors.border,
              width: 1,
            ),
          ),
          boxShadow: AppShadows.lg,
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(AppSpacing.sm),  // md → sm
          child: Wrap(
            spacing: AppSpacing.xs,  // sm → xs
            runSpacing: AppSpacing.xs,  // sm → xs
            children: section.items.map((item) {
              return _CommandBarItemButton(item: item, onClose: onClose);
            }).toList(),
          ),
        ),
      ),
    );
  }
}

/// 单个命令按钮
class _CommandBarItemButton extends StatefulWidget {
  final CommandBarItem item;
  final VoidCallback onClose;

  const _CommandBarItemButton({
    required this.item,
    required this.onClose,
  });

  @override
  State<_CommandBarItemButton> createState() => _CommandBarItemButtonState();
}

class _CommandBarItemButtonState extends State<_CommandBarItemButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: InkWell(
        onTap: widget.item.enabled
            ? () {
                widget.item.onTap();
                widget.onClose();  // 点击后关闭面板
              }
            : null,
        borderRadius: BorderRadius.circular(6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),  // 12,8 → 10,6
          decoration: BoxDecoration(
            color: _isHovered
                ? AppColors.cardHover
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _isHovered
                  ? AppColors.primary.withValues(alpha: 0.3)
                  : AppColors.border,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.item.icon,
                size: 14,  // 16 → 14
                color: widget.item.enabled
                    ? AppColors.textPrimary
                    : AppColors.textTertiary,
              ),
              const SizedBox(width: 6),  // 8 → 6
              Text(
                widget.item.label,
                style: TextStyle(
                  fontSize: 12,  // 13 → 12
                  color: widget.item.enabled
                      ? AppColors.textPrimary
                      : AppColors.textTertiary,
                ),
              ),
              if (widget.item.shortcut != null) ...[
                const SizedBox(width: 8),  // 12 → 8
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),  // 6,2 → 5,1
                  decoration: BoxDecoration(
                    color: AppColors.border.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    widget.item.shortcut!,
                    style: TextStyle(
                      fontSize: 10,  // 11 → 10
                      color: AppColors.textSecondary,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

