import 'package:flutter/widgets.dart';

import '../panel/panel_registry.dart';
import 'dock_manager.dart';
import 'dock_node.dart';
import 'dock_tabs.dart';

class SplitView extends StatelessWidget {
  const SplitView({
    super.key,
    required this.node,
    required this.registry,
    required this.manager,
  });

  final DockNode node;
  final PanelRegistry registry;
  final DockManager manager;

  @override
  Widget build(BuildContext context) {
    return _buildNode(node);
  }

  Widget _buildNode(DockNode current) {
    switch (current) {
      case SplitNode split:
        final firstFlex = (split.ratio * 1000).round().clamp(1, 999);
        final secondFlex = 1000 - firstFlex;
        return Flex(
          direction: split.direction,
          children: [
            Expanded(flex: firstFlex, child: _buildNode(split.first)),
            _divider(split.direction),
            Expanded(flex: secondFlex, child: _buildNode(split.second)),
          ],
        );
      case TabNode tab:
        return DockTabs(
          node: tab,
          registry: registry,
          onSelect: (index) => manager.activateTab(tab, index),
        );
      case PanelNode panelNode:
        final panel = registry.resolve(panelNode.panelId);
        return Builder(
          builder: (context) {
            return panel?.buildPanel(context) ?? const SizedBox.shrink();
          },
        );
    }
  }

  Widget _divider(Axis direction) {
    return SizedBox(
      width: direction == Axis.horizontal ? 1 : null,
      height: direction == Axis.vertical ? 1 : null,
    );
  }
}
