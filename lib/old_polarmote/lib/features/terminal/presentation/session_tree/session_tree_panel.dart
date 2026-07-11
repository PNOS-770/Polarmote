import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:safe_layout_x/safe_layout_x.dart';

import '../../../../shared/constants/app_string.dart';
import '../../../../shared/design_system/design_system.dart';
import '../../models/host_entry.dart';
import '../../models/terminal_tab.dart';
import '../../state/terminal_app_state.dart';
import '../common/compact_more_menu_button.dart';
import '../common/terminal_localization.dart';
import '../common/terminal_ui_palette.dart';
import '../common/vscode_action_icons.dart';
import '../dialogs/terminal_dialogs.dart';

enum _SessionHostAction { connect, edit, delete, pinToggle }

enum _SessionFolderAction { edit, delete }

class SessionTreePanel extends StatefulWidget {
  const SessionTreePanel({super.key});

  @override
  State<SessionTreePanel> createState() => _SessionTreePanelState();
}

class _SessionTreePanelState extends State<SessionTreePanel> {
  static const Duration _doubleTapThreshold = Duration(milliseconds: 320);
  String? _lastTappedHostId;
  DateTime? _lastTappedAt;
  late final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final appState = context.read<TerminalAppState>();
    _searchController.text = appState.sessionQuery;
    _searchController.addListener(() {
      context.read<TerminalAppState>().setSessionQuery(_searchController.text);
    });
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
    final multi = _isMultiSelectPressed();
    appState.toggleHostSelection(host.id, multi: multi);
    if (multi) {
      _lastTappedHostId = null;
      _lastTappedAt = null;
      return;
    }
    final existingSession = appState.terminalSessionForHost(host);
    if (existingSession != null) {
      appState.setActiveTerminalSession(existingSession.id);
      _lastTappedHostId = null;
      _lastTappedAt = null;
      return;
    }
    final now = DateTime.now();
    final isDoubleTap =
        _lastTappedHostId == host.id &&
        _lastTappedAt != null &&
        now.difference(_lastTappedAt!) <= _doubleTapThreshold;
    _lastTappedHostId = host.id;
    _lastTappedAt = now;
    if (isDoubleTap) {
      _lastTappedHostId = null;
      _lastTappedAt = null;
      unawaited(appState.connectToHost(host));
    }
  }

  Future<void> _renameFolder(
    BuildContext context,
    TerminalAppState appState,
    _SessionFolderNode folder,
  ) async {
    final controller = TextEditingController(text: folder.name);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            backgroundColor: AppColors.cardBackground,
            shape: RoundedRectangleBorder(
              borderRadius: AppRadius.radiusDialog,
            ),
            title: Text(
              '${t(dialogContext, AppStrings.values.edit)} · ${t(dialogContext, AppStrings.values.group)}',
              style: AppTextStyles.h4,
            ),
            content: AppTextField(
              controller: controller,
              label: t(dialogContext, AppStrings.values.group),
              autofocus: true,
              onSubmitted: (_) => Navigator.of(dialogContext).pop(true),
            ),
            actionsPadding: const EdgeInsets.all(AppSpacing.lg),
            actions: [
              AppTextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                label: t(dialogContext, AppStrings.values.cancel),
                size: ButtonSize.small,
              ),
              PrimaryButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                label: t(dialogContext, AppStrings.values.save),
                size: ButtonSize.medium,
              ),
            ],
          );
        },
      );
      if (confirmed != true) return;
      final value = controller.text.trim();
      if (value.isEmpty || value == folder.name) return;
      appState.renameSessionFolder(folderKey: folder.key, newName: value);
    } finally {
      controller.dispose();
    }
  }

  Future<void> _deleteFolder(
    BuildContext context,
    TerminalAppState appState,
    _SessionFolderNode folder,
  ) async {
    final hostCount = appState.sessionFolderHostCount(folder.key);
    final confirmed = await showConfirmDialog(
      context,
      title: t(context, AppStrings.values.confirm),
      message:
          '${t(context, AppStrings.values.deleteVar, params: {'name': folder.name})}\n\n'
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
    final root = _buildTree(appState, hosts);
    if (hasQuery) {
      _markMatches(root, query);
    }
    _sortTree(root, appState);
    final rows = _flattenTreeRows(root, appState, hasQuery);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => showHostDialog(context, appState),
                icon: buildNewSessionVscodeIcon(),
                label: Text(l(appState, AppStrings.values.newSession)),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => showQuickConnectDialog(context, appState),
                icon: buildQuickConnectVscodeIcon(),
                label: Text(l(appState, AppStrings.values.quickConnect)),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
          child: AppSearchBar(
            controller: _searchController,
            hint: l(appState, AppStrings.values.search),
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? Center(
                  child: Text(
                    l(appState, AppStrings.values.noMatchingSessions),
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                )
              : GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: appState.clearHostSelection,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      if (row.folder != null) {
                        final folder = row.folder!;
                        return _SessionFolderRow(
                          key: ValueKey<String>('folder-${folder.key}'),
                          appState: appState,
                          folder: folder,
                          depth: row.depth,
                          expanded: row.expanded,
                          query: appState.sessionQuery,
                          onToggleExpanded: () =>
                              appState.toggleSessionFolderExpanded(folder.key),
                          onEdit: () => unawaited(
                            _renameFolder(context, appState, folder),
                          ),
                          onDelete: () => unawaited(
                            _deleteFolder(context, appState, folder),
                          ),
                        );
                      }
                      final host = row.host!;
                      return _SessionHostRow(
                        key: ValueKey<String>('host-${host.id}'),
                        appState: appState,
                        host: host,
                        depth: row.depth,
                        query: appState.sessionQuery,
                        status: appState.hostSessionStatus(host.id),
                        selected: appState.selectedHostIds.contains(host.id),
                        isPinned: appState.isHostPinned(host.id),
                        readOnly: false,
                        onTap: () => _handleHostTap(appState, host),
                        onConnect: () =>
                            unawaited(appState.connectToHost(host)),
                        onEdit: () =>
                            showHostDialog(context, appState, host: host),
                        onDelete: () =>
                            confirmDeleteHost(context, appState, host),
                        onTogglePin: () => appState.toggleHostPinned(host.id),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  _SessionFolderNode _buildTree(
    TerminalAppState appState,
    List<HostEntry> hosts,
  ) {
    final root = _SessionFolderNode.root();
    for (final host in hosts) {
      final segments = host.group
          .split(RegExp(r'[\\/]+'))
          .map((segment) => segment.trim())
          .where((segment) => segment.isNotEmpty)
          .toList(growable: false);
      var cursor = root;
      for (final segment in segments) {
        cursor = cursor.ensureChild(segment);
      }
      cursor.hosts.add(host);
    }
    return root;
  }

  bool _markMatches(_SessionFolderNode node, String query) {
    var matched = false;
    if (node.name.toLowerCase().contains(query)) {
      matched = true;
    }
    for (final host in node.hosts) {
      if (_hostMatchesQuery(host, query)) {
        matched = true;
        break;
      }
    }
    for (final child in node.children.values) {
      if (_markMatches(child, query)) {
        matched = true;
      }
    }
    node.hasMatch = matched;
    return matched;
  }

  bool _hostMatchesQuery(HostEntry host, String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return true;
    }
    return host.name.toLowerCase().contains(normalized);
  }

  void _sortTree(_SessionFolderNode node, TerminalAppState appState) {
    final sortedChildren = node.children.values.toList(growable: false)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    node.children
      ..clear()
      ..addEntries(sortedChildren.map((child) => MapEntry(child.name, child)));
    node.hosts.sort((a, b) => _compareHosts(a, b, appState));
    for (final child in sortedChildren) {
      _sortTree(child, appState);
    }
  }

  int _compareHosts(HostEntry a, HostEntry b, TerminalAppState appState) {
    int compareByRecent(HostEntry left, HostEntry right) {
      final l = left.lastConnected;
      final r = right.lastConnected;
      if (l == null && r == null) return 0;
      if (l == null) return 1;
      if (r == null) return -1;
      return r.compareTo(l);
    }

    int compareByName(HostEntry left, HostEntry right) {
      return left.name.toLowerCase().compareTo(right.name.toLowerCase());
    }

    int compareBySmart(HostEntry left, HostEntry right) {
      final lOnline =
          appState.hostSessionStatus(left.id) == TerminalStatus.connected;
      final rOnline =
          appState.hostSessionStatus(right.id) == TerminalStatus.connected;
      if (lOnline != rOnline) {
        return lOnline ? -1 : 1;
      }
      final recent = compareByRecent(left, right);
      if (recent != 0) return recent;
      return compareByName(left, right);
    }

    final aPinned = appState.isHostPinned(a.id);
    final bPinned = appState.isHostPinned(b.id);
    if (aPinned != bPinned) {
      return aPinned ? -1 : 1;
    }
    return switch (appState.sessionSortMode) {
      SessionSortMode.name => compareByName(a, b),
      SessionSortMode.recent => compareByRecent(a, b),
      SessionSortMode.smart => compareBySmart(a, b),
    };
  }

  List<_SessionTreeRowData> _flattenTreeRows(
    _SessionFolderNode root,
    TerminalAppState appState,
    bool hasQuery,
  ) {
    final rows = <_SessionTreeRowData>[];
    final query = appState.sessionQuery.trim().toLowerCase();

    void appendFolder(_SessionFolderNode node, int depth) {
      final folders = node.children.values.toList(growable: false);
      for (final child in folders) {
        if (hasQuery && !child.hasMatch) {
          continue;
        }
        final expanded = hasQuery
            ? true
            : appState.isSessionFolderExpanded(child.key);
        rows.add(
          _SessionTreeRowData.folder(
            folder: child,
            depth: depth,
            expanded: expanded,
          ),
        );
        if (expanded) {
          appendFolder(child, depth + 1);
        }
      }
      for (final host in node.hosts) {
        if (hasQuery && !_hostMatchesQuery(host, query)) {
          continue;
        }
        rows.add(_SessionTreeRowData.host(host: host, depth: depth));
      }
    }

    appendFolder(root, 0);
    return rows;
  }
}

class _SessionFolderNode {
  _SessionFolderNode({required this.name, required this.key});

  factory _SessionFolderNode.root() => _SessionFolderNode(name: '', key: '');

  final String name;
  final String key;
  final Map<String, _SessionFolderNode> children = {};
  final List<HostEntry> hosts = [];
  bool hasMatch = false;

  _SessionFolderNode ensureChild(String segment) {
    final childKey = key.isEmpty ? segment : '$key/$segment';
    return children.putIfAbsent(
      segment,
      () => _SessionFolderNode(name: segment, key: childKey),
    );
  }
}

class _SessionTreeRowData {
  const _SessionTreeRowData.folder({
    required this.folder,
    required this.depth,
    required this.expanded,
  }) : host = null;

  const _SessionTreeRowData.host({required this.host, required this.depth})
    : folder = null,
      expanded = false;

  final _SessionFolderNode? folder;
  final HostEntry? host;
  final int depth;
  final bool expanded;
}

class _SessionFolderRow extends StatelessWidget {
  const _SessionFolderRow({
    super.key,
    required this.appState,
    required this.folder,
    required this.depth,
    required this.expanded,
    required this.query,
    required this.onToggleExpanded,
    required this.onEdit,
    required this.onDelete,
  });

  final TerminalAppState appState;
  final _SessionFolderNode folder;
  final int depth;
  final bool expanded;
  final String query;
  final VoidCallback onToggleExpanded;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  Future<void> _showFolderMenu(BuildContext context, Offset position) async {
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
        onEdit();
      case _SessionFolderAction.delete:
        onDelete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final indent = depth * 14.0;
    final toggleIcon = expanded
        ? Icons.keyboard_arrow_down
        : Icons.keyboard_arrow_right;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      child: InkWell(
        onTap: onToggleExpanded,
        onSecondaryTapDown: (details) =>
            unawaited(_showFolderMenu(context, details.globalPosition)),
        onLongPress: () {
          final box = context.findRenderObject() as RenderBox?;
          final position = box == null
              ? Offset.zero
              : box.localToGlobal(box.size.center(Offset.zero));
          unawaited(_showFolderMenu(context, position));
        },
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 7),
          child: Row(
            children: [
              SizedBox(width: indent),
              SizedBox(
                width: 30,
                height: 30,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 30,
                    height: 30,
                  ),
                  splashRadius: 16,
                  onPressed: onToggleExpanded,
                  icon: Icon(
                    toggleIcon,
                    size: 20,
                    color: TerminalUiPalette.textSecondary,
                  ),
                ),
              ),
              expanded
                  ? buildGroupFolderOpenVscodeIcon(size: 16)
                  : buildGroupFolderVscodeIcon(size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text.rich(
                  AppTextStyles.highlightSpan(
                    text: folder.name,
                    query: query,
                    baseStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionHostRow extends StatelessWidget {
  const _SessionHostRow({
    super.key,
    required this.appState,
    required this.host,
    required this.depth,
    required this.query,
    required this.status,
    required this.selected,
    required this.isPinned,
    required this.readOnly,
    required this.onTap,
    required this.onConnect,
    required this.onEdit,
    required this.onDelete,
    required this.onTogglePin,
  });

  final TerminalAppState appState;
  final HostEntry host;
  final int depth;
  final String query;
  final TerminalStatus? status;
  final bool selected;
  final bool isPinned;
  final bool readOnly;
  final VoidCallback onTap;
  final VoidCallback onConnect;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onTogglePin;

  Future<void> _showHostMenu(BuildContext context, Offset position) async {
    final action = await showCompactMenu<_SessionHostAction>(
      context: context,
      position: position,
      items: [
        compactMenuItem(
          value: _SessionHostAction.connect,
          label: l(appState, AppStrings.values.connect),
        ),
        compactMenuItem(
          value: _SessionHostAction.edit,
          enabled: !readOnly,
          label: l(appState, AppStrings.values.edit),
        ),
        compactMenuItem(
          value: _SessionHostAction.pinToggle,
          enabled: !readOnly,
          label: l(
            appState,
            isPinned ? AppStrings.values.unpin : AppStrings.values.pin,
          ),
        ),
        compactMenuItem(
          value: _SessionHostAction.delete,
          enabled: !readOnly,
          label: l(appState, AppStrings.values.delete),
        ),
      ],
    );
    if (action == null) return;
    if (!context.mounted) return;
    _handleHostAction(action);
  }

  void _handleHostAction(_SessionHostAction action) {
    switch (action) {
      case _SessionHostAction.connect:
        onConnect();
      case _SessionHostAction.edit:
        onEdit?.call();
      case _SessionHostAction.delete:
        onDelete?.call();
      case _SessionHostAction.pinToggle:
        onTogglePin?.call();
    }
  }

  Widget _sessionTypeIcon() {
    return switch (host.connectionType) {
      ConnectionType.ssh => buildConnectionSshVscodeIcon(
        size: 16,
        color: _sessionStatusColor(),
      ),
      ConnectionType.serial => const Icon(Icons.usb, size: 16),
      ConnectionType.telnet => const Icon(Icons.lan, size: 16),
      ConnectionType.local => switch (host.localShellType) {
        LocalShellType.powershell => buildLocalShellPowerShellVscodeIcon(
          size: 16,
        ),
        LocalShellType.powershellAdmin =>
          buildLocalShellPowerShellAdminVscodeIcon(size: 16),
        LocalShellType.commandPrompt => buildLocalShellCommandPromptVscodeIcon(
          size: 16,
        ),
        LocalShellType.wsl => buildLocalShellWslVscodeIcon(size: 16),
        LocalShellType.bash => buildLocalShellBashVscodeIcon(size: 16),
        LocalShellType.systemDefault => buildLocalShellSystemDefaultVscodeIcon(
          size: 16,
        ),
      },
    };
  }

  Color _probeStatusColor(SessionProbeStatus status) {
    switch (status) {
      case SessionProbeStatus.reachable:
        return TerminalUiPalette.success;
      case SessionProbeStatus.unreachable:
        return TerminalUiPalette.error;
      case SessionProbeStatus.probing:
        return TerminalUiPalette.warning;
      case SessionProbeStatus.unknown:
        return TerminalUiPalette.textSecondary;
    }
  }

  String _probeStatusLabel(TerminalAppState appState, SessionProbeState state) {
    final base = switch (state.status) {
      SessionProbeStatus.reachable => l(
        appState,
        AppStrings.values.probeReachable,
      ),
      SessionProbeStatus.unreachable => l(
        appState,
        AppStrings.values.probeUnreachable,
      ),
      SessionProbeStatus.probing => l(appState, AppStrings.values.probeProbing),
      SessionProbeStatus.unknown => l(appState, AppStrings.values.probeUnknown),
    };
    if (state.latencyMs != null && state.latencyMs! > 0) {
      return '$base ${state.latencyMs}ms';
    }
    return base;
  }

  Color _effectiveStatusColor(SessionProbeState? probeState) {
    if (status == TerminalStatus.connected) {
      return _sessionStatusColor();
    }
    if (probeState == null) {
      return _sessionStatusColor();
    }
    return _probeStatusColor(probeState.status);
  }

  Widget _statusDot(SessionProbeState? probeState) {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: _effectiveStatusColor(probeState),
        shape: BoxShape.circle,
        border: Border.all(color: TerminalUiPalette.cardBackground, width: 1),
      ),
    );
  }

  String _sessionTypeLabel() {
    return switch (host.connectionType) {
      ConnectionType.ssh => l(appState, AppStrings.values.connectionSsh),
      ConnectionType.serial => l(
        appState,
        AppStrings.values.badgeConnectionTypeSerial,
      ),
      ConnectionType.telnet => l(appState, AppStrings.values.connectionTelnet),
      ConnectionType.local => switch (host.localShellType) {
        LocalShellType.powershell => l(
          appState,
          AppStrings.values.localShellPowerShell,
        ),
        LocalShellType.powershellAdmin => l(
          appState,
          AppStrings.values.localShellPowerShellAdmin,
        ),
        LocalShellType.commandPrompt => l(
          appState,
          AppStrings.values.badgeLocalShellCmd,
        ),
        LocalShellType.wsl => l(appState, AppStrings.values.localShellWsl),
        LocalShellType.bash => l(appState, AppStrings.values.localShellBash),
        LocalShellType.systemDefault => l(
          appState,
          AppStrings.values.badgeLocalShellLocal,
        ),
      },
    };
  }

  String _sessionStatusLabel() {
    switch (status) {
      case TerminalStatus.connected:
        return l(appState, AppStrings.values.connected);
      case TerminalStatus.connecting:
        return l(appState, AppStrings.values.connecting);
      case TerminalStatus.reconnecting:
        return l(appState, AppStrings.values.reconnecting);
      case TerminalStatus.disconnected:
      case null:
        return l(appState, AppStrings.values.disconnected);
    }
  }

  Color _sessionStatusColor() {
    switch (status) {
      case TerminalStatus.connected:
        return TerminalUiPalette.success;
      case TerminalStatus.connecting:
        return TerminalUiPalette.warning;
      case TerminalStatus.reconnecting:
        return TerminalUiPalette.info;
      case TerminalStatus.disconnected:
      case null:
        return TerminalUiPalette.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final indent = 12.0 + (depth * 14.0);
    final leadingIndent = (indent + 8).clamp(8.0, 96.0).toDouble();
    final probeState = appState.sessionProbeStateForHost(host.id);
    final probeLabel =
        probeState == null || probeState.status == SessionProbeStatus.unknown
        ? null
        : _probeStatusLabel(appState, probeState);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: InkWell(
        onTapDown: (_) => onTap(),
        onSecondaryTapDown: (details) =>
            unawaited(_showHostMenu(context, details.globalPosition)),
        onLongPress: () {
          final box = context.findRenderObject() as RenderBox?;
          final position = box == null
              ? Offset.zero
              : box.localToGlobal(box.size.center(Offset.zero));
          unawaited(_showHostMenu(context, position));
        },
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? TerminalUiPalette.accentSelected : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth = constraints.maxWidth;
              final compact = maxWidth < 150;
              final ultraCompact = maxWidth < 130;
              final showTypeIcon = !ultraCompact;
              final showPin = maxWidth >= 150;
              final adaptiveLeadingIndent = ultraCompact
                  ? 0.0
                  : (compact
                        ? leadingIndent.clamp(0.0, 16.0).toDouble()
                        : leadingIndent);
              final actionPadding = compact ? 2.0 : 4.0;
              final actionIconSize = compact ? 16.0 : 17.0;
              return Row(
                children: [
                  SizedBox(width: adaptiveLeadingIndent),
                  if (showTypeIcon)
                    Tooltip(
                      key: ValueKey<String>('host-type-tip-${host.id}'),
                      message: [
                        _sessionTypeLabel(),
                        _sessionStatusLabel(),
                        if (probeLabel != null) probeLabel,
                      ].join(' · '),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _statusDot(probeState),
                          const SizedBox(width: 5),
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: _sessionTypeIcon(),
                          ),
                        ],
                      ),
                    ),
                  if (showTypeIcon) SizedBox(width: compact ? 3 : 6),
                  Expanded(
                    child: Text.rich(
                      AppTextStyles.highlightSpan(
                        text: host.name,
                        query: query,
                        baseStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (showPin)
                    Tooltip(
                      key: ValueKey<String>('host-pin-tip-${host.id}'),
                      message: l(
                        appState,
                        isPinned
                            ? AppStrings.values.unpin
                            : AppStrings.values.pin,
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: onTogglePin,
                        child: Padding(
                          padding: EdgeInsets.all(actionPadding),
                          child: Icon(
                            isPinned ? Icons.star : Icons.star_outline,
                            size: actionIconSize - 1,
                            color: isPinned
                                ? TerminalUiPalette.warning
                                : TerminalUiPalette.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  CompactMoreMenuButton(
                    tooltip: l(appState, AppStrings.values.more),
                    padding: actionPadding,
                    iconSize: actionIconSize,
                    onTapDown: (details) => unawaited(
                      _showHostMenu(context, details.globalPosition),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
