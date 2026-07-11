import 'package:flutter/widgets.dart';

sealed class DockNode {
  const DockNode();

  Map<String, dynamic> toJson();
}

class SplitNode extends DockNode {
  const SplitNode({
    required this.direction,
    required this.ratio,
    required this.first,
    required this.second,
  });

  final Axis direction;
  final double ratio;
  final DockNode first;
  final DockNode second;

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': 'split',
      'direction': direction.name,
      'ratio': ratio,
      'first': first.toJson(),
      'second': second.toJson(),
    };
  }
}

class TabNode extends DockNode {
  const TabNode({required this.tabs, this.activeIndex = 0});

  final List<PanelNode> tabs;
  final int activeIndex;

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': 'tab',
      'tabs': tabs.map((item) => item.toJson()).toList(),
      'activeIndex': activeIndex,
    };
  }
}

class PanelNode extends DockNode {
  const PanelNode({required this.panelId});

  final String panelId;

  @override
  Map<String, dynamic> toJson() {
    return {'type': 'panel', 'panelId': panelId};
  }
}
