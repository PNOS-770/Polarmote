part of 'terminal_dialogs.dart';

class TerminalSettingsPanel extends StatefulWidget {
  const TerminalSettingsPanel({
    super.key,
    required this.appState,
    this.embedded = false,
    this.mobilePage = false,
    this.initialCategoryIndex = 0,
  });

  final TerminalAppState appState;
  final bool embedded;
  final bool mobilePage;
  final int initialCategoryIndex;

  @override
  State<TerminalSettingsPanel> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<TerminalSettingsPanel> with _ShortcutsTabMixin {
  final List<TextEditingController> _pendingDisposals = [];
  final ScrollController _scrollController = ScrollController();
  int _selectedCategoryIndex = 0;
  String? _scrollToBindingId;

  void _disposeControllerLater(TextEditingController controller) {
    _pendingDisposals.add(controller);
  }

  @override
  void initState() {
    super.initState();
    _selectedCategoryIndex = widget.initialCategoryIndex;
  }

  @override
  void dispose() {
    for (final controller in _pendingDisposals) {
      controller.dispose();
    }
    _scrollController.dispose();
    disposeShortcutsFocus();
    super.dispose();
  }

  String _languageLabel(Locale locale) {
    return locale.languageCode == 'zh'
        ? t(context, AppStrings.values.languageZh)
        : t(context, AppStrings.values.languageEn);
  }

  Future<void> _showTransferRetryDialog(TerminalAppState appState) async {
    final maxAttemptsController = TextEditingController(
      text: '${appState.transferRetryMaxAttempts}',
    );
    final baseDelayController = TextEditingController(
      text: '${appState.transferRetryBaseDelayMs}',
    );
    final maxDelayController = TextEditingController(
      text: '${appState.transferRetryMaxDelayMs}',
    );
    _disposeControllerLater(maxAttemptsController);
    _disposeControllerLater(baseDelayController);
    _disposeControllerLater(maxDelayController);

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.cardBackground,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.radiusDialog,
          ),
          title: Text(
            t(context, AppStrings.values.transferRetryMaxAttempts),
            style: AppTextStyles.h4,
          ),
          content: SizedBox(
            width: (MediaQuery.of(context).size.width - 48).clamp(300.0, 420.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DialogField(
                  label: t(context, AppStrings.values.transferRetryMaxAttempts),
                  controller: maxAttemptsController,
                  keyboardType: TextInputType.number,
                ),
                _DialogField(
                  label: t(context, AppStrings.values.transferRetryBaseDelayMs),
                  controller: baseDelayController,
                  keyboardType: TextInputType.number,
                ),
                _DialogField(
                  label: t(context, AppStrings.values.transferRetryMaxDelayMs),
                  controller: maxDelayController,
                  keyboardType: TextInputType.number,
                ),
              ],
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
    if (saved != true) return;
    appState.setTransferRetryPolicy(
      maxAttempts: int.tryParse(maxAttemptsController.text.trim()),
      baseDelayMs: int.tryParse(baseDelayController.text.trim()),
      maxDelayMs: int.tryParse(maxDelayController.text.trim()),
    );
  }

  Future<void> _exportConfig(TerminalAppState appState) async {
    final location = await getSaveLocation(suggestedName: 'Polarmote-config.json');
    final path = location?.path ?? '';
    if (path.trim().isEmpty) return;
    if (!mounted) return;
    final password = await _showExportEncryptionDialog();
    if (password == null) {
      // User cancelled the entire export operation
      // Actually we need to distinguish "cancel" from "export without encryption"
      // Let's treat null as cancelled, empty string as "no encryption"
      return;
    }
    try {
      await appState.exportPortableStateToPath(
        path,
        masterPassword: password.isEmpty ? null : password,
      );
      appState.addStructuredLog(
        category: TerminalLogCategory.system,
        message: l(appState, AppStrings.values.exported),
      );
    } catch (error) {
      appState.setError(
        l(
          appState,
          AppStrings.values.exportFailedVar,
          params: {'error': '$error'},
        ),
      );
    }
  }

  Future<String?> _showExportEncryptionDialog() async {
    return showDialog<String>(
      context: context,
      builder: (dialogCtx) => const _ExportEncryptionDialog(),
    );
  }

  Future<void> _importConfig(TerminalAppState appState, {String? filePath}) async {
    String? path = filePath;
    if (path == null) {
      final file = await openFile(
        acceptedTypeGroups: [
          XTypeGroup(label: 'json', extensions: const ['json']),
        ],
      );
      if (file == null) return;
      path = file.path;
    }
    if (!mounted) return;
    try {
      final raw = await File(path).readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        appState.setError(
          l(appState, AppStrings.values.importFailedVar, params: {
            'error': 'Invalid format',
          }),
        );
        return;
      }
      final encryptedSecrets = decoded['encryptedSecrets'] as Map<String, dynamic>?;
      String? masterPassword;
      if (encryptedSecrets != null && encryptedSecrets.isNotEmpty) {
        masterPassword = await _showDecryptionDialog();
        if (masterPassword == null) return;
        final decrypted = SecretEncryption.decryptSecrets(
          payload: encryptedSecrets,
          password: masterPassword,
        );
        if (decrypted == null) {
          appState.setError(
            l(appState, AppStrings.values.wrongMasterPassword),
          );
          return;
        }
        await appState.importHostSecretsFromData(decrypted);
      }
    } catch (_) {
      // File read or JSON parse errors handled below in import
    }
    if (!mounted) return;
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.cardBackground,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.radiusDialog,
          ),
          title: Text(
            t(context, AppStrings.values.importConfiguration),
            style: AppTextStyles.h4,
          ),
          content: Text(
            t(context, AppStrings.values.importReplaceCurrentData),
            style: AppTextStyles.body,
          ),
          actionsPadding: const EdgeInsets.all(AppSpacing.lg),
          actions: [
            SecondaryButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              label: t(context, AppStrings.values.merge),
              size: ButtonSize.medium,
            ),
            const SizedBox(width: AppSpacing.sm),
            PrimaryButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              label: t(context, AppStrings.values.replace),
              size: ButtonSize.medium,
            ),
          ],
        );
      },
    );
    try {
      await appState.importPortableStateFromPath(path);
      appState.addStructuredLog(
        category: TerminalLogCategory.system,
        message: l(appState, AppStrings.values.imported),
      );
    } catch (error) {
      appState.setError(
        l(
          appState,
          AppStrings.values.importFailedVar,
          params: {'error': '$error'},
        ),
      );
    }
  }

  Future<String?> _showDecryptionDialog() async {
    final passwordController = TextEditingController();
    String? errorText;
    return showDialog<String>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (stateCtx, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.cardBackground,
              shape: RoundedRectangleBorder(
                borderRadius: AppRadius.radiusDialog,
              ),
              title: Text(
                t(context, AppStrings.values.enterDecryptionPassword),
                style: AppTextStyles.h4,
              ),
              content: SizedBox(
                width: (MediaQuery.of(context).size.width - 48).clamp(300.0, 320.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t(
                        context,
                        AppStrings.values.fileContainsEncryptedSecrets,
                      ),
                      style: AppTextStyles.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        hintText: t(
                          context,
                          AppStrings.values.masterPassword,
                        ),
                        errorText: errorText,
                      ),
                    ),
                  ],
                ),
              ),
              actionsPadding: const EdgeInsets.all(AppSpacing.lg),
              actions: [
                SecondaryButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  label: t(context, AppStrings.values.cancel),
                  size: ButtonSize.medium,
                ),
                const SizedBox(width: AppSpacing.sm),
                PrimaryButton(
                  onPressed: () {
                    final pw = passwordController.text.trim();
                    if (pw.isEmpty) {
                      setDialogState(() {
                        errorText = t(
                          context,
                          AppStrings.values.masterPassword,
                        );
                      });
                      return;
                    }
                    Navigator.pop(dialogCtx, pw);
                  },
                  label: t(context, AppStrings.values.decrypt),
                  size: ButtonSize.medium,
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildGeneralTab(TerminalAppState appState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SettingSwitchRow(
          title: t(context, AppStrings.values.showHiddenFiles),
          value: appState.showHiddenFiles,
          onChanged: appState.setShowHiddenFiles,
        ),
        _SettingSwitchRow(
          title: t(context, AppStrings.values.autoReconnect),
          value: appState.autoReconnect,
          onChanged: appState.setAutoReconnect,
        ),
        _SettingSwitchRow(
          title: t(context, AppStrings.values.confirmPaste),
          value: appState.confirmPaste,
          onChanged: appState.setConfirmPaste,
        ),
        _SettingSwitchRow(
          title: t(context, AppStrings.values.reuseSessionForNewPane),
          value: appState.reuseSessionForNewPane,
          onChanged: appState.setReuseSessionForNewPane,
        ),
        _SettingSwitchRow(
          title: t(context, AppStrings.values.terminalAccessibilitySemantics),
          value: appState.terminalAccessibilitySemanticsEnabled,
          onChanged: appState.setTerminalAccessibilitySemanticsEnabled,
        ),
        _SettingSwitchRow(
          title: t(context, AppStrings.values.terminalHorizontalScroll),
          value: appState.terminalHorizontalScrollEnabled,
          onChanged: appState.setTerminalHorizontalScrollEnabled,
        ),
        _SettingSwitchRow(
          title: t(context, AppStrings.values.showThumbnailBackground),
          value: appState.showThumbnailBackground,
          onChanged: appState.setShowThumbnailBackground,
        ),
        _SettingSwitchRow(
          title: t(context, AppStrings.values.transferAutoRetry),
          value: appState.transferAutoRetryEnabled,
          onChanged: appState.setTransferAutoRetryEnabled,
        ),
        _SettingSwitchRow(
          title: t(context, AppStrings.values.transferResume),
          value: appState.transferResumeEnabled,
          onChanged: appState.setTransferResumeEnabled,
        ),
        _SettingSwitchRow(
          title: t(context, AppStrings.values.broadcast),
          value: appState.broadcastEnabled,
          onChanged: appState.setBroadcastEnabled,
        ),
        _SettingActionRow(
          title: t(context, AppStrings.values.transferRetryMaxAttempts),
          value:
              '${appState.transferRetryMaxAttempts} / ${appState.transferRetryBaseDelayMs}ms / ${appState.transferRetryMaxDelayMs}ms',
          onMoreTapDown: (details) async {
            final action = await showCompactMenu<int>(
              context: context,
              position: details.globalPosition,
              items: [
                compactMenuItem(
                  value: 0,
                  label: t(context, AppStrings.values.edit),
                ),
              ],
            );
            if (action == 0) {
              await _showTransferRetryDialog(appState);
            }
          },
        ),
        _SettingActionRow(
          title: t(context, AppStrings.values.language),
          value: _languageLabel(appState.locale),
          onMoreTapDown: (details) async {
            final action = await showCompactMenu<Locale>(
              context: context,
              position: details.globalPosition,
              items: [
                compactMenuItem(
                  value: const Locale('zh'),
                  label: t(context, AppStrings.values.languageZh),
                ),
                compactMenuItem(
                  value: const Locale('en'),
                  label: t(context, AppStrings.values.languageEn),
                ),
              ],
            );
            if (action != null) {
              appState.setLocale(action);
            }
          },
        ),
        if (defaultTargetPlatform == TargetPlatform.android)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: InkWell(
              onTap: () {
                const MethodChannel('Polarmote/startup_guard')
                    .invokeMethod<void>('openBatteryOptimizationSettings');
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        t(context, AppStrings.values.batteryOptimization),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 18, color: AppColors.textTertiary),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMemoryModeOption(
    TerminalAppState appState,
    MemoryMode mode,
    String title,
    String description,
  ) {
    final isSelected = appState.memoryMode == mode;
    return InkWell(
      onTap: () {
        appState.memoryMode = mode;
        appState.notifyState();
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? TerminalUiPalette.accent.withOpacity(0.1) : Colors.transparent,
          border: Border.all(
            color: isSelected ? TerminalUiPalette.accent : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: isSelected ? TerminalUiPalette.accent : AppColors.textSecondary,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackupTab(TerminalAppState appState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        _ImportDropZone(
          onFileDropped: (path) => _importConfig(appState, filePath: path),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PrimaryButton(
                onPressed: () => _importConfig(appState),
                label: t(context, AppStrings.values.importConfig),
                size: ButtonSize.medium,
                icon: Icons.file_download,
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'or drag and drop a .json file here',
                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SecondaryButton(
          onPressed: () => _exportConfig(appState),
          label: t(context, AppStrings.values.exportConfig),
          size: ButtonSize.medium,
          icon: Icons.file_upload,
        ),
        const SizedBox(height: 24),
        _SectionTitle(label: t(context, AppStrings.values.settingsSnapshots)),
        const SizedBox(height: 8),
        PrimaryButton(
          onPressed: () async {
            await appState.createPortableStateSnapshot();
            appState.addStructuredLog(
              category: TerminalLogCategory.system,
              message: l(appState, AppStrings.values.snapshotCreated),
            );
          },
          icon: Icons.camera_alt_outlined,
          label: t(context, AppStrings.values.createSnapshot),
          size: ButtonSize.medium,
        ),
        const SizedBox(height: 12),
        SecondaryButton(
          onPressed: () async {
            await appState.refreshPortableStateSnapshots();
          },
          label: t(context, AppStrings.values.refresh),
          size: ButtonSize.medium,
          icon: Icons.refresh,
        ),
        const SizedBox(height: 16),
        _buildSnapshotList(appState),
      ],
    );
  }

  Widget _buildSnapshotList(TerminalAppState appState) {
    final items = appState.portableStateSnapshots;
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          t(context, AppStrings.values.noSnapshotsYet),
          style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
        ),
      );
    }
    return Column(
      children: items
          .map((snapshot) {
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: TerminalUiPalette.border),
                color: TerminalUiPalette.pageBackground,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    snapshot.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  if (snapshot.description != null && snapshot.description!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      snapshot.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: TerminalUiPalette.textSecondary),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    snapshot.id,
                    style: const TextStyle(
                      fontSize: 11,
                      color: TerminalUiPalette.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SecondaryButton(
                        onPressed: () => _showEditSnapshotDialog(context, appState, snapshot),
                        label: t(context, AppStrings.values.editSnapshot),
                        size: ButtonSize.small,
                        icon: Icons.edit,
                      ),
                      const SizedBox(height: 8),
                      SecondaryButton(
                        onPressed: () async {
                          await appState.rollbackPortableStateSnapshot(
                            snapshot.id,
                          );
                          appState.addStructuredLog(
                            category: TerminalLogCategory.system,
                            message: l(
                              appState,
                              AppStrings.values.snapshotRolledBack,
                            ),
                          );
                        },
                        label: t(context, AppStrings.values.restoreSnapshot),
                        size: ButtonSize.small,
                        icon: Icons.restore,
                      ),
                      const SizedBox(height: 8),
                      SecondaryButton(
                        onPressed: () async {
                          await appState.deletePortableStateSnapshot(
                            snapshot.id,
                          );
                          appState.addStructuredLog(
                            category: TerminalLogCategory.system,
                            message: l(
                              appState,
                              AppStrings.values.snapshotDeleted,
                            ),
                          );
                        },
                        label: t(context, AppStrings.values.delete),
                        size: ButtonSize.small,
                        icon: Icons.delete_outline,
                      ),
                    ],
                  ),
                ],
              ),
            );
          })
          .toList(growable: false),
    );
  }

  Future<void> _showEditSnapshotDialog(BuildContext ctx, TerminalAppState appState, PortableStateSnapshot snap) async {
    final labelCtrl = TextEditingController(text: snap.label);
    final descCtrl = TextEditingController(text: snap.description ?? '');
    _disposeControllerLater(labelCtrl);
    _disposeControllerLater(descCtrl);
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.radiusDialog,
        ),
        title: Text(t(context, AppStrings.values.editSnapshot), style: AppTextStyles.h4),
        content: SizedBox(
          width: (MediaQuery.of(ctx).size.width - 48).clamp(300.0, 320.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppTextField(
                controller: labelCtrl,
                label: t(context, AppStrings.values.snapshotName),
              ),
              const SizedBox(height: AppSpacing.sm),
              AppTextField(
                controller: descCtrl,
                label: t(context, AppStrings.values.snapshotDescription),
                maxLines: 3,
              ),
            ],
          ),
        ),
        contentPadding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.md, AppSpacing.xl, AppSpacing.md),
        actionsPadding: const EdgeInsets.all(AppSpacing.lg),
        actions: [
          SecondaryButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            label: t(context, AppStrings.values.cancel),
            size: ButtonSize.medium,
          ),
          const SizedBox(width: AppSpacing.sm),
          PrimaryButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            label: t(context, AppStrings.values.snapshotSave),
            size: ButtonSize.medium,
          ),
        ],
      ),
    );
    if (ok == true && labelCtrl.text.trim().isNotEmpty) {
      await appState.updatePortableStateSnapshotMeta(
        snap.id,
        label: labelCtrl.text.trim(),
        description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
      );
      appState.addStructuredLog(
        category: TerminalLogCategory.system,
        message: l(appState, AppStrings.values.snapshotUpdated),
      );
    }
  }

  Widget _buildTerminalTab(TerminalAppState appState) {
    final appearance = appState.globalAppearance;
    final fc = TextEditingController(text: appearance.fontFamily);
    final fsc = TextEditingController(text: appearance.fontSize.toString());
    final lhc = TextEditingController(text: appearance.lineHeight.toString());
    _disposeControllerLater(fc);
    _disposeControllerLater(fsc);
    _disposeControllerLater(lhc);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(label: t(context, AppStrings.values.terminalAppearance)),
        const SizedBox(height: 4),
        _SettingTextField(
          label: t(context, AppStrings.values.terminalFontFamily),
          controller: fc,
          hint: t(context, AppStrings.values.fontFamilyHint),
          onSubmit: (v) {
            final trimmed = v.trim();
            if (trimmed.isNotEmpty) {
              appState.globalAppearance = TerminalAppearanceProfile(
                fontFamily: trimmed,
                fontSize: appearance.fontSize,
                lineHeight: appearance.lineHeight,
                cursorShape: appearance.cursorShape,
              );
              appState.scheduleStateSave();
              appState.notifyState();
            }
          },
        ),
        _SettingTextField(
          label: t(context, AppStrings.values.terminalFontSize),
          controller: fsc,
          hint: '14',
          keyboardType: TextInputType.number,
          onSubmit: (v) {
            final d = double.tryParse(v.trim());
            if (d != null && d > 0 && d <= 48) {
              appState.globalAppearance = TerminalAppearanceProfile(
                fontFamily: appearance.fontFamily,
                fontSize: d,
                lineHeight: appearance.lineHeight,
                cursorShape: appearance.cursorShape,
              );
              appState.scheduleStateSave();
              appState.notifyState();
            }
          },
        ),
        _SettingTextField(
          label: t(context, AppStrings.values.terminalLineHeight),
          controller: lhc,
          hint: '1.25',
          keyboardType: TextInputType.number,
          onSubmit: (v) {
            final d = double.tryParse(v.trim());
            if (d != null && d > 0 && d <= 4) {
              appState.globalAppearance = TerminalAppearanceProfile(
                fontFamily: appearance.fontFamily,
                fontSize: appearance.fontSize,
                lineHeight: d,
                cursorShape: appearance.cursorShape,
              );
              appState.scheduleStateSave();
              appState.notifyState();
            }
          },
        ),
        const SizedBox(height: 8),
        _SectionTitle(label: t(context, AppStrings.values.terminalCursorStyle)),
        const SizedBox(height: 4),
        _buildCursorStylePicker(context, appState, appearance),
        const SizedBox(height: 8),
        _SectionTitle(label: t(context, AppStrings.values.terminalBackgroundImage)),
        if (appState.terminalBackgroundImages.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: SizedBox(
              height: 90,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: appState.terminalBackgroundImages.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) {
                  final image = appState.terminalBackgroundImages[i];
                  final exists = File(image.path).existsSync();
                  return SizedBox(
                    width: 100,
                    child: Card(
                      margin: EdgeInsets.zero,
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: exists
                                ? Image.file(
                                    File(image.path),
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Center(
                                      child: Icon(Icons.broken_image, size: 20, color: AppColors.textTertiary),
                                    ),
                                  )
                                : const Center(
                                    child: Icon(Icons.broken_image, size: 20, color: AppColors.textTertiary),
                                  ),
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: Text(
                                    image.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 9),
                                  ),
                                ),
                              ),
                              InkWell(
                                onTap: () {
                                  appState.removeBackgroundImage(image.id);
                                },
                                child: const Padding(
                                  padding: EdgeInsets.all(2),
                                  child: Icon(Icons.close, size: 12, color: AppColors.textTertiary),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        Row(children: [
          TextButton.icon(
            onPressed: () async {
              final file = await openFile(
                acceptedTypeGroups: [
                  XTypeGroup(label: t(context, AppStrings.values.imageFiles), extensions: const ['png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp']),
                ],
              );
              if (file != null && mounted) {
                await appState.addBackgroundImage(file.path);
              }
            },
            icon: const Icon(Icons.add, size: 14),
            label: Text(t(context, AppStrings.values.addImage)),
          ),
        ]),
        _SettingActionRow(
          title: t(context, AppStrings.values.terminalBackgroundOpacity),
          value: '${(appState.terminalBackgroundOpacity * 100).round()}%',
          onMoreTapDown: (details) async {
            final result = await showDialog<double>(
              context: context,
              builder: (ctx) => SimpleDialog(
                title: Text(t(context, AppStrings.values.terminalBackgroundOpacity)),
                children: List.generate(21, (i) {
                  final val = i * 0.05;
                  return SimpleDialogOption(
                    onPressed: () => Navigator.pop(ctx, val),
                    child: Text('${(val * 100).round()}%'),
                  );
                }),
              ),
            );
            if (result != null) {
              appState.terminalBackgroundOpacity = result;
              appState.scheduleStateSave();
              appState.notifyState();
            }
          },
        ),
        const SizedBox(height: 16),
        _SectionTitle(label: t(context, AppStrings.values.memoryMode)),
        const SizedBox(height: 4),
        _buildMemoryModeOption(
          appState,
          MemoryMode.low,
          t(context, AppStrings.values.memoryModeLow),
          t(context, AppStrings.values.memoryModeLowDesc),
        ),
        _buildMemoryModeOption(
          appState,
          MemoryMode.medium,
          t(context, AppStrings.values.memoryModeMedium),
          t(context, AppStrings.values.memoryModeMediumDesc),
        ),
        _buildMemoryModeOption(
          appState,
          MemoryMode.high,
          t(context, AppStrings.values.memoryModeHigh),
          t(context, AppStrings.values.memoryModeHighDesc),
        ),
        _buildMemoryModeOption(
          appState,
          MemoryMode.custom,
          t(context, AppStrings.values.memoryModeCustom),
          t(context, AppStrings.values.memoryModeCustomDesc),
        ),
        if (appState.memoryMode == MemoryMode.custom) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t(context, AppStrings.values.terminalBufferSize),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: appState.customTerminalBufferSize.toDouble(),
                        min: 1000,
                        max: 50000,
                        divisions: 49,
                        label: '${appState.customTerminalBufferSize}',
                        onChanged: (value) {
                          appState.customTerminalBufferSize = value.toInt();
                          appState.notifyState();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 80,
                      child: Text(
                        '${appState.customTerminalBufferSize} ${t(context, AppStrings.values.terminalBufferSizeLines).replaceAll('{count}', '').trim()}',
                        style: const TextStyle(fontSize: 12),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        _SectionTitle(label: t(context, AppStrings.values.stageCardSize)),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: appState.stageCardMinWidth.toDouble(),
                      min: 160,
                      max: 600,
                      divisions: 44,
                      label: '${appState.stageCardMinWidth}',
                      onChanged: (v) {
                        appState.stageCardMinWidth = v.round();
                        appState.scheduleStateSave();
                        appState.notifyState();
                      },
                    ),
                  ),
                  SizedBox(
                    width: 60,
                    child: Text(
                      '${appState.stageCardMinWidth}px',
                      style: const TextStyle(fontSize: 12),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
              Text(
                t(context, AppStrings.values.stageCardWidth),
                style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: appState.stageCardAspectRatio,
                      min: 0.8,
                      max: 3.0,
                      divisions: 44,
                      label: appState.stageCardAspectRatio.toStringAsFixed(2),
                      onChanged: (v) {
                        appState.stageCardAspectRatio =
                            double.parse(v.toStringAsFixed(2));
                        appState.scheduleStateSave();
                        appState.notifyState();
                      },
                    ),
                  ),
                  SizedBox(
                    width: 60,
                    child: Text(
                      appState.stageCardAspectRatio.toStringAsFixed(2),
                      style: const TextStyle(fontSize: 12),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
              Text(
                t(context, AppStrings.values.stageCardAspect),
                style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildCursorStylePicker(
    BuildContext context,
    TerminalAppState appState,
    TerminalAppearanceProfile appearance,
  ) {
    final options = [
      (TerminalCursorShape.block, AppStrings.values.terminalCursorBlock, Icons.rectangle),
      (TerminalCursorShape.verticalBar, AppStrings.values.terminalCursorVerticalBar, Icons.vertical_align_center),
      (TerminalCursorShape.underline, AppStrings.values.terminalCursorUnderline, Icons.horizontal_rule),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (shape, text, icon) in options)
          GestureDetector(
            onTap: () {
              appState.globalAppearance = TerminalAppearanceProfile(
                fontFamily: appearance.fontFamily,
                fontSize: appearance.fontSize,
                lineHeight: appearance.lineHeight,
                cursorShape: shape,
              );
              appState.scheduleStateSave();
              appState.notifyState();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: appearance.cursorShape == shape
                    ? AppColors.primaryLight.withValues(alpha: 0.12)
                    : AppColors.backgroundGrey,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: appearance.cursorShape == shape
                      ? AppColors.primaryLight
                      : AppColors.border,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16,
                    color: appearance.cursorShape == shape
                        ? AppColors.primaryLight
                        : AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    t(context, text),
                    style: AppTextStyles.caption.copyWith(
                      color: appearance.cursorShape == shape
                          ? AppColors.primaryLight
                          : AppColors.textPrimary,
                      fontWeight: appearance.cursorShape == shape
                          ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSettingsContent(BuildContext context) {
    _scrollToBinding(widget.appState, _scrollController);

    final categories = _settingsCategories(context);

    if (_selectedCategoryIndex >= categories.length) {
      _selectedCategoryIndex = 0;
    }

    return Row(
      children: [
        SizedBox(
          width: 200,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            itemCount: categories.length,
            itemBuilder: (context, index) {
                    final info = categories[index];
                    final selected = index == _selectedCategoryIndex;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Material(
                        color: selected
                            ? TerminalUiPalette.accentSelectedLight
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => setState(() => _selectedCategoryIndex = index),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  info.icon,
                                  size: 18,
                                  color: selected
                                      ? AppColors.primaryLight
                                      : TerminalUiPalette.textSecondary,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    info.title,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                                      color: selected
                                          ? AppColors.primaryLight
                                          : TerminalUiPalette.textPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        const VerticalDivider(width: 1, thickness: 1),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
            child: SingleChildScrollView(
              controller: _scrollController,
              child: categories[_selectedCategoryIndex].builder(),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return _buildSettingsContent(context);
    }

    final isMobile = !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

    if (isMobile) {
      if (widget.mobilePage) {
        if (_mobileDrillDownIndex == 0) {
          return _buildMobileCategoryList();
        }
        return _buildMobileCategoryContent();
      }
      return _buildDesktopDialog();
    }

    return _buildDesktopDialog();
  }

  int _mobileDrillDownIndex = 0;

  Widget _buildMobileCategoryList() {
    final categories = _settingsCategories(context);
    return Scaffold(
      backgroundColor: AppColors.cardBackground,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundGrey,
        title: Text(t(context, AppStrings.values.settings), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        leading: IconButton(
          icon: Icon(Icons.close, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
        itemBuilder: (ctx, i) {
          final cat = categories[i];
          return ListTile(
            leading: Icon(cat.icon, size: 20, color: AppColors.textPrimary),
            title: Text(cat.title, style: const TextStyle(fontSize: 14, color: AppColors.textPrimary)),
            trailing: Icon(Icons.chevron_right, size: 18, color: AppColors.textSecondary),
            onTap: () => setState(() => _mobileDrillDownIndex = i + 1),
          );
        },
      ),
    );
  }

  Widget _buildMobileCategoryContent() {
    final categories = _settingsCategories(context);
    final cat = categories[_mobileDrillDownIndex - 1];
    return Scaffold(
      backgroundColor: AppColors.cardBackground,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundGrey,
        title: Text(cat.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => setState(() => _mobileDrillDownIndex = 0),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: cat.builder(),
      ),
    );
  }

  Widget _buildDesktopDialog() {
    return AlertDialog(
      backgroundColor: AppColors.cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.radiusDialog,
      ),
      title: Text(t(context, AppStrings.values.settings), style: AppTextStyles.h4),
      content: SizedBox(
        width: 720,
        height: 600,
        child: _buildSettingsContent(context),
      ),
      actionsPadding: const EdgeInsets.all(AppSpacing.lg),
      actions: [
        PrimaryButton(
          onPressed: () => Navigator.pop(context),
          label: t(context, AppStrings.values.close),
          size: ButtonSize.medium,
        ),
      ],
    );
  }

  List<_CategoryInfo> _settingsCategories(BuildContext context) {
    return [
      _CategoryInfo(
        title: t(context, AppStrings.values.settingsGeneral),
        icon: Icons.tune,
        builder: () => _buildGeneralTab(widget.appState),
      ),
      _CategoryInfo(
        title: t(context, AppStrings.values.settingsTerminal),
        icon: Icons.terminal,
        builder: () => _buildTerminalTab(widget.appState),
      ),
      _CategoryInfo(
        title: t(context, AppStrings.values.settingsConfigBackup),
        icon: Icons.backup,
        builder: () => _buildBackupTab(widget.appState),
      ),
      _CategoryInfo(
        title: t(context, AppStrings.values.shortcutsTab),
        icon: Icons.keyboard,
        builder: () => _buildShortcutsTab(widget.appState),
      ),
    ];
  }

}

class _ImportDropZone extends StatefulWidget {
  final Widget child;
  final ValueChanged<String> onFileDropped;

  const _ImportDropZone({
    required this.child,
    required this.onFileDropped,
  });

  @override
  State<_ImportDropZone> createState() => _ImportDropZoneState();
}

class _ImportDropZoneState extends State<_ImportDropZone> {
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    return DropRegion(
      formats: const [Formats.fileUri],
      hitTestBehavior: HitTestBehavior.opaque,
      onDropOver: (event) {
        setState(() => _dragging = true);
        return DropOperation.copy;
      },
      onDropLeave: (_) {
        setState(() => _dragging = false);
      },
      onDropEnded: (_) {
        setState(() => _dragging = false);
      },
      onPerformDrop: (event) async {
        setState(() => _dragging = false);
        for (final item in event.session.items) {
          if (!item.canProvide(Formats.fileUri)) continue;
          final reader = item.dataReader;
          if (reader == null) continue;
          final completer = Completer<Uri?>();
          final dynamicReader = reader;
          dynamicReader.getValue<Uri>(
            Formats.fileUri,
            (value) {
              if (!completer.isCompleted) completer.complete(value);
            },
            onError: (_) {
              if (!completer.isCompleted) completer.complete(null);
            },
          );
          final uri = await completer.future;
          if (uri != null) {
            final path = uri.toFilePath(windows: true);
            if (path.endsWith('.json')) {
              widget.onFileDropped(path);
              return;
            }
          }
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _dragging ? AppColors.primaryLight : Colors.transparent,
            width: 2,
            style: _dragging ? BorderStyle.solid : BorderStyle.none,
          ),
          color: _dragging ? AppColors.primaryLight.withValues(alpha: 0.05) : Colors.transparent,
        ),
        child: widget.child,
      ),
    );
  }
}

class _ExportEncryptionDialog extends StatefulWidget {
  const _ExportEncryptionDialog();

  @override
  State<_ExportEncryptionDialog> createState() =>
      _ExportEncryptionDialogState();
}

class _ExportEncryptionDialogState extends State<_ExportEncryptionDialog> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  var _includeEncrypted = false;
  String? _errorText;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.radiusDialog,
      ),
      title: Text(
        t(context, AppStrings.values.exportConfig),
        style: AppTextStyles.h4,
      ),
      content: SizedBox(
        width: (MediaQuery.of(context).size.width - 48).clamp(300.0, 320.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: _includeEncrypted,
                    onChanged: (v) {
                      setState(() {
                        _includeEncrypted = v ?? false;
                        _errorText = null;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t(
                      context,
                      AppStrings.values.includeEncryptedSecrets,
                    ),
                    style: AppTextStyles.body,
                  ),
                ),
              ],
            ),
            if (_includeEncrypted) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: t(
                    context,
                    AppStrings.values.masterPassword,
                  ),
                  errorText: _errorText,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmController,
                obscureText: true,
                decoration: InputDecoration(
                  hintText: t(
                    context,
                    AppStrings.values.confirmMasterPassword,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.all(AppSpacing.lg),
      actions: [
        SecondaryButton(
          onPressed: () => Navigator.pop(context),
          label: t(context, AppStrings.values.cancel),
          size: ButtonSize.medium,
        ),
        const SizedBox(width: AppSpacing.sm),
        PrimaryButton(
          onPressed: () {
            if (_includeEncrypted) {
              final pw = _passwordController.text.trim();
              final confirm = _confirmController.text.trim();
              if (pw.isEmpty || pw != confirm) {
                setState(() {
                  _errorText = t(
                    context,
                    AppStrings.values.passwordsDoNotMatch,
                  );
                });
                return;
              }
              Navigator.pop(context, pw);
            } else {
              Navigator.pop(context, '');
            }
          },
          label: t(context, AppStrings.values.exportConfig),
          size: ButtonSize.medium,
        ),
      ],
    );
  }
}

