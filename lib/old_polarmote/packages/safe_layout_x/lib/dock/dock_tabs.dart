import 'package:flutter/material.dart';

import '../panel/panel_registry.dart';
import 'dock_node.dart';

class DockTabs extends StatelessWidget {
  const DockTabs({
    super.key,
    required this.node,
    required this.registry,
    required this.onSelect,
  });

  final TabNode node;
  final PanelRegistry registry;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    if (node.tabs.isEmpty) {
      return const SizedBox.shrink();
    }
    final activeIndex = node.activeIndex.clamp(0, node.tabs.length - 1);
    final active = node.tabs[activeIndex];
    final panel = registry.resolve(active.panelId);
    if (panel == null) return const SizedBox.shrink();

    return Column(
      children: [
        Container(
          height: 36,
          color: const Color(0xFFF5F5F5),
          child: Row(
            children: [
              for (var index = 0; index < node.tabs.length; index++)
                _TabButton(
                  label:
                      registry.resolve(node.tabs[index].panelId)?.title ??
                      node.tabs[index].panelId,
                  active: index == activeIndex,
                  onTap: () => onSelect(index),
                ),
            ],
          ),
        ),
        Expanded(child: panel.buildPanel(context)),
      ],
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? const Color(0xFF1976D2) : const Color(0x00000000),
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
