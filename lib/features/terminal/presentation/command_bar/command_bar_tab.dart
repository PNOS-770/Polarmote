import 'package:flutter/material.dart';
import 'command_bar_models.dart';
import '../../../../shared/design_system/theme/app_colors.dart';

/// 命令栏 Tab（单个分组按钮）
class CommandBarTab extends StatefulWidget {
  final CommandBarSection section;
  final bool isExpanded;
  final VoidCallback onTap;

  const CommandBarTab({
    super.key,
    required this.section,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  State<CommandBarTab> createState() => _CommandBarTabState();
}

class _CommandBarTabState extends State<CommandBarTab> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.isExpanded
        ? AppColors.primary
        : _isHovered
            ? AppColors.primary.withValues(alpha: 0.7)
            : AppColors.textSecondary;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: InkWell(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isHovered ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),  // 减小 padding
            decoration: BoxDecoration(
              border: widget.isExpanded
                  ? Border(
                      bottom: BorderSide(
                        color: AppColors.primary,
                        width: 2,
                      ),
                    )
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.section.icon,
                  size: 14,  // 16 → 14
                  color: color,
                ),
                const SizedBox(width: 5),  // 6 → 5
                Text(
                  widget.section.title,
                  style: TextStyle(
                    fontSize: 12,  // 13 → 12
                    fontWeight: widget.isExpanded ? FontWeight.w600 : FontWeight.w500,
                    color: color,
                  ),
                ),
                const SizedBox(width: 3),  // 4 → 3
                Icon(
                  widget.isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  size: 13,  // 14 → 13
                  color: color,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

