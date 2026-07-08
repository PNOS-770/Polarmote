import 'package:flutter/material.dart';
import 'command_bar_models.dart';
import 'command_bar_tab.dart';
import 'command_bar_panel.dart';
import '../../../../shared/design_system/theme/app_colors.dart';

/// 顶部命令栏（工业软件风格）
class CommandBar extends StatefulWidget {
  final List<CommandBarSection> sections;

  const CommandBar({
    super.key,
    required this.sections,
  });

  @override
  State<CommandBar> createState() => _CommandBarState();
}

class _CommandBarState extends State<CommandBar> {
  String? _expandedSectionId;  // 当前展开的分组 ID

  void _toggleSection(String sectionId) {
    setState(() {
      if (_expandedSectionId == sectionId) {
        // 点击已展开的 Tab → 收起
        _expandedSectionId = null;
      } else {
        // 点击其他 Tab → 切换到该 Tab
        _expandedSectionId = sectionId;
      }
    });
  }

  void _closePanel() {
    setState(() {
      _expandedSectionId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final expandedSection = widget.sections
        .where((s) => s.id == _expandedSectionId)
        .firstOrNull;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 顶部 Tab 栏
        Container(
          height: 32,  // 40px → 32px
          decoration: BoxDecoration(
            color: AppColors.backgroundGrey,
            border: Border(
              bottom: BorderSide(
                color: AppColors.border,
                width: 1,
              ),
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 响应式布局：计算可显示的 Tab 数量
              final maxWidth = constraints.maxWidth;
              final tabWidth = 120.0;  // 每个 Tab 约 120px（减小）
              final maxTabs = (maxWidth / tabWidth).floor();

              List<Widget> tabs;
              if (widget.sections.length <= maxTabs) {
                // 全部显示
                tabs = widget.sections.map((section) {
                  return CommandBarTab(
                    section: section,
                    isExpanded: section.id == _expandedSectionId,
                    onTap: () => _toggleSection(section.id),
                  );
                }).toList();
              } else {
                // 部分显示 + 更多按钮
                final visibleSections = widget.sections.take(maxTabs - 1).toList();
                final hiddenSections = widget.sections.skip(maxTabs - 1).toList();

                tabs = [
                  ...visibleSections.map((section) {
                    return CommandBarTab(
                      section: section,
                      isExpanded: section.id == _expandedSectionId,
                      onTap: () => _toggleSection(section.id),
                    );
                  }),
                  // 更多按钮
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_horiz, size: 16, color: AppColors.textSecondary),
                    tooltip: 'More',
                    itemBuilder: (context) {
                      return hiddenSections.map((section) {
                        return PopupMenuItem<String>(
                          value: section.id,
                          child: Row(
                            children: [
                              Icon(section.icon, size: 16),
                              const SizedBox(width: 8),
                              Text(section.title),
                            ],
                          ),
                        );
                      }).toList();
                    },
                    onSelected: _toggleSection,
                  ),
                ];
              }

              return Row(
                children: tabs,
              );
            },
          ),
        ),

        // 展开的面板
        if (expandedSection != null)
          CommandBarPanel(
            section: expandedSection,
            onClose: _closePanel,
          ),
      ],
    );
  }
}

