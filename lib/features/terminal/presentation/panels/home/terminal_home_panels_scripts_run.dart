part of '../terminal_home_panels.dart';

List<TreeViewNode<HostEntry>> _buildHostTree(
  List<HostEntry> hosts,
  Set<String> selectedIds, {
  String? locale,
}) {
  final byGroup = <String, List<HostEntry>>{};
  for (final host in hosts) {
    final ungroupedLabel = locale != null
        ? AppStrings.values.ungrouped.resolve(locale)
        : 'Ungrouped';
    final g = host.group.isEmpty ? ungroupedLabel : host.group;
    byGroup.putIfAbsent(g, () => []).add(host);
  }
  final rootKeys = byGroup.keys.toList()..sort();
  return rootKeys.map((groupName) {
    final groupHosts = byGroup[groupName]!..sort((a, b) => a.name.compareTo(b.name));
    return TreeViewNode<HostEntry>(
      key: 'group-$groupName',
      label: groupName,
      subtitle: '${groupHosts.length} host(s)',
      icon: Icons.folder,
      isExpanded: false,
      children: groupHosts.map((host) {
        return TreeViewNode<HostEntry>(
          key: host.id,
          label: host.name,
          value: host,
          subtitle: '${host.username}@${host.host}${host.port != 22 ? ':${host.port}' : ''}',
          icon: Icons.computer,
          isSelected: selectedIds.contains(host.id),
        );
      }).toList(),
    );
  }).toList();
}

