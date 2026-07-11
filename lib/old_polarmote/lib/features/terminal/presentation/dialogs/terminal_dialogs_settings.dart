part of 'terminal_dialogs.dart';

class TerminalSettingsPanel extends StatefulWidget {
  const TerminalSettingsPanel({
    super.key,
    required this.appState,
    this.embedded = false,
  });

  final TerminalAppState appState;
  final bool embedded;

  @override
  State<TerminalSettingsPanel> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<TerminalSettingsPanel> {
  final List<TextEditingController> _pendingDisposals = [];
  final ScrollController _scrollController = ScrollController();
  String _searchQuery = '';
  String _logQuery = '';
  String _shortcutSearchQuery = '';
  String? _editingScriptShortcutKey;
  final FocusNode _scriptCaptureFocus = FocusNode();

  void _disposeControllerLater(TextEditingController controller) {
    _pendingDisposals.add(controller);
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    for (final controller in _pendingDisposals) {
      controller.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  String _portForwardTypeLabel(BuildContext context, PortForwardType type) {
    return switch (type) {
      PortForwardType.local => t(
        context,
        AppStrings.values.portForwardTypeLocal,
      ),
      PortForwardType.reverse => t(
        context,
        AppStrings.values.portForwardTypeReverse,
      ),
      PortForwardType.socks => t(
        context,
        AppStrings.values.portForwardTypeSocks,
      ),
    };
  }

  String _homeLayoutLabel(BuildContext context, HomeLayoutMode mode) {
    return switch (mode) {
      HomeLayoutMode.mobile => t(context, AppStrings.values.homeLayoutMobile),
      HomeLayoutMode.desktop => t(context, AppStrings.values.homeLayoutDesktop),
    };
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
            width: 420,
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

  Future<void> _showPortForwardDialog(
    TerminalAppState appState, {
    PortForwardEntry? initial,
    PortForwardTemplate? initialTemplate,
  }) async {
    final now = DateTime.now();
    final nameController = TextEditingController(
      text: initial?.name ?? initialTemplate?.name ?? '',
    );
    final localHostController = TextEditingController(
      text: initial?.localHost ?? initialTemplate?.localHost ?? '127.0.0.1',
    );
    final localPortController = TextEditingController(
      text: '${initial?.localPort ?? initialTemplate?.localPort ?? 0}',
    );
    final remoteHostController = TextEditingController(
      text: initial?.remoteHost ?? initialTemplate?.remoteHost ?? '',
    );
    final remotePortController = TextEditingController(
      text: '${initial?.remotePort ?? initialTemplate?.remotePort ?? 0}',
    );
    PortForwardType type =
        initial?.type ?? initialTemplate?.type ?? PortForwardType.local;
    bool autoStart = initial?.autoStart ?? false;
    String hostId = initial?.hostId ?? '';
    if (hostId.isEmpty) {
      final availableHosts = appState.availablePortForwardHosts();
      if (availableHosts.isNotEmpty) {
        hostId = availableHosts.first.id;
      }
    }
    _disposeControllerLater(nameController);
    _disposeControllerLater(localHostController);
    _disposeControllerLater(localPortController);
    _disposeControllerLater(remoteHostController);
    _disposeControllerLater(remotePortController);

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setState) {
            final availableHosts = appState.availablePortForwardHosts();
            final isReverse = type == PortForwardType.reverse;
            final isSocks = type == PortForwardType.socks;
            final hint = isReverse
                ? t(context, AppStrings.values.portForwardReverseHint)
                : isSocks
                ? t(context, AppStrings.values.portForwardSocksHint)
                : null;
            return AlertDialog(
              backgroundColor: AppColors.cardBackground,
              shape: RoundedRectangleBorder(
                borderRadius: AppRadius.radiusDialog,
              ),
              title: Text(
                initial == null
                    ? t(context, AppStrings.values.addPortForwardRule)
                    : t(context, AppStrings.values.editPortForwardRule),
                style: AppTextStyles.h4,
              ),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DialogField(
                        label: t(context, AppStrings.values.name),
                        controller: nameController,
                      ),
                      _SectionTitle(
                        label: t(context, AppStrings.values.portForwardType),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _ChoiceCard(
                            label: t(
                              context,
                              AppStrings.values.portForwardTypeLocal,
                            ),
                            icon: const Icon(Icons.call_split, size: 18),
                            selected: type == PortForwardType.local,
                            onTap: () =>
                                setState(() => type = PortForwardType.local),
                          ),
                          _ChoiceCard(
                            label: t(
                              context,
                              AppStrings.values.portForwardTypeReverse,
                            ),
                            icon: const Icon(Icons.compare_arrows, size: 18),
                            selected: type == PortForwardType.reverse,
                            onTap: () =>
                                setState(() => type = PortForwardType.reverse),
                          ),
                          _ChoiceCard(
                            label: t(
                              context,
                              AppStrings.values.portForwardTypeSocks,
                            ),
                            icon: const Icon(Icons.route, size: 18),
                            selected: type == PortForwardType.socks,
                            onTap: () =>
                                setState(() => type = PortForwardType.socks),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (availableHosts.isEmpty)
                        Text(
                          t(context, AppStrings.values.noSshHostsAvailable),
                          style: TextStyle(color: Colors.grey[700]),
                        )
                      else
                        DropdownButtonFormField<String>(
                          initialValue: hostId.isEmpty ? null : hostId,
                          decoration: InputDecoration(
                            labelText: t(context, AppStrings.values.sshHost),
                          ),
                          items: availableHosts
                              .map(
                                (host) => DropdownMenuItem<String>(
                                  value: host.id,
                                  child: Text(host.name),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (value) {
                            setState(() {
                              hostId = value ?? '';
                            });
                          },
                        ),
                      const SizedBox(height: 6),
                      _DialogField(
                        label: isReverse
                            ? t(context, AppStrings.values.localTargetHost)
                            : t(context, AppStrings.values.localHost),
                        controller: localHostController,
                      ),
                      _DialogField(
                        label: isReverse
                            ? t(context, AppStrings.values.localTargetPort)
                            : t(context, AppStrings.values.localPort),
                        controller: localPortController,
                        keyboardType: TextInputType.number,
                      ),
                      if (!isSocks) ...[
                        _DialogField(
                          label: isReverse
                              ? t(context, AppStrings.values.remoteBindHost)
                              : t(context, AppStrings.values.remoteHost),
                          controller: remoteHostController,
                        ),
                        _DialogField(
                          label: isReverse
                              ? t(context, AppStrings.values.remoteBindPort)
                              : t(context, AppStrings.values.remotePort),
                          controller: remotePortController,
                          keyboardType: TextInputType.number,
                        ),
                      ],
                      if (hint != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          hint,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(t(context, AppStrings.values.autoStart)),
                        value: autoStart,
                        onChanged: (value) {
                          setState(() {
                            autoStart = value;
                          });
                        },
                      ),
                    ],
                  ),
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
                    if (localPort <= 0 || localPort > 65535) {
                      return;
                    }
                    if (!isSocks &&
                        ((!isReverse &&
                                remoteHostController.text.trim().isEmpty) ||
                            remotePort <= 0 ||
                            remotePort > 65535)) {
                      return;
                    }
                    Navigator.pop(dialogContext, true);
                  },
                  label: t(context, AppStrings.values.save),
                  size: ButtonSize.medium,
                ),
              ],
            );
          },
        );
      },
    );

