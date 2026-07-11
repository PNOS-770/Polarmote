import 'package:flutter/widgets.dart';

import 'dock_node.dart';
import 'dock_tree.dart';
import 'drag_engine.dart';

class DockManager extends ChangeNotifier {
  DockManager({required DockTree initialTree}) : _tree = initialTree;

  final DragEngine dragEngine = const DragEngine();
  DockTree _tree;

  DockTree get tree => _tree;

  void setTree(DockTree next) {
    _tree = next;
    notifyListeners();
  }

  void activateTab(TabNode node, int index) {
    if (index < 0 || index >= node.tabs.length) return;
    final next = TabNode(tabs: node.tabs, activeIndex: index);
    _tree = _tree.copyWith(root: _replaceNode(_tree.root, node, next));
    notifyListeners();
  }

  DockNode _replaceNode(
    DockNode current,
    DockNode target,
    DockNode replacement,
  ) {
    if (identical(current, target)) return replacement;
    switch (current) {
      case SplitNode split:
        return SplitNode(
          direction: split.direction,
          ratio: split.ratio,
          first: _replaceNode(split.first, target, replacement),
          second: _replaceNode(split.second, target, replacement),
        );
      case TabNode tab:
        return TabNode(tabs: tab.tabs, activeIndex: tab.activeIndex);
      case PanelNode panel:
        return panel;
    }
  }

  void insertPanelWithTarget({
    required PanelNode source,
    required PanelNode target,
    required DockTarget dockTarget,
  }) {
    if (source.panelId == target.panelId) return;

    final root = _tree.root;
    if (root is PanelNode && root.panelId == target.panelId) {
      _tree = _tree.copyWith(
        root: _insertAroundPanel(root, source, dockTarget),
      );
      notifyListeners();
    }
  }

  DockNode _insertAroundPanel(
    PanelNode target,
    PanelNode source,
    DockTarget dockTarget,
  ) {
    switch (dockTarget) {
      case DockTarget.top:
        return SplitNode(
          direction: Axis.vertical,
          ratio: 0.5,
          first: source,
          second: target,
        );
      case DockTarget.bottom:
        return SplitNode(
          direction: Axis.vertical,
          ratio: 0.5,
          first: target,
          second: source,
        );
      case DockTarget.left:
        return SplitNode(
          direction: Axis.horizontal,
          ratio: 0.5,
          first: source,
          second: target,
        );
      case DockTarget.right:
        return SplitNode(
          direction: Axis.horizontal,
          ratio: 0.5,
          first: target,
          second: source,
        );
      case DockTarget.center:
        return TabNode(tabs: [target, source]);
    }
  }
}
