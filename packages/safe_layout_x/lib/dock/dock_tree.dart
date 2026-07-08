import 'dock_node.dart';

class DockTree {
  const DockTree({required this.root});

  final DockNode root;

  DockTree copyWith({DockNode? root}) {
    return DockTree(root: root ?? this.root);
  }

  Map<String, dynamic> toJson() {
    return root.toJson();
  }
}