    if (saved != true) {
      return;
    }

    final isReverse = type == PortForwardType.reverse;
    final remoteHostText = remoteHostController.text.trim();
    final entry = PortForwardEntry(
      id: initial?.id ?? 'pf-${now.microsecondsSinceEpoch}',
      name: nameController.text.trim(),
      hostId: hostId.trim(),
      localHost: localHostController.text.trim(),
      localPort: int.tryParse(localPortController.text.trim()) ?? 0,
      remoteHost: type == PortForwardType.socks
          ? ''
          : (isReverse && remoteHostText.isEmpty
                ? '127.0.0.1'
                : remoteHostText),
      remotePort: type == PortForwardType.socks
          ? 0
          : (int.tryParse(remotePortController.text.trim()) ?? 0),
      createdAt: initial?.createdAt ?? now,
      autoStart: autoStart,
      type: type,
    );
    appState.upsertPortForwardEntry(entry);
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

  Future<void> _exportConfig(TerminalAppState appState) async {
    final location = await getSaveLocation(suggestedName: 'asmote-config.json');
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
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    String? errorText;
    return showDialog<String>(
      context: context,
      builder: (dialogCtx) {
        var includeEncrypted = false;
        return StatefulBuilder(
          builder: (stateCtx, setDialogState) {
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
                width: 320,
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
                            value: includeEncrypted,
                            onChanged: (v) {
                              setDialogState(() {
                                includeEncrypted = v ?? false;
                                errorText = null;
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
                    if (includeEncrypted) ...[
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
                      const SizedBox(height: 12),
                      TextField(
                        controller: confirmController,
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
                  onPressed: () => Navigator.pop(dialogCtx),
                  label: t(context, AppStrings.values.cancel),
                  size: ButtonSize.medium,
                ),
                const SizedBox(width: AppSpacing.sm),
                PrimaryButton(
                  onPressed: () {
                    if (includeEncrypted) {
                      final pw = passwordController.text.trim();
                      final confirm = confirmController.text.trim();
                      if (pw.isEmpty || pw != confirm) {
                        setDialogState(() {
                          errorText = t(
                            context,
                            AppStrings.values.passwordsDoNotMatch,
                          );
                        });
                        return;
                      }
                      Navigator.pop(dialogCtx, pw);
                    } else {
                      Navigator.pop(dialogCtx, '');
                    }
                  },
                  label: t(context, AppStrings.values.exportConfig),
                  size: ButtonSize.medium,
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _importConfig(TerminalAppState appState) async {
    final file = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(label: 'json', extensions: const ['json']),
      ],
    );
    if (file == null) return;
    if (!mounted) return;
    try {
      final raw = await File(file.path).readAsString();
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
    final replace = await showDialog<bool>(
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
      await appState.importPortableStateFromPath(file.path);
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
                width: 320,
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

  Widget _buildPortForwardSection(TerminalAppState appState) {
    final rules = appState.portForwards.toList(growable: false);
    if (rules.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t(context, AppStrings.values.noPortForwardRules),
            style: TextStyle(color: Colors.grey[700], fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            t(context, AppStrings.values.noPortForwardRulesHint),
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
        ],
      );
    }
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final views = appState.portForwardViews();
        return Column(
          children: views
              .map((view) {
                final rule = view.entry;
                final typeLabel = _portForwardTypeLabel(context, rule.type);
                final mapping = switch (rule.type) {
                  PortForwardType.local =>
                    '${rule.localHost}:${rule.localPort} -> '
                        '${rule.remoteHost}:${rule.remotePort}',
                  PortForwardType.reverse =>
                    '${rule.remoteHost}:${rule.remotePort} -> '
                        '${rule.localHost}:${rule.localPort}',
                  PortForwardType.socks => '${rule.localHost}:${rule.localPort}',
                };
                final status = view.status;
                final statusColor = switch (status) {
                  PortForwardRuntimeStatus.running => const Color(0xFF16A34A),
                  PortForwardRuntimeStatus.starting => const Color(0xFFF59E0B),
                  PortForwardRuntimeStatus.error => const Color(0xFFDC2626),
                  PortForwardRuntimeStatus.stopped => Colors.grey,
                };
                final statusText = switch (status) {
                  PortForwardRuntimeStatus.running =>
                    t(context, AppStrings.values.running),
                  PortForwardRuntimeStatus.starting =>
                    t(context, AppStrings.values.starting),
                  PortForwardRuntimeStatus.error =>
                    t(context, AppStrings.values.error),
                  PortForwardRuntimeStatus.stopped =>
                    t(context, AppStrings.values.stopped),
                };
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                    color: const Color(0xFFF9FAFB),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              rule.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              typeLabel,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1D4ED8),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        mapping,
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 6),
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
                          const SizedBox(width: 6),
                          Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 12,
                              color: statusColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (status == PortForwardRuntimeStatus.running &&
                              view.boundPort != null) ...[
                            const SizedBox(width: 12),
                            Text(
                              ':${view.boundPort}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[700],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '${t(context, AppStrings.values.tunnelConnections, params: {'connections': '${view.activeLocalConnections}'})}  '
                              '${t(context, AppStrings.values.tunnelChannels, params: {'channels': '${view.activeTunnelChannels}'})}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                          const Spacer(),
                          if (view.lastActivityAt != null)
                            Text(
                              '${_relativeTime(view.lastActivityAt!)}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[500],
                              ),
                            ),
                        ],
                      ),
                      if (status == PortForwardRuntimeStatus.error &&
                          view.lastError != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          view.lastError!,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFFDC2626),
                          ),
                        ),
                      ],
                      if (view.diagnosticHint != null) ...[
                        const SizedBox(height: 4),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFBEB),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: const Color(0xFFFDE68A),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '\u26A0\uFE0F ',
                                style: TextStyle(fontSize: 12),
                              ),
                              Expanded(
                                child: Text(
                                  view.diagnosticHint!,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF92400E),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (status == PortForwardRuntimeStatus.stopped)
                            _pfActionButton(
                              label: t(context, AppStrings.values.start),
                              onPressed: () => unawaited(
                                appState.startPortForward(rule.id),
                              ),
                            ),
                          if (status == PortForwardRuntimeStatus.running)
                            _pfActionButton(
                              label: t(context, AppStrings.values.stop),
                              onPressed: () => unawaited(
                                appState.stopPortForward(rule.id),
                              ),
                            ),
                          if (status == PortForwardRuntimeStatus.running &&
                              rule.type == PortForwardType.reverse &&
                              rule.remoteHost.trim() == '0.0.0.0') ...[
                            _pfActionButton(
                              label: t(context,
                                  AppStrings.values.portForwardTestConnectivity),
                              onPressed: () => unawaited(
                                _testReverseForwardConnectivity(
                                  appState, rule.id, context,
                                ),
                              ),
                            ),
                            _pfActionButton(
                              label: t(context, AppStrings.values
                                  .portForwardEnableGatewayPorts),
                              onPressed: () => unawaited(
                                _enableGatewayPortsOnServer(
                                  appState, rule.id, context,
                                ),
                              ),
                            ),
                          ],
                          if (status == PortForwardRuntimeStatus.running ||
                              status == PortForwardRuntimeStatus.error)
                            _pfActionButton(
                              label: t(context, AppStrings.values.restart),
                              onPressed: () => unawaited(
                                appState.restartPortForward(rule.id),
                              ),
                            ),
                          _pfActionButton(
                            label: t(context, AppStrings.values.edit),
                            onPressed: () => unawaited(
                              _showPortForwardDialog(appState, initial: rule),
                            ),
                          ),
                          _pfActionButton(
                            label: t(context, AppStrings.values.delete),
                            onPressed: () async {
                              final confirm = await _confirmDeleteNamedItem(
                                rule.name,
                              );
                              if (!mounted || !confirm) return;
                              await appState.removePortForwardEntry(rule.id);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              })
              .toList(growable: false),
        );
      },
    );
  }

  Future<void> _testReverseForwardConnectivity(
    TerminalAppState appState,
    String ruleId,
    BuildContext context,
  ) async {
    final locale = appState.locale.languageCode;
    final successMsg =
        AppStrings.values.portForwardConnectivityTestSuccess.resolve(locale);
    final skippedMsg =
        AppStrings.values.portForwardConnectivityTestSkipped.resolve(locale);
    final title = t(context, AppStrings.values.portForwardTestConnectivity);
    final result = await appState.testReverseForwardConnectivity(ruleId);
    if (!mounted) return;
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    if (result != null) {
      if (result == skippedMsg) {
        showBannerAndLog(
          appState,
          BannerData(
            id: 'pf-test-skipped-$timestamp',
            type: BannerType.info,
            title: title,
            message: result,
          ),
        );
        return;
      }
      showBannerAndLog(
        appState,
        BannerData(
          id: 'pf-test-failed-$timestamp',
          type: BannerType.error,
          title: title,
          message: result,
        ),
      );
    } else {
      showBannerAndLog(
        appState,
        BannerData(
          id: 'pf-test-success-$timestamp',
          type: BannerType.success,
          title: title,
          message: successMsg,
        ),
      );
    }
  }

  Future<void> _enableGatewayPortsOnServer(
    TerminalAppState appState,
    String ruleId,
    BuildContext context,
  ) async {
    final locale = appState.locale.languageCode;
    final title = t(context, AppStrings.values.portForwardEnableGatewayPorts);
    final timestamp = DateTime.now().microsecondsSinceEpoch;

    showBannerAndLog(
      appState,
      BannerData(
        id: 'gp-checking-$timestamp',
        type: BannerType.info,
        title: title,
        message: AppStrings.values.portForwardGatewayPortsChecking
            .resolve(locale),
      ),
    );

    final result = await appState.enableGatewayPorts(ruleId);
    if (!mounted) return;

    if (result == null) return;
    final isSuccess =
        result ==
            AppStrings.values.portForwardGatewayPortsSuccess.resolve(locale) ||
        result ==
            AppStrings.values.portForwardGatewayPortsAlreadyEnabled
                .resolve(locale);
    showBannerAndLog(
      appState,
      BannerData(
        id: 'gp-result-$timestamp',
        type: isSuccess ? BannerType.success : BannerType.error,
        title: title,
        message: result,
      ),
    );
  }

  Widget _pfActionButton({
    required String label,
    required VoidCallback onPressed,
  }) {
    return SecondaryButton(
      onPressed: onPressed,
      label: label,
      size: ButtonSize.small,
    );
  }

  String _relativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) {
      return t(context, AppStrings.values.timeAgoSeconds, params: {'count': '${diff.inSeconds}'});
    }
    if (diff.inMinutes < 60) {
      return t(context, AppStrings.values.timeAgoMinutes, params: {'count': '${diff.inMinutes}'});
    }
    if (diff.inHours < 24) {
      return t(context, AppStrings.values.timeAgoHours, params: {'count': '${diff.inHours}'});
    }
    return t(context, AppStrings.values.timeAgoDays, params: {'count': '${diff.inDays}'});
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
          title: t(context, AppStrings.values.transferAutoRetry),
          value: appState.transferAutoRetryEnabled,
          onChanged: appState.setTransferAutoRetryEnabled,
        ),
        _SettingSwitchRow(
          title: t(context, AppStrings.values.transferResume),
          value: appState.transferResumeEnabled,
          onChanged: appState.setTransferResumeEnabled,
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
          title: t(context, AppStrings.values.homeLayout),
          value: _homeLayoutLabel(context, appState.homeLayoutMode),
          onMoreTapDown: (details) async {
            final action = await showCompactMenu<HomeLayoutMode>(
              context: context,
              position: details.globalPosition,
              items: HomeLayoutMode.values
                  .map(
                    (layout) => compactMenuItem(
                      value: layout,
                      label: _homeLayoutLabel(context, layout),
                    ),
                  )
                  .toList(growable: false),
            );
            if (action != null) {
              appState.setHomeLayoutMode(action);
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
        const SizedBox(height: 8),
        _SectionTitle(label: t(context, AppStrings.values.settingsCache)),
        Row(
          children: [
            PrimaryButton(
              onPressed: () async {
                final timestamp = DateTime.now().microsecondsSinceEpoch;
                final title = t(
                  context,
                  AppStrings.values.startupSectionCacheCleanup,
                );
                try {
                  final result = await appState.clearFilePreviewCache();
                  if (!mounted) return;
                  final message = t(
                    context,
                    AppStrings.values.filePreviewCacheClearedVarVar,
                    params: {
                      'deleted': '${result.deleted}',
                      'failed': '${result.failed}',
                    },
                  );
                  showBannerAndLog(
                    appState,
                    BannerData(
                      id: 'cache-cleanup-$timestamp',
                      type: result.failed == 0
                          ? BannerType.success
                          : BannerType.warning,
                      title: title,
                      message: message,
                    ),
                  );
                  appState.addStructuredLog(
                    category: TerminalLogCategory.system,
                    message: '$title: $message',
                  );
                } catch (error) {
                  if (!mounted) return;
                  final message = '$error';
                  showBannerAndLog(
                    appState,
                    BannerData(
                      id: 'cache-cleanup-$timestamp',
                      type: BannerType.error,
                      title: title,
                      message: message,
                    ),
                  );
                  appState.addStructuredLog(
                    category: TerminalLogCategory.system,
                    message: '$title: $message',
                  );
                }
              },
              icon: Icons.cleaning_services_outlined,
              label: t(context, AppStrings.values.clearFilePreviewCache),
              size: ButtonSize.small,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _SectionTitle(label: t(context, AppStrings.values.recentVisitedFiles)),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: TerminalUiPalette.border),
            borderRadius: BorderRadius.circular(8),
            color: TerminalUiPalette.pageBackground,
          ),
          child: Row(
            children: [
              const Icon(Icons.history, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  t(context, AppStrings.values.recentVisitedFiles),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SecondaryButton(
                onPressed: () =>
                    showRecentVisitedFilesDialog(context, appState),
                label: t(context, AppStrings.values.quickJump),
                size: ButtonSize.small,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLogsTab(TerminalAppState appState) {
    final query = _logQuery.trim().toLowerCase();
    final source = List<String>.from(appState.logs.reversed, growable: false);
    final filtered = query.isEmpty
        ? source
        : source
              .where((line) => line.toLowerCase().contains(query))
              .toList(growable: false);
    final spans = <TextSpan>[];
    for (var i = 0; i < filtered.length; i++) {
      final line = filtered[i];
      spans.add(
        AppTextStyles.highlightSpan(
          text: line,
          query: _logQuery,
          baseStyle: const TextStyle(fontSize: 12),
        ),
      );
      if (i != filtered.length - 1) {
        spans.add(const TextSpan(text: '\n'));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        AppSearchBar(
          hint: t(context, AppStrings.values.logSearchHint),
          onChanged: (value) => setState(() => _logQuery = value),
        ),
        const SizedBox(height: 8),
        if (filtered.isEmpty)
          Text(
            t(context, AppStrings.values.noLogs),
            style: TextStyle(color: Colors.grey[600], fontSize: 11),
          )
        else
          SelectableText.rich(TextSpan(children: spans)),
      ],
    );
  }

  Widget _buildBackupTab(TerminalAppState appState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            PrimaryButton(
              onPressed: () => _importConfig(appState),
              label: t(context, AppStrings.values.importConfig),
              size: ButtonSize.small,
            ),
            const SizedBox(width: 8),
            SecondaryButton(
              onPressed: () => _exportConfig(appState),
              label: t(context, AppStrings.values.exportConfig),
              size: ButtonSize.small,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
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
              size: ButtonSize.small,
            ),
            const SizedBox(width: 8),
            SecondaryButton(
              onPressed: () async {
                await appState.refreshPortableStateSnapshots();
              },
              label: t(context, AppStrings.values.refresh),
              size: ButtonSize.small,
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildSnapshotList(appState),
      ],
    );
  }

  Widget _buildSnapshotList(TerminalAppState appState) {
    final items = appState.portableStateSnapshots;
    if (items.isEmpty) {
      return Text(
        t(context, AppStrings.values.noSnapshotsYet),
        style: TextStyle(color: Colors.grey[600], fontSize: 12),
      );
    }
    return Column(
      children: items
          .map((snapshot) {
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
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
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (snapshot.description != null && snapshot.description!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      snapshot.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: TerminalUiPalette.textSecondary),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    snapshot.id,
                    style: const TextStyle(
                      fontSize: 12,
                      color: TerminalUiPalette.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      SecondaryButton(
                        onPressed: () => _showEditSnapshotDialog(context, appState, snapshot),
                        label: t(context, AppStrings.values.editSnapshot),
                        size: ButtonSize.small,
                      ),
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
                      ),
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
        title: Text(t(context, AppStrings.values.editSnapshot)),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelCtrl,
                decoration: InputDecoration(
                  labelText: t(context, AppStrings.values.snapshotName),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: descCtrl,
                decoration: InputDecoration(
                  labelText: t(context, AppStrings.values.snapshotDescription),
                  isDense: true,
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          SecondaryButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            label: t(context, AppStrings.values.cancel),
            size: ButtonSize.small,
          ),
          PrimaryButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            label: t(context, AppStrings.values.snapshotSave),
            size: ButtonSize.small,
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

  Widget _buildPortForwardTab(TerminalAppState appState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
          children: [
            PrimaryButton(
              onPressed: () {
                unawaited(_showPortForwardDialog(appState));
              },
              icon: Icons.add,
              label: t(context, AppStrings.values.add),
              size: ButtonSize.small,
            ),
            const SizedBox(width: 8),
            SecondaryButton(
              onPressed: () {
                unawaited(appState.startAllPortForwards());
              },
              label: t(context, AppStrings.values.startAll),
              size: ButtonSize.small,
            ),
            const SizedBox(width: 8),
            SecondaryButton(
              onPressed: () {
                unawaited(appState.stopAllPortForwards());
              },
              label: t(context, AppStrings.values.stopAll),
              size: ButtonSize.small,
            ),
            const SizedBox(width: 8),
            SecondaryButton(
              onPressed: () {
                unawaited(_showPortForwardTemplatesDialog(appState));
              },
              label: t(context, AppStrings.values.portForwardTemplates),
              size: ButtonSize.small,
            ),
          ],
        ),
        ),
        const SizedBox(height: 12),
        _buildPortForwardSection(appState),
      ],
    );
  }

  Widget _buildTerminalTab(TerminalAppState appState) {
    final appearance = appState.globalAppearance;
    final fc = TextEditingController(text: appearance.fontFamily);
    final fsc = TextEditingController(text: appearance.fontSize.toString());
    final lhc = TextEditingController(text: appearance.lineHeight.toString());
    final sbc = TextEditingController(text: appState.maxScrollbackLines.toString());
    _disposeControllerLater(fc);
    _disposeControllerLater(fsc);
    _disposeControllerLater(lhc);
    _disposeControllerLater(sbc);
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
              );
              appState.scheduleStateSave();
              appState.notifyState();
            }
          },
        ),
        _SettingTextField(
          label: t(context, AppStrings.values.maxScrollbackLines),
          controller: sbc,
          hint: '10000',
          keyboardType: TextInputType.number,
          onSubmit: (v) {
            final n = int.tryParse(v.trim());
            if (n != null && n >= 1000) {
              appState.maxScrollbackLines = n.clamp(1000, 100000);
              appState.scheduleStateSave();
              appState.notifyState();
            }
          },
        ),
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
                                      child: Icon(Icons.broken_image, size: 20, color: Colors.grey),
                                    ),
                                  )
                                : const Center(
                                    child: Icon(Icons.broken_image, size: 20, color: Colors.grey),
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
                                  child: Icon(Icons.close, size: 12, color: Colors.grey),
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
                appState.addBackgroundImage(file.path);
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
        const SizedBox(height: 12),
      ],
    );
  }

  String _shortcutGroupLabel(String key) {
    return switch (key) {
      'clipboard' => t(context, AppStrings.values.shortcutGroupClipboard),
      'search' => t(context, AppStrings.values.shortcutGroupSearch),
      'panes' => t(context, AppStrings.values.shortcutGroupPanes),
      'selection' => t(context, AppStrings.values.shortcutGroupSelection),
      _ => key,
    };
  }

  static const Map<String, String> _shortcutBindingGroup = {
    'copy': 'clipboard',
    'paste': 'clipboard',
    'selectAll': 'clipboard',
    'search': 'search',
    'blockSelect': 'selection',
    'splitMaximize': 'panes',
    'splitBroadcast': 'panes',
    'splitPrev': 'panes',
    'splitNext': 'panes',
  };

  Widget _buildShortcutsTab(TerminalAppState appState) {
    final bindings = appState.shortcutBindings.where((sb) {
      if (_shortcutSearchQuery.isEmpty) return true;
      final q = _shortcutSearchQuery.toLowerCase();
      return sb.name.toLowerCase().contains(q) ||
          _shortcutName(sb).toLowerCase().contains(q) ||
          sb.effectiveKeys.toLowerCase().contains(q);
    }).toList();

    final grouped = <String, List<ShortcutBinding>>{};
    for (final sb in bindings) {
      final group = _shortcutBindingGroup[sb.id] ?? 'clipboard';
      grouped.putIfAbsent(group, () => []).add(sb);
    }

    final groupOrder = ['clipboard', 'search', 'panes', 'selection'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          style: const TextStyle(fontSize: 12),
          decoration: InputDecoration(
            hintText: '${t(context, AppStrings.values.search)}...',
            isDense: true,
            prefixIcon: const Icon(Icons.search, size: 16),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          ),
          onChanged: (v) => setState(() => _shortcutSearchQuery = v),
        ),
        const SizedBox(height: 8),
        ...groupOrder.where((g) => grouped.containsKey(g)).expand((g) {
          final items = grouped[g]!;
          return [
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Text(
                _shortcutGroupLabel(g),
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: TerminalUiPalette.textSecondary),
              ),
            ),
            ...items.map((sb) => _buildShortcutRow(appState, sb, _conflictingIds(appState))),
          ];
        }),
        const SizedBox(height: 16),
        _SectionTitle(label: t(context, AppStrings.values.scriptShortcuts)),
        const SizedBox(height: 4),
        _buildScriptShortcutsSection(appState),
      ],
    );
  }

  Widget _buildScriptShortcutsSection(TerminalAppState appState) {
    final scriptBindings = appState.scriptShortcutBindings.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final scriptsById = {
      for (final script in appState.scripts) script.id: script,
    };
    final conflictingScriptKeys = _conflictingScriptKeys(appState);
    if (scriptBindings.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          t(context, AppStrings.values.noScriptShortcuts),
          style: TextStyle(color: Colors.grey[600], fontSize: 12),
        ),
      );
    }
    return Column(
      children: scriptBindings.map((entry) {
        final script = scriptsById[entry.value];
        final name = script?.name ?? entry.value;
        final isEditing = _editingScriptShortcutKey == entry.key;
        final hasConflict = conflictingScriptKeys.contains(entry.key);
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: hasConflict
                  ? TerminalUiPalette.error
                  : isEditing
                      ? TerminalUiPalette.accent
                      : TerminalUiPalette.border,
            ),
            color: TerminalUiPalette.pageBackground,
          ),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    if (hasConflict) ...[
                      const Icon(Icons.warning_amber_rounded, size: 14, color: TerminalUiPalette.error),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (isEditing)
                _buildScriptCaptureWidget(appState, entry)
              else
                GestureDetector(
                  onTap: () => setState(() => _editingScriptShortcutKey = entry.key),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: hasConflict
                          ? TerminalUiPalette.error.withValues(alpha: 0.15)
                          : TerminalUiPalette.cardBackground,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      entry.key,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: hasConflict ? TerminalUiPalette.error : TerminalUiPalette.accent,
                      ),
                    ),
                  ),
                ),
              if (!isEditing) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    appState.scriptShortcutBindings.remove(entry.key);
                    appState.scheduleStateSave();
                    appState.notifyState();
                  },
                  child: const Icon(Icons.close, size: 16, color: TerminalUiPalette.textSecondary),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildScriptCaptureWidget(TerminalAppState appState, MapEntry<String, String> entry) {
    return Focus(
      focusNode: _scriptCaptureFocus,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.escape) {
          setState(() => _editingScriptShortcutKey = null);
          return KeyEventResult.handled;
        }
        final isModifier = key == LogicalKeyboardKey.controlLeft ||
            key == LogicalKeyboardKey.controlRight ||
            key == LogicalKeyboardKey.shiftLeft ||
            key == LogicalKeyboardKey.shiftRight ||
            key == LogicalKeyboardKey.altLeft ||
            key == LogicalKeyboardKey.altRight ||
            key == LogicalKeyboardKey.metaLeft ||
            key == LogicalKeyboardKey.metaRight;
        if (!isModifier) {
          final parts = <String>[];
          final kb = HardwareKeyboard.instance;
          if (kb.isControlPressed) parts.add('Ctrl');
          if (kb.isAltPressed) parts.add('Alt');
          if (kb.isShiftPressed) parts.add('Shift');
          if (kb.isMetaPressed) parts.add('Meta');
          parts.add(shortcutKeyName(key) ?? '');
          final captured = parts.join('+');
          appState.scriptShortcutBindings.remove(entry.key);
          appState.scriptShortcutBindings[captured] = entry.value;
          appState.shortcutConflictToken++;
          appState.scheduleStateSave();
          appState.notifyState();
          setState(() => _editingScriptShortcutKey = null);
        }
        return KeyEventResult.handled;
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: TerminalUiPalette.accent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: TerminalUiPalette.accent),
        ),
        child: Text(
          t(context, AppStrings.values.pressNewShortcut),
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: TerminalUiPalette.accent),
        ),
      ),
    );
  }

  String _shortcutName(ShortcutBinding sb) {
    return switch (sb.id) {
      'copy' => t(context, AppStrings.values.shortcutCopy),
      'paste' => t(context, AppStrings.values.shortcutPaste),
      'selectAll' => t(context, AppStrings.values.shortcutSelectAll),
      'search' => t(context, AppStrings.values.shortcutFind),
      'blockSelect' => t(context, AppStrings.values.shortcutBlockSelect),
      'splitMaximize' => t(context, AppStrings.values.shortcutSplitMaximize),
      'splitBroadcast' => t(context, AppStrings.values.shortcutSplitBroadcast),
      'splitPrev' => t(context, AppStrings.values.shortcutSplitPrev),
      'splitNext' => t(context, AppStrings.values.shortcutSplitNext),
      _ => sb.name,
    };
  }

  Set<String> _conflictingIds(TerminalAppState appState) {
    final conflictIds = <String>{};
    final usedKeys = <String, String>{};
    for (final sb in appState.shortcutBindings) {
      final keys = sb.effectiveKeys;
      if (keys.isEmpty) continue;
      for (final alt in keys.split(' / ')) {
        final trimmed = alt.trim();
        if (trimmed.isEmpty) continue;
        if (usedKeys.containsKey(trimmed)) {
          conflictIds.add(sb.id);
          conflictIds.add(usedKeys[trimmed]!);
        } else {
          usedKeys[trimmed] = sb.id;
        }
      }
    }
    for (final entry in appState.scriptShortcutBindings.entries) {
      for (final alt in entry.key.split(' / ')) {
        final trimmed = alt.trim();
        if (trimmed.isEmpty) continue;
        if (usedKeys.containsKey(trimmed)) {
          conflictIds.add(usedKeys[trimmed]!);
        }
      }
    }
    return conflictIds;
  }

  Set<String> _conflictingScriptKeys(TerminalAppState appState) {
    final usedKeys = <String>{};
    final conflictKeys = <String>{};
    for (final sb in appState.shortcutBindings) {
      final keys = sb.effectiveKeys;
      if (keys.isEmpty) continue;
      for (final alt in keys.split(' / ')) {
        final trimmed = alt.trim();
        if (trimmed.isNotEmpty) {
          usedKeys.add(trimmed);
        }
      }
    }
    for (final entry in appState.scriptShortcutBindings.entries) {
      for (final alt in entry.key.split(' / ')) {
        final trimmed = alt.trim();
        if (trimmed.isNotEmpty && usedKeys.contains(trimmed)) {
          conflictKeys.add(entry.key);
        }
      }
    }
    return conflictKeys;
  }

  Widget _buildShortcutRow(TerminalAppState appState, ShortcutBinding sb, Set<String> conflictingIds) {
    final isCustom = sb.isCustomized;
    final hasConflict = conflictingIds.contains(sb.id);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasConflict
              ? TerminalUiPalette.error
              : isCustom
                  ? TerminalUiPalette.accent
                  : TerminalUiPalette.border,
        ),
        color: TerminalUiPalette.pageBackground,
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                if (hasConflict) ...[
                  const Icon(Icons.warning_amber_rounded, size: 14, color: TerminalUiPalette.error),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    _shortcutName(sb),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: hasConflict
                    ? TerminalUiPalette.error.withValues(alpha: 0.15)
                    : isCustom
                        ? TerminalUiPalette.accent.withValues(alpha: 0.15)
                        : TerminalUiPalette.cardBackground,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                sb.effectiveKeys,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: hasConflict ? TerminalUiPalette.error : isCustom ? TerminalUiPalette.accent : TerminalUiPalette.textPrimary,
                ),
              ),
            ),
          ),
          if (isCustom) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                final idx = appState.shortcutBindings.indexWhere((s) => s.id == sb.id);
                if (idx >= 0) {
                  appState.shortcutBindings[idx] = sb.copyWith(customKeys: null);
                  appState.scheduleStateSave();
                  appState.notifyState();
                }
              },
              child: const Icon(Icons.restore, size: 16, color: TerminalUiPalette.warning),
            ),
          ],
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _showShortcutEditDialog(appState, sb),
            child: const Icon(Icons.edit, size: 16, color: TerminalUiPalette.textSecondary),
          ),
        ],
      ),
    );
  }

  Future<void> _showShortcutEditDialog(TerminalAppState appState, ShortcutBinding sb) async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => _ShortcutCaptureDialog(
        title: '${t(context, AppStrings.values.editShortcut)}: ${_shortcutName(sb)}',
        currentKeys: sb.effectiveKeys,
      ),
    );
    if (result == null || !mounted) return;
    final idx = appState.shortcutBindings.indexWhere((s) => s.id == sb.id);
    if (idx < 0) return;
    if (result.isEmpty) {
      appState.shortcutBindings[idx] = sb.copyWith(customKeys: null);
    } else {
      appState.shortcutBindings[idx] = sb.copyWith(customKeys: result);
    }
    appState.shortcutConflictToken++;
    appState.scheduleStateSave();
    appState.notifyState();
  }

  Widget _buildSettingsContent(BuildContext context) {
    final appState = widget.appState;
    final query = _searchQuery.trim().toLowerCase();

    final categories = [
      _CategoryInfo(
        title: t(context, AppStrings.values.settingsGeneral),
        icon: Icons.tune,
        builder: () => _buildGeneralTab(appState),
        keywords: ['general', 'show hidden', 'auto reconnect', 'paste', 'split', 'transfer', 'layout', 'language', 'cache', 'accessibility'],
      ),
      _CategoryInfo(
        title: t(context, AppStrings.values.settingsTerminal),
        icon: Icons.terminal,
        builder: () => _buildTerminalTab(appState),
        keywords: ['terminal', 'font', 'scrollback', 'background', 'opacity', 'bell', 'broadcast', 'input'],
      ),
      _CategoryInfo(
        title: t(context, AppStrings.values.logs),
        icon: Icons.list_alt,
        builder: () => _buildLogsTab(appState),
        keywords: ['log', 'recent files', 'verbosity', '重要', '仅错误'],
      ),
      _CategoryInfo(
        title: t(context, AppStrings.values.settingsConfigBackup),
        icon: Icons.backup,
        builder: () => _buildBackupTab(appState),
        keywords: ['backup', 'import', 'export', 'snapshot', 'config'],
      ),
      _CategoryInfo(
        title: t(context, AppStrings.values.settingsPortForwarding),
        icon: Icons.route,
        builder: () => _buildPortForwardTab(appState),
        keywords: ['port forward', 'tunnel', 'template'],
      ),
      _CategoryInfo(
        title: t(context, AppStrings.values.shortcutsTab),
        icon: Icons.keyboard,
        builder: () => _buildShortcutsTab(appState),
        keywords: ['shortcut', 'key', 'binding', 'hotkey'],
      ),
    ];

    final filtered = query.isEmpty
        ? categories
        : categories.where((c) {
            if (c.title.toLowerCase().contains(query)) return true;
            return c.keywords.any((k) => k.contains(query));
          }).toList();

    return Column(
      children: [
        if (!widget.embedded)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextField(
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                hintText: '${t(context, AppStrings.values.search)}...',
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 16),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
        Expanded(
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility: widget.embedded,
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final info = filtered[index];
                return _CategoryTile(
                  title: info.title,
                  icon: info.icon,
                  initiallyExpanded: false,
                  child: info.builder(),
                );
              },
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
}

class _SettingTextField extends StatelessWidget {
  const _SettingTextField({
    required this.label,
    required this.controller,
    this.hint,
    this.keyboardType,
    required this.onSubmit,
  });
  final String label;
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboardType;
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(width: 100, child: Text(label, style: const TextStyle(fontSize: 12, color: TerminalUiPalette.textSecondary))),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                hintText: hint,
              ),
              onSubmitted: onSubmit,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _VisitedFileLoadProgress {
  const _VisitedFileLoadProgress({
    required this.downloadedBytes,
    required this.totalBytes,
  });

  final int downloadedBytes;
  final int? totalBytes;
}

class _VisitedFileLoadingDialog extends StatelessWidget {
  const _VisitedFileLoadingDialog({
    required this.appState,
    required this.fileName,
    required this.progress,
  });

  final TerminalAppState appState;
  final String fileName;
  final ValueListenable<_VisitedFileLoadProgress> progress;

  @override
  Widget build(BuildContext context) {
    final languageCode = appState.locale.languageCode;
    final loadingText = AppStrings.values.loadingFilePreview.resolve(
      languageCode,
    );
    return Dialog(
      backgroundColor: TerminalUiPalette.cardBackground,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        child: ValueListenableBuilder<_VisitedFileLoadProgress>(
          valueListenable: progress,
          builder: (context, value, _) {
            final totalBytes = value.totalBytes;
            final downloaded = value.downloadedBytes
                .clamp(0, totalBytes ?? value.downloadedBytes)
                .toInt();
            final percent = totalBytes != null && totalBytes > 0
                ? (downloaded / totalBytes).clamp(0.0, 1.0)
                : null;
            final progressLabel = totalBytes != null && totalBytes > 0
                ? '${formatBytes(downloaded)}/${formatBytes(totalBytes)}  ${(percent! * 100).toStringAsFixed(1)}%'
                : formatBytes(downloaded);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loadingText,
                  style: const TextStyle(
                    color: TerminalUiPalette.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: TerminalUiPalette.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: percent,
                    minHeight: 6,
                    backgroundColor: TerminalUiPalette.border,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      TerminalUiPalette.accent,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  progressLabel,
                  style: const TextStyle(
                    color: TerminalUiPalette.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Widget icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected
        ? TerminalUiPalette.accent
        : TerminalUiPalette.border;
    final background = selected
        ? TerminalUiPalette.accentSelected
        : TerminalUiPalette.cardBackground;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: selected
                    ? TerminalUiPalette.accent
                    : TerminalUiPalette.textPrimary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogField extends StatelessWidget {
  const _DialogField({
    required this.label,
    required this.controller,
    this.keyboardType,
    this.obscureText = false,
  });

  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        decoration: InputDecoration(
          labelText: label,
        ),
      ),
    );
  }
}

class _CategoryInfo {
  const _CategoryInfo({
    required this.title,
    required this.icon,
    required this.builder,
    required this.keywords,
  });

  final String title;
  final IconData icon;
  final Widget Function() builder;
  final List<String> keywords;
}

class _CategoryTile extends StatefulWidget {
  const _CategoryTile({
    required this.title,
    required this.icon,
    required this.initiallyExpanded,
    required this.child,
  });

  final String title;
  final IconData icon;
  final bool initiallyExpanded;
  final Widget child;

  @override
  State<_CategoryTile> createState() => _CategoryTileState();
}

class _CategoryTileState extends State<_CategoryTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _rotationAnimation;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _rotationAnimation = Tween<double>(begin: 0.0, end: 0.5).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    if (_expanded) {
      _animationController.value = 0.5;
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 0),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: TerminalUiPalette.border),
      ),
      color: TerminalUiPalette.cardBackground,
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _expanded = !_expanded;
                if (_expanded) {
                  _animationController.forward();
                } else {
                  _animationController.reverse();
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(widget.icon, size: 18, color: TerminalUiPalette.textPrimary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  RotationTransition(
                    turns: _rotationAnimation,
                    child: const Icon(Icons.expand_more, size: 20, color: TerminalUiPalette.textSecondary),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: widget.child,
            ),
            crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }
}

class _SettingSwitchRow extends StatelessWidget {
  const _SettingSwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 12))),
          Transform.scale(
            scale: 0.9,
            child: Switch(
              value: value,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingActionRow extends StatelessWidget {
  const _SettingActionRow({
    required this.title,
    required this.value,
    this.onMoreTapDown,
  });

  final String title;
  final String value;
  final void Function(TapDownDetails details)? onMoreTapDown;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 1),
                Text(
                  value,
                  style: TextStyle(fontSize: 10.5, color: Colors.grey[700]),
                ),
              ],
            ),
          ),
          if (onMoreTapDown != null)
            CompactMoreMenuButton(
              tooltip: t(context, AppStrings.values.more),
              onTapDown: onMoreTapDown!,
              icon: Icons.more_horiz,
              iconSize: 18,
              padding: 1,
            ),
        ],
      ),
    );
  }
}

