import 'package:flutter/material.dart';
import 'tree_node.dart';

class TreeView<T> extends StatefulWidget {
  const TreeView({
    super.key,
    required this.roots,
    required this.itemBuilder,
    this.onSelectionChanged,
    this.onToggleExpand,
    this.expandedKeys,
    this.searchQuery,
    this.showCheckboxes = true,
    this.indentWidth = 24,
    this.emptyHint,
    this.shrinkWrap = false,
    this.physics,
    this.controller,
  });

  final List<TreeViewNode<T>> roots;
  final Widget Function(
    BuildContext context,
    TreeViewNode<T> node,
    TreeViewItemState state,
    int depth,
  ) itemBuilder;
  final void Function(Set<String> selectedKeys)? onSelectionChanged;
  final void Function(String nodeKey)? onToggleExpand;
  final Set<String>? expandedKeys;
  final String? searchQuery;
  final bool showCheckboxes;
  final double indentWidth;
  final String? emptyHint;
  final bool shrinkWrap;
  final ScrollPhysics? physics;
  final ScrollController? controller;

  @override
  State<TreeView<T>> createState() => TreeViewState<T>();
}

class TreeViewItemState {
  TreeViewItemState({
    required this.isExpanded,
    required this.isSelected,
    required this.isLeaf,
    required this.onToggleExpand,
    required this.onToggleSelect,
  });

  final bool isExpanded;
  final bool isSelected;
  final bool isLeaf;
  final VoidCallback onToggleExpand;
  final VoidCallback onToggleSelect;
}

class TreeViewState<T> extends State<TreeView<T>> {
  late List<_FlatEntry<T>> _flatList;

  @override
  void initState() {
    super.initState();
    _rebuildFlatList();
  }

  @override
  void didUpdateWidget(TreeView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roots != widget.roots ||
        oldWidget.searchQuery != widget.searchQuery ||
        oldWidget.expandedKeys != widget.expandedKeys) {
      _rebuildFlatList();
    }
  }

  void _rebuildFlatList() {
    final query = widget.searchQuery?.toLowerCase().trim() ?? '';
    _applyExpandedState();
    _flatList = _flatten(widget.roots, query);
  }

  void _applyExpandedState() {
    final keys = widget.expandedKeys;
    if (keys != null) {
      _applyExpandedStateTo(widget.roots, keys);
    }
  }

  void _applyExpandedStateTo(List<TreeViewNode<T>> nodes, Set<String> keys) {
    for (final node in nodes) {
      if (!node.isLeaf) {
        node.isExpanded = keys.contains(node.key);
        _applyExpandedStateTo(node.children, keys);
      }
    }
  }

  List<_FlatEntry<T>> _flatten(
    List<TreeViewNode<T>> nodes,
    String query,
  ) {
    final result = <_FlatEntry<T>>[];
    for (final node in nodes) {
      _flattenNode(node, result, query, 0);
    }
    return result;
  }

  bool _flattenNode(
    TreeViewNode<T> node,
    List<_FlatEntry<T>> result,
    String query,
    int depth,
  ) {
    final matchLabel = query.isEmpty || node.label.toLowerCase().contains(query);

    if (node.isLeaf) {
      if (!matchLabel) return false;
      result.add(_FlatEntry(node: node, depth: depth));
      return true;
    }

    final childEntries = <_FlatEntry<T>>[];
    for (final child in node.children) {
      _flattenNode(child, childEntries, query, depth + 1);
    }

    if (!matchLabel && childEntries.isEmpty) return false;

    result.add(_FlatEntry(node: node, depth: depth));
    if (node.isExpanded) {
      result.addAll(childEntries);
    }
    return true;
  }

  void _toggleExpand(TreeViewNode<T> node) {
    if (widget.expandedKeys != null) {
      widget.onToggleExpand?.call(node.key);
      return;
    }
    setState(() {
      node.isExpanded = !node.isExpanded;
      _rebuildFlatList();
    });
  }

  void _toggleSelect(TreeViewNode<T> node) {
    setState(() {
      _toggleNodeAndDescendants(node, !node.isSelected);
      _updateParentSelection(node);
      _rebuildFlatList();
    });
    final selected = _collectSelected(widget.roots);
    widget.onSelectionChanged?.call(selected);
  }

  void _toggleNodeAndDescendants(TreeViewNode<T> node, bool selected) {
    node.isSelected = selected;
    for (final child in node.children) {
      _toggleNodeAndDescendants(child, selected);
    }
  }

  void _updateParentSelection(TreeViewNode<T> node) {
    var current = node;
    while (true) {
      final parent = _findParent(current);
      if (parent == null) break;
      final allSelected = parent.children.every((c) => c.isSelected);
      final anySelected = parent.children.any((c) => c.isSelected);
      if (allSelected) {
        parent.isSelected = true;
      } else if (!anySelected) {
        parent.isSelected = false;
      }
      current = parent;
    }
  }

  TreeViewNode<T>? _findParent(TreeViewNode<T> node) {
    for (final root in widget.roots) {
      final result = _findParentIn(root, node);
      if (result != null) return result;
    }
    return null;
  }

  TreeViewNode<T>? _findParentIn(
    TreeViewNode<T> parent,
    TreeViewNode<T> target,
  ) {
    for (final child in parent.children) {
      if (child == target) return parent;
      final found = _findParentIn(child, target);
      if (found != null) return found;
    }
    return null;
  }

  Set<String> _collectSelected(List<TreeViewNode<T>> nodes) {
    final result = <String>{};
    for (final node in nodes) {
      if (node.isLeaf && node.isSelected) {
        result.add(node.key);
      }
      result.addAll(_collectSelected(node.children));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    if (_flatList.isEmpty) {
      final hint = widget.emptyHint;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            hint ?? '',
            style: TextStyle(color: Colors.grey[500], fontSize: 13),
          ),
        ),
      );
    }

    return ListView.builder(
      controller: widget.controller,
      shrinkWrap: widget.shrinkWrap,
      physics: widget.physics,
      itemCount: _flatList.length,
      itemBuilder: (context, index) {
        final entry = _flatList[index];
        final node = entry.node;
        final depth = entry.depth;
        final state = TreeViewItemState(
          isExpanded: node.isExpanded,
          isSelected: node.isSelected,
          isLeaf: node.isLeaf,
          onToggleExpand: () => _toggleExpand(node),
          onToggleSelect: () => _toggleSelect(node),
        );
        return Padding(
          padding: EdgeInsets.only(left: depth * widget.indentWidth),
          child: widget.itemBuilder(context, node, state, depth),
        );
      },
    );
  }
}

class _FlatEntry<T> {
  final TreeViewNode<T> node;
  final int depth;
  _FlatEntry({required this.node, required this.depth});
}

