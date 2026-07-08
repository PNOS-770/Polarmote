part of 'terminal_dialogs.dart';

Future<void> showHostDialog(
  BuildContext context,
  TerminalAppState appState, {
  HostEntry? host,
}) async {
  final defaultGroup = t(context, AppStrings.values.defaultValue);
  final isEdit = host != null;
  final currentGroup = host?.group.trim();
  final nameController = TextEditingController(text: host?.name ?? '');
  final hostController = TextEditingController(text: host?.host ?? '');
  final portController = TextEditingController(
    text: host?.port.toString() ?? '22',
  );
  final userController = TextEditingController(text: host?.username ?? '');
  final groupController = TextEditingController(
    text: (currentGroup == null || currentGroup.isEmpty)
        ? defaultGroup
        : currentGroup,
  );
  final passwordController = TextEditingController(text: host?.password ?? '');
  final localTerminalSupported = _isLocalTerminalSupportedOnPlatform();
  final serialTerminalSupported = _isSerialSupportedOnPlatform();
  final localShellOptions = _localShellOptionsForCurrentPlatform();
  var connectionType = host?.connectionType ?? ConnectionType.ssh;
  var localShellType = host?.localShellType ?? LocalShellType.systemDefault;
  if (!localShellOptions.contains(localShellType)) {
    localShellType = localShellOptions.first;
  }
  var authType = host?.authType ?? AuthType.password;
  var keyPath = host?.privateKeyPath ?? '';
  final keyPassphraseController = TextEditingController(
    text: host?.privateKeyPassphrase ?? '',
  );
  var sshProxyType = host?.sshProxyType ?? SshProxyType.none;
  final socksProxyHostController = TextEditingController(
    text: host?.socksProxyHost ?? '',
  );
  final socksProxyPortController = TextEditingController(
    text: '${host?.socksProxyPort ?? 1080}',
  );
  final socksProxyUsernameController = TextEditingController(
    text: host?.socksProxyUsername ?? '',
  );
  final socksProxyPasswordController = TextEditingController(
    text: host?.socksProxyPassword ?? '',
  );
  final jumpHostEntries = <JumpHostEntry>[
    if (host != null) ...host.jumpHosts,
  ];
  final jumpHostControllers = <TextEditingController>[
    for (final j in jumpHostEntries)
      TextEditingController(
        text: j.username != null ? '${j.username}@${j.host}:${j.port}' : '${j.host}:${j.port}',
      ),
  ];
  var useSshAgent = host?.useSshAgent ?? false;
  final keepAliveController = TextEditingController(
    text: '${host?.keepAliveSeconds ?? 10}',
  );
  final connectTimeoutController = TextEditingController(
    text: '${host?.connectTimeoutSeconds ?? 12}',
  );
  final serialPortController = TextEditingController(
    text: host?.serialPortPath ?? '',
  );
  final serialBaudRateController = TextEditingController(
    text: '${host?.serialBaudRate ?? 9600}',
  );
  final serialDataBitsController = TextEditingController(
    text: '${host?.serialDataBits ?? 8}',
  );
  final serialStopBitsController = TextEditingController(
    text: '${host?.serialStopBits ?? 1}',
  );
  var serialParity = host?.serialParity ?? SerialParity.none;
  await showDialog<void>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          final screenWidth = MediaQuery.of(context).size.width;
          final dialogWidth = (screenWidth - 24).clamp(360.0, 920.0);
          void selectLocalShell(LocalShellType shell) {
            final currentName = nameController.text.trim();
            final previousLabel = _localShellLabel(context, localShellType);
            final defaultLocalName = t(
              context,
              AppStrings.values.localTerminal,
            );
            final shouldAutoRename =
                currentName.isEmpty ||
                currentName == defaultLocalName ||
                currentName == previousLabel;
            setState(() {
              localShellType = shell;
              if (shouldAutoRename) {
                nameController.text = _localShellLabel(context, shell);
              }
            });
          }

          void selectConnectionType(ConnectionType value) {
            setState(() {
              connectionType = value;
            });
          }

          return AlertDialog(
            backgroundColor: AppColors.cardBackground,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.radiusDialog),
            actionsPadding: const EdgeInsets.all(AppSpacing.lg),
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isEdit) ...[
                  buildNewSessionVscodeIcon(size: 18),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    t(
                      context,
                      isEdit
                          ? AppStrings.values.editSession
                          : AppStrings.values.newSession,
                    ),
                    style: AppTextStyles.h4,
                  ),
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
                          onTap: () => selectConnectionType(ConnectionType.ssh),
                        ),
                        if (localTerminalSupported ||
                            connectionType == ConnectionType.local)
                          _ChoiceCard(
                            label: t(
                              context,
                              AppStrings.values.connectionLocal,
                            ),
                            icon: buildConnectionLocalVscodeIcon(size: 18),
                            selected: connectionType == ConnectionType.local,
                            onTap: () =>
                                selectConnectionType(ConnectionType.local),
                          ),
                        if (serialTerminalSupported ||
                            connectionType == ConnectionType.serial)
                           _ChoiceCard(
                            label: t(
                              context,
                              AppStrings.values.connectionSerial,
                            ),
                            icon: const Icon(Icons.usb, size: 18),
                            selected: connectionType == ConnectionType.serial,
                            onTap: () =>
                                selectConnectionType(ConnectionType.serial),
                          ),
                        _ChoiceCard(
                          label: t(context, AppStrings.values.connectionTelnet),
                          icon: const Icon(Icons.lan, size: 18),
                          selected: connectionType == ConnectionType.telnet,
                          onTap: () =>
                              selectConnectionType(ConnectionType.telnet),
                        ),
                      ],
                    ),
                    if (Platform.isIOS && !localTerminalSupported) ...[
                      const SizedBox(height: 8),
                      Text(
                        t(context, AppStrings.values.localTerminalUseSshOnIos),
                        style: TextStyle(color: Colors.grey[700], fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _DialogField(
                      label:
                          connectionType == ConnectionType.local ||
                              connectionType == ConnectionType.serial
                          ? t(context, AppStrings.values.localSessionName)
                          : t(context, AppStrings.values.name),
                      controller: nameController,
                    ),
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
                      if (connectionType == ConnectionType.ssh) ...[
                        const SizedBox(height: 2),
                        _SectionTitle(
                          label: t(context, AppStrings.values.auth),
                        ),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _ChoiceCard(
                              label: t(context, AppStrings.values.password),
                              icon: buildAuthPasswordVscodeIcon(size: 18),
                              selected: authType == AuthType.password,
                              onTap: () {
                                setState(() => authType = AuthType.password);
                              },
                            ),
                            _ChoiceCard(
                              label: t(context, AppStrings.values.key),
                              icon: buildAuthKeyVscodeIcon(size: 18),
                              selected: authType == AuthType.key,
                              onTap: () {
                                setState(() => authType = AuthType.key);
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (connectionType == ConnectionType.ssh &&
                          authType == AuthType.password)
                        _DialogField(
                          label: t(context, AppStrings.values.password),
                          controller: passwordController,
                          obscureText: true,
                        )
                      else if (connectionType == ConnectionType.ssh) ...[
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                keyPath.isEmpty
                                    ? t(
                                        context,
                                        AppStrings.values.noKeySelected,
                                      )
                                    : keyPath,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.grey[700],
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SecondaryButton(
                              onPressed: () async {
                                final file = await openFile(
                                  acceptedTypeGroups: [
                                    XTypeGroup(
                                      label: t(context, AppStrings.values.key),
                                      extensions: const ['pem', 'key', 'ppk'],
                                    ),
                                  ],
                                );
                                if (file != null) {
                                  setState(() => keyPath = file.path);
                                }
                              },
                              iconWidget: buildSelectKeyVscodeIcon(size: 14),
                              label: t(context, AppStrings.values.selectKey),
                              size: ButtonSize.small,
                            ),
                          ],
                        ),
                        _DialogField(
                          label: t(
                            context,
                            AppStrings.values.privateKeyPassphrase,
                          ),
                          controller: keyPassphraseController,
                          obscureText: true,
                        ),
                        SwitchListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(t(context, AppStrings.values.sshAgent)),
                          value: useSshAgent,
                          onChanged: (value) {
                            setState(() => useSshAgent = value);
                          },
                        ),
                      ],
                      if (connectionType == ConnectionType.ssh) ...[
                        const SizedBox(height: 4),
                        _SectionTitle(
                          label: t(context, AppStrings.values.sshAdvanced),
                        ),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _ChoiceCard(
                              label: t(context, AppStrings.values.proxyNone),
                              icon: const Icon(Icons.link, size: 18),
                              selected: sshProxyType == SshProxyType.none,
                              onTap: () {
                                setState(
                                  () => sshProxyType = SshProxyType.none,
                                );
                              },
                            ),
                            _ChoiceCard(
                              label: t(context, AppStrings.values.proxySocks5),
                              icon: const Icon(Icons.route, size: 18),
                              selected: sshProxyType == SshProxyType.socks5,
                              onTap: () {
                                setState(
                                  () => sshProxyType = SshProxyType.socks5,
                                );
                              },
                            ),
                            _ChoiceCard(
                              label: t(context, AppStrings.values.proxyJump),
                              icon: const Icon(Icons.hub_outlined, size: 18),
                              selected: sshProxyType == SshProxyType.jump,
                              onTap: () {
                                setState(
                                  () => sshProxyType = SshProxyType.jump,
                                );
                              },
                            ),
                          ],
                        ),
                        if (sshProxyType == SshProxyType.socks5) ...[
                          _DialogField(
                            label: t(context, AppStrings.values.socksProxyHost),
                            controller: socksProxyHostController,
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: _DialogField(
                                  label: t(
                                    context,
                                    AppStrings.values.socksProxyPort,
                                  ),
                                  controller: socksProxyPortController,
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _DialogField(
                                  label: t(
                                    context,
                                    AppStrings.values.socksProxyUsername,
                                  ),
                                  controller: socksProxyUsernameController,
                                ),
                              ),
                            ],
                          ),
                          _DialogField(
                            label: t(
                              context,
                              AppStrings.values.socksProxyPassword,
                            ),
                            controller: socksProxyPasswordController,
                            obscureText: true,
                          ),
                        ],
                        if (sshProxyType == SshProxyType.jump) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Text(
                                t(context, AppStrings.values.proxyJumpChain),
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                              const Spacer(),
                              TextButton.icon(
                                icon: const Icon(Icons.add, size: 14),
                                label: Text(
                                  t(context, AppStrings.values.proxyJumpAdd),
                                  style: const TextStyle(fontSize: 11),
                                ),
                                onPressed: () {
                                  setState(() {
                                    jumpHostControllers.add(TextEditingController());
                                  });
                                },
                              ),
                            ],
                          ),
                          for (var i = 0; i < jumpHostControllers.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                children: [
                                  Text('$i.', style: const TextStyle(fontSize: 11, color: AppColors.grey400)),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: _DialogField(
                                      label: t(context, AppStrings.values.proxyJumpHostLabel),
                                      controller: jumpHostControllers[i],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle_outline, size: 16, color: AppColors.error),
                                    onPressed: () {
                                      setState(() {
                                        jumpHostControllers[i].dispose();
                                        jumpHostControllers.removeAt(i);
                                      });
                                    },
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                  ),
                                ],
                              ),
                            ),
                        ],
                        Row(
                          children: [
                            Expanded(
                              child: _DialogField(
                                label: t(
                                  context,
                                  AppStrings.values.sshKeepAliveSeconds,
                                ),
                                controller: keepAliveController,
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _DialogField(
                                label: t(
                                  context,
                                  AppStrings.values.sshConnectTimeoutSeconds,
                                ),
                                controller: connectTimeoutController,
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 6),
                    ] else if (connectionType == ConnectionType.telnet) ...[
                      _DialogField(
                        label: t(context, AppStrings.values.host),
                        controller: hostController,
                      ),
                      _DialogField(
                        label: t(context, AppStrings.values.telnetPort),
                        controller: portController,
                        keyboardType: TextInputType.number,
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
                                  selectLocalShell(shell);
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
                    _DialogField(
                      label: t(context, AppStrings.values.group),
                      controller: groupController,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              AppTextButton(
                onPressed: () => Navigator.pop(context),
                label: t(context, AppStrings.values.cancel),
                size: ButtonSize.small,
              ),
              PrimaryButton(
                iconWidget: buildNewSessionVscodeIcon(size: 16),
                onPressed: () {
                  final name = nameController.text.trim();
                  final hostValue = hostController.text.trim();
                  final user = userController.text.trim();
                  final serialPortPath = serialPortController.text.trim();
                  final port = int.tryParse(portController.text.trim()) ?? 22;
                  final serialBaudRate =
                      int.tryParse(serialBaudRateController.text.trim()) ??
                      9600;
                  final serialDataBits =
                      int.tryParse(serialDataBitsController.text.trim()) ?? 8;
                  final serialStopBits =
                      int.tryParse(serialStopBitsController.text.trim()) ?? 1;
                  final keepAliveSeconds =
                      int.tryParse(keepAliveController.text.trim()) ?? 10;
                  final connectTimeoutSeconds =
                      int.tryParse(connectTimeoutController.text.trim()) ?? 12;
                  final socksProxyPort =
                      int.tryParse(socksProxyPortController.text.trim()) ??
                      1080;
                  final fallbackName = switch (connectionType) {
                    ConnectionType.local => _localShellLabel(
                      context,
                      localShellType,
                    ),
                    ConnectionType.serial =>
                      serialPortPath.isEmpty
                          ? t(context, AppStrings.values.serialTerminal)
                          : serialPortPath,
                    ConnectionType.ssh || ConnectionType.telnet => hostValue,
                  };
                  final normalizedName = name.isEmpty ? fallbackName : name;
                  if (connectionType == ConnectionType.local &&
                      !localTerminalSupported) {
                    appState.setError(
                      t(
                        context,
                        AppStrings.values.localTerminalUnsupportedOnPlatform,
                      ),
                    );
                    return;
                  }
                  if (connectionType == ConnectionType.serial &&
                      !serialTerminalSupported) {
                    appState.setError(
                      t(context, AppStrings.values.serialUnsupportedOnPlatform),
                    );
                    return;
                  }
                  if (connectionType == ConnectionType.serial &&
                      serialPortPath.isEmpty) {
                    appState.setError(
                      t(context, AppStrings.values.serialPortRequired),
                    );
                    return;
                  }
                  if (connectionType == ConnectionType.ssh &&
                      (normalizedName.isEmpty ||
                          hostValue.isEmpty ||
                          user.isEmpty)) {
                    return;
                  }
                  if (connectionType == ConnectionType.ssh &&
                      sshProxyType == SshProxyType.socks5 &&
                      socksProxyHostController.text.trim().isEmpty) {
                    return;
                  }
                  if (connectionType == ConnectionType.ssh &&
                      sshProxyType == SshProxyType.jump &&
                      jumpHostControllers.every((c) => c.text.trim().isEmpty)) {
                    return;
                  }
                  final localUser =
                      Platform.environment['USERNAME'] ??
                      Platform.environment['USER'] ??
                      'local';
                  const serialUser = 'serial';
                  final entry = HostEntry(
                    id:
                        host?.id ??
                        'host-${DateTime.now().microsecondsSinceEpoch}',
                    name: normalizedName,
                    host: switch (connectionType) {
                      ConnectionType.local => 'local',
                      ConnectionType.serial => serialPortPath,
                      ConnectionType.ssh || ConnectionType.telnet => hostValue,
                    },
                    port: connectionType == ConnectionType.ssh
                        ? port
                        : (connectionType == ConnectionType.telnet
                            ? (int.tryParse(portController.text.trim()) ?? 23)
                            : 0),
                    username: switch (connectionType) {
                      ConnectionType.local => localUser,
                      ConnectionType.serial => serialUser,
                      ConnectionType.ssh || ConnectionType.telnet => user,
                    },
                    group: groupController.text.trim().isEmpty
                        ? t(context, AppStrings.values.defaultValue)
                        : groupController.text.trim(),
                    authType: connectionType == ConnectionType.ssh
                        ? authType
                        : AuthType.password,
                    connectionType: connectionType,
                    sshProxyType: connectionType == ConnectionType.ssh
                        ? sshProxyType
                        : SshProxyType.none,
                    socksProxyHost:
                        connectionType == ConnectionType.ssh &&
                            sshProxyType == SshProxyType.socks5
                        ? socksProxyHostController.text.trim()
                        : null,
                    socksProxyPort:
                        connectionType == ConnectionType.ssh &&
                            sshProxyType == SshProxyType.socks5
                        ? socksProxyPort.clamp(1, 65535).toInt()
                        : 1080,
                    socksProxyUsername:
                        connectionType == ConnectionType.ssh &&
                            sshProxyType == SshProxyType.socks5
                        ? socksProxyUsernameController.text.trim()
                        : null,
                    socksProxyPassword:
                        connectionType == ConnectionType.ssh &&
                            sshProxyType == SshProxyType.socks5
                        ? socksProxyPasswordController.text
                        : null,
                    jumpHosts:
                        connectionType == ConnectionType.ssh &&
                            sshProxyType == SshProxyType.jump
                        ? jumpHostControllers
                            .map((c) {
                              final raw = c.text.trim();
                              if (raw.isEmpty) return null;
                              return _parseJumpHostFromString(raw);
                            })
                            .whereType<JumpHostEntry>()
                            .toList(growable: false)
                        : const [],
                    useSshAgent: connectionType == ConnectionType.ssh
                        ? useSshAgent
                        : false,
                    privateKeyPassphrase:
                        connectionType == ConnectionType.ssh &&
                            authType == AuthType.key
                        ? keyPassphraseController.text
                        : null,
                    keepAliveSeconds: connectionType == ConnectionType.ssh
                        ? keepAliveSeconds.clamp(0, 600).toInt()
                        : 10,
                    connectTimeoutSeconds: connectionType == ConnectionType.ssh
                        ? connectTimeoutSeconds.clamp(3, 120).toInt()
                        : 12,
                    localShellType: connectionType == ConnectionType.local
                        ? localShellType
                        : LocalShellType.systemDefault,
                    serialPortPath: connectionType == ConnectionType.serial
                        ? serialPortPath
                        : null,
                    serialBaudRate: connectionType == ConnectionType.serial
                        ? serialBaudRate.clamp(1200, 4000000).toInt()
                        : 9600,
                    serialDataBits: connectionType == ConnectionType.serial
                        ? serialDataBits.clamp(5, 8).toInt()
                        : 8,
                    serialStopBits:
                        connectionType == ConnectionType.serial &&
                            serialStopBits == 2
                        ? 2
                        : 1,
                    serialParity: connectionType == ConnectionType.serial
                        ? serialParity
                        : SerialParity.none,
                    password:
                        connectionType == ConnectionType.ssh &&
                            authType == AuthType.password
                        ? passwordController.text
                        : null,
                    privateKeyPath:
                        connectionType == ConnectionType.ssh &&
                            authType == AuthType.key
                        ? keyPath
                        : null,
                    telnetPort: connectionType == ConnectionType.telnet
                        ? (int.tryParse(portController.text.trim()) ?? 23)
                        : 23,
                  );
                  if (isEdit) {
                    appState.updateHost(entry);
                  } else {
                    appState.addHost(entry);
                    unawaited(appState.connectToHost(entry));
                  }
                  Navigator.pop(context);
                },
                label: t(
                  context,
                  isEdit
                      ? AppStrings.values.save
                      : AppStrings.values.saveAndConnect,
                ),
                size: ButtonSize.medium,
              ),
            ],
          );
        },
      );
    },
  );
}

JumpHostEntry _parseJumpHostFromString(String raw) {
  var username = null as String?;
  var hostPart = raw;
  final atIdx = raw.indexOf('@');
  if (atIdx > 0) {
    username = raw.substring(0, atIdx).trim();
    hostPart = raw.substring(atIdx + 1).trim();
  }
  var host = hostPart;
  var port = 22;
  if (hostPart.startsWith('[')) {
    final close = hostPart.indexOf(']');
    if (close > 1) {
      host = hostPart.substring(1, close);
      final remain = hostPart.substring(close + 1).trim();
      if (remain.startsWith(':')) {
        port = int.tryParse(remain.substring(1).trim()) ?? 22;
      }
    }
  } else {
    final firstColon = hostPart.indexOf(':');
    final lastColon = hostPart.lastIndexOf(':');
    if (firstColon > 0 && firstColon == lastColon) {
      host = hostPart.substring(0, firstColon).trim();
      port = int.tryParse(hostPart.substring(firstColon + 1).trim()) ?? 22;
    }
  }
  return JumpHostEntry(
    host: host,
    port: port.clamp(1, 65535),
    username: username,
  );
}
