part of 'terminal_dialogs.dart';

extension _SettingsDialogPortForwardTemplates on _SettingsDialogState {
  Future<void> _savePortForwardAsTemplate(
    TerminalAppState appState,
    PortForwardEntry entry,
  ) async {
    final nameController = TextEditingController(text: entry.name);
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
              t(context, AppStrings.values.saveAsTemplate),
              style: AppTextStyles.h4,
            ),
            content: SizedBox(
              width: 420,
              child: _DialogField(
                label: t(context, AppStrings.values.name),
                controller: nameController,
              ),
            ),
            actionsPadding: const EdgeInsets.all(AppSpacing.lg),
            actions: [
              SecondaryButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                label: t(context, AppStrings.values.cancel),
                size: ButtonSize.medium,
              ),
              const SizedBox(width: AppSpacing.sm),
              PrimaryButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                label: t(context, AppStrings.values.save),
                size: ButtonSize.medium,
              ),
            ],
          );
        },
      );
      if (confirmed != true) {
        return;
      }
      final templateName = nameController.text.trim();
      if (templateName.isEmpty) {
        return;
      }
      final template = appState.buildTemplateFromPortForwardEntry(
        entry,
        name: templateName,
      );
      appState.upsertPortForwardTemplate(template);
    } finally {
      _disposeControllerLater(nameController);
    }
  }

  Future<bool> _confirmDeleteNamedItem(String name) async {
    final target = name.trim().isEmpty ? '-' : name.trim();
    final confirmed = await showConfirmDialog(
      context,
      title: t(context, AppStrings.values.delete),
      message: t(context, AppStrings.values.deleteVar, params: {'name': target}),
      confirmText: t(context, AppStrings.values.delete),
      cancelText: t(context, AppStrings.values.cancel),
      destructive: true,
    );
    return confirmed == true;
  }

  Future<void> _showPortForwardTemplatesDialog(
    TerminalAppState appState,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setState) {
            final templates = appState.portForwardTemplates.toList(
              growable: false,
            )..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
            return AlertDialog(
              backgroundColor: AppColors.cardBackground,
              shape: RoundedRectangleBorder(
                borderRadius: AppRadius.radiusDialog,
              ),
              title: Text(
                t(context, AppStrings.values.portForwardTemplates),
                style: AppTextStyles.h4,
              ),
              content: SizedBox(
                width: 620,
                child: templates.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          t(context, AppStrings.values.noPortForwardTemplates),
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: templates
                              .map((template) {
                                final typeLabel = _portForwardTypeLabel(
                                  context,
                                  template.type,
                                );
                                final mappingLabel = switch (template.type) {
                                  PortForwardType.local =>
                                    '${template.localHost}:${template.localPort} -> '
                                        '${template.remoteHost}:${template.remotePort}',
                                  PortForwardType.reverse =>
                                    '${template.remoteHost}:${template.remotePort} -> '
                                        '${template.localHost}:${template.localPort}',
                                  PortForwardType.socks =>
                                    '${template.localHost}:${template.localPort}',
                                };
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: TerminalUiPalette.pageBackground,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: TerminalUiPalette.border,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              template.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color:
                                                  TerminalUiPalette.accentSoft,
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              typeLabel,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: TerminalUiPalette.accent,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        mappingLabel,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[700],
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: [
                                          SecondaryButton(
                                            onPressed: () {
                                              Navigator.pop(dialogContext);
                                              unawaited(
                                                _showPortForwardDialog(
                                                  appState,
                                                  initialTemplate: template,
                                                ),
                                              );
                                            },
                                            label: t(
                                              context,
                                              AppStrings.values.useTemplate,
                                            ),
                                            size: ButtonSize.small,
                                          ),
                                          AppTextButton(
                                            onPressed: () => unawaited(() async {
                                              final confirmed =
                                                  await _confirmDeleteNamedItem(
                                                    template.name,
                                                  );
                                              if (!confirmed) {
                                                return;
                                              }
                                              appState
                                                  .removePortForwardTemplate(
                                                    template.id,
                                                  );
                                              setState(() {});
                                            }()),
                                            label: t(
                                              context,
                                              AppStrings.values.delete,
                                            ),
                                            size: ButtonSize.small,
                                            color: AppColors.error,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              })
                              .toList(growable: false),
                        ),
                      ),
              ),
              actionsPadding: const EdgeInsets.all(AppSpacing.lg),
              actions: [
                PrimaryButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  label: t(context, AppStrings.values.close),
                  size: ButtonSize.medium,
                ),
              ],
            );
          },
        );
      },
    );
  }
}
