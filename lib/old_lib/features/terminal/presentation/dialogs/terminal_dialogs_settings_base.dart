part of 'terminal_dialogs.dart';

Future<void> showFilesMenu(
  BuildContext context,
  TerminalAppState appState,
  TerminalSession session,
  List<FileNode> nodes,
  Offset position,
) async {
  if (nodes.isEmpty) return;
  final action = await showCompactMenu<_FilesAction>(
    context: context,
    position: position,
    items: [
      if (!session.profile.isLocal)
        compactMenuItem(
          value: _FilesAction.download,
          label: t(context, AppStrings.values.download),
        ),
      compactMenuItem(
        value: _FilesAction.delete,
        label: t(context, AppStrings.values.delete),
      ),
    ],
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case _FilesAction.download:
      final targetDir = await getDirectoryPath();
      if (!context.mounted || targetDir == null) return;
      unawaited(
        appState.downloadFiles(
          session,
          nodes.map((node) => node.path).toList(growable: false),
          targetDir,
        ),
      );
      break;
    case _FilesAction.delete:
      final confirm = await _confirmDialog(
        context,
        t(
          context,
          AppStrings.values.deleteVarItems,
          params: {'count': '${nodes.length}'},
        ),
      );
      if (!context.mounted) return;
      if (confirm) {
        unawaited(appState.deleteEntries(session, nodes));
      }
      break;
  }
}

Future<void> showSettingsDialog(
  BuildContext context,
  TerminalAppState appState,
) async {
  await showDialog<void>(
    context: context,
    builder: (context) {
      return TerminalSettingsPanel(appState: appState);
    },
  );
}

Future<void> confirmDeleteHost(
  BuildContext context,
  TerminalAppState appState,
  HostEntry host,
) async {
  final confirm = await _confirmDialog(
    context,
    t(context, AppStrings.values.deleteVar, params: {'name': host.name}),
  );
  if (confirm) {
    await appState.stopPortForwardsByHost(host.id);
    appState.removeHost(host.id);
  }
}

Future<bool> _confirmDialog(BuildContext context, String message) async {
  final result = await showConfirmDialog(
    context,
    title: t(context, AppStrings.values.confirm),
    message: message,
    confirmText: t(context, AppStrings.values.ok),
    cancelText: t(context, AppStrings.values.cancel),
  );
  return result ?? false;
}

void showHostKeyPromptIfNeeded(
  BuildContext context,
  TerminalAppState appState,
) {
  final prompt = appState.pendingHostKeyPrompt;
  if (prompt == null) {
    return;
  }
  if (!appState.beginHostKeyPromptDialog()) {
    return;
  }
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    if (!context.mounted) {
      appState.resolveHostKeyPrompt(false, remember: false);
      appState.endHostKeyPromptDialog();
      return;
    }
    var remember = true;
    final decision = await showDialog<_HostKeyDecision>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setState) {
            final title = prompt.isChanged
                ? t(dialogContext, AppStrings.values.hostKeyChanged)
                : t(dialogContext, AppStrings.values.firstHostConnection);
            final intro = prompt.isChanged
                ? t(dialogContext, AppStrings.values.hostKeyChangedDesc)
                : t(dialogContext, AppStrings.values.hostKeyNewDesc);
            return AlertDialog(
              backgroundColor: AppColors.cardBackground,
              shape: RoundedRectangleBorder(
                borderRadius: AppRadius.radiusDialog,
              ),
              title: Text(title, style: AppTextStyles.h4),
              content: SizedBox(
                width: 560,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(intro, style: AppTextStyles.body),
                    const SizedBox(height: 10),
                    Text(
                      '${t(dialogContext, AppStrings.values.hostLabel)}: ${prompt.hostDisplayName} (${prompt.hostAddress})',
                      style: AppTextStyles.body,
                    ),
                    const SizedBox(height: 6),
                    Text('${t(dialogContext, AppStrings.values.keyType)}: ${prompt.keyType}',
                      style: AppTextStyles.body,
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      '${t(dialogContext, AppStrings.values.currentFingerprint)}:\n${prompt.fingerprint}',
                      style: AppTextStyles.code,
                    ),
                    if (prompt.isChanged) ...[
                      const SizedBox(height: 10),
                      SelectableText(
                        '${t(dialogContext, AppStrings.values.recordedFingerprint)}:\n${prompt.existedFingerprint}',
                        style: AppTextStyles.code,
                      ),
                    ],
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: remember,
                      onChanged: (value) {
                        setState(() {
                          remember = value ?? true;
                        });
                      },
                      title: Text(
                        t(dialogContext, AppStrings.values.rememberFingerprint),
                        style: AppTextStyles.body,
                      ),
                    ),
                  ],
                ),
              ),
              actionsPadding: const EdgeInsets.all(AppSpacing.lg),
              actions: [
                SecondaryButton(
                  onPressed: () => Navigator.pop(
                    dialogContext,
                    const _HostKeyDecision(trust: false, remember: false),
                  ),
                  label: t(dialogContext, AppStrings.values.reject),
                  size: ButtonSize.medium,
                ),
                const SizedBox(width: AppSpacing.sm),
                PrimaryButton(
                  onPressed: () => Navigator.pop(
                    dialogContext,
                    _HostKeyDecision(trust: true, remember: remember),
                  ),
                  label: t(dialogContext, AppStrings.values.trustAndConnect),
                  size: ButtonSize.medium,
                ),
              ],
            );
          },
        );
      },
    );

    appState.resolveHostKeyPrompt(
      decision?.trust ?? false,
      remember: decision?.remember ?? false,
    );
    appState.endHostKeyPromptDialog();
  });
}
