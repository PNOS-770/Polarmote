import 'package:flutter/widgets.dart';

class TreeViewNode<T> {
  TreeViewNode({
    required this.key,
    required this.label,
    this.value,
    this.children = const [],
    this.isExpanded = false,
    this.isSelected = false,
    this.isExpandable = false,
    this.icon,
    this.subtitle,
  });

  final String key;
  final String label;
  final T? value;
  List<TreeViewNode<T>> children;
  bool isExpanded;
  bool isSelected;
  bool isExpandable;
  final IconData? icon;
  final String? subtitle;

  bool get isLeaf => !isExpandable && children.isEmpty;

  TreeViewNode<T> copyWith({
    List<TreeViewNode<T>>? children,
    bool? isExpanded,
    bool? isSelected,
    bool? isExpandable,
  }) {
    return TreeViewNode<T>(
      key: key,
      label: label,
      value: value,
      children: children ?? this.children,
      isExpanded: isExpanded ?? this.isExpanded,
      isSelected: isSelected ?? this.isSelected,
      isExpandable: isExpandable ?? this.isExpandable,
      icon: icon,
      subtitle: subtitle,
    );
  }
}

List<TreeViewNode<T>> buildTreeFromList<T, G>({
  required List<T> items,
  required String Function(T) keyOf,
  required String Function(T) labelOf,
  required G Function(T) groupOf,
  required String Function(G) groupLabel,
  IconData Function(T)? iconOf,
  String Function(T)? subtitleOf,
}) {
  final groupMap = <G, List<T>>{};
  for (final item in items) {
    groupMap.putIfAbsent(groupOf(item), () => []).add(item);
  }

  final roots = <TreeViewNode<T>>[];
  for (final entry in groupMap.entries) {
    final groupKey = entry.key.toString();
    final groupName = groupLabel(entry.key);
    final children = entry.value.map((item) {
      return TreeViewNode<T>(
        key: keyOf(item),
        label: labelOf(item),
        value: item,
        icon: iconOf?.call(item),
        subtitle: subtitleOf?.call(item),
      );
    }).toList();

    roots.add(TreeViewNode<T>(
      key: 'group-$groupKey',
      label: groupName,
      children: children,
      isExpanded: true,
    ));
  }

  return roots;
}