class _ShortcutCaptureDialog extends StatefulWidget {
  const _ShortcutCaptureDialog({required this.title, required this.currentKeys});
  final String title;
  final String currentKeys;

  @override
  State<_ShortcutCaptureDialog> createState() => _ShortcutCaptureDialogState();
}

class _ShortcutCaptureDialogState extends State<_ShortcutCaptureDialog> {
  String _captured = '';
  bool _listening = true;

  String _captureHint(BuildContext ctx) => t(ctx, AppStrings.values.pressNewShortcut);
  String _captureLabel(BuildContext ctx, AppText text) => t(ctx, text);

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (!_listening) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      Navigator.pop(context);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      if (_captured.isNotEmpty) {
        Navigator.pop(context, _captured);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace || key == LogicalKeyboardKey.delete) {
      setState(() => _captured = '');
      return KeyEventResult.handled;
    }
    final isModifier = key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight ||
        key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight ||
        key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight ||
        key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight;
    if (!isModifier) {
      final parts = <String>[];
      final kb = HardwareKeyboard.instance;
      if (kb.isControlPressed) parts.add('Ctrl');
      if (kb.isAltPressed) parts.add('Alt');
      if (kb.isShiftPressed) parts.add('Shift');
      if (kb.isMetaPressed) parts.add('Meta');
      parts.add(shortcutKeyName(key) ?? '');
      setState(() {
        _captured = parts.join('+');
        _listening = false;
      });
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) setState(() => _listening = true);
      });
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.radiusDialog,
      ),
      title: Text(widget.title, style: AppTextStyles.h4),
      content: Focus(
        autofocus: true,
        onKeyEvent: _handleKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _captured.isEmpty
                  ? _captureHint(context)
                  : _captured,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _captured.isEmpty ? Colors.grey : TerminalUiPalette.accent,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${_captureLabel(context, AppStrings.values.currentLabel)}: ${widget.currentKeys}',
              style: const TextStyle(fontSize: 11, color: TerminalUiPalette.textSecondary),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.all(AppSpacing.lg),
      actions: [
        if (_captured.isNotEmpty)
          AppTextButton(
            onPressed: () => Navigator.pop(context, ''),
            label: t(context, AppStrings.values.resetToDefault),
            size: ButtonSize.small,
          ),
        SecondaryButton(
          onPressed: () => Navigator.pop(context),
          label: t(context, AppStrings.values.cancel),
          size: ButtonSize.small,
        ),
        if (_captured.isNotEmpty) ...[
          const SizedBox(width: AppSpacing.sm),
          PrimaryButton(
            onPressed: () => Navigator.pop(context, _captured),
            label: t(context, AppStrings.values.save),
            size: ButtonSize.small,
          ),
        ],
      ],
    );
  }
}
