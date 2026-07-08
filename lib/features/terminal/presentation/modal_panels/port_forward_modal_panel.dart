import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../shared/design_system/design_system.dart';
import '../../../../shared/constants/app_string.dart';
import '../../models/port_forward_entry.dart';
import '../../state/terminal_app_state.dart';
import '../common/terminal_localization.dart';
import 'modal_panel_base.dart';

class PortForwardModalPanel extends StatefulWidget {
  const PortForwardModalPanel({super.key});

  @override
  State<PortForwardModalPanel> createState() => _PortForwardModalPanelState();

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => const PortForwardModalPanel(),
    );
  }
}

class _PortForwardModalPanelState extends State<PortForwardModalPanel> {
  final List<TextEditingController> _pendingDisposals = [];

  void _disposeControllerLater(TextEditingController c) {
    _pendingDisposals.add(c);
  }

  @override
  void dispose() {
    for (final c in _pendingDisposals) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<TerminalAppState>(context);
    return ModalPanelBase(
      title: l(appState, AppStrings.values.settingsPortForwarding),
      width: 800,
      height: 600,
      actions: [
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          iconSize: 20,
          tooltip: l(appState, AppStrings.values.add),
          onPressed: () => unawaited(_showAddDialog(appState)),
        ),
        IconButton(
          icon: const Icon(Icons.play_arrow),
          iconSize: 20,
          tooltip: l(appState, AppStrings.values.startAll),
          onPressed: () => unawaited(appState.startAllPortForwards()),
        ),
        IconButton(
          icon: const Icon(Icons.stop),
          iconSize: 20,
          tooltip: l(appState, AppStrings.values.stopAll),
          onPressed: () => unawaited(appState.stopAllPortForwards()),
        ),
      ],
      child: _buildContent(appState),
    );
  }

  Widget _buildContent(TerminalAppState appState) {
    final rules = appState.portForwards.toList(growable: false);
    if (rules.isEmpty) {
      return Center(
        child: Text(
          l(appState, AppStrings.values.noPortForwardRules),
          style: AppTextStyles.secondary,
        ),
      );
    }
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final views = appState.portForwardViews();
        return ListView.builder(
          padding: const EdgeInsets.all(AppSpacing.md),
          itemCount: views.length,
          itemBuilder: (context, index) {
            final view = views[index];
            return _buildRuleCard(appState, view);
          },
        );
      },
    );
  }

  Widget _buildRuleCard(TerminalAppState appState, PortForwardRuntimeView view) {
    final entry = view.entry;
    final status = view.status;
    final localDisplay = '${entry.localHost}:${entry.localPort}';
    final remoteDisplay = entry.type == PortForwardType.socks
        ? l(appState, AppStrings.values.portForwardingSocks)
        : '${entry.remoteHost}:${entry.remotePort}';
    final isRunning = status == PortForwardRuntimeStatus.running;

    Color statusColor;
    String statusText;
    switch (status) {
      case PortForwardRuntimeStatus.running:
        statusColor = AppColors.success;
        statusText = view.boundPort != null
            ? l(appState, AppStrings.values.portForwardingBoundPort,
                params: {'port': '${view.boundPort}'})
            : l(appState, AppStrings.values.running);
      case PortForwardRuntimeStatus.starting:
        statusColor = AppColors.warning;
        statusText = l(appState, AppStrings.values.connecting);
      case PortForwardRuntimeStatus.error:
        statusColor = AppColors.error;
        statusText = l(appState, AppStrings.values.error);
      case PortForwardRuntimeStatus.stopped:
        statusColor = AppColors.textTertiary;
        statusText = l(appState, AppStrings.values.stopped);
    }

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entry.name,
                    style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                _typeBadge(appState, entry.type),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.arrow_forward, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(localDisplay, style: AppTextStyles.code),
                const SizedBox(width: 4),
                Icon(Icons.arrow_forward, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(remoteDisplay, style: AppTextStyles.code),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(statusText, style: AppTextStyles.caption.copyWith(color: statusColor)),
                const Spacer(),
                _actionButton(
                  Icons.edit,
                  l(appState, AppStrings.values.edit),
                  () => unawaited(_showEditDialog(appState, entry)),
                ),
                _actionButton(
                  isRunning ? Icons.stop : Icons.play_arrow,
                  isRunning
                      ? l(appState, AppStrings.values.stop)
                      : l(appState, AppStrings.values.start),
                  () {
                    if (isRunning) {
                      appState.stopPortForward(entry.id);
                    } else {
                      appState.startPortForward(entry.id);
                    }
                  },
                ),
                _actionButton(
                  Icons.delete,
                  l(appState, AppStrings.values.delete),
                  () => unawaited(_confirmDelete(appState, entry)),
                  color: AppColors.error,
                ),
              ],
            ),
            if (status == PortForwardRuntimeStatus.error && view.lastError != null) ...[
              const SizedBox(height: 4),
              Text(
                view.lastError ?? '',
                style: AppTextStyles.error,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _typeBadge(TerminalAppState appState, PortForwardType type) {
    final label = switch (type) {
      PortForwardType.local => l(appState, AppStrings.values.portForwardingLocal),
      PortForwardType.reverse => l(appState, AppStrings.values.portForwardingReverse),
      PortForwardType.socks => l(appState, AppStrings.values.portForwardingSocks),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primaryLight.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: AppTextStyles.captionSmall.copyWith(
          color: AppColors.primaryLight,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _actionButton(IconData icon, String tooltip, VoidCallback onPressed, {Color? color}) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Icon(icon, size: 16, color: color ?? AppColors.textSecondary),
        ),
      ),
    );
  }

  Future<void> _showAddDialog(TerminalAppState appState) =>
      _showPortForwardDialog(appState, null);

  Future<void> _showEditDialog(TerminalAppState appState, PortForwardEntry entry) =>
      _showPortForwardDialog(appState, entry);

  Future<void> _showPortForwardDialog(
    TerminalAppState appState,
    PortForwardEntry? initial,
  ) async {
    final nameController = TextEditingController(text: initial?.name ?? '');
    final localHostController = TextEditingController(
      text: initial?.localHost ?? '127.0.0.1',
    );
    final localPortController = TextEditingController(
      text: '${initial?.localPort ?? 0}',
    );
    final remoteHostController = TextEditingController(
      text: initial?.remoteHost ?? '',
    );
    final remotePortController = TextEditingController(
      text: '${initial?.remotePort ?? 0}',
    );
    _disposeControllerLater(nameController);
    _disposeControllerLater(localHostController);
    _disposeControllerLater(localPortController);
    _disposeControllerLater(remoteHostController);
    _disposeControllerLater(remotePortController);

    PortForwardType type = initial?.type ?? PortForwardType.local;
    bool autoStart = initial?.autoStart ?? false;
    String hostId = initial?.hostId ?? '';
    if (hostId.isEmpty) {
      final availableHosts = appState.availablePortForwardHosts();
      if (availableHosts.isNotEmpty) {
        hostId = availableHosts.first.id;
      }
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setState) {
            final availableHosts = appState.availablePortForwardHosts();
            final isReverse = type == PortForwardType.reverse;
            final isSocks = type == PortForwardType.socks;
            return AlertDialog(
              backgroundColor: AppColors.cardBackground,
              shape: RoundedRectangleBorder(
                borderRadius: AppRadius.radiusDialog,
              ),
              title: Text(
                initial == null
                    ? l(appState, AppStrings.values.addPortForwardRule)
                    : l(appState, AppStrings.values.editPortForwardRule),
                style: AppTextStyles.h4,
              ),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppTextField(
                        controller: nameController,
                        label: l(appState, AppStrings.values.name),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        l(appState, AppStrings.values.portForwardType),
                        style: AppTextStyles.label,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceCard(
                            label: l(appState, AppStrings.values.portForwardTypeLocal),
                            selected: type == PortForwardType.local,
                            onTap: () => setState(() => type = PortForwardType.local),
                          ),
                          ChoiceCard(
                            label: l(appState, AppStrings.values.portForwardTypeReverse),
                            selected: type == PortForwardType.reverse,
                            onTap: () => setState(() => type = PortForwardType.reverse),
                          ),
                          ChoiceCard(
                            label: l(appState, AppStrings.values.portForwardTypeSocks),
                            selected: type == PortForwardType.socks,
                            onTap: () => setState(() => type = PortForwardType.socks),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (availableHosts.isEmpty)
                        Text(
                          l(appState, AppStrings.values.noSshHostsAvailable),
                          style: AppTextStyles.secondarySmall,
                        )
                      else
                        DropdownButtonFormField<String>(
                          initialValue: hostId.isEmpty ? null : hostId,
                          decoration: InputDecoration(
                            labelText: l(appState, AppStrings.values.sshHost),
                          ),
                          items: availableHosts
                              .map((host) => DropdownMenuItem<String>(
                                    value: host.id,
                                    child: Text(host.name),
                                  ))
                              .toList(growable: false),
                          onChanged: (value) {
                            setState(() => hostId = value ?? '');
                          },
                        ),
                      const SizedBox(height: 6),
                      AppTextField(
                        controller: localHostController,
                        label: isReverse
                            ? l(appState, AppStrings.values.localTargetHost)
                            : l(appState, AppStrings.values.localHost),
                      ),
                      AppTextField(
                        controller: localPortController,
                        label: isReverse
                            ? l(appState, AppStrings.values.localTargetPort)
                            : l(appState, AppStrings.values.localPort),
                      ),
                      if (!isSocks) ...[
                        AppTextField(
                          controller: remoteHostController,
                          label: isReverse
                              ? l(appState, AppStrings.values.remoteBindHost)
                              : l(appState, AppStrings.values.remoteHost),
                        ),
                        AppTextField(
                          controller: remotePortController,
                          label: isReverse
                              ? l(appState, AppStrings.values.remoteBindPort)
                              : l(appState, AppStrings.values.remotePort),
                        ),
                      ],
                      SettingSwitchRow(
                        title: l(appState, AppStrings.values.autoStart),
                        value: autoStart,
                        onChanged: (v) => setState(() => autoStart = v),
                      ),
                    ],
                  ),
                ),
              ),
              actionsPadding: const EdgeInsets.all(AppSpacing.lg),
              actions: [
                SecondaryButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  label: l(appState, AppStrings.values.cancel),
                  size: ButtonSize.medium,
                ),
                const SizedBox(width: AppSpacing.sm),
                PrimaryButton(
                  onPressed: () {
                    if (nameController.text.trim().isEmpty ||
                        hostId.trim().isEmpty ||
                        localHostController.text.trim().isEmpty) {
                      return;
                    }
                    final localPort =
                        int.tryParse(localPortController.text.trim()) ?? 0;
                    final remotePort =
                        int.tryParse(remotePortController.text.trim()) ?? 0;
                    if (localPort <= 0 || localPort > 65535) return;
                    if (!isSocks && ((!isReverse && remoteHostController.text.trim().isEmpty) || remotePort <= 0 || remotePort > 65535)) return;
                    Navigator.pop(dialogContext, true);
                  },
                  label: l(appState, AppStrings.values.save),
                  size: ButtonSize.medium,
                ),
              ],
            );
          },
        );
      },
    );

    if (saved != true) return;

    appState.upsertPortForwardEntry(PortForwardEntry(
      id: initial?.id ?? 'pf-${DateTime.now().microsecondsSinceEpoch}',
      name: nameController.text.trim(),
      hostId: hostId.trim(),
      localHost: localHostController.text.trim(),
      localPort: int.tryParse(localPortController.text.trim()) ?? 0,
      remoteHost: type == PortForwardType.socks
          ? ''
          : (type == PortForwardType.reverse && remoteHostController.text.trim().isEmpty
              ? '127.0.0.1'
              : remoteHostController.text.trim()),
      remotePort: type == PortForwardType.socks
          ? 0
          : (int.tryParse(remotePortController.text.trim()) ?? 0),
      createdAt: initial?.createdAt ?? DateTime.now(),
      autoStart: autoStart,
      type: type,
    ));
  }

  Future<void> _confirmDelete(TerminalAppState appState, PortForwardEntry entry) async {
    final confirmed = await showConfirmDialog(
      context,
      title: l(appState, AppStrings.values.delete),
      message: l(appState, AppStrings.values.deleteVar, params: {'name': entry.name}),
      confirmText: l(appState, AppStrings.values.delete),
      cancelText: l(appState, AppStrings.values.cancel),
      destructive: true,
    );
    if (confirmed == true) {
      appState.removePortForwardEntry(entry.id);
    }
  }
}

