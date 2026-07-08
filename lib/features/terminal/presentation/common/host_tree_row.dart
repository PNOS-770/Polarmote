import 'package:flutter/material.dart';

import '../../../../shared/constants/app_string.dart';
import '../../../../shared/design_system/design_system.dart';
import '../../models/host_entry.dart';
import '../../models/terminal_tab.dart';
import '../../state/terminal_app_state.dart';
import 'terminal_localization.dart';

/// 统一的主机树节点组件，用于会话页面和脚本执行对话框
class HostTreeRow extends StatefulWidget {
  const HostTreeRow({
    super.key,
    required this.appState,
    required this.host,
    required this.depth,
    this.query = '',
    this.showStatus = true,
    this.showPin = true,
    this.showCheckbox = false,
    this.isSelected = false,
    this.readOnly = false,
    this.onTap,
    this.onToggleSelect,
    this.onConnect,
    this.onEdit,
    this.onDelete,
    this.onTogglePin,
    this.subtitle,
    this.trailingLabel,
    this.trailingColor,
    this.leadingIcon,
    this.showProbe = false,
    this.lightTheme = false,
    this.menuActions,
  });

  final TerminalAppState appState;
  final HostEntry host;
  final int depth;
  final String query;
  final bool showStatus;
  final bool showPin;
  final bool showCheckbox;
  final bool isSelected;
  final bool readOnly;
  final VoidCallback? onTap;
  final VoidCallback? onToggleSelect;
  final VoidCallback? onConnect;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onTogglePin;
  final String? subtitle;
  final String? trailingLabel;
  final Color? trailingColor;
  final IconData? leadingIcon;
  final bool showProbe;
  final bool lightTheme;
  final List<({String label, VoidCallback? action})>? menuActions;

  @override
  State<HostTreeRow> createState() => _HostTreeRowState();
}

class _HostTreeRowState extends State<HostTreeRow> {
  bool _hovered = false;

  TerminalStatus? get _status {
    if (!widget.showStatus) return null;
    return widget.appState.hostSessionStatus(widget.host.id);
  }

  bool get _isPinned {
    if (!widget.showPin) return false;
    return widget.appState.isHostPinned(widget.host.id);
  }

  Color _statusColor() {
    return switch (_status) {
      TerminalStatus.connected => AppColors.success,
      TerminalStatus.connecting => AppColors.warning,
      TerminalStatus.reconnecting => AppColors.warning,
      TerminalStatus.disconnected || null => AppColors.terminalTreeMuted,
    };
  }

  String? _probeLabel() {
    if (_status == TerminalStatus.connected) return '✓';
    final probe = widget.appState.sessionProbeStateForHost(widget.host.id);
    if (probe == null) return null;
    return switch (probe.status) {
      SessionProbeStatus.probing => '...',
      SessionProbeStatus.reachable when probe.latencyMs != null => '${probe.latencyMs}ms',
      SessionProbeStatus.reachable => '✓',
      SessionProbeStatus.unreachable => '✗',
      SessionProbeStatus.unknown => null,
    };
  }

  Color _probeColor() {
    if (_status == TerminalStatus.connected) return AppColors.success;
    final probe = widget.appState.sessionProbeStateForHost(widget.host.id);
    if (probe == null) return AppColors.terminalTreeMuted;
    return switch (probe.status) {
      SessionProbeStatus.probing => AppColors.warning,
      SessionProbeStatus.reachable => AppColors.success,
      SessionProbeStatus.unreachable => AppColors.error,
      SessionProbeStatus.unknown => AppColors.terminalTreeMuted,
    };
  }

  String _badgeLabel() {
    if (!widget.showStatus) {
      return _connectionTypeLabel();
    }

    final existingSession = widget.appState.terminalSessionForHost(widget.host);
    if (existingSession != null) {
      return switch (_status) {
        TerminalStatus.connected => l(widget.appState, AppStrings.values.connected),
        TerminalStatus.connecting => l(widget.appState, AppStrings.values.connecting),
        TerminalStatus.reconnecting => l(widget.appState, AppStrings.values.reconnecting),
        TerminalStatus.disconnected || null => l(widget.appState, AppStrings.values.disconnected),
      };
    }
    return _connectionTypeLabel();
  }

  String _connectionTypeLabel() {
    return switch (widget.host.connectionType) {
      ConnectionType.ssh => l(widget.appState, AppStrings.values.connectionSsh),
      ConnectionType.serial => l(widget.appState, AppStrings.values.badgeConnectionTypeSerial),
      ConnectionType.telnet => l(widget.appState, AppStrings.values.connectionTelnet),
      ConnectionType.local => switch (widget.host.localShellType) {
        LocalShellType.powershell => l(widget.appState, AppStrings.values.localShellPowerShell),
        LocalShellType.powershellAdmin => l(widget.appState, AppStrings.values.localShellPowerShellAdmin),
        LocalShellType.commandPrompt => l(widget.appState, AppStrings.values.badgeLocalShellCmd),
        LocalShellType.wsl => l(widget.appState, AppStrings.values.localShellWsl),
        LocalShellType.bash => l(widget.appState, AppStrings.values.localShellBash),
        LocalShellType.systemDefault => l(widget.appState, AppStrings.values.badgeLocalShellLocal),
      },
    };
  }

