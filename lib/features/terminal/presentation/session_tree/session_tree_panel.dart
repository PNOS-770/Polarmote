import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:safe_layout_x/safe_layout_x.dart';

import '../../../../shared/constants/app_string.dart';
import '../../../../shared/design_system/design_system.dart';
import '../../models/host_entry.dart';
import '../../state/terminal_app_state.dart';
import '../common/terminal_localization.dart';

import '../dialogs/terminal_dialogs.dart';
import '../common/host_tree_row.dart';

enum _SessionFolderAction { edit, delete }

class SessionTreePanel extends StatefulWidget {
  const SessionTreePanel({super.key});

  @override
  State<SessionTreePanel> createState() => _SessionTreePanelState();
}

class _SessionTreePanelState extends State<SessionTreePanel> {
  late final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final appState = context.read<TerminalAppState>();
    _searchController.text = appState.sessionQuery;
    _searchController.addListener(() {
      context.read<TerminalAppState>().setSessionQuery(_searchController.text);
    });
    appState.ensureSessionProbeRuntime();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _isMultiSelectPressed() {
    return HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
  }

  void _handleHostTap(TerminalAppState appState, HostEntry host) {
    if (_isMultiSelectPressed()) {
      appState.toggleHostSelection(host.id, multi: true);
      return;
    }
    unawaited(appState.connectToHost(host));
  }