Widget _buildHostTreeRow(
  BuildContext context,
  TerminalAppState appState,
  TreeViewNode<HostEntry> node,
  TreeViewItemState state,
  int depth,
) {
  final isGroup = !node.isLeaf;
  if (!isGroup && node.value != null) {
    final host = node.value!;
    return HostTreeRow(
      appState: appState,
      host: host,
      depth: depth,
      showCheckbox: true,
      showStatus: false,
      showPin: false,
      isSelected: state.isSelected,
      subtitle: node.subtitle,
      trailingLabel: _hostScriptStatusLabel(appState, node.key),
      onTap: state.onToggleSelect,
      onToggleSelect: state.onToggleSelect,
      lightTheme: true,
    );
  }
  if (isGroup) {
    final indent = (depth * 14).clamp(0, 56).toDouble();
    return Material(
      color: state.isExpanded ? const Color(0xFFF8F9FA) : Colors.transparent,
      borderRadius: BorderRadius.circular(5),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: state.onToggleExpand,
        child: Padding(
          padding: EdgeInsets.only(left: indent, right: 6),
          child: SizedBox(
            height: 26,
            child: Row(
              children: [
                Icon(
                  state.isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                  size: 15,
                  color: AppColors.grey400,
                ),
                const SizedBox(width: 2),
                Icon(
                  state.isExpanded ? Icons.folder_open_outlined : Icons.folder_outlined,
                  size: 14,
                  color: AppColors.grey400,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    node.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.terminalTreeFolderLight,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  node.subtitle ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.terminalTreeFolderCountLight,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  return InkWell(
    onTap: state.onToggleSelect,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Checkbox(
            value: state.isSelected,
            onChanged: (_) => state.onToggleSelect(),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
          Icon(
            node.icon ?? Icons.insert_drive_file,
            size: 16,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              node.label,
              style: AppTextStyles.bodySmall.copyWith(
                fontWeight: FontWeight.normal,
                color: AppColors.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (node.value != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                _hostScriptStatusLabel(appState, node.key),
                style: AppTextStyles.captionSmall.copyWith(color: AppColors.grey400),
              ),
            ),
        ],
      ),
    ),
  );
}

Future<void> _showRunScriptDialog(
  BuildContext context,
  TerminalAppState appState,
  ScriptEntry script,
) async {
  final hosts = appState.availableScriptHosts();
  final localShellOptions = _scriptLocalShellOptions();
  if (hosts.isEmpty && localShellOptions.isEmpty) {
    appState.setError(l(appState, AppStrings.values.noSessions));
    return;
  }
  final lastConfig = script.lastRunConfig;
  final hostIdSet = hosts.map((host) => host.id).toSet();
  final selectedHostIds = (lastConfig == null)
      ? <String>{}
      : lastConfig.hostIds.where(hostIdSet.contains).toSet();
  final selectedLocalShells = (lastConfig == null)
      ? <LocalShellType>{}
      : lastConfig.localShellTypes.where(localShellOptions.contains).toSet();
  var hostQuery = '';
  var notifyEnabled = lastConfig?.notifyEnabled ?? true;
  var silentExecution = lastConfig?.silentExecution ?? false;
  var failurePolicy =
      lastConfig?.failurePolicy ?? ScriptFailurePolicy.continueOnFailure;
  var retryPerHost = lastConfig?.retryPerHost ?? 1;
  var maxConcurrency = (lastConfig?.maxConcurrency ?? script.maxConcurrency)
      .clamp(1, 8);
  var expandedKeys = <String>{};
  final scriptVariableKeys = script.variables.keys.toList(growable: false)
    ..sort();
  final scriptTemplateArgs = <String, String>{
    ...script.variables,
    ...?lastConfig?.templateArgs,
  };
  final environmentOverrides = <String, String>{
    ...?lastConfig?.environmentOverrides,
  };
  final templateControllers = <String, TextEditingController>{};
  for (final key in scriptVariableKeys) {
    templateControllers[key] = TextEditingController(
      text: scriptTemplateArgs[key] ?? '',
    );
  }
  var showSelectionError = false;

  bool? confirmed;
  try {
    confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final normalizedQuery = hostQuery.trim().toLowerCase();
            final filteredHosts = hosts
                .where((host) {
                  if (normalizedQuery.isEmpty) {
                    return true;
                  }
                  final group = host.group.toLowerCase();
                  return host.name.toLowerCase().contains(normalizedQuery) ||
                      host.host.toLowerCase().contains(normalizedQuery) ||
                      host.username.toLowerCase().contains(normalizedQuery) ||
                      group.contains(normalizedQuery);
                })
                .toList(growable: false);

            return AlertDialog(
              title: Text(
                l(
                  appState,
                  AppStrings.values.runScriptVar,
                  params: {'name': script.name},
                ),
              ),
              content: SizedBox(
                width: 620,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l(appState, AppStrings.values.runTargetsSavedSessions),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (hosts.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            l(appState, AppStrings.values.noSessions),
                            style: AppTextStyles.secondarySmall,
                          ),
                        )
                      else ...[
                        TextField(
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: l(appState, AppStrings.values.search),
                            prefixIcon: const Icon(Icons.search, size: 18),
                            suffixIcon: hostQuery.isEmpty
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.close, size: 18),
                                    tooltip: l(
                                      appState,
                                      AppStrings.values.clear,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        hostQuery = '';
                                      });
                                    },
                                  ),
                          ),
                          onChanged: (value) {
                            setState(() {
                              hostQuery = value;
                            });
                          },
                        ),
                        const SizedBox(height: 6),
                        if (filteredHosts.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              l(appState, AppStrings.values.noMatchingSessions),
                              style: AppTextStyles.secondarySmall,
                            ),
                          )
                        else
                          TreeView<HostEntry>(
                            shrinkWrap: true,
                            roots: _buildHostTree(
                              filteredHosts,
                              selectedHostIds,
                              locale: appState.locale.languageCode,
                            ),
                            showCheckboxes: true,
                            expandedKeys: expandedKeys,
                            onToggleExpand: (key) {
                              setState(() {
                                if (expandedKeys.contains(key)) {
                                  expandedKeys.remove(key);
                                } else {
                                  expandedKeys.add(key);
                                }
                              });
                            },
                            onSelectionChanged: (selected) {
                              setState(() {
                                showSelectionError = false;
                                selectedHostIds
                                  ..clear()
                                  ..addAll(selected);
                              });
                            },
                            itemBuilder: (context, node, state, depth) {
                              return _buildHostTreeRow(
                                context,
                                appState,
                                node,
                                state,
                                depth,
                              );
                            },
                          ),
                      ],
                      const Divider(height: 22),
                      Text(
                        l(appState, AppStrings.values.runTargetsLocalSessions),
                        style: AppTextStyles.h6,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: localShellOptions
                            .map((shell) {
                              final selected = selectedLocalShells.contains(
                                shell,
                              );
                              return FilterChip(
                                selected: selected,
                                label: Text(
                                  _scriptLocalShellLabel(appState, shell),
                                ),
                                onSelected: (value) {
                                  setState(() {
                                    showSelectionError = false;
                                    if (value) {
                                      selectedLocalShells.add(shell);
                                    } else {
                                      selectedLocalShells.remove(shell);
                                    }
                                  });
                                },
                              );
                            })
                            .toList(growable: false),
                      ),
                      if (scriptVariableKeys.isNotEmpty) ...[
                        const Divider(height: 22),
                        Text(
                          l(appState, AppStrings.values.scriptTemplateArgs),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...scriptVariableKeys.map((key) {
                          final controller = templateControllers[key]!;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: TextField(
                              controller: controller,
                              decoration: InputDecoration(
                                isDense: true,
                                labelText: key,
                              ),
                              onChanged: (value) {
                                scriptTemplateArgs[key] = value;
                              },
                            ),
                          );
                        }),
                      ],
                      const Divider(height: 22),
                      Row(
                        children: [
                          Text(
                            l(appState, AppStrings.values.scriptMaxConcurrency),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(color: AppColors.border),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '$maxConcurrency',
                                  style: const TextStyle(fontSize: 13),
                                ),
                                const SizedBox(width: 4),
                                CompactMoreMenuButton(
                                  tooltip: l(
                                    appState,
                                    AppStrings.values.scriptMaxConcurrency,
                                  ),
                                  icon: Icons.arrow_drop_down,
                                  iconSize: 18,
                                  padding: 0,
                                  onTapDown: (details) => unawaited(() async {
                                    final value = await showCompactMenu<int>(
                                      context: context,
                                      position: details.globalPosition,
                                      items: List<PopupMenuEntry<int>>.generate(
                                        8,
                                        (index) => compactMenuItem(
                                          value: index + 1,
                                          label: '${index + 1}',
                                        ),
                                      ),
                                    );
                                    if (!context.mounted || value == null) {
                                      return;
                                    }
                                    setState(() {
                                      maxConcurrency = value;
                                    });
                                  }()),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          l(appState, AppStrings.values.runOptionNotify),
                        ),
                        value: notifyEnabled,
                        onChanged: (value) =>
                            setState(() => notifyEnabled = value),
                      ),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          l(appState, AppStrings.values.runOptionSilent),
                        ),
                        subtitle: Text(
                          silentExecution
                              ? l(
                                  appState,
                                  AppStrings.values.runSilentExecutionHint,
                                )
                              : l(
                                  appState,
                                  AppStrings.values.runInteractiveExecutionHint,
                                ),
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        value: silentExecution,
                        onChanged: (value) =>
                            setState(() => silentExecution = value),
                      ),
                      AppDropdownButtonFormField<ScriptFailurePolicy>(
                        value: failurePolicy,
                        label: l(appState, AppStrings.values.scriptFailurePolicy),
                        items: ScriptFailurePolicy.values
                            .map(
                              (policy) => DropdownMenuItem(
                                value: policy,
                                child: Text(
                                  _scriptFailurePolicyLabel(appState, policy),
                                ),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() => failurePolicy = value);
                        },
                      ),
                      if (failurePolicy == ScriptFailurePolicy.retryHost)
                        Row(
                          children: [
                            Text(
                              l(appState, AppStrings.values.scriptRetryPerHost),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(color: AppColors.border),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('$retryPerHost'),
                                  const SizedBox(width: 4),
                                  CompactMoreMenuButton(
                                    tooltip: l(
                                      appState,
                                      AppStrings.values.scriptRetryPerHost,
                                    ),
                                    icon: Icons.arrow_drop_down,
                                    iconSize: 18,
                                    padding: 0,
                                    onTapDown: (details) {
                                      unawaited(() async {
                                        final value = await showCompactMenu<int>(
                                          context: context,
                                          position: details.globalPosition,
                                          items:
                                              List<PopupMenuEntry<int>>.generate(
                                                6,
                                                (index) => compactMenuItem(
                                                  value: index + 1,
                                                  label: '${index + 1}',
                                                ),
                                              ),
                                        );
                                        if (!context.mounted || value == null) {
                                          return;
                                        }
                                        setState(() => retryPerHost = value);
                                      }());
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      if (showSelectionError)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            l(appState, AppStrings.values.runNoTargetSelected),
                            style: const TextStyle(
                              color: AppColors.error,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                AppTextButton(
                  onPressed: () {
                    for (final entry in templateControllers.entries) {
                      scriptTemplateArgs[entry.key] = entry.value.text;
                    }
                    appState.updateScriptLastRunConfig(
                      scriptId: script.id,
                      hostIds: selectedHostIds.toList(growable: false),
                      localShellTypes: selectedLocalShells.toList(growable: false),
                      notifyEnabled: notifyEnabled,
                      silentExecution: silentExecution,
                      failurePolicy: failurePolicy,
                      retryPerHost: retryPerHost,
                      templateArgs: scriptTemplateArgs,
                      environmentOverrides: environmentOverrides,
                      maxConcurrency: maxConcurrency,
                    );
                    appState.scheduleStateSave();
                    if (context.mounted) Navigator.pop(context, false);
                  },
                  label: l(appState, AppStrings.values.saveRunConfig),
                ),
                SecondaryButton(
                  onPressed: () => Navigator.pop(context, false),
                  label: t(context, AppStrings.values.cancel),
                  size: ButtonSize.medium,
                ),
                PrimaryButton(
                  onPressed: () {
                    if (selectedHostIds.isEmpty &&
                        selectedLocalShells.isEmpty) {
                      setState(() => showSelectionError = true);
                      return;
                    }
                    for (final entry in templateControllers.entries) {
                      scriptTemplateArgs[entry.key] = entry.value.text;
                    }
                    Navigator.pop(context, true);
                  },
                  label: l(appState, AppStrings.values.run),
                  size: ButtonSize.medium,
                ),
              ],
            );
          },
        );
      },
    );
  } finally {
    for (final controller in templateControllers.values) {
      controller.dispose();
    }
  }
  if (confirmed != true) return;
  appState.updateScriptLastRunConfig(
    scriptId: script.id,
    hostIds: selectedHostIds.toList(growable: false),
    localShellTypes: selectedLocalShells.toList(growable: false),
    notifyEnabled: notifyEnabled,
    silentExecution: silentExecution,
    failurePolicy: failurePolicy,
    retryPerHost: retryPerHost,
    templateArgs: scriptTemplateArgs,
    environmentOverrides: environmentOverrides,
    maxConcurrency: maxConcurrency,
  );

  // Fire-and-forget execution
  unawaited(appState.runScriptOnTargets(
    scriptId: script.id,
    hostIds: selectedHostIds.toList(growable: false),
    localShellTypes: selectedLocalShells.toList(growable: false),
    silentExecution: silentExecution,
    notifyEnabled: notifyEnabled,
    failurePolicy: failurePolicy,
    retryPerHost: retryPerHost,
    templateArgs: scriptTemplateArgs,
    environmentOverrides: environmentOverrides,
    maxConcurrency: maxConcurrency,
  ));

  // 标记显示监控视图，下次打开弹窗时自动显示
  appState.showScriptMonitorInline = true;
  appState.notifyState();
}

Future<void> showRunScriptsBatchDialogWithSelection(
  BuildContext context,
  TerminalAppState appState,
  List<String> presetScriptIds,
) async {
  await _showRunScriptsBatchDialog(
    context,
    appState,
    presetScriptIds: presetScriptIds,
    lockScriptSelection: true,
  );
}

Future<void> _showRunScriptsBatchDialog(
  BuildContext context,
  TerminalAppState appState, {
  List<String>? presetScriptIds,
  bool lockScriptSelection = false,
}) async {
  final scripts = List<ScriptEntry>.from(appState.scripts, growable: false)
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  if (scripts.isEmpty) {
    appState.setError(l(appState, AppStrings.values.noData));
    return;
  }
  final hosts = appState.availableScriptHosts();
  final localShellOptions = _scriptLocalShellOptions();
  if (hosts.isEmpty && localShellOptions.isEmpty) {
    appState.setError(l(appState, AppStrings.values.noSessions));
    return;
  }

  final hostIdSet = hosts.map((host) => host.id).toSet();
  ScriptLastRunConfig? seedConfig;
  for (final script in List<ScriptEntry>.from(
    appState.scripts,
    growable: false,
  )..sort((a, b) => b.updatedAt.compareTo(a.updatedAt))) {
    if (script.lastRunConfig != null) {
      seedConfig = script.lastRunConfig;
      break;
    }
  }

  final selectedScriptIds = <String>{};
  if (presetScriptIds != null && presetScriptIds.isNotEmpty) {
    final valid = presetScriptIds
        .where((id) => scripts.any((script) => script.id == id))
        .toList(growable: false);
    selectedScriptIds.addAll(valid);
  }
  final selectedHostIds = (seedConfig == null)
      ? <String>{}
      : seedConfig.hostIds.where(hostIdSet.contains).toSet();
  final selectedLocalShells = (seedConfig == null)
      ? <LocalShellType>{}
      : seedConfig.localShellTypes.where(localShellOptions.contains).toSet();
  var scriptQuery = '';
  var hostQuery = '';
  var notifyEnabled = seedConfig?.notifyEnabled ?? true;
  var silentExecution = seedConfig?.silentExecution ?? false;
  var failurePolicy =
      seedConfig?.failurePolicy ?? ScriptFailurePolicy.continueOnFailure;
  var retryPerHost = seedConfig?.retryPerHost ?? 1;
  var maxConcurrency = (seedConfig?.maxConcurrency ?? 1).clamp(1, 8);
  var expandedKeys = <String>{};
  var showScriptSelectionError = false;
  var showTargetSelectionError = false;

  bool? confirmed;
  confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          final normalizedScriptQuery = scriptQuery.trim().toLowerCase();
          final filteredScripts = scripts
              .where((script) {
                if (normalizedScriptQuery.isEmpty) {
                  return true;
                }
                return script.name.toLowerCase().contains(
                  normalizedScriptQuery,
                );
              })
              .toList(growable: false);
          final normalizedHostQuery = hostQuery.trim().toLowerCase();
          final filteredHosts = hosts
              .where((host) {
                if (normalizedHostQuery.isEmpty) {
                  return true;
                }
                final group = host.group.toLowerCase();
                return host.name.toLowerCase().contains(normalizedHostQuery) ||
                    host.host.toLowerCase().contains(normalizedHostQuery) ||
                    host.username.toLowerCase().contains(normalizedHostQuery) ||
                    group.contains(normalizedHostQuery);
              })
              .toList(growable: false);
          final allScriptsSelected = selectedScriptIds.length == scripts.length;

          return AlertDialog(
            title: Text(l(appState, AppStrings.values.batchRunScripts)),
            content: SizedBox(
              width: 680,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!lockScriptSelection) ...[
                      Row(
                        children: [
                          Text(
                            l(appState, AppStrings.values.scripts),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          AppTextButton(
                            onPressed: () {
                              setState(() {
                                if (allScriptsSelected) {
                                  selectedScriptIds.clear();
                                } else {
                                  selectedScriptIds
                                    ..clear()
                                    ..addAll(scripts.map((item) => item.id));
                                }
                                showScriptSelectionError = false;
                              });
                            },
                            label: allScriptsSelected
                                ? l(appState, AppStrings.values.clearAll)
                                : l(appState, AppStrings.values.selectAll),
                          ),
                        ],
                      ),
                      TextField(
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: l(appState, AppStrings.values.searchScripts),
                          prefixIcon: const Icon(Icons.search, size: 18),
                          suffixIcon: scriptQuery.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.close, size: 18),
                                  onPressed: () {
                                    setState(() {
                                      scriptQuery = '';
                                    });
                                  },
                                ),
                        ),
                        onChanged: (value) {
                          setState(() {
                            scriptQuery = value;
                          });
                        },
                      ),
                      const SizedBox(height: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 210),
                        child: filteredScripts.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Text(
                                  l(appState, AppStrings.values.noData),
                            style: AppTextStyles.secondarySmall,
                                ),
                              )
                            : ListView(
                                shrinkWrap: true,
                                children: filteredScripts
                                    .map(
                                      (script) => CheckboxListTile(
                                        dense: true,
                                        contentPadding: EdgeInsets.zero,
                                        value: selectedScriptIds.contains(
                                          script.id,
                                        ),
                                        onChanged: (value) {
                                          setState(() {
                                            if (value == true) {
                                              selectedScriptIds.add(script.id);
                                            } else {
                                              selectedScriptIds.remove(
                                                script.id,
                                              );
                                            }
                                            showScriptSelectionError = false;
                                          });
                                        },
                                        title: Text(
                                          script.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        subtitle: Text(
                                          l(
                                            appState,
                                            AppStrings
                                                .values
                                                .scriptCommandsCountVar,
                                            params: {
                                              'count':
                                                  '${script.commands.length}',
                                            },
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(growable: false),
                              ),
                      ),
                      if (showScriptSelectionError)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            l(
                              appState,
                              AppStrings.values.selectAtLeastOneScript,
                            ),
                            style: const TextStyle(
                              color: AppColors.error,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ] else ...[
                      Text(
                        l(
                          appState,
                          AppStrings.values.selectedCountVar,
                          params: {'count': '${selectedScriptIds.length}'},
                        ),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    const Divider(height: 22),
                    Text(
                      l(appState, AppStrings.values.runTargetsSavedSessions),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (hosts.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          l(appState, AppStrings.values.noSessions),
                          style: AppTextStyles.secondarySmall,
                        ),
                      )
                    else ...[
                      TextField(
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: l(appState, AppStrings.values.search),
                          prefixIcon: const Icon(Icons.search, size: 18),
                          suffixIcon: hostQuery.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.close, size: 18),
                                  onPressed: () {
                                    setState(() {
                                      hostQuery = '';
                                    });
                                  },
                                ),
                        ),
                        onChanged: (value) {
                          setState(() {
                            hostQuery = value;
                          });
                        },
                      ),
                      const SizedBox(height: 6),
                      if (filteredHosts.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            l(appState, AppStrings.values.noMatchingSessions),
                            style: AppTextStyles.secondarySmall,
                          ),
                        )
                      else
                        TreeView<HostEntry>(
                          shrinkWrap: true,
                          roots: _buildHostTree(
                            filteredHosts,
                            selectedHostIds,
                            locale: appState.locale.languageCode,
                          ),
                          showCheckboxes: true,
                          expandedKeys: expandedKeys,
                          onToggleExpand: (key) {
                            setState(() {
                              if (expandedKeys.contains(key)) {
                                expandedKeys.remove(key);
                              } else {
                                expandedKeys.add(key);
                              }
                            });
                          },
                          onSelectionChanged: (selected) {
                            setState(() {
                              showTargetSelectionError = false;
                              selectedHostIds
                                ..clear()
                                ..addAll(selected);
                            });
                          },
                          itemBuilder: (context, node, state, depth) {
                            return _buildHostTreeRow(
                              context,
                              appState,
                              node,
                              state,
                              depth,
                            );
                          },
                        ),
                    ],
                    const Divider(height: 22),
                    Text(
                      l(appState, AppStrings.values.runTargetsLocalSessions),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: localShellOptions
                          .map((shell) {
                            final selected = selectedLocalShells.contains(
                              shell,
                            );
                            return FilterChip(
                              selected: selected,
                              label: Text(
                                _scriptLocalShellLabel(appState, shell),
                              ),
                              onSelected: (value) {
                                setState(() {
                                  if (value) {
                                    selectedLocalShells.add(shell);
                                  } else {
                                    selectedLocalShells.remove(shell);
                                  }
                                  showTargetSelectionError = false;
                                });
                              },
                            );
                          })
                          .toList(growable: false),
                    ),
                    const Divider(height: 22),
                    Row(
                      children: [
                        Text(
                          l(appState, AppStrings.values.scriptMaxConcurrency),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '$maxConcurrency',
                                style: const TextStyle(fontSize: 13),
                              ),
                              const SizedBox(width: 4),
                              CompactMoreMenuButton(
                                tooltip: l(
                                  appState,
                                  AppStrings.values.scriptMaxConcurrency,
                                ),
                                icon: Icons.arrow_drop_down,
                                iconSize: 18,
                                padding: 0,
                                onTapDown: (details) => unawaited(() async {
                                  final value = await showCompactMenu<int>(
                                    context: context,
                                    position: details.globalPosition,
                                    items: List<PopupMenuEntry<int>>.generate(
                                      8,
                                      (index) => compactMenuItem(
                                        value: index + 1,
                                        label: '${index + 1}',
                                      ),
                                    ),
                                  );
                                  if (!context.mounted || value == null) {
                                    return;
                                  }
                                  setState(() => maxConcurrency = value);
                                }()),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        l(appState, AppStrings.values.runOptionNotify),
                      ),
                      value: notifyEnabled,
                      onChanged: (value) =>
                          setState(() => notifyEnabled = value),
                    ),
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        l(appState, AppStrings.values.runOptionSilent),
                      ),
                      subtitle: Text(
                        silentExecution
                            ? l(
                                appState,
                                AppStrings.values.runSilentExecutionHint,
                              )
                            : l(
                                appState,
                                AppStrings.values.runInteractiveExecutionHint,
                              ),
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                      value: silentExecution,
                      onChanged: (value) =>
                          setState(() => silentExecution = value),
                    ),
                    AppDropdownButtonFormField<ScriptFailurePolicy>(
                      value: failurePolicy,
                      label: l(appState, AppStrings.values.scriptFailurePolicy),
                      items: ScriptFailurePolicy.values
                          .map(
                            (policy) => DropdownMenuItem(
                              value: policy,
                              child: Text(
                                _scriptFailurePolicyLabel(appState, policy),
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() => failurePolicy = value);
                      },
                    ),
                    if (failurePolicy == ScriptFailurePolicy.retryHost)
                      Row(
                        children: [
                          Text(
                            l(appState, AppStrings.values.scriptRetryPerHost),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(color: AppColors.border),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('$retryPerHost'),
                                const SizedBox(width: 4),
                                CompactMoreMenuButton(
                                  tooltip: l(
                                    appState,
                                    AppStrings.values.scriptRetryPerHost,
                                  ),
                                  icon: Icons.arrow_drop_down,
                                  iconSize: 18,
                                  padding: 0,
                                  onTapDown: (details) => unawaited(() async {
                                    final value = await showCompactMenu<int>(
                                      context: context,
                                      position: details.globalPosition,
                                      items: List<PopupMenuEntry<int>>.generate(
                                        6,
                                        (index) => compactMenuItem(
                                          value: index + 1,
                                          label: '${index + 1}',
                                        ),
                                      ),
                                    );
                                    if (!context.mounted || value == null) {
                                      return;
                                    }
                                    setState(() => retryPerHost = value);
                                  }()),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    if (showTargetSelectionError)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          l(appState, AppStrings.values.runNoTargetSelected),
                          style: const TextStyle(
                            color: AppColors.error,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              AppTextButton(
                onPressed: () {
                  setState(() {
                    selectedScriptIds.clear();
                    selectedHostIds.clear();
                    selectedLocalShells.clear();
                    scriptQuery = '';
                    hostQuery = '';
                    notifyEnabled = true;
                    silentExecution = false;
                    failurePolicy = ScriptFailurePolicy.continueOnFailure;
                    retryPerHost = 1;
                    maxConcurrency = 1;
                    showScriptSelectionError = false;
                    showTargetSelectionError = false;
                  });
                },
                label: l(appState, AppStrings.values.reset),
                size: ButtonSize.small,
              ),
              SecondaryButton(
                onPressed: () => Navigator.pop(context, false),
                label: t(context, AppStrings.values.cancel),
                size: ButtonSize.small,
              ),
              const SizedBox(width: AppSpacing.sm),
              PrimaryButton(
                onPressed: () {
                  var hasError = false;
                  if (selectedScriptIds.isEmpty) {
                    showScriptSelectionError = true;
                    hasError = true;
                  }
                  if (selectedHostIds.isEmpty && selectedLocalShells.isEmpty) {
                    showTargetSelectionError = true;
                    hasError = true;
                  }
                  if (hasError) {
                    setState(() {});
                    return;
                  }
                  Navigator.pop(context, true);
                },
                label: l(appState, AppStrings.values.run),
              ),
            ],
          );
        },
      );
    },
  );

  if (confirmed != true) {
    return;
  }

  final selectedScripts = scripts
      .where((script) => selectedScriptIds.contains(script.id))
      .toList(growable: false);
  if (selectedScripts.isEmpty) {
    return;
  }

  var totalAttempted = 0;
  var totalExecuted = 0;
  var totalFailed = 0;
  final batchFutures = <Future<void>>[];
  for (final script in selectedScripts) {
    final scriptLastConfig = script.lastRunConfig;
    final templateArgs = <String, String>{
      ...script.variables,
      ...?scriptLastConfig?.templateArgs,
    };
    final scriptEnvOverrides = <String, String>{
      ...?scriptLastConfig?.environmentOverrides,
    };
    appState.updateScriptLastRunConfig(
      scriptId: script.id,
      hostIds: selectedHostIds.toList(growable: false),
      localShellTypes: selectedLocalShells.toList(growable: false),
      notifyEnabled: notifyEnabled,
      silentExecution: silentExecution,
      failurePolicy: failurePolicy,
      retryPerHost: retryPerHost,
      templateArgs: templateArgs,
      environmentOverrides: scriptEnvOverrides,
      maxConcurrency: maxConcurrency,
    );
    batchFutures.add(
      appState.runScriptOnTargets(
        scriptId: script.id,
        hostIds: selectedHostIds.toList(growable: false),
        localShellTypes: selectedLocalShells.toList(growable: false),
        silentExecution: silentExecution,
        notifyEnabled: false,
        failurePolicy: failurePolicy,
        retryPerHost: retryPerHost,
        templateArgs: templateArgs,
        environmentOverrides: scriptEnvOverrides,
        maxConcurrency: maxConcurrency,
      ).then((result) {
        totalAttempted += result.attempted;
        totalExecuted += result.executed;
        totalFailed += result.failed;
      }),
    );
  }
  for (var i = 0; i < batchFutures.length; i += _maxBatchConcurrency) {
    final batch = batchFutures.sublist(
      i,
      (i + _maxBatchConcurrency).clamp(0, batchFutures.length),
    );
    await Future.wait(batch);
  }

  if (!context.mounted || !notifyEnabled) {
    return;
  }
  if (totalExecuted <= 0 && totalFailed <= 0) {
    return;
  }
  final summary = l(
    appState,
    AppStrings.values.runSummaryVarVar,
    params: {'success': '$totalExecuted', 'failed': '$totalFailed'},
  );
  final detail = l(
    appState,
    AppStrings.values.runBatchSummaryVarVarVar,
    params: {
      'summary': summary,
      'scripts': '${selectedScripts.length}',
      'targets': '$totalAttempted',
    },
  );
  showBannerAndLog(
    appState,
    BannerData(
      id: 'script-batch-run-${DateTime.now().microsecondsSinceEpoch}',
      type: totalFailed > 0 ? BannerType.error : BannerType.success,
      title: totalFailed > 0
          ? l(appState, AppStrings.values.failed)
          : l(appState, AppStrings.values.done),
      message: detail,
    ),
  );
}

