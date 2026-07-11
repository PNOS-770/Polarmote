part of 'terminal_dialogs.dart';

Future<void> showQuickConnectDialog(
  BuildContext context,
  TerminalAppState appState,
) async {
  final hostController = TextEditingController();
  final portController = TextEditingController(text: '22');
  final userController = TextEditingController();
  final passwordController = TextEditingController();
  final serialPortController = TextEditingController();
  final serialBaudRateController = TextEditingController(text: '9600');
  final serialDataBitsController = TextEditingController(text: '8');
  final serialStopBitsController = TextEditingController(text: '1');
  final localTerminalSupported = _isLocalTerminalSupportedOnPlatform();
  final serialTerminalSupported = _isSerialSupportedOnPlatform();
  final localShellOptions = _localShellOptionsForCurrentPlatform();
  var connectionType = ConnectionType.ssh;
  var localShellType = localShellOptions.first;
  var serialParity = SerialParity.none;

  await showDialog<void>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          final screenWidth = MediaQuery.of(context).size.width;
          final dialogWidth = (screenWidth - 24).clamp(360.0, 920.0);
          return AlertDialog(
            backgroundColor: AppColors.cardBackground,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.radiusDialog),
            actionsPadding: const EdgeInsets.all(AppSpacing.lg),
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                buildQuickConnectVscodeIcon(size: 18),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(t(context, AppStrings.values.quickConnect), style: AppTextStyles.h4),
                ),
              ],
            ),
            content: SizedBox(
              width: dialogWidth,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionTitle(
                      label: t(context, AppStrings.values.connectionType),
                    ),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _ChoiceCard(
                          label: t(context, AppStrings.values.connectionSsh),
                          icon: buildConnectionSshVscodeIcon(size: 18),
                          selected: connectionType == ConnectionType.ssh,
                          onTap: () {
                            setState(() {
                              connectionType = ConnectionType.ssh;
                            });
                          },
                        ),
                        if (localTerminalSupported)
                          _ChoiceCard(
                            label: t(
                              context,
                              AppStrings.values.connectionLocal,
                            ),
                            icon: buildConnectionLocalVscodeIcon(size: 18),
                            selected: connectionType == ConnectionType.local,
                            onTap: () {
                              setState(
                                () => connectionType = ConnectionType.local,
                              );
                            },
                          ),
                        if (serialTerminalSupported)
                          _ChoiceCard(
                            label: t(
                              context,
                              AppStrings.values.connectionSerial,
                            ),
                            icon: const Icon(Icons.usb, size: 18),
                            selected: connectionType == ConnectionType.serial,
                            onTap: () {
                              setState(
                                () => connectionType = ConnectionType.serial,
                              );
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (connectionType == ConnectionType.ssh) ...[
                      _DialogField(
                        label: t(context, AppStrings.values.host),
                        controller: hostController,
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: _DialogField(
                              label: t(context, AppStrings.values.port),
                              controller: portController,
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: _DialogField(
                              label: t(context, AppStrings.values.username),
                              controller: userController,
                            ),
                          ),
                        ],
                      ),
                      if (connectionType == ConnectionType.ssh)
                        _DialogField(
                          label: t(context, AppStrings.values.password),
                          controller: passwordController,
                          obscureText: true,
                        ),
                    ] else if (connectionType == ConnectionType.serial) ...[
                      _DialogField(
                        label: t(context, AppStrings.values.serialPortPath),
                        controller: serialPortController,
                      ),
                      Text(
                        t(context, AppStrings.values.serialPortPathHint),
                        style: TextStyle(color: Colors.grey[700], fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _DialogField(
                              label: t(
                                context,
                                AppStrings.values.serialBaudRate,
                              ),
                              controller: serialBaudRateController,
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _DialogField(
                              label: t(
                                context,
                                AppStrings.values.serialDataBits,
                              ),
                              controller: serialDataBitsController,
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: _DialogField(
                              label: t(
                                context,
                                AppStrings.values.serialStopBits,
                              ),
                              controller: serialStopBitsController,
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: DropdownButtonFormField<SerialParity>(
                                initialValue: serialParity,
                                decoration: InputDecoration(
                                  labelText: t(
                                    context,
                                    AppStrings.values.serialParity,
                                  ),
                                ),
                                items: SerialParity.values
                                    .map(
                                      (parity) =>
                                          DropdownMenuItem<SerialParity>(
                                            value: parity,
                                            child: Text(
                                              _serialParityLabel(
                                                context,
                                                parity,
                                              ),
                                            ),
                                          ),
                                    )
                                    .toList(growable: false),
                                onChanged: (value) {
                                  if (value == null) {
                                    return;
                                  }
                                  setState(() {
                                    serialParity = value;
                                  });
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        t(context, AppStrings.values.serialTerminalHint),
                        style: TextStyle(color: Colors.grey[700], fontSize: 12),
                      ),
                    ] else ...[
                      _SectionTitle(
                        label: t(context, AppStrings.values.localShellType),
                      ),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: localShellOptions
                            .map(
                              (shell) => _ChoiceCard(
                                label: _localShellLabel(context, shell),
                                icon: _localShellIcon(shell),
                                selected: localShellType == shell,
                                onTap: () {
                                  setState(() => localShellType = shell);
                                },
                              ),
                            )
                            .toList(growable: false),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        t(context, AppStrings.values.localTerminalHint),
                        style: TextStyle(color: Colors.grey[700], fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _localShellDescription(context, localShellType),
                        style: const TextStyle(
                          color: Color(0xFF4B5563),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              SecondaryButton(
                onPressed: () => Navigator.pop(context),
                label: t(context, AppStrings.values.cancel),
                size: ButtonSize.small,
              ),
              PrimaryButton(
                onPressed: () {
                  if (connectionType == ConnectionType.local) {
                    final localUser =
                        Platform.environment['USERNAME'] ??
                        Platform.environment['USER'] ??
                        'local';
                    final entry = HostEntry(
                      id: 'quick-local-${DateTime.now().microsecondsSinceEpoch}',
                      name: _localShellLabel(context, localShellType),
                      host: 'local',
                      port: 0,
                      username: localUser,
                      group: t(context, AppStrings.values.quickConnect),
                      authType: AuthType.password,
                      connectionType: ConnectionType.local,
                      localShellType: localShellType,
                    );
                    unawaited(appState.connectToHost(entry, remember: false));
                    Navigator.pop(context);
                    return;
                  }
                  if (connectionType == ConnectionType.serial) {
                    if (!serialTerminalSupported) {
                      appState.setError(
                        t(
                          context,
                          AppStrings.values.serialUnsupportedOnPlatform,
                        ),
                      );
                      return;
                    }
                    final serialPortPath = serialPortController.text.trim();
                    if (serialPortPath.isEmpty) {
                      appState.setError(
                        t(context, AppStrings.values.serialPortRequired),
                      );
                      return;
                    }
                    final serialBaudRate =
                        int.tryParse(serialBaudRateController.text.trim()) ??
                        9600;
                    final serialDataBits =
                        int.tryParse(serialDataBitsController.text.trim()) ?? 8;
                    final serialStopBits =
                        int.tryParse(serialStopBitsController.text.trim()) ?? 1;
                    final entry = HostEntry(
                      id: 'quick-serial-${DateTime.now().microsecondsSinceEpoch}',
                      name: serialPortPath,
                      host: serialPortPath,
                      port: 0,
                      username: 'serial',
                      group: t(context, AppStrings.values.quickConnect),
                      authType: AuthType.password,
                      connectionType: ConnectionType.serial,
                      serialPortPath: serialPortPath,
                      serialBaudRate: serialBaudRate.clamp(1200, 4000000),
                      serialDataBits: serialDataBits.clamp(5, 8),
                      serialStopBits: serialStopBits == 2 ? 2 : 1,
                      serialParity: serialParity,
                    );
                    unawaited(appState.connectToHost(entry, remember: false));
                    Navigator.pop(context);
                    return;
                  }
                  final host = hostController.text.trim();
                  final user = userController.text.trim();
                  final port = int.tryParse(portController.text.trim()) ?? 22;
                  if (host.isEmpty || user.isEmpty) return;
                  unawaited(
                    appState.quickConnect(
                      host: host,
                      port: port,
                      username: user,
                      password: passwordController.text,
                    ),
                  );
                  Navigator.pop(context);
                },
                label: t(context, AppStrings.values.connect),
                size: ButtonSize.medium,
              ),
            ],
          );
        },
      );
    },
  );
}

bool _isLocalTerminalSupportedOnPlatform() {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    return true;
  }
  if (Platform.isAndroid) {
    return true;
  }
  return false;
}

bool _isSerialSupportedOnPlatform() {
  return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
}

List<LocalShellType> _localShellOptionsForCurrentPlatform() {
  if (Platform.isWindows) {
    return const [
      LocalShellType.systemDefault,
      LocalShellType.powershell,
      LocalShellType.powershellAdmin,
      LocalShellType.commandPrompt,
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
  return const [LocalShellType.systemDefault];
}

String _localShellLabel(BuildContext context, LocalShellType type) {
  switch (type) {
    case LocalShellType.systemDefault:
      return t(context, AppStrings.values.localShellSystemDefault);
    case LocalShellType.powershell:
      return t(context, AppStrings.values.localShellPowerShell);
    case LocalShellType.powershellAdmin:
      return t(context, AppStrings.values.localShellPowerShellAdmin);
    case LocalShellType.commandPrompt:
      return t(context, AppStrings.values.localShellCommandPrompt);
    case LocalShellType.wsl:
      return t(context, AppStrings.values.localShellWsl);
    case LocalShellType.bash:
      return t(context, AppStrings.values.localShellBash);
  }
}

String _serialParityLabel(BuildContext context, SerialParity parity) {
  return switch (parity) {
    SerialParity.none => t(context, AppStrings.values.serialParityNone),
    SerialParity.odd => t(context, AppStrings.values.serialParityOdd),
    SerialParity.even => t(context, AppStrings.values.serialParityEven),
  };
}

String _localShellDescription(BuildContext context, LocalShellType type) {
  switch (type) {
    case LocalShellType.systemDefault:
      return t(context, AppStrings.values.localShellSystemDefaultHint);
    case LocalShellType.powershell:
      return t(context, AppStrings.values.localShellPowerShellHint);
    case LocalShellType.powershellAdmin:
      return t(context, AppStrings.values.localShellPowerShellAdminHint);
    case LocalShellType.commandPrompt:
      return t(context, AppStrings.values.localShellCommandPromptHint);
    case LocalShellType.wsl:
      return t(context, AppStrings.values.localShellWslHint);
    case LocalShellType.bash:
      return t(context, AppStrings.values.localShellBashHint);
  }
}

Widget _localShellIcon(LocalShellType type) {
  switch (type) {
    case LocalShellType.systemDefault:
      return buildLocalShellSystemDefaultVscodeIcon(size: 18);
    case LocalShellType.powershell:
      return buildLocalShellPowerShellVscodeIcon(size: 18);
    case LocalShellType.powershellAdmin:
      return buildLocalShellPowerShellAdminVscodeIcon(size: 18);
    case LocalShellType.commandPrompt:
      return buildLocalShellCommandPromptVscodeIcon(size: 18);
    case LocalShellType.wsl:
      return buildLocalShellWslVscodeIcon(size: 18);
    case LocalShellType.bash:
      return buildLocalShellBashVscodeIcon(size: 18);
  }
}