  List<TreeViewNode<HostEntry>> _buildSessionTreeNodes(
    TerminalAppState appState,
    List<HostEntry> hosts,
  ) {
    final root = TreeViewNode<HostEntry>(key: '', label: '', children: []);
    for (final host in hosts) {
      final segments = host.group
          .split(RegExp(r'[\\/]+'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
      var cursor = root;
      for (final segment in segments) {
        var child = cursor.children.cast<TreeViewNode<HostEntry>?>().firstWhere(
          (c) => c!.label == segment,
          orElse: () => null,
        );
        if (child == null) {
          child = TreeViewNode<HostEntry>(
            key: cursor.key.isEmpty ? segment : '${cursor.key}/$segment',
            label: segment,
            children: [],
          );
          cursor.children.add(child);
        }
        cursor = child;
      }
      cursor.children.add(TreeViewNode<HostEntry>(
        key: host.id,
        label: host.name,
        value: host,
      ));
    }
    return root.children;
  }

  Set<String> _collectExpandedKeys(
    List<TreeViewNode<HostEntry>> nodes,
    TerminalAppState appState,
  ) {
    final keys = <String>{};
    void walk(List<TreeViewNode<HostEntry>> ns) {
      for (final n in ns) {
        if (!n.isLeaf) {
          if (appState.isSessionFolderExpanded(n.key)) {
            keys.add(n.key);
          }
          walk(n.children);
        }
      }
    }
    walk(nodes);
    return keys;
  }

  void _sortTreeNodes(
    List<TreeViewNode<HostEntry>> nodes,
    TerminalAppState appState,
  ) {
    for (final node in nodes) {
      if (!node.isLeaf) {
        _sortTreeNodes(node.children, appState);
        node.children.sort((a, b) {
          if (a.isLeaf == b.isLeaf) {
            return a.label.toLowerCase().compareTo(b.label.toLowerCase());
          }
          return a.isLeaf ? 1 : -1;
        });
      }
    }
  }

  bool _hostMatchesQuery(HostEntry host, String query) {
    if (query.isEmpty) return true;
    return host.name.toLowerCase().contains(query);
  }

  Future<void> _renameFolder(
    BuildContext context,
    TerminalAppState appState,
    TreeViewNode<HostEntry> folder,
  ) async {
    final result = await showInputDialog(
      context,
      title: '${t(context, AppStrings.values.edit)} · ${t(context, AppStrings.values.group)}',
      initialValue: folder.label,
      confirmText: t(context, AppStrings.values.save),
      cancelText: t(context, AppStrings.values.cancel),
      validator: (v) => (v == null || v.trim().isEmpty) ? ' ' : null,
    );
    if (result == null) return;
    final value = result.trim();
    if (value.isEmpty || value == folder.label) return;
    appState.renameSessionFolder(folderKey: folder.key, newName: value);
  }

  Future<void> _deleteFolder(
    BuildContext context,
    TerminalAppState appState,
    TreeViewNode<HostEntry> folder,
  ) async {
    final hostCount = appState.sessionFolderHostCount(folder.key);
    final confirmed = await showConfirmDialog(
      context,
      title: t(context, AppStrings.values.confirm),
      message:
          '${t(context, AppStrings.values.deleteVar, params: {'name': folder.label})}\n\n'
          '${l(appState, AppStrings.values.sessionFolderDeleteDangerVar, params: {'count': '$hostCount'})}',
      confirmText: t(context, AppStrings.values.delete),
      cancelText: t(context, AppStrings.values.cancel),
    );
    if (confirmed != true) return;
    appState.deleteSessionFolder(folder.key);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<TerminalAppState>();
    if (_searchController.text != appState.sessionQuery) {
      _searchController.value = _searchController.value.copyWith(
        text: appState.sessionQuery,
        selection: TextSelection.collapsed(
          offset: appState.sessionQuery.length,
        ),
        composing: TextRange.empty,
      );
    }
    final query = appState.sessionQuery.trim().toLowerCase();
    final hasQuery = query.isNotEmpty;
    final hosts = appState.visibleHosts();

    var roots = _buildSessionTreeNodes(appState, hosts);
    _sortTreeNodes(roots, appState);
    final expandedKeys = _collectExpandedKeys(roots, appState);

    // Filter hosts by query
    if (hasQuery) {
      _filterNodes(roots, query);
    }

    return Stack(
      children: [
        const Positioned.fill(child: BreatheGrid()),
        Container(
          color: AppColors.terminalTreeBackground.withValues(alpha: 0.85),
          child: Column(
            children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 2),
            child: Text(
              l(appState, AppStrings.values.connectSessionToPane),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.terminalTreeHeader,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white,
              ),
              decoration: InputDecoration(
                hintText: l(appState, AppStrings.values.search),
                hintStyle: const TextStyle(
                  fontSize: 12,
                  color: AppColors.terminalTreeMuted,
                ),
                prefixIcon: const Icon(
                  Icons.search,
                  size: 14,
                  color: AppColors.terminalTreeMuted,
                ),
                filled: true,
                fillColor: AppColors.terminalTreeInputBg,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                border: OutlineInputBorder(
                  borderRadius: AppRadius.radiusSM,
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: TreeView<HostEntry>(
            roots: roots,
            expandedKeys: expandedKeys,
            onToggleExpand: (key) => appState.toggleSessionFolderExpanded(key),
            showCheckboxes: false,
            indentWidth: 14,
            emptyHint: l(appState, AppStrings.values.noMatchingSessions),
            itemBuilder: (context, node, state, depth) {
              if (!node.isLeaf) {
                return _buildSessionFolderRow(
                  context,
                  appState,
                  node,
                  state,
                  depth,
                  query: appState.sessionQuery,
                  onRename: () =>
                      unawaited(_renameFolder(context, appState, node)),
                  onDelete: () =>
                      unawaited(_deleteFolder(context, appState, node)),
                );
              }
              final host = node.value;
              if (host == null) return const SizedBox.shrink();
              return HostTreeRow(
                key: ValueKey<String>('host-${host.id}'),
                appState: appState,
                host: host,
                depth: depth,
                query: appState.sessionQuery,
                isSelected: appState.selectedHostIds.contains(host.id),
                showProbe: true,
                onTap: () => _handleHostTap(appState, host),
                onConnect: () => unawaited(appState.connectToHost(host)),
                onEdit: () =>
                    showHostDialog(context, appState, host: host),
                onDelete: () =>
                    confirmDeleteHost(context, appState, host),
                onTogglePin: () => appState.toggleHostPinned(host.id),
              );
            },
          ),
        ),
      ],
      ),
    ),
  ],
);
  }

  bool _filterNodes(List<TreeViewNode<HostEntry>> nodes, String query) {
    nodes.removeWhere((n) {
        if (n.isLeaf) {
          final value = n.value;
          return value == null || !_hostMatchesQuery(value, query);
        }
        final childMatch = _filterNodes(n.children, query);
        if (childMatch) return false;
        return !n.label.toLowerCase().contains(query);
      });
    return nodes.isNotEmpty;
  }

  int _folderHostCount(TreeViewNode<HostEntry> node) {
    var count = 0;
    for (final child in node.children) {
      if (child.isLeaf) {
        count++;
      } else {
        count += _folderHostCount(child);
      }
    }
    return count;
  }

  Widget _buildSessionFolderRow(
    BuildContext context,
    TerminalAppState appState,
    TreeViewNode<HostEntry> node,
    TreeViewItemState state,
    int depth, {
    required String query,
    required VoidCallback onRename,
    required VoidCallback onDelete,
  }) {
    final expanded = state.isExpanded;
    final indent = (depth * 14).clamp(0, 56).toDouble();
    return Material(
      color: expanded ? AppColors.terminalTreeFolderBg : Colors.transparent,
      borderRadius: BorderRadius.circular(5),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: state.onToggleExpand,
        onSecondaryTapDown: (details) => unawaited(
          _showFolderMenu(context, appState, node, details.globalPosition,
              onRename, onDelete),
        ),
        child: Padding(
          padding: EdgeInsets.only(left: indent, right: 6),
          child: SizedBox(
            height: 26,
            child: Row(
              children: [
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  size: 15,
                  color: AppColors.terminalTreeIcon,
                ),
                const SizedBox(width: 2),
                Icon(
                  expanded
                      ? Icons.folder_open_outlined
                      : Icons.folder_outlined,
                  size: 14,
                  color: AppColors.terminalTreeIcon,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    node.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.terminalTreeFolder,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  '${_folderHostCount(node)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.terminalTreeFolderCount,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showFolderMenu(
    BuildContext context,
    TerminalAppState appState,
    TreeViewNode<HostEntry> node,
    Offset position,
    VoidCallback onRename,
    VoidCallback onDelete,
  ) async {
    final action = await showCompactMenu<_SessionFolderAction>(
      context: context,
      position: position,
      items: [
        compactMenuItem(
          value: _SessionFolderAction.edit,
          label: l(appState, AppStrings.values.edit),
        ),
        compactMenuItem(
          value: _SessionFolderAction.delete,
          label: l(appState, AppStrings.values.delete),
        ),
      ],
    );
    if (action == null) return;
    switch (action) {
      case _SessionFolderAction.edit:
        onRename();
      case _SessionFolderAction.delete:
        onDelete();
    }
  }
}