  Future<void> _showHostMenu(BuildContext context, Offset position) async {
    if (widget.readOnly) return;

    final renderBox = Overlay.of(context).context.findRenderObject() as RenderBox;
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & renderBox.size,
      ),
      color: AppColors.cardBackground,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.radiusDialog,
        side: BorderSide(color: AppColors.border),
      ),
      items: [
        if (widget.onConnect != null)
          PopupMenuItem(
            value: 'connect',
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            height: 28,
            child: Row(
              children: [
                Icon(Icons.terminal, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(
                  l(widget.appState, AppStrings.values.connect),
                  style: TextStyle(fontSize: 12, color: AppColors.textPrimary),
                ),
              ],
            ),
          ),
        if (widget.onEdit != null)
          PopupMenuItem(
            value: 'edit',
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            height: 28,
            child: Row(
              children: [
                Icon(Icons.edit, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(
                  l(widget.appState, AppStrings.values.edit),
                  style: TextStyle(fontSize: 12, color: AppColors.textPrimary),
                ),
              ],
            ),
          ),
        if (widget.onTogglePin != null)
          PopupMenuItem(
            value: 'pin',
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            height: 28,
            child: Row(
              children: [
                Icon(Icons.push_pin, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(
                  l(widget.appState, _isPinned ? AppStrings.values.unpin : AppStrings.values.pin),
                  style: TextStyle(fontSize: 12, color: AppColors.textPrimary),
                ),
              ],
            ),
          ),
        if (widget.onDelete != null)
          PopupMenuItem(
            value: 'delete',
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            height: 28,
            child: Row(
              children: [
                Icon(Icons.delete, size: 14, color: AppColors.error),
                const SizedBox(width: 6),
                Text(
                  l(widget.appState, AppStrings.values.delete),
                  style: TextStyle(fontSize: 12, color: AppColors.error),
                ),
              ],
            ),
          ),
      ],
    );

    if (result == null) return;
    switch (result) {
      case 'connect':
        widget.onConnect?.call();
      case 'edit':
        widget.onEdit?.call();
      case 'pin':
        widget.onTogglePin?.call();
      case 'delete':
        widget.onDelete?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = _status == TerminalStatus.connected;
    final indent = (widget.depth * 14 + (widget.showCheckbox ? 0 : 17)).clamp(0, 100).toDouble();

    final hostTextStyle = widget.lightTheme
        ? AppTextStyles.terminalTreeHost.copyWith(color: AppColors.textPrimary)
        : AppTextStyles.terminalTreeHost;
    final mutedColor = widget.lightTheme ? AppColors.grey400 : AppColors.terminalTreeMuted;
    final connectedBg = widget.lightTheme ? const Color(0xFFECFDF5) : AppColors.terminalTreeConnectedBg;
    final hoverBg = widget.lightTheme ? const Color(0xFFF3F4F6) : AppColors.terminalTreeHover;
    final statusColor = widget.lightTheme && _status == null ? AppColors.grey400 : _statusColor();
    final probeFallbackColor = widget.lightTheme ? AppColors.grey400 : AppColors.terminalTreeMuted;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: connected
            ? connectedBg
            : widget.isSelected || _hovered
                ? hoverBg
                : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: GestureDetector(
          onTap: widget.onTap,
          onSecondaryTapDown: (details) =>
              _showHostMenu(context, details.globalPosition),
          child: Padding(
            padding: EdgeInsets.only(left: indent, right: 6),
            child: SizedBox(
              height: widget.subtitle != null ? 38 : 26,
              child: Row(
                children: [
                  if (widget.showCheckbox)
                    Checkbox(
                      value: widget.isSelected,
                      onChanged: (_) => widget.onToggleSelect?.call(),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    )
                  else if (widget.leadingIcon != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(widget.leadingIcon, size: 14, color: AppColors.textSecondary),
                    )
                  else if (widget.showStatus)
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  Expanded(
                    child: widget.subtitle != null
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text.rich(
                                AppTextStyles.highlightSpan(
                                  text: widget.host.name.trim().isEmpty
                                      ? _badgeLabel()
                                      : widget.host.name,
                                  query: widget.query,
                                  baseStyle: hostTextStyle,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                widget.subtitle!,
                                style: AppTextStyles.captionSmall.copyWith(color: AppColors.grey400),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          )
                        : Text.rich(
                            AppTextStyles.highlightSpan(
                              text: widget.host.name.trim().isEmpty
                                  ? _badgeLabel()
                                  : widget.host.name,
                              query: widget.query,
                              baseStyle: hostTextStyle,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                  if (_isPinned && widget.showPin)
                    const SizedBox(width: 4),
                  if (_isPinned && widget.showPin)
                    Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: Icon(
                        Icons.push_pin,
                        size: 12,
                        color: mutedColor,
                      ),
                    ),
                  if (widget.showProbe)
                    const SizedBox(width: 4),
                  if (widget.showProbe)
                    SizedBox(
                      width: 32,
                      child: Text(
                        _probeLabel() ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: AppTextStyles.terminalTreeBadge.copyWith(
                          color: _probeLabel() == null ? probeFallbackColor : _probeColor(),
                          fontSize: 10,
                        ),
                      ),
                    ),
                  const SizedBox(width: 4),
                  Text(
                    widget.trailingLabel ?? _badgeLabel(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: AppTextStyles.terminalTreeBadge.copyWith(
                      color: widget.trailingColor ?? statusColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

