import '../dock/dock_tree.dart';

class LayoutState {
  const LayoutState({required this.tree});

  final DockTree tree;

  LayoutState copyWith({DockTree? tree}) {
    return LayoutState(tree: tree ?? this.tree);
  }
}
