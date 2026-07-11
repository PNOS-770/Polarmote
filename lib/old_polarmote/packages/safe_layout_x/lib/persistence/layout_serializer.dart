import 'package:flutter/widgets.dart';

import '../dock/dock_node.dart';
import '../dock/dock_tree.dart';

class LayoutSerializer {
  const LayoutSerializer._();

  static Map<String, dynamic> toJson(DockTree tree) {
    return tree.toJson();
  }

  static DockTree fromJson(Map<String, dynamic> json) {
    return DockTree(root: _nodeFromJson(json));
  }

  static DockNode _nodeFromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    switch (type) {
      case 'split':
        return SplitNode(
          direction: (json['direction'] as String?) == Axis.horizontal.name
              ? Axis.horizontal
              : Axis.vertical,
          ratio: (json['ratio'] as num?)?.toDouble() ?? 0.5,
          first: _nodeFromJson((json['first'] as Map).cast<String, dynamic>()),
          second: _nodeFromJson(
            (json['second'] as Map).cast<String, dynamic>(),
          ),
        );
      case 'tab':
        final tabsJson = (json['tabs'] as List?) ?? const <dynamic>[];
        return TabNode(
          tabs: [
            for (final item in tabsJson)
              _nodeFromJson((item as Map).cast<String, dynamic>()) as PanelNode,
          ],
          activeIndex: (json['activeIndex'] as num?)?.toInt() ?? 0,
        );
      case 'panel':
      default:
        return PanelNode(panelId: json['panelId'] as String? ?? 'unknown');
    }
  }
}
