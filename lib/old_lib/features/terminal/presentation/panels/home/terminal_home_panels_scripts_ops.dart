part of '../terminal_home_panels.dart';

List<LocalShellType> _scriptLocalShellOptions() {
  if (Platform.isWindows) {
    return const [
      LocalShellType.systemDefault,
      LocalShellType.powershell,
      LocalShellType.powershellAdmin,
      LocalShellType.wsl,
      LocalShellType.bash,
    ];
  }
  if (Platform.isLinux || Platform.isMacOS) {
    return const [LocalShellType.systemDefault, LocalShellType.bash];
  }
  if (Platform.isAndroid) {
    return const [LocalShellType.systemDefault];
  }
  return const [];
}

String _scriptLocalShellLabel(TerminalAppState appState, LocalShellType type) {
  switch (type) {
    case LocalShellType.systemDefault:
      return l(appState, AppStrings.values.localShellSystemDefault);
    case LocalShellType.powershell:
      return l(appState, AppStrings.values.localShellPowerShell);
    case LocalShellType.powershellAdmin:
      return l(appState, AppStrings.values.localShellPowerShellAdmin);
    case LocalShellType.commandPrompt:
      return l(appState, AppStrings.values.localShellCommandPrompt);
    case LocalShellType.wsl:
      return l(appState, AppStrings.values.localShellWsl);
    case LocalShellType.bash:
      return l(appState, AppStrings.values.localShellBash);
  }
}

Future<void> showAllScriptHistoryDialog(
  BuildContext context,
  TerminalAppState appState,
) async {
  String selectedScriptId = '';
  await showDialog<void>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          final records = appState.scriptRunHistory.toList(growable: false)
            ..sort((a, b) => b.finishedAt.compareTo(a.finishedAt));
          final scriptIds =
              records
                  .map((item) => item.scriptId)
                  .where((id) => id.isNotEmpty)
                  .toSet()
                  .toList(growable: false)
                ..sort();
          final filtered = selectedScriptId.isEmpty
              ? records
              : records
                    .where((item) => item.scriptId == selectedScriptId)
                    .toList(growable: false);
          return AlertDialog(
            backgroundColor: AppColors.cardBackground,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.radiusDialog),
            actionsPadding: const EdgeInsets.all(AppSpacing.lg),
            title: Text(
              l(appState, AppStrings.values.scriptHistory),
              style: AppTextStyles.h4,
            ),
            content: SizedBox(
              width: 720,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (scriptIds.isNotEmpty)
                    AppDropdownButtonFormField<String>(
                      value: selectedScriptId.isEmpty
                          ? '__all__'
                          : selectedScriptId,
                      label: l(appState, AppStrings.values.scripts),
                      items: [
                        DropdownMenuItem(
                          value: '__all__',
                          child: Text(l(appState, AppStrings.values.all)),
                        ),
                        ...scriptIds.map((scriptId) {
                          final sample = records.firstWhere(
                            (item) => item.scriptId == scriptId,
                            orElse: () => records.first,
                          );
                          final name = sample.scriptName.isEmpty
                              ? scriptId
                              : sample.scriptName;
                          return DropdownMenuItem(
                            value: scriptId,
                            child: Text(name),
                          );
                        }),
                      ],
                      onChanged: (value) {
                        setState(() {
                          if (value == null || value == '__all__') {
                            selectedScriptId = '';
                          } else {
                            selectedScriptId = value;
                          }
                        });
                      },
                    ),
                  const SizedBox(height: 8),
                  if (filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        l(appState, AppStrings.values.noData),
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          final color = item.success
                              ? Colors.green.shade700
                              : Colors.red.shade700;
                          final scriptName = item.scriptName.isEmpty
                              ? item.scriptId
                              : item.scriptName;
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              '$scriptName · ${item.hostName.isEmpty ? item.hostId : item.hostName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${item.finishedAt.toLocal()}\n${item.detail}',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Text(
                              item.success
                                  ? l(appState, AppStrings.values.done)
                                  : l(appState, AppStrings.values.failed),
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        },
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemCount: filtered.length,
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              AppTextButton(
                onPressed: () => Navigator.pop(context),
                label: t(context, AppStrings.values.close),
                size: ButtonSize.small,
              ),
            ],
          );
        },
      );
    },
  );
}

String _scriptFailurePolicyLabel(
  TerminalAppState appState,
  ScriptFailurePolicy policy,
) {
  return switch (policy) {
    ScriptFailurePolicy.continueOnFailure => l(
      appState,
      AppStrings.values.scriptFailurePolicyContinue,
    ),
    ScriptFailurePolicy.stopOnFailure => l(
      appState,
      AppStrings.values.scriptFailurePolicyStop,
    ),
    ScriptFailurePolicy.retryHost => l(
      appState,
      AppStrings.values.scriptFailurePolicyRetryHost,
    ),
  };
}

String _sessionStatusLabel(TerminalAppState appState, TerminalStatus status) {
  switch (status) {
    case TerminalStatus.connected:
      return l(appState, AppStrings.values.connected);
    case TerminalStatus.connecting:
      return l(appState, AppStrings.values.connecting);
    case TerminalStatus.reconnecting:
      return l(appState, AppStrings.values.reconnecting);
    case TerminalStatus.disconnected:
      return l(appState, AppStrings.values.disconnected);
  }
}

String _hostScriptStatusLabel(TerminalAppState appState, String hostId) {
  final status = _hostSessionStatus(appState, hostId);
  if (status == null) {
    return l(appState, AppStrings.values.notStartedAutoConnect);
  }
  return _sessionStatusLabel(appState, status);
}

TerminalStatus? _hostSessionStatus(TerminalAppState appState, String hostId) {
  TerminalStatus? status;
  for (final session in appState.sessions.reversed) {
    if (session.profile.id != hostId) continue;
    status = session.tab.status;
    if (status == TerminalStatus.connected) break;
  }
  return status;
}
